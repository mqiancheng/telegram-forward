#!/usr/bin/env python3
from telethon import TelegramClient
import asyncio
import sys
import os
import json
import subprocess
import argparse
import re

# 导入共享库
from utils import (
    GREEN, RED, YELLOW, NC,
    print_colored, get_script_dir, is_script_running,
    stop_script, start_script, restart_script, parse_forward_py
)

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

# 使用共享库中的 parse_forward_py 函数

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

# 使用共享库中的 stop_script 函数

async def add_account(script_dir, forward_py_path):
    """添加新小号"""
    print_colored("=== 添加新小号 ===", YELLOW)

    # 检查 forward.py 是否存在
    if not os.path.exists(forward_py_path):
        print_colored("错误：配置文件不存在！", RED)
        print_colored("请先使用选项 2 进行配置管理，创建配置文件。", YELLOW)
        input("按 Enter 键返回...")
        return False

    # 解析 forward.py
    accounts = parse_forward_py(forward_py_path)
    account_index = len(accounts) + 1

    # 收集新小号信息
    print_colored(f"正在添加小号 {account_index}", YELLOW)
    api_id = input(f"请输入小号{account_index}的 api_id（从 my.telegram.org 获取）：").strip()
    api_hash = input(f"请输入小号{account_index}的 api_hash（从 my.telegram.org 获取）：").strip()
    session_name = f"session_account{account_index}"

    # 读取 forward.py 文件
    with open(forward_py_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 找到 accounts 数组的结束位置
    accounts_start = content.find("accounts = [")
    accounts_end = content.find("]", accounts_start)

    if accounts_start == -1 or accounts_end == -1:
        print_colored("错误：无法解析 forward.py 文件中的账号数组", RED)
        input("按 Enter 键返回...")
        return False

    # 构建新账号字符串
    new_account_str = f"""    {{
        'api_id': '{api_id}',
        'api_hash': '{api_hash}',
        'session': '{session_name}'
    }},\n"""

    # 在数组结束前添加新账号
    new_content = content[:accounts_end] + new_account_str + content[accounts_end:]

    # 写回文件
    with open(forward_py_path, 'w', encoding='utf-8') as f:
        f.write(new_content)

    # 验证新会话
    print_colored("正在验证新小号会话...", YELLOW)
    client = TelegramClient(os.path.join(script_dir, session_name), api_id, api_hash)

    try:
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
                print_colored("登录成功！", GREEN)
            except Exception as e:
                # 如果需要密码（两步验证）
                if "password" in str(e).lower():
                    password = input("请输入您的两步验证密码: ")
                    await client.sign_in(password=password)
                    print_colored("登录成功！", GREEN)
                else:
                    print_colored(f"登录失败: {e}", RED)
                    await client.disconnect()
                    return False

        # 获取用户信息
        me = await client.get_me()
        first_name = me.first_name if me.first_name else ""
        username = me.username if me.username else ""
        print_colored(f"已登录为: {first_name} (@{username})", GREEN)

        # 断开连接
        await client.disconnect()

        print_colored(f"小号 {account_index} 已成功添加！", GREEN)

        # 询问是否重启脚本
        restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
        if restart == "" or restart == "y":
            # 重启脚本
            restart_script(script_dir)
            print_colored("转发脚本已重启！", GREEN)

        return True

    except Exception as e:
        print_colored(f"添加小号时出错: {e}", RED)
        await client.disconnect()
        return False

async def delete_account(script_dir, forward_py_path):
    """删除小号"""
    print_colored("=== 删除小号 ===", YELLOW)

    # 检查 forward.py 是否存在
    if not os.path.exists(forward_py_path):
        print_colored("错误：配置文件不存在！", RED)
        print_colored("请先使用选项 2 进行配置管理，创建配置文件。", YELLOW)
        input("按 Enter 键返回...")
        return False

    # 解析 forward.py
    accounts = parse_forward_py(forward_py_path)

    if not accounts:
        print_colored("错误：没有找到任何小号配置", RED)
        input("按 Enter 键返回...")
        return False

    # 显示所有小号
    print_colored("当前配置的小号：", YELLOW)
    for i, account in enumerate(accounts, 1):
        session = account['session']
        api_id = account['api_id']

        # 尝试获取更多信息
        try:
            client = TelegramClient(os.path.join(script_dir, session), api_id, account['api_hash'])
            await client.connect()
            if await client.is_user_authorized():
                me = await client.get_me()
                username = me.username if me.username else ""
                first_name = me.first_name if me.first_name else ""
                if username:
                    print(f"{i}. @{username} (API ID: {api_id}, 会话: {session})")
                else:
                    print(f"{i}. {first_name} (API ID: {api_id}, 会话: {session})")
            else:
                print(f"{i}. 未授权 (API ID: {api_id}, 会话: {session})")
            await client.disconnect()
        except:
            print(f"{i}. API ID: {api_id}, 会话: {session}")

    # 选择要删除的小号
    print_colored("请输入要删除的小号序号（输入 0 取消）：", YELLOW)
    try:
        choice = int(input().strip())
        if choice == 0:
            print_colored("已取消删除操作", YELLOW)
            return False

        if choice < 1 or choice > len(accounts):
            print_colored("无效的选择", RED)
            return False

        # 获取要删除的账号
        account_to_delete = accounts[choice - 1]
        session_name = account_to_delete['session']
        session_file = os.path.join(script_dir, session_name + ".session")

        # 删除会话文件
        if os.path.exists(session_file):
            os.remove(session_file)
            print_colored(f"已删除会话文件: {session_file}", GREEN)

        # 删除会话日志文件
        session_journal = session_file + "-journal"
        if os.path.exists(session_journal):
            os.remove(session_journal)
            print_colored(f"已删除会话日志文件: {session_journal}", GREEN)

        # 从账号列表中移除
        accounts.pop(choice - 1)

        # 读取 forward.py 文件
        with open(forward_py_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # 找到 accounts 数组的开始和结束位置
        accounts_start = content.find("accounts = [") + len("accounts = [")
        accounts_end = content.find("]", accounts_start)

        # 构建新的账号数组
        new_accounts_str = "\n"
        for account in accounts:
            new_accounts_str += f"""    {{
        'api_id': '{account['api_id']}',
        'api_hash': '{account['api_hash']}',
        'session': '{account['session']}'
    }},\n"""

        # 替换账号数组
        new_content = content[:accounts_start] + new_accounts_str + content[accounts_end:]

        # 写回文件
        with open(forward_py_path, 'w', encoding='utf-8') as f:
            f.write(new_content)

        print_colored(f"小号 {choice} 已成功删除！", GREEN)

        # 询问是否重启脚本
        restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
        if restart == "" or restart == "y":
            # 重启脚本
            restart_script(script_dir)
            print_colored("转发脚本已重启！", GREEN)

        return True

    except ValueError:
        print_colored("无效输入，请输入数字", RED)
        return False

# 使用共享库中的 is_script_running 函数

# 使用共享库中的 start_script 函数

# 使用共享库中的 restart_script 函数

async def show_accounts_menu(script_dir, forward_py_path):
    """显示小号状态菜单"""
    while True:
        print_colored("=== 小号状态菜单 ===", YELLOW)
        print("1. 查看小号状态")
        print("2. 重新授权小号")
        print("3. 添加新小号")
        print("4. 删除小号")
        print("0. 返回主菜单")
        print_colored("请选择一个选项：", YELLOW)

        try:
            choice = int(input().strip())

            if choice == 1:
                await check_accounts_status(script_dir, forward_py_path)
            elif choice == 2:
                await reauthorize_accounts_menu(script_dir, forward_py_path)
            elif choice == 3:
                await add_account(script_dir, forward_py_path)
            elif choice == 4:
                await delete_account(script_dir, forward_py_path)
            elif choice == 0:
                return
            else:
                print_colored("无效选项，请重试！", RED)
        except ValueError:
            print_colored("无效输入，请输入数字", RED)

async def check_accounts_status(script_dir, forward_py_path):
    """检查所有小号状态"""
    print_colored("=== 小号状态检查 ===", YELLOW)

    # 检查 forward.py 是否存在
    if not os.path.exists(forward_py_path):
        print_colored("错误：配置文件不存在！", RED)
        print_colored("请先使用选项 2 进行配置管理，创建配置文件。", YELLOW)
        input("按 Enter 键返回...")
        return

    # 解析 forward.py
    accounts = parse_forward_py(forward_py_path)

    if not accounts:
        print_colored("错误：无法解析账号信息", RED)
        input("按 Enter 键返回...")
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

    input("按 Enter 键返回...")

async def reauthorize_accounts_menu(script_dir, forward_py_path):
    """重新授权小号菜单"""
    print_colored("=== 重新授权小号 ===", YELLOW)
    print_colored("使用说明：输入序号并回车重新配置标红异常状态的小号", YELLOW)
    print_colored("对于有多个小号异常的，请输入数字加空格，例如：2 3 6", YELLOW)

    # 检查 forward.py 是否存在
    if not os.path.exists(forward_py_path):
        print_colored("错误：配置文件不存在！", RED)
        print_colored("请先使用选项 2 进行配置管理，创建配置文件。", YELLOW)
        input("按 Enter 键返回...")
        return

    # 解析 forward.py
    accounts = parse_forward_py(forward_py_path)

    if not accounts:
        print_colored("错误：无法解析账号信息", RED)
        input("按 Enter 键返回...")
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
    print("0. 返回上级菜单")
    choice = input(f"{YELLOW}请输入要重新授权的小号序号（多个用空格分隔）：{NC}")

    # 检查是否返回上级菜单
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

        # 询问是否重启脚本
        restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
        if restart == "" or restart == "y":
            # 重启脚本
            restart_script(script_dir)
            print_colored("转发脚本已重启！", GREEN)

# 使用共享库中的 get_script_dir 函数

async def main():
    parser = argparse.ArgumentParser(description='Telegram 小号管理工具')
    parser.add_argument('--script-dir', help='脚本目录路径', default=get_script_dir())
    parser.add_argument('--add-account', action='store_true', help='添加新小号')
    parser.add_argument('--delete-account', action='store_true', help='删除小号')
    parser.add_argument('--check-status', action='store_true', help='检查小号状态')
    parser.add_argument('--reauthorize', action='store_true', help='重新授权小号')
    args = parser.parse_args()

    script_dir = args.script_dir
    forward_py_path = os.path.join(script_dir, "forward.py")

    # 处理命令行参数
    if args.add_account:
        await add_account(script_dir, forward_py_path)
    elif args.delete_account:
        await delete_account(script_dir, forward_py_path)
    elif args.check_status:
        await check_accounts_status(script_dir, forward_py_path)
    elif args.reauthorize:
        await reauthorize_accounts_menu(script_dir, forward_py_path)
    else:
        # 显示交互式菜单
        await show_accounts_menu(script_dir, forward_py_path)

if __name__ == "__main__":
    asyncio.run(main())
