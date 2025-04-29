#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import argparse
import asyncio
import shutil
import tarfile
import tempfile
import glob
import subprocess
from datetime import datetime
from telethon import TelegramClient

# 导入共享库
from utils import (
    RED, GREEN, YELLOW, NC,
    print_colored, get_script_dir, is_script_running,
    stop_script, start_script, restart_script, parse_forward_py, edit_config_file
)

# 使用共享库中的函数

async def verify_session(api_id, api_hash, session_name):
    """验证会话是否有效"""
    try:
        client = TelegramClient(session_name, api_id, api_hash)
        await client.start()
        me = await client.get_me()
        await client.disconnect()
        return {
            'status': 'ok',
            'username': me.username,
            'first_name': me.first_name,
            'id': me.id
        }
    except Exception as e:
        if "AUTH_KEY_UNREGISTERED" in str(e):
            return {'status': 'unauthorized', 'error': str(e)}
        else:
            return {'status': 'error', 'error': str(e)}

async def check_all_accounts(accounts):
    """检查所有账号的状态"""
    results = []
    for i, account in enumerate(accounts, 1):
        print_colored(f"正在检查小号 {i} 的状态...", YELLOW)
        session_name = account['session']
        api_id = account['api_id']
        api_hash = account['api_hash']

        # 确保会话文件路径正确
        if not os.path.isabs(session_name):
            session_name = os.path.join(get_script_dir(), session_name)

        result = await verify_session(api_id, api_hash, session_name)
        result['account_index'] = i
        result['api_id'] = api_id
        result['api_hash'] = api_hash
        result['session'] = account['session']
        results.append(result)

    return results

def backup_config(script_dir, backup_dir):
    """备份配置文件"""
    print_colored("正在备份配置...", YELLOW)

    forward_py = os.path.join(script_dir, "forward.py")

    # 检查 forward.py 是否存在
    if not os.path.exists(forward_py):
        print_colored("forward.py 文件不存在，无法备份", RED)
        return False

    # 创建备份目录
    os.makedirs(backup_dir, exist_ok=True)
    os.chmod(backup_dir, 0o755)  # 设置权限为 755

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = os.path.join(backup_dir, f"forward_backup_{timestamp}.tar.gz")

    # 检查会话文件
    session_files = glob.glob(os.path.join(script_dir, "session_account*.session"))
    if not session_files:
        print_colored("未找到会话文件，仅备份 forward.py", YELLOW)
    else:
        print_colored(f"找到 {len(session_files)} 个会话文件，将一并备份", GREEN)

    # 创建临时目录
    with tempfile.TemporaryDirectory() as temp_dir:
        # 复制文件到临时目录
        shutil.copy2(forward_py, temp_dir)

        for session_file in session_files:
            shutil.copy2(session_file, temp_dir)

        # 创建压缩文件
        with tarfile.open(backup_file, "w:gz") as tar:
            for file in os.listdir(temp_dir):
                tar.add(os.path.join(temp_dir, file), arcname=file)

    # 设置权限
    os.chmod(backup_file, 0o644)

    print_colored(f"配置已备份到: {backup_file}", GREEN)
    print_colored("备份内容: forward.py（API凭证和转发规则）, 会话文件（授权信息）", YELLOW)
    return True

def restore_config(script_dir, backup_dir):
    """恢复配置文件"""
    print_colored("可用的备份文件:", YELLOW)

    # 检查备份目录
    if not os.path.exists(backup_dir):
        print_colored("备份目录不存在", RED)
        return False

    # 列出备份文件
    backup_files = glob.glob(os.path.join(backup_dir, "forward_backup_*.tar.gz"))
    if not backup_files:
        print_colored("没有找到备份文件", RED)
        return False

    # 显示备份文件列表
    for i, file in enumerate(backup_files, 1):
        print(f"{i}. {os.path.basename(file)}")

    # 选择备份文件
    print_colored("请选择要恢复的备份文件编号（输入 0 取消）:", YELLOW)
    try:
        backup_choice = int(input())
        if backup_choice == 0:
            print_colored("已取消恢复操作", YELLOW)
            return False

        if backup_choice < 1 or backup_choice > len(backup_files):
            print_colored("无效的选择", RED)
            return False

        selected_file = backup_files[backup_choice - 1]

        # 创建临时目录
        with tempfile.TemporaryDirectory() as temp_dir:
            # 解压备份文件
            print_colored("正在解压备份文件...", YELLOW)
            with tarfile.open(selected_file, "r:gz") as tar:
                tar.extractall(temp_dir)

            print_colored("正在恢复配置文件到项目目录...", YELLOW)

            # 跟踪是否有文件被恢复
            files_restored = 0

            # 复制 forward.py 到项目目录
            forward_py_temp = os.path.join(temp_dir, "forward.py")
            if os.path.exists(forward_py_temp):
                shutil.copy2(forward_py_temp, os.path.join(script_dir, "forward.py"))
                print_colored("已恢复 forward.py（API凭证和转发规则）", GREEN)
                files_restored += 1

            # 复制会话文件到项目目录
            session_count = 0
            for session_file in glob.glob(os.path.join(temp_dir, "session_account*.session")):
                shutil.copy2(session_file, script_dir)
                session_count += 1

            if session_count > 0:
                print_colored(f"已恢复 {session_count} 个会话文件（授权信息）", GREEN)
                files_restored += 1

            # 检查是否有文件被恢复
            if files_restored == 0:
                print_colored("警告：备份文件中没有找到可恢复的文件", YELLOW)
                return False

            print_colored("配置已成功恢复到项目目录！", GREEN)
            return True

    except ValueError:
        print_colored("无效的输入", RED)
        return False

def manage_backups(backup_dir):
    """管理备份文件"""
    print_colored("=== 备份文件管理 ===", YELLOW)

    # 检查备份目录
    if not os.path.exists(backup_dir):
        print_colored("备份目录不存在", RED)
        return False

    # 列出备份文件
    backup_files = glob.glob(os.path.join(backup_dir, "forward_backup_*.tar.gz"))
    if not backup_files:
        print_colored("没有找到备份文件", RED)
        return False

    # 显示备份文件列表
    print_colored("可用的备份文件:", YELLOW)
    for i, file in enumerate(backup_files, 1):
        print(f"{i}. {os.path.basename(file)}")

    # 选择要删除的备份文件
    print_colored("请选择要删除的备份文件编号（多个用空格分隔，输入 0 删除所有，输入 c 取消）:", YELLOW)
    choice = input().strip()

    # 检查是否取消
    if choice.lower() == 'c':
        print_colored("已取消删除操作", GREEN)
        return False

    # 检查是否删除所有
    if choice == '0':
        print_colored("确认删除所有备份文件？（y/n，回车默认为 n）：", YELLOW)
        confirm = input().strip().lower()
        if not confirm or confirm != 'y':
            print_colored("已取消删除操作", GREEN)
            return False

        # 删除所有备份文件
        for file in backup_files:
            os.remove(file)
        print_colored("已删除所有备份文件", GREEN)
        return True

    # 删除选定的备份文件
    try:
        choices = [int(x) for x in choice.split()]
        for choice_num in choices:
            if choice_num < 1 or choice_num > len(backup_files):
                print_colored(f"无效的选择: {choice_num}", RED)
                continue

            file_to_delete = backup_files[choice_num - 1]
            os.remove(file_to_delete)
            print_colored(f"已删除: {os.path.basename(file_to_delete)}", GREEN)

        return True
    except ValueError:
        print_colored("无效的输入", RED)
        return False

async def create_new_config(script_dir):
    """创建新的配置文件"""
    print_colored("=== 配置 Telegram 转发脚本 ===", YELLOW)
    print_colored("第一步：配置大号群组", YELLOW)
    print_colored("请输入大号群组/个人的 Chat ID（例如 -4688142035）：", YELLOW)
    target_chat_id = input().strip()

    # 初始化 accounts 数组
    accounts = []
    account_index = 1

    print_colored("=== 第二步：配置小号 ===", YELLOW)

    # 循环添加小号
    while True:
        print_colored(f"正在配置小号 {account_index}", YELLOW)
        print_colored(f"请输入小号{account_index}的 api_id（从 my.telegram.org 获取）：", YELLOW)
        api_id = input().strip()
        print_colored(f"请输入小号{account_index}的 api_hash（从 my.telegram.org 获取）：", YELLOW)
        api_hash = input().strip()

        # 创建会话文件名
        session_name = f"session_account{account_index}"

        # 添加小号到 accounts 数组
        accounts.append({
            'api_id': api_id,
            'api_hash': api_hash,
            'session': session_name
        })

        # 询问是否继续添加小号
        print_colored("是否继续添加小号？（y/n，回车默认为 n）：", YELLOW)
        continue_adding = input().strip().lower()
        if not continue_adding or continue_adding != 'y':
            break

        account_index += 1

    print_colored("=== 第三步：配置转发规则 ===", YELLOW)

    # 询问是否只转发特定用户/机器人的消息
    print_colored("是否只转发特定用户/机器人的消息？（y/n，回车默认为 y）：", YELLOW)
    filter_senders = input().strip().lower()
    if not filter_senders:
        filter_senders = 'y'

    allowed_senders = []
    if filter_senders == 'y':
        print_colored("请输入用户名（例如 @HaxBot），多个用户用空格分隔：", YELLOW)
        senders = input().strip().split()
        allowed_senders = senders

    # 询问是否启用MCP服务
    print_colored("=== 第四步：配置MCP服务 ===", YELLOW)
    print_colored("是否启用MCP服务（消息控制协议）？（y/n，回车默认为 y）：", YELLOW)
    print_colored("MCP服务允许通过命令控制转发行为，如暂停/恢复转发、设置过滤规则等", YELLOW)
    enable_mcp = input().strip().lower()
    if not enable_mcp:
        enable_mcp = 'y'

    mcp_admin_users = []
    if enable_mcp == 'y':
        print_colored("请输入MCP管理员用户ID（数字ID），多个用户用空格分隔：", YELLOW)
        print_colored("（只有这些用户可以发送控制命令，留空则不设置管理员）", YELLOW)
        admin_input = input().strip()
        if admin_input:
            try:
                mcp_admin_users = [int(user_id) for user_id in admin_input.split()]
            except ValueError:
                print_colored("警告：输入的用户ID不是有效的数字，已忽略", RED)
                mcp_admin_users = []

    # 创建 forward.py
    forward_py_content = f"""from telethon import TelegramClient, events
import asyncio
import re
import logging
import os
import sys

# 添加当前目录到路径，以便导入mcp_service
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.append(current_dir)

# 导入MCP服务
try:
    from mcp_service import MCPService
except ImportError:
    print("警告: 无法导入MCP服务模块，MCP功能将被禁用")
    MCPService = None

# 配置日志
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger('telegram_forward')

# 大号的 Chat ID（消息的目标）
target_chat_id = {target_chat_id}

# 每个账号的配置（api_id, api_hash, session 文件名）
accounts = [
"""

    for account in accounts:
        forward_py_content += f"""    {{
        'api_id': '{account['api_id']}',
        'api_hash': '{account['api_hash']}',
        'session': '{account['session']}'
    }},
"""

    forward_py_content = forward_py_content.rstrip(",\n") + "\n]\n\n"

    # 添加允许的发送者
    forward_py_content += "# 可选：只转发特定用户/机器人的消息（留空则转发所有私聊消息）\n"
    if allowed_senders:
        allowed_senders_str = ", ".join([f"'{sender}'" for sender in allowed_senders])
        forward_py_content += f"allowed_senders = [{allowed_senders_str}]\n\n"
    else:
        forward_py_content += "allowed_senders = []\n\n"

    # 添加客户端创建和消息处理代码
    forward_py_content += """# 创建所有账号的客户端
clients = [TelegramClient(acc['session'], acc['api_id'], acc['api_hash']) for acc in accounts]

# 为每个客户端设置消息监听
for client in clients:
    if allowed_senders:  # 如果指定了消息来源
        @client.on(events.NewMessage(from_users=allowed_senders, chats=None))
        async def handler(event):
            # 实时转发消息到大号
            await client.forward_messages(target_chat_id, event.message)
            print(f"消息已转发 (来自 {event.sender_id})")
    else:  # 转发所有私聊消息
        @client.on(events.NewMessage(chats=None))
        async def handler(event):
            # 确保只转发私聊消息（排除群组/频道）
            if event.is_private:
                await client.forward_messages(target_chat_id, event.message)
                print(f"消息已转发 (来自 {event.sender_id})")

# 启动所有客户端
async def main():
    while True:
        try:
            for client in clients:
                await client.start()
            # 保持运行
            await asyncio.gather(*(client.run_until_disconnected() for client in clients))
        except Exception as e:
            print(f"脚本异常退出: {e}")
            print("将在 60 秒后重试...")
            await asyncio.sleep(60)

# 运行主程序
asyncio.run(main())
"""

    # 写入 forward.py 文件
    forward_py_path = os.path.join(script_dir, "forward.py")
    with open(forward_py_path, 'w') as f:
        f.write(forward_py_content)

    print_colored("forward.py 已生成！", GREEN)

    # 验证会话
    print_colored("=== 第四步：验证小号会话 ===", YELLOW)
    print_colored("现在需要验证每个小号的会话，请按照提示操作", YELLOW)

    # 验证所有会话
    for i, account in enumerate(accounts, 1):
        session_name = account['session']
        api_id = account['api_id']
        api_hash = account['api_hash']

        print_colored(f"正在验证小号 {i} 的会话...", YELLOW)

        # 确保会话文件路径正确
        if not os.path.isabs(session_name):
            session_name = os.path.join(script_dir, session_name)

        try:
            client = TelegramClient(session_name, api_id, api_hash)
            await client.start()
            me = await client.get_me()
            print_colored(f"成功登录为: {me.first_name} (@{me.username})", GREEN)
            await client.disconnect()
        except Exception as e:
            print_colored(f"验证小号 {i} 时出错: {e}", RED)
            return False

    print_colored("所有小号会话验证完成！", GREEN)
    print_colored("配置完成！", GREEN)
    return True

