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
    echo -e "${YELLOW}是否继续卸载脚本？(y/n，默认n): ${NC}"
    read confirm
    if [ "$confirm" != "y" ]; then
        echo -e "${GREEN}已取消卸载${NC}"
        return 0
    fi

    # 自动备份配置（有提示）
    echo -e "${YELLOW}正在自动备份小号API和会话文件...${NC}"
    backup_config
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}小号API和会话文件备份成功！备份文件保存在 $BACKUP_DIR${NC}"
    else
        echo -e "${RED}备份失败！${NC}"
        echo -e "${YELLOW}是否继续卸载？(y/n，默认n): ${NC}"
        read continue_confirm
        if [ "$continue_confirm" != "y" ]; then
            echo -e "${GREEN}已取消卸载${NC}"
            return 0
        fi
    fi

    # 询问是否删除备份文件
    echo -e "${YELLOW}是否删除备份文件夹中的备份文件？(y/n/c，默认n，c取消卸载): ${NC}"
    read delete_backup

    if [ "$delete_backup" = "c" ]; then
        echo -e "${GREEN}已取消卸载${NC}"
        return 0
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

    # 删除脚本文件和配置
    echo -e "${YELLOW}正在删除脚本文件和配置...${NC}"

    # 删除脚本目录
    if [ -d "$SCRIPT_DIR" ]; then
        echo -e "${YELLOW}正在删除脚本目录...${NC}"
        rm -rf "$SCRIPT_DIR" && echo -e "${GREEN}已删除脚本目录 $SCRIPT_DIR${NC}"
    fi

    # 删除快捷命令（如果存在）
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

    # 根据用户选择删除备份文件
    if [ "$delete_backup" = "y" ]; then
        if [ -d "$BACKUP_DIR" ]; then
            echo -e "${YELLOW}正在删除备份文件夹中的备份文件...${NC}"
            rm -rf "$BACKUP_DIR"/* && echo -e "${GREEN}已删除备份文件夹中的所有备份文件${NC}"
        fi
    else
        echo -e "${GREEN}保留备份文件夹中的备份文件${NC}"
    fi

    # 删除脚本本身（最后执行）
    if [ -f "$SELF_SCRIPT" ]; then
        echo -e "${YELLOW}正在删除脚本文件...${NC}"
        # 使用变量保存脚本路径，因为脚本即将被删除
        local script_path="$SELF_SCRIPT"

        echo -e "${GREEN}卸载完成！${NC}"
        echo -e "${YELLOW}感谢使用 Telegram 转发脚本！${NC}"

        # 如果当前执行的就是要删除的脚本，使用特殊方式退出
        if [ "$SELF_SCRIPT" = "$0" ]; then
            echo -e "${YELLOW}脚本将在3秒后自动退出并删除自身...${NC}"
            sleep 3
            # 使用exec启动一个新的shell，然后删除当前脚本
            exec bash -c "rm -f $0; echo '已删除脚本文件 $0'; exit 0"
        else
            rm -f "$script_path" && echo -e "${GREEN}已删除脚本文件 $script_path${NC}"
            exit 0
        fi
    else
        echo -e "${GREEN}卸载完成！${NC}"
        echo -e "${YELLOW}感谢使用 Telegram 转发脚本！${NC}"
        exit 0
    fi
}
