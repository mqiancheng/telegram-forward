#!/usr/bin/env python3
from telethon import TelegramClient
import asyncio
import sys
import os
import json

# 检查小号状态的脚本
# 用法: python3 check_account_status.py [session_file]

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
        print(f"解析 forward.py 失败: {e}")
        return []

async def main():
    # 检查参数
    if len(sys.argv) < 2:
        print("用法: python3 check_account_status.py <forward.py路径>")
        return
    
    forward_py_path = sys.argv[1]
    
    # 检查文件是否存在
    if not os.path.exists(forward_py_path):
        print(f"错误: 文件 {forward_py_path} 不存在")
        return
    
    # 解析 forward.py
    accounts = parse_forward_py(forward_py_path)
    
    if not accounts:
        print("错误: 无法解析账号信息")
        return
    
    # 检查所有账号状态
    results = await check_all_accounts(accounts)
    
    # 输出结果为 JSON
    print(json.dumps(results, ensure_ascii=False))

if __name__ == "__main__":
    asyncio.run(main())
