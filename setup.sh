#!/bin/bash
# setup.sh - نصب و مدیریت ربات تلگرام با یک دستور
# https://github.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook

set -e

echo "🤖 ربات تلگرام دانلود از شبکه‌های اجتماعی"
echo "========================================"

# متغیرها
REPO_URL="https://github.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook"
INSTALL_DIR="$HOME/khodam-bot"
SCRIPT_URL="https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/setup.sh"

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    echo "استفاده:"
    echo "  bash <(curl -s $SCRIPT_URL) install    # نصب ربات"
    echo "  bash <(curl -s $SCRIPT_URL) update     # بروزرسانی"
    echo "  bash <(curl -s $SCRIPT_URL) remove     # حذف ربات"
    echo "  bash <(curl -s $SCRIPT_URL) help       # نمایش راهنما"
    echo ""
    echo "📌 دستور نصب سریع:"
    echo "  bash <(curl -s $SCRIPT_URL) install"
}

install_bot() {
    echo -e "${GREEN}[1/5]${NC} بروزرسانی سیستم..."
    sudo apt update -y
    sudo apt upgrade -y
    
    echo -e "${GREEN}[2/5]${NC} نصب پیش‌نیازها..."
    sudo apt install -y python3 python3-pip python3-venv git wget curl ffmpeg
    
    echo -e "${GREEN}[3/5]${NC} دریافت کدها..."
    if [ -d "$INSTALL_DIR" ]; then
        echo "⚠️  پوشه قبلاً وجود دارد. حذف و دانلود مجدد..."
        rm -rf "$INSTALL_DIR"
    fi
    
    # روش ساده: دانلود مستقیم فایل‌های ضروری
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # دانلود bot.py
    echo "📥 دانلود bot.py..."
    curl -s -o bot.py https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/bot.py
    
    # دانلود requirements.txt
    echo "📥 دانلود requirements.txt..."
    curl -s -o requirements.txt https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/requirements.txt
    
    # ایجاد فایل config.json
    echo "⚙️  ایجاد تنظیمات..."
    cat > config.json << 'EOF'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "schedule": {
        "enabled": false,
        "start_time": "08:00",
        "end_time": "23:00",
        "days": [0, 1, 2, 3, 4, 5, 6]
    },
    "download_dir": "downloads",
    "keep_files_days": 7
}
EOF
    
    echo -e "${GREEN}[4/5]${NC} ایجاد محیط مجازی..."
    python3 -m venv venv
    source venv/bin/activate
    
    echo "📦 نصب کتابخانه‌ها..."
    pip install --upgrade pip
    pip install -r requirements.txt
    
    echo -e "${GREEN}[5/5]${NC} ایجاد اسکریپت‌های مدیریت..."
    
    # فایل start.sh
    cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python bot.py
EOF
    chmod +x start.sh
    
    # فایل start-background.sh
    cat > start-background.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
nohup ./start.sh > bot.log 2>&1 &
echo $! > bot.pid
echo "✅ ربات شروع شد (PID: $(cat bot.pid))"
echo "📝 لاگ‌ها: tail -f bot.log"
EOF
    chmod +x start-background.sh
    
    # فایل stop.sh
    cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    kill $(cat bot.pid) 2>/dev/null
    rm -f bot.pid
    echo "🛑 ربات متوقف شد"
else
    echo "⚠️  ربات در حال اجرا نیست"
fi
EOF
    chmod +x stop.sh
    
    # فایل status.sh
    cat > status.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ] && kill -0 $(cat bot.pid) 2>/dev/null; then
    echo "✅ ربات در حال اجراست (PID: $(cat bot.pid))"
    echo "📊 لاگ آخرین خطوط:"
    tail -5 bot.log
else
    echo "❌ ربات در حال اجرا نیست"
    [ -f "bot.pid" ] && rm -f bot.pid
fi
EOF
    chmod +x status.sh
    
    # فایل restart.sh
    cat > restart.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./stop.sh
sleep 2
./start-background.sh
EOF
    chmod +x restart.sh
    
    # فایل pause.sh
    cat > pause.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -STOP $PID 2>/dev/null; then
        echo "⏸ ربات موقتاً متوقف شد"
        echo "برای ادامه: kill -CONT $PID"
        
        # اگر ساعت مشخص شده
        if [ -n "$1" ]; then
            echo "⏰ ربات بعد از $1 ساعت ادامه می‌یابد..."
            (sleep ${1}h && kill -CONT $PID) &
        fi
    else
        echo "❌ خطا در توقف ربات"
    fi
else
    echo "⚠️  ربات در حال اجرا نیست"
fi
EOF
    chmod +x pause.sh
    
    # فایل resume.sh
    cat > resume.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill -CONT $PID 2>/dev/null; then
        echo "▶ ربات ادامه یافت"
    else
        echo "❌ خطا در ادامه ربات"
    fi
else
    echo "⚠️  ربات در حال اجرا نیست"
fi
EOF
    chmod +x resume.sh
    
    # فایل schedule.sh
    cat > schedule.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

