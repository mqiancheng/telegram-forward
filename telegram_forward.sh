#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本版本号
SCRIPT_VERSION="1.5.5"

# 检测当前用户的主目录
if [ "$HOME" = "/root" ]; then
    USER_HOME="/root"
else
    USER_HOME="$HOME"
fi

# 脚本路径和文件
SCRIPT_DIR="$USER_HOME"
FORWARD_PY="$SCRIPT_DIR/forward.py"
LOG_FILE="$SCRIPT_DIR/forward.log"
VENV_DIR="$SCRIPT_DIR/venv"
SELF_SCRIPT="$0" # 当前脚本路径
CONFIG_FILE="$SCRIPT_DIR/.telegram_forward.conf"
BACKUP_DIR="/home/backup-TGfw" # 新的备份目录

# 检测系统类型
if [ -f "/etc/os-release" ]; then
    . /etc/os-release
    OS_TYPE="$ID"
else
    OS_TYPE="unknown"
fi

# 系统类型已检测完成

# 加载配置文件（如果存在）
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# 检查命令是否存在并安装（支持多种包管理器）
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}$1 未安装，正在安装...${NC}"

        # 根据系统类型使用不同的包管理器
        if [ "$OS_TYPE" = "alpine" ]; then
            apk add $1
        elif [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
            apt-get update && apt-get install -y $1
        elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
            if command -v dnf &> /dev/null; then
                dnf install -y $1
            else
                yum install -y $1
            fi
        else
            echo -e "${RED}无法确定系统类型，请手动安装 $1${NC}"
            return 1
        fi

        # 检查安装是否成功
        if ! command -v $1 &> /dev/null; then
            echo -e "${RED}安装 $1 失败，请手动安装${NC}"
            return 1
        fi
    fi
    return 0
}

