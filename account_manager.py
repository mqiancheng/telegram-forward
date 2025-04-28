#!/usr/bin/env python3
from telethon import TelegramClient
import asyncio
import sys
import os
import json
import subprocess
import argparse
import re

# 颜色代码
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
NC = '\033[0m'  # No Color

def print_colored(text, color):
    """打印彩色文本"""
    print(f"{color}{text}{NC}")

async def check_account(session_file, api_id, api_hash):
    """检查账号状态，返回状态和用户信息"""
    try:
        # 创建客户端但不连接
        client = TelegramClient(session_file, api_id, api_hash)
        
        # 尝试连接
        await client.connect()
        
        # 检查是否已授权
        if not await client.is_user_authorized():
            await client.disconnect()
            return {
                "status": "unauthorized",
                "message": "账号未授权，需要重新登录",
                "session": session_file
            }
        
        # 获取用户信息
        me = await client.get_me()
        
        # 断开连接
        await client.disconnect()
        
        # 返回状态和用户信息
        return {
            "status": "ok",
            "message": "账号状态正常",
            "session": session_file,
            "user_id": me.id,
            "username": me.username,
            "first_name": me.first_name,
            "last_name": me.last_name,
            "phone": me.phone
        }
    except Exception as e:
        # 捕获所有异常
        return {
            "status": "error",
            "message": str(e),
            "session": session_file
        }

async def check_all_accounts(accounts):
    """检查所有账号状态"""
    results = []
    for account in accounts:
        session = account['session']
        api_id = account['api_id']
        api_hash = account['api_hash']
        
        # 检查账号状态
        result = await check_account(session, api_id, api_hash)
        results.append(result)
    
    return results

def parse_forward_py(file_path):
    """解析 forward.py 文件，提取账号信息"""
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        # 提取 accounts 部分
        accounts_start = content.find('accounts = [')
        accounts_end = content.find(']', accounts_start)
        
        if accounts_start == -1 or accounts_end == -1:
            return []
        
        # 提取账号信息
        accounts_str = content[accounts_start:accounts_end+1]
        
        # 将单引号替换为双引号以便 JSON 解析
        accounts_str = accounts_str.replace("'", '"')
        accounts_str = accounts_str.replace("accounts = ", "")
        
        # 解析 JSON
        try:
            accounts = json.loads(accounts_str)
            return accounts
        except json.JSONDecodeError:
            # 如果 JSON 解析失败，使用更简单的方法
            accounts = []
            lines = accounts_str.strip()[1:-1].split('{')
            for line in lines:
                if not line.strip():
                    continue
                line = '{' + line
                if line.endswith(','):
                    line = line[:-1]
                try:
                    account = eval(line)
                    accounts.append(account)
                except:
                    pass
            return accounts
    except Exception as e:
        print_colored(f"解析 forward.py 失败: {e}", RED)
        return []

async def reauthorize_account(script_dir, session, api_id, api_hash):
    """重新授权账号"""
    print_colored(f"正在重新授权账号 [session: {session}]...", YELLOW)
    
    # 删除旧的 session 文件
    session_file = os.path.join(script_dir, f"{session}.session")
    if os.path.exists(session_file):
        os.remove(session_file)
    
    # 创建客户端
    client = TelegramClient(os.path.join(script_dir, session), api_id, api_hash)
    
    # 连接并登录
    await client.connect()
    
    if not await client.is_user_authorized():
        print("请登录您的 Telegram 账号")
        
        # 获取手机号
        phone = input("请输入您的手机号（包含国家代码，例如 +86）: ")
        
        # 发送验证码
        await client.send_code_request(phone)
        
        # 输入验证码
        code = input("请输入收到的验证码: ")
        
        try:
            # 尝试使用验证码登录
            await client.sign_in(phone, code)
            print("登录成功！")
        except Exception as e:
            # 如果需要密码（两步验证）
            if "password" in str(e).lower():
                password = input("请输入您的两步验证密码: ")
                await client.sign_in(password=password)
                print("登录成功！")
            else:
                print(f"登录失败: {e}")
                await client.disconnect()
                return False
    else:
        print("已经登录！")
    
    # 获取用户信息
    me = await client.get_me()
    first_name = me.first_name if me.first_name else ""
    username = me.username if me.username else ""
    print(f"已登录为: {first_name} (@{username})")
    
    # 断开连接
    await client.disconnect()
    
    print_colored(f"账号重新授权完成！", GREEN)
    return True

