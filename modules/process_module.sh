#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 清理进程
cleanup_processes() {
    # 清理可能残留的进程
    if pgrep -f "run_forward.sh" > /dev/null; then
        echo -e "${YELLOW}清理残留的 run_forward.sh 进程...${NC}"
        pkill -f "run_forward.sh" 2>/dev/null
        sleep 1
    fi

    if pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "${YELLOW}清理残留的 forward.py 进程...${NC}"
        pkill -f "python.*forward.py" 2>/dev/null
        sleep 1
    fi

    # 清理 PID 文件
    cleanup_pid_files
}

# 清理 PID 文件
cleanup_pid_files() {
    if [ -f "$SCRIPT_DIR/forward.pid" ]; then
        rm -f "$SCRIPT_DIR/forward.pid"
    fi

    if [ -f "$SCRIPT_DIR/monitor.pid" ]; then
        rm -f "$SCRIPT_DIR/monitor.pid"
    fi
}

# 启动脚本
start_script() {
    # 可选参数：是否静默模式
    local silent_mode=${1:-false}

    if [ "$silent_mode" != "true" ]; then
        echo -e "${YELLOW}正在启动服务...${NC}"
    fi

    # 检查 forward.py 是否存在
    if [ ! -f "$FORWARD_PY" ]; then
        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}forward.py 文件不存在，请先配置脚本！${NC}"
        fi
        return 1
    fi

    # 检查虚拟环境是否存在
    if [ ! -d "$VENV_DIR" ]; then
        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}虚拟环境不存在，请先安装依赖！${NC}"
        fi
        return 1
    fi

    # 清理残留进程和状态文件
    if [ "$silent_mode" != "true" ]; then
        cleanup_processes
    else
        cleanup_processes > /dev/null 2>&1
    fi

    # 使用脚本启动
    if [ "$silent_mode" != "true" ]; then
        echo -e "${YELLOW}正在启动转发脚本...${NC}"
    fi

    # 检查启动脚本是否存在
    if [ ! -f "$SCRIPT_DIR/bin/run_forward.sh" ]; then
        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}找不到启动脚本，正在重新创建...${NC}"
        fi

        # 创建目录
        mkdir -p "$SCRIPT_DIR/bin"

        # 创建启动脚本
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
    fi

    # 执行启动脚本
    if [ -f "$SCRIPT_DIR/bin/run_forward.sh" ]; then
        if [ "$silent_mode" = "true" ]; then
            $SCRIPT_DIR/bin/run_forward.sh > /dev/null 2>&1
        else
            $SCRIPT_DIR/bin/run_forward.sh
        fi
        sleep 2

        # 检查脚本是否成功启动
        if [ -f "$SCRIPT_DIR/forward.pid" ]; then
            pid=$(cat "$SCRIPT_DIR/forward.pid" 2>/dev/null)
            if [ -n "$pid" ] && ps -p $pid > /dev/null 2>&1; then
                if [ "$silent_mode" != "true" ]; then
                    echo -e "${GREEN}脚本已成功启动！${NC}"
                fi
                return 0
            fi
        fi

        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}脚本启动失败，请检查日志${NC}"
        fi
        return 1
    else
        if [ "$silent_mode" != "true" ]; then
            echo -e "${RED}找不到启动脚本${NC}"
        fi
        return 1
    fi
}

# 停止脚本
stop_script() {
    echo -e "${YELLOW}正在停止服务...${NC}"

    # 使用脚本停止
    if [ -f "$SCRIPT_DIR/bin/stop_forward.sh" ]; then
        $SCRIPT_DIR/bin/stop_forward.sh
    else
        echo -e "${YELLOW}找不到停止脚本，尝试直接终止进程...${NC}"
    fi

    # 停止所有 run_forward.sh 进程
    if pgrep -f "run_forward.sh" > /dev/null; then
        echo -e "${YELLOW}正在停止 run_forward.sh 进程...${NC}"
        pkill -f "run_forward.sh" 2>/dev/null
        sleep 1
    fi

    # 停止所有 forward.py 进程
    if pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "${YELLOW}正在停止 forward.py 进程...${NC}"
        pkill -f "python.*forward.py" 2>/dev/null
        sleep 1
    fi

    # 清理可能残留的进程
    cleanup_processes

    # 验证 forward.py 停止状态
    if ! pgrep -f "python.*forward.py" > /dev/null && ! pgrep -f "run_forward.sh" > /dev/null; then
        echo -e "${GREEN}所有转发脚本已成功停止！${NC}"
    else
        echo -e "${RED}部分转发脚本停止失败，尝试强制终止...${NC}"
        pkill -9 -f "python.*forward.py" 2>/dev/null
        pkill -9 -f "run_forward.sh" 2>/dev/null
        sleep 1

        if ! pgrep -f "python.*forward.py" > /dev/null && ! pgrep -f "run_forward.sh" > /dev/null; then
            echo -e "${GREEN}所有转发脚本已强制停止！${NC}"
        else
            echo -e "${RED}无法停止所有转发脚本，请手动检查进程${NC}"
            return 1
        fi
    fi

    # 删除所有 PID 文件
    if [ -f "$SCRIPT_DIR/forward.pid" ]; then
        rm -f "$SCRIPT_DIR/forward.pid"
    fi

    if [ -f "$SCRIPT_DIR/monitor.pid" ]; then
        rm -f "$SCRIPT_DIR/monitor.pid"
    fi

    return 0
}

# 重启脚本
restart_script() {
    echo -e "${YELLOW}正在重启脚本...${NC}"

    # 先停止脚本
    stop_script

    # 等待一下，确保所有进程都已停止
    sleep 2

    # 再启动脚本
    start_script

    # 检查脚本是否成功启动
    if pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "${GREEN}脚本已成功重启！${NC}"
        echo -e "${YELLOW}按任意键返回主菜单...${NC}"
        read -n 1
        return 0
    else
        echo -e "${RED}脚本重启失败，请检查日志${NC}"
        echo -e "${YELLOW}按任意键返回主菜单...${NC}"
        read -n 1
        return 1
    fi
}

# 查看日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}正在查看日志（按 q 退出）...${NC}"
        less $LOG_FILE
        echo -e "${GREEN}日志查看完成！${NC}"
    else
        echo -e "${RED}日志文件不存在！${NC}"
    fi
}

# 检查脚本状态
check_script_status() {
    if pgrep -f "python.*forward.py" > /dev/null; then
        echo -e "脚本状态: ${GREEN}运行中${NC}"

        # 显示 PID
        if [ -f "$SCRIPT_DIR/forward.pid" ]; then
            pid=$(cat "$SCRIPT_DIR/forward.pid" 2>/dev/null)
            if [ -n "$pid" ]; then
                echo -e "PID: $pid"
            fi
        fi
    else
        echo -e "脚本状态: ${RED}未运行${NC}"
    fi
}

# 检查虚拟环境状态
check_venv_status() {
    if [ -d "$VENV_DIR" ]; then
        echo -e "虚拟环境: ${GREEN}已创建${NC}"
    else
        echo -e "虚拟环境: ${RED}未创建${NC}"
    fi
}

# 检查配置状态
check_config_status() {
    if [ -f "$FORWARD_PY" ]; then
        echo -e "配置状态: ${GREEN}已配置（forward.py 存在）${NC}"
    else
        echo -e "配置状态: ${RED}未配置（forward.py 不存在）${NC}"
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
        fi
    else
        echo -e "小号状态: ${RED}未配置${NC}"
    fi
}
