FROM python:3.11-slim

LABEL org.opencontainers.image.description="Telegram 消息转发工具 - 支持多账号转发 + 定时签到"

WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码和静态资源
COPY app/ ./app/
COPY static/ ./static/

# 创建数据和会话目录
RUN mkdir -p /app/data/sessions

# 暴露端口
EXPOSE 44000

# 启动命令
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "44000"]
