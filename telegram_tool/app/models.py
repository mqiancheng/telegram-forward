"""数据库模型"""

from datetime import datetime, timezone
from sqlalchemy import (
    Column, Integer, String, Text, Boolean, DateTime,
    ForeignKey, Table
)
from sqlalchemy.orm import relationship
try:
    from .database import Base
except ImportError:
    from database import Base

# 项目-账号 多对多关联表
project_accounts = Table(
    "project_accounts",
    Base.metadata,
    Column("project_id", Integer, ForeignKey("projects.id", ondelete="CASCADE"), primary_key=True),
    Column("account_id", Integer, ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True),
)


class Account(Base):
    """Telegram 账号"""
    __tablename__ = "accounts"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False, comment="备注名称")
    api_id = Column(String(50), nullable=False)
    api_hash = Column(String(100), nullable=False)
    session_name = Column(String(100), nullable=False)
    phone = Column(String(20), nullable=True, default="")
    user_id = Column(String(50), nullable=True, default="", comment="Telegram 用户ID")
    username = Column(String(100), nullable=True, default="", comment="Telegram @用户名")
    first_name = Column(String(100), nullable=True, default="")
    is_logged_in = Column(Boolean, default=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    projects = relationship("Project", secondary=project_accounts, back_populates="accounts")


class ForwardConfig(Base):
    """转发规则配置（单例）"""
    __tablename__ = "forward_config"

    id = Column(Integer, primary_key=True, autoincrement=True)
    target_chat_id = Column(String(50), nullable=False, default="", comment="大号 Chat ID")
    allowed_senders = Column(Text, nullable=False, default="[]", comment="JSON 数组，允许的发件人")
    is_enabled = Column(Boolean, default=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))


class Project(Base):
    """签到/定时任务项目"""
    __tablename__ = "projects"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(200), nullable=False, comment="项目名称")
    target_type = Column(String(20), nullable=False, default="bot", comment="bot / group / channel（无子任务时使用）")
    target_bot = Column(String(200), nullable=False, comment="目标 @username 或 Chat ID（无子任务时使用）")
    message = Column(String(500), nullable=False, comment="发送的消息内容（无子任务时使用）")
    schedule_type = Column(String(20), nullable=False, default="cron", comment="cron / interval")
    schedule_rule = Column(String(100), nullable=False, comment="cron表达式 或 间隔秒数")
    is_enabled = Column(Boolean, default=True)

    # 随机延迟配置（秒），0 表示不启用随机延迟
    jitter_min = Column(Integer, default=0, comment="任务级随机延迟下限（秒），0=不延迟")
    jitter_max = Column(Integer, default=0, comment="任务级随机延迟上限（秒）")
    account_delay_min = Column(Integer, default=0, comment="账号间随机间隔下限（秒），0=不延迟")
    account_delay_max = Column(Integer, default=0, comment="账号间随机间隔上限（秒）")

    # 排序
    sort_order = Column(Integer, default=0, comment="排序值，越小越靠前")

    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    accounts = relationship("Account", secondary=project_accounts, back_populates="projects")
    logs = relationship("TaskLog", back_populates="project", cascade="all, delete-orphan")
    subtasks = relationship("SubTask", back_populates="project", cascade="all, delete-orphan", order_by="SubTask.sort_order")


class SubTask(Base):
    """项目子任务（每个项目可含多个目标）"""
    __tablename__ = "subtask"

    id = Column(Integer, primary_key=True, autoincrement=True)
    project_id = Column(Integer, ForeignKey("projects.id", ondelete="CASCADE"), nullable=False)
    target_type = Column(String(20), nullable=False, default="bot", comment="bot / group / channel")
    target_bot = Column(String(200), nullable=False, comment="目标 @username 或 Chat ID")
    message = Column(String(500), nullable=False, comment="发送的消息内容")
    sort_order = Column(Integer, default=0, comment="排序值，越小越靠前")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    project = relationship("Project", back_populates="subtasks")


class TaskLog(Base):
    """任务执行日志"""
    __tablename__ = "task_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    project_id = Column(Integer, ForeignKey("projects.id", ondelete="CASCADE"))
    account_id = Column(Integer, ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True)
    account_name = Column(String(100), nullable=True, default="")
    project_name = Column(String(200), nullable=True, default="")
    status = Column(String(20), nullable=False, comment="success / failed / error")
    detail = Column(Text, nullable=True, default="")
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    project = relationship("Project", back_populates="logs")
