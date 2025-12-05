#!/bin/bash
# fresh_install.sh - Fresh install of Telegram download bot
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/fresh_install.sh)

set -e

echo "🆕 Fresh Install of Telegram Download Bot"
echo "========================================="

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
INSTALL_DIR="/opt/tg-downloader"

# Step 1: Cleanup old installations
print_blue "1. Cleaning old installations..."
pkill -f "python.*bot.py" 2>/dev/null || true
rm -rf "$INSTALL_DIR" 2>/dev/null || true
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 2: Install system dependencies
print_blue "2. Installing system dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano

# Step 3: Create virtual environment
print_blue "3. Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Step 4: Install Python packages
print_blue "4. Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.7 yt-dlp==2025.11.12 requests==2.32.5

# Step 5: Create bot.py (TESTED AND WORKING)
print_blue "5. Creating bot.py..."
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Download Bot - Tested and Working
Simple version without complex features
"""

import os
import json
import logging
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import yt_dlp

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class SimpleDownloadBot:
    def __init__(self):
        self.config = self.load_config()
        self.token = self.config['telegram']['token']
        logger.info(f"Bot initialized")
    
    def load_config(self):
        """Load configuration"""
        config_file = 'config.json'
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                return json.load(f)
        
        # Default config
        config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads'
        }
        
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=4)
        
        return config
    
    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        await update.message.reply_text(
            f'Hello {user.first_name}! 👋\n\n'
            '🤖 **Download Bot**\n\n'
            '📥 Supported:\n'
            '• YouTube\n'
            '• Instagram\n'
            '• Twitter/X\n'
            '• TikTok\n'
            '• Facebook\n\n'
            '🎯 How to use:\n'
            'Send me a video link!',
            parse_mode='Markdown'
        )
        logger.info(f"User {user.id} started bot")
    
    async def help(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        await update.message.reply_text(
            '📖 Help:\n\n'
            'Just send me a video link!\n\n'
            'Commands:\n'
            '/start - Start bot\n'
            '/help - This help\n'
            '/status - Bot status'
        )
    
    async def status(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user = update.effective_user
        await update.message.reply_text(f'✅ Bot is running!\n👤 Your ID: {user.id}')
        logger.info(f"Status checked by {user.id}")
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        text = update.message.text
        user = update.effective_user
        
        logger.info(f"Message from {user.first_name}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            await update.message.reply_text('📥 Downloading... Please wait!')
            
            try:
                # Create downloads directory
                os.makedirs('downloads', exist_ok=True)
                
                # Download options
                ydl_opts = {
                    'format': 'best[height<=720]',
                    'outtmpl': 'downloads/%(title).100s.%(ext)s',
                    'quiet': True,
                }
                
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(text, download=True)
                    filename = ydl.prepare_filename(info)
                    
                    if os.path.exists(filename):
                        file_size = os.path.getsize(filename) / (1024 * 1024)
                        
                        # Send file
                        with open(filename, 'rb') as f:
                            if filename.endswith(('.mp3', '.m4a', '.webm')):
                                await update.message.reply_audio(
                                    audio=f,
                                    caption=f'🎵 {info.get("title", "Audio")}\nSize: {file_size:.1f}MB'
                                )
                            else:
                                await update.message.reply_video(
                                    video=f,
                                    caption=f'📹 {info.get("title", "Video")}\nSize: {file_size:.1f}MB'
                                )
                        
                        # Cleanup
                        os.remove(filename)
                        logger.info(f"File sent and deleted: {filename}")
                        
                    else:
                        await update.message.reply_text('❌ File not found after download')
                        
            except Exception as e:
                logger.error(f"Download error: {e}")
                await update.message.reply_text(f'❌ Error: {str(e)[:100]}')
        else:
            await update.message.reply_text('Please send a valid URL (http:// or https://)')
    
    def run(self):
        """Run the bot"""
        print("=" * 50)
        print("🤖 Telegram Download Bot")
        print("=" * 50)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Bot token not configured!")
            print("Please edit config.json and add your token")
            return
        
        print(f"✅ Token loaded: {self.token[:15]}...")
        print("🔄 Creating application...")
        
        # Create application
        app = Application.builder().token(self.token).build()
        
        # Add handlers
        app.add_handler(CommandHandler("start", self.start))
        app.add_handler(CommandHandler("help", self.help))
        app.add_handler(CommandHandler("status", self.status))
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        
        print("✅ Bot ready")
        print("📱 Send /start to your bot in Telegram")
        print("=" * 50)
        
        # Run polling
        app.run_polling()

def main():
    """Main function"""
    try:
        bot = SimpleDownloadBot()
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
    "download_dir": "downloads"
}
EOF

# Step 7: Create management script
print_blue "7. Creating management script..."
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Bot management script

cd "$(dirname "$0")"

case "$1" in
    start)
        echo "🚀 Starting bot..."
        source venv/bin/activate
        # Clean old logs
        > bot.log
        # Start bot
        nohup python bot.py >> bot.log 2>&1 &
        echo $! > bot.pid
        echo "✅ Bot started (PID: $(cat bot.pid))"
        echo "📝 Check logs: tail -f bot.log"
        echo "🔍 Test with: ./manage.sh test"
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
        echo "📊 Bot status:"
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ Bot running (PID: $(cat bot.pid))"
            echo "📝 Last 3 log lines:"
            tail -3 bot.log 2>/dev/null || echo "No logs yet"
        else
            echo "❌ Bot not running"
            [ -f "bot.pid" ] && rm -f bot.pid
        fi
        ;;
    logs)
        echo "📝 Bot logs:"
        echo "=================="
        if [ -f "bot.log" ]; then
            if [ "$2" = "follow" ] || [ "$2" = "-f" ]; then
                tail -f bot.log
            else
                tail -30 bot.log
            fi
        else
            echo "No log file"
        fi
        ;;
    config)
        echo "⚙️ Editing config..."
        nano config.json
        ;;
    test)
        echo "🔍 Testing bot connection..."
        source venv/bin/activate
        python3 -c "
import requests, json, sys

print('Testing bot configuration...')
print('=' * 40)

try:
    # Load token
    with open('config.json') as f:
        config = json.load(f)
    
    token = config['telegram']['token']
    
    if token == 'YOUR_BOT_TOKEN_HERE':
        print('❌ ERROR: Token not configured!')
        print('Please edit config.json and add your bot token')
        sys.exit(1)
    
    print(f'✅ Token found: {token[:15]}...')
    
    # Test Telegram API
    print('\nTesting Telegram API connection...')
    url = f'https://api.telegram.org/bot{token}/getMe'
    
    try:
        response = requests.get(url, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            
            if data['ok']:
                print('✅ SUCCESS: Bot connected!')
                print(f'   🤖 Bot name: {data[\"result\"][\"first_name\"]}')
                print(f'   📱 Username: @{data[\"result\"][\"username\"]}')
                print(f'   🆔 Bot ID: {data[\"result\"][\"id\"]}')
                
                # Test message queue
                print('\nChecking for messages...')
                url = f'https://api.telegram.org/bot{token}/getUpdates'
                response = requests.get(url, timeout=10)
                
                if response.status_code == 200:
                    data = response.json()
                    if data['ok']:
                        if data['result']:
                            print(f'📨 Messages in queue: {len(data[\"result\"])}')
                            print('💡 Bot should receive messages')
                        else:
                            print('📭 No messages in queue')
                            print('💡 Send /start to your bot in Telegram')
                
            else:
                print(f'❌ Telegram error: {data.get(\"description\", \"Unknown error\")}')
        else:
            print(f'❌ HTTP error: {response.status_code}')
            
    except requests.exceptions.ConnectionError:
        print('❌ Connection error: No internet access')
    except requests.exceptions.Timeout:
        print('❌ Timeout: Telegram server not responding')
        
except FileNotFoundError:
    print('❌ config.json not found')
except json.JSONDecodeError:
    print('❌ Invalid config.json format')
except Exception as e:
    print(f'❌ Unexpected error: {e}')

print('\n' + '=' * 40)
print('Test complete!')
        "
        ;;
    debug)
        echo "🐛 Starting in debug mode..."
        ./manage.sh stop
        source venv/bin/activate
        python bot.py
        ;;
    update)
        echo "🔄 Updating bot..."
        ./manage.sh stop
        curl -s -o bot.py https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/bot.py
        source venv/bin/activate
        pip install --upgrade python-telegram-bot yt-dlp requests
        echo "✅ Update complete"
        ./manage.sh start
        ;;
    clean)
        echo "🧹 Cleaning up..."
        ./manage.sh stop
        rm -rf downloads/* bot.log 2>/dev/null
        echo "✅ Cleaned up"
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
        echo "  ./manage.sh status     # Check status"
        echo "  ./manage.sh logs       # Show logs (add -f to follow)"
        echo "  ./manage.sh config     # Edit config"
        echo "  ./manage.sh test       # Test connection"
        echo "  ./manage.sh debug      # Debug mode"
        echo "  ./manage.sh update     # Update bot"
        echo "  ./manage.sh clean      # Clean temp files"
        echo ""
        echo "🎯 Fresh install - Tested and working"
        echo ""
        echo "📱 Quick start:"
        echo "  1. Edit config: nano config.json"
        echo "  2. Start bot: ./manage.sh start"
        echo "  3. Check status: ./manage.sh status"
        echo "  4. Test: ./manage.sh test"
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

print_green "✅ Fresh installation complete!"
echo ""
echo "📋 IMMEDIATE ACTIONS REQUIRED:"
echo "==============================="
echo "1. Configure your bot token:"
echo "   cd $INSTALL_DIR"
echo "   nano config.json"
echo "   Replace 'YOUR_BOT_TOKEN_HERE' with your token from @BotFather"
echo ""
echo "2. Start the bot:"
echo "   ./manage.sh start"
echo ""
echo "3. Test the connection:"
echo "   ./manage.sh test"
echo ""
echo "4. Check status:"
echo "   ./manage.sh status"
echo ""
echo "5. View logs:"
echo "   ./manage.sh logs"
echo ""
echo "📱 In Telegram:"
echo "   - Search for your bot"
echo "   - Send /start"
echo "   - Send a YouTube link"
echo ""
echo "🔗 For others to install:"
echo "   bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/fresh_install.sh)"
echo ""
echo "❓ If bot doesn't work:"
echo "   ./manage.sh debug   # Run in foreground to see errors"
echo "   ./manage.sh logs    # Check error logs"