if [ "$1" = "on" ]; then
    START=${2:-"08:00"}
    END=${3:-"23:00"}
    echo "⏰ تنظیم زمان‌بندی: $START تا $END"
    python3 -c "
import json
with open('config.json', 'r') as f:
    config = json.load(f)
config['schedule']['enabled'] = True
config['schedule']['start_time'] = '$START'
config['schedule']['end_time'] = '$END'
with open('config.json', 'w') as f:
    json.dump(config, f, indent=4)
"
    echo "✅ زمان‌بندی فعال شد"
    
elif [ "$1" = "off" ]; then
    echo "⏰ غیرفعال کردن زمان‌بندی..."
    python3 -c "
import json
with open('config.json', 'r') as f:
    config = json.load(f)
config['schedule']['enabled'] = False
with open('config.json', 'w') as f:
    json.dump(config, f, indent=4)
"
    echo "✅ زمان‌بندی غیرفعال شد"
    
else
    echo "استفاده:"
    echo "  ./schedule.sh on [start_time] [end_time]"
    echo "  ./schedule.sh off"
    echo ""
    echo "مثال:"
    echo "  ./schedule.sh on 09:00 18:00"
    echo "  ./schedule.sh off"
fi
EOF
    chmod +x schedule.sh
    
    # فایل logs.sh
    cat > logs.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.log" ]; then
    echo "📝 لاگ‌های ربات:"
    echo "=================="
    tail -50 bot.log
else
    echo "فایل لاگ موجود نیست"
fi
EOF
    chmod +x logs.sh
    
    # فایل config-edit.sh
    cat > config-edit.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if command -v nano &> /dev/null; then
    nano config.json
elif command -v vim &> /dev/null; then
    vim config.json
else
    echo "محتویات config.json:"
    echo "===================="
    cat config.json
    echo ""
    echo "برای ویرایش: nano config.json"
fi
EOF
    chmod +x config-edit.sh
    
    echo ""
    echo -e "${GREEN}✅ نصب کامل شد!${NC}"
    echo ""
    echo "📁 پوشه نصب: $INSTALL_DIR"
    echo ""
    echo "📝 مراحل بعدی:"
    echo "1. تنظیم توکن ربات:"
    echo "   cd $INSTALL_DIR && nano config.json"
    echo ""
    echo "2. شروع ربات:"
    echo "   cd $INSTALL_DIR && ./start-background.sh"
    echo ""
    echo "3. دستورات مدیریت:"
    echo "   ./status.sh    # وضعیت ربات"
    echo "   ./stop.sh      # توقف ربات"
    echo "   ./pause.sh 3   # توقف 3 ساعته"
    echo "   ./restart.sh   # راه‌اندازی مجدد"
    echo "   ./logs.sh      # نمایش لاگ‌ها"
    echo ""
    echo "💡 نکته: برای مدیریت آسان، این دستورها را به خاطر بسپارید!"
}

update_bot() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "❌ ربات نصب نیست. ابتدا نصب کنید:"
        echo "bash <(curl -s $SCRIPT_URL) install"
        exit 1
    fi
    
    echo "🔄 بروزرسانی ربات..."
    cd "$INSTALL_DIR"
    
    # توقف ربات اگر در حال اجراست
    if [ -f "stop.sh" ]; then
        ./stop.sh
    fi
    
    # دانلود فایل‌های جدید
    echo "📥 دریافت نسخه جدید..."
    curl -s -o bot.py.new https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/bot.py
    curl -s -o requirements.txt.new https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/requirements.txt
    
    # بکاپ از فایل‌های قدیمی
    if [ -f "bot.py" ]; then
        cp bot.py bot.py.backup
    fi
    if [ -f "requirements.txt" ]; then
        cp requirements.txt requirements.txt.backup
    fi
    
    # جایگزینی فایل‌ها
    mv bot.py.new bot.py
    mv requirements.txt.new requirements.txt
    
    # بروزرسانی کتابخانه‌ها
    source venv/bin/activate
    pip install -r requirements.txt --upgrade
    
    echo "✅ بروزرسانی کامل شد"
    echo ""
    echo "برای شروع مجدد:"
    echo "cd $INSTALL_DIR && ./restart.sh"
}

remove_bot() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "❌ ربات نصب نیست"
        exit 1
    fi
    
    echo "🗑️  حذف ربات..."
    cd "$INSTALL_DIR"
    
    # توقف ربات
    if [ -f "stop.sh" ]; then
        ./stop.sh
    fi
    
    # تأیید حذف
    read -p "آیا مطمئنید می‌خواهید ربات را حذف کنید؟ (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd ~
        rm -rf "$INSTALL_DIR"
        echo "✅ ربات حذف شد"
    else
        echo "❌ حذف لغو شد"
    fi
}

# پردازش آرگومان
case "$1" in
    install)
        install_bot
        ;;
    update)
        update_bot
        ;;
    remove|uninstall)
        remove_bot
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -z "$1" ]; then
            show_help
        else
            echo "❌ دستور نامعتبر: $1"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac
