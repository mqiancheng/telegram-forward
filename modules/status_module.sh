#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查脚本运行状态
check_script_status() {
    local max_retries=3
    local retry_delay=2
    local status="未知"

    for ((i=1; i<=$max_retries; i++)); do
        # 检查 PID 文件
        if [ -f "$SCRIPT_DIR/forward.pid" ]; then
            pid=$(cat "$SCRIPT_DIR/forward.pid")
            if ps -p $pid > /dev/null; then
                status="运行中"
                echo -e "脚本状态: ${GREEN}运行中${NC}"
                echo -e "PID: $pid"
                return 0
            fi
        # 直接检查 Python 进程
        elif pgrep -f "python.*forward.py" > /dev/null; then
            status="运行中"
            echo -e "脚本状态: ${GREEN}运行中${NC}"
            return 0
        fi

        if [ $i -lt $max_retries ]; then
            sleep $retry_delay
        fi
    done

    echo -e "脚本状态: ${RED}未运行${NC}"
    return 1
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

# 检查 forward.py 是否存在
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
                    return 0
                else
                    echo -e "小号状态: ${YELLOW}部分异常（$normal_count/$total_count 个小号正常）${NC}"
                    return 2
                fi
            elif grep -q "\"status\":\"unauthorized\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                echo -e "小号状态: ${RED}未授权（需要重新登录）${NC}"
                return 1
            elif grep -q "\"status\":\"error\"" "$SCRIPT_DIR/.account_status.json" 2>/dev/null; then
                echo -e "小号状态: ${RED}异常（连接错误）${NC}"
                return 1
            else
                echo -e "小号状态: ${YELLOW}未知${NC}"
                return 3
            fi
        else
            echo -e "小号状态: ${YELLOW}未检测（状态文件不存在）${NC}"
            return 3
        fi
    else
        echo -e "小号状态: ${RED}未配置${NC}"
        return 1
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
