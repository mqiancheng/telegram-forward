#!/usr/bin/env python3
import os
import sys
import subprocess
import re
import json

# 颜色代码
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
NC = '\033[0m'  # No Color

def print_colored(text, color):
    """打印彩色文本"""
    print(f"{color}{text}{NC}")

def get_script_dir():
    """获取脚本目录"""
    # 检测当前用户的主目录
    if os.environ.get('HOME') == "/root":
        user_home = "/root"
    else:
        user_home = os.environ.get('HOME', "/home/" + os.environ.get('USER', 'user'))

    # 设置脚本目录
    return os.path.join(user_home, ".telegram_forward")

def is_script_running(script_dir):
    """检查脚本是否正在运行"""
    # 检查 PID 文件
    if os.path.exists(os.path.join(script_dir, "forward.pid")):
        try:
            with open(os.path.join(script_dir, "forward.pid"), 'r') as f:
                pid = int(f.read().strip())
            # 检查进程是否存在
            try:
                os.kill(pid, 0)  # 发送信号0，不会真正发送信号，只检查进程是否存在
                return True
            except OSError:
                return False
        except:
            pass
    
    # 直接检查 Python 进程
    try:
        result = subprocess.run(["pgrep", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.returncode == 0
    except:
        # 如果 pgrep 命令不可用，尝试使用 ps 命令
        try:
            result = subprocess.run(["ps", "aux"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output = result.stdout.decode('utf-8')
            return "python" in output and "forward.py" in output
        except:
            return False

def stop_script(script_dir):
    """停止转发脚本"""
    # 检查脚本是否在运行
    if not is_script_running(script_dir):
        print_colored("转发脚本当前未运行，无需停止", YELLOW)
        return True
    
    print_colored("正在停止服务...", YELLOW)

    # 使用脚本停止
    stop_script_path = os.path.join(script_dir, "bin", "stop_forward.sh")
    if os.path.exists(stop_script_path):
        subprocess.run([stop_script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print_colored("转发脚本已停止！", GREEN)
        return True
    else:
        print_colored("找不到停止脚本，尝试直接终止进程...", YELLOW)
        subprocess.run(["pkill", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        # 验证 forward.py 停止状态
        try:
            result = subprocess.run(["pgrep", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode != 0:
                print_colored("转发脚本已成功停止！", GREEN)
                return True
            else:
                print_colored("转发脚本停止失败，尝试强制终止...", RED)
                subprocess.run(["pkill", "-9", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                return True
        except:
            print_colored("检查进程状态时出错", RED)
            return False

def start_script(script_dir):
    """启动转发脚本"""
    # 检查脚本是否已经在运行
    if is_script_running(script_dir):
        print_colored("转发脚本已经在运行中，无需重新启动", YELLOW)
        return True
    
    print_colored("正在启动服务...", YELLOW)
    
    # 使用脚本启动
    start_script_path = os.path.join(script_dir, "bin", "run_forward.sh")
    if os.path.exists(start_script_path):
        subprocess.run([start_script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        print_colored("转发脚本已启动！", GREEN)
        return True
    else:
        print_colored("找不到启动脚本，无法启动服务", RED)
        return False

def restart_script(script_dir):
    """重启转发脚本"""
    # 检查脚本是否正在运行
    if is_script_running(script_dir):
        if stop_script(script_dir):
            return start_script(script_dir)
        return False
    else:
        # 如果脚本没有运行，直接启动
        print_colored("转发脚本当前未运行，正在启动...", YELLOW)
        return start_script(script_dir)

def parse_forward_py(forward_py_path):
    """解析 forward.py 文件，提取账号信息"""
    if not os.path.exists(forward_py_path):
        return None

    accounts = []
    try:
        with open(forward_py_path, 'r') as f:
            content = f.read()

        # 提取 accounts 部分
        start_marker = "accounts = ["
        end_marker = "]"

        start_idx = content.find(start_marker) + len(start_marker)
        end_idx = content.find(end_marker, start_idx)

        if start_idx > 0 and end_idx > start_idx:
            accounts_str = content[start_idx:end_idx].strip()

            # 解析每个账号
            account_pattern = r"{\s*'api_id':\s*'([^']*)',\s*'api_hash':\s*'([^']*)',\s*'session':\s*'([^']*)'\s*}"
            matches = re.findall(account_pattern, accounts_str)

            for match in matches:
                api_id, api_hash, session = match
                accounts.append({
                    'api_id': api_id,
                    'api_hash': api_hash,
                    'session': session
                })
    except Exception as e:
        print_colored(f"解析 forward.py 时出错: {e}", RED)
        return None

    return accounts

def edit_config_file(forward_py_path):
    """编辑配置文件"""
    if os.path.exists(forward_py_path):
        if os.name == 'nt':  # Windows
            subprocess.run(["notepad", forward_py_path], shell=True)
        else:  # Linux/Mac
            editor = os.environ.get('EDITOR', 'nano')
            subprocess.run([editor, forward_py_path], shell=True)
        print_colored("配置已保存！", GREEN)
        return True
    else:
        print_colored("forward.py 文件不存在，请先创建配置", RED)
        return False
