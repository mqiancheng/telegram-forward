"""定时任务调度服务

基于 APScheduler，管理签到 / 定时发送任务的调度与执行。
"""

import asyncio
import logging
import random
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy.orm import Session

try:
    from .database import SessionLocal
    from .models import Project, Account, TaskLog
    from .client_manager import client_manager
except ImportError:
    from database import SessionLocal
    from models import Project, Account, TaskLog
    from client_manager import client_manager

logger = logging.getLogger(__name__)

# 默认随机延迟配置（单位：秒），项目未配置时使用
DEFAULT_JITTER_MIN = 30
DEFAULT_JITTER_MAX = 180
DEFAULT_DELAY_MIN = 10
DEFAULT_DELAY_MAX = 60

# 子任务间间隔（秒）
SUBTASK_DELAY = 3


class SchedulerService:
    """定时任务调度服务（单例）"""

    def __init__(self):
        self.scheduler = AsyncIOScheduler(timezone="Asia/Shanghai")

    async def start(self):
        """启动调度器并加载所有启用的项目"""
        self.scheduler.start()
        await self._load_projects()
        logger.info("Scheduler started")

    async def stop(self):
        """停止调度器"""
        self.scheduler.shutdown(wait=False)
        logger.info("Scheduler stopped")

    # ==================== 任务管理 ====================

    def add_job(self, project: Project):
        """添加或更新一个项目的调度任务"""
        job_id = f"project_{project.id}"

        # 移除旧任务
        if self.scheduler.get_job(job_id):
            self.scheduler.remove_job(job_id)

        if not project.is_enabled:
            return

        if project.schedule_type == "cron":
            parts = project.schedule_rule.strip().split()
            if len(parts) != 5:
                logger.error(f"Invalid cron rule: {project.schedule_rule}")
                return
            self.scheduler.add_job(
                self._execute_project,
                "cron",
                args=[project.id],
                id=job_id,
                minute=parts[0],
                hour=parts[1],
                day=parts[2],
                month=parts[3],
                day_of_week=parts[4],
                replace_existing=True,
                misfire_grace_time=300,
            )
        elif project.schedule_type == "interval":
            seconds = int(project.schedule_rule)
            self.scheduler.add_job(
                self._execute_project,
                "interval",
                args=[project.id],
                id=job_id,
                seconds=seconds,
                replace_existing=True,
                misfire_grace_time=30,
            )

        logger.info(f"Job added: {project.name} ({project.schedule_type}: {project.schedule_rule})")

    def remove_job(self, project_id: int):
        """移除一个项目的调度任务"""
        job_id = f"project_{project_id}"
        if self.scheduler.get_job(job_id):
            self.scheduler.remove_job(job_id)
            logger.info(f"Job removed: project #{project_id}")

    async def execute_now(self, project_id: int) -> list[dict]:
        """立即手动执行一次项目任务（跳过随机延迟），返回执行结果列表"""
        return await self._execute_project(project_id, skip_delay=True)

    # ==================== 内部方法 ====================

    async def _load_projects(self):
        """从数据库加载所有启用的项目"""
        db = SessionLocal()
        try:
            projects = db.query(Project).filter(Project.is_enabled == True).all()
            for p in projects:
                self.add_job(p)
        finally:
            db.close()

    async def _execute_project(self, project_id: int, skip_delay: bool = False) -> list[dict]:
        """执行一个项目：遍历子任务和账号，发送消息（定时任务含随机延迟，手动执行跳过延迟）"""
        db = SessionLocal()
        results = []

        try:
            project = db.query(Project).get(project_id)
            if not project or not project.is_enabled:
                return results

            accounts = project.accounts if project.accounts else []
            if not accounts:
                logger.warning(f"Project '{project.name}': no accounts assigned")
                return results

            # 过滤启用的账号
            active_accounts = [a for a in accounts if a.is_active]
            if not active_accounts:
                logger.info(f"Project '{project.name}': no active accounts")
                return results

            # 构建发信目标列表：优先用子任务，否则用项目主目标
            subtask_list = sorted(project.subtasks, key=lambda s: s.sort_order) if project.subtasks else []
            if subtask_list:
                targets = [
                    {"target_bot": s.target_bot, "message": s.message, "target_type": s.target_type}
                    for s in subtask_list
                ]
            else:
                targets = [
                    {"target_bot": project.target_bot, "message": project.message, "target_type": project.target_type}
                ]

            if not skip_delay:
                # 任务级随机抖动（使用项目配置，否则默认值）
                jitter_min = project.jitter_min if project.jitter_min > 0 else DEFAULT_JITTER_MIN
                jitter_max = project.jitter_max if project.jitter_max > 0 else DEFAULT_JITTER_MAX
                if jitter_min > 0 and jitter_max > jitter_min:
                    jitter = random.randint(jitter_min, jitter_max)
                    logger.info(
                        f"[{project.name}] jitter delay {jitter}s "
                        f"before executing with {len(active_accounts)} accounts, {len(targets)} targets"
                    )
                    await asyncio.sleep(jitter)

            for i, account in enumerate(active_accounts):
                if not skip_delay:
                    # 账号间随机间隔
                    delay_min = project.account_delay_min if project.account_delay_min > 0 else DEFAULT_DELAY_MIN
                    delay_max = project.account_delay_max if project.account_delay_max > 0 else DEFAULT_DELAY_MAX
                    if i > 0 and delay_min > 0 and delay_max > delay_min:
                        delay = random.randint(delay_min, delay_max)
                        logger.info(f"[{project.name}] waiting {delay}s before next account...")
                        await asyncio.sleep(delay)

                # 对该账号发送所有子任务
                for j, target in enumerate(targets):
                    if j > 0 and not skip_delay:
                        await asyncio.sleep(SUBTASK_DELAY)

                    result = await self._send_for_account(db, project, account,
                                                          target["target_bot"], target["message"],
                                                          target.get("target_type", "bot"))
                    results.append(result)

        finally:
            db.close()

        return results

    async def _send_for_account(self, db: Session, project: Project, account: Account,
                                 target_bot: str, message: str, target_type: str = "bot") -> dict:
        """通过单个账号发送消息到指定目标"""
        now = datetime.now(timezone.utc)

        try:
            # 确保客户端已连接
            if not client_manager.is_connected(account.id):
                logger.info(f"Account '{account.name}' not connected, reconnecting...")
                ok = await client_manager.start_client(account)
                if not ok:
                    raise RuntimeError("Failed to connect")
                await asyncio.sleep(2)

            if not client_manager.is_connected(account.id):
                raise RuntimeError("Account not connected after retry")

            # 发送消息
            await client_manager.send_message(
                account.id,
                target_bot,
                message,
            )

            # 记录成功日志
            log = TaskLog(
                project_id=project.id,
                account_id=account.id,
                account_name=account.name,
                project_name=project.name,
                status="success",
                detail=f"[{target_type}] → {target_bot}: {message}",
                created_at=now,
            )
            db.add(log)
            db.commit()

            logger.info(f"[{project.name}] {account.name} → {target_bot}: {message}")
            return {"account": account.name, "target": target_bot, "status": "success"}

        except Exception as e:
            err_msg = str(e)
            log = TaskLog(
                project_id=project.id,
                account_id=account.id,
                account_name=account.name,
                project_name=project.name,
                status="error",
                detail=err_msg,
                created_at=now,
            )
            db.add(log)
            db.commit()

            logger.error(f"[{project.name}] {account.name} failed: {err_msg}")
            return {"account": account.name, "target": target_bot, "status": "error", "message": err_msg}


# 全局单例
scheduler_service = SchedulerService()
