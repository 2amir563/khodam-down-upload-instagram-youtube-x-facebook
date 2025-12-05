#!/bin/bash
# final_install.sh - Final working Telegram download bot
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/final_install.sh)

set -e

echo "🚀 Final Working Telegram Download Bot Installer"
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
INSTALL_DIR="/opt/final-tg-bot"

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

# Step 4: Install ONLY required packages
print_blue "4. Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.7 yt-dlp==2025.11.12 requests==2.32.5

# Step 5: Create FINAL working bot.py
print_blue "5. Creating final bot.py..."
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
FINAL WORKING Telegram Download Bot
No external dependencies except telegram, yt-dlp, requests
"""

import os
import json
import logging
import asyncio
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from telegram import Update
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

class FinalDownloadBot:
    def __init__(self):
        self.config = self.load_config()
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        # Bot state
        self.is_paused = False
        self.paused_until = None
        
        # Create directories
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # Start auto cleanup
        self.start_auto_cleanup()
        
        logger.info("🤖 Final bot initialized")
        print(f"✅ Token: {self.token[:15]}...")
    
    def load_config(self):
        """Load configuration"""
        config_file = 'config.json'
        if os.path.exists(config_file):
            with open(config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        
        # Default config
        config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'auto_cleanup_minutes': 2
        }
        
        with open(config_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        
        return config
    
    def save_config(self):
        """Save configuration"""
        with open('config.json', 'w', encoding='utf-8') as f:
            json.dump(self.config, f, indent=4, ensure_ascii=False)
    
    def start_auto_cleanup(self):
        """Start auto cleanup thread"""
        def cleanup_worker():
            while True:
                try:
                    self.cleanup_old_files()
                    time.sleep(60)  # Check every minute
                except Exception as e:
                    logger.error(f"Cleanup error: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=cleanup_worker, daemon=True)
        thread.start()
        logger.info("🧹 Auto cleanup started")
    
    def cleanup_old_files(self):
        """Cleanup files older than 2 minutes"""
        cutoff_time = time.time() - (2 * 60)  # 2 minutes
        files_deleted = 0
        
        for file_path in self.download_dir.glob('*'):
            if file_path.is_file():
                file_age = time.time() - file_path.stat().st_mtime
                if file_age > (2 * 60):
                    try:
                        file_path.unlink()
                        files_deleted += 1
                    except Exception as e:
                        logger.error(f"Error deleting {file_path}: {e}")
        
        if files_deleted > 0:
            logger.info(f"Cleaned {files_deleted} old files")
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        # Check if paused
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\n"
                f"Will resume in: {hours}h {minutes}m"
            )
            return
        
        welcome = f"""
Hello {user.first_name}! 👋

🤖 **Telegram Download Bot**

📥 **Supported Platforms:**
✅ YouTube
✅ Instagram (Reels/Posts)
✅ Twitter/X
✅ TikTok  
✅ Facebook
✅ Direct file links

⚡ **Features:**
• Auto cleanup (files deleted after 2 min)
• Pause/Resume functionality
• All platforms support
• Simple and reliable

🛠️ **Commands:**
/start - This menu
/help - Detailed help
/status - Bot status (admin only)
/pause [hours] - Pause bot (admin)
/resume - Resume bot (admin)
/clean - Clean temp files (admin)

🎯 **How to use:**
Just send me a video link or direct file URL!

