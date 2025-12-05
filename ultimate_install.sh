#!/bin/bash
# ultimate_install.sh - Ultimate Telegram download bot with all features
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/ultimate_install.sh)

set -e

echo "🌟 Ultimate Telegram Download Bot Installer"
echo "==========================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_green() { echo -e "${GREEN}[✓]${NC} $1"; }
print_red() { echo -e "${RED}[✗]${NC} $1"; }
print_yellow() { echo -e "${YELLOW}[!]${NC} $1"; }
print_blue() { echo -e "${BLUE}[i]${NC} $1"; }

# Install directory
INSTALL_DIR="/opt/ultimate-tg-bot"

# Step 1: Cleanup old installations
print_blue "1. Cleaning old installations..."
pkill -f "python.*bot.py" 2>/dev/null || true
rm -rf "$INSTALL_DIR" 2>/dev/null || true
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 2: Install system dependencies
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

# Step 5: Create bot.py with ALL features
print_blue "5. Creating ultimate bot.py..."
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Ultimate Telegram Download Bot with ALL Features:
1. Download from YouTube, Instagram, Twitter, TikTok, Facebook
2. Download any direct file link
3. Auto cleanup (files deleted after 2 minutes)
4. Pause/resume functionality
5. Schedule bot working hours
6. Easy uninstall
7. Status monitoring
"""

import os
import json
import logging
import asyncio
import threading
import time
import schedule
from datetime import datetime, timedelta
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import yt_dlp
import requests

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

class UltimateDownloadBot:
    def __init__(self):
        self.config = self.load_config()
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        # Bot state
        self.is_paused = False
        self.paused_until = None
        self.schedule_enabled = self.config.get('schedule', {}).get('enabled', False)
        self.schedule_start = self.config.get('schedule', {}).get('start_time', '00:00')
        self.schedule_end = self.config.get('schedule', {}).get('end_time', '23:59')
        
        # Create directories
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # Start auto cleanup thread
        self.start_auto_cleanup()
        
        logger.info("🤖 Ultimate Bot initialized")
    
    def load_config(self):
        """Load configuration"""
        config_file = 'config.json'
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                return json.load(f)
        
        # Default config with all features
        config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'auto_cleanup_minutes': 2,
            'schedule': {
                'enabled': False,
                'start_time': '08:00',
                'end_time': '23:00',
                'days': [0, 1, 2, 3, 4, 5, 6]  # 0=Monday, 6=Sunday
            }
        }
        
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
        
        return config
    
    def save_config(self):
        """Save configuration"""
        with open('config.json', 'w') as f:
            json.dump(self.config, f, indent=4)
    
    def start_auto_cleanup(self):
        """Start auto cleanup thread"""
        def cleanup_worker():
            cleanup_minutes = self.config.get('auto_cleanup_minutes', 2)
            while True:
                try:
                    self.cleanup_old_files(cleanup_minutes)
                    time.sleep(60)  # Check every minute
                except Exception as e:
                    logger.error(f"Cleanup error: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=cleanup_worker, daemon=True)
        thread.start()
        logger.info(f"🧹 Auto cleanup started (every {self.config.get('auto_cleanup_minutes', 2)} minutes)")
    
    def cleanup_old_files(self, minutes=2):
        """Cleanup files older than X minutes"""
        cutoff_time = time.time() - (minutes * 60)
        files_deleted = 0
        
        for file_path in self.download_dir.glob('*'):
            if file_path.is_file():
                file_age = time.time() - file_path.stat().st_mtime
                if file_age > (minutes * 60):
                    try:
                        file_path.unlink()
                        files_deleted += 1
                        logger.debug(f"Deleted old file: {file_path.name}")
                    except Exception as e:
                        logger.error(f"Error deleting {file_path}: {e}")
        
        if files_deleted > 0:
            logger.info(f"Cleaned {files_deleted} old files")
    
    def check_bot_availability(self):
        """Check if bot should be available based on schedule/pause"""
        # Check if paused
        if self.is_paused:
            if self.paused_until and datetime.now() < self.paused_until:
                return False, f"Bot paused until {self.paused_until.strftime('%H:%M')}"
            else:
                # Auto resume if pause time passed
                self.is_paused = False
                self.paused_until = None
        
        # Check schedule
        if self.schedule_enabled:
            now = datetime.now()
            current_time = now.strftime("%H:%M")
            current_day = now.weekday()
            
            schedule_days = self.config.get('schedule', {}).get('days', [])
            
            if current_day not in schedule_days:
                return False, f"Bot not available today. Available days: {schedule_days}"
            
            if not (self.schedule_start <= current_time <= self.schedule_end):
                return False, f"Bot available from {self.schedule_start} to {self.schedule_end}"
        
        return True, "Bot is available"
    
    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        # Check bot availability
        is_available, message = self.check_bot_availability()
        
        welcome = f"""