# 检查脚本运行状态
check_script_status() {
    local max_retries=3
    local retry_delay=2
    local status="未知"

    for ((i=1; i<=$max_retries; i++)); do
        # 检查 PID 文件
        if [ -f "$SCRIPT_DIR/forward.pid" ]; then
            pid=$(cat "$SCRIPT_DIR/forward.pid")
            if ps -p $pid > /dev/null; then
                status="运行中"
                break
            fi
        # 直接检查 Python 进程
        elif pgrep -f "python.*forward.py" > /dev/null; then
            status="运行中"
            break
        fi

        if [ $i -lt $max_retries ]; then
            sleep $retry_delay
        fi
    done

    case "$status" in
        "运行中") echo -e "${GREEN}脚本正在运行${NC}" ;;
        "已停止") echo -e "${RED}脚本未运行${NC}" ;;
        *) echo -e "${RED}脚本未运行${NC}" ;;
    esac
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

    # 根据系统类型更新包索引
    if [ "$OS_TYPE" = "alpine" ]; then
        apk update
    elif [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
        apt-get update
    elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
        if command -v dnf &> /dev/null; then
            dnf check-update
        else
            yum check-update
        fi
    fi

    # 安装 Python 和 pip
    if [ "$OS_TYPE" = "alpine" ]; then
        check_command python3
        # 在 Alpine 中，py3-pip 可能不会提供独立的 pip 命令
        if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
            echo -e "${YELLOW}正在安装 pip...${NC}"
            apk add py3-pip
            # 如果仍然没有 pip 命令，创建一个符号链接
            if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
                if [ -f "/usr/bin/python3" ]; then
                    echo -e "${YELLOW}创建 pip 符号链接...${NC}"
                    ln -sf /usr/bin/python3 /usr/local/bin/pip3
                    chmod +x /usr/local/bin/pip3
                    echo '#!/bin/sh
python3 -m pip "$@"' > /usr/local/bin/pip3
                    chmod +x /usr/local/bin/pip3
                    ln -sf /usr/local/bin/pip3 /usr/local/bin/pip
                fi
            fi
        fi
    elif [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
        check_command python3
        check_command python3-pip
    elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
        check_command python3
        check_command python3-pip
    else
        echo -e "${YELLOW}请确保已安装 Python3 和 pip${NC}"
    fi

    # 安装 venv 模块（某些系统中可能需要单独安装）
    if [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
        apt-get install -y python3-venv
    elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
        if command -v dnf &> /dev/null; then
            dnf install -y python3-virtualenv
        else
            yum install -y python3-virtualenv
        fi
    fi

    # 创建虚拟环境
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${YELLOW}创建虚拟环境...${NC}"
        python3 -m venv $VENV_DIR
        if [ $? -ne 0 ]; then
            echo -e "${RED}创建虚拟环境失败，请检查 Python 安装${NC}"
            return 1
        fi
    fi

    # 激活虚拟环境
    if [ -f "$VENV_DIR/bin/activate" ]; then
        source $VENV_DIR/bin/activate
    else
        echo -e "${RED}虚拟环境激活脚本不存在${NC}"
        return 1
    fi

    # 安装 Telethon
    echo -e "${YELLOW}安装 Telethon...${NC}"
    pip install telethon --no-cache-dir
    if [ $? -ne 0 ]; then
        echo -e "${RED}安装 Telethon 失败${NC}"
        return 1
    fi

    # 创建启动和停止脚本
    echo -e "${YELLOW}创建启动和停止脚本...${NC}"

    # 创建目录
    mkdir -p "$SCRIPT_DIR/bin"

    # 创建启动脚本（包含自动重启功能）
    cat > "$SCRIPT_DIR/bin/run_forward.sh" << EOL
#!/bin/sh
# 自动生成的启动脚本
cd "$SCRIPT_DIR"
source "$VENV_DIR/bin/activate"

# 启动脚本并保存PID
start_script() {
    python "$FORWARD_PY" >> "$LOG_FILE" 2>&1 &
    echo \$! > "$SCRIPT_DIR/forward.pid"
    echo "转发脚本已启动，PID: \$(cat "$SCRIPT_DIR/forward.pid")"
}

# 检查脚本是否在运行
check_script() {
    if [ -f "$SCRIPT_DIR/forward.pid" ]; then
        pid=\$(cat "$SCRIPT_DIR/forward.pid")
        if ps -p \$pid > /dev/null; then
            return 0  # 脚本正在运行
        fi
    fi
    return 1  # 脚本未运行
}

# 启动脚本
start_script

# 启动监控进程，如果脚本停止则自动重启
(
    while true; do
        sleep 30
        if ! check_script; then
            echo "\$(date): 检测到脚本已停止，正在重启..." >> "$LOG_FILE"
            start_script
        fi
    done
) &
echo \$! > "$SCRIPT_DIR/monitor.pid"
EOL
    chmod +x "$SCRIPT_DIR/bin/run_forward.sh"

    # 创建停止脚本
    cat > "$SCRIPT_DIR/bin/stop_forward.sh" << EOL
#!/bin/sh
# 自动生成的停止脚本
# 停止监控进程
if [ -f "$SCRIPT_DIR/monitor.pid" ]; then
    pid=\$(cat "$SCRIPT_DIR/monitor.pid")
    if ps -p \$pid > /dev/null; then
        kill \$pid
        echo "已停止监控进程，PID: \$pid"
    fi
    rm -f "$SCRIPT_DIR/monitor.pid"
fi

# 停止主脚本
if [ -f "$SCRIPT_DIR/forward.pid" ]; then
    pid=\$(cat "$SCRIPT_DIR/forward.pid")
    if ps -p \$pid > /dev/null; then
        kill \$pid
        echo "已停止转发脚本，PID: \$pid"
    else
        echo "转发脚本未运行"
    fi
    rm -f "$SCRIPT_DIR/forward.pid"
else
    echo "找不到 PID 文件，尝试查找并终止进程..."
    pkill -f "python.*forward.py"
fi
EOL
    chmod +x "$SCRIPT_DIR/bin/stop_forward.sh"

    echo -e "${GREEN}启动和停止脚本已创建${NC}"

    # 创建快捷命令
    create_shortcut

    echo -e "${GREEN}依赖安装完成！${NC}"
    return 0
}

# 配置 forward.py 脚本
configure_script() {
    # 停止任何可能正在运行的脚本
    stop_script > /dev/null 2>&1

    echo -e "${YELLOW}=== 配置 Telegram 转发脚本 ===${NC}"
    echo -e "${YELLOW}第一步：配置大号群组${NC}"
    echo -e "${YELLOW}请输入大号群组/个人的 Chat ID（例如 -4688142035）：${NC}"
    read target_chat_id

    # 初始化 accounts 数组
    accounts=()
    account_index=1

    echo -e "${YELLOW}=== 第二步：配置小号 ===${NC}"

    # 循环添加小号
    while true; do
        echo -e "${YELLOW}正在配置小号 ${account_index}${NC}"
        echo -e "${YELLOW}请输入小号${account_index}的 api_id（从 my.telegram.org 获取）：${NC}"
        read api_id
        echo -e "${YELLOW}请输入小号${account_index}的 api_hash（从 my.telegram.org 获取）：${NC}"
        read api_hash

        # 创建会话文件目录（如果不存在）
        session_name="session_account${account_index}"

        # 添加小号到 accounts 数组（使用正确的换行格式）
        account_entry="    {
        'api_id': '$api_id',
        'api_hash': '$api_hash',
        'session': '$session_name'
    }"
        accounts+=("$account_entry")

        # 询问是否继续添加小号，回车默认为 n
        echo -e "${YELLOW}是否继续添加小号？（y/n，回车默认为 n）：${NC}"
        read continue_adding
        # 如果用户直接按回车，设置默认值为 n
        if [ -z "$continue_adding" ]; then
            continue_adding="n"
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

    echo -e "${YELLOW}=== 第三步：配置转发规则 ===${NC}"

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
    cat > $FORWARD_PY << 'EOPY'
from telethon import TelegramClient, events
import asyncio

# 大号的 Chat ID（消息的目标）
target_chat_id = TARGET_CHAT_ID

# 每个账号的配置（api_id, api_hash, session 文件名）
accounts = [
ACCOUNTS_STR
]

# 可选：只转发特定用户/机器人的消息（留空则转发所有私聊消息）
allowed_senders = ALLOWED_SENDERS

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
EOPY
    # 替换模板中的变量
    sed -i "s|TARGET_CHAT_ID|$target_chat_id|g" "$FORWARD_PY"
    sed -i "s|ACCOUNTS_STR|$accounts_str|g" "$FORWARD_PY"
    # 使用不同的分隔符避免与内容冲突
    sed -i "s~ALLOWED_SENDERS~$allowed_senders~g" "$FORWARD_PY"
    echo -e "${GREEN}forward.py 已生成！${NC}"

    # 配置完成后进行会话验证
    echo -e "${YELLOW}=== 第四步：验证小号会话 ===${NC}"
    echo -e "${YELLOW}现在需要验证每个小号的会话，请按照提示操作${NC}"

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 为每个小号创建验证脚本
    for i in $(seq 1 $account_index); do
        session_name="session_account$i"
        api_id=$(echo "$accounts_str" | grep -o "'api_id': '[^']*'" | sed -n "${i}p" | cut -d "'" -f 4)
        api_hash=$(echo "$accounts_str" | grep -o "'api_hash': '[^']*'" | sed -n "${i}p" | cut -d "'" -f 4)

        echo -e "${YELLOW}正在验证小号 $i 的会话...${NC}"

        # 创建临时验证脚本
        cat > /tmp/verify_session.py << EOL
from telethon import TelegramClient
import asyncio

async def main():
    client = TelegramClient('$session_name', $api_id, '$api_hash')
    await client.start()
    me = await client.get_me()
    print(f"成功登录为: {me.first_name} (@{me.username})")
    await client.disconnect()

asyncio.run(main())
EOL

        # 运行验证脚本
        python3 /tmp/verify_session.py

        # 删除临时脚本
        rm -f /tmp/verify_session.py
    done

    # 退出虚拟环境
    deactivate

    echo -e "${GREEN}所有小号会话验证完成！${NC}"
    echo -e "${YELLOW}正在启动转发脚本...${NC}"
    sleep 2  # 确保配置文件已写入

    # 启动脚本（使用静默模式）
    start_script true

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}转发脚本已成功启动！${NC}"
        echo -e "${YELLOW}配置完成，正在返回主菜单...${NC}"
        sleep 2
    else
        echo -e "${RED}转发脚本启动失败，请检查日志${NC}"
        echo -e "${YELLOW}请使用主菜单中的选项 7 查看日志以获取详细错误信息${NC}"
    fi
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
    # 可选参数：是否静默模式
    local silent_mode=${1:-false}

    if [ "$silent_mode" != "true" ]; then
        echo -e "${YELLOW}正在启动服务...${NC}"
    fi

    # 检查 forward.py 是否存在
    if [ ! -f "$FORWARD_PY" ]; then
        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}forward.py 文件不存在，请先配置脚本！${NC}"
        fi
        return 1
    fi

    # 检查虚拟环境是否存在
    if [ ! -d "$VENV_DIR" ]; then
        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}虚拟环境不存在，请先安装依赖！${NC}"
        fi
        return 1
    fi

    # 清理残留进程和状态文件
    if [ "$silent_mode" != "true" ]; then
        cleanup_processes
    else
        cleanup_processes > /dev/null 2>&1
    fi

    # 使用脚本启动
    if [ "$silent_mode" != "true" ]; then
        echo -e "${YELLOW}正在启动转发脚本...${NC}"
    fi

    if [ -f "$SCRIPT_DIR/bin/run_forward.sh" ]; then
        if [ "$silent_mode" = "true" ]; then
            $SCRIPT_DIR/bin/run_forward.sh > /dev/null 2>&1
        else
            $SCRIPT_DIR/bin/run_forward.sh
        fi
        sleep 2

        # 检查脚本是否成功启动
        if [ -f "$SCRIPT_DIR/forward.pid" ] && ps -p $(cat "$SCRIPT_DIR/forward.pid") > /dev/null; then
            if [ "$silent_mode" != "true" ]; then
                echo -e "${GREEN}脚本已成功启动！${NC}"
            fi
        else
            if [ "$silent_mode" != "true" ]; then
                echo -e "${RED}脚本启动失败，请检查日志${NC}"
                echo -e "${YELLOW}可能的原因：${NC}"
                echo -e "1. Telegram API 凭证错误"
                echo -e "2. 网络连接问题"
                echo -e "3. Python 依赖问题"
                echo -e "${YELLOW}请使用选项 7 查看日志以获取详细错误信息${NC}"
            fi
            return 1
        fi
    else
        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}找不到启动脚本，请重新安装依赖${NC}"
        fi
        return 1
    fi

    return 0
}

