#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 下载共享库
download_utils() {
    # 检查 utils.py 是否存在
    if [ ! -f "$SCRIPT_DIR/utils.py" ]; then
        echo -e "${YELLOW}正在下载共享库...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/utils.py -o "$SCRIPT_DIR/utils.py"
        chmod +x "$SCRIPT_DIR/utils.py"
    fi
}

# 配置 forward.py 脚本（调用配置管理工具）
configure_script() {
    # 停止任何可能正在运行的脚本
    stop_script > /dev/null 2>&1

    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    if [ ! -f "$SCRIPT_DIR/config_manager.py" ]; then
        echo -e "${YELLOW}正在下载配置管理工具...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py -o "$SCRIPT_DIR/config_manager.py"
        chmod +x "$SCRIPT_DIR/config_manager.py"
    fi

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行配置管理工具的创建配置功能
    python3 "$SCRIPT_DIR/config_manager.py" --script-dir "$SCRIPT_DIR" --backup-dir "$BACKUP_DIR" --create-config

    # 保存返回值
    local result=$?

    # 退出虚拟环境
    deactivate

    if [ $result -eq 0 ]; then
        echo -e "${GREEN}配置已成功创建！${NC}"
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
    else
        echo -e "${RED}配置创建失败，请重试${NC}"
    fi
}

# 查看配置（调用配置管理工具）
view_config() {
    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    if [ ! -f "$SCRIPT_DIR/config_manager.py" ]; then
        echo -e "${YELLOW}正在下载配置管理工具...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py -o "$SCRIPT_DIR/config_manager.py"
        chmod +x "$SCRIPT_DIR/config_manager.py"
    fi

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行配置管理工具的编辑配置功能
    python3 "$SCRIPT_DIR/config_manager.py" --script-dir "$SCRIPT_DIR" --backup-dir "$BACKUP_DIR" --edit-config

    # 保存返回值
    local result=$?

    # 退出虚拟环境
    deactivate

    return $result
}

# 备份配置（调用配置管理工具）
backup_config() {
    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    if [ ! -f "$SCRIPT_DIR/config_manager.py" ]; then
        echo -e "${YELLOW}正在下载配置管理工具...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py -o "$SCRIPT_DIR/config_manager.py"
        chmod +x "$SCRIPT_DIR/config_manager.py"
    fi

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行配置管理工具的备份功能
    python3 "$SCRIPT_DIR/config_manager.py" --script-dir "$SCRIPT_DIR" --backup-dir "$BACKUP_DIR" --backup

    # 保存返回值
    local result=$?

    # 退出虚拟环境
    deactivate

    return $result
}

# 恢复配置（调用配置管理工具）
restore_config() {
    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    if [ ! -f "$SCRIPT_DIR/config_manager.py" ]; then
        echo -e "${YELLOW}正在下载配置管理工具...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py -o "$SCRIPT_DIR/config_manager.py"
        chmod +x "$SCRIPT_DIR/config_manager.py"
    fi

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

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行配置管理工具的恢复功能
    python3 "$SCRIPT_DIR/config_manager.py" --script-dir "$SCRIPT_DIR" --backup-dir "$BACKUP_DIR" --restore

    # 保存返回值
    local result=$?

    # 退出虚拟环境
    deactivate

    return $result
}

# 管理小号
manage_accounts() {
    # 先下载共享库
    download_utils

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

    # 保存返回值
    local result=$?

    # 退出虚拟环境
    deactivate

    # 如果小号状态有更改（返回值为0表示成功且有更改），询问是否启动/重启脚本
    if [ $result -eq 0 ] && [ -f "$FORWARD_PY" ]; then
        # 调用处理配置更改的函数
        handle_config_change
    fi

    return $result
}

# 配置管理菜单
config_management_menu() {
    # 检查虚拟环境是否存在
    if [ ! -d "$VENV_DIR" ]; then
        echo -e "${RED}错误：虚拟环境不存在，请先安装依赖！${NC}"
        echo -e "${YELLOW}正在自动进入安装依赖选项...${NC}"
        install_dependencies
        if [ $? -ne 0 ]; then
            echo -e "${RED}安装依赖失败，无法继续配置${NC}"
            return 1
        fi
    fi

    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    if [ ! -f "$SCRIPT_DIR/config_manager.py" ]; then
        echo -e "${YELLOW}正在下载配置管理工具...${NC}"
        curl -fsSL https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py -o "$SCRIPT_DIR/config_manager.py"
        chmod +x "$SCRIPT_DIR/config_manager.py"
    fi

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行配置管理工具的菜单
    python3 "$SCRIPT_DIR/config_manager.py" --script-dir "$SCRIPT_DIR" --backup-dir "$BACKUP_DIR"

    # 保存返回值
    local result=$?

    # 退出虚拟环境
    deactivate

    # 如果配置有更改（返回值为0表示成功且有更改），询问是否启动/重启脚本
    if [ $result -eq 0 ] && [ -f "$FORWARD_PY" ]; then
        # 调用处理配置更改的函数
        handle_config_change
    fi

    return $result
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
