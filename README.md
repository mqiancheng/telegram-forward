Telegram 消息转发管理工具
这是一个用于管理 Telegram 消息转发的 Bash 脚本，支持多账号私聊消息实时转发到指定群组。脚本提供交互式菜单，方便安装依赖、配置脚本、启动/停止脚本、查看日志等操作。
功能

自动安装 Python 环境和 Telethon 库。
配置 Telegram 消息转发脚本（forward.py）。
使用 supervisord 管理脚本进程，支持自动重启。
使用 logrotate 自动管理日志。
提供交互式菜单，支持启动、停止、重启脚本以及查看日志。

前提条件

运行环境：Alpine Linux（其他 Linux 发行版需调整依赖安装命令）。
已安装 curl 和 bash。
服务器有网络连接，可以访问 Telegram API 和 GitHub。

安装和使用
1. 下载脚本
curl -fsSL https://raw.githubusercontent.com/你的用户名/telegram-forward/main/telegram_forward.sh -o telegram_forward.sh
chmod +x telegram_forward.sh

2. 运行脚本
./telegram_forward.sh

3. 操作菜单
运行脚本后，会显示以下菜单：
=== Telegram 消息转发管理工具 ===
1. 安装依赖
2. 配置脚本
3. 启动脚本
4. 停止脚本
5. 重启脚本
6. 查看日志
7. 退出
请选择一个选项：

选项说明：

安装依赖：
安装 Python、pip、Telethon、supervisord 和 logrotate。
配置 supervisord 和日志轮转。


配置脚本：
输入大号群组的 Chat ID、小号的 api_id 和 api_hash。
可选择是否只转发特定用户/机器人的消息。
自动生成 forward.py。


启动脚本：
启动消息转发脚本，首次运行需输入小号手机号和验证码。


停止脚本：
停止消息转发脚本。


重启脚本：
重启消息转发脚本。


查看日志：
实时查看转发日志（/root/forward.log）。


退出：
退出程序。



获取 API 和 Chat ID

获取 api_id 和 api_hash：
访问 my.telegram.org，用小号登录。
点击 API development tools，创建应用。
记录 api_id 和 api_hash。


获取群组 Chat ID：
用大号创建私有群组，邀请小号加入。
搜索 Telegram 机器人 @username_to_id_bot，发送群组邀请链接（t.me/+xxxxx）。
记录返回的 Chat ID（例如 -4688142035）。



注意事项

首次运行脚本时，需输入小号的手机号和验证码登录。
日志文件（/root/forward.log）会自动轮转，保留最近 7 天。
脚本使用 supervisord 管理进程，支持自动重启。
保护好 session_*.session 文件，避免泄露。

上传到 GitHub

创建 GitHub 仓库（例如 telegram-forward）。
将 telegram_forward.sh 和 README.md 上传：git init
git add telegram_forward.sh README.md
git commit -m "Initial commit"
git remote add origin https://github.com/你的用户名/telegram-forward.git
git push -u origin main


在 GitHub 仓库中查看和管理。

贡献
欢迎提交 Issue 或 Pull Request，优化脚本功能！
许可证
MIT License
