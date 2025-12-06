#!/bin/bash
# quality_install.sh - Install Telegram bot with quality selection
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)

set -e

echo "🎯 Installing Telegram Bot with Quality Selection"
echo "================================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_green() { echo -e "${GREEN}[✓]${NC} $1"; }
print_red() { echo -e "${RED}[✗]${NC} $1"; }
print_blue() { echo -e "${BLUE}[i]${NC} $1"; }

# Install directory
INSTALL_DIR="/opt/quality-tg-bot"

# Step 1: Cleanup
print_blue "1. Cleaning old installations..."
pkill -f "python.*bot.py" 2>/dev/null || true
rm -rf "$INSTALL_DIR" 2>/dev/null || true
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 2: Install dependencies
print_blue "2. Installing system dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano cron

# Step 3: Create virtual environment
print_blue "3. Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Step 4: Install Python packages
print_blue "4. Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.7 yt-dlp==2025.11.12 requests==2.32.5

# Step 5: Create bot.py with quality selection
print_blue "5. Creating bot.py with quality selection..."
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Download Bot with Quality Selection
"""

import os
import json
import logging
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes
import yt_dlp
import requests

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

class QualityDownloadBot:
    def __init__(self):
        self.config = self.load_config()
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        self.is_paused = False
        self.paused_until = None
        
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        self.start_auto_cleanup()
        
        logger.info("Bot initialized")
    
    def load_config(self):
        config_file = 'config.json'
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                return json.load(f)
        
        config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'auto_cleanup_minutes': 2
        }
        
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
        
        return config
    
    def start_auto_cleanup(self):
        def cleanup_worker():
            while True:
                try:
                    self.cleanup_old_files()
                    time.sleep(60)
                except Exception as e:
                    logger.error(f"Cleanup error: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=cleanup_worker, daemon=True)
        thread.start()
    
    def cleanup_old_files(self):
        cleanup_minutes = self.config.get('auto_cleanup_minutes', 2)
        cutoff_time = time.time() - (cleanup_minutes * 60)
        
        for file_path in self.download_dir.glob('*'):
            if file_path.is_file():
                file_age = time.time() - file_path.stat().st_mtime
                if file_age > (cleanup_minutes * 60):
                    try:
                        file_path.unlink()
                    except:
                        pass
    
    def detect_platform(self, url):
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
    
    async def get_video_formats(self, url):
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                formats = []
                if 'formats' in info:
                    for fmt in info['formats']:
                        if not fmt.get('filesize'):
                            continue
                        
                        if fmt.get('vcodec') == 'none' and fmt.get('acodec') != 'none':
                            continue
                        
                        resolution = fmt.get('resolution', 'N/A')
                        if resolution == 'audio only':
                            continue
                        
                        format_note = fmt.get('format_note', '')
                        if not format_note and resolution != 'N/A':
                            format_note = resolution
                        
                        size_mb = fmt['filesize'] / (1024 * 1024)
                        max_size = self.config['telegram']['max_file_size']
                        
                        if size_mb > max_size:
                            continue
                        
                        formats.append({
                            'format_id': fmt['format_id'],
                            'resolution': resolution,
                            'format_note': format_note,
                            'ext': fmt.get('ext', 'mp4'),
                            'filesize_mb': round(size_mb, 1),
                            'quality': f"{format_note} ({resolution}) - {size_mb:.1f}MB"
                        })
                
                formats.sort(key=lambda x: (
                    -int(x['resolution'].split('x')[0]) if 'x' in x['resolution'] else 0,
                    -x['filesize_mb']
                ))
                
                return formats[:5]
                
        except Exception as e:
            logger.error(f"Error getting formats: {e}")
            return []
    
    def create_quality_keyboard(self, formats, platform):
        keyboard = []
        
        if platform in ['youtube', 'twitter'] and formats:
            for fmt in formats:
                quality_label = fmt['quality']
                if len(quality_label) > 50:
                    quality_label = quality_label[:47] + "..."
                
                keyboard.append([
                    InlineKeyboardButton(
                        f"🎬 {quality_label}",
                        callback_data=f"download_{fmt['format_id']}"
                    )
                ])
            
            if platform == 'youtube':
                keyboard.append([
                    InlineKeyboardButton(
                        "🎵 MP3 Audio Only",
                        callback_data="download_bestaudio"
                    )
                ])
        else:
            keyboard.append([
                InlineKeyboardButton("📹 Best Quality", callback_data="download_best")
            ])
            keyboard.append([
                InlineKeyboardButton("📹 720p", callback_data="download_best[height<=720]")
            ])
            keyboard.append([
                InlineKeyboardButton("📹 480p", callback_data="download_best[height<=480]")
            ])
        
        keyboard.append([
            InlineKeyboardButton("❌ Cancel", callback_data="cancel")
        ])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        welcome = f"""
