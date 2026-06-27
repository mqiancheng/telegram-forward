"""Telethon 客户端管理器

负责所有 Telegram 账号客户端的生命周期管理、消息监听和转发。
"""

import asyncio
import json
import logging
from typing import Optional

from telethon import TelegramClient, events
from sqlalchemy.orm import Session

try:
    from .database import SessionLocal
    from .models import Account, ForwardConfig
    from .config import SESSION_DIR
except ImportError:
    from database import SessionLocal
    from models import Account, ForwardConfig
    from config import SESSION_DIR

logger = logging.getLogger(__name__)


class ClientManager:
    """Telegram 客户端管理器（单例）"""

    def __init__(self):
        self.clients: dict[int, TelegramClient] = {}       # account_id -> client
        self._bg_tasks: dict[int, asyncio.Task] = {}       # account_id -> background task
        self._pending_logins: dict[int, TelegramClient] = {}  # account_id -> client (登录中)

    # ==================== 事件处理器辅助 ====================

    @staticmethod
    def _remove_all_handlers(client: TelegramClient):
        """移除客户端上所有已注册的事件处理器"""
        try:
            handlers = client.list_event_handlers()
            for handler in handlers:
                client.remove_event_handler(callback=handler[0])
        except Exception:
            pass  # 如果没有 handler 也不报错

    # ==================== 客户端生命周期 ====================

    async def start_client(self, account: Account) -> bool:
        """启动并连接一个账号的 Telegram 客户端"""
        session_path = str(SESSION_DIR / account.session_name)

        client = TelegramClient(
            session_path,
            int(account.api_id),
            account.api_hash,
        )

        try:
            await client.connect()

            if not await client.is_user_authorized():
                logger.warning(f"Account {account.name}: session 未授权（可能已过期或在其他设备登出），需要重新登录")
                self.clients[account.id] = client
                # 不在这里修改 is_logged_in，由显式登出或重新登录流程处理
                return False  # 返回 False 表示需要重新登录

            # 获取用户信息并更新数据库
            me = await client.get_me()
            self._update_account_info(account.id, me)

            # 清除旧处理器，设置新消息转发处理器
            self._remove_all_handlers(client)
            self._setup_handlers(account.id, client)

            self.clients[account.id] = client
            logger.info(f"Client started: {account.name} (@{me.username or me.first_name})")

            # 后台保持连接
            self._bg_tasks[account.id] = asyncio.create_task(
                self._keep_alive(account.id, client)
            )

            return True

        except Exception as e:
            logger.error(f"Failed to start client for {account.name}: {e}")
            try:
                await client.disconnect()
            except Exception:
                pass
            # 连接失败不修改登录状态，下次还能重试
            return False

    async def stop_client(self, account_id: int):
        """停止一个账号的客户端"""
        # 取消后台任务
        task = self._bg_tasks.pop(account_id, None)
        if task:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

        client = self.clients.pop(account_id, None)
        if client:
            await client.disconnect()
            logger.info(f"Client stopped: account #{account_id}")

    async def stop_all(self):
        """停止所有客户端"""
        for aid in list(self.clients.keys()):
            await self.stop_client(aid)
        logger.info("All clients stopped")

    # ==================== 登录流程 ====================

    async def send_login_code(self, account_id: int, phone: str) -> dict:
        """发送登录验证码"""
        client = self.clients.get(account_id)
        if not client:
            return {"success": False, "error": "客户端未连接，请先保存账号配置"}

        try:
            if not client.is_connected():
                await client.connect()

            result = await client.send_code_request(phone)
            self._pending_logins[account_id] = client
            return {
                "success": True,
                "phone_code_hash": result.phone_code_hash,
                "timeout": getattr(result, "timeout", 60),
            }
        except Exception as e:
            return {"success": False, "error": str(e)}

    async def verify_login_code(
        self, account_id: int, phone: str, code: str, password: str = ""
    ) -> dict:
        """验证登录验证码"""
        client = self.clients.get(account_id)
        if not client:
            return {"success": False, "error": "客户端不存在"}

        try:
            if not client.is_connected():
                await client.connect()

            try:
                await client.sign_in(phone, code)
            except Exception as e:
                err_str = str(e).lower()
                if "password" in err_str or "2fa" in err_str:
                    if not password:
                        return {"success": False, "need_password": True, "error": "需要两步验证密码"}
                    await client.sign_in(password=password)
                else:
                    raise

            me = await client.get_me()
            self._update_account_info(account_id, me)
            self._pending_logins.pop(account_id, None)

            # 重新设置处理器
            self._remove_all_handlers(client)
            self._setup_handlers(account_id, client)

            # 启动后台保活
            old_task = self._bg_tasks.pop(account_id, None)
            if old_task:
                old_task.cancel()
            self._bg_tasks[account_id] = asyncio.create_task(
                self._keep_alive(account_id, client)
            )

            return {
                "success": True,
                "user_id": str(me.id),
                "username": me.username or "",
                "first_name": me.first_name or "",
                "phone": me.phone or "",
            }

        except Exception as e:
            return {"success": False, "error": str(e)}

    async def logout_account(self, account_id: int):
        """登出账号"""
        client = self.clients.get(account_id)
        if client and client.is_connected():
            try:
                await client.log_out()
            except Exception:
                pass
        await self.stop_client(account_id)
        self._update_account_logged_in(account_id, False)
        # 删除 session 文件
        import os
        db = SessionLocal()
        try:
            account = db.query(Account).get(account_id)
            if account:
                session_file = str(SESSION_DIR / f"{account.session_name}.session")
                if os.path.exists(session_file):
                    os.remove(session_file)
                account.is_logged_in = False
                account.user_id = ""
                account.username = ""
                account.first_name = ""
                account.phone = ""
                db.commit()
        finally:
            db.close()

    # ==================== 消息转发 ====================

    def _setup_handlers(self, account_id: int, client: TelegramClient):
        """为客户端设置消息转发事件处理器"""
        # 读取转发配置
        db = SessionLocal()
        try:
            fwd = db.query(ForwardConfig).first()
            if not fwd or not fwd.is_enabled or not fwd.target_chat_id:
                return

            target_chat_id = int(fwd.target_chat_id)
            allowed_senders = self._parse_senders(fwd.allowed_senders)

            @client.on(events.NewMessage(incoming=True))
            async def forward_handler(event: events.NewMessage.Event):
                if not event.is_private:
                    return
                if not allowed_senders:
                    await self._do_forward(event, target_chat_id)
                    return

                sender = await event.get_sender()
                sid = str(sender.id)
                suname = sender.username or ""
                for allowed in allowed_senders:
                    if allowed.lower() == sid or (
                        suname and allowed.lower().lstrip("@") == suname.lower().lstrip("@")
                    ):
                        await self._do_forward(event, target_chat_id)
                        return

        finally:
            db.close()

    async def _do_forward(self, event: events.NewMessage.Event, target: int):
        """执行消息转发"""
        try:
            await event.client.forward_messages(target, event.message)
            logger.info(f"Forwarded message from {event.sender_id} -> {target}")
        except Exception as e:
            logger.error(f"Forward failed: {e}")

    # ==================== 工具方法 ====================

    def get_client(self, account_id: int) -> Optional[TelegramClient]:
        return self.clients.get(account_id)

    def is_connected(self, account_id: int) -> bool:
        client = self.clients.get(account_id)
        return client is not None and client.is_connected()

    async def send_message(self, account_id: int, target: str, message: str):
        """通过指定账号发送消息"""
        client = self.get_client(account_id)
        if not client or not client.is_connected():
            raise RuntimeError(f"Account #{account_id} is not connected")
        return await client.send_message(target, message)

    async def reconnect_all(self):
        """重连所有已激活且已登录的账号（启动时调用）"""
        db = SessionLocal()
        try:
            accounts = (
                db.query(Account)
                .filter(Account.is_active == True, Account.is_logged_in == True)
                .all()
            )
        finally:
            db.close()

        if not accounts:
            logger.info("No logged-in accounts to reconnect")
            return

        logger.info(f"Reconnecting {len(accounts)} account(s)...")
        for acc in accounts:
            if acc.id in self.clients:
                continue
            # 每个账号重试 3 次，间隔递增
            for attempt in range(1, 4):
                ok = await self.start_client(acc)
                if ok:
                    logger.info(f"Account {acc.name} reconnected")
                    break
                logger.warning(f"Account {acc.name} reconnect attempt {attempt}/3 failed, retrying...")
                await asyncio.sleep(attempt * 3)
            else:
                logger.error(f"Account {acc.name} failed to reconnect after 3 attempts")
        logger.info(f"Reconnect finished: {sum(1 for a in accounts if a.id in self.clients and self.clients[a.id].is_connected())}/{len(accounts)} online")

    async def refresh_forward_handlers(self):
        """刷新所有客户端的转发处理器（配置变更后调用）"""
        for aid, client in self.clients.items():
            self._remove_all_handlers(client)
            self._setup_handlers(aid, client)

    async def _keep_alive(self, account_id: int, client: TelegramClient):
        """后台保持客户端连接，断线自动重连"""
        while True:
            try:
                await client.run_until_disconnected()
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(f"Client {account_id} disconnected: {e}")

            # 尝试重连（最多重试 10 次，间隔递增）
            db = SessionLocal()
            try:
                acc = db.query(Account).get(account_id)
            finally:
                db.close()

            if not acc or not acc.is_active:
                logger.info(f"Account {account_id} inactive, stop reconnect")
                return

            for attempt in range(1, 11):
                logger.info(f"Reconnect attempt {attempt}/10 for {acc.name}")
                try:
                    success = await self.start_client(acc)
                    if success:
                        logger.info(f"Reconnected {acc.name} successfully")
                        return  # start_client 会创建新的 _keep_alive，这个退出
                except Exception as ex:
                    logger.error(f"Reconnect attempt {attempt} failed: {ex}")
                await asyncio.sleep(min(attempt * 10, 60))  # 递增间隔: 10s, 20s, 30s... 最多 60s

            logger.error(f"Account {acc.name} reconnect failed after 10 attempts, giving up")
            return  # 彻底退出 keep_alive，避免无限重试刷日志

    # ==================== 数据库辅助 ====================

    @staticmethod
    def _update_account_info(account_id: int, me):
        """更新账号的 Telegram 用户信息"""
        db = SessionLocal()
        try:
            acc = db.query(Account).get(account_id)
            if acc:
                acc.user_id = str(me.id)
                acc.username = me.username or ""
                acc.first_name = me.first_name or ""
                acc.phone = me.phone or ""
                acc.is_logged_in = True
                db.commit()
        finally:
            db.close()

    @staticmethod
    def _update_account_logged_in(account_id: int, logged_in: bool):
        db = SessionLocal()
        try:
            acc = db.query(Account).get(account_id)
            if acc:
                acc.is_logged_in = logged_in
                db.commit()
        finally:
            db.close()

    @staticmethod
    def _parse_senders(raw: str) -> list[str]:
        try:
            return json.loads(raw) if raw else []
        except json.JSONDecodeError:
            return []


# 全局单例
client_manager = ClientManager()
