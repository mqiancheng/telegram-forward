#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 脚本版本号
SCRIPT_VERSION="2.1.2"

# 检测当前用户的主目录
if [ "$HOME" = "/root" ]; then
    USER_HOME="/root"
else
    USER_HOME="$HOME"
fi

# 设置脚本目录
SCRIPT_DIR="$USER_HOME/.telegram_forward"
MODULES_DIR="$SCRIPT_DIR/modules"
LOG_DIR="$SCRIPT_DIR/logs"
BACKUP_DIR="$USER_HOME/backup-TGfw"
LOG_FILE="$LOG_DIR/telegram_forward.log"
CONFIG_FILE="$SCRIPT_DIR/.telegram_forward.conf"
FORWARD_PY="$SCRIPT_DIR/forward.py"
VENV_DIR="$SCRIPT_DIR/venv"

# 获取当前脚本的绝对路径
SELF_SCRIPT="$(readlink -f "$0")"

# GitHub 原始内容 URL
GITHUB_RAW_URL="https://raw.githubusercontent.com/mqiancheng/telegram-forward/test"

# 显示欢迎信息
show_welcome() {
    clear
    echo -e "${YELLOW}=== Telegram 消息转发管理工具 ===${NC}"
    echo -e "${YELLOW}版本: $SCRIPT_VERSION${NC}"
    echo -e "${YELLOW}正在初始化...${NC}"
    sleep 1
}

# 加载模块
load_module() {
    local module_name="$1"
    local module_path="$MODULES_DIR/${module_name}.sh"

    # 检查模块文件是否存在
    if [ ! -f "$module_path" ]; then
        echo -e "${RED}错误：模块 $module_name 不存在！${NC}"
        return 1
    fi

    # 加载模块
    source "$module_path" 2>/dev/null
}

# 下载所有模块
download_all_modules() {
    echo -e "${YELLOW}正在下载模块...${NC}"

    # 定义所有模块列表（按依赖顺序排列）
    local all_modules=(
        "utils_module"      # 基础工具模块，应该最先加载
        "status_module"     # 状态检查模块
        "process_module"    # 进程管理模块
        "config_interface"  # 配置管理模块
        "menu_module"       # 菜单模块
        "install_module"    # 安装模块
        "log_module"        # 日志模块
        "backup_module"     # 备份模块
        "uninstall_module"  # 卸载模块
    )

    # 首先尝试下载模块包
    download_modules_package

    # 如果模块包下载失败，则尝试单独下载每个模块
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}尝试单独下载模块...${NC}"
        # 顺序下载所有模块
        for module in "${all_modules[@]}"; do
            # 检查模块文件是否存在且非空
            if [ ! -f "$MODULES_DIR/${module}.sh" ] || [ ! -s "$MODULES_DIR/${module}.sh" ]; then
                # 尝试从test分支下载
                curl -fsSL "$GITHUB_RAW_URL/modules/${module}.sh" -o "$MODULES_DIR/${module}.sh" 2>/dev/null

                # 如果下载失败，尝试从main分支下载
                if [ $? -ne 0 ] || [ ! -s "$MODULES_DIR/${module}.sh" ]; then
                    curl -fsSL "https://raw.githubusercontent.com/mqiancheng/telegram-forward/main/modules/${module}.sh" -o "$MODULES_DIR/${module}.sh" 2>/dev/null
                fi

                # 设置执行权限
                chmod +x "$MODULES_DIR/${module}.sh" 2>/dev/null
            fi
        done
    fi

    # 按顺序加载所有模块（确保依赖关系正确）
    for module in "${all_modules[@]}"; do
        if [ -f "$MODULES_DIR/${module}.sh" ]; then
            source "$MODULES_DIR/${module}.sh"
        fi
    done

    # 验证关键函数是否存在
    local missing_functions=0

    # 检查关键函数
    if ! type handle_config_change >/dev/null 2>&1; then
        echo -e "${RED}错误：handle_config_change 函数未定义${NC}"
        missing_functions=$((missing_functions+1))
    fi

    if ! type config_management_menu >/dev/null 2>&1; then
        echo -e "${RED}错误：config_management_menu 函数未定义${NC}"
        missing_functions=$((missing_functions+1))
    fi

    if ! type start_script >/dev/null 2>&1; then
        echo -e "${RED}错误：start_script 函数未定义${NC}"
        missing_functions=$((missing_functions+1))
    fi

    if ! type stop_script >/dev/null 2>&1; then
        echo -e "${RED}错误：stop_script 函数未定义${NC}"
        missing_functions=$((missing_functions+1))
    fi

    if [ $missing_functions -gt 0 ]; then
        echo -e "${RED}警告：有 $missing_functions 个关键函数未定义，模块可能未正确加载${NC}"
        echo -e "${YELLOW}请检查网络连接或GitHub仓库是否可访问${NC}"
        sleep 2
    else
        echo -e "${GREEN}所有模块加载成功${NC}"
    fi
}

