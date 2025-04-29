from telethon import TelegramClient, events
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
{accounts_str}
]

# 可选：只转发特定用户/机器人的消息（留空则转发所有私聊消息）
allowed_senders = {allowed_senders_str}

# 消息过滤设置
filter_mode = 'none'  # 可选值: 'none', 'whitelist', 'blacklist'
whitelist_keywords = []  # 白名单关键词，当 filter_mode 为 'whitelist' 时生效
blacklist_keywords = []  # 黑名单关键词，当 filter_mode 为 'blacklist' 时生效

# MCP服务配置
enable_mcp = True  # 是否启用MCP服务
mcp_admin_users = []  # MCP管理员用户ID列表，只有这些用户可以发送控制命令

# 创建所有账号的客户端
clients = [TelegramClient(acc['session'], acc['api_id'], acc['api_hash']) for acc in accounts]

# 为每个客户端设置消息监听
for client in clients:
    if allowed_senders:  # 如果指定了消息来源
        @client.on(events.NewMessage(from_users=allowed_senders, chats=None))
        async def handler(event):
            # 检查消息是否符合过滤规则
            if should_forward_message(event.message):
                # 转发消息到大号
                await client.forward_messages(target_chat_id, event.message)
                logger.info(f"消息已转发 (来自 {event.sender_id})")
            else:
                logger.info(f"消息被过滤 (来自 {event.sender_id})")
    else:  # 转发所有私聊消息
        @client.on(events.NewMessage(chats=None))
        async def handler(event):
            # 确保只转发私聊消息（排除群组/频道）
            if event.is_private:
                # 检查消息是否符合过滤规则
                if should_forward_message(event.message):
                    # 转发消息到大号
                    await client.forward_messages(target_chat_id, event.message)
                    logger.info(f"消息已转发 (来自 {event.sender_id})")
                else:
                    logger.info(f"消息被过滤 (来自 {event.sender_id})")

# 初始化MCP服务
mcp_service = None
if enable_mcp and MCPService is not None:
    mcp_service = MCPService(clients, target_chat_id, mcp_admin_users)
    # 将过滤设置加载到MCP服务
    mcp_service.load_settings(filter_mode, whitelist_keywords, blacklist_keywords, allowed_senders)

# 检查消息是否应该被转发（使用MCP服务如果可用）
def should_forward_message(message):
    # 如果MCP服务可用，使用MCP服务的过滤逻辑
    if mcp_service is not None:
        return mcp_service.should_forward_message(message)

    # 否则使用默认的过滤逻辑
    # 如果没有设置过滤模式，直接转发
    if filter_mode == 'none':
        return True

    # 获取消息文本
    if not message.text:
        # 如果消息没有文本（例如图片、文件等），根据配置决定是否转发
        return True

    text = message.text.lower()

    # 白名单模式：只转发包含白名单关键词的消息
    if filter_mode == 'whitelist':
        if not whitelist_keywords:  # 如果白名单为空，不转发任何消息
            return False

        for keyword in whitelist_keywords:
            if keyword.lower() in text:
                return True

        return False

    # 黑名单模式：不转发包含黑名单关键词的消息
    elif filter_mode == 'blacklist':
        if not blacklist_keywords:  # 如果黑名单为空，转发所有消息
            return True

        for keyword in blacklist_keywords:
            if keyword.lower() in text:
                return False

        return True

    # 默认转发
    return True

# 启动所有客户端
async def main():
    while True:
        try:
            # 启动所有客户端
            for client in clients:
                await client.start()

            # 如果MCP服务可用，注册命令处理器
            if mcp_service is not None:
                mcp_service.register_handlers()
                logger.info("MCP服务已启动")

            # 保持运行
            await asyncio.gather(*(client.run_until_disconnected() for client in clients))
        except Exception as e:
            logger.error(f"脚本异常退出: {e}")
            logger.info("将在 60 秒后重试...")
            await asyncio.sleep(60)

# 运行主程序
asyncio.run(main())