💡 **Note:** Files are auto deleted after 2 minutes
"""
        
        await update.message.reply_text(welcome, parse_mode='Markdown')
        logger.info(f"User {user.id} started bot")
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
📖 **Help Guide**

🔗 **Supported Links:**
• YouTube: https://youtube.com/watch?v=...
• Instagram: https://instagram.com/p/... or /reel/...
• Twitter/X: https://twitter.com/.../status/...
• TikTok: https://tiktok.com/@.../video/...
• Facebook: https://facebook.com/watch/?v=...
• Direct files: Any direct download link

⚙️ **Admin Commands** (for admins only):
/status - Bot status
/pause [hours] - Pause bot for X hours
/resume - Resume bot
/clean - Clean temp files

⏸️ **Pause Format:**
/pause [hours]
Example: /pause 3 (pauses for 3 hours)

🧹 **Auto Cleanup:**
Files are automatically deleted after 2 minutes

🔧 **Need help?**
Contact admin or check /status
"""
        
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user = update.effective_user
        
        # Check if admin
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        # Count files
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        status_text = f"""
📊 **Bot Status**

🤖 **Basic Info:**
• Status: {'⏸️ Paused' if self.is_paused else '✅ Active'}
• Paused until: {self.paused_until.strftime('%Y-%m-%d %H:%M') if self.paused_until else 'Not paused'}
• Uptime: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

⚙️ **Settings:**
• Max file size: {self.config['telegram']['max_file_size']}MB
• Auto cleanup: Every 2 minutes

📁 **Storage:**
• Temp files: {len(files)}
• Total size: {total_size:.1f}MB

👤 **User Info:**
• Your ID: {user.id}
• Your name: {user.first_name}
• Admin: {'✅ Yes' if user.id in self.admin_ids else '❌ No'}
"""
        
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
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
    
    async def resume_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Resume bot immediately"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        self.is_paused = False
        self.paused_until = None
        
        await update.message.reply_text("▶️ Bot resumed successfully!")
        logger.info(f"Bot resumed by {user.id}")
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
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
    
    def get_ydl_format(self, platform):
        """Get yt-dlp format based on platform"""
        formats = {
            'youtube': 'best[height<=720]/best',
            'instagram': 'best',
            'twitter': 'best',
            'tiktok': 'best',
            'facebook': 'best[height<=720]/best',
            'default': 'best'
        }
        return formats.get(platform, formats['default'])
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        # Check if paused
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\n"
                f"Will resume in: {hours}h {minutes}m\n"
                f"Use /resume to resume now (admin only)"
            )
            return
        
        text = update.message.text
        user = update.effective_user
        
        logger.info(f"Message from {user.first_name}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            await update.message.reply_text("🔍 Processing your link...")
            
            try:
                # Detect platform
                url_lower = text.lower()
                if 'youtube.com' in url_lower or 'youtu.be' in url_lower:
                    platform = 'youtube'
                elif 'instagram.com' in url_lower:
                    platform = 'instagram'
                elif 'twitter.com' in url_lower or 'x.com' in url_lower:
                    platform = 'twitter'
                elif 'tiktok.com' in url_lower:
                    platform = 'tiktok'
                elif 'facebook.com' in url_lower or 'fb.com' in url_lower:
                    platform = 'facebook'
                else:
                    platform = 'default'
                
                # Try yt-dlp first
                ydl_opts = {
                    'format': self.get_ydl_format(platform),
                    'quiet': True,
                    'no_warnings': True,
                    'outtmpl': str(self.download_dir / '%(title).100s.%(ext)s'),
                }
                
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(text, download=True)
                    filename = ydl.prepare_filename(info)
                    
                    if os.path.exists(filename):
                        file_size = os.path.getsize(filename) / (1024 * 1024)
                        max_size = self.config['telegram']['max_file_size']
                        
                        if file_size > max_size:
                            os.remove(filename)
                            await update.message.reply_text(
                                f"❌ File too large: {file_size:.1f}MB > {max_size}MB limit"
                            )
                            return
                        
                        # Send file
                        with open(filename, 'rb') as f:
                            if filename.endswith(('.mp3', '.m4a', '.wav', '.ogg')):
                                await update.message.reply_audio(
                                    audio=f,
                                    caption=f"🎵 {info.get('title', 'Audio')[:50]}\nSize: {file_size:.1f}MB"
                                )
                            else:
                                await update.message.reply_video(
                                    video=f,
                                    caption=f"📹 {info.get('title', 'Video')[:50]}\nSize: {file_size:.1f}MB"
                                )
                        
                        await update.message.reply_text("✅ Download complete!")
                        logger.info(f"Download successful: {filename}")
                        
                        # Schedule deletion after 2 minutes
                        def delete_later(file_path):
                            time.sleep(120)  # 2 minutes
                            if os.path.exists(file_path):
                                try:
                                    os.remove(file_path)
                                    logger.info(f"Auto deleted: {file_path}")
                                except:
                                    pass
                        
                        threading.Thread(target=delete_later, args=(filename,), daemon=True).start()
                        
                    else:
                        await update.message.reply_text("❌ File not found after download")
                        
            except yt_dlp.utils.DownloadError as e:
                # If yt-dlp fails, try direct download
                logger.warning(f"yt-dlp failed, trying direct download: {e}")
                await self.download_direct_file(update, text)
                
            except Exception as e:
                logger.error(f"Error: {e}")
                await update.message.reply_text(f"❌ Error: {str(e)[:100]}")
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
    
    async def download_direct_file(self, update: Update, url):
        """Download direct file link"""
        try:
            await update.message.reply_text("📥 Downloading direct file...")
            
            response = requests.get(url, stream=True, timeout=30)
            response.raise_for_status()
            
            # Get filename
            filename = os.path.basename(url.split('?')[0])
            if not filename or len(filename) < 3:
                filename = f"file_{int(time.time())}"
            
            filepath = self.download_dir / filename
            
            with open(filepath, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            
            file_size = os.path.getsize(filepath) / (1024 * 1024)
            max_size = self.config['telegram']['max_file_size']
            
            if file_size > max_size:
                os.remove(filepath)
                await update.message.reply_text(
                    f"❌ File too large: {file_size:.1f}MB > {max_size}MB limit"
                )
                return
            
            # Send file
            with open(filepath, 'rb') as f:
                if filename.endswith(('.mp3', '.m4a', '.wav', '.ogg', '.flac')):
                    await update.message.reply_audio(
                        audio=f,
                        caption=f"🎵 {filename}\nSize: {file_size:.1f}MB"
                    )
                elif filename.endswith(('.mp4', '.avi', '.mkv', '.mov', '.webm', '.flv')):
                    await update.message.reply_video(
                        video=f,
                        caption=f"📹 {filename}\nSize: {file_size:.1f}MB"
                    )
                elif filename.endswith(('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')):
                    await update.message.reply_photo(
                        photo=f,
                        caption=f"🖼️ {filename}\nSize: {file_size:.1f}MB"
                    )
                else:
                    await update.message.reply_document(
                        document=f,
                        caption=f"📄 {filename}\nSize: {file_size:.1f}MB"
                    )
            
            await update.message.reply_text("✅ Download complete!")
            
            # Schedule deletion
            def delete_later(file_path):
                time.sleep(120)
                if os.path.exists(file_path):
                    try:
                        os.remove(file_path)
                    except:
                        pass
            
            threading.Thread(target=delete_later, args=(filepath,), daemon=True).start()
            
        except Exception as e:
            logger.error(f"Direct download error: {e}")
            await update.message.reply_text(f"❌ Download error: {str(e)[:100]}")
    
    def run(self):
        """Run the bot"""
        print("=" * 50)
        print("🤖 FINAL Telegram Download Bot")
        print("=" * 50)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Bot token not configured!")
            print("Please edit config.json and add your bot token")
            print("Get token from @BotFather on Telegram")
            return
        
        print("✅ All checks passed")
        print("🔄 Creating application...")
        
        # Create application
        app = Application.builder().token(self.token).build()
        
        # Add handlers
        app.add_handler(CommandHandler("start", self.start_command))
        app.add_handler(CommandHandler("help", self.help_command))
        app.add_handler(CommandHandler("status", self.status_command))
        app.add_handler(CommandHandler("pause", self.pause_command))
        app.add_handler(CommandHandler("resume", self.resume_command))
        app.add_handler(CommandHandler("clean", self.clean_command))
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        
        print("✅ Bot ready and waiting for commands")
        print("📱 In Telegram, send /start to your bot")
        print("=" * 50)
        
        # Run polling
        app.run_polling()

def main():
    """Main function"""
    try:
        bot = FinalDownloadBot()
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
    "auto_cleanup_minutes": 2
}
EOF

# Step 7: Create final management script
print_blue "7. Creating management script..."
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Final bot management

cd "$(dirname "$0")"

case "$1" in
    start)
        echo "🚀 Starting Final Bot..."
        source venv/bin/activate
        
        # Clean old logs
        > bot.log
        
        # Start bot
        nohup python bot.py >> bot.log 2>&1 &
        echo $! > bot.pid
        
        echo "✅ Final Bot started (PID: $(cat bot.pid))"
        echo "📝 Logs: tail -f bot.log"
        echo "📊 Status: ./manage.sh status"
        echo ""
        echo "🌟 Features:"
        echo "   • All platforms supported"
        echo "   • Auto cleanup (2 minutes)"
        echo "   • Pause/Resume functionality"
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
        echo "📊 Bot Status:"
        echo "=============="
        
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ Bot running (PID: $(cat bot.pid))"
            
            # Show last logs
            echo ""
            echo "📝 Recent logs:"
            tail -5 bot.log 2>/dev/null || echo "No logs yet"
            
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
            if [ -n "$admins" ] && [ "$admins" != '"admin_ids": []' ]; then
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
        echo "🔍 Testing bot connection..."
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
        print('Please edit config.json and add your bot token')
        print('Get token from @BotFather on Telegram')
    else:
        print(f'✅ Token: {token[:15]}...')
        
    print(f'✅ Max file size: {config[\"telegram\"][\"max_file_size\"]}MB')
    
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
        print('Skipping Telegram test (token not set)')
    else:
        url = f'https://api.telegram.org/bot{token}/getMe'
        r = requests.get(url, timeout=10)
        
        if r.status_code == 200:
            data = r.json()
            if data['ok']:
                print('✅ Bot connected!')
                print(f'   Name: {data[\"result\"][\"first_name\"]}')
                print(f'   Username: @{data[\"result\"][\"username\"]}')
                print(f'   Bot ID: {data[\"result\"][\"id\"]}')
            else:
                print(f'❌ Telegram error: {data.get(\"description\")}')
        else:
            print(f'❌ HTTP error: {r.status_code}')
