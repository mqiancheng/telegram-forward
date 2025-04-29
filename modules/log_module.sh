#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 查看日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}正在查看日志（按 q 退出查看日志）...${NC}"
        less $LOG_FILE
        echo -e "${GREEN}日志查看完成！${NC}"
    else
        echo -e "${RED}日志文件不存在！${NC}"
    fi
}

# 配置日志轮转
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

# 清理日志
clean_logs() {
    echo -e "${YELLOW}正在清理日志...${NC}"

    if [ -f "$LOG_FILE" ]; then
        # 询问是否备份当前日志
        echo -e "${YELLOW}是否备份当前日志？(y/n，默认y): ${NC}"
        read backup_log
        if [ "$backup_log" = "" ] || [ "$backup_log" = "y" ]; then
            # 备份日志
            log_backup="$LOG_FILE.$(date +%Y%m%d%H%M%S).bak"
            cp "$LOG_FILE" "$log_backup"
            echo -e "${GREEN}已备份日志到 $log_backup${NC}"
        fi

        # 清空日志文件
        > "$LOG_FILE"
        echo -e "${GREEN}已清空日志文件${NC}"
    else
        echo -e "${RED}日志文件不存在！${NC}"
    fi
}

# 日志管理菜单
log_management_menu() {
    while true; do
        echo -e "${YELLOW}=== 日志管理菜单 ===${NC}"
        echo "1. 查看日志（按q退出查看日志）"
        echo "2. 配置日志轮转"
        echo "3. 清理日志"
        echo "0. 返回主菜单"
        echo -e "${YELLOW}请选择一个选项：${NC}"
        read choice

        case $choice in
            1)
                view_log
                ;;
            2)
                configure_logrotate
                ;;
            3)
                clean_logs
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