async def show_config_menu(script_dir, backup_dir):
    """显示配置管理菜单"""
    while True:
        print_colored("=== 配置管理菜单 ===", YELLOW)
        print("1. 新建配置")
        print("2. 修改配置")
        print("3. 备份配置")
        print("4. 恢复配置")
        print("5. 管理备份")
        print("0. 返回主菜单")
        print_colored("请选择一个选项：", YELLOW)

        try:
            choice = int(input().strip())

            if choice == 1:
                success = await create_new_config(script_dir)
                if success:
                    # 询问是否重启脚本
                    restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
                    if restart == "" or restart == "y":
                        restart_script(script_dir)
            elif choice == 2:
                # 打开编辑器修改配置
                forward_py_path = os.path.join(script_dir, "forward.py")
                if os.path.exists(forward_py_path):
                    edit_config_file(forward_py_path)

                    # 询问是否重启脚本
                    restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
                    if restart == "" or restart == "y":
                        restart_script(script_dir)
                else:
                    print_colored("forward.py 文件不存在，请先创建配置", RED)
            elif choice == 3:
                success = backup_config(script_dir, backup_dir)
                if success:
                    print_colored("备份已完成！", GREEN)
            elif choice == 4:
                success = restore_config(script_dir, backup_dir)
                if success:
                    # 询问是否重启脚本
                    restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
                    if restart == "" or restart == "y":
                        restart_script(script_dir)
            elif choice == 5:
                manage_backups(backup_dir)
            elif choice == 0:
                return
            else:
                print_colored("无效选项，请重试！", RED)
        except ValueError:
            print_colored("无效输入，请输入数字", RED)

async def main():
    parser = argparse.ArgumentParser(description='Telegram 配置管理工具')
    parser.add_argument('--script-dir', help='脚本目录路径', default=get_script_dir())
    parser.add_argument('--backup-dir', help='备份目录路径', default='/home/backup-TGfw')
    parser.add_argument('--backup', action='store_true', help='备份配置')
    parser.add_argument('--restore', action='store_true', help='恢复配置')
    parser.add_argument('--manage-backups', action='store_true', help='管理备份文件')
    parser.add_argument('--create-config', action='store_true', help='创建新配置')
    parser.add_argument('--edit-config', action='store_true', help='编辑配置')
    args = parser.parse_args()

    script_dir = args.script_dir
    backup_dir = args.backup_dir

    # 处理直接命令
    if args.backup:
        success = backup_config(script_dir, backup_dir)
        return 0 if success else 1
    elif args.restore:
        success = restore_config(script_dir, backup_dir)
        if success:
            # 询问是否重启脚本
            restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
            if restart == "" or restart == "y":
                restart_script(script_dir)
        return 0 if success else 1
    elif args.manage_backups:
        success = manage_backups(backup_dir)
        return 0 if success else 1
    elif args.create_config:
        success = await create_new_config(script_dir)
        if success:
            # 询问是否重启脚本
            restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
            if restart == "" or restart == "y":
                restart_script(script_dir)
        return 0 if success else 1
    elif args.edit_config:
        forward_py_path = os.path.join(script_dir, "forward.py")
        if os.path.exists(forward_py_path):
            edit_config_file(forward_py_path)

            # 询问是否重启脚本
            restart = input(f"{YELLOW}是否立即重启转发脚本以应用更改？(y/n，默认y): {NC}").strip().lower()
            if restart == "" or restart == "y":
                restart_script(script_dir)
            return 0
        else:
            print_colored("forward.py 文件不存在，请先创建配置", RED)
            return 1

    # 如果没有指定直接命令，显示配置菜单
    await show_config_menu(script_dir, backup_dir)
    return 0

if __name__ == "__main__":
    import sys
    sys.exit(asyncio.run(main()))
