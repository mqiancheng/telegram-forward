#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 备份配置
backup_config() {
    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    download_python_module "config_manager" "https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py"

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

# 恢复配置
restore_config() {
    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    download_python_module "config_manager" "https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py"

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

# 管理备份
manage_backups() {
    # 先下载共享库
    download_utils

    # 检查 config_manager.py 是否存在
    download_python_module "config_manager" "https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/config_manager.py"

    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"

    # 运行配置管理工具的备份管理功能
    python3 "$SCRIPT_DIR/config_manager.py" --script-dir "$SCRIPT_DIR" --backup-dir "$BACKUP_DIR" --manage-backups

    # 退出虚拟环境
    deactivate

    return $?
}

# 备份管理菜单
backup_management_menu() {
    while true; do
        echo -e "${YELLOW}=== 备份管理菜单 ===${NC}"
        echo "1. 创建备份"
        echo "2. 恢复备份"
        echo "3. 管理备份"
        echo "0. 返回主菜单"
        echo -e "${YELLOW}请选择一个选项：${NC}"
        read choice
        
        case $choice in
            1)
                backup_config
                ;;
            2)
                restore_config
                ;;
            3)
                manage_backups
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