Hello {user.first_name}! 👋

🤖 **Ultimate Download Bot**

📥 **Supported Platforms:**
✅ YouTube
✅ Instagram (Reels/Posts)
✅ Twitter/X
✅ TikTok
✅ Facebook
✅ Direct file links
✅ Generic URLs

⚡ **Features:**
• Auto cleanup (files deleted after 2 min)
• Pause/Resume bot
• Schedule working hours
• Quality selection
• Admin controls

🛠️ **Commands:**
/start - This menu
/help - Detailed help
/download [url] - Download link
/status - Bot status
/pause [hours] - Pause bot
/resume - Resume bot
/schedule - Set working hours
/clean - Clean temp files
/stats - Download statistics

📊 **Current Status:**
{message}

🎯 **How to use:**
Just send me a video link!
"""
        
        await update.message.reply_text(welcome, parse_mode='Markdown')
        logger.info(f"User {user.id} started bot")
    
    async def help(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
📖 **Ultimate Bot Help Guide**

🔗 **Supported Links:**
• YouTube: https://youtube.com/watch?v=...
• Instagram: https://instagram.com/p/... or /reel/...
• Twitter/X: https://twitter.com/.../status/...
• TikTok: https://tiktok.com/@.../video/...
• Facebook: https://facebook.com/watch/?v=...
• Direct files: Any direct download link

⚙️ **Admin Commands (for admins only):**
/status - Detailed bot status
/pause [hours] - Pause bot for X hours
/resume - Resume bot immediately
/schedule on 08:00 23:00 - Set working hours
/schedule off - Disable schedule
/stats - Download statistics
/clean - Force cleanup

⏰ **Schedule Format:**
/schedule on [start_time] [end_time]
Example: /schedule on 09:00 18:00

⏸️ **Pause Format:**
/pause [hours]
Example: /pause 3 (pauses for 3 hours)

🧹 **Auto Cleanup:**
Files are automatically deleted after 2 minutes
Use /clean to manually clean now

🔧 **Need help?**
Contact admin or check /status
"""
        
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    async def status(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user = update.effective_user
        
        # Check if admin
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        # Get bot status
        is_available, avail_message = self.check_bot_availability()
        
        # Count files
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        status_text = f"""
📊 **Bot Status Report**

🤖 **Basic Info:**
• Status: {'✅ Active' if is_available else '⏸️ Paused'}
• Availability: {avail_message}
• Paused until: {self.paused_until.strftime('%Y-%m-%d %H:%M') if self.paused_until else 'Not paused'}

⚙️ **Settings:**
• Schedule: {'✅ ON' if self.schedule_enabled else '❌ OFF'}
• Schedule hours: {self.schedule_start} to {self.schedule_end}
• Auto cleanup: Every {self.config.get('auto_cleanup_minutes', 2)} minutes
• Max file size: {self.config['telegram']['max_file_size']}MB

📁 **Storage:**
• Temp files: {len(files)}
• Total size: {total_size:.1f}MB
• Directory: {self.download_dir}

👤 **User Info:**
• Your ID: {user.id}
• Your name: {user.first_name}
• Admin: {'✅ Yes' if user.id in self.admin_ids else '❌ No'}

🔄 **Last cleanup:** {datetime.now().strftime('%H:%M:%S')}
"""
        
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def pause(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Pause bot for X hours"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        hours = 1  # Default 1 hour
        if context.args:
            try:
                hours = int(context.args[0])
                if hours > 24:
                    hours = 24
            except:
                hours = 1
        
        self.is_paused = True
        self.paused_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸️ Bot paused for {hours} hour(s)\n"
            f"Will resume at: {self.paused_until.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
            f"Use /resume to resume immediately"
        )
        
        logger.info(f"Bot paused by {user.id} for {hours} hours")
    
    async def resume(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Resume bot immediately"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        self.is_paused = False
        self.paused_until = None
        
        await update.message.reply_text("▶️ Bot resumed successfully!")
        logger.info(f"Bot resumed by {user.id}")
    
    async def schedule_cmd(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Set bot schedule"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        if not context.args:
            # Show current schedule
            status = "ON" if self.schedule_enabled else "OFF"
            await update.message.reply_text(
                f"📅 Current schedule: {status}\n"
                f"⏰ Hours: {self.schedule_start} to {self.schedule_end}\n\n"
                f"To change:\n"
                f"/schedule on 08:00 23:00\n"
                f"/schedule off"
            )
            return
        
        action = context.args[0].lower()
        
        if action == 'on':
            if len(context.args) >= 3:
                start_time = context.args[1]
                end_time = context.args[2]
                
                # Validate times
                try:
                    datetime.strptime(start_time, '%H:%M')
                    datetime.strptime(end_time, '%H:%M')
                    
                    self.schedule_enabled = True
                    self.schedule_start = start_time
                    self.schedule_end = end_time
                    
                    # Update config
                    self.config['schedule']['enabled'] = True
                    self.config['schedule']['start_time'] = start_time
                    self.config['schedule']['end_time'] = end_time
                    self.save_config()
                    
                    await update.message.reply_text(
                        f"✅ Schedule set!\n"
                        f"Bot will work from {start_time} to {end_time}"
                    )
                    logger.info(f"Schedule set to {start_time}-{end_time} by {user.id}")
                    
                except ValueError:
                    await update.message.reply_text("❌ Invalid time format. Use HH:MM")
            else:
                await update.message.reply_text("❌ Usage: /schedule on [start_time] [end_time]\nExample: /schedule on 08:00 23:00")
        
        elif action == 'off':
            self.schedule_enabled = False
            self.config['schedule']['enabled'] = False
            self.save_config()
            
            await update.message.reply_text("✅ Schedule disabled. Bot available 24/7")
            logger.info(f"Schedule disabled by {user.id}")
        
        else:
            await update.message.reply_text("❌ Usage: /schedule [on/off] [start_time] [end_time]")
    
    async def clean(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Clean temp files"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        files = list(self.download_dir.glob('*'))
        files_count = len(files)
        
        for file_path in files:
            if file_path.is_file():
                try:
                    file_path.unlink()
                except:
                    pass
        
        await update.message.reply_text(f"🧹 Cleaned {files_count} temporary files")
        logger.info(f"Cleaned {files_count} files by {user.id}")
    
    async def stats(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Show download statistics"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        # Count files by type
        files = list(self.download_dir.glob('*'))
        video_count = sum(1 for f in files if f.suffix in ['.mp4', '.mkv', '.avi', '.mov'])
        audio_count = sum(1 for f in files if f.suffix in ['.mp3', '.m4a', '.wav'])
        other_count = len(files) - video_count - audio_count
        
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        stats_text = f"""
📈 **Download Statistics**

📁 **File Count:**
• Total files: {len(files)}
• Videos: {video_count}
• Audio: {audio_count}
• Other: {other_count}

💾 **Storage:**
• Total size: {total_size:.1f}MB
• Average size: {total_size/len(files) if files else 0:.1f}MB/file

⚙️ **Bot Status:**
• Paused: {'Yes' if self.is_paused else 'No'}
• Schedule: {'Enabled' if self.schedule_enabled else 'Disabled'}
• Auto cleanup: Every {self.config.get('auto_cleanup_minutes', 2)} minutes

🔄 **Last activity:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
"""
        
        await update.message.reply_text(stats_text, parse_mode='Markdown')
    
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
        elif any(ext in url_lower for ext in ['.mp4', '.mp3', '.avi', '.mkv', '.mov', '.wav', '.pdf', '.zip', '.rar']):
            return 'direct_file'
        else:
            return 'generic'
    
    async def download_url(self, update: Update, url):
        """Download from URL with platform-specific handling"""
        platform = self.detect_platform(url)
        
        try:
            if platform == 'direct_file':
                # Download direct file
                await update.message.reply_text("📥 Downloading direct file...")
                
                response = requests.get(url, stream=True, timeout=30)
                response.raise_for_status()
                
                # Get filename
                filename = os.path.basename(url.split('?')[0])
                if not filename:
                    filename = f"file_{int(time.time())}"
                
                filepath = self.download_dir / filename
                
                with open(filepath, 'wb') as f:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)
                
                file_size = os.path.getsize(filepath) / (1024 * 1024)
                
                # Send file based on type
                with open(filepath, 'rb') as f:
                    if filename.endswith(('.mp3', '.m4a', '.wav', '.ogg')):
                        await update.message.reply_audio(
                            audio=f,
                            caption=f"🎵 {filename}\nSize: {file_size:.1f}MB"
                        )
                    elif filename.endswith(('.mp4', '.avi', '.mkv', '.mov', '.webm')):
                        await update.message.reply_video(
                            video=f,
                            caption=f"📹 {filename}\nSize: {file_size:.1f}MB"
                        )
                    elif filename.endswith(('.jpg', '.jpeg', '.png', '.gif')):
                        await update.message.reply_photo(
                            photo=f,
                            caption=f"🖼️ {filename}\nSize: {file_size:.1f}MB"
                        )
                    else:
                        await update.message.reply_document(
                            document=f,
                            caption=f"📄 {filename}\nSize: {file_size:.1f}MB"
                        )
                
                # Schedule deletion
                self.schedule_file_deletion(filepath)
                return True
                
            else:
                # Use yt-dlp for social media
                await update.message.reply_text(f"📥 Downloading from {platform}...")
                
                # Platform-specific yt-dlp options
                ydl_opts = {
                    'quiet': True,
                    'no_warnings': True,
                    'outtmpl': str(self.download_dir / '%(title).100s.%(ext)s'),
                }
                
                # Platform-specific format selection
                if platform == 'instagram':
                    ydl_opts['format'] = 'best'
                elif platform == 'twitter':
                    ydl_opts['format'] = 'best'
                elif platform == 'tiktok':
                    ydl_opts['format'] = 'best'
                else:  # youtube, facebook, generic
                    ydl_opts['format'] = 'best[height<=720]/best'
                
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=True)
                    filename = ydl.prepare_filename(info)
                    
                    if os.path.exists(filename):
                        file_size = os.path.getsize(filename) / (1024 * 1024)
                        
                        # Check file size limit
                        max_size = self.config['telegram']['max_file_size']
                        if file_size > max_size:
                            os.remove(filename)
                            await update.message.reply_text(
                                f"❌ File too large: {file_size:.1f}MB > {max_size}MB limit"
                            )
                            return False
                        
                        # Send file
                        with open(filename, 'rb') as f:
                            if filename.endswith(('.mp3', '.m4a', '.wav')):
                                await update.message.reply_audio(
                                    audio=f,
                                    caption=f"🎵 {info.get('title', 'Audio')}\nSize: {file_size:.1f}MB"
                                )
                            else:
                                await update.message.reply_video(
                                    video=f,
                                    caption=f"📹 {info.get('title', 'Video')}\nSize: {file_size:.1f}MB"
                                )
                        
                        # Schedule deletion
                        self.schedule_file_deletion(filename)
                        return True
                    else:
                        await update.message.reply_text("❌ File not found after download")
                        return False
                        
        except yt_dlp.utils.DownloadError as e:
            logger.error(f"Download error: {e}")
            await update.message.reply_text(f"❌ Download error: {str(e)[:100]}")
            return False
        except Exception as e:
            logger.error(f"Error: {e}")
            await update.message.reply_text(f"❌ Error: {str(e)[:100]}")
            return False
    
    def schedule_file_deletion(self, filepath, minutes=2):
        """Schedule file deletion after X minutes"""
        def delete_file():
            time.sleep(minutes * 60)
            if os.path.exists(filepath):
                try:
                    os.remove(filepath)
                    logger.info(f"Auto deleted: {os.path.basename(filepath)}")
                except:
                    pass
        
        thread = threading.Thread(target=delete_file, daemon=True)
        thread.start()
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        # Check bot availability
        is_available, message = self.check_bot_availability()
        if not is_available:
            await update.message.reply_text(f"⏸️ {message}")
            return
        
        text = update.message.text
        user = update.effective_user
        
        logger.info(f"Message from {user.first_name}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            success = await self.download_url(update, text)
            if success:
                logger.info(f"Download successful for {user.id}")
            else:
                logger.warning(f"Download failed for {user.id}")
        else:
            await update.message.reply_text(
                "Please send a valid URL starting with http:// or https://\n\n"
                "Supported:\n"
                "• YouTube videos\n"
                "• Instagram posts/reels\n"
                "• Twitter/X videos\n"
                "• TikTok videos\n"
                "• Facebook videos\n"
                "• Direct file links"
            )
    
    async def download_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /download command"""
        if not context.args:
            await update.message.reply_text("Usage: /download [URL]")
            return
        
        url = context.args[0]
        await self.download_url(update, url)
    
    def run(self):
        """Run the bot"""
        print("=" * 60)
        print("🤖 ULTIMATE TELEGRAM DOWNLOAD BOT")
        print("=" * 60)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ CRITICAL: Bot token not configured!")
            print("Please edit config.json and add your bot token")
            print("Get token from @BotFather on Telegram")
            return
        
        print(f"✅ Token: {self.token[:15]}...")
        print(f"⚙️ Features enabled:")
        print(f"   • Auto cleanup (2 minutes)")
        print(f"   • Pause/Resume functionality")
        print(f"   • Schedule working hours")
        print(f"   • Support for all platforms")
        print(f"   • Direct file downloads")
        print(f"   • Admin controls")
        print("🔄 Creating application...")
        
        # Create application
        app = Application.builder().token(self.token).build()
        
        # Add handlers
        app.add_handler(CommandHandler("start", self.start))
        app.add_handler(CommandHandler("help", self.help))
        app.add_handler(CommandHandler("status", self.status))
        app.add_handler(CommandHandler("pause", self.pause))
        app.add_handler(CommandHandler("resume", self.resume))
        app.add_handler(CommandHandler("schedule", self.schedule_cmd))
        app.add_handler(CommandHandler("clean", self.clean))
        app.add_handler(CommandHandler("stats", self.stats))
        app.add_handler(CommandHandler("download", self.download_command))
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        
        print("✅ Bot ready and waiting for commands")
        print("📱 In Telegram, send /start to your bot")
        print("=" * 60)
        
        # Run polling
        app.run_polling()

def main():
    """Main function"""
    try:
        bot = UltimateDownloadBot()
        bot.run()
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped by user")
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

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
    "auto_cleanup_minutes": 2,
    "schedule": {
        "enabled": false,
        "start_time": "08:00",
        "end_time": "23:00",
        "days": [0, 1, 2, 3, 4, 5, 6]
    }
}
EOF

# Step 7: Create ultimate management script
print_blue "7. Creating ultimate management script..."
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Ultimate bot management

cd "$(dirname "$0")"

case "$1" in
    start)
        echo "🚀 Starting Ultimate Bot..."
        source venv/bin/activate
        
        # Clean old logs
        > bot.log
        
        # Start bot
        nohup python bot.py >> bot.log 2>&1 &
        echo $! > bot.pid
        
        echo "✅ Ultimate Bot started (PID: $(cat bot.pid))"
        echo "📝 Logs: tail -f bot.log"
        echo "📊 Status: ./manage.sh status"
        echo ""
        echo "🌟 Features enabled:"
        echo "   • Auto cleanup (2 minutes)"
        echo "   • Pause/Resume functionality"
        echo "   • Schedule working hours"
        echo "   • All platform support"
        echo "   • Direct file downloads"
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
        echo "📊 Ultimate Bot Status:"
        echo "======================="
        
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ Bot running (PID: $(cat bot.pid))"
            
            # Show last logs
            echo ""
            echo "📝 Recent activity:"
            tail -10 bot.log 2>/dev/null | grep -v "DEBUG" || echo "No recent activity"
            
            # Show temp files
            echo ""
            echo "📁 Temporary files:"
            ls -la downloads/ 2>/dev/null | head -10 || echo "No temp files"
            
        else
            echo "❌ Bot not running"
            [ -f "bot.pid" ] && rm -f bot.pid
        fi
        
        # Show config info
        echo ""
        echo "⚙️ Configuration:"
        if [ -f "config.json" ]; then
            token=$(grep -o '"token": "[^"]*' config.json | cut -d'"' -f4)
            if [ "$token" != "YOUR_BOT_TOKEN_HERE" ]; then
                echo "✅ Token configured: ${token:0:15}..."
            else
                echo "❌ Token NOT configured!"
            fi
            
            admins=$(grep -o '"admin_ids": \[[^]]*\]' config.json)
            if [ -n "$admins" ]; then
                echo "✅ Admin IDs configured"
            else
                echo "⚠️ No admin IDs configured"
            fi
        fi
        ;;
    logs)
        echo "📝 Bot logs:"
        echo "==========="
        if [ -f "bot.log" ]; then
            if [ "$2" = "follow" ] || [ "$2" = "-f" ]; then
                tail -f bot.log
            elif [ "$2" = "error" ] || [ "$2" = "-e" ]; then
                grep -i "error\|failed\|exception" bot.log | tail -50
            elif [ "$2" = "download" ] || [ "$2" = "-d" ]; then
                grep -i "download\|downloading\|downloaded" bot.log | tail -50
            else
                tail -50 bot.log
            fi
        else
            echo "No log file"
        fi
        ;;
    config)
        echo "⚙️ Editing configuration..."
        nano config.json
        echo ""
        echo "💡 After editing config:"
        echo "   ./manage.sh restart  # Apply changes"
        ;;
    test)
        echo "🔍 Testing Ultimate Bot..."
        source venv/bin/activate
        
        echo "1. Testing Python imports..."
        python3 -c "
import sys
try:
    import telegram
    import yt_dlp
    import requests
    print('✅ All imports successful')
except ImportError as e:
    print(f'❌ Import error: {e}')
    sys.exit(1)
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
        print('Please edit config.json')
    else:
        print(f'✅ Token: {token[:15]}...')
        
    print(f'✅ Max file size: {config[\"telegram\"][\"max_file_size\"]}MB')
    print(f'✅ Auto cleanup: {config.get(\"auto_cleanup_minutes\", 2)} minutes')
    
except Exception as e:
    print(f'❌ Config error: {e}')
"
        
        echo ""
        echo "3. Testing Telegram connection..."
        python3 -c "
import requests, json
try:
    with open('config.json') as f:
        token = json.load(f)['telegram']['token']
    
    if token == 'YOUR_BOT_TOKEN_HERE':
        print('Skipping (token not set)')
    else:
        url = f'https://api.telegram.org/bot{token}/getMe'
        r = requests.get(url, timeout=10)
        
        if r.status_code == 200:
            data = r.json()
            if data['ok']:
                print('✅ Bot connected!')
                print(f'   Name: {data[\"result\"][\"first_name\"]}')
                print(f'   Username: @{data[\"result\"][\"username\"]}')
            else:
                print(f'❌ Telegram error: {data.get(\"description\")}')
        else:
            print(f'❌ HTTP error: {r.status_code}')
except Exception as e:
    print(f'❌ Error: {e}')
"
        ;;
    debug)
        echo "🐛 Debug mode (foreground)..."
        ./manage.sh stop
        sleep 1
        source venv/bin/activate
        echo "Starting bot in foreground..."
        echo "Press Ctrl+C to stop"
        echo ""
        python bot.py
        ;;
    pause)
        echo "⏸️ Pausing bot..."
        hours=${2:-1}
        echo "Bot will be paused for $hours hour(s)"
        echo "Note: This command works from Telegram"
        echo "In Telegram, send: /pause $hours"
        ;;
    schedule)
        echo "📅 Schedule management..."
        echo "Note: This command works from Telegram"
        echo ""
        echo "To enable schedule:"
        echo "   In Telegram: /schedule on 08:00 23:00"
        echo ""
        echo "To disable schedule:"
        echo "   In Telegram: /schedule off"
        echo ""
        echo "Current schedule in config.json:"
        grep -A5 '"schedule"' config.json || echo "No schedule config"
        ;;
    cleanup)
        echo "🧹 Manual cleanup..."
        rm -rf downloads/* 2>/dev/null
        echo "✅ Temporary files cleaned"
        ;;
    uninstall)
        echo "🗑️ UNINSTALL Ultimate Bot"
        echo "========================"
        echo ""
        echo "⚠️ WARNING: This will completely remove the bot!"
        echo ""
        read -p "Are you SURE? Type 'YES' to confirm: " confirm
        echo ""
        
        if [ "$confirm" = "YES" ]; then
            echo "Uninstalling..."
            ./manage.sh stop
            
            # Remove from crontab
            crontab -l 2>/dev/null | grep -v "$INSTALL_DIR" | crontab -
            
            # Remove installation directory
            cd /
            rm -rf "$INSTALL_DIR"
            
            echo "✅ Ultimate Bot completely uninstalled!"
            echo ""
            echo "To reinstall, run:"
            echo "bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/ultimate_install.sh)"
        else
            echo "❌ Uninstall cancelled"
        fi
        ;;
    autostart)
        echo "⚙️ Configuring auto-start..."
        CRON_JOB="@reboot cd $INSTALL_DIR && ./manage.sh start"
        
        # Remove existing entries
        (crontab -l 2>/dev/null | grep -v "$INSTALL_DIR") | crontab -
        
        # Add new entry
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        
        echo "✅ Auto-start configured"
        echo "Bot will start automatically on server reboot"
        ;;
    update)
        echo "🔄 Updating Ultimate Bot..."
        ./manage.sh stop
        
        # Backup config
        cp config.json config.json.backup
        
        # Download latest
        curl -s -o bot.py https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/bot.py
        
        # Restore config
        mv config.json.backup config.json
        
        # Update packages
        source venv/bin/activate
        pip install --upgrade python-telegram-bot yt-dlp requests
        
        echo "✅ Update complete"
        ./manage.sh start
        ;;
    *)
        echo "🌟 ULTIMATE TELEGRAM BOT MANAGEMENT"
        echo "=================================="
        echo ""
        echo "📁 Directory: $INSTALL_DIR"
        echo ""
        echo "🚀 MAIN COMMANDS:"
        echo "  ./manage.sh start      # Start bot"
        echo "  ./manage.sh stop       # Stop bot"
        echo "  ./manage.sh restart    # Restart bot"
        echo "  ./manage.sh status     # Detailed status"
        echo "  ./manage.sh logs       # View logs"
        echo "  ./manage.sh config     # Edit config"
        echo ""
        echo "⚙️ ADMIN FEATURES:"
        echo "  ./manage.sh pause [h]  # Pause bot (Telegram: /pause)"
        echo "  ./manage.sh schedule   # Schedule hours (Telegram: /schedule)"
        echo "  ./manage.sh cleanup    # Manual cleanup"
        echo "  ./manage.sh test       # Comprehensive test"
        echo ""
        echo "🔧 MAINTENANCE:"
        echo "  ./manage.sh debug      # Run in foreground"
        echo "  ./manage.sh update     # Update bot"
        echo "  ./manage.sh autostart  # Auto-start on reboot"
        echo "  ./manage.sh uninstall  # COMPLETE uninstall"
        echo ""
        echo "📱 TELEGRAM COMMANDS:"
        echo "  /start      - Welcome menu"
        echo "  /help       - Detailed help"
        echo "  /status     - Bot status (admin)"
        echo "  /pause [h]  - Pause bot X hours (admin)"
        echo "  /resume     - Resume bot (admin)"
        echo "  /schedule   - Set working hours (admin)"
        echo "  /clean      - Clean temp files (admin)"
        echo "  /stats      - Statistics (admin)"
        echo "  /download   - Download URL"
        echo ""
        echo "🎯 ALL FEATURES:"
        echo "  • YouTube/Instagram/Twitter/TikTok/Facebook"
        echo "  • Direct file downloads"
        echo "  • Auto cleanup (2 minutes)"
        echo "  • Pause/Resume functionality"
        echo "  • Schedule working hours"
        echo "  • Easy uninstall"
        echo "  • Admin controls"
        ;;
esac
EOF

chmod +x manage.sh

# Step 8: Create requirements.txt
print_blue "8. Creating requirements.txt..."
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
EOF

print_green "✅ ULTIMATE BOT INSTALLATION COMPLETE!"
echo ""
echo "🌟 ALL FEATURES READY:"
echo "======================"
echo "✅ Download from ALL platforms (YouTube, Instagram, Twitter, TikTok, Facebook)"
echo "✅ Download ANY direct file link"
echo "✅ Auto cleanup (files deleted after 2 minutes)"
echo "✅ Pause/Resume bot functionality"
echo "✅ Schedule working hours"
echo "✅ Easy uninstall with ./manage.sh uninstall"
echo "✅ Admin controls and monitoring"
echo ""
echo "📋 IMMEDIATE SETUP REQUIRED:"
echo "============================"
echo "1. Configure your bot:"
echo "   cd $INSTALL_DIR"
echo "   nano config.json"
echo "   • Replace YOUR_BOT_TOKEN_HERE with your token"
echo "   • Add your Telegram ID to admin_ids (get from @userinfobot)"
echo ""
echo "2. Start the bot:"
echo "   ./manage.sh start"
echo ""
echo "3. Test everything:"
echo "   ./manage.sh test"
echo "   ./manage.sh status"
echo ""
echo "4. Set auto-start (optional but recommended):"
echo "   ./manage.sh autostart"
echo ""
echo "📱 IN TELEGRAM:"
echo "==============="
echo "1. Find your bot"
echo "2. Send /start"
echo "3. Send any video link or direct file URL"
echo "4. Use /help for all commands"
echo ""
echo "🔧 TROUBLESHOOTING:"
echo "=================="
echo "• Check logs: ./manage.sh logs"
echo "• Debug mode: ./manage.sh debug"
echo "• Test download: Send a YouTube link"
echo ""
echo "🗑️ TO UNINSTALL:"
echo "================"
echo "   ./manage.sh uninstall"
echo ""
print_green "🎉 Your Ultimate Bot is ready! Enjoy all features!"
