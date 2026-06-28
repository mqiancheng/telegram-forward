import asyncio
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session

try:
    from .database import SessionLocal, init_db, get_db
    from .models import Account, ForwardConfig, Project, TaskLog
    from .schemas import (
        AccountCreate, AccountUpdate, AccountResponse,
        LoginCodeRequest, LoginVerifyRequest,
        ForwardConfigRequest, ForwardConfigResponse,
        ProjectCreate, ProjectUpdate, ProjectAssignAccounts, ProjectResponse,
        TaskLogResponse, DashboardResponse,
    )
    from .client_manager import client_manager
    from .scheduler_service import scheduler_service
    from .config import PORT, HOST
except ImportError:
    from database import SessionLocal, init_db, get_db
    from models import Account, ForwardConfig, Project, TaskLog
    from schemas import (
        AccountCreate, AccountUpdate, AccountResponse,
        LoginCodeRequest, LoginVerifyRequest,
        ForwardConfigRequest, ForwardConfigResponse,
        ProjectCreate, ProjectUpdate, ProjectAssignAccounts, ProjectResponse,
        TaskLogResponse, DashboardResponse,
    )
    from client_manager import client_manager
    from scheduler_service import scheduler_service
    from config import PORT, HOST

# ==================== 日志 ====================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("tg_forward")

# ==================== FastAPI 生命周期 ====================

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Telegram Forward Tool...")
    init_db()
    await client_manager.reconnect_all()
    await scheduler_service.start()
    yield
    logger.info("Shutting down...")
    await scheduler_service.stop()
    await client_manager.stop_all()

app = FastAPI(title="Telegram 消息转发工具", lifespan=lifespan)

# 静态文件
static_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "static")
os.makedirs(static_dir, exist_ok=True)
app.mount("/static", StaticFiles(directory=static_dir), name="static")

# ==================== 辅助函数 ====================

def mask_str(s: str, show: int = 4) -> str:
    """对敏感字符串进行掩码处理"""
    if not s:
        return ""
    if len(s) <= show:
        return "*" * len(s)
    return s[:show] + "*" * (len(s) - show * 2) + s[-show:]


def account_to_dict(acc: Account) -> dict:
    d = {c.name: getattr(acc, c.name) for c in acc.__table__.columns}
    d["created_at"] = d["created_at"].isoformat() if d["created_at"] else ""
    d["updated_at"] = d["updated_at"].isoformat() if d["updated_at"] else ""
    return d


def project_to_dict(p: Project) -> dict:
    d = {c.name: getattr(p, c.name) for c in p.__table__.columns}
    d["created_at"] = d["created_at"].isoformat() if d["created_at"] else ""
    d["updated_at"] = d["updated_at"].isoformat() if d["updated_at"] else ""
    d["account_ids"] = [a.id for a in p.accounts]
    # 兼容旧数据：如果 target_type 为空，默认 bot
    if not d.get("target_type"):
        d["target_type"] = "bot"
    return d


# ==================== API 路由 ====================

# -- 仪表盘 --

@app.get("/api/dashboard", response_model=DashboardResponse)
def api_dashboard(db: Session = Depends(get_db)):
    accounts = db.query(Account).all()
    projects = db.query(Project).all()
    fwd = db.query(ForwardConfig).first()
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    today_logs = db.query(TaskLog).filter(TaskLog.created_at >= today).count()

    online = sum(1 for a in accounts if client_manager.is_connected(a.id))
    return DashboardResponse(
        account_count=len(accounts),
        account_online=online,
        project_count=len(projects),
        project_enabled=sum(1 for p in projects if p.is_enabled),
        today_logs=today_logs,
        forward_enabled=fwd.is_enabled if fwd else False,
    )


# -- 账号管理 --

@app.get("/api/accounts")
def api_list_accounts(db: Session = Depends(get_db)):
    accounts = db.query(Account).order_by(Account.created_at.desc()).all()
    result = []
    for a in accounts:
        d = account_to_dict(a)
        d["is_connected"] = client_manager.is_connected(a.id)
        result.append(d)
    return result


@app.post("/api/accounts")
def api_create_account(data: AccountCreate, db: Session = Depends(get_db)):
    session_name = f"session_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    acc = Account(
        name=data.name,
        api_id=data.api_id,
        api_hash=data.api_hash,
        session_name=session_name,
    )
    db.add(acc)
    db.commit()
    db.refresh(acc)
    return {"id": acc.id, "message": "账号已创建"}


@app.put("/api/accounts/{account_id}")
def api_update_account(account_id: int, data: AccountUpdate, db: Session = Depends(get_db)):
    acc = db.query(Account).get(account_id)
    if not acc:
        raise HTTPException(404, "账号不存在")
    if data.name is not None:
        acc.name = data.name
    if data.api_id is not None:
        acc.api_id = data.api_id
    if data.api_hash is not None:
        acc.api_hash = data.api_hash
    if data.is_active is not None:
        acc.is_active = data.is_active
    db.commit()
    return {"message": "账号已更新"}


@app.delete("/api/accounts/{account_id}")
async def api_delete_account(account_id: int, db: Session = Depends(get_db)):
    acc = db.query(Account).get(account_id)
    if not acc:
        raise HTTPException(404, "账号不存在")
    await client_manager.stop_client(account_id)
    session_file = f"data/sessions/{acc.session_name}.session"
    if os.path.exists(session_file):
        os.remove(session_file)
    session_journal = session_file + "-journal"
    if os.path.exists(session_journal):
        os.remove(session_journal)
    db.delete(acc)
    db.commit()
    return {"message": "账号已删除"}


