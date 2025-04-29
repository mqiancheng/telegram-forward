#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 卸载脚本
uninstall_script() {
    echo -e "${YELLOW}=== 卸载 Telegram 转发脚本 ===${NC}"
    echo -e "${RED}警告：此操作将删除所有脚本文件和配置！${NC}"
    echo -e "${YELLOW}是否继续？(y/n): ${NC}"
    read confirm
    if [ "$confirm" != "y" ]; then
        echo -e "${GREEN}已取消卸载${NC}"
        return 0
    fi

    # 询问是否备份配置
    echo -e "${YELLOW}是否在卸载前备份配置？(y/n，默认y): ${NC}"
    read backup_confirm
    if [ "$backup_confirm" = "" ] || [ "$backup_confirm" = "y" ]; then
        # 备份配置
        backup_config
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

    # 删除 config_manager.py
    if [ -f "$SCRIPT_DIR/config_manager.py" ]; then
        rm -f "$SCRIPT_DIR/config_manager.py" && echo -e "${GREEN}已删除 config_manager.py${NC}"
    fi

    # 删除 account_manager.py
    if [ -f "$SCRIPT_DIR/account_manager.py" ]; then
        rm -f "$SCRIPT_DIR/account_manager.py" && echo -e "${GREEN}已删除 account_manager.py${NC}"
    fi

    # 删除 utils.py
    if [ -f "$SCRIPT_DIR/utils.py" ]; then
        rm -f "$SCRIPT_DIR/utils.py" && echo -e "${GREEN}已删除 utils.py${NC}"
    fi

    # 删除 bin 目录
    if [ -d "$SCRIPT_DIR/bin" ]; then
        rm -rf "$SCRIPT_DIR/bin" && echo -e "${GREEN}已删除 bin 目录${NC}"
    fi

    # 删除虚拟环境
    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR" && echo -e "${GREEN}已删除虚拟环境${NC}"
    fi

    # 删除日志文件
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE" && echo -e "${GREEN}已删除日志文件${NC}"
    fi

    # 删除配置文件
    if [ -f "$CONFIG_FILE" ]; then
        rm -f "$CONFIG_FILE" && echo -e "${GREEN}已删除配置文件${NC}"
    fi

    # 删除会话文件
    session_files=$(find "$SCRIPT_DIR" -name "session_account*.session" 2>/dev/null)
    if [ -n "$session_files" ]; then
        rm -f $session_files && echo -e "${GREEN}已删除会话文件${NC}"
    fi

    # 删除会话日志文件
    session_journal_files=$(find "$SCRIPT_DIR" -name "session_account*.session-journal" 2>/dev/null)
    if [ -n "$session_journal_files" ]; then
        rm -f $session_journal_files && echo -e "${GREEN}已删除会话日志文件${NC}"
    fi

    # 删除状态文件
    if [ -f "$SCRIPT_DIR/.account_status.json" ]; then
        rm -f "$SCRIPT_DIR/.account_status.json" && echo -e "${GREEN}已删除账号状态文件${NC}"
    fi

    # 删除 logrotate 配置
    LOGROTATE_CONF="/etc/logrotate.d/telegram_forward"
    if [ -f "$LOGROTATE_CONF" ]; then
        if [ -w "$LOGROTATE_CONF" ]; then
            rm -f "$LOGROTATE_CONF" && echo -e "${GREEN}已删除 logrotate 配置${NC}"
        else
            sudo rm -f "$LOGROTATE_CONF" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}已删除 logrotate 配置${NC}"
            else
                echo -e "${YELLOW}无法删除 logrotate 配置，请手动删除 $LOGROTATE_CONF${NC}"
            fi
        fi
    fi

    # 删除快捷命令
    if [ -f "/usr/local/bin/tg" ]; then
        if [ -w "/usr/local/bin/tg" ]; then
            rm -f "/usr/local/bin/tg" && echo -e "${GREEN}已删除快捷命令${NC}"
        else
            sudo rm -f "/usr/local/bin/tg" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}已删除快捷命令${NC}"
            else
                echo -e "${YELLOW}无法删除快捷命令，请手动删除 /usr/local/bin/tg${NC}"
            fi
        fi
    fi

    # 询问是否删除备份文件
    if [ -d "$BACKUP_DIR" ] && [ "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}是否删除备份文件？(y/n，默认n): ${NC}"
        read delete_backup
        if [ "$delete_backup" = "y" ]; then
            # 列出所有备份文件
            echo -e "${YELLOW}可用的备份文件:${NC}"
            backup_files=($(find "$BACKUP_DIR" -name "forward_backup_*.tar.gz" | sort))
            
            for i in "${!backup_files[@]}"; do
                echo "$((i+1)). $(basename "${backup_files[$i]}")"
            done
            
            echo -e "${YELLOW}请选择要删除的备份文件编号（多个用空格分隔，输入 0 删除所有，输入 c 取消）:${NC}"
            read choice
            
            if [ "$choice" = "c" ]; then
                echo -e "${GREEN}已取消删除备份文件${NC}"
            elif [ "$choice" = "0" ]; then
                rm -f "$BACKUP_DIR"/forward_backup_*.tar.gz && echo -e "${GREEN}已删除所有备份文件${NC}"
            else
                for num in $choice; do
                    if [ "$num" -ge 1 ] && [ "$num" -le "${#backup_files[@]}" ]; then
                        rm -f "${backup_files[$((num-1))]}" && echo -e "${GREEN}已删除 $(basename "${backup_files[$((num-1))]}")${NC}"
                    else
                        echo -e "${RED}无效的选择: $num${NC}"
                    fi
                done
            fi
        fi
    fi

    echo -e "${GREEN}卸载完成！${NC}"
    echo -e "${YELLOW}感谢使用 Telegram 转发脚本！${NC}"
    exit 0
}
