#!/bin/bash
# install_fixed.sh - Install fixed version of Telegram download bot
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/install_fixed.sh)

set -e

echo "🚀 Installing Fixed Telegram Download Bot"
echo "========================================="

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Step 1: Install dependencies
print_info "1. Installing system dependencies..."
apt-get update -y
apt-get upgrade -y
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano

# Step 2: Create directory
INSTALL_DIR="/opt/telegram-bot-fixed"
print_info "2. Creating directory: $INSTALL_DIR..."
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

# Step 5: Download fixed bot code
print_info "5. Downloading fixed bot code..."
curl -s -o bot.py https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/bot_fixed.py

# Step 6: Create config file
print_info "6. Creating config file..."
cat > config.json << 'EOF'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "download_dir": "downloads",
    "keep_files_days": 7
}
EOF

# Step 7: Create management script
print_info "7. Creating management script..."
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Bot management

cd "$(dirname "$0")"

case "$1" in
    start)
        echo "🚀 Starting bot..."
        source venv/bin/activate
        nohup python bot.py > bot.log 2>&1 &
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
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        echo "📊 Bot status:"
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ Bot running (PID: $(cat bot.pid))"
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
        else:
            print(f'❌ Error: {data.get(\"description\", \"Unknown\")}')
    else:
        print(f'❌ HTTP Error: {r.status_code}')
except Exception as e:
    print(f'❌ Error: {e}')
        "
        ;;
    debug)
        echo "🐛 Debug mode..."
        $0 stop
        source venv/bin/activate
        python bot.py
        ;;
    update)
        echo "🔄 Updating bot..."
        $0 stop
        curl -s -o bot.py https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/bot_fixed.py
        source venv/bin/activate
        pip install --upgrade python-telegram-bot yt-dlp requests
        echo "✅ Update complete"
        $0 start
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
        echo "  ./manage.sh debug      # Debug mode"
        echo "  ./manage.sh update     # Update bot"
        echo ""
        echo "🎯 Fixed version - No event loop issues"
        ;;
esac
EOF

chmod +x manage.sh

# Step 8: Create requirements file
print_info "8. Creating requirements file..."
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
EOF

print_status "✅ Installation complete!"
echo ""
echo "📋 Next steps:"
echo "1. Configure bot token:"
echo "   cd $INSTALL_DIR"
echo "   nano config.json"
echo ""
echo "2. Start the bot:"
echo "   ./manage.sh start"
echo ""
echo "3. Test connection:"
echo "   ./manage.sh test"
echo ""
echo "📱 In Telegram:"
echo "   - Find your bot"
echo "   - Send /start"
echo "   - Send video link"
echo ""
echo "🔗 One-line install for others:"
echo "   bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/install_fixed.sh)"