Hello {user.first_name}! 👋

🤖 **Telegram Download Bot**

📥 **Supported Platforms:**
✅ YouTube (choose quality with file size)
✅ Twitter/X (choose quality with file size)
✅ Instagram
✅ TikTok  
✅ Facebook
✅ Direct files

🎯 **How to use:**
1. Send YouTube/Twitter link → Choose quality
2. Send other links → Auto download

🛠️ **Commands:**
/start - This menu
/help - Detailed help
/status - Bot status (admin)
/pause [hours] - Pause bot (admin)
/resume - Resume bot (admin)
/clean - Clean files (admin)

💡 **Files auto deleted after 2 minutes**
"""
        
        await update.message.reply_text(welcome, parse_mode='Markdown')
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        text = update.message.text
        user = update.effective_user
        
        logger.info(f"Message from {user.first_name}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            platform = self.detect_platform(text)
            
            if platform in ['youtube', 'twitter']:
                await update.message.reply_text("🔍 Getting available qualities...")
                formats = await self.get_video_formats(text)
                
                if formats:
                    info_text = f"📹 **{platform.capitalize()} Video**\n\n"
                    info_text += "🎬 **Available Qualities:**\n"
                    
                    for i, fmt in enumerate(formats[:3], 1):
                        info_text += f"{i}. {fmt['quality']}\n"
                    
                    if len(formats) > 3:
                        info_text += f"... and {len(formats) - 3} more\n"
                    
                    await update.message.reply_text(info_text, parse_mode='Markdown')
                    
                    keyboard = self.create_quality_keyboard(formats, platform)
                    await update.message.reply_text(
                        "👇 Select quality:",
                        reply_markup=keyboard
                    )
                    
                    context.user_data['last_url'] = text
                    context.user_data['last_platform'] = platform
                    
                else:
                    await update.message.reply_text("📥 Downloading with best quality...")
                    await self.download_video(update, text, 'best')
            
            else:
                await update.message.reply_text("📥 Downloading...")
                await self.process_url(update, text, platform)
        
        else:
            await update.message.reply_text(
                "Please send a valid URL starting with http:// or https://"
            )
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ Download cancelled.")
            return
        
        if data.startswith('download_'):
            format_id = data.replace('download_', '')
            
            url = context.user_data.get('last_url')
            if not url:
                await query.edit_message_text("❌ URL not found!")
                return
            
            await query.edit_message_text(f"⏳ Downloading...")
            await self.download_video(update, url, format_id, query)
    
    async def download_video(self, update: Update, url, format_spec, query=None):
        try:
            chat_id = update.effective_chat.id
            
            ydl_opts = {
                'format': format_spec,
                'quiet': True,
                'outtmpl': str(self.download_dir / '%(title).100s.%(ext)s'),
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                if os.path.exists(filename):
                    file_size = os.path.getsize(filename) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(filename)
                        error_msg = f"❌ File too large: {file_size:.1f}MB"
                        if query:
                            await query.edit_message_text(error_msg)
                        else:
                            await update.message.reply_text(error_msg)
                        return
                    
                    # Send file
                    with open(filename, 'rb') as f:
                        if filename.endswith(('.mp3', '.m4a')):
                            await update.message.reply_audio(
                                audio=f,
                                caption=f"🎵 {info.get('title', 'Audio')[:50]}\nSize: {file_size:.1f}MB"
                            )
                        elif filename.endswith(('.mp4', '.avi', '.mkv', '.mov', '.webm')):
                            await update.message.reply_video(
                                video=f,
                                caption=f"📹 {info.get('title', 'Video')[:50]}\nSize: {file_size:.1f}MB",
                                supports_streaming=True
                            )
                        elif filename.endswith(('.jpg', '.jpeg', '.png', '.gif')):
                            await update.message.reply_photo(
                                photo=f,
                                caption=f"🖼️ {info.get('title', 'Image')[:50]}\nSize: {file_size:.1f}MB"
                            )
                        else:
                            await update.message.reply_document(
                                document=f,
                                caption=f"📄 {info.get('title', 'File')[:50]}\nSize: {file_size:.1f}MB"
                            )
                    
                    success_msg = f"✅ Download complete! ({file_size:.1f}MB)"
                    if query:
                        await query.edit_message_text(success_msg)
                    else:
                        await update.message.reply_text(success_msg)
                    
                    # Schedule deletion
                    threading.Thread(target=lambda: self.delete_file_later(filename), daemon=True).start()
                    
                else:
                    error_msg = "❌ File not found"
                    if query:
                        await query.edit_message_text(error_msg)
                    else:
                        await update.message.reply_text(error_msg)
                        
        except Exception as e:
            logger.error(f"Download error: {e}")
            error_msg = f"❌ Error: {str(e)[:100]}"
            if query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
    
    def delete_file_later(self, filename):
        time.sleep(120)
        if os.path.exists(filename):
            try:
                os.remove(filename)
            except:
                pass
    
    async def process_url(self, update: Update, url, platform):
        try:
            ydl_opts = {
                'format': 'best',
                'quiet': True,
                'outtmpl': str(self.download_dir / '%(title).100s.%(ext)s'),
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                if os.path.exists(filename):
                    file_size = os.path.getsize(filename) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(filename)
                        await update.message.reply_text(f"❌ File too large: {file_size:.1f}MB")
                        return
                    
                    with open(filename, 'rb') as f:
                        if filename.endswith(('.mp3', '.m4a')):
                            await update.message.reply_audio(
                                audio=f,
                                caption=f"🎵 {info.get('title', 'Audio')[:50]}\nSize: {file_size:.1f}MB"
                            )
                        elif filename.endswith(('.mp4', '.avi', '.mkv', '.mov', '.webm')):
                            await update.message.reply_video(
                                video=f,
                                caption=f"📹 {info.get('title', 'Video')[:50]}\nSize: {file_size:.1f}MB",
                                supports_streaming=True
                            )
                        elif filename.endswith(('.jpg', '.jpeg', '.png', '.gif')):
                            await update.message.reply_photo(
                                photo=f,
                                caption=f"🖼️ {info.get('title', 'Image')[:50]}\nSize: {file_size:.1f}MB"
                            )
                        else:
                            await update.message.reply_document(
                                document=f,
                                caption=f"📄 {info.get('title', 'File')[:50]}\nSize: {file_size:.1f}MB"
                            )
                    
                    await update.message.reply_text(f"✅ Download complete! ({file_size:.1f}MB)")
                    
                    threading.Thread(target=lambda: self.delete_file_later(filename), daemon=True).start()
                    
        except Exception as e:
            logger.error(f"Process error: {e}")
            await update.message.reply_text(f"❌ Error: {str(e)[:100]}")
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        await update.message.reply_text(
            "📖 **Help**\n\n"
            "Send YouTube/Twitter link → Choose quality\n"
            "Send other links → Auto download\n"
            "Files auto deleted after 2 minutes",
            parse_mode='Markdown'
        )
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        await update.message.reply_text(
            f"📊 **Status**\n\n"
            f"✅ Bot active\n"
            f"📁 Files: {len(files)}\n"
            f"💾 Size: {total_size:.1f}MB\n"
            f"👤 Your ID: {user.id}",
            parse_mode='Markdown'
        )
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        hours = 1
        if context.args:
            try:
                hours = int(context.args[0])
            except:
                hours = 1
        
        self.is_paused = True
        self.paused_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸️ Bot paused for {hours} hour(s)\n"
            f"Resume at: {self.paused_until.strftime('%H:%M')}"
        )
    
    async def resume_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        self.is_paused = False
        self.paused_until = None
        await update.message.reply_text("▶️ Bot resumed!")
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        count = len(files)
        
        for f in files:
            try:
                f.unlink()
            except:
                pass
        
        await update.message.reply_text(f"🧹 Cleaned {count} files")
    
    def run(self):
        print("=" * 50)
        print("🤖 Telegram Download Bot")
        print("=" * 50)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Configure token in config.json")
            return
        
        print(f"✅ Token: {self.token[:15]}...")
        
        app = Application.builder().token(self.token).build()
        
        app.add_handler(CommandHandler("start", self.start_command))
        app.add_handler(CommandHandler("help", self.help_command))
        app.add_handler(CommandHandler("status", self.status_command))
        app.add_handler(CommandHandler("pause", self.pause_command))
        app.add_handler(CommandHandler("resume", self.resume_command))
        app.add_handler(CommandHandler("clean", self.clean_command))
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        app.add_handler(CallbackQueryHandler(self.handle_callback))
        
        print("✅ Bot ready!")
        print("📱 Send YouTube link to test")
        print("=" * 50)
        
        app.run_polling()

def main():
    try:
        bot = QualityDownloadBot()
        bot.run()
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped")
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == '__main__':
    main()
EOF

# Step 6: Create config.json
print_blue "6. Creating config.json..."
cat > config.json << 'EOF'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "download_dir": "downloads",
    "auto_cleanup_minutes": 2
}
EOF

# Step 7: Create management script
print_blue "7. Creating management script..."
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Quality bot management

cd "$(dirname "$0")"

case "$1" in
    start)
        echo "🚀 Starting Quality Bot..."
        source venv/bin/activate
        > bot.log
        nohup python bot.py >> bot.log 2>&1 &
        echo $! > bot.pid
        echo "✅ Bot started (PID: $(cat bot.pid))"
        echo "📝 Logs: tail -f bot.log"
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
        ./manage.sh stop
        sleep 2
        ./manage.sh start
        ;;
    status)
        echo "📊 Bot Status:"
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ Bot running (PID: $(cat bot.pid))"
            echo "📝 Recent logs:"
            tail -5 bot.log 2>/dev/null || echo "No logs"
        else
            echo "❌ Bot not running"
            [ -f "bot.pid" ] && rm -f bot.pid
        fi
        ;;
    logs)
        echo "📝 Bot logs:"
        if [ -f "bot.log" ]; then
            if [ "$2" = "-f" ]; then
                tail -f bot.log
            else
                tail -50 bot.log
            fi
        else
            echo "No log file"
        fi
        ;;
    config)
        echo "⚙️ Editing config..."
        nano config.json
        echo "💡 Restart after editing: ./manage.sh restart"
        ;;
    test)
        echo "🔍 Testing..."
        source venv/bin/activate
        python3 -c "
try:
    import telegram, yt_dlp, requests
    print('✅ All imports OK')
except Exception as e:
    print(f'❌ Import error: {e}')
"
        ;;
    debug)
        echo "🐛 Debug mode..."
        ./manage.sh stop
        source venv/bin/activate
        python bot.py
        ;;
    clean)
        echo "🧹 Cleaning..."
        rm -rf downloads/*
        echo "✅ Files cleaned"
        ;;
    *)
        echo "🤖 Quality Download Bot Management"
        echo "================================="
        echo "📁 Directory: /opt/quality-tg-bot"
        echo ""
        echo "📋 Commands:"
        echo "  ./manage.sh start      # Start bot"
        echo "  ./manage.sh stop       # Stop bot"
        echo "  ./manage.sh restart    # Restart bot"
        echo "  ./manage.sh status     # Check status"
        echo "  ./manage.sh logs       # View logs"
        echo "  ./manage.sh config     # Edit config"
        echo "  ./manage.sh test       # Test everything"
        echo "  ./manage.sh debug      # Debug mode"
        echo "  ./manage.sh clean      # Clean files"
        ;;
esac
EOF

chmod +x manage.sh

# Step 8: Create requirements.txt
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
EOF

print_green "✅ INSTALLATION COMPLETE!"
echo ""
echo "📋 SETUP STEPS:"
echo "================"
echo "1. Configure bot:"
echo "   cd /opt/quality-tg-bot"
echo "   nano config.json"
echo "   • Replace YOUR_BOT_TOKEN_HERE with your token"
echo "   • Add your Telegram ID to admin_ids"
echo ""
echo "2. Start bot:"
echo "   ./manage.sh start"
echo ""
echo "3. Test:"
echo "   ./manage.sh test"
echo "   ./manage.sh status"
echo ""
echo "4. In Telegram:"
echo "   • Find your bot"
echo "   • Send /start"
echo "   • Send YouTube link → Choose quality"
echo ""
echo "🚀 Install command for others:"
echo "bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)"
