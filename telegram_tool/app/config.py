"""应用配置"""

import os
from pathlib import Path

# 基础路径
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
SESSION_DIR = DATA_DIR / "sessions"
DB_PATH = DATA_DIR / "tg_forward.db"

# 确保目录存在
DATA_DIR.mkdir(parents=True, exist_ok=True)
SESSION_DIR.mkdir(parents=True, exist_ok=True)

# 数据库 URL
DATABASE_URL = f"sqlite:///{DB_PATH}"

# 服务配置
HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "44000"))
