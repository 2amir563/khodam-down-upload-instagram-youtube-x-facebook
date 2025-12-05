cd /opt/telegram-downloader

# ابتدا ربات را متوقف کنید
./manage.sh stop

# کد جدید
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Download Bot - Fixed version without event loop issues
"""

import os
import json
import logging
import asyncio
import threading
import time
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    filters,
    ContextTypes
)
import yt_dlp

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DownloadBot:
    def __init__(self, config_path='config.json'):
        self.config = self.load_config(config_path)
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        # Create directories
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        logger.info(f"Bot initialized with token: {self.token[:15]}...")
    
    def load_config(self, config_path):
        """Load configuration"""
        default_config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'keep_files_days': 7
        }
        
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        
        # Save default config
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(default_config, f, indent=4, ensure_ascii=False)
        
        return default_config
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        await update.message.reply_text(
            f'Hello {user.first_name}! 👋\n\n'
            '🤖 **Download Bot**\n\n'
            '📥 **Supported:**\n'
            '• YouTube • Instagram • Twitter/X\n'
            '• TikTok • Facebook • Direct links\n\n'
            '🎯 **How to use:**\n'
            '1. Send video link\n'
            '2. Select quality\n'
            '3. Receive video\n\n'
            '📊 **Commands:**\n'
            '/start - Start\n'
            '/help - Help\n'
            '/status - Status (admin)\n'
            '/clean - Clean temp files',
            parse_mode='Markdown'
        )
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        await update.message.reply_text(
            '📖 **Help Guide**\n\n'
            '🔗 **Send Link:**\n'
            '- Send video link from any platform\n\n'
            '🎛️ **Select Quality:**\n'
            '- Bot shows available qualities\n\n'
            '📥 **Receive Video:**\n'
            '- Video downloaded and sent\n\n'
            '⚙️ **Commands:**\n'
            '/start - Show guide\n'
            '/help - This help\n'
            '/status - Bot status\n'
            '/clean - Clean temp files',
            parse_mode='Markdown'
        )
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        await update.message.reply_text(
            f'📊 **Bot Status**\n\n'
            f'✅ Bot active\n'
            f'📁 Files: {len(files)}\n'
            f'💾 Size: {total_size:.1f}MB\n'
            f'👤 Your ID: {user_id}',
            parse_mode='Markdown'
        )
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Clean temp files"""
        files = list(self.download_dir.glob('*'))
        files_count = len(files)
        
        for file_path in files:
            if file_path.is_file():
                try:
                    file_path.unlink()
                except:
                    pass
        
        await update.message.reply_text(f'🧹 Cleaned {files_count} files')
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        text = update.message.text
        
        if text.startswith(('http://', 'https://')):
            # Simple download without quality selection
            await update.message.reply_text('📥 Downloading...')
            
            try:
                ydl_opts = {
                    'format': 'best[height<=720]',
                    'outtmpl': str(self.download_dir / '%(title).50s.%(ext)s'),
                    'quiet': True,
                }
                
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(text, download=True)
                    filename = ydl.prepare_filename(info)
                    
                    if os.path.exists(filename):
                        file_size = os.path.getsize(filename) / (1024 * 1024)
                        
                        # Send file
                        with open(filename, 'rb') as f:
                            if filename.endswith(('.mp3', '.m4a')):
                                await update.message.reply_audio(
                                    audio=f,
                                    caption=f'🎵 {info.get("title", "Audio")[:50]}\n📦 {file_size:.1f}MB'
                                )
                            else:
                                await update.message.reply_video(
                                    video=f,
                                    caption=f'📹 {info.get("title", "Video")[:50]}\n📦 {file_size:.1f}MB'
                                )
                        
                        # Delete temp file
                        os.unlink(filename)
                        
            except Exception as e:
                logger.error(f"Download error: {e}")
                await update.message.reply_text(f'❌ Error: {str(e)[:100]}')
        else:
            await update.message.reply_text('Please send a valid URL (http:// or https://)')
    
    def run_bot(self):
        """Run the bot - FIXED VERSION"""
        print("=" * 50)
        print("🤖 Telegram Download Bot")
        print("=" * 50)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Bot token not configured!")
            print("Please edit config.json and add your token")
            return
        
        print(f"✅ Token: {self.token[:15]}...")
        
        # Create and run application - SIMPLE VERSION
        application = Application.builder().token(self.token).build()
        
        # Add handlers
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CommandHandler("status", self.status_command))
        application.add_handler(CommandHandler("clean", self.clean_command))
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        
        print("✅ Bot ready")
        print("📱 Send /start to your bot in Telegram")
        print("=" * 50)
        
        # Run polling - this is the correct way
        application.run_polling()

def main():
    """Main function"""
    try:
        bot = DownloadBot()
        bot.run_bot()
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped by user")
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
EOF

# حالا ربات را شروع کنید
./manage.sh restart

# لاگ‌ها را بررسی کنید
tail -f bot.log
