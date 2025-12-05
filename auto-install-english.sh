#!/bin/bash
# auto-install-english.sh - Auto install Telegram download bot
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/auto-install-english.sh)

set -e

echo "🚀 Auto Installing Telegram Download Bot"
echo "========================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Server info
SERVER_IP=$(curl -s ifconfig.me)
INSTALL_DIR="/opt/telegram-downloader"

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Step 1: Check and install dependencies
print_info "1. Installing system dependencies..."
apt-get update -y
apt-get upgrade -y
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano cron

# Step 2: Create project directory
print_info "2. Creating project directory..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 3: Create virtual environment
print_info "3. Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Step 4: Install Python libraries
print_info "4. Installing Python libraries..."
pip install --upgrade pip
pip install python-telegram-bot==20.7 yt-dlp==2025.11.12 requests==2.32.5

# Step 5: Create main files
print_info "5. Creating main files..."

# File bot.py with auto cleanup
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Download Bot with Auto Cleanup
Files are automatically deleted after 2 minutes
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

# Logging setup
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class AutoCleanDownloadBot:
    def __init__(self, config_path='config.json'):
        self.config = self.load_config(config_path)
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        self.cleanup_interval = self.config.get('cleanup_interval', 120)  # Default 2 minutes
        
        # Create directories
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # Start auto cleanup
        self.start_auto_cleanup()
        
        logger.info(f"Bot started with auto cleanup ({self.cleanup_interval} seconds)")
    
    def load_config(self, config_path):
        """Load configuration"""
        default_config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'cleanup_interval': 120,
            'keep_files_days': 7
        }
        
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                # Merge with defaults
                for key in default_config:
                    if key not in config:
                        config[key] = default_config[key]
                return config
        
        # Save default config
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(default_config, f, indent=4, ensure_ascii=False)
        
        return default_config
    
    def start_auto_cleanup(self):
        """Start auto cleanup in separate thread"""
        def cleanup_worker():
            while True:
                try:
                    self.cleanup_old_files()
                    time.sleep(self.cleanup_interval)
                except Exception as e:
                    logger.error(f"Cleanup error: {e}")
                    time.sleep(60)
        
        # Start cleanup thread
        cleanup_thread = threading.Thread(target=cleanup_worker, daemon=True)
        cleanup_thread.start()
        logger.info(f"Auto cleanup enabled every {self.cleanup_interval} seconds")
    
    def cleanup_old_files(self):
        """Cleanup old files"""
        try:
            now = time.time()
            files_deleted = 0
            
            for file_path in self.download_dir.glob('*'):
                if file_path.is_file():
                    # If file is older than cleanup interval
                    file_age = now - file_path.stat().st_mtime
                    if file_age > self.cleanup_interval:
                        try:
                            file_path.unlink()
                            files_deleted += 1
                            logger.debug(f"Cleaned: {file_path.name} (age: {file_age:.0f}s)")
                        except Exception as e:
                            logger.error(f"Error cleaning {file_path}: {e}")
            
            if files_deleted > 0:
                logger.info(f"Cleaned {files_deleted} old files")
                
        except Exception as e:
            logger.error(f"Cleanup error: {e}")
    
    def detect_platform(self, url):
        """Detect platform from URL"""
        url_lower = url.lower()
        
        if 'youtube.com' in url_lower or 'youtu.be' in url_lower:
            return 'youtube'
        elif 'instagram.com' in url_lower:
            return 'instagram'
        elif 'twitter.com' in url_lower or 'x.com' in url_lower:
            return 'twitter'
        elif 'tiktok.com' in url_lower:
            return 'tiktok'
        elif 'facebook.com' in url_lower or 'fb.com' in url_lower:
            return 'facebook'
        else:
            return 'generic'
    
    async def get_video_info(self, url):
        """Get video information"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                if info:
                    title = info.get('title', 'No title')[:100]
                    duration = info.get('duration', 0)
                    
                    # Estimate size
                    formats = []
                    if 'formats' in info:
                        for fmt in info['formats']:
                            if fmt.get('filesize'):
                                size_mb = fmt['filesize'] / (1024 * 1024)
                                if size_mb < self.config['telegram']['max_file_size']:
                                    formats.append({
                                        'format_id': fmt.get('format_id', ''),
                                        'resolution': fmt.get('resolution', ''),
                                        'filesize_mb': round(size_mb, 1)
                                    })
                    
                    return {
                        'title': title,
                        'duration': duration,
                        'formats': formats,
                        'platform': self.detect_platform(url)
                    }
        except Exception as e:
            logger.error(f"Error getting info: {e}")
            return None
    
    def create_quality_keyboard(self, platform, formats):
        """Create quality selection keyboard"""
        keyboard = []
        
        # Default options for YouTube
        if platform == 'youtube' and formats:
            # Group formats
            video_formats = [f for f in formats if 'video' in f.get('format_id', '') or 'mp4' in f.get('format_id', '')]
            audio_formats = [f for f in formats if 'audio' in f.get('format_id', '') or 'm4a' in f.get('format_id', '')]
            
            # Add video options
            for fmt in video_formats[:3]:
                if fmt.get('resolution'):
                    keyboard.append([
                        InlineKeyboardButton(
                            f"🎥 {fmt['resolution']} (~{fmt['filesize_mb']}MB)",
                            callback_data=f"format_{fmt['format_id']}"
                        )
                    ])
            
            # Add audio option
            if audio_formats:
                for fmt in audio_formats[:1]:
                    keyboard.append([
                        InlineKeyboardButton(
                            f"🎵 MP3 (~{fmt['filesize_mb']}MB)",
                            callback_data=f"format_{fmt['format_id']}"
                        )
                    ])
        else:
            # General options
            keyboard.append([
                InlineKeyboardButton("🎥 Best quality", callback_data="format_best")
            ])
            keyboard.append([
                InlineKeyboardButton("🎥 Medium quality", callback_data="format_worst")
            ])
        
        keyboard.append([InlineKeyboardButton("❌ Cancel", callback_data="cancel")])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def download_video(self, url, format_id):
        """Download video"""
        try:
            ydl_opts = {
                'format': format_id,
                'outtmpl': str(self.download_dir / '%(title).50s.%(ext)s'),
                'quiet': False,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # Check file size
                if os.path.exists(filename):
                    file_size = os.path.getsize(filename) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.unlink(filename)
                        return None, None, f"File too large: {file_size:.1f}MB > {max_size}MB"
                    
                    return filename, info, None
                else:
                    return None, None, "File not created"
                
        except Exception as e:
            logger.error(f"Download error: {e}")
            return None, None, str(e)
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        welcome_text = f"""
Hello {user.first_name}! 👋

