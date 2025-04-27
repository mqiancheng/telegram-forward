# Telegram 消息转发管理工具 🚀

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Version](https://img.shields.io/badge/version-1.3.0-brightgreen.svg)
![Platform](https://img.shields.io/badge/platform-Linux-green.svg)

这是一个用于管理 Telegram 消息转发的 Bash 脚本，支持多账号私聊消息实时转发到指定群组。通过交互式菜单，你可以轻松安装依赖、配置脚本、启动/停止脚本、查看日志等。

## ✨ 功能特性

- **多系统支持**：兼容 Alpine、Ubuntu/Debian、CentOS/RHEL/Fedora 等多种 Linux 发行版。
- **依赖安装**：自动安装 Python、Telethon 和 supervisord，自动检测系统类型。
- **脚本配置**：生成 Telegram 消息转发脚本，支持多账号。
- **进程管理**：使用 `supervisord` 管理脚本，支持自动重启。
- **日志管理**：通过 `logrotate` 自动轮转日志，节省空间。
- **配置备份**：支持配置和会话文件的备份与恢复。
- **系统诊断**：提供系统信息和网络连接测试。
- **交互式菜单**：一键操作，简单易用。

## 📋 前提条件

确保你的服务器满足以下条件：

- **操作系统**：支持 Alpine、Ubuntu/Debian、CentOS/RHEL/Fedora 等主流 Linux 发行版。
- **工具**：已安装 `curl` 和 `bash`。
- **网络**：可以访问 Telegram API 和 GitHub。
- **权限**：需要有安装软件包的权限（通常需要 sudo 或 root）。

## 🚀 快速开始

### 1. 下载并运行脚本

> ```bash
> curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/telegram_forward.sh -o telegram_forward.sh && chmod +x telegram_forward.sh && ./telegram_forward.sh
> ```

### 2. 使用交互式菜单

运行脚本后，你会看到以下菜单：

```plaintext
=== Telegram 消息转发管理工具 ===
版本: 1.3.0
--- 当前状态 ---
脚本未运行
supervisord 未运行
虚拟环境已创建
脚本已配置（forward.py 存在）
停止脚本时将同时停止 supervisord
----------------
1. 安装依赖
2. 配置管理
3. 启动脚本
4. 停止脚本
5. 重启脚本
6. 查看日志（按q可退出查看日志）
7. 切换 supervisord 停止设置
8. 系统信息
9. 卸载脚本
0. 退出
请选择一个选项：
```

#### 菜单选项说明

| 选项                      | 功能描述                                   |
|---------------------------|--------------------------------------------|
| **1. 安装依赖**           | 安装 Python、Telethon、supervisord 和日志管理工具。 |
| **2. 配置管理**           | 进入配置管理子菜单，可以新建、修改、备份和恢复配置。 |
| **3. 启动脚本**           | 启动消息转发，首次运行需登录小号。如果配置文件不存在，会提示先配置。 |
| **4. 停止脚本**           | 停止消息转发脚本。                         |
| **5. 重启脚本**           | 重启消息转发脚本。如果配置文件不存在，会提示先配置。 |
| **6. 查看日志**           | 实时查看转发日志。                         |
| **7. 切换 supervisord 设置** | 切换停止脚本时是否同时停止 supervisord。   |
| **8. 系统信息**           | 显示系统信息和网络连接测试结果。           |
| **9. 卸载脚本**           | 卸载脚本及相关文件，但保留备份文件。       |
| **0. 退出**               | 退出程序。                                 |

#### 配置管理子菜单

选择主菜单中的"2. 配置管理"后，会进入以下子菜单：

```plaintext
=== 配置管理菜单 ===
1. 新建配置
2. 修改配置
3. 备份配置
4. 恢复配置
0. 返回主菜单
请选择一个选项：
```

| 选项                | 功能描述                                   |
|---------------------|--------------------------------------------|
| **1. 新建配置**     | 输入群组 Chat ID 和小号 API，生成转发脚本。 |
| **2. 修改配置**     | 使用文本编辑器查看和编辑 forward.py 文件。  |
| **3. 备份配置**     | 备份脚本配置和会话文件。                   |
| **4. 恢复配置**     | 从备份文件恢复配置到项目目录。             |
| **0. 返回主菜单**   | 返回到主菜单。                             |

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
4. **配置持久化**：用户设置会保存到配置文件，重启后自动加载。
5. **多系统适配**：自动检测系统类型，使用对应的包管理器和配置路径。

## 📜 日志管理

- 日志文件：位于用户主目录下的 `forward.log`
- 自动轮转：每天轮转，保留最近 7 天日志，旧日志会被压缩。
- 查看方式：通过菜单选项 7 可以方便地查看日志。

## 💾 备份与恢复

脚本提供了配置备份和恢复功能，可以备份以下内容：

- forward.py 脚本文件
- Telegram 会话文件（session_account*.session）
- 用户配置文件

备份文件保存在用户主目录下的 `backup` 文件夹中，格式为 `forward_backup_YYYYMMDD_HHMMSS.tar.gz`。

## ⚠️ 注意事项

- **首次运行**：需输入小号的手机号和验证码登录。
- **安全性**：保护好会话文件（`session_*.session`），避免泄露。
- **权限**：确保小号有权限向目标群组发送消息。
- **日志隐私**：脚本不记录消息内容，仅记录转发事件。
- **系统兼容性**：脚本会自动检测系统类型，但在某些特殊环境可能需要手动调整。
- **Supervisord 设置**：如果系统中有其他应用也使用 supervisord，可以通过菜单选项 9 修改停止行为。

## 🛠️ 故障排除

- **转发失败**：
  1. 使用菜单选项 7 查看日志。
  2. 使用菜单选项 10 检查系统信息和网络连接。
  3. 确认小号是否在群组中，且有发送消息权限。
  4. 确保 `allowed_senders` 配置正确（留空则转发所有私聊消息）。

- **脚本未运行**：
  1. 使用菜单选项 10 检查系统状态。
  2. 使用菜单选项 5 重启脚本。
  3. 检查日志查找错误信息。

- **依赖安装失败**：
  1. 确保系统有足够的权限安装软件包。
  2. 检查网络连接是否正常。
  3. 对于不支持的系统，可能需要手动安装依赖。

- **配置恢复失败**：
  1. 确保备份文件完整且未损坏。
  2. 尝试手动解压备份文件并复制到正确位置。

## 📦 上传到 GitHub

1. 创建 GitHub 仓库（例如 `telegram-forward`）。
2. 提交文件：
   ```bash
   git init
   git add telegram_forward.sh README.md LICENSE
   git commit -m "Initial commit"
   git remote add origin https://github.com/mqiancheng/telegram-forward.git
   git push -u origin main
   ```

## 🔄 更新日志

### 版本 1.3.0
- 优化菜单结构，合并配置相关功能到统一的配置管理菜单
- 改进恢复配置功能，确保从备份目录复制到项目目录
- 在启动脚本时添加配置文件检查，提示用户先配置
- 改进卸载功能，保留备份文件但删除其他所有项目相关文件
- 确保卸载时退出虚拟环境
- 更新文档，反映新的菜单结构和功能

### 版本 1.2.0
- 添加多系统支持（Alpine、Ubuntu/Debian、CentOS/RHEL/Fedora）
- 增强错误处理和恢复机制
- 添加配置备份和恢复功能
- 添加系统信息和网络连接测试
- 改进 supervisord 管理
- 配置持久化保存
- 更新文档

### 版本 1.1.0
- 添加 supervisord 停止设置
- 改进进程管理
- 修复进程残留问题

### 版本 1.0.7
- 初始版本

## 🤝 贡献

欢迎提交 Issue 或 Pull Request，优化脚本功能！如果你有任何建议或发现了 bug，请在 GitHub 上提交 Issue。

## 📄 许可证

MIT License