# 停止脚本
stop_script() {
    echo -e "${YELLOW}正在停止服务...${NC}"

    # 使用脚本停止
    if [ -f "$SCRIPT_DIR/bin/stop_forward.sh" ]; then
        $SCRIPT_DIR/bin/stop_forward.sh
    else
        echo -e "${YELLOW}找不到停止脚本，尝试直接终止进程...${NC}"
    fi

    # 停止所有 run_forward.sh 进程
    if pgrep -f "run_forward.sh" > /dev/null; then
        echo -e "${YELLOW}正在停止 run_forward.sh 进程...${NC}"
        pkill -f "run_forward.sh" 2>/dev/null
        sleep 1
    fi

    # 停止所有 forward.py 进程
    if pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "${YELLOW}正在停止 forward.py 进程...${NC}"
        pkill -f "python.*forward.py" 2>/dev/null
        sleep 1
    fi

    # 清理可能残留的进程
    cleanup_processes

    # 验证 forward.py 停止状态
    if ! pgrep -f "python.*forward.py" > /dev/null && ! pgrep -f "run_forward.sh" > /dev/null; then
        echo -e "${GREEN}所有转发脚本已成功停止！${NC}"
    else
        echo -e "${RED}部分转发脚本停止失败，尝试强制终止...${NC}"
        pkill -9 -f "python.*forward.py" 2>/dev/null
        pkill -9 -f "run_forward.sh" 2>/dev/null
        sleep 1

        if ! pgrep -f "python.*forward.py" > /dev/null && ! pgrep -f "run_forward.sh" > /dev/null; then
            echo -e "${GREEN}所有转发脚本已强制停止！${NC}"
        else
            echo -e "${RED}无法停止所有转发脚本，请手动检查进程${NC}"
            return 1
        fi
    fi

    # 删除所有 PID 文件
    if [ -f "$SCRIPT_DIR/forward.pid" ]; then
        rm -f "$SCRIPT_DIR/forward.pid"
    fi

    if [ -f "$SCRIPT_DIR/monitor.pid" ]; then
        rm -f "$SCRIPT_DIR/monitor.pid"
    fi

    return 0
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

# 创建快捷命令
create_shortcut() {
    echo -e "${YELLOW}正在创建快捷命令 'tg'...${NC}"

    # 检查是否已存在
    if [ -f "/usr/local/bin/tg" ]; then
        echo -e "${YELLOW}快捷命令 'tg' 已存在，正在更新...${NC}"
    fi

    # 创建快捷命令
    cat > /usr/local/bin/tg << EOL
#!/bin/bash
# Telegram 消息转发管理工具快捷命令
$SELF_SCRIPT
EOL

    # 设置执行权限
    chmod +x /usr/local/bin/tg

    echo -e "${GREEN}快捷命令 'tg' 已创建，您可以在任何位置输入 'tg' 来启动脚本${NC}"
}

# 管理备份文件
manage_backups() {
    echo -e "${YELLOW}=== 备份文件管理 ===${NC}"

    # 检查备份目录
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}备份目录不存在${NC}"
        return 1
    fi

    # 列出备份文件
    local backup_files=("$BACKUP_DIR"/forward_backup_*.tar.gz)
    if [ ${#backup_files[@]} -eq 0 ] || [ ! -f "${backup_files[0]}" ]; then
        echo -e "${RED}没有找到备份文件${NC}"
        return 1
    fi

    echo -e "${YELLOW}可用的备份文件:${NC}"
    local i=1
    for file in "${backup_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$i. $(basename "$file")"
            i=$((i+1))
        fi
    done

    echo -e "${YELLOW}请选择要删除的备份文件编号（多个用空格分隔，输入 0 删除所有，输入 c 取消）:${NC}"
    read -a delete_choices

    # 检查是否取消
    if [[ "${delete_choices[0]}" == "c" ]]; then
        echo -e "${GREEN}已取消删除操作${NC}"
        return 0
    fi

    # 检查是否删除所有
    if [[ "${delete_choices[0]}" == "0" ]]; then
        echo -e "${YELLOW}确认删除所有备份文件？（y/n，回车默认为 n）：${NC}"
        read confirm_delete_all
        if [ -z "$confirm_delete_all" ] || [ "$confirm_delete_all" != "y" ]; then
            echo -e "${GREEN}已取消删除操作${NC}"
            return 0
        fi

        rm -rf "$BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"
        echo -e "${GREEN}已删除所有备份文件${NC}"
        return 0
    fi

    # 删除选定的备份文件
    for choice in "${delete_choices[@]}"; do
        if [ "$choice" -gt 0 ] && [ "$choice" -lt "$i" ]; then
            local file_to_delete="${backup_files[$((choice-1))]}"
            if [ -f "$file_to_delete" ]; then
                rm -f "$file_to_delete"
                echo -e "${GREEN}已删除: $(basename "$file_to_delete")${NC}"
            fi
        else
            echo -e "${RED}无效的选择: $choice${NC}"
        fi
    done

    return 0
}

# 卸载脚本
uninstall_script() {
    echo -e "${RED}警告：卸载脚本将删除除备份文件外的所有相关文件和配置！${NC}"
    echo -e "${YELLOW}备份文件位于 $BACKUP_DIR 目录，包含您的配置和会话文件。${NC}"
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

    # 自动创建备份
    echo -e "${YELLOW}正在自动备份配置文件...${NC}"
    backup_config

    # 询问是否删除备份文件
    echo -e "${YELLOW}是否删除备份文件？（y/n，回车默认为 n）：${NC}"
    read delete_backups
    # 如果用户直接按回车，设置默认值为 n
    if [ -z "$delete_backups" ]; then
        delete_backups="n"
    fi

    if [ "$delete_backups" = "y" ]; then
        manage_backups
    else
        echo -e "${YELLOW}保留备份文件${NC}"
    fi

    echo -e "${YELLOW}正在停止脚本和相关进程...${NC}"

    # 如果在虚拟环境中，先退出虚拟环境
    if [ -n "$VIRTUAL_ENV" ]; then
        echo -e "${YELLOW}正在退出虚拟环境...${NC}"
        deactivate 2>/dev/null
    fi

    # 停止所有相关进程

    # 杀死所有相关 Python 进程（forward.py）
    if pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "${YELLOW}正在终止 forward.py 进程...${NC}"
        pkill -f "python.*forward.py" 2>/dev/null
        sleep 1
        # 如果进程仍然存在，使用强制终止
        if pgrep -f "python.*forward.py" > /dev/null; then
            echo -e "${YELLOW}尝试强制终止 forward.py 进程...${NC}"
            pkill -9 -f "python.*forward.py" 2>/dev/null
            sleep 1
        fi
    fi

    # 停止所有相关进程
    stop_script

    # 清理所有 PID 文件
    cleanup_pid_files

    echo -e "${YELLOW}正在删除相关文件和配置...${NC}"

    # 删除 forward.py
    if [ -f "$FORWARD_PY" ]; then
        rm -f "$FORWARD_PY" && echo -e "${GREEN}已删除 forward.py${NC}"
    fi

    # 删除日志文件
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE" && echo -e "${GREEN}已删除日志文件${NC}"
    fi

    # 删除日志轮转的压缩日志
    rm -f "$LOG_FILE"* 2>/dev/null && echo -e "${GREEN}已删除所有日志文件${NC}"

    # 删除配置文件
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE" && echo -e "${GREEN}已删除配置文件${NC}"
    fi

    # 删除虚拟环境
    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR" && echo -e "${GREEN}已删除虚拟环境${NC}"
    fi

    # 删除启动和停止脚本
    if [ -d "$SCRIPT_DIR/bin" ]; then
        rm -rf "$SCRIPT_DIR/bin" && echo -e "${GREEN}已删除启动和停止脚本${NC}"
    fi

    # 删除日志轮转配置文件
    if [ -f "/etc/logrotate.d/forward" ]; then
        rm -f "/etc/logrotate.d/forward" && echo -e "${GREEN}已删除日志轮转配置文件${NC}"
    fi

    # 删除 Telegram 会话文件
    rm -f "$SCRIPT_DIR/session_account"*.session 2>/dev/null && echo -e "${GREEN}已删除会话文件${NC}"
    rm -f "$SCRIPT_DIR/session_account"*.session-journal 2>/dev/null && echo -e "${GREEN}已删除会话日志文件${NC}"

    # 删除可能的缓存文件
    rm -rf "$SCRIPT_DIR/.telegram-cli" 2>/dev/null
    rm -rf "$SCRIPT_DIR/__pycache__" 2>/dev/null

    # 删除小号管理脚本
    if [ -f "$SCRIPT_DIR/account_manager.py" ]; then
        rm -f "$SCRIPT_DIR/account_manager.py" && echo -e "${GREEN}已删除小号管理脚本${NC}"
    fi

    # 删除配置管理脚本
    if [ -f "$SCRIPT_DIR/config_manager.py" ]; then
        rm -f "$SCRIPT_DIR/config_manager.py" && echo -e "${GREEN}已删除配置管理脚本${NC}"
    fi

    # 删除小号状态文件
    if [ -f "$SCRIPT_DIR/.account_status.json" ]; then
        rm -f "$SCRIPT_DIR/.account_status.json" && echo -e "${GREEN}已删除小号状态文件${NC}"
    fi

    echo -e "${GREEN}已清理缓存文件${NC}"

    # 删除快捷命令
    if [ -f "/usr/local/bin/tg" ]; then
        echo -e "${YELLOW}正在删除快捷命令 'tg'...${NC}"
        rm -f "/usr/local/bin/tg" && echo -e "${GREEN}快捷命令已删除！${NC}"
    fi

    echo -e "${YELLOW}正在删除脚本自身...${NC}"
    # 删除脚本自身
    rm -f "$SELF_SCRIPT" && echo -e "${GREEN}脚本已删除！${NC}"

    echo -e "${GREEN}卸载完成！${NC}"
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}备份文件已保留在 $BACKUP_DIR 目录中。${NC}"
    fi
    echo -e "${GREEN}程序即将退出。${NC}"
    exit 0
}

# 保存配置到文件
save_config() {
    # 创建配置文件目录（如果不存在）
    mkdir -p "$(dirname "$CONFIG_FILE")"

    # 写入配置
    cat > "$CONFIG_FILE" << EOL
# Telegram Forward 配置文件
# 自动生成于 $(date)
# 用户配置
EOL

    # 设置适当的权限
    chmod 600 "$CONFIG_FILE"
}

# 清理 PID 文件函数
cleanup_pid_files() {
    # 清理转发脚本的 PID 文件
    if [ -f "$SCRIPT_DIR/forward.pid" ]; then
        rm -f "$SCRIPT_DIR/forward.pid" 2>/dev/null
        echo -e "${YELLOW}已清理 PID 文件: $SCRIPT_DIR/forward.pid${NC}"
    fi

    if [ -f "$SCRIPT_DIR/monitor.pid" ]; then
        rm -f "$SCRIPT_DIR/monitor.pid" 2>/dev/null
        echo -e "${YELLOW}已清理 PID 文件: $SCRIPT_DIR/monitor.pid${NC}"
    fi
}

# 进程清理函数（减少代码重复）
cleanup_processes() {
    # 杀死所有 forward.py 相关进程
    if pgrep -f "python.*forward.py" > /dev/null; then
        pkill -f "python.*forward.py" 2>/dev/null
        echo -e "${YELLOW}已终止 forward.py 进程${NC}"
    fi

    # 杀死所有 run_forward.sh 相关进程
    if pgrep -f "run_forward.sh" > /dev/null; then
        pkill -f "run_forward.sh" 2>/dev/null
        echo -e "${YELLOW}已终止 run_forward.sh 进程${NC}"
    fi

    # 杀死所有监控进程
    if [ -f "$SCRIPT_DIR/monitor.pid" ]; then
        pid=$(cat "$SCRIPT_DIR/monitor.pid")
        if ps -p $pid > /dev/null; then
            kill $pid 2>/dev/null
            echo -e "${YELLOW}已终止监控进程 PID: $pid${NC}"
        fi
        rm -f "$SCRIPT_DIR/monitor.pid"
    fi
}

# 备份配置
backup_config() {
    echo -e "${YELLOW}正在备份配置...${NC}"

    # 检查 forward.py 是否存在
    if [ ! -f "$FORWARD_PY" ]; then
        echo -e "${RED}forward.py 文件不存在，无法备份${NC}"
        return 1
    fi

    # 创建备份目录并设置权限
    mkdir -p "$BACKUP_DIR"
    chmod 755 "$BACKUP_DIR"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$BACKUP_DIR/forward_backup_$timestamp.tar.gz"

    # 检查会话文件是否存在
    local session_files=$(find "$SCRIPT_DIR" -name "session_account*.session" 2>/dev/null)
    if [ -z "$session_files" ]; then
        echo -e "${YELLOW}未找到会话文件，仅备份 forward.py${NC}"
    else
        echo -e "${GREEN}找到会话文件，将一并备份${NC}"
    fi

    # 创建要备份的文件列表
    local files_to_backup=""

    # 检查并添加 forward.py（包含 API 凭证和转发规则）
    if [ -f "$FORWARD_PY" ]; then
        files_to_backup="$files_to_backup $(basename "$FORWARD_PY")"
    fi

    # 检查并添加会话文件（包含会话授权信息）
    local session_files=$(find "$SCRIPT_DIR" -name "session_account*.session" 2>/dev/null)
    if [ -n "$session_files" ]; then
        for session in $session_files; do
            files_to_backup="$files_to_backup $(basename "$session")"
        done
    fi

    # 如果没有文件可备份，则返回错误
    if [ -z "$files_to_backup" ]; then
        echo -e "${RED}没有找到可备份的文件${NC}"
        return 1
    fi

    # 创建备份文件
    cd "$SCRIPT_DIR" && tar -czf "$backup_file" $files_to_backup

    if [ $? -eq 0 ] && [ -f "$backup_file" ]; then
        # 设置适当的权限，确保用户可以访问
        chmod 644 "$backup_file"
        echo -e "${GREEN}配置已备份到: $backup_file${NC}"
        echo -e "${YELLOW}备份内容: forward.py（API凭证和转发规则）, 会话文件（授权信息）${NC}"
        return 0
    else
        echo -e "${RED}备份失败${NC}"
        return 1
    fi
}

# 恢复配置
restore_config() {
    echo -e "${YELLOW}可用的备份文件:${NC}"

    # 检查备份目录
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}备份目录不存在${NC}"
        return 1
    fi

    # 列出备份文件
    local backup_files=("$BACKUP_DIR"/forward_backup_*.tar.gz)
    if [ ${#backup_files[@]} -eq 0 ] || [ ! -f "${backup_files[0]}" ]; then
        echo -e "${RED}没有找到备份文件${NC}"
        return 1
    fi

    local i=1
    for file in "${backup_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$i. $(basename "$file")"
            i=$((i+1))
        fi
    done

    # 选择备份文件
    echo -e "${YELLOW}请选择要恢复的备份文件编号（输入 0 取消）:${NC}"
    read backup_choice

    if [ -z "$backup_choice" ] || [ "$backup_choice" -eq 0 ]; then
        echo -e "${YELLOW}已取消恢复操作${NC}"
        return 0
    fi

    if [ "$backup_choice" -gt 0 ] && [ "$backup_choice" -lt "$i" ]; then
        local selected_file="${backup_files[$((backup_choice-1))]}"

        # 安静地停止脚本（如果正在运行）
        if pgrep -f "python.*forward.py" > /dev/null; then
            echo -e "${YELLOW}正在停止当前运行的脚本...${NC}"
            # 使用安静模式停止脚本
            if [ -f "$SCRIPT_DIR/bin/stop_forward.sh" ]; then
                $SCRIPT_DIR/bin/stop_forward.sh > /dev/null 2>&1
            else
                pkill -f "python.*forward.py" > /dev/null 2>&1
            fi
            sleep 1
        fi

        # 创建临时目录
        local temp_dir="/tmp/forward_restore_$$"
        mkdir -p "$temp_dir"

        # 先解压到临时目录
        echo -e "${YELLOW}正在解压备份文件...${NC}"
        tar -xzf "$selected_file" -C "$temp_dir"

        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}正在恢复配置文件到项目目录...${NC}"

            # 跟踪是否有文件被恢复
            local files_restored=0

            # 复制 forward.py 到项目目录（包含 API 凭证和转发规则）
            if [ -f "$temp_dir/forward.py" ]; then
                cp "$temp_dir/forward.py" "$FORWARD_PY"
                echo -e "${GREEN}已恢复 forward.py（API凭证和转发规则）${NC}"
                files_restored=$((files_restored + 1))
            fi

            # 复制会话文件到项目目录（包含会话授权信息）
            local session_count=0
            for session_file in "$temp_dir"/session_account*.session; do
                if [ -f "$session_file" ]; then
                    cp "$session_file" "$SCRIPT_DIR/"
                    session_count=$((session_count + 1))
                fi
            done

            if [ $session_count -gt 0 ]; then
                echo -e "${GREEN}已恢复 $session_count 个会话文件（授权信息）${NC}"
                files_restored=$((files_restored + 1))
            fi

            # 检查是否有文件被恢复
            if [ $files_restored -eq 0 ]; then
                echo -e "${YELLOW}警告：备份文件中没有找到可恢复的文件${NC}"
            fi

            # 清理临时目录
            rm -rf "$temp_dir"

            echo -e "${GREEN}配置已成功恢复到项目目录！${NC}"
            return 0
        else
            echo -e "${RED}解压备份文件失败${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        echo -e "${RED}无效的选择${NC}"
        return 1
    fi
}

# 显示系统信息
show_system_info() {
    echo -e "${YELLOW}系统信息:${NC}"
    echo -e "操作系统: $OS_TYPE"
    echo -e "Python 版本: $(python3 --version 2>/dev/null || echo '未安装')"
    echo -e "脚本目录: $SCRIPT_DIR"
    echo -e "虚拟环境: $VENV_DIR"

    # 检查网络连接
    echo -e "${YELLOW}网络连接测试:${NC}"
    if ping -c 1 api.telegram.org &> /dev/null; then
        echo -e "${GREEN}Telegram API 可访问${NC}"
    else
        echo -e "${RED}Telegram API 不可访问${NC}"
    fi
}



# 检查小号状态
check_account_status() {
    # 检查小号状态文件是否存在
    if [ -f "$SCRIPT_DIR/.account_status.json" ]; then
        # 使用 jq 检查状态，如果没有 jq 则使用 grep
        if command -v jq &> /dev/null; then
            local status=$(jq -r '.[0].status' "$SCRIPT_DIR/.account_status.json" 2>/dev/null)
            if [ "$status" = "ok" ]; then
                echo -e "小号状态: ${GREEN}正常${NC}"
            elif [ "$status" = "unauthorized" ]; then
                echo -e "小号状态: ${RED}异常（需要重新授权）${NC}"
            elif [ "$status" = "error" ]; then
                echo -e "小号状态: ${RED}异常（连接错误）${NC}"
            else
                echo -e "小号状态: ${YELLOW}未知${NC}"
            fi
        else
            if grep -q "\"status\":\"ok\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                echo -e "小号状态: ${GREEN}正常${NC}"
            elif grep -q "\"status\":\"unauthorized\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                echo -e "小号状态: ${RED}异常（需要重新授权）${NC}"
            elif grep -q "\"status\":\"error\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                echo -e "小号状态: ${RED}异常（连接错误）${NC}"
            else
                echo -e "小号状态: ${YELLOW}未知${NC}"
            fi
        fi
    else
        echo -e "小号状态: ${RED}未配置${NC}"
    fi
}

# 主菜单
show_menu() {
    echo -e "${YELLOW}=== Telegram 消息转发管理工具 ===${NC}"
    echo -e "${YELLOW}版本: $SCRIPT_VERSION${NC}"
    echo -e "${YELLOW}--- 当前状态 ---${NC}"
    check_script_status
    check_venv_status
    check_config_status
    check_account_status
    echo -e "${YELLOW}----------------${NC}"
    echo "1. 安装依赖"
    echo "2. 配置管理"
    echo "3. 小号状态"
    echo "4. 启动脚本"
    echo "5. 停止脚本"
    echo "6. 重启脚本"
    echo "7. 查看日志（按q可退出查看日志）"
    echo "8. 卸载脚本"
    echo "0. 退出"
    echo -e "${YELLOW}请选择一个选项：${NC}"
}



# 配置管理菜单
config_management_menu() {
    # 检查 config_manager.py 是否存在
    if [ ! -f "$SCRIPT_DIR/config_manager.py" ]; then
        echo -e "${YELLOW}正在下载配置管理工具...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py -o "$SCRIPT_DIR/config_manager.py"
        chmod +x "$SCRIPT_DIR/config_manager.py"
    fi

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行配置管理工具
    python3 "$SCRIPT_DIR/config_manager.py" --script-dir "$SCRIPT_DIR" --backup-dir "$BACKUP_DIR"

    # 退出虚拟环境
    deactivate
}



# 主循环
while true; do
    show_menu
    read choice

    case $choice in
        1)
            install_dependencies
            if [ $? -eq 0 ]; then
                configure_logrotate
            fi
            ;;
        2)
            config_management_menu
            ;;
        3)
            # 检查 account_manager.py 是否存在
            if [ ! -f "$SCRIPT_DIR/account_manager.py" ]; then
                echo -e "${YELLOW}正在下载小号管理工具...${NC}"
                curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/account_manager.py -o "$SCRIPT_DIR/account_manager.py"
                chmod +x "$SCRIPT_DIR/account_manager.py"
            fi

            # 激活虚拟环境
            source "$VENV_DIR/bin/activate"

            # 运行小号管理工具
            python3 "$SCRIPT_DIR/account_manager.py" --script-dir "$SCRIPT_DIR"
            ;;
        4)
            # 检查配置文件是否存在
            if [ ! -f "$FORWARD_PY" ]; then
                echo -e "${RED}错误：配置文件不存在！${NC}"
                echo -e "${YELLOW}正在自动进入配置管理菜单...${NC}"
                config_management_menu
            else
                start_script
            fi
            ;;
        5)
            stop_script
            ;;
        6)
            # 检查配置文件是否存在
            if [ ! -f "$FORWARD_PY" ]; then
                echo -e "${RED}错误：配置文件不存在！${NC}"
                echo -e "${YELLOW}正在自动进入配置管理菜单...${NC}"
                config_management_menu
            else
                stop_script
                if [ $? -eq 0 ]; then
                    start_script
                fi
            fi
            ;;
        7)
            view_log
            ;;
        8)
            uninstall_script
            ;;
        0)
            echo -e "${YELLOW}您希望如何退出？${NC}"
            echo "1. 保持转发脚本在后台运行并退出菜单"
            echo "2. 停止所有转发脚本并完全退出"
            read exit_choice

            case $exit_choice in
                1)
                    echo -e "${GREEN}退出功能菜单，转发脚本继续在后台运行...${NC}"
                    exit 0
                    ;;
                2)
                    echo -e "${YELLOW}正在停止所有转发脚本...${NC}"
                    stop_script
                    echo -e "${GREEN}已停止所有转发脚本，完全退出。${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}无效选项，返回主菜单${NC}"
                    ;;
            esac
            ;;
        *)
            echo -e "${RED}无效选项，请重试！${NC}"
            ;;
    esac
done