🤖 **Telegram Download Bot**

📥 **Supported platforms:**
• YouTube • Instagram • Twitter/X
• TikTok • Facebook • Direct links

⚡ **Special features:**
✅ Auto cleanup after 2 minutes
✅ Quality selection
✅ Easy management

🎯 **How to use:**
1. Send video link
2. Select quality
3. Video will be downloaded and sent
4. File auto deleted after 2 minutes

⚠️ **Limits:**
• Max size: {self.config['telegram']['max_file_size']}MB
• Files auto deleted after 2 minutes

📊 **Commands:**
/start - Start
/help - Help
/status - Status
/clean - Manual cleanup
        """
        await update.message.reply_text(welcome_text, parse_mode='Markdown')
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
📖 **Full Guide:**

🔗 **Send Link:**
- Send video link from any platform
- Bot auto detects platform

🎛️ **Select Quality:**
- Bot shows available qualities
- Select your preferred quality

📥 **Receive Video:**
- Video downloaded and sent
- File stored temporarily

🧹 **Auto Cleanup:**
- Files auto deleted after 2 minutes
- Use /clean for manual cleanup

⚙️ **Commands:**
/start - Show guide
/help - This help
/status - Bot status (admin)
/clean - Manual cleanup
        """
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        # Count files
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        status_text = f"""
📊 **Bot Status:**

✅ Bot active
📁 Download dir: {self.download_dir}
📦 Current files: {len(files)}
💾 Total size: {total_size:.1f}MB
⏰ Cleanup every: {self.cleanup_interval} seconds
👤 Your ID: {user_id}
🔄 Last cleanup: {time.ctime() if files else 'Just now'}
        """
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Manual cleanup"""
        try:
            files_before = list(self.download_dir.glob('*'))
            files_count = len(files_before)
            
            for file_path in files_before:
                if file_path.is_file():
                    try:
                        file_path.unlink()
                    except:
                        pass
            
            files_after = list(self.download_dir.glob('*'))
            cleaned = files_count - len(files_after)
            
            await update.message.reply_text(
                f"🧹 Cleanup done!\n"
                f"✅ {cleaned} files deleted\n"
                f"📁 Remaining: {len(files_after)} files"
            )
            
            logger.info(f"Manual cleanup: {cleaned} files deleted")
            
        except Exception as e:
            await update.message.reply_text(f"❌ Cleanup error: {e}")
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        message = update.message
        url = message.text
        
        if not url.startswith(('http://', 'https://')):
            await message.reply_text("⚠️ Please send a valid URL.")
            return
        
        logger.info(f"Link received from {message.from_user.first_name}: {url[:50]}")
        
        # Get video info
        await message.reply_text("🔍 Checking link...")
        video_info = await self.get_video_info(url)
        
        if not video_info:
            await message.reply_text("❌ Error getting video info.")
            return
        
        # Show info
        title = video_info['title']
        platform = video_info['platform']
        duration = video_info['duration']
        
        minutes = duration // 60 if duration else 0
        seconds = duration % 60 if duration else 0
        
        info_text = f"""