except Exception as e:
    print(f'❌ Error: {e}')
"
        ;;
    debug)
        echo "🐛 Debug mode..."
        ./manage.sh stop
        sleep 1
        source venv/bin/activate
        echo "Starting bot in foreground..."
        echo "Press Ctrl+C to stop"
        echo ""
        python bot.py
        ;;
    pause)
        echo "⏸️ Pause bot (via Telegram)"
        echo ""
        echo "In Telegram, send:"
        echo "   /pause [hours]"
        echo ""
        echo "Example:"
        echo "   /pause 3  # Pause for 3 hours"
        ;;
    clean)
        echo "🧹 Cleaning temp files..."
        rm -rf downloads/* 2>/dev/null
        echo "✅ Temporary files cleaned"
        ;;
    uninstall)
        echo "🗑️ UNINSTALL Final Bot"
        echo "===================="
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
            
            echo "✅ Bot completely uninstalled!"
            echo ""
            echo "To reinstall:"
            echo "bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/final_install.sh)"
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
        echo "🔄 Updating bot..."
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
        echo "🤖 FINAL TELEGRAM BOT MANAGEMENT"
        echo "================================"
        echo ""
        echo "📁 Directory: $INSTALL_DIR"
        echo ""
        echo "🚀 MAIN COMMANDS:"
        echo "  ./manage.sh start      # Start bot"
        echo "  ./manage.sh stop       # Stop bot"
        echo "  ./manage.sh restart    # Restart bot"
        echo "  ./manage.sh status     # Check status"
        echo "  ./manage.sh logs       # View logs"
        echo "  ./manage.sh config     # Edit config"
        echo "  ./manage.sh test       # Test everything"
        echo ""
        echo "⚙️ ADMIN FEATURES:"
        echo "  ./manage.sh pause      # Pause bot (via Telegram)"
        echo "  ./manage.sh clean      # Clean temp files"
        echo ""
        echo "🔧 MAINTENANCE:"
        echo "  ./manage.sh debug      # Debug mode"
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
        echo "  /clean      - Clean temp files (admin)"
        echo ""
        echo "🎯 FEATURES:"
        echo "  • YouTube/Instagram/Twitter/TikTok/Facebook"
        echo "  • Direct file downloads"
        echo "  • Auto cleanup (2 minutes)"
        echo "  • Pause/Resume functionality"
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

print_green "✅ FINAL INSTALLATION COMPLETE!"
echo ""
echo "📋 SETUP INSTRUCTIONS:"
echo "======================"
echo "1. Configure your bot:"
echo "   cd $INSTALL_DIR"
echo "   nano config.json"
echo "   • Replace YOUR_BOT_TOKEN_HERE with your bot token"
echo "   • Add your Telegram ID to admin_ids array"
echo ""
echo "2. Start the bot:"
echo "   ./manage.sh start"
echo ""
echo "3. Test everything:"
echo "   ./manage.sh test"
echo "   ./manage.sh status"
echo ""
echo "4. In Telegram:"
echo "   • Find your bot"
echo "   • Send /start"
echo "   • Send a YouTube link to test"
echo ""
echo "🔧 TROUBLESHOOTING:"
echo "=================="
echo "• Check logs: ./manage.sh logs"
echo "• Debug mode: ./manage.sh debug"
echo "• Reinstall if needed: ./manage.sh uninstall then run installer again"
echo ""
echo "🚀 One-line install for others:"
echo "bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/final_install.sh)"
echo ""
print_green "🎉 Your Final Bot is ready! No external dependencies issues!"
