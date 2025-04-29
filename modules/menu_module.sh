#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 主菜单
show_main_menu() {
    echo -e "${YELLOW}=== Telegram 消息转发管理工具 ===${NC}"
    echo -e "${YELLOW}版本: $SCRIPT_VERSION${NC}"
    
    # 显示当前状态
    show_all_status
    
    echo "1. 安装依赖"
    echo "2. 配置管理"
    echo "3. 小号状态"
    echo "4. 启动脚本"
    echo "5. 停止脚本"
    echo "6. 重启脚本"
    echo "7. 日志管理"
    echo "8. 备份管理"
    echo "9. 系统信息"
    echo "10. 卸载脚本"
    echo "0. 退出"
    echo -e "${YELLOW}请选择一个选项：${NC}"
}

# 处理主菜单选择
handle_main_menu() {
    local choice="$1"
    
    case $choice in
        1)
            install_dependencies
            if [ $? -eq 0 ]; then
                configure_logrotate
                create_shortcut
            fi
            ;;
        2)
            config_management_menu
            ;;
        3)
            manage_accounts
            ;;
        4)
            # 检查配置文件是否存在
            if ! check_config_status; then
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
            if ! check_config_status; then
                echo -e "${RED}错误：配置文件不存在！${NC}"
                echo -e "${YELLOW}正在自动进入配置管理菜单...${NC}"
                config_management_menu
            else
                # 使用 restart_script 函数重启脚本
                restart_script
                # 无论成功与否，都返回主菜单
                sleep 1
            fi
            ;;
        7)
            log_management_menu
            ;;
        8)
            backup_management_menu
            ;;
        9)
            show_system_info
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1
            ;;
        10)
            uninstall_script
            ;;
        0)
            handle_exit
            ;;
        *)
            echo -e "${RED}无效选项，请重试！${NC}"
            ;;
    esac
}

# 处理退出
handle_exit() {
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
            return 1
            ;;
    esac
}