📹 **{title}**

📌 Platform: {platform.upper()}
⏱ Duration: {minutes}:{seconds:02d}
🎬 Formats: {len(video_info['formats'])}
💡 File auto deleted after 2 minutes
        """
        
        await message.reply_text(info_text, parse_mode='Markdown')
        
        # Show quality options
        keyboard = self.create_quality_keyboard(platform, video_info['formats'])
        await message.reply_text(
            "✅ Please select quality:",
            reply_markup=keyboard
        )
        
        # Save info for callback
        context.user_data['last_url'] = url
        context.user_data['last_formats'] = video_info['formats']
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle callback queries"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ Cancelled.")
            return
        
        if data.startswith('format_'):
            format_id = data.replace('format_', '')
            
            await query.edit_message_text(f"⏳ Downloading with {format_id}...")
            
            url = context.user_data.get('last_url')
            if not url:
                await query.edit_message_text("❌ Link not found!")
                return
            
            # Download
            filename, info, error = await self.download_video(url, format_id)
            
            if error:
                await query.edit_message_text(f"❌ Download error:\n{error}")
                return
            
            if filename and os.path.exists(filename):
                file_size = os.path.getsize(filename) / (1024 * 1024)
                
                try:
                    # Send file
                    with open(filename, 'rb') as f:
                        if filename.endswith('.mp3') or filename.endswith('.m4a'):
                            await context.bot.send_audio(
                                chat_id=query.message.chat_id,
                                audio=f,
                                caption=f"🎵 {info.get('title', 'Audio')[:50]}\n"
                                        f"📦 Size: {file_size:.1f}MB\n"
                                        f"⏰ Auto delete: after 2 minutes"
                            )
                        else:
                            await context.bot.send_video(
                                chat_id=query.message.chat_id,
                                video=f,
                                caption=f"📹 {info.get('title', 'Video')[:50]}\n"
                                        f"📦 Size: {file_size:.1f}MB\n"
                                        f"⏰ Auto delete: after 2 minutes"
                            )
                    
                    await query.edit_message_text("✅ Download complete! File sent.")
                    logger.info(f"File sent: {filename} ({file_size:.1f}MB)")
                    
                except Exception as e:
                    await query.edit_message_text(f"❌ Send error: {str(e)[:100]}")
                    logger.error(f"Send error: {e}")
                    
                finally:
                    # Schedule file deletion after 2 minutes
                    def delete_later(file_path):
                        time.sleep(120)
                        if os.path.exists(file_path):
                            try:
                                os.unlink(file_path)
                                logger.info(f"Auto deleted: {file_path}")
                            except:
                                pass
                    
                    threading.Thread(target=delete_later, args=(filename,), daemon=True).start()
            else:
                await query.edit_message_text("❌ Downloaded file not found!")
    
    async def run(self):
        """Main bot runner"""
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            logger.error("❌ Token not set!")
            print("❌ Please set bot token in config.json")
            return
        
        logger.info(f"🚀 Starting bot with token: {self.token[:15]}...")
        print(f"🤖 Bot starting with auto cleanup")
        print(f"⏰ Files auto deleted every {self.cleanup_interval} seconds")
        
        # Create application
        application = Application.builder().token(self.token).build()
        
        # Add handlers
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CommandHandler("status", self.status_command))
        application.add_handler(CommandHandler("clean", self.clean_command))
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        application.add_handler(CallbackQueryHandler(self.handle_callback))
        
        logger.info("✅ Bot ready...")
        print("✅ Bot ready")
        print("📱 Send /start to bot in Telegram")
        print("=" * 50)
        
        # Start polling
        await application.run_polling(
            poll_interval=1.0,
            timeout=30,
            drop_pending_updates=True
        )

def main():
    """Main function"""
    print("=" * 50)
    print("🤖 Telegram Download Bot with Auto Cleanup")
    print("=" * 50)
    
    try:
        bot = AutoCleanDownloadBot()
        
        import asyncio
        asyncio.run(bot.run())
        
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped by user")
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
EOF

# File config.json
cat > config.json << 'EOF'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "download_dir": "downloads",
    "cleanup_interval": 120,
    "keep_files_days": 7
}
EOF

# File requirements.txt
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
EOF

# Management script
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Bot management script
# Usage: ./manage.sh [command]

cd "$(dirname "$0")"

case "$1" in
    start)
        echo "🚀 Starting bot..."
        source venv/bin/activate
        nohup python bot.py > bot.log 2>&1 &
        echo $! > bot.pid
        echo "✅ Bot started (PID: $(cat bot.pid))"
        echo "📝 Logs: tail -f bot.log"
        echo "🧹 Auto cleanup: every 2 minutes"
        ;;
    stop)
        echo "🛑 Stopping bot..."
        if [ -f "bot.pid" ]; then
            kill $(cat bot.pid) 2>/dev/null
            rm -f bot.pid
            echo "✅ Bot stopped"
        else
            echo "⚠️ Bot not running"
        fi
        ;;
    restart)
        echo "🔄 Restarting..."
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        echo "📊 Bot status:"
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ Bot running (PID: $(cat bot.pid))"
            echo "📁 Temp files: $(ls -1 downloads/ 2>/dev/null | wc -l)"
            echo "📝 Last logs:"
            tail -5 bot.log 2>/dev/null || echo "No log file"
        else
            echo "❌ Bot not running"
            [ -f "bot.pid" ] && rm -f bot.pid
        fi
        ;;
    logs)
        echo "📝 Bot logs:"
        echo "=================="
        if [ -f "bot.log" ]; then
            tail -50 bot.log
        else
            echo "No log file"
        fi
        ;;
    config)
        echo "⚙️ Editing config..."
        nano config.json
        echo "💡 After edit: ./manage.sh restart"
        ;;
    test)
        echo "🔍 Testing connection..."
        source venv/bin/activate
        python3 -c "
import requests, json
try:
    with open('config.json') as f:
        token = json.load(f)['telegram']['token']
    
    print(f'✅ Token: {token[:15]}...')
    
    url = f'https://api.telegram.org/bot{token}/getMe'
    r = requests.get(url, timeout=10)
    
    if r.status_code == 200:
        data = r.json()
        if data['ok']:
            print(f'✅ Connection OK!')
            print(f'🤖 Bot: {data[\"result\"][\"first_name\"]}')
            print(f'📱 @{data[\"result\"][\"username\"]}')
            
            # Test getUpdates
            url = f'https://api.telegram.org/bot{token}/getUpdates'
            r = requests.get(url, timeout=10)
            if r.status_code == 200:
                data = r.json()
                if data['ok']:
                    if data['result']:
                        print(f'📨 Messages in queue: {len(data[\"result\"])}')
                    else:
                        print('📭 No messages in queue')
        else:
            print(f'❌ Error: {data.get(\"description\", \"Unknown\")}')
    else:
        print(f'❌ HTTP Error: {r.status_code}')
except Exception as e:
    print(f'❌ Error: {e}')
        "
        ;;
    clean)
        echo "🧹 Cleaning temp files..."
        rm -rf downloads/*
        echo "✅ All temp files cleaned"
        ;;
    update)
        echo "🔄 Updating..."
        $0 stop
        source venv/bin/activate
        pip install --upgrade python-telegram-bot yt-dlp requests
        echo "✅ Update complete"
        $0 start
        ;;
    autostart)
        echo "⚙️ Setting auto-start..."
        CRON_JOB="@reboot cd $INSTALL_DIR && ./manage.sh start"
        (crontab -l 2>/dev/null | grep -v "manage.sh" ; echo "$CRON_JOB") | crontab -
        echo "✅ Auto-start configured"
        ;;
    debug)
        echo "🐛 Debug mode..."
        $0 stop
        source venv/bin/activate
        echo "🧹 Cleaning old logs..."
        > bot.log
        echo "🚀 Starting in foreground..."
        python bot.py
        ;;
    uninstall)
        echo "🗑️ Uninstalling..."
        $0 stop
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
            crontab -l 2>/dev/null | grep -v "manage.sh" | crontab -
            echo "✅ Bot uninstalled"
        else
            echo "❌ Uninstall cancelled"
        fi
        ;;
    *)
        echo "🤖 Telegram Download Bot Management"
        echo "=================================="
        echo ""
        echo "📁 Directory: $INSTALL_DIR"
        echo ""
        echo "📋 Commands:"
        echo "  ./manage.sh start      # Start bot"
        echo "  ./manage.sh stop       # Stop bot"
        echo "  ./manage.sh restart    # Restart bot"
        echo "  ./manage.sh status     # Bot status"
        echo "  ./manage.sh logs       # Show logs"
        echo "  ./manage.sh config     # Edit config"
        echo "  ./manage.sh test       # Test connection"
        echo "  ./manage.sh clean      # Clean temp files"
        echo "  ./manage.sh update     # Update bot"
        echo "  ./manage.sh autostart  # Configure auto-start"
        echo "  ./manage.sh debug      # Debug mode"
        echo "  ./manage.sh uninstall  # Uninstall bot"
        echo ""
        echo "🎯 Feature: Files auto deleted after 2 minutes"
        ;;
esac
EOF

chmod +x manage.sh

# Step 6: Initial setup
print_info "6. Initial setup..."
echo ""
echo "🔧 Please configure your bot token:"
echo "   nano $INSTALL_DIR/config.json"
echo ""
echo "Get token from @BotFather and replace YOUR_BOT_TOKEN_HERE"

# Step 7: First start
print_info "7. First start..."
./manage.sh start

sleep 3

# Step 8: Check installation
print_info "8. Checking installation..."
./manage.sh status

echo ""
echo "========================================"
print_status "✅ Installation complete!"
echo ""
echo "📋 Installation info:"
echo "   📁 Directory: $INSTALL_DIR"
echo "   🤖 Bot: Telegram Download Bot"
echo "   🧹 Cleanup: Every 2 minutes"
echo "   ⚡ Management: ./manage.sh"
echo ""
echo "🎯 Quick commands:"
echo "   cd $INSTALL_DIR"
echo "   ./manage.sh status    # Status"
echo "   ./manage.sh logs      # Logs"
echo "   ./manage.sh config    # Edit config"
echo ""
echo "🚀 For auto-start after reboot:"
echo "   ./manage.sh autostart"
echo ""
echo "📱 In Telegram:"
echo "   1. Find your bot"
echo "   2. Send /start"
echo "   3. Send video link"
echo ""
echo "🔗 Server: $SERVER_IP"
echo "========================================"
