#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本版本号
SCRIPT_VERSION="2.0.0"

# 检测当前用户的主目录
if [ "$HOME" = "/root" ]; then
    USER_HOME="/root"
else
    USER_HOME="$HOME"
fi

# 脚本路径和文件
SCRIPT_DIR="$USER_HOME/.telegram_forward"
FORWARD_PY="$SCRIPT_DIR/forward.py"
LOG_FILE="$SCRIPT_DIR/forward.log"
VENV_DIR="$SCRIPT_DIR/venv"
SELF_SCRIPT="$0" # 当前脚本路径
CONFIG_FILE="$SCRIPT_DIR/.telegram_forward.conf"
BACKUP_DIR="/home/backup-TGfw" # 备份目录
MODULES_DIR="$SCRIPT_DIR/modules" # 模块目录
GITHUB_RAW_URL="https://raw.githubusercontent.com/mqiancheng/telegram-forward/main"

# 检测系统类型
if [ -f "/etc/os-release" ]; then
    . /etc/os-release
    OS_TYPE="$ID"
else
    OS_TYPE="unknown"
fi

# 加载配置文件（如果存在）
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"
fi

# 创建必要的目录
mkdir -p "$SCRIPT_DIR"
mkdir -p "$MODULES_DIR"

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${YELLOW}=== Telegram 消息转发管理工具 ===${NC}"
    echo -e "${YELLOW}版本: $SCRIPT_VERSION${NC}"
    echo -e "${YELLOW}正在初始化，请稍候...${NC}"
}

# 下载模块
download_module() {
    local module_name="$1"
    local module_url="$GITHUB_RAW_URL/modules/${module_name}.sh"
    local module_path="$MODULES_DIR/${module_name}.sh"
    
    # 检查模块是否已存在
    if [ ! -f "$module_path" ]; then
        echo -e "${YELLOW}正在下载 ${module_name} 模块...${NC}"
        curl -fsSL "$module_url" -o "$module_path"
        chmod +x "$module_path"
        echo -e "${GREEN}${module_name} 模块下载完成${NC}"
    fi
}

# 加载模块
load_module() {
    local module_name="$1"
    local module_path="$MODULES_DIR/${module_name}.sh"
    
    # 检查模块是否存在
    if [ -f "$module_path" ]; then
        source "$module_path"
    else
        echo -e "${RED}错误：模块 ${module_name} 不存在！${NC}"
        download_module "$module_name"
        source "$module_path"
    fi
}

