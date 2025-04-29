#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装依赖...${NC}"

    # 检查 Python 是否已安装
    if ! command -v python3 &> /dev/null; then
        echo -e "${YELLOW}Python3 未安装，正在安装...${NC}"
        
        # 根据系统类型安装 Python
        if [ "$OS_TYPE" = "alpine" ]; then
            apk add --no-cache python3 py3-pip
        elif [ "$OS_TYPE" = "debian" ] || [ "$OS_TYPE" = "ubuntu" ]; then
            apt-get update
            apt-get install -y python3 python3-pip python3-venv
        elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "rhel" ] || [ "$OS_TYPE" = "fedora" ]; then
            yum install -y python3 python3-pip
        else
            echo -e "${RED}不支持的系统类型: $OS_TYPE${NC}"
            return 1
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}安装 Python 失败${NC}"
            return 1
        fi
    fi

    # 创建虚拟环境
    echo -e "${YELLOW}创建 Python 虚拟环境...${NC}"
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}创建虚拟环境失败${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}虚拟环境已存在${NC}"
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

# 停止转发脚本
if [ -f "$SCRIPT_DIR/forward.pid" ]; then
    pid=\$(cat "$SCRIPT_DIR/forward.pid")
    if ps -p \$pid > /dev/null; then
        kill \$pid
        echo "已停止转发脚本，PID: \$pid"
    fi
    rm -f "$SCRIPT_DIR/forward.pid"
fi
EOL
    chmod +x "$SCRIPT_DIR/bin/stop_forward.sh"

    # 退出虚拟环境
    deactivate

    echo -e "${GREEN}依赖安装完成！${NC}"
    return 0
}

# 配置 logrotate
configure_logrotate() {
    echo -e "${YELLOW}配置日志轮转...${NC}"

    # 检查 logrotate 是否已安装
    if ! command -v logrotate &> /dev/null; then
        echo -e "${YELLOW}logrotate 未安装，正在安装...${NC}"
        
        # 根据系统类型安装 logrotate
        if [ "$OS_TYPE" = "alpine" ]; then
            apk add --no-cache logrotate
        elif [ "$OS_TYPE" = "debian" ] || [ "$OS_TYPE" = "ubuntu" ]; then
            apt-get update
            apt-get install -y logrotate
        elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "rhel" ] || [ "$OS_TYPE" = "fedora" ]; then
            yum install -y logrotate
        else
            echo -e "${RED}不支持的系统类型: $OS_TYPE${NC}"
            return 1
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}安装 logrotate 失败${NC}"
            return 1
        fi
    fi

    # 创建 logrotate 配置文件
    LOGROTATE_CONF="/etc/logrotate.d/telegram_forward"
    
    # 检查是否有权限写入 /etc/logrotate.d/
    if [ -w "/etc/logrotate.d/" ]; then
        cat > "$LOGROTATE_CONF" << EOL
$LOG_FILE {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 $(whoami) $(id -gn)
}
EOL
        echo -e "${GREEN}已配置 logrotate${NC}"
    else
        echo -e "${YELLOW}无权限写入 logrotate 配置，尝试使用 sudo${NC}"
        
        # 使用 sudo 创建配置文件
        cat > /tmp/telegram_forward_logrotate << EOL
$LOG_FILE {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 $(whoami) $(id -gn)
}
EOL
        
        sudo mv /tmp/telegram_forward_logrotate "$LOGROTATE_CONF" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}已配置 logrotate${NC}"
        else
            echo -e "${YELLOW}无法配置 logrotate，日志将不会自动轮转${NC}"
        fi
    fi

    return 0
}

# 创建快捷命令
create_shortcut() {
    echo -e "${YELLOW}创建快捷命令...${NC}"
    
    # 检查是否有权限写入 /usr/local/bin/
    if [ -w "/usr/local/bin/" ]; then
        cat > "/usr/local/bin/tg" << EOL
#!/bin/bash
$SELF_SCRIPT "\$@"
EOL
        chmod +x "/usr/local/bin/tg"
        echo -e "${GREEN}已创建快捷命令 'tg'${NC}"
    else
        echo -e "${YELLOW}无权限写入 /usr/local/bin/，尝试使用 sudo${NC}"
        
        # 使用 sudo 创建快捷命令
        cat > /tmp/tg_shortcut << EOL
#!/bin/bash
$SELF_SCRIPT "\$@"
EOL
        
        sudo mv /tmp/tg_shortcut "/usr/local/bin/tg" 2>/dev/null
        sudo chmod +x "/usr/local/bin/tg" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}已创建快捷命令 'tg'${NC}"
        else
            echo -e "${YELLOW}无法创建快捷命令，请使用完整路径运行脚本${NC}"
        fi
    fi

    return 0
}
