# Telegram 消息转发工具 (Docker 版)

基于 Telethon 的 Telegram 消息转发 + 定时签到工具，支持 WebUI 管理。

## 功能

- **消息转发**：小号收到私聊消息 → 自动转发到大号群组
- **定时签到**：支持 Cron 和固定间隔两种调度方式，多账号绑定多项目
- **WebUI 管理**：可视化配置账号、转发规则、签到任务
- **Docker 部署**：一键启动，数据持久化

## 快速开始

### 1. 拉取镜像

```bash
docker pull ghcr.io/<your-username>/tg-forward:latest
```

### 2. 创建 docker-compose.yml

```yaml
services:
  tg-forward:
    image: ghcr.io/<your-username>/tg-forward:latest
    container_name: tg-forward
    restart: unless-stopped
    ports:
      - "44000:44000"
    volumes:
      - ./data:/app/data
    environment:
      - TZ=Asia/Shanghai
```

### 3. 启动

```bash
docker compose up -d
```

### 4. 访问

浏览器打开 `http://你的IP:44000`

## 配置说明

### 账号配置

1. 在「账号管理」页面添加小号
2. 填写 API ID 和 API Hash（从 [my.telegram.org](https://my.telegram.org) 获取）
3. 点击「登录」，输入手机号和验证码完成授权
4. 可选填写备注名称（如「甲-主签到」）

### 转发配置

1. 在「转发配置」页面设置大号 Chat ID
2. 可选设置 allowed_senders 过滤特定发件人
3. 大号只需 Chat ID，不需要 API 凭证

### 签到任务

1. 在「签到任务」页面添加项目
2. 填写项目名称、目标机器人（如 `@Lamhosting_bot`）、发送消息（如 `/check`）
3. 设置调度规则：
   - **Cron**：`分 时 日 月 周`，例如 `0 9 * * *` = 每天 9:00
   - **间隔**：秒数，例如 `450` = 每 7 分 30 秒
4. 分配要使用的账号

签到消息自动通过现有转发规则转发回复给大号。

## 安全说明

- 数据库文件和 Telegram session 文件存储在 `data/` 目录
- **请勿将 `data/` 目录暴露到公网**
- docker-compose 的 volumes 建议映射到安全路径
- 建议定期备份 `data/` 目录

## 开发

```bash
pip install -r requirements.txt
cd telegram_tool
python -m uvicorn app.main:app --host 0.0.0.0 --port 44000 --reload
```

## GitHub Actions 自动构建

推送代码到 main 分支后，GitHub Actions 会自动构建 Docker 镜像并推送到 `ghcr.io`。

需要在仓库 Settings → Secrets and variables → Actions 中确保 `GITHUB_TOKEN` 有 `write packages` 权限。
