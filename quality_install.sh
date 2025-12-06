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
import mimetypes

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
            file_extensions = ['.mp4', '.avi', '.mkv', '.mov', '.mp3', '.m4a', '.wav', 
                              '.jpg', '.jpeg', '.png', '.gif', '.pdf', '.zip', '.rar']
            for ext in file_extensions:
                if url_lower.endswith(ext):
                    return 'direct'
            return 'generic'
    
    async def get_video_formats(self, url, platform='youtube'):
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
            }
            
            if platform == 'instagram':
                ydl_opts['cookiefile'] = 'cookies.txt'
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                formats = []
                if 'formats' in info:
                    for fmt in info['formats']:
                        if fmt.get('vcodec') == 'none' and fmt.get('acodec') != 'none':
                            continue
                        
                        resolution = fmt.get('resolution', 'N/A')
                        if resolution == 'audio only':
                            continue
                        
                        filesize = fmt.get('filesize')
                        if not filesize and fmt.get('tbr') and info.get('duration'):
                            duration = info.get('duration', 60)
                            filesize = (fmt['tbr'] * 1000 * duration) / 8
                        
                        if not filesize:
                            continue
                        
                        format_note = fmt.get('format_note', '')
                        if not format_note and resolution != 'N/A':
                            format_note = resolution
                        
                        size_mb = filesize / (1024 * 1024)
                        max_size = self.config['telegram']['max_file_size']
                        
                        if size_mb > max_size:
                            continue
                        
                        format_id = fmt.get('format_id', 'best')
                        
                        if resolution == 'N/A' and format_note:
                            quality_label = f"{format_note} - {size_mb:.1f}MB"
                        elif resolution != 'N/A':
                            quality_label = f"{resolution} - {size_mb:.1f}MB"
                        else:
                            quality_label = f"Unknown - {size_mb:.1f}MB"
                        
                        formats.append({
                            'format_id': format_id,
                            'resolution': resolution,
                            'format_note': format_note,
                            'filesize_mb': round(size_mb, 1),
                            'quality': quality_label
                        })
                
                def sort_key(fmt):
                    res = fmt['resolution']
                    if res == 'N/A':
                        return (0, -fmt['filesize_mb'])
                    if 'x' in res:
                        try:
                            w, h = map(int, res.split('x'))
                            return (-h, -w, -fmt['filesize_mb'])
                        except:
                            return (0, -fmt['filesize_mb'])
                    return (0, -fmt['filesize_mb'])
                
                formats.sort(key=sort_key)
                
                unique_formats = []
                seen = set()
                for fmt in formats:
                    key = (fmt['resolution'], round(fmt['filesize_mb'], 1))
                    if key not in seen:
                        seen.add(key)
                        unique_formats.append(fmt)
                
                return unique_formats[:6]
                
        except Exception as e:
            logger.error(f"Error getting formats: {e}")
            return []
    
    def create_quality_keyboard(self, formats, platform):
        keyboard = []
        
        if formats:
            for fmt in formats:
                quality_label = fmt['quality']
                if len(quality_label) > 40:
                    quality_label = quality_label[:37] + "..."
                
                callback_data = f"download_{platform}_{fmt['format_id']}"
                
                if platform == 'youtube':
                    button_text = f"🎬 {quality_label}"
                elif platform == 'twitter':
                    button_text = f"🐦 {quality_label}"
                elif platform == 'instagram':
                    button_text = f"📸 {quality_label}"
                else:
                    button_text = f"📹 {quality_label}"
                
                keyboard.append([
                    InlineKeyboardButton(button_text, callback_data=callback_data)
                ])
            
            if platform == 'youtube':
                keyboard.append([
                    InlineKeyboardButton("🎵 MP3 Audio Only", callback_data="download_youtube_bestaudio")
                ])
        else:
            keyboard.append([
                InlineKeyboardButton("📹 Best Quality", callback_data=f"download_{platform}_best")
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
✅ Instagram (choose quality with file size)
✅ TikTok  
✅ Facebook
✅ Direct files

🎯 **How to use:**
1. Send YouTube/Twitter/Instagram link → Choose quality
2. Send other links → Auto download
3. Send direct file link → Download file

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
        
        text = update.message.text.strip()
        
        if text.startswith(('http://', 'https://')):
            platform = self.detect_platform(text)
            
            context.user_data['last_url'] = text
            context.user_data['last_platform'] = platform
            context.user_data['chat_id'] = update.effective_chat.id
            context.user_data['message_id'] = update.message.message_id
            
            if platform in ['youtube', 'twitter', 'instagram']:
                await update.message.reply_text(f"🔍 Getting available qualities from {platform}...")
                formats = await self.get_video_formats(text, platform)
                
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
                    
                else:
                    await update.message.reply_text("📥 Downloading with best quality...")
                    await self.download_media(update, context, text, 'best', platform, is_callback=False)
            
            elif platform == 'direct':
                await self.download_direct_file(update, context, text)
            
            else:
                await update.message.reply_text(f"📥 Processing {platform} link...")
                await self.download_media(update, context, text, 'best', platform, is_callback=False)
        
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
            parts = data.split('_')
            if len(parts) >= 3:
                platform = parts[1]
                format_id = parts[2]
                
                url = context.user_data.get('last_url')
                chat_id = context.user_data.get('chat_id')
                message_id = context.user_data.get('message_id')
                
                if not url:
                    await query.edit_message_text("❌ URL not found!")
                    return
                
                await query.edit_message_text(f"⏳ Downloading {format_id}...")
                
                # Get the original message for sending file
                try:
                    original_message = await context.bot.get_chat(chat_id=chat_id)
                except:
                    original_message = None
                
                await self.download_media(update, context, url, format_id, platform, is_callback=True, query=query)
    
    async def download_media(self, update: Update, context: ContextTypes.DEFAULT_TYPE, url, format_spec, platform, is_callback=False, query=None):
        try:
            chat_id = update.effective_chat.id
            
            ydl_opts = {
                'format': format_spec,
                'quiet': True,
                'outtmpl': str(self.download_dir / '%(id)s_%(title).100s.%(ext)s'),
                'http_headers': {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            }
            
            if platform == 'instagram':
                ydl_opts['cookiefile'] = 'cookies.txt'
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # Find actual file
                actual_file = self.find_downloaded_file(filename)
                
                if actual_file and os.path.exists(actual_file):
                    file_size = os.path.getsize(actual_file) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(actual_file)
                        error_msg = f"❌ File too large: {file_size:.1f}MB"
                        if is_callback and query:
                            await query.edit_message_text(error_msg)
                        else:
                            await update.message.reply_text(error_msg)
                        return
                    
                    # Send file - ALWAYS use update.message for sending files
                    await self.send_file(update, actual_file, info, is_callback, query)
                    
                    # Schedule deletion
                    threading.Thread(target=lambda: self.delete_file_later(actual_file), daemon=True).start()
                    
                else:
                    error_msg = "❌ File not found after download"
                    if is_callback and query:
                        await query.edit_message_text(error_msg)
                    else:
                        await update.message.reply_text(error_msg)
                        
        except Exception as e:
            logger.error(f"Download error: {e}")
            error_msg = f"❌ Error: {str(e)[:100]}"
            if is_callback and query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
    
    def find_downloaded_file(self, base_filename):
        base = os.path.splitext(base_filename)[0]
        
        for ext in ['.mp4', '.mkv', '.webm', '.m4a', '.mp3', '.flv', '.avi', '.mov']:
            if os.path.exists(base + ext):
                return base + ext
        
        if os.path.exists(base_filename):
            return base_filename
        
        return None
    
    async def download_direct_file(self, update: Update, context: ContextTypes.DEFAULT_TYPE, url):
        try:
            await update.message.reply_text("📥 Downloading file...")
            
            filename = os.path.basename(url.split('?')[0])
            if not filename:
                filename = f"file_{int(time.time())}"
            
            filepath = self.download_dir / filename
            
            response = requests.get(url, stream=True, timeout=30)
            response.raise_for_status()
            
            with open(filepath, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            
            file_size = os.path.getsize(filepath) / (1024 * 1024)
            max_size = self.config['telegram']['max_file_size']
            
            if file_size > max_size:
                os.remove(filepath)
                await update.message.reply_text(f"❌ File too large: {file_size:.1f}MB")
                return
            
            # Send file
            await self.send_file(update, str(filepath), {'title': filename}, is_callback=False, query=None)
            
            # Schedule deletion
            threading.Thread(target=lambda: self.delete_file_later(str(filepath)), daemon=True).start()
            
        except Exception as e:
            logger.error(f"Direct download error: {e}")
            await update.message.reply_text(f"❌ Download error: {str(e)[:100]}")
    
    async def send_file(self, update, filepath, info, is_callback=False, query=None):
        """Send file to Telegram - FIXED VERSION"""
        try:
            file_size = os.path.getsize(filepath) / (1024 * 1024)
            title = info.get('title', os.path.basename(filepath))[:100]
            
            caption = f"✅ **Download Complete!**\n"
            caption += f"📁 **Title:** {title}\n"
            caption += f"📊 **Size:** {file_size:.1f}MB"
            
            # Get mime type
            mime_type, _ = mimetypes.guess_type(filepath)
            
            with open(filepath, 'rb') as f:
                if mime_type:
                    if mime_type.startswith('audio/'):
                        await update.message.reply_audio(
                            audio=f,
                            caption=caption,
                            title=title[:64],
                            parse_mode='Markdown'
                        )
                    elif mime_type.startswith('video/'):
                        await update.message.reply_video(
                            video=f,
                            caption=caption,
                            supports_streaming=True,
                            parse_mode='Markdown'
                        )
                    elif mime_type.startswith('image/'):
                        await update.message.reply_photo(
                            photo=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
                    else:
                        await update.message.reply_document(
                            document=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
                else:
                    # Fallback based on extension
                    if filepath.endswith(('.mp3', '.m4a', '.wav', '.flac')):
                        await update.message.reply_audio(
                            audio=f,
                            caption=caption,
                            title=title[:64],
                            parse_mode='Markdown'
                        )
                    elif filepath.endswith(('.mp4', '.avi', '.mkv', '.mov', '.webm')):
                        await update.message.reply_video(
                            video=f,
                            caption=caption,
                            supports_streaming=True,
                            parse_mode='Markdown'
                        )
                    elif filepath.endswith(('.jpg', '.jpeg', '.png', '.gif')):
                        await update.message.reply_photo(
                            photo=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
                    else:
                        await update.message.reply_document(
                            document=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
            
            success_msg = f"✅ File sent successfully! ({file_size:.1f}MB)"
            
            if is_callback and query:
                await query.edit_message_text(success_msg)
            else:
                await update.message.reply_text(success_msg)
                
        except Exception as e:
            logger.error(f"Error sending file: {e}")
            error_msg = f"❌ Error sending file: {str(e)[:100]}"
            if is_callback and query:
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
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        await update.message.reply_text(
            "📖 **Help**\n\n"
            "Send YouTube/Twitter/Instagram link → Choose quality\n"
            "Send other links → Auto download\n"
            "Send direct file link → Download file\n\n"
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
        print("📱 Send YouTube/Twitter/Instagram link to test")
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
        echo ""
        echo "🎯 Features:"
        echo "   • YouTube quality selection with file sizes"
        echo "   • Twitter quality selection with file sizes"
        echo "   • Instagram quality selection with file sizes"
        echo "   • Direct file download"
        echo "   • Auto cleanup every 2 minutes"
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
        
        echo "1. Testing imports..."
        python3 -c "
try:
    import telegram, yt_dlp, requests, mimetypes
    print('✅ All imports OK')
except Exception as e:
    print(f'❌ Import error: {e}')
"
        
        echo ""
        echo "2. Testing config..."
        python3 -c "
import json
try:
    with open('config.json') as f:
        config = json.load(f)
    
    token = config['telegram']['token']
    if token == 'YOUR_BOT_TOKEN_HERE':
        print('❌ Token not configured!')
    else:
        print(f'✅ Token: {token[:15]}...')
        print(f'✅ Max size: {config[\"telegram\"][\"max_file_size\"]}MB')
except Exception as e:
    print(f'❌ Config error: {e}')
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
        echo ""
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
        echo ""
        echo "🎯 Features:"
        echo "  • YouTube quality selection with file sizes"
        echo "  • Twitter quality selection with file sizes"
        echo "  • Instagram quality selection with file sizes"
        echo "  • Direct file download"
        echo "  • Auto cleanup (2 minutes)"
        echo "  • Pause/Resume functionality"
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
echo "   • Send YouTube/Twitter/Instagram link → Choose quality"
echo "   • Send direct file link → Download file"
echo ""
echo "🚀 Install command for others:"
echo "bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)"