@app.post("/api/accounts/{account_id}/send-code")
async def api_send_code(account_id: int, data: LoginCodeRequest, db: Session = Depends(get_db)):
    acc = db.query(Account).get(account_id)
    if not acc:
        raise HTTPException(404, "账号不存在")

    if not client_manager.get_client(account_id):
        await client_manager.start_client(acc)

    result = await client_manager.send_login_code(account_id, data.phone)
    if result["success"]:
        acc.phone = data.phone
        db.commit()
    return result


@app.post("/api/accounts/{account_id}/verify")
async def api_verify_code(account_id: int, data: LoginVerifyRequest, db: Session = Depends(get_db)):
    acc = db.query(Account).get(account_id)
    if not acc:
        raise HTTPException(404, "账号不存在")
    return await client_manager.verify_login_code(
        account_id, data.phone, data.code, data.password
    )


@app.post("/api/accounts/{account_id}/logout")
async def api_logout_account(account_id: int, db: Session = Depends(get_db)):
    acc = db.query(Account).get(account_id)
    if not acc:
        raise HTTPException(404, "账号不存在")
    await client_manager.logout_account(account_id)
    return {"message": "已登出"}


@app.post("/api/accounts/{account_id}/connect")
async def api_connect_account(account_id: int, db: Session = Depends(get_db)):
    """手动重连已登录的账号"""
    acc = db.query(Account).get(account_id)
    if not acc:
        raise HTTPException(404, "账号不存在")
    if not acc.is_logged_in:
        raise HTTPException(400, "账号未登录，请先登录后再连接")
    try:
        if acc.id in client_manager.clients:
            await client_manager.stop_client(acc.id)
        ok = await client_manager.start_client(acc)
        if ok:
            return {"success": True, "message": f"账号 {acc.name} 已连接"}
        else:
            raise HTTPException(500, "连接失败：可能是 session 过期、API 凭据错误或网络问题，请尝试重新登录")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"连接失败: {str(e)}")


# -- 转发配置 --

@app.get("/api/forward-config")
def api_get_forward_config(db: Session = Depends(get_db)):
    fwd = db.query(ForwardConfig).first()
    if not fwd:
        fwd = ForwardConfig(target_chat_id="", allowed_senders="[]", is_enabled=False)
        db.add(fwd)
        db.commit()
        db.refresh(fwd)
    return {
        "id": fwd.id,
        "target_chat_id": fwd.target_chat_id,
        "allowed_senders": fwd.allowed_senders,
        "is_enabled": fwd.is_enabled,
        "created_at": fwd.created_at.isoformat() if fwd.created_at else "",
        "updated_at": fwd.updated_at.isoformat() if fwd.updated_at else "",
    }


@app.put("/api/forward-config")
async def api_update_forward_config(data: ForwardConfigRequest, db: Session = Depends(get_db)):
    fwd = db.query(ForwardConfig).first()
    if not fwd:
        fwd = ForwardConfig()
        db.add(fwd)
    fwd.target_chat_id = data.target_chat_id
    fwd.allowed_senders = data.allowed_senders
    fwd.is_enabled = data.is_enabled
    db.commit()
    await client_manager.refresh_forward_handlers()
    return {"message": "转发配置已更新"}


# -- 项目管理 --

@app.get("/api/projects")
def api_list_projects(db: Session = Depends(get_db)):
    projects = db.query(Project).order_by(Project.created_at.desc()).all()
    return [project_to_dict(p) for p in projects]


@app.post("/api/projects")
async def api_create_project(data: ProjectCreate, db: Session = Depends(get_db)):
    p = Project(
        name=data.name,
        target_bot=data.target_bot,
        message=data.message,
        schedule_type=data.schedule_type,
        schedule_rule=data.schedule_rule,
        target_type=data.target_type,
    )
    db.add(p)
    db.commit()
    db.refresh(p)
    scheduler_service.add_job(p)
    return {"id": p.id, "message": "项目已创建"}


@app.put("/api/projects/{project_id}")
async def api_update_project(project_id: int, data: ProjectUpdate, db: Session = Depends(get_db)):
    p = db.query(Project).get(project_id)
    if not p:
        raise HTTPException(404, "项目不存在")
    for field in ["name", "target_type", "target_bot", "message", "schedule_type", "schedule_rule", "is_enabled"]:
        val = getattr(data, field, None)
        if val is not None:
            setattr(p, field, val)
    db.commit()
    db.refresh(p)
    scheduler_service.add_job(p)
    return {"message": "项目已更新"}


@app.delete("/api/projects/{project_id}")
def api_delete_project(project_id: int, db: Session = Depends(get_db)):
    p = db.query(Project).get(project_id)
    if not p:
        raise HTTPException(404, "项目不存在")
    scheduler_service.remove_job(project_id)
    db.delete(p)
    db.commit()
    return {"message": "项目已删除"}


