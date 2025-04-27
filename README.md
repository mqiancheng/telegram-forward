# Telegram 消息转发管理工具 🚀

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-Alpine%20Linux-green.svg)

这是一个用于管理 Telegram 消息转发的 Bash 脚本，支持多账号私聊消息实时转发到指定群组。通过交互式菜单，你可以轻松安装依赖、配置脚本、启动/停止脚本、查看日志等。

## ✨ 功能特性

- **依赖安装**：自动安装 Python、Telethon 和 supervisord。
- **脚本配置**：生成 Telegram 消息转发脚本，支持多账号。
- **进程管理**：使用 `supervisord` 管理脚本，支持自动重启。
- **日志管理**：通过 `logrotate` 自动轮转日志，节省空间。
- **交互式菜单**：一键操作，简单易用。

## 📋 前提条件

确保你的服务器满足以下条件：

- **操作系统**：Alpine Linux（其他 Linux 发行版需调整依赖安装命令）。
- **工具**：已安装 `curl` 和 `bash`。
- **网络**：可以访问 Telegram API 和 GitHub。

## 🚀 快速开始

### 1. 下载并运行脚本

只需一行命令即可下载并运行脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/telegram_forward.sh | bash
```

> **注意**：此命令会自动下载脚本并执行。如果需要手动检查脚本内容，可以分步操作：
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/telegram_forward.sh -o telegram_forward.sh
> chmod +x telegram_forward.sh
> ./telegram_forward.sh
> ```

### 2. 使用交互式菜单

运行脚本后，你会看到以下菜单：

```plaintext
=== Telegram 消息转发管理工具 ===
1. 安装依赖
2. 配置脚本
3. 启动脚本
4. 停止脚本
5. 重启脚本
6. 查看日志
7. 退出
请选择一个选项：
```

#### 菜单选项说明

| 选项         | 功能描述                                   |
|--------------|--------------------------------------------|
| **1. 安装依赖** | 安装 Python、Telethon、supervisord 和日志管理工具。 |
| **2. 配置脚本** | 输入群组 Chat ID 和小号 API，生成转发脚本。 |
| **3. 启动脚本** | 启动消息转发，首次运行需登录小号。         |
| **4. 停止脚本** | 停止消息转发脚本。                         |
| **5. 重启脚本** | 重启消息转发脚本。                         |
| **6. 查看日志** | 实时查看转发日志（`/root/forward.log`）。  |
| **7. 退出**     | 退出程序。                                 |

## 🔑 获取 API 和 Chat ID

### 获取 `api_id` 和 `api_hash`

1. 访问 [my.telegram.org](https://my.telegram.org)，用小号登录。
2. 点击 **API development tools**，创建应用：
   - **App title**：`MyForwardApp`
   - **Short name**：`forward`
   - **Platform**：`Other`
   - **Description**：留空
3. 提交后，记录 `api_id`（例如 `25018336`）和 `api_hash`（例如 `f3dba3011e3b2f9a59e0bbeff20d5db9`）。

### 获取群组 Chat ID

1. 用大号创建私有群组，邀请小号加入。
2. 在 Telegram 中搜索 `@username_to_id_bot`，发送 `/start`。
3. 发送群组邀请链接（例如 `t.me/+xxxxx`）。
4. 记录返回的 Chat ID（例如 `-4688142035`）。

## ⚙️ 脚本工作原理

1. **监听消息**：脚本登录小号，监听私聊消息。
2. **消息转发**：将消息实时转发到指定群组。
3. **自动重启**：通过 `supervisord` 确保脚本持续运行。

## 📜 日志管理

- 日志文件：`/root/forward.log`
- 自动轮转：每天轮转，保留最近 7 天日志，旧日志会被压缩。

## ⚠️ 注意事项

- **首次运行**：需输入小号的手机号和验证码登录。
- **安全性**：保护好 `/root/session_*.session` 文件，避免泄露。
- **权限**：确保小号有权限向目标群组发送消息。
- **日志隐私**：脚本不记录消息内容，仅记录转发事件。

## 🛠️ 故障排除

- **转发失败**：
  1. 检查日志：`tail -f /root/forward.log`
  2. 确认小号是否在群组中，且有发送消息权限。
  3. 确保 `allowed_senders` 配置正确（留空则转发所有私聊消息）。
- **脚本未运行**：
  1. 检查进程：`supervisorctl status`
  2. 重启脚本：`supervisorctl restart forward`

## 📦 上传到 GitHub

1. 创建 GitHub 仓库（例如 `telegram-forward`）。
2. 提交文件：
   ```bash
   git init
   git add telegram_forward.sh README.md
   git commit -m "Initial commit"
   git remote add origin https://github.com/mqiancheng/telegram-forward.git
   git push -u origin main
   ```

## 🤝 贡献

欢迎提交 Issue 或 Pull Request，优化脚本功能！

## 📄 许可证

MIT License
