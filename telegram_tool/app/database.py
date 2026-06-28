"""数据库连接管理"""

import logging
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, Session, declarative_base
try:
    from .config import DATABASE_URL
except ImportError:
    from config import DATABASE_URL

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
    echo=False,
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db() -> Session:
    """FastAPI 依赖注入：获取数据库会话"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """初始化数据库表并执行迁移"""
    try:
        from . import models  # noqa: F401  确保模型被导入
    except ImportError:
        import models  # noqa: F401  确保模型被导入
    Base.metadata.create_all(bind=engine)

    # 自动迁移：为已有数据库添加缺失的列
    _migrate()


def _migrate():
    """执行数据库迁移（为旧数据库添加新列）"""
    logger = logging.getLogger(__name__)
    migrations = [
        ("target_type", "projects", "VARCHAR(20) NOT NULL DEFAULT 'bot'"),
        ("jitter_min", "projects", "INTEGER NOT NULL DEFAULT 0"),
        ("jitter_max", "projects", "INTEGER NOT NULL DEFAULT 0"),
        ("account_delay_min", "projects", "INTEGER NOT NULL DEFAULT 0"),
        ("account_delay_max", "projects", "INTEGER NOT NULL DEFAULT 0"),
        ("sort_order", "projects", "INTEGER NOT NULL DEFAULT 0"),
    ]
    with engine.connect() as conn:
        for col_name, table, col_def in migrations:
            try:
                # 检查列是否存在
                result = conn.execute(text(
                    f"PRAGMA table_info({table})"
                ))
                columns = [row[1] for row in result]
                if col_name not in columns:
                    conn.execute(text(
                        f"ALTER TABLE {table} ADD COLUMN {col_name} {col_def}"
                    ))
                    conn.commit()
                    logger.info(f"Migration: added {col_name} to {table}")
            except Exception as e:
                logger.warning(f"Migration skipped ({col_name}): {e}")
