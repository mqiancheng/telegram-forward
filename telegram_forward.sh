#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本版本号
SCRIPT_VERSION="1.5.1"

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

# 检测系统类型
if [ -f "/etc/os-release" ]; then
    . /etc/os-release
    OS_TYPE="$ID"
else
    OS_TYPE="unknown"
fi

# 根据系统类型设置 supervisord 配置路径
if [ "$OS_TYPE" = "alpine" ]; then
    SUPERVISORD_CONF="/etc/supervisord.conf"
    SUPERVISOR_DIR="/etc/supervisor.d"
elif [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
    SUPERVISORD_CONF="/etc/supervisor/supervisord.conf"
    SUPERVISOR_DIR="/etc/supervisor/conf.d"
elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
    SUPERVISORD_CONF="/etc/supervisord.conf"
    SUPERVISOR_DIR="/etc/supervisord.d"
else
    SUPERVISORD_CONF="/etc/supervisord.conf"
    SUPERVISOR_DIR="/etc/supervisor.d"
fi

# 配置选项：是否默认停止 supervisord（默认为 true）
# 如果系统中有其他应用也使用 supervisord，请将此选项设置为 false
STOP_SUPERVISORD_DEFAULT=true

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

# 检查小号状态
check_accounts_status() {
    # 检查 forward.py 是否存在
    if [ ! -f "$FORWARD_PY" ]; then
        echo -e "${RED}小号状态：未配置${NC}"
        return 1
    fi

    # 检查虚拟环境是否存在
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${RED}小号状态：虚拟环境未创建，无法检查${NC}"
        return 1
    fi

    # 检查状态检查脚本是否存在
    if [ ! -f "$SCRIPT_DIR/check_account_status.py" ]; then
        echo -e "${RED}小号状态：状态检查脚本不存在${NC}"
        return 1
    fi

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行状态检查脚本
    local status_output=$(python "$SCRIPT_DIR/check_account_status.py" "$FORWARD_PY" 2>/dev/null)
    local exit_code=$?

    # 检查脚本是否成功运行
    if [ $exit_code -ne 0 ] || [ -z "$status_output" ]; then
        echo -e "${RED}小号状态：检查失败${NC}"
        return 1
    fi

    # 解析状态输出
    local error_count=0
    local total_count=$(echo "$status_output" | grep -o '"status"' | wc -l)

    if [ $total_count -eq 0 ]; then
        echo -e "${RED}小号状态：未检测到小号${NC}"
        return 1
    fi

    # 检查是否有错误状态
    if echo "$status_output" | grep -q '"status":"error"\|"status":"unauthorized"'; then
        error_count=$(echo "$status_output" | grep -o '"status":"error"\|"status":"unauthorized"' | wc -l)
        echo -e "${RED}小号状态：异常（$error_count/$total_count 个小号需要重新授权）${NC}"
        # 保存状态到临时文件
        echo "$status_output" > "$SCRIPT_DIR/.account_status.json"
        return 1
    else
        echo -e "${GREEN}小号状态：正常（$total_count 个小号）${NC}"
        # 保存状态到临时文件
        echo "$status_output" > "$SCRIPT_DIR/.account_status.json"
        return 0
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

    # 复制账户状态检查脚本
    if [ -f "$SCRIPT_DIR/check_account_status.py" ]; then
        echo -e "${YELLOW}账户状态检查脚本已存在，跳过复制...${NC}"
    else
        echo -e "${YELLOW}正在创建账户状态检查脚本...${NC}"
        cat > "$SCRIPT_DIR/check_account_status.py" << EOL
#!/usr/bin/env python3
from telethon import TelegramClient
import asyncio
import sys
import os
import json

# 检查小号状态的脚本
# 用法: python3 check_account_status.py [forward.py路径]

async def check_account(session_file, api_id, api_hash):
    """检查账号状态，返回状态和用户信息"""
    try:
        # 创建客户端但不连接
        client = TelegramClient(session_file, api_id, api_hash)

        # 尝试连接
        await client.connect()

        # 检查是否已授权
        if not await client.is_user_authorized():
            await client.disconnect()
            return {
                "status": "unauthorized",
                "message": "账号未授权，需要重新登录",
                "session": session_file
            }

        # 获取用户信息
        me = await client.get_me()

        # 断开连接
        await client.disconnect()

        # 返回状态和用户信息
        return {
            "status": "ok",
            "message": "账号状态正常",
            "session": session_file,
            "user_id": me.id,
            "username": me.username,
            "first_name": me.first_name,
            "last_name": me.last_name,
            "phone": me.phone
        }
    except Exception as e:
        # 捕获所有异常
        return {
            "status": "error",
            "message": str(e),
            "session": session_file
        }

async def check_all_accounts(accounts):
    """检查所有账号状态"""
    results = []
    for account in accounts:
        session = account['session']
        api_id = account['api_id']
        api_hash = account['api_hash']

        # 检查账号状态
        result = await check_account(session, api_id, api_hash)
        results.append(result)

    return results

def parse_forward_py(file_path):
    """解析 forward.py 文件，提取账号信息"""
    try:
        with open(file_path, 'r') as f:
            content = f.read()

        # 提取 accounts 部分
        accounts_start = content.find('accounts = [')
        accounts_end = content.find(']', accounts_start)

        if accounts_start == -1 or accounts_end == -1:
            return []

        # 提取账号信息
        accounts_str = content[accounts_start:accounts_end+1]

        # 将单引号替换为双引号以便 JSON 解析
        accounts_str = accounts_str.replace("'", '"')
        accounts_str = accounts_str.replace("accounts = ", "")

        # 解析 JSON
        try:
            accounts = json.loads(accounts_str)
            return accounts
        except json.JSONDecodeError:
            # 如果 JSON 解析失败，使用更简单的方法
            accounts = []
            lines = accounts_str.strip()[1:-1].split('{')
            for line in lines:
                if not line.strip():
                    continue
                line = '{' + line
                if line.endswith(','):
                    line = line[:-1]
                try:
                    account = eval(line)
                    accounts.append(account)
                except:
                    pass
            return accounts
    except Exception as e:
        print("解析 forward.py 失败: " + str(e))
        return []

async def main():
    # 检查参数
    if len(sys.argv) < 2:
        print("用法: python3 check_account_status.py <forward.py路径>")
        return

    forward_py_path = sys.argv[1]

    # 检查文件是否存在
    if not os.path.exists(forward_py_path):
        print("错误: 文件 " + forward_py_path + " 不存在")
        return

    # 解析 forward.py
    accounts = parse_forward_py(forward_py_path)

    if not accounts:
        print("错误: 无法解析账号信息")
        return

    # 检查所有账号状态
    results = await check_all_accounts(accounts)

    # 输出结果为 JSON
    print(json.dumps(results, ensure_ascii=False))

if __name__ == "__main__":
    asyncio.run(main())
EOL
        chmod +x "$SCRIPT_DIR/check_account_status.py"
        echo -e "${GREEN}账户状态检查脚本已创建${NC}"
    fi

    # 创建快捷命令
    create_shortcut

    echo -e "${GREEN}依赖安装完成！${NC}"
    return 0
}

# 配置 forward.py 脚本
configure_script() {
    echo -e "${YELLOW}请输入大号群组/个人的 Chat ID（例如 -4688142035）：${NC}"
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
            print("消息已转发 (来自 " + str(event.sender_id) + ")")
    else:  # 转发所有私聊消息
        @client.on(events.NewMessage(chats=None))
        async def handler(event):
            # 确保只转发私聊消息（排除群组/频道）
            if event.is_private:
                await client.forward_messages(target_chat_id, event.message)
                print("消息已转发 (来自 " + str(event.sender_id) + ")")

# 启动所有客户端
async def main():
    while True:
        try:
            for client in clients:
                await client.start()
            # 保持运行
            await asyncio.gather(*(client.run_until_disconnected() for client in clients))
        except Exception as e:
            print("脚本异常退出: " + str(e))
            print("将在 60 秒后重试...")
            await asyncio.sleep(60)

# 运行主程序
asyncio.run(main())
EOL
    echo -e "${GREEN}forward.py 已生成！${NC}"

    # 配置完成后自动启动脚本
    echo -e "${YELLOW}正在自动启动脚本...${NC}"
    sleep 2  # 确保配置文件已写入
    start_script
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
    echo -e "${YELLOW}正在启动服务...${NC}"

    # 检查 forward.py 是否存在
    if [ ! -f "$FORWARD_PY" ]; then
        echo -e "${RED}forward.py 文件不存在，请先配置脚本！${NC}"
        return 1
    fi

    # 检查虚拟环境是否存在
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${RED}虚拟环境不存在，请先安装依赖！${NC}"
        return 1
    fi

    # 清理残留进程和状态文件
    cleanup_processes

    # 使用脚本启动
    echo -e "${YELLOW}正在启动转发脚本...${NC}"
    if [ -f "$SCRIPT_DIR/bin/run_forward.sh" ]; then
        $SCRIPT_DIR/bin/run_forward.sh
        sleep 2

        # 检查脚本是否成功启动
        if [ -f "$SCRIPT_DIR/forward.pid" ] && ps -p $(cat "$SCRIPT_DIR/forward.pid") > /dev/null; then
            echo -e "${GREEN}脚本已成功启动！${NC}"
        else
            echo -e "${RED}脚本启动失败，请检查日志${NC}"
            echo -e "${YELLOW}可能的原因：${NC}"
            echo -e "1. Telegram API 凭证错误"
            echo -e "2. 网络连接问题"
            echo -e "3. Python 依赖问题"
            echo -e "${YELLOW}请使用选项 6 查看日志以获取详细错误信息${NC}"
            return 1
        fi
    else
        echo -e "${RED}找不到启动脚本，请重新安装依赖${NC}"
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
        pkill -f "python.*forward.py" 2>/dev/null
    fi

    # 清理可能残留的进程
    cleanup_processes

    # 验证 forward.py 停止状态
    if ! pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "${GREEN}转发脚本已成功停止！${NC}"
    else
        echo -e "${RED}转发脚本停止失败，尝试强制终止...${NC}"
        pkill -9 -f "python.*forward.py" 2>/dev/null
        sleep 1

        if ! pgrep -f "python.*forward.py" > /dev/null; then
            echo -e "${GREEN}转发脚本已强制停止！${NC}"
        else
            echo -e "${RED}无法停止转发脚本，请手动检查进程${NC}"
            return 1
        fi
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

# 卸载脚本
uninstall_script() {
    echo -e "${RED}警告：卸载脚本将删除除备份文件外的所有相关文件和配置！${NC}"
    echo -e "${YELLOW}备份文件位于 $SCRIPT_DIR/backup 目录，包含您的配置和会话文件。${NC}"
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

    # 如果在虚拟环境中，先退出虚拟环境
    if [ -n "$VIRTUAL_ENV" ]; then
        echo -e "${YELLOW}正在退出虚拟环境...${NC}"
        deactivate 2>/dev/null
    fi

    # 停止 supervisord 和 forward 进程
    if command -v supervisorctl &> /dev/null; then
        echo -e "${YELLOW}正在停止 forward 服务...${NC}"
        supervisorctl stop forward 2>/dev/null
        sleep 2
    fi

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

    # 确保 supervisord 进程被停止
    if pgrep -f "supervisord" > /dev/null; then
        echo -e "${YELLOW}正在停止 supervisord...${NC}"

        # 根据系统类型停止 supervisord
        if [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
            systemctl stop supervisor 2>/dev/null
        elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
            systemctl stop supervisord 2>/dev/null
        else
            pkill -f "supervisord" 2>/dev/null
        fi
        sleep 1

        # 如果进程仍然存在，使用强制终止
        if pgrep -f "supervisord" > /dev/null; then
            echo -e "${YELLOW}尝试强制终止 supervisord 进程...${NC}"
            pkill -9 -f "supervisord" 2>/dev/null
            sleep 1
        fi
    fi

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

    # 删除 supervisord 配置文件（检查多个可能的位置）
    local supervisor_configs=(
        "$SUPERVISOR_DIR/forward.ini"
        "/etc/supervisor.d/forward.ini"
        "/etc/supervisor/conf.d/forward.ini"
        "/etc/supervisord.d/forward.ini"
    )

    for config in "${supervisor_configs[@]}"; do
        if [ -f "$config" ]; then
            rm -f "$config" && echo -e "${GREEN}已删除 supervisord 配置文件: $config${NC}"
        fi
    done

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
    echo -e "${GREEN}已清理缓存文件${NC}"

    echo -e "${YELLOW}是否同时卸载 supervisor？（y/n，回车默认为 n）：${NC}"
    read uninstall_supervisor
    # 如果用户直接按回车，设置默认值为 n
    if [ -z "$uninstall_supervisor" ]; then
        uninstall_supervisor="n"
    fi

    if [ "$uninstall_supervisor" = "y" ]; then
        echo -e "${YELLOW}正在卸载 supervisor...${NC}"
        if [ "$OS_TYPE" = "alpine" ]; then
            apk del supervisor 2>/dev/null && echo -e "${GREEN}已卸载 supervisor${NC}"
        elif [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
            apt-get remove -y supervisor 2>/dev/null && echo -e "${GREEN}已卸载 supervisor${NC}"
        elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
            if command -v dnf &> /dev/null; then
                dnf remove -y supervisor 2>/dev/null && echo -e "${GREEN}已卸载 supervisor${NC}"
            else
                yum remove -y supervisor 2>/dev/null && echo -e "${GREEN}已卸载 supervisor${NC}"
            fi
        else
            echo -e "${RED}无法确定系统类型，请手动卸载 supervisor${NC}"
        fi
    else
        echo -e "${YELLOW}保留 supervisor 安装${NC}"
    fi

    # 删除快捷命令
    if [ -f "/usr/local/bin/tg" ]; then
        echo -e "${YELLOW}正在删除快捷命令 'tg'...${NC}"
        rm -f "/usr/local/bin/tg" && echo -e "${GREEN}快捷命令已删除！${NC}"
    fi

    echo -e "${YELLOW}正在删除脚本自身...${NC}"
    # 删除脚本自身
    rm -f "$SELF_SCRIPT" && echo -e "${GREEN}脚本已删除！${NC}"

    echo -e "${GREEN}卸载完成！${NC}"
    echo -e "${YELLOW}备份文件已保留在 $SCRIPT_DIR/backup 目录中，如需完全清理，请手动删除该目录。${NC}"
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
STOP_SUPERVISORD_DEFAULT=$STOP_SUPERVISORD_DEFAULT
EOL

    # 设置适当的权限
    chmod 600 "$CONFIG_FILE"
}

# 清理 PID 文件函数
cleanup_pid_files() {
    # 清理 supervisord PID 文件（如果存在）
    local pid_files=(
        "/var/run/supervisord.pid"
        "/run/supervisord.pid"
        "/var/run/supervisor/supervisord.pid"
        "/var/run/supervisor.pid"
        "/tmp/supervisord.pid"
    )

    for pid_file in "${pid_files[@]}"; do
        if [ -f "$pid_file" ]; then
            rm -f "$pid_file" 2>/dev/null
            echo -e "${YELLOW}已清理 PID 文件: $pid_file${NC}"
        fi
    done
}

# 进程清理函数（减少代码重复）
cleanup_processes() {
    # 杀死所有 forward.py 相关进程
    if pgrep -f "python.*forward.py" > /dev/null; then
        pkill -f "python.*forward.py" 2>/dev/null
        echo -e "${YELLOW}已终止 forward.py 进程${NC}"
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

    # 创建备份目录
    local backup_dir="$SCRIPT_DIR/backup"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/forward_backup_$timestamp.tar.gz"

    mkdir -p "$backup_dir"

    # 创建备份文件
    tar -czf "$backup_file" -C "$SCRIPT_DIR" $(basename "$FORWARD_PY") $(basename "$CONFIG_FILE" 2>/dev/null) $(basename "$SCRIPT_DIR"/session_account*.session 2>/dev/null)

    if [ $? -eq 0 ] && [ -f "$backup_file" ]; then
        echo -e "${GREEN}配置已备份到: $backup_file${NC}"
        echo -e "${YELLOW}备份内容: forward.py, 会话文件, 配置文件${NC}"
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
    local backup_dir="$SCRIPT_DIR/backup"
    if [ ! -d "$backup_dir" ]; then
        echo -e "${RED}备份目录不存在${NC}"
        return 1
    fi

    # 列出备份文件
    local backup_files=("$backup_dir"/forward_backup_*.tar.gz)
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

            # 复制 forward.py 到项目目录
            if [ -f "$temp_dir/forward.py" ]; then
                cp "$temp_dir/forward.py" "$FORWARD_PY"
                echo -e "${GREEN}已恢复 forward.py${NC}"
            fi

            # 复制会话文件到项目目录
            if ls "$temp_dir"/session_account*.session &>/dev/null; then
                cp "$temp_dir"/session_account*.session "$SCRIPT_DIR/" 2>/dev/null
                echo -e "${GREEN}已恢复会话文件${NC}"
            fi

            # 复制配置文件到项目目录
            if [ -f "$temp_dir/.telegram_forward.conf" ]; then
                cp "$temp_dir/.telegram_forward.conf" "$CONFIG_FILE"
                echo -e "${GREEN}已恢复配置设置${NC}"
                # 重新加载配置
                . "$CONFIG_FILE"
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
    echo -e "Supervisor 配置: $SUPERVISORD_CONF"
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



# 主菜单
show_menu() {
    echo -e "${YELLOW}=== Telegram 消息转发管理工具 ===${NC}"
    echo -e "${YELLOW}版本: $SCRIPT_VERSION${NC}"
    echo -e "${YELLOW}--- 当前状态 ---${NC}"
    check_script_status
    check_venv_status
    check_config_status
    check_accounts_status
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
    while true; do
        echo -e "${YELLOW}=== 配置管理菜单 ===${NC}"
        echo "1. 新建配置"
        echo "2. 修改配置"
        echo "3. 备份配置"
        echo "4. 恢复配置"
        echo "0. 返回主菜单"
        echo -e "${YELLOW}请选择一个选项：${NC}"

        read config_choice
        case $config_choice in
            1)
                configure_script
                ;;
            2)
                view_config
                ;;
            3)
                backup_config
                ;;
            4)
                restore_config
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选项，请重试！${NC}"
                ;;
        esac
    done
}

# 小号状态菜单
accounts_status_menu() {
    while true; do
        echo -e "${YELLOW}=== 小号状态菜单 ===${NC}"
        echo -e "${YELLOW}使用说明：输入序号并回车重新配置标红异常状态的小号${NC}"
        echo -e "${YELLOW}对于有多个小号异常的，请输入数字加空格，例如：2 3 6${NC}"

        # 检查 forward.py 是否存在
        if [ ! -f "$FORWARD_PY" ]; then
            echo -e "${RED}错误：配置文件不存在！${NC}"
            echo -e "${YELLOW}请先使用选项 2 进行配置管理，创建配置文件。${NC}"
            echo -e "${YELLOW}按 Enter 键返回主菜单...${NC}"
            read
            return
        fi

        # 检查状态文件是否存在
        if [ ! -f "$SCRIPT_DIR/.account_status.json" ]; then
            # 运行状态检查
            check_accounts_status > /dev/null
        fi

        # 显示小号列表
        if [ -f "$SCRIPT_DIR/.account_status.json" ]; then
            # 激活虚拟环境
            source "$VENV_DIR/bin/activate"

            # 解析状态文件并显示小号列表
            python3 -c '
import json
import sys

try:
    with open("'"$SCRIPT_DIR/.account_status.json"'", "r") as f:
        accounts = json.load(f)

    for i, account in enumerate(accounts, 1):
        status = account.get("status", "unknown")
        session = account.get("session", "")
        username = account.get("username", "")
        first_name = account.get("first_name", "")
        phone = account.get("phone", "")

        # 构建显示名称
        display_name = ""
        if username:
            display_name = "@" + username
        elif first_name:
            display_name = first_name
        elif phone:
            display_name = phone
        else:
            display_name = "小号" + str(i)

        # 根据状态显示不同颜色
        if status == "ok":
            print("\033[32m" + str(i) + ". " + display_name + " (正常)\033[0m")
        else:
            message = account.get("message", "未知错误")
            print("\033[31m" + str(i) + ". " + display_name + " (异常: " + message + ")\033[0m")
except Exception as e:
    print("\033[31m无法解析小号状态: " + str(e) + "\033[0m")
'
        else
            echo -e "${RED}无法获取小号状态信息${NC}"
        fi

        echo -e "${YELLOW}----------------${NC}"
        echo "0. 返回主菜单"
        echo -e "${YELLOW}请输入要重新授权的小号序号（多个用空格分隔）：${NC}"

        read account_choice

        # 检查是否返回主菜单
        if [ "$account_choice" = "0" ]; then
            return
        fi

        # 处理用户输入
        if [ -n "$account_choice" ]; then
            # 停止脚本
            stop_script

            # 重新授权选择的小号
            reauthorize_accounts "$account_choice"
        fi
    done
}

# 重新授权小号
reauthorize_accounts() {
    local account_indices="$1"

    # 检查 forward.py 是否存在
    if [ ! -f "$FORWARD_PY" ]; then
        echo -e "${RED}错误：配置文件不存在！${NC}"
        return 1
    fi

    # 检查状态文件是否存在
    if [ ! -f "$SCRIPT_DIR/.account_status.json" ]; then
        echo -e "${RED}错误：小号状态信息不存在！${NC}"
        return 1
    fi

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 解析状态文件
    local accounts_data=$(cat "$SCRIPT_DIR/.account_status.json")

    # 解析 forward.py 获取 API 信息
    local api_info=$(python3 -c '
import json
import sys
import re

try:
    # 读取 forward.py
    with open("'"$FORWARD_PY"'", "r") as f:
        content = f.read()

    # 提取 accounts 部分
    accounts_match = re.search(r"accounts\s*=\s*\[(.*?)\]", content, re.DOTALL)
    if not accounts_match:
        print(json.dumps([]))
        sys.exit(0)

    accounts_str = accounts_match.group(1)

    # 解析每个账号
    accounts = []
    for match in re.finditer(r"{[^{}]*?}", accounts_str, re.DOTALL):
        account_str = match.group(0)

        # 提取 api_id
        api_id_match = re.search(r"[\'"]api_id[\'"]\s*:\s*[\'"]?(\d+)[\'"]?", account_str)
        api_id = api_id_match.group(1) if api_id_match else ""

        # 提取 api_hash
        api_hash_match = re.search(r"[\'"]api_hash[\'"]\s*:\s*[\'"]([a-zA-Z0-9]+)[\'"]", account_str)
        api_hash = api_hash_match.group(1) if api_hash_match else ""

        # 提取 session
        session_match = re.search(r"[\'"]session[\'"]\s*:\s*[\'"]([^\'\"]+)[\'"]", account_str)
        session = session_match.group(1) if session_match else ""

        if api_id and api_hash and session:
            accounts.append({
                "api_id": api_id,
                "api_hash": api_hash,
                "session": session
            })

    print(json.dumps(accounts))
except Exception as e:
    print(json.dumps([]))
')

    # 检查是否成功解析
    if [ -z "$api_info" ] || [ "$api_info" = "[]" ]; then
        echo -e "${RED}错误：无法解析 API 信息！${NC}"
        return 1
    fi

    # 处理每个选择的小号
    for index in $account_indices; do
        # 检查索引是否有效
        if ! [[ "$index" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}错误：无效的索引 '$index'${NC}"
            continue
        fi

        # 获取对应的 API 信息
        local account_api=$(echo "$api_info" | python3 -c '
import json
import sys

try:
    accounts = json.loads(sys.stdin.read())
    index = int("'"$index"'") - 1

    if 0 <= index < len(accounts):
        print(json.dumps(accounts[index]))
    else:
        print("{}")
except:
    print("{}")
')

        # 检查是否成功获取 API 信息
        if [ -z "$account_api" ] || [ "$account_api" = "{}" ]; then
            echo -e "${RED}错误：无法获取小号 $index 的 API 信息！${NC}"
            continue
        fi

        # 提取 API 信息
        local api_id=$(echo "$account_api" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("api_id", ""))')
        local api_hash=$(echo "$account_api" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("api_hash", ""))')
        local session=$(echo "$account_api" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("session", ""))')

        # 检查是否成功提取
        if [ -z "$api_id" ] || [ -z "$api_hash" ] || [ -z "$session" ]; then
            echo -e "${RED}错误：小号 $index 的 API 信息不完整！${NC}"
            continue
        fi

        echo -e "${YELLOW}正在重新授权小号 $index [session: $session]...${NC}"

        # 删除旧的 session 文件
        if [ -f "$SCRIPT_DIR/$session.session" ]; then
            rm -f "$SCRIPT_DIR/$session.session"
        fi

        # 创建临时登录脚本
        cat > "$SCRIPT_DIR/temp_login.py" << EOL
from telethon import TelegramClient
import asyncio

async def main():
    # 创建客户端
    client = TelegramClient('$SCRIPT_DIR/$session', $api_id, '$api_hash')

    # 连接并登录
    await client.connect()

    if not await client.is_user_authorized():
        print("请登录您的 Telegram 账号")

        # 获取手机号
        phone = input("请输入您的手机号（包含国家代码，例如 +86）: ")

        # 发送验证码
        await client.send_code_request(phone)

        # 输入验证码
        code = input("请输入收到的验证码: ")

        try:
            # 尝试使用验证码登录
            await client.sign_in(phone, code)
            print("登录成功！")
        except Exception as e:
            # 如果需要密码（两步验证）
            if "password" in str(e).lower():
                password = input("请输入您的两步验证密码: ")
                await client.sign_in(password=password)
                print("登录成功！")
            else:
                print("登录失败: " + str(e))
    else:
        print("已经登录！")

    # 获取用户信息
    me = await client.get_me()
    first_name = me.first_name if me.first_name else ""
    username = me.username if me.username else ""
    print("已登录为: " + first_name + " (@" + username + ")")

    # 断开连接
    await client.disconnect()

asyncio.run(main())
EOL

        # 运行登录脚本
        python3 "$SCRIPT_DIR/temp_login.py"

        # 删除临时登录脚本
        rm -f "$SCRIPT_DIR/temp_login.py"

        echo -e "${GREEN}小号 $index 重新授权完成！${NC}"
    done

    # 更新状态
    check_accounts_status > /dev/null

    echo -e "${GREEN}所有选择的小号已重新授权完成！${NC}"
    return 0
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
            accounts_status_menu
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
            echo -e "${GREEN}退出功能菜单，脚本后台运行中...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重试！${NC}"
            ;;
    esac
done