# 并行下载核心模块
download_core_modules() {
    echo -e "${YELLOW}正在下载核心模块...${NC}"
    
    # 创建一个临时目录来存储下载状态
    local tmp_dir=$(mktemp -d)
    
    # 定义核心模块列表
    local core_modules=("utils_module" "status_module" "menu_module")
    
    # 并行下载所有核心模块
    for module in "${core_modules[@]}"; do
        (
            download_module "$module"
            touch "$tmp_dir/$module.done"
        ) &
    done
    
    # 显示下载进度
    local total=${#core_modules[@]}
    local done=0
    local spinner=('|' '/' '-' '\')
    local i=0
    
    while [ $done -lt $total ]; do
        done=$(ls "$tmp_dir"/*.done 2>/dev/null | wc -l)
        percentage=$((done * 100 / total))
        
        echo -ne "\r${YELLOW}下载进度: ${percentage}% ${spinner[$i]} ${NC}"
        i=$(( (i+1) % 4 ))
        sleep 0.2
    done
    
    echo -e "\r${GREEN}核心模块下载完成！                ${NC}"
    
    # 清理临时目录
    rm -rf "$tmp_dir"
}

# 按需下载其他模块
download_module_if_needed() {
    local module_name="$1"
    local module_path="$MODULES_DIR/${module_name}.sh"
    
    if [ ! -f "$module_path" ]; then
        download_module "$module_name"
    fi
    
    load_module "$module_name"
}

# 检查脚本状态
check_script_status() {
    if pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "脚本状态: ${GREEN}运行中${NC}"
        return 0
    else
        echo -e "脚本状态: ${RED}未运行${NC}"
        return 1
    fi
}

# 检查虚拟环境状态
check_venv_status() {
    if [ -d "$VENV_DIR" ]; then
        echo -e "虚拟环境: ${GREEN}已创建${NC}"
        return 0
    else
        echo -e "虚拟环境: ${RED}未创建${NC}"
        return 1
    fi
}

# 检查配置状态
check_config_status() {
    if [ -f "$FORWARD_PY" ]; then
        echo -e "配置状态: ${GREEN}已配置（forward.py 存在）${NC}"
        return 0
    else
        echo -e "配置状态: ${RED}未配置（forward.py 不存在）${NC}"
        return 1
    fi
}

# 检查小号状态
check_account_status() {
    if [ -f "$FORWARD_PY" ]; then
        # 检查 .account_status.json 文件是否存在
        if [ -f "$SCRIPT_DIR/.account_status.json" ]; then
            # 检查文件内容
            if grep -q "\"status\":\"ok\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                # 计算正常账号数量
                normal_count=$(grep -o "\"status\":\"ok\"" "$SCRIPT_DIR/.account_status.json" | wc -l)
                total_count=$(grep -o "\"status\":" "$SCRIPT_DIR/.account_status.json" | wc -l)
                
                if [ $normal_count -eq $total_count ]; then
                    echo -e "小号状态: ${GREEN}正常（$normal_count 个小号）${NC}"
                else
                    echo -e "小号状态: ${YELLOW}部分异常（$normal_count/$total_count 个小号正常）${NC}"
                fi
            elif grep -q "\"status\":\"unauthorized\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                echo -e "小号状态: ${RED}未授权（需要重新登录）${NC}"
            elif grep -q "\"status\":\"error\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                echo -e "小号状态: ${RED}异常（连接错误）${NC}"
            else
                echo -e "小号状态: ${YELLOW}未知${NC}"
            fi
        else
            echo -e "小号状态: ${YELLOW}未检测（状态文件不存在）${NC}"
        fi
    else
        echo -e "小号状态: ${RED}未配置${NC}"
    fi
}

# 显示所有状态
show_all_status() {
    echo -e "${YELLOW}--- 当前状态 ---${NC}"
    check_script_status
    check_venv_status
    check_config_status
    check_account_status
    echo -e "${YELLOW}----------------${NC}"
}

# 主菜单
show_main_menu() {
    clear
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
            # 安装依赖
            download_module_if_needed "install_module"
            install_dependencies
            if [ $? -eq 0 ]; then
                download_module_if_needed "log_module"
                configure_logrotate
                create_shortcut
            fi
            ;;
        2)
            # 配置管理
            download_module_if_needed "config_interface"
            config_management_menu
            ;;
        3)
            # 小号状态
            download_module_if_needed "config_interface"
            manage_accounts
            ;;
        4)
            # 启动脚本
            if ! check_config_status; then
                echo -e "${RED}错误：配置文件不存在！${NC}"
                echo -e "${YELLOW}正在自动进入配置管理菜单...${NC}"
                download_module_if_needed "config_interface"
                config_management_menu
            else
                download_module_if_needed "process_module"
                start_script
            fi
            ;;
        5)
            # 停止脚本
            download_module_if_needed "process_module"
            stop_script
            ;;
        6)
            # 重启脚本
            if ! check_config_status; then
                echo -e "${RED}错误：配置文件不存在！${NC}"
                echo -e "${YELLOW}正在自动进入配置管理菜单...${NC}"
                download_module_if_needed "config_interface"
                config_management_menu
            else
                download_module_if_needed "process_module"
                restart_script
                # 无论成功与否，都返回主菜单
                sleep 1
            fi
            ;;
        7)
            # 日志管理
            download_module_if_needed "log_module"
            log_management_menu
            ;;
        8)
            # 备份管理
            download_module_if_needed "backup_module"
            backup_management_menu
            ;;
        9)
            # 系统信息
            download_module_if_needed "utils_module"
            show_system_info
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1
            ;;
        10)
            # 卸载脚本
            download_module_if_needed "uninstall_module"
            uninstall_script
            ;;
        0)
            # 退出
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
            download_module_if_needed "process_module"
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

# 主程序
main() {
    # 显示欢迎信息
    show_welcome
    
    # 下载核心模块
    download_core_modules
    
    # 加载核心模块
    load_module "utils_module"
    load_module "status_module"
    load_module "menu_module"
    
    # 显示菜单并处理用户选择
    while true; do
        show_main_menu
        read choice
        handle_main_menu "$choice"
    done
}

# 运行主程序
main