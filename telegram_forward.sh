#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本版本号
SCRIPT_VERSION="1.0.6"

# 脚本路径和文件
SCRIPT_DIR="/root"
FORWARD_PY="$SCRIPT_DIR/forward.py"
LOG_FILE="$SCRIPT_DIR/forward.log"
VENV_DIR="$SCRIPT_DIR/venv"
SELF_SCRIPT="$0" # 当前脚本路径
SUPERVISORD_CONF="/etc/supervisord.conf"

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}$1 未安装，正在安装...${NC}"
        apk add $1
    fi
}

# 检查脚本运行状态
check_script_status() {
    # 首先检查 supervisord 是否运行
    if pgrep -f "supervisord" > /dev/null; then
        # 检查 forward 任务状态
        if supervisorctl status forward 2>/dev/null | grep -q "RUNNING"; then
            echo -e "${GREEN}脚本正在运行${NC}"
        else
            echo -e "${RED}脚本未运行${NC}"
        fi
    else
        # 如果 supervisord 未运行，检查是否有 forward.py 的 Python 进程
        if pgrep -f "python.*forward.py" > /dev/null; then
            echo -e "${GREEN}脚本正在运行${NC}"
        else
            echo -e "${RED}脚本未运行${NC}"
        fi
    fi
}

# 检查虚拟环境状态
check_venv_status() {
    if [ -d "$VENV_DIR" ]; then
        echo -e "${GREEN}虚拟环境已创建${NC}"
    else
        echo -e "${RED}虚拟环境未创建${NC}"
    fi
}

# 检查 forward.py 是否存在
check_config_status() {
    if [ -f "$FORWARD_PY" ]; then
        echo -e "${GREEN}脚本已配置（forward.py 存在）${NC}"
    else
        echo -e "${RED}脚本未配置（forward.py 不存在）${NC}"
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

    # 初始化 accounts 数组
    accounts=()
    account_index=1

    # 循环添加小号
    while true; do
        echo -e "${YELLOW}请输入小号${account_index}的 api_id（从 my.telegram.org 获取）：${NC}"
        read api_id
        echo -e "${YELLOW}请输入小号${account_index}的 api_hash（从 my.telegram.org 获取）：${NC}"
        read api_hash

        # 添加小号到 accounts 数组（使用正确的换行格式）
        account_entry="    {
        'api_id': '$api_id',
        'api_hash': '$api_hash',
        'session': 'session_account${account_index}'
    }"
        accounts+=("$account_entry")

        # 询问是否继续添加小号，回车默认为 y
        echo -e "${YELLOW}是否继续添加小号？（y/n，回车默认为 y）：${NC}"
        read continue_adding
        # 如果用户直接按回车，设置默认值为 y
        if [ -z "$continue_adding" ]; then
            continue_adding="y"
        fi
        if [ "$continue_adding" != "y" ]; then
            break
        fi
        account_index=$((account_index + 1))
    done

    # 将 accounts 数组转换为字符串，添加逗号和换行
    IFS=","
    accounts_str=$(echo "${accounts[*]}")
    unset IFS

    # 询问是否只转发特定用户/机器人的消息，回车默认为 y
    echo -e "${YELLOW}是否只转发特定用户/机器人的消息？（y/n，回车默认为 y）：${NC}"
    read filter_senders
    # 如果用户直接按回车，设置默认值为 y
    if [ -z "$filter_senders" ]; then
        filter_senders="y"
    fi
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
$accounts_str
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

    # 配置完成后自动启动脚本
    echo -e "${YELLOW}正在自动启动脚本...${NC}"
    start_script
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
    # 清理可能的残留进程和状态
    pkill -f "supervisord" 2>/dev/null
    pkill -f "python.*forward.py" 2>/dev/null
    # 删除 supervisord 的 pid 文件（如果存在）
    if [ -f "/var/run/supervisord.pid" ]; then
        rm -f /var/run/supervisord.pid 2>/dev/null
    fi

    # 检查 supervisord 是否已经在运行
    if ! pgrep -f "supervisord" > /dev/null; then
        supervisord -c $SUPERVISORD_CONF &> /dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}supervisord 已启动${NC}"
        else
            echo -e "${RED}supervisord 启动失败${NC}"
            return 1
        fi
    fi

    # 检查 forward 任务状态
    if supervisorctl status forward 2>/dev/null | grep -q "RUNNING"; then
        echo -e "${YELLOW}脚本已在运行，无需重复启动${NC}"
    else
        supervisorctl start forward 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}脚本已启动！${NC}"
        else
            echo -e "${RED}脚本启动失败，请检查配置或日志${NC}"
        fi
    fi

    # 延迟6秒后再次检查状态
    echo -e "${YELLOW}正在等待服务启动...${NC}"
    sleep 6
}

# 停止脚本
stop_script() {
    # 停止 forward 任务
    if supervisorctl status forward 2>/dev/null | grep -q "RUNNING"; then
        supervisorctl stop forward 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}forward 任务已停止${NC}"
        else
            echo -e "${RED}停止 forward 任务失败${NC}"
        fi
    fi

    # 杀死 supervisord 和 forward.py 进程
    pkill -f "supervisord" 2>/dev/null
    pkill -f "python.*forward.py" 2>/dev/null

    # 删除 supervisord 的 pid 文件（如果存在）
    if [ -f "/var/run/supervisord.pid" ]; then
        rm -f /var/run/supervisord.pid 2>/dev/null
    fi

    # 延迟6秒后再次检查状态
    echo -e "${YELLOW}正在等待服务停止...${NC}"
    sleep 6

    # 再次检查是否仍有进程
    if pgrep -f "supervisord" > /dev/null || pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "${RED}停止脚本失败，某些进程仍在运行${NC}"
    else
        echo -e "${GREEN}脚本已停止！${NC}"
    fi
}

# 重启脚本
restart_script() {
    # 先停止脚本
    stop_script
    # 再启动脚本
    start_script
}

# 查看日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}正在查看日志（按 q 退出）...${NC}"
        less $LOG_FILE
        echo -e "${GREEN}日志查看完成！${NC}"
    else
        echo -e "${RED}日志文件不存在！${NC}"
    fi
}

# 查看配置（以 nano 打开 forward.py）
view_config() {
    if [ -f "$FORWARD_PY" ]; then
        nano $FORWARD_PY
        echo -e "${GREEN}配置已保存！${NC}"
    else
        echo -e "${RED}forward.py 文件不存在，请先配置脚本！${NC}"
    fi
}

# 卸载脚本
uninstall_script() {
    echo -e "${RED}警告：卸载脚本将删除所有相关文件和配置，包括 forward.py、日志、虚拟环境等！${NC}"
    echo -e "${YELLOW}是否确认卸载脚本？（y/n，回车默认为 n）：${NC}"
    read confirm_uninstall
    # 如果用户直接按回车，设置默认值为 n
    if [ -z "$confirm_uninstall" ]; then
        confirm_uninstall="n"
    fi

    if [ "$confirm_uninstall" != "y" ]; then
        echo -e "${GREEN}已取消卸载操作！${NC}"
        return
    fi

    echo -e "${YELLOW}正在停止脚本和相关进程...${NC}"
    # 停止 supervisord 和 forward 进程
    if command -v supervisorctl &> /dev/null; then
        supervisorctl stop forward 2>/dev/null
        pkill -f "supervisord" 2>/dev/null
    fi
    # 杀死所有相关 Python 进程（forward.py）
    pkill -f "python.*forward.py" 2>/dev/null

    echo -e "${YELLOW}正在删除相关文件和配置...${NC}"
    # 删除 forward.py
    [ -f "$FORWARD_PY" ] && rm -f "$FORWARD_PY" && echo -e "${GREEN}已删除 forward.py${NC}"
    # 删除日志文件
    [ -f "$LOG_FILE" ] && rm -f "$LOG_FILE" && echo -e "${GREEN}已删除日志文件${NC}"
    # 删除虚拟环境
    [ -d "$VENV_DIR" ] && rm -rf "$VENV_DIR" && echo -e "${GREEN}已删除虚拟环境${NC}"
    # 删除 supervisord 配置文件
    [ -f "/etc/supervisor.d/forward.ini" ] && rm -f "/etc/supervisor.d/forward.ini" && echo -e "${GREEN}已删除 supervisord 配置文件${NC}"
    # 删除日志轮转配置文件
    [ -f "/etc/logrotate.d/forward" ] && rm -f "/etc/logrotate.d/forward" && echo -e "${GREEN}已删除日志轮转配置文件${NC}"
    # 删除 Telegram 会话文件
    rm -f "$SCRIPT_DIR/session_account*.session" 2>/dev/null && echo -e "${GREEN}已删除会话文件${NC}"

    echo -e "${YELLOW}正在卸载相关程序...${NC}"
    # 卸载 supervisor
    if command -v apk &> /dev/null; then
        apk del supervisor 2>/dev/null && echo -e "${GREEN}已卸载 supervisor${NC}"
    fi

    echo -e "${YELLOW}正在删除脚本自身...${NC}"
    # 删除脚本自身
    rm -f "$SELF_SCRIPT" && echo -e "${GREEN}脚本已删除！${NC}"

    echo -e "${GREEN}卸载完成！程序即将退出。${NC}"
    exit 0
}

# 主菜单
show_menu() {
    echo -e "${YELLOW}=== Telegram 消息转发管理工具 ===${NC}"
    echo -e "${YELLOW}版本: $SCRIPT_VERSION${NC}"
    echo -e "${YELLOW}--- 当前状态 ---${NC}"
    check_script_status
    check_venv_status
    check_config_status
    echo -e "${YELLOW}----------------${NC}"
    echo "1. 安装依赖"
    echo "2. 配置脚本"
    echo "3. 启动脚本"
    echo "4. 停止脚本"
    echo "5. 重启脚本"
    echo "6. 查看配置"
    echo "7. 查看日志（按q可退出查看日志）"
    echo "8. 卸载脚本"
    echo "9. 退出"
    echo -e "${YELLOW}请选择一个选项：${NC}"
}

# 主循环
while true; do
    show_menu
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
            stop_script
            start_script
            ;;
        6)
            view_config
            ;;
        7)
            view_log
            ;;
        8)
            uninstall_script
            ;;
        9)
            echo -e "${GREEN}退出程序${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重试！${NC}"
            ;;
    esac
done
