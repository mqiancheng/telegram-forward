#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检测系统类型
detect_os_type() {
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# 检查命令是否存在并安装（支持多种包管理器）
check_command() {
    local command_name="$1"
    if ! command -v $command_name &> /dev/null; then
        echo -e "${RED}$command_name 未安装，正在安装...${NC}"

        # 根据系统类型使用不同的包管理器
        if [ "$OS_TYPE" = "alpine" ]; then
            apk add $command_name
        elif [ "$OS_TYPE" = "ubuntu" ] || [ "$OS_TYPE" = "debian" ]; then
            apt-get update && apt-get install -y $command_name
        elif [ "$OS_TYPE" = "centos" ] || [ "$OS_TYPE" = "fedora" ] || [ "$OS_TYPE" = "rhel" ]; then
            if command -v dnf &> /dev/null; then
                dnf install -y $command_name
            else
                yum install -y $command_name
            fi
        else
            echo -e "${RED}无法确定系统类型，请手动安装 $command_name${NC}"
            return 1
        fi

        # 检查安装是否成功
        if ! command -v $command_name &> /dev/null; then
            echo -e "${RED}安装 $command_name 失败，请手动安装${NC}"
            return 1
        fi
    fi
    return 0
}

# 下载共享库
download_utils() {
    # 检查 utils.py 是否存在
    if [ ! -f "$SCRIPT_DIR/utils.py" ]; then
        echo -e "${YELLOW}正在下载共享库...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/utils.py -o "$SCRIPT_DIR/utils.py"
        chmod +x "$SCRIPT_DIR/utils.py"
    fi
}

# 下载Python模块
download_python_module() {
    local module_name="$1"
    local module_url="$2"
    
    # 检查模块是否存在
    if [ ! -f "$SCRIPT_DIR/$module_name.py" ]; then
        echo -e "${YELLOW}正在下载 $module_name 模块...${NC}"
        curl -fsSL "$module_url" -o "$SCRIPT_DIR/$module_name.py"
        chmod +x "$SCRIPT_DIR/$module_name.py"
    fi
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

# 确认操作
confirm_action() {
    local message="$1"
    local default="$2"
    
    echo -e "${YELLOW}$message${NC}"
    read confirm
    
    # 如果用户直接按回车，使用默认值
    if [ -z "$confirm" ]; then
        confirm="$default"
    fi
    
    if [ "$confirm" = "y" ]; then
        return 0
    else
        return 1
    fi
}