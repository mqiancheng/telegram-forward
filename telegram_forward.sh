#!/bin/bash

# 检查是否通过管道执行（例如 curl ... | bash）
if [ -p /proc/self/fd/0 ] && [ -z "$EXECUTED_ONCE" ]; then
    # 如果是通过管道执行，将脚本保存到临时文件
    export EXECUTED_ONCE=1
    TEMP_SCRIPT=$(mktemp /tmp/telegram_forward.XXXXXX)
    cat - > "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    # 执行临时脚本并传递参数
    exec bash "$TEMP_SCRIPT" "$@"
    exit 0
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本路径和文件
SCRIPT_DIR="/root"
FORWARD_PY="$SCRIPT_DIR/forward.py"
LOG_FILE="$SCRIPT_DIR/forward.log"
VENV_DIR="$SCRIPT_DIR/venv"

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}$1 未安装，正在安装...${NC}"
        apk add $1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在更新包索引...${NC}"
    apk update
    check_command python3
    check_command py3-pip
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${YELLOW}创建虚拟环境...${NC}"
        python3 -m venv $VENV_DIR
    fi
    source $VENV_DIR/bin/activate
    echo -e "${YELLOW}安装 Telethon...${NC}"
    pip install telethon --no-cache-dir
    echo -e "${YELLOW}安装 supervisord...${NC}"
    apk add supervisor
    echo -e "${GREEN}依赖安装完成！${NC}"
}

# 配置 forward.py 脚本
configure_script() {
    echo -e "${YELLOW}请输入大号群组的 Chat ID（例如 -4688142035）：${NC}"
    read target_chat_id
    echo -e "${YELLOW}请输入小号的 api_id（从 my.telegram.org 获取）：${NC}"
    read api_id
    echo -e "${YELLOW}请输入小号的 api_hash（从 my.telegram.org 获取）：${NC}"
    read api_hash
    echo -e "${YELLOW}是否只转发特定用户/机器人的消息？（y/n）：${NC}"
    read filter_senders
    allowed_senders="[]"
    if [ "$filter_senders" = "y" ]; then
        echo -e "${YELLOW}请输入用户名（例如 @HaxBot），多个用户用空格分隔：${NC}"
        read -a senders
        allowed_senders="["
        for sender in "${senders[@]}"; do
            allowed_senders="$allowed_senders'$sender', "
        done
        allowed_senders="${allowed_senders%, }]"
    fi

    # 创建 forward.py
    cat > $FORWARD_PY << EOL
from telethon import TelegramClient, events
import asyncio

# 大号的 Chat ID（消息的目标）
target_chat_id = $target_chat_id

# 每个账号的配置（api_id, api_hash, session 文件名）
accounts = [
    {
        'api_id': '$api_id',
        'api_hash': '$api_hash',
        'session': 'session_account1'
    },
]

# 可选：只转发特定用户/机器人的消息（留空则转发所有私聊消息）
allowed_senders = $allowed_senders

# 创建所有账号的客户端
clients = [TelegramClient(acc['session'], acc['api_id'], acc['api_hash']) for acc in accounts]

# 为每个客户端设置消息监听
for client in clients:
    if allowed_senders:  # 如果指定了消息来源
        @client.on(events.NewMessage(from_users=allowed_senders, chats=None))
        async def handler(event):
            # 实时转发消息到大号
            await client.forward_messages(target_chat_id, event.message)
            print(f"消息已转发 (来自 {event.sender_id})")
    else:  # 转发所有私聊消息
        @client.on(events.NewMessage(chats=None))
        async def handler(event):
            # 确保只转发私聊消息（排除群组/频道）
            if event.is_private:
                await client.forward_messages(target_chat_id, event.message)
                print(f"消息已转发 (来自 {event.sender_id})")

# 启动所有客户端
async def main():
    while True:
        try:
            for client in clients:
                await client.start()
            # 保持运行
            await asyncio.gather(*(client.run_until_disconnected() for client in clients))
        except Exception as e:
            print(f"脚本异常退出: {e}")
            print("将在 60 秒后重试...")
            await asyncio.sleep(60)

# 运行主程序
asyncio.run(main())
EOL
    echo -e "${GREEN}forward.py 已生成！${NC}"
}

# 配置 supervisord
configure_supervisord() {
    mkdir -p /etc/supervisor.d
    cat > /etc/supervisor.d/forward.ini << EOL
[program:forward]
command=$VENV_DIR/bin/python $FORWARD_PY
directory=$SCRIPT_DIR
autostart=true
autorestart=true
startsecs=10
stopwaitsecs=10
stdout_logfile=$LOG_FILE
stderr_logfile=$LOG_FILE
EOL
    echo -e "${GREEN}supervisord 已配置！${NC}"
}

# 配置日志轮转
configure_logrotate() {
    cat > /etc/logrotate.d/forward << EOL
$LOG_FILE {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOL
    echo -e "${GREEN}日志轮转已配置！${NC}"
}

# 启动脚本
start_script() {
    supervisord -c /etc/supervisord.conf &> /dev/null
    supervisorctl start forward
    echo -e "${GREEN}脚本已启动！${NC}"
}

# 停止脚本
stop_script() {
    supervisorctl stop forward
    echo -e "${GREEN}脚本已停止！${NC}"
}

# 重启脚本
restart_script() {
    supervisorctl restart forward
    echo -e "${GREEN}脚本已重启！${NC}"
}

# 查看日志
view_log() {
    tail -f $LOG_FILE
}

# 主菜单
while true; do
    echo -e "${YELLOW}=== Telegram 消息转发管理工具 ===${NC}"
    echo "1. 安装依赖"
    echo "2. 配置脚本"
    echo "3. 启动脚本"
    echo "4. 停止脚本"
    echo "5. 重启脚本"
    echo "6. 查看日志"
    echo "7. 退出"
    echo -e "${YELLOW}请选择一个选项：${NC}"
    read choice

    case $choice in
        1)
            install_dependencies
            configure_supervisord
            configure_logrotate
            ;;
        2)
            configure_script
            ;;
        3)
            start_script
            ;;
        4)
            stop_script
            ;;
        5)
            restart_script
            ;;
        6)
            view_log
            ;;
        7)
            echo -e "${GREEN}退出程序${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重试！${NC}"
            ;;
    esac
done