# 下载并安装模块包
download_modules_package() {
    echo -e "${YELLOW}尝试下载模块包...${NC}"

    # 模块包的 URL
    local package_url="https://github.com/mqiancheng/telegram-forward/releases/download/v$SCRIPT_VERSION-modules/telegram-forward-modules.tar.gz"
    local package_file="$SCRIPT_DIR/modules.tar.gz"

    # 下载模块包
    curl -fsSL "$package_url" -o "$package_file" 2>/dev/null

    # 检查下载是否成功
    if [ $? -eq 0 ] && [ -s "$package_file" ]; then
        echo -e "${GREEN}模块包下载成功${NC}"

        # 解压模块包
        mkdir -p "$MODULES_DIR"
        tar -xzf "$package_file" -C "$MODULES_DIR" --strip-components=1 telegram-forward-modules 2>/dev/null

        # 设置执行权限
        chmod +x "$MODULES_DIR"/*.sh 2>/dev/null

        # 删除临时文件
        rm -f "$package_file"

        return 0
    else
        echo -e "${YELLOW}模块包下载失败，将尝试单独下载模块...${NC}"
        return 1
    fi
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

# 此函数已移至 utils_module.sh

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

# 检查依赖是否已安装
check_dependencies_installed() {
    # 检查虚拟环境是否存在
    if [ ! -d "$VENV_DIR" ]; then
        return 1
    fi

    # 检查关键依赖是否已安装
    if ! $PYTHON_CMD -c "import telethon" 2>/dev/null; then
        return 1
    fi

    return 0
}

# 处理主菜单选择
handle_main_menu() {
    local choice="$1"

    # 对于需要依赖的选项，先检查依赖是否已安装
    if [[ "$choice" =~ ^[2-9]$ ]] && ! check_dependencies_installed; then
        echo -e "${YELLOW}检测到依赖未安装，需要先安装依赖才能使用此功能${NC}"
        echo -e "${YELLOW}是否现在安装依赖？(y/n): ${NC}"
        read install_deps
        if [ "$install_deps" = "y" ]; then
            install_dependencies
            if [ $? -eq 0 ]; then
                configure_logrotate
                create_shortcut
                echo -e "${GREEN}依赖安装完成，现在可以使用所选功能${NC}"
                echo -e "${YELLOW}按任意键继续...${NC}"
                read -n 1
            else
                echo -e "${RED}依赖安装失败，无法继续${NC}"
                echo -e "${YELLOW}按任意键返回主菜单...${NC}"
                read -n 1
                return
            fi
        else
            echo -e "${YELLOW}已取消安装依赖，返回主菜单${NC}"
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1
            return
        fi
    fi

    case $choice in
        1)
            # 安装依赖
            install_dependencies
            if [ $? -eq 0 ]; then
                configure_logrotate
                create_shortcut
            fi
            ;;
        2)
            # 配置管理
            config_management_menu
            ;;
        3)
            # 小号状态
            manage_accounts
            ;;
        4)
            # 启动脚本
            if ! check_config_status; then
                echo -e "${RED}错误：配置文件不存在！${NC}"
                echo -e "${YELLOW}正在自动进入配置管理菜单...${NC}"
                config_management_menu
            else
                start_script
            fi
            ;;
        5)
            # 停止脚本
            stop_script
            ;;
        6)
            # 重启脚本
            if ! check_config_status; then
                echo -e "${RED}错误：配置文件不存在！${NC}"
                echo -e "${YELLOW}正在自动进入配置管理菜单...${NC}"
                config_management_menu
            else
                restart_script
                # 等待3秒，让用户看到重启结果，然后自动返回主菜单
                sleep 3
            fi
            ;;
        7)
            # 日志管理
            log_management_menu
            ;;
        8)
            # 备份管理
            backup_management_menu
            ;;
        9)
            # 系统信息
            show_system_info
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1
            ;;
        10)
            # 卸载脚本
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

    # 确保变量不为空
    if [ -z "$SCRIPT_DIR" ]; then
        SCRIPT_DIR="$USER_HOME/.telegram_forward"
        echo -e "${YELLOW}警告：SCRIPT_DIR为空，已设置为默认值：$SCRIPT_DIR${NC}"
    fi

    if [ -z "$MODULES_DIR" ]; then
        MODULES_DIR="$SCRIPT_DIR/modules"
        echo -e "${YELLOW}警告：MODULES_DIR为空，已设置为默认值：$MODULES_DIR${NC}"
    fi

    if [ -z "$LOG_DIR" ]; then
        LOG_DIR="$SCRIPT_DIR/logs"
        echo -e "${YELLOW}警告：LOG_DIR为空，已设置为默认值：$LOG_DIR${NC}"
    fi

    if [ -z "$BACKUP_DIR" ]; then
        BACKUP_DIR="$USER_HOME/backup-TGfw"
        echo -e "${YELLOW}警告：BACKUP_DIR为空，已设置为默认值：$BACKUP_DIR${NC}"
    fi

    # 创建必要的目录
    mkdir -p "$SCRIPT_DIR"
    mkdir -p "$MODULES_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$BACKUP_DIR"

    # 下载并加载所有模块
    download_all_modules

    # 显示菜单并处理用户选择
    while true; do
        show_main_menu
        read choice
        handle_main_menu "$choice"
    done
}

# 运行主程序
main