def stop_script(script_dir):
    """停止转发脚本"""
    print_colored("正在停止服务...", YELLOW)
    
    # 使用脚本停止
    stop_script_path = os.path.join(script_dir, "bin", "stop_forward.sh")
    if os.path.exists(stop_script_path):
        subprocess.run([stop_script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    else:
        print_colored("找不到停止脚本，尝试直接终止进程...", YELLOW)
        subprocess.run(["pkill", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    # 验证 forward.py 停止状态
    try:
        result = subprocess.run(["pgrep", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0:
            print_colored("转发脚本已成功停止！", GREEN)
        else:
            print_colored("转发脚本停止失败，尝试强制终止...", RED)
            subprocess.run(["pkill", "-9", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            # 再次检查
            result = subprocess.run(["pgrep", "-f", "python.*forward.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode != 0:
                print_colored("转发脚本已强制停止！", GREEN)
            else:
                print_colored("无法停止转发脚本，请手动检查进程", RED)
                return False
    except Exception as e:
        print_colored(f"停止脚本时出错: {e}", RED)
        return False
    
    return True

async def show_accounts_menu(script_dir, forward_py_path):
    """显示小号状态菜单"""
    while True:
        print_colored("=== 小号状态菜单 ===", YELLOW)
        print_colored("使用说明：输入序号并回车重新配置标红异常状态的小号", YELLOW)
        print_colored("对于有多个小号异常的，请输入数字加空格，例如：2 3 6", YELLOW)
        
        # 检查 forward.py 是否存在
        if not os.path.exists(forward_py_path):
            print_colored("错误：配置文件不存在！", RED)
            print_colored("请先使用选项 2 进行配置管理，创建配置文件。", YELLOW)
            input("按 Enter 键返回主菜单...")
            return
        
        # 解析 forward.py
        accounts = parse_forward_py(forward_py_path)
        
        if not accounts:
            print_colored("错误：无法解析账号信息", RED)
            input("按 Enter 键返回主菜单...")
            return
        
        # 检查所有账号状态
        results = await check_all_accounts(accounts)
        
        # 保存状态到临时文件
        status_file = os.path.join(script_dir, ".account_status.json")
        with open(status_file, 'w') as f:
            json.dump(results, f, ensure_ascii=False)
        
        # 显示小号列表
        for i, account in enumerate(results, 1):
            status = account.get("status", "unknown")
            session = account.get("session", "")
            username = account.get("username", "")
            first_name = account.get("first_name", "")
            phone = account.get("phone", "")
            
            # 构建显示名称
            display_name = ""
            if username:
                display_name = f"@{username}"
            elif first_name:
                display_name = first_name
            elif phone:
                display_name = phone
            else:
                display_name = f"小号{i}"
            
            # 根据状态显示不同颜色
            if status == "ok":
                print_colored(f"{i}. {display_name} (正常)", GREEN)
            else:
                message = account.get("message", "未知错误")
                print_colored(f"{i}. {display_name} (异常: {message})", RED)
        
        print_colored("----------------", YELLOW)
        print("0. 返回主菜单")
        choice = input(f"{YELLOW}请输入要重新授权的小号序号（多个用空格分隔）：{NC}")
        
        # 检查是否返回主菜单
        if choice.strip() == "0":
            return
        
        # 处理用户输入
        if choice.strip():
            # 停止脚本
            stop_script(script_dir)
            
            # 重新授权选择的小号
            indices = [int(idx) for idx in choice.split() if idx.isdigit()]
            
            for idx in indices:
                if 1 <= idx <= len(accounts):
                    account = accounts[idx-1]
                    session = account['session']
                    api_id = account['api_id']
                    api_hash = account['api_hash']
                    
                    # 重新授权
                    await reauthorize_account(script_dir, session, api_id, api_hash)
                else:
                    print_colored(f"错误：无效的索引 {idx}", RED)
            
            print_colored("所有选择的小号已重新授权完成！", GREEN)

def get_script_dir():
    """获取脚本目录"""
    # 检测当前用户的主目录
    if os.environ.get('HOME') == "/root":
        user_home = "/root"
    else:
        user_home = os.environ.get('HOME', "/home/" + os.environ.get('USER', 'user'))
    
    # 设置脚本目录
    return os.path.join(user_home, ".telegram_forward")

async def main():
    parser = argparse.ArgumentParser(description='Telegram 小号管理工具')
    parser.add_argument('--script-dir', help='脚本目录路径', default=get_script_dir())
    args = parser.parse_args()
    
    script_dir = args.script_dir
    forward_py_path = os.path.join(script_dir, "forward.py")
    
    await show_accounts_menu(script_dir, forward_py_path)

if __name__ == "__main__":
    asyncio.run(main())
