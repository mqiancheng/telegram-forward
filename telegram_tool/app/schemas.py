"""Pydantic 数据校验模型"""

from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


# ============ 账号 ============

class AccountCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    api_id: str = Field(..., min_length=1, max_length=50)
    api_hash: str = Field(..., min_length=1, max_length=100)


class AccountUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    api_id: Optional[str] = Field(None, max_length=50)
    api_hash: Optional[str] = Field(None, max_length=100)
    is_active: Optional[bool] = None


class AccountResponse(BaseModel):
    id: int
    name: str
    api_id: str
    api_hash: str
    session_name: str
    phone: str = ""
    user_id: str = ""
    username: str = ""
    first_name: str = ""
    is_logged_in: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class LoginCodeRequest(BaseModel):
    phone: str = Field(..., min_length=1)


class LoginVerifyRequest(BaseModel):
    phone: str
    code: str = ""
    password: str = ""


# ============ 转发配置 ============

class ForwardConfigRequest(BaseModel):
    target_chat_id: str = Field(..., min_length=1, max_length=50)
    allowed_senders: str = "[]"
    is_enabled: bool = True


class ForwardConfigResponse(BaseModel):
    id: int
    target_chat_id: str
    allowed_senders: str
    is_enabled: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============ 项目 ============

class ProjectCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    target_type: str = Field(default="bot", pattern="^(bot|group|channel)$")
    target_bot: str = Field(..., min_length=1, max_length=200)
    message: str = Field(..., min_length=1, max_length=500)
    schedule_type: str = Field(default="cron", pattern="^(cron|interval)$")
    schedule_rule: str = Field(..., min_length=1, max_length=100)
    jitter_min: int = Field(default=0, ge=0, le=43200)
    jitter_max: int = Field(default=0, ge=0, le=43200)
    account_delay_min: int = Field(default=0, ge=0, le=43200)
    account_delay_max: int = Field(default=0, ge=0, le=43200)


class ProjectUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=200)
    target_type: Optional[str] = None
    target_bot: Optional[str] = Field(None, max_length=200)
    message: Optional[str] = Field(None, max_length=500)
    schedule_type: Optional[str] = None
    schedule_rule: Optional[str] = None
    is_enabled: Optional[bool] = None
    jitter_min: Optional[int] = Field(None, ge=0, le=43200)
    jitter_max: Optional[int] = Field(None, ge=0, le=43200)
    account_delay_min: Optional[int] = Field(None, ge=0, le=43200)
    account_delay_max: Optional[int] = Field(None, ge=0, le=43200)
    sort_order: Optional[int] = None


class ProjectAssignAccounts(BaseModel):
    account_ids: List[int]


class ProjectResponse(BaseModel):
    id: int
    name: str
    target_type: str
    target_bot: str
    message: str
    schedule_type: str
    schedule_rule: str
    is_enabled: bool
    account_ids: List[int] = []
    jitter_min: int = 0
    jitter_max: int = 0
    account_delay_min: int = 0
    account_delay_max: int = 0
    sort_order: int = 0
    subtasks: List["SubTaskResponse"] = []
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============ 子任务 ============

class SubTaskCreate(BaseModel):
    target_type: str = Field(default="bot", pattern="^(bot|group|channel)$")
    target_bot: str = Field(..., min_length=1, max_length=200)
    message: str = Field(..., min_length=1, max_length=500)
    sort_order: int = Field(default=0)


class SubTaskUpdate(BaseModel):
    target_type: Optional[str] = None
    target_bot: Optional[str] = Field(None, max_length=200)
    message: Optional[str] = Field(None, max_length=500)
    sort_order: Optional[int] = None


class SubTaskResponse(BaseModel):
    id: int
    project_id: int
    target_type: str
    target_bot: str
    message: str
    sort_order: int

    class Config:
        from_attributes = True


# ============ 日志 ============

class TaskLogResponse(BaseModel):
    id: int
    project_id: int
    account_id: Optional[int]
    account_name: str = ""
    project_name: str = ""
    status: str
    detail: str = ""
    created_at: datetime

    class Config:
        from_attributes = True


# ============ 仪表盘 ============

class DashboardResponse(BaseModel):
    account_count: int = 0
    account_online: int = 0
    project_count: int = 0
    project_enabled: int = 0
    today_logs: int = 0
    forward_enabled: bool = False