@app.put("/api/projects/{project_id}/accounts")
def api_assign_accounts(project_id: int, data: ProjectAssignAccounts, db: Session = Depends(get_db)):
    p = db.query(Project).get(project_id)
    if not p:
        raise HTTPException(404, "项目不存在")
    accounts = db.query(Account).filter(Account.id.in_(data.account_ids)).all()
    p.accounts = accounts
    db.commit()
    return {"message": f"已为项目「{p.name}」分配 {len(accounts)} 个账号"}


@app.post("/api/projects/{project_id}/execute")
async def api_execute_project_now(project_id: int):
    """立即手动执行一次项目任务"""
    results = await scheduler_service.execute_now(project_id)
    return {"results": results}


# -- 日志 --

@app.get("/api/logs")
def api_list_logs(
    page: int = Query(1, ge=1),
    size: int = Query(50, ge=1, le=500),
    project_id: int = Query(None),
    status: str = Query(None),
    db: Session = Depends(get_db),
):
    q = db.query(TaskLog)
    if project_id:
        q = q.filter(TaskLog.project_id == project_id)
    if status:
        q = q.filter(TaskLog.status == status)
    total = q.count()
    logs = q.order_by(TaskLog.created_at.desc()).offset((page - 1) * size).limit(size).all()
    items = []
    for l in logs:
        items.append({
            "id": l.id,
            "project_id": l.project_id,
            "account_id": l.account_id,
            "account_name": l.account_name or "",
            "project_name": l.project_name or "",
            "status": l.status,
            "detail": l.detail or "",
            "created_at": l.created_at.isoformat() if l.created_at else "",
        })
    return {"items": items, "total": total, "page": page, "size": size}


@app.delete("/api/logs")
def api_clear_logs(db: Session = Depends(get_db)):
    db.query(TaskLog).delete()
    db.commit()
    return {"message": "日志已清空"}


# ==================== 前端页面 ====================

@app.get("/", response_class=HTMLResponse)
async def index():
    return HTMLResponse(FRONTEND_HTML)


FRONTEND_HTML = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Telegram 消息转发工具</title>
<script src="/static/vue.global.prod.js"></script>
<script src="/static/axios.min.js"></script>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f5; }
.container { max-width: 1200px; margin: 0 auto; padding: 20px; }
.header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 10px; margin-bottom: 20px; }
.header h1 { font-size: 24px; margin-bottom: 5px; }
.header p { opacity: 0.8; font-size: 14px; }
.card { background: white; border-radius: 10px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
.card-title { font-size: 18px; font-weight: 600; margin-bottom: 15px; color: #333; border-bottom: 2px solid #667eea; padding-bottom: 10px; }
.form-group { margin-bottom: 15px; }
.form-group label { display: block; margin-bottom: 5px; color: #666; font-size: 14px; }
.form-group input[type="text"], .form-group input[type="number"], .form-group input[type="password"], .form-group select {
    width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 5px; font-size: 14px;
}
.btn { padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; font-size: 14px; transition: all 0.3s; }
.btn-primary { background: #667eea; color: white; }
.btn-primary:hover { background: #5568d3; }
.btn-success { background: #48bb78; color: white; }
.btn-success:hover { background: #38a169; }
.btn-danger { background: #f56565; color: white; }
.btn-danger:hover { background: #e53e3e; }
.btn-outline { background: white; color: #667eea; border: 1px solid #667eea; }
.btn-outline:hover { background: #f0f0ff; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }
.btn-group { display: flex; gap: 10px; flex-wrap: wrap; }
.btn-sm { padding: 5px 12px; font-size: 12px; }
.nav-tabs { display: flex; background: white; border-radius: 10px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
.nav-tab { flex: 1; padding: 15px 20px; text-align: center; cursor: pointer; transition: all 0.3s; font-weight: 500; color: #666; border-bottom: 3px solid transparent; }
.nav-tab:hover { background: #f8f9fa; }
.nav-tab.active { color: #667eea; border-bottom-color: #667eea; background: #f8f9fa; }
.stats-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 15px; margin-bottom: 15px; }
.stat-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 15px; border-radius: 10px; text-align: center; }
.stat-card.green { background: linear-gradient(135deg, #48bb78 0%, #38a169 100%); }
.stat-card.orange { background: linear-gradient(135deg, #ed8936 0%, #dd6b20 100%); }
.stat-card.red { background: linear-gradient(135deg, #f56565 0%, #e53e3e 100%); }
.stat-card.gray { background: linear-gradient(135deg, #a0aec0 0%, #718096 100%); }
.stat-value { font-size: 28px; font-weight: 600; }
.stat-label { font-size: 12px; opacity: 0.9; margin-top: 5px; }
table { width: 100%; border-collapse: collapse; }
th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid #eee; font-size: 13px; }
th { font-weight: 600; color: #666; font-size: 12px; background: #f8f9fa; }
tr:hover td { background: #f0f0ff; }
.badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 12px; }
.badge-success { background: rgba(72, 187, 120, 0.15); color: #38a169; }
.badge-danger { background: rgba(245, 101, 101, 0.15); color: #e53e3e; }
.badge-warning { background: rgba(237, 137, 54, 0.15); color: #dd6b20; }
.badge-info { background: rgba(102, 126, 234, 0.15); color: #667eea; }
.mask { font-family: monospace; font-size: 12px; color: #999; }
.code { font-family: monospace; background: #f4f4f4; padding: 2px 6px; border-radius: 4px; font-size: 12px; }
.help-text { font-size: 12px; color: #999; margin-top: 4px; }
.modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 1000; }
.modal-content { background: white; border-radius: 10px; padding: 25px; max-width: 550px; width: 90%; max-height: 80vh; overflow-y: auto; }
.modal-title { font-size: 18px; font-weight: 600; margin-bottom: 20px; color: #333; }
.modal-actions { display: flex; gap: 10px; justify-content: flex-end; margin-top: 20px; }
.error { color: #f56565; padding: 10px; background: #fff5f5; border-radius: 5px; margin-bottom: 15px; font-size: 13px; }
.success-msg { color: #48bb78; padding: 10px; background: #f0fff4; border-radius: 5px; margin-bottom: 15px; font-size: 13px; }
.info-box { background: #e7f3ff; border: 1px solid #b3d8fd; border-radius: 5px; padding: 10px; margin-bottom: 15px; font-size: 13px; color: #333; }
.pagination { display: flex; justify-content: center; gap: 5px; margin-top: 15px; }
.pagination button { padding: 5px 12px; border: 1px solid #ddd; background: white; border-radius: 5px; cursor: pointer; }
.pagination button.active { background: #667eea; color: white; border-color: #667eea; }
.pagination button:disabled { opacity: 0.5; cursor: not-allowed; }
.pagination span { padding: 5px 12px; color: #666; font-size: 13px; }
.empty { text-align: center; padding: 40px; color: #999; font-size: 14px; }
.spinner { display: inline-block; width: 16px; height: 16px; border: 2px solid rgba(255,255,255,.3); border-radius: 50%; border-top-color: white; animation: spin .6s linear infinite; vertical-align: middle; margin-right: 6px; }
@keyframes spin { to { transform: rotate(360deg); } }
.flex-row { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.flex-between { display: flex; justify-content: space-between; align-items: center; }
.project-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 15px; }
.project-card { background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); position: relative; }
.project-card.enabled { border-left: 4px solid #48bb78; }
.project-card.disabled { border-left: 4px solid #ccc; opacity: 0.7; }
.project-name { font-size: 16px; font-weight: 600; color: #333; margin-bottom: 8px; }
.project-meta { font-size: 12px; color: #666; margin-bottom: 4px; }
.project-meta code { font-size: 12px; color: #667eea; }
.project-accounts { display: flex; gap: 4px; flex-wrap: wrap; margin-top: 10px; }
.account-tag { display: inline-block; padding: 2px 8px; border-radius: 12px; font-size: 11px; background: #e7f3ff; color: #667eea; }
</style>
</head>
<body>
<div id="app">
<div class="container">
    <div class="header">
        <h1>🤖 Telegram 消息转发工具</h1>
        <p>账号管理 · 消息转发 · 定时签到 | SQLite</p>
    </div>

    <div class="nav-tabs">
        <div :class="['nav-tab', tab==='dash'?'active':'']" @click="tab='dash'">📊 仪表盘</div>
        <div :class="['nav-tab', tab==='accounts'?'active':'']" @click="tab='accounts'">👤 账号管理</div>
        <div :class="['nav-tab', tab==='forward'?'active':'']" @click="tab='forward'">📨 转发配置</div>
        <div :class="['nav-tab', tab==='projects'?'active':'']" @click="tab='projects'">⏰ 签到任务</div>
        <div :class="['nav-tab', tab==='logs'?'active':'']" @click="tab='logs'">📋 执行日志</div>
    </div>

    <!-- ====== 仪表盘 ====== -->
    <div v-if="tab==='dash'">
        <div class="stats-grid">
            <div class="stat-card"><div class="stat-value">{{dash.account_count}}</div><div class="stat-label">账号总数</div></div>
            <div class="stat-card green"><div class="stat-value">{{dash.account_online}}</div><div class="stat-label">在线</div></div>
            <div class="stat-card orange"><div class="stat-value">{{dash.project_count}}</div><div class="stat-label">签到项目</div></div>
            <div class="stat-card green"><div class="stat-value">{{dash.project_enabled}}</div><div class="stat-label">已启用</div></div>
            <div class="stat-card gray"><div class="stat-value">{{dash.today_logs}}</div><div class="stat-label">今日执行</div></div>
            <div :class="['stat-card', dash.forward_enabled?'green':'red']"><div class="stat-value">{{dash.forward_enabled?'已开启':'未开启'}}</div><div class="stat-label">转发状态</div></div>
        </div>
        <div class="card" v-if="recentLogs.length">
            <div class="card-title">最近执行记录</div>
            <table>
                <thead><tr><th>时间</th><th>项目</th><th>账号</th><th>状态</th><th>详情</th></tr></thead>
                <tbody>
                    <tr v-for="l in recentLogs" :key="l.id">
                        <td>{{fmtTime(l.created_at)}}</td><td>{{l.project_name}}</td><td>{{l.account_name}}</td>
                        <td><span :class="['badge', l.status==='success'?'badge-success':'badge-danger']">{{l.status==='success'?'成功':'失败'}}</span></td>
                        <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{{l.detail}}</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>

    <!-- ====== 账号管理 ====== -->
    <div v-if="tab==='accounts'">
        <div class="flex-between" style="margin-bottom:15px">
            <div></div>
            <button class="btn btn-primary" @click="showAccountModal()">+ 添加账号</button>
        </div>
        <div class="card" v-if="accounts.length">
            <div class="card-title">账号列表</div>
            <table>
                <thead><tr><th>备注</th><th>API ID</th><th>API Hash</th><th>状态</th><th>Telegram</th><th>操作</th></tr></thead>
                <tbody>
                    <tr v-for="a in accounts" :key="a.id">
                        <td><strong>{{a.name}}</strong></td>
                        <td><span class="mask">{{a.api_id}}</span></td>
                        <td><span class="mask">{{maskStr(a.api_hash)}}</span></td>
                        <td><span :class="['badge', a.is_connected?'badge-success':a.is_logged_in?'badge-warning':'badge-danger']">{{a.is_connected?'在线':a.is_logged_in?'离线':'未登录'}}</span></td>
                        <td>{{a.first_name}}{{a.username?' @'+a.username:''}}</td>
                        <td>
                            <div class="flex-row">
                                <button class="btn btn-outline btn-sm" @click="showAccountModal(a)" v-if="!a.is_logged_in">登录</button>
                                <button class="btn btn-primary btn-sm" @click="connectAccount(a.id)" v-if="a.is_logged_in&&!a.is_connected">连接</button>
                                <button class="btn btn-outline btn-sm" @click="logoutAccount(a.id)" v-if="a.is_logged_in">登出</button>
                                <button class="btn btn-outline btn-sm" @click="showAccountModal(a)">编辑</button>
                                <button class="btn btn-danger btn-sm" @click="deleteAccount(a.id)">删除</button>
                            </div>
                        </td>
                    </tr>
                </tbody>
            </table>
        </div>
        <div class="empty" v-else>暂无账号，点击右上角 + 添加账号</div>
    </div>

    <!-- 账号弹窗 -->
    <div class="modal-overlay" v-if="accountModal.show">
        <div class="modal-content">
            <div class="modal-title">{{accountModal.edit?'编辑账号':'添加账号'}}</div>
            <div class="error" v-if="accountModal.error">{{accountModal.error}}</div>
            <div class="form-group"><label>备注名称 *</label><input type="text" v-model="accountModal.form.name" placeholder="例如：甲-主签到"></div>
            <div class="form-group"><label>API ID *</label><input type="text" v-model="accountModal.form.api_id" placeholder="从 my.telegram.org 获取"></div>
            <div class="form-group"><label>API Hash *</label><input type="text" v-model="accountModal.form.api_hash" placeholder="从 my.telegram.org 获取"></div>
            <div v-if="accountModal.step==='login'">
                <div class="form-group"><label>手机号（含国家代码）</label><input type="text" v-model="accountModal.loginPhone" placeholder="+8613800138000"></div>
                <button class="btn btn-primary" @click="sendCode()" :disabled="accountModal.loading"><span v-if="accountModal.loading" class="spinner"></span>发送验证码</button>
            </div>
            <div v-if="accountModal.step==='verify'">
                <div class="form-group"><label>验证码</label><input type="text" v-model="accountModal.loginCode" placeholder="输入验证码"></div>
                <div class="form-group"><label>两步验证密码（无则留空）</label><input type="password" v-model="accountModal.loginPwd" placeholder="两步验证密码"></div>
                <button class="btn btn-success" @click="verifyCode()" :disabled="accountModal.loading"><span v-if="accountModal.loading" class="spinner"></span>验证登录</button>
            </div>
            <div class="modal-actions" v-if="accountModal.step==='form'">
                <button class="btn btn-outline" @click="closeAccountModal()">取消</button>
                <button class="btn btn-primary" @click="saveAccount()" :disabled="accountModal.loading">保存</button>
            </div>
        </div>
    </div>

    <!-- ====== 转发配置 ====== -->
    <div v-if="tab==='forward'">
        <div class="card">
            <div class="card-title">转发配置</div>
            <div class="info-box">
                <strong>转发规则说明：</strong><br>
                · 小号收到的私聊消息 → 转发到 <strong>大号 Chat ID</strong>（群组或私人）<br>
                · <strong>allowed_senders</strong> 用于过滤：只转发列表中发件人的消息<br>
                &nbsp;&nbsp;- <code>@username</code> 按<strong>用户名</strong>匹配（如 <code>"@HaxBot"</code>）<br>
                &nbsp;&nbsp;- <code>数字ID</code> 按<strong>用户数字ID</strong>匹配（如 <code>"123456789"</code>）<br>
                · 留空 <code>[]</code> 表示<strong>不筛选</strong>，转发所有私聊消息
            </div>
            <div class="form-group"><label>大号 Chat ID * <span class="help-text">例：-4688142035（群组）或 123456789（个人）</span></label><input type="text" v-model="fwd.target_chat_id" placeholder="输入 Chat ID"></div>
            <div class="form-group"><label>允许的发件人 <span class="help-text">每行一个。留空表示转发全部私聊</span></label><textarea v-model="fwd.allowed_senders" placeholder="@HaxBot&#10;123456789" rows="4" style="width:100%;padding:8px;border:1px solid #ddd;border-radius:5px;font-size:14px;resize:vertical"></textarea></div>
            <div class="form-group"><label><input type="checkbox" v-model="fwd.is_enabled" style="margin-right:6px">启用转发</label></div>
            <div class="flex-row">
                <button class="btn btn-primary" @click="saveForward()" :disabled="fwdLoading">{{fwdLoading?'保存中...':'保存配置'}}</button>
                <span class="help-text" v-if="fwdMsg">{{fwdMsg}}</span>
            </div>
        </div>
    </div>

    <!-- ====== 签到任务（卡片视图） ====== -->
    <div v-if="tab==='projects'">
        <div class="flex-between" style="margin-bottom:15px">
            <div></div>
            <button class="btn btn-primary" @click="showProjectModal()">+ 添加项目</button>
        </div>
        <div class="project-cards" v-if="projects.length">
            <div :class="['project-card', p.is_enabled?'enabled':'disabled']" v-for="p in projects" :key="p.id">
                <div class="project-name">{{p.name}}</div>
                <div class="project-meta">{{p.target_type==='group'?'👥':'🤖'}} 目标: <code>{{p.target_bot}}</code></div>
                <div class="project-meta">💬 消息: <code>{{p.message}}</code></div>
                <div class="project-meta">⏱ 调度: {{p.schedule_type==='cron'?'Cron':'间隔'}} <code>{{p.schedule_rule}}</code></div>
                <div style="margin-top:6px">
                    <span :class="['badge', p.is_enabled?'badge-success':'badge-warning']" style="margin-right:4px">{{p.is_enabled?'启用中':'已停用'}}</span>
                    <span class="badge badge-info" v-if="p.account_ids.length">{{p.account_ids.length}} 个账号</span>
                </div>
                <div class="project-accounts" v-if="p.account_ids.length">
                    <span class="account-tag" v-for="aid in p.account_ids" :key="aid">{{getAccountName(aid)}}</span>
                </div>
                <div class="flex-row" style="margin-top:12px">
                    <button class="btn btn-outline btn-sm" @click="showProjectModal(p)">编辑</button>
                    <button class="btn btn-success btn-sm" @click="execProject(p.id)">▶ 测试执行</button>
                    <button class="btn btn-danger btn-sm" @click="deleteProject(p.id)">删除</button>
                </div>
            </div>
        </div>
        <div class="empty" v-else>暂无签到项目，点击右上角 + 添加项目</div>
    </div>

    <!-- 项目弹窗 -->
    <div class="modal-overlay" v-if="projectModal.show">
        <div class="modal-content">
            <div class="modal-title">{{projectModal.edit?'编辑':'添加'}}签到项目</div>
            <div class="error" v-if="projectModal.error">{{projectModal.error}}</div>
            <div class="form-group"><label>项目名称 *</label><input type="text" v-model="projectModal.form.name" placeholder="例如：Lamhosting签到"></div>
            <div class="form-group"><label>目标类型</label>
                <select v-model="projectModal.form.target_type">
                    <option value="bot">🤖 机器人</option>
                    <option value="group">👥 群组</option>
                    <option value="channel">📢 频道</option>
                </select>
            </div>
            <div class="form-group"><label>目标 <span class="help-text">{{projectModal.form.target_type==='bot'?'@username':'群组ID 或 @username'}}</span></label><input type="text" v-model="projectModal.form.target_bot" :placeholder="projectModal.form.target_type==='bot'?'@Lamhosting_bot':projectModal.form.target_type==='group'?'@mygroup 或 -1001234567890':'@mychannel'"></div>
            <div class="form-group"><label>发送内容 *</label><input type="text" v-model="projectModal.form.message" placeholder="/check"></div>
            <div class="form-group"><label>调度类型</label>
                <select v-model="projectModal.form.schedule_type">
                    <option value="cron">Cron 表达式</option>
                    <option value="interval">固定间隔</option>
                </select>
            </div>
            <div class="form-group" v-if="projectModal.form.schedule_type==='cron'">
                <label>规则 <span class="help-text">格式: 分 时 日 月 周 (例如 "0 9 * * *" = 每天9点)</span></label>
                <input type="text" v-model="projectModal.form.schedule_rule" placeholder="0 9 * * *">
            </div>
            <div class="form-group" v-else>
                <label>间隔秒数 <span class="help-text">例如 450 = 7分30秒</span></label>
                <input type="number" v-model="projectModal.form.schedule_rule" placeholder="450">
            </div>
            <div class="form-group"><label><input type="checkbox" v-model="projectModal.form.is_enabled" style="margin-right:6px">启用</label></div>
            <div class="form-group" v-if="projectModal.edit">
                <label>分配账号（可多选）</label>
                <div v-for="a in accounts" :key="a.id" style="margin:4px 0">
                    <label><input type="checkbox" :value="a.id" v-model="projectModal.assignIds"> {{a.name}} <span class="help-text">({{a.first_name||'未登录'}})</span></label>
                </div>
                <button class="btn btn-outline btn-sm" @click="saveAssign()" style="margin-top:8px">保存分配</button>
            </div>
            <div class="modal-actions">
                <button class="btn btn-outline" @click="closeProjectModal()">取消</button>
                <button class="btn btn-primary" @click="saveProject()" :disabled="projectModal.loading">保存</button>
            </div>
        </div>
    </div>

    <!-- ====== 日志 ====== -->
    <div v-if="tab==='logs'">
        <div class="flex-between" style="margin-bottom:15px">
            <div class="flex-row">
                <select v-model="logFilter.status" @change="loadLogs()" style="padding:8px;border:1px solid #ddd;border-radius:5px">
                    <option value="">全部状态</option><option value="success">成功</option><option value="error">失败</option>
                </select>
                <select v-model="logFilter.project_id" @change="loadLogs()" style="padding:8px;border:1px solid #ddd;border-radius:5px">
                    <option value="">全部项目</option>
                    <option v-for="p in projects" :key="p.id" :value="p.id">{{p.name}}</option>
                </select>
            </div>
            <button class="btn btn-danger btn-sm" @click="clearLogs()">清空日志</button>
        </div>
        <div class="card" v-if="logs.items.length">
            <div class="card-title">执行日志</div>
            <table>
                <thead><tr><th>时间</th><th>项目</th><th>账号</th><th>状态</th><th>详情</th></tr></thead>
                <tbody>
                    <tr v-for="l in logs.items" :key="l.id">
                        <td>{{fmtTime(l.created_at)}}</td><td>{{l.project_name}}</td><td>{{l.account_name}}</td>
                        <td><span :class="['badge', l.status==='success'?'badge-success':'badge-danger']">{{l.status==='success'?'成功':'失败'}}</span></td>
                        <td style="max-width:300px;word-break:break-all">{{l.detail}}</td>
                    </tr>
                </tbody>
            </table>
            <div class="pagination" v-if="logs.total>logs.size">
                <button :disabled="logs.page<=1" @click="goPage(logs.page-1)">上一页</button>
                <span>第 {{logs.page}} / {{Math.ceil(logs.total/logs.size)}} 页 (共 {{logs.total}} 条)</span>
                <button :disabled="logs.page>=Math.ceil(logs.total/logs.size)" @click="goPage(logs.page+1)">下一页</button>
            </div>
        </div>
        <div class="empty" v-else>暂无日志</div>
    </div>
</div>
</div>
<script>
const {createApp,ref,reactive,onMounted,watch}=Vue
createApp({
setup(){
    const tab=ref('dash')
    const dash=reactive({account_count:0,account_online:0,project_count:0,project_enabled:0,today_logs:0,forward_enabled:false})
    const recentLogs=ref([])
    const accounts=ref([])
    const accountModal=reactive({show:false,edit:false,step:'form',error:'',loading:false,form:{name:'',api_id:'',api_hash:''},loginPhone:'',loginCode:'',loginPwd:''})
    const fwd=reactive({target_chat_id:'',allowed_senders:'',is_enabled:false})
    const fwdLoading=ref(false),fwdMsg=ref('')
    const projects=ref([])
    const projectModal=reactive({show:false,edit:false,loading:false,error:'',form:{name:'',target_type:'bot',target_bot:'',message:'',schedule_type:'cron',schedule_rule:'',is_enabled:true},assignIds:[],editId:null})
    const logs=reactive({items:[],total:0,page:1,size:20})
    const logFilter=reactive({status:'',project_id:''})

    function errMsg(e){
        const d=e.response&&e.response.data?e.response.data.detail:null
        if(!d)return e.message||'未知错误'
        if(Array.isArray(d))return d.map(function(x){return (x.loc||[]).join('.')+': '+x.msg}).join('; ')
        if(typeof d==='string')return d
        return JSON.stringify(d)
    }

    async function loadDash(){var r=await axios.get('/api/dashboard');Object.assign(dash,r.data)}
    async function loadRecentLogs(){var r=await axios.get('/api/logs?size=10');recentLogs.value=r.data.items}
    async function loadAccounts(){var r=await axios.get('/api/accounts');accounts.value=r.data}
    async function loadFwd(){var r=await axios.get('/api/forward-config');Object.assign(fwd,r.data);try{var arr=JSON.parse(fwd.allowed_senders);if(Array.isArray(arr)){fwd.allowed_senders=arr.join('\n')}}catch(e){}}
    async function loadProjects(){var r=await axios.get('/api/projects');projects.value=r.data}
    async function loadLogs(){var params={page:logs.page,size:logs.size};if(logFilter.status)params.status=logFilter.status;if(logFilter.project_id)params.project_id=logFilter.project_id;var r=await axios.get('/api/logs',{params:params});logs.items=r.data.items;logs.total=r.data.total}
    async function goPage(p){logs.page=p;await loadLogs()}
    async function refreshAll(){await Promise.all([loadDash(),loadRecentLogs(),loadAccounts(),loadFwd(),loadProjects(),loadLogs()])}
    onMounted(refreshAll)
    watch(tab,function(t){
        if(t==='dash'){loadDash();loadRecentLogs()}
        if(t==='accounts')loadAccounts()
        if(t==='forward')loadFwd()
        if(t==='projects')loadProjects()
        if(t==='logs')loadLogs()
    })

    function maskStr(s){if(!s)return'';if(s.length<=8)return'****';return s.slice(0,4)+'****'+s.slice(-4)}
    function fmtTime(t){if(!t)return'';var d=new Date(t);return d.toLocaleString('zh-CN')}
    function getAccountName(id){var a=accounts.value.find(function(x){return x.id===id});return a?a.name:'#'+id}

    // 账号
    function showAccountModal(acc){
        accountModal.show=true;accountModal.step='form';accountModal.error=''
        if(acc){accountModal.edit=true;accountModal.form={name:acc.name,api_id:acc.api_id,api_hash:acc.api_hash};accountModal.editId=acc.id}
        else{accountModal.edit=false;accountModal.form={name:'',api_id:'',api_hash:''};accountModal.editId=null}
    }
    function closeAccountModal(){accountModal.show=false}
    async function saveAccount(){
        accountModal.loading=true;accountModal.error=''
        try{
            if(accountModal.edit){await axios.put('/api/accounts/'+accountModal.editId,accountModal.form)}
            else{var r=await axios.post('/api/accounts',accountModal.form);accountModal.editId=r.data.id;accountModal.edit=true}
            accountModal.step='login';accountModal.loading=false
        }catch(e){accountModal.error=errMsg(e);accountModal.loading=false}
    }
    async function sendCode(){
        accountModal.loading=true;accountModal.error=''
        try{await axios.post('/api/accounts/'+accountModal.editId+'/send-code',{phone:accountModal.loginPhone});accountModal.step='verify'}
        catch(e){accountModal.error=errMsg(e)}
        accountModal.loading=false
    }
    async function verifyCode(){
        accountModal.loading=true;accountModal.error=''
        try{await axios.post('/api/accounts/'+accountModal.editId+'/verify',{phone:accountModal.loginPhone,code:accountModal.loginCode,password:accountModal.loginPwd});closeAccountModal();loadAccounts();loadDash()}
        catch(e){accountModal.error=errMsg(e)}
        accountModal.loading=false
    }
    async function connectAccount(id){try{var r=await axios.post('/api/accounts/'+id+'/connect');alert(r.data.message);loadAccounts();loadDash()}catch(e){alert('连接失败: '+errMsg(e))}}
    async function logoutAccount(id){if(!confirm('确认登出此账号？'))return;await axios.post('/api/accounts/'+id+'/logout');loadAccounts();loadDash()}
    async function deleteAccount(id){if(!confirm('确认删除此账号？将同时删除 session 文件。'))return;await axios.delete('/api/accounts/'+id);loadAccounts();loadDash()}
    // 转发
    async function saveForward(){
        fwdLoading.value=true;fwdMsg.value='';
        var senders=fwd.allowed_senders.split('\n').map(function(s){return s.trim()}).filter(function(s){return s.length>0});
        try{await axios.put('/api/forward-config',{target_chat_id:fwd.target_chat_id,allowed_senders:JSON.stringify(senders),is_enabled:fwd.is_enabled});fwdMsg.value='已保存'}
        catch(e){fwdMsg.value='错误: '+errMsg(e)};
        fwdLoading.value=false
    }
    // 项目
    function showProjectModal(p){
        projectModal.show=true;projectModal.error='';projectModal.form={name:'',target_type:'bot',target_bot:'',message:'',schedule_type:'cron',schedule_rule:'',is_enabled:true};projectModal.assignIds=[]
        if(p){projectModal.edit=true;projectModal.editId=p.id;Object.assign(projectModal.form,{name:p.name,target_type:p.target_type||'bot',target_bot:p.target_bot,message:p.message,schedule_type:p.schedule_type,schedule_rule:p.schedule_rule,is_enabled:p.is_enabled});projectModal.assignIds=[].concat(p.account_ids)}
        else{projectModal.edit=false;projectModal.editId=null}
    }
    function closeProjectModal(){projectModal.show=false}
    async function saveProject(){
        projectModal.loading=true;projectModal.error=''
        try{
            var payload=Object.assign({},projectModal.form,{schedule_rule:String(projectModal.form.schedule_rule),target_type:projectModal.form.target_type})
            if(projectModal.edit){await axios.put('/api/projects/'+projectModal.editId,payload)}
            else{var r=await axios.post('/api/projects',payload);projectModal.editId=r.data.id;projectModal.edit=true}
            closeProjectModal();loadProjects();loadDash()
        }catch(e){projectModal.error=errMsg(e)}
        projectModal.loading=false
    }
    async function saveAssign(){try{await axios.put('/api/projects/'+projectModal.editId+'/accounts',{account_ids:projectModal.assignIds});loadProjects()}catch(e){alert('保存失败: '+errMsg(e))}}
    async function deleteProject(id){if(!confirm('确认删除此项目？'))return;await axios.delete('/api/projects/'+id);loadProjects();loadDash()}
    async function execProject(id){try{var r=await axios.post('/api/projects/'+id+'/execute');alert('执行结果: '+JSON.stringify(r.data.results,null,2));loadLogs();loadDash()}catch(e){alert('执行失败: '+errMsg(e))}}
    async function clearLogs(){if(!confirm('确认清空所有日志？'))return;await axios.delete('/api/logs');loadLogs();loadDash()}

    return{tab,dash,recentLogs,accounts,accountModal,fwd,fwdLoading,fwdMsg,projects,projectModal,logs,logFilter,
        maskStr,fmtTime,getAccountName,
        showAccountModal,closeAccountModal,saveAccount,sendCode,verifyCode,connectAccount,logoutAccount,deleteAccount,
        saveForward,showProjectModal,closeProjectModal,saveProject,saveAssign,deleteProject,execProject,loadLogs,goPage,clearLogs}
}
}).mount('#app')
</script>
</body>
</html>
"""


# ==================== 入口 ====================

if __name__ == "__main__":
    import uvicorn
    # 支持从 telegram_tool/ 或 telegram_tool/app/ 目录运行
    if os.path.basename(os.getcwd()) == "app":
        uvicorn.run("main:app", host=HOST, port=PORT, reload=True)
    else:
        uvicorn.run("app.main:app", host=HOST, port=PORT, reload=True)
