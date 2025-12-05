#!/bin/bash
# manager.sh - مدیریت کامل ربات با یک دستور
# آدرس گیت‌هاب: https://github.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_NAME="khodam-down-upload-instagram-youtube-x-facebook"
PROJECT_DIR="$HOME/$PROJECT_NAME"
GITHUB_REPO="https://github.com/2amir563/$PROJECT_NAME.git"

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

check_dependencies() {
    print_info "بررسی پیش‌نیازها..."
    
    # بررسی پایتون
    if ! command -v python3 &> /dev/null; then
        print_error "پایتون 3 نصب نیست. در حال نصب..."
        sudo apt-get update
        sudo apt-get install -y python3 python3-pip python3-venv
    fi
    
    # بررسی git
    if ! command -v git &> /dev/null; then
        print_error "Git نصب نیست. در حال نصب..."
        sudo apt-get install -y git
    fi
    
    # بررسی ffmpeg
    if ! command -v ffmpeg &> /dev/null; then
        print_warning "FFmpeg نصب نیست. در حال نصب..."
        sudo apt-get install -y ffmpeg
    fi
}

install_bot() {
    print_info "📦 نصب ربات دانلود از شبکه‌های اجتماعی"
    echo "========================================"
    
    # بررسی نصب بودن
    if [ -d "$PROJECT_DIR" ]; then
        print_warning "ربات قبلاً نصب شده است!"
        read -p "آیا می‌خواهید دوباره نصب کنید؟ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
        rm -rf "$PROJECT_DIR"
    fi
    
    # بروزرسانی سیستم
    print_status "بروزرسانی سیستم..."
    sudo apt-get update
    sudo apt-get upgrade -y
    
    # نصب پیش‌نیازها
    check_dependencies
    
    # کلون کردن ریپو
    print_status "دریافت کدها از گیت‌هاب..."
    git clone "$GITHUB_REPO" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # ایجاد محیط مجازی
    print_status "ایجاد محیط مجازی پایتون..."
    python3 -m venv venv
    source venv/bin/activate
    
    # نصب نیازمندی‌ها
    print_status "نصب کتابخانه‌های مورد نیاز..."
    pip install --upgrade pip
    
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    else
        # ایجاد requirements.txt اگر وجود ندارد
        cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2024.4.9
requests==2.31.0
EOF
        pip install -r requirements.txt
    fi
    
    # ایجاد فایل config اگر وجود ندارد
    if [ ! -f "config.json" ]; then
        print_status "ایجاد فایل تنظیمات..."
        cat > config.json << 'EOF'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "server": {
        "port": 3152,
        "web_password": "admin123",
        "web_enabled": false,
        "host": "0.0.0.0"
    },
    "schedule": {
        "enabled": false,
        "start_time": "08:00",
        "end_time": "23:00",
        "days": [0, 1, 2, 3, 4, 5, 6]
    },
    "download_dir": "downloads",
    "keep_files_days": 7,
    "temp_pause_hours": 0
}
EOF
    fi
    
    # ایجاد فایل‌های مدیریتی
    create_management_files
    
    print_status "نصب کامل شد!"
    
    # نمایش راهنما
    echo ""
    echo "========================================"
    echo "🎉 ربات با موفقیت نصب شد!"
    echo ""
    echo "📝 مراحل بعدی:"
    echo "1. توکن ربات تلگرام خود را در فایل زیر قرار دهید:"
    echo "   nano $PROJECT_DIR/config.json"
    echo ""
    echo "2. ربات را شروع کنید:"
    echo "   ./manager.sh start"
    echo ""
    echo "3. برای مدیریت ربات:"
    echo "   ./manager.sh help"
}

create_management_files() {
    print_status "ایجاد فایل‌های مدیریتی..."
    
    # فایل start.sh
    cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python bot.py
EOF
    chmod +x start.sh
    
    # فایل start-service.sh
    cat > start-service.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
nohup ./start.sh > bot.log 2>&1 &
echo $! > bot.pid
echo "✅ ربات در پس‌زمینه شروع شد (PID: $(cat bot.pid))"
EOF
    chmod +x start-service.sh
    
    # فایل stop.sh
    cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    kill $PID 2>/dev/null
    rm -f bot.pid
    echo "🛑 ربات متوقف شد"
else
    echo "⚠️ ربات در حال اجرا نیست"
fi
EOF
    chmod +x stop.sh
    
    # فایل pause.sh
    cat > pause.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    kill -STOP $PID
    echo "⏸ ربات موقتاً متوقف شد"
    echo "برای ادامه: kill -CONT $PID"
else
    echo "❌ ربات در حال اجرا نیست"
fi
EOF
    chmod +x pause.sh
    
    # فایل resume.sh
    cat > resume.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    kill -CONT $PID
    echo "▶ ربات ادامه یافت"
else
    echo "❌ ربات در حال اجرا نیست"
fi
EOF
    chmod +x resume.sh
    
    # فایل status.sh
    cat > status.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if ps -p $PID > /dev/null; then
        echo "✅ ربات در حال اجراست (PID: $PID)"
        echo "📊 لاگ‌ها:"
        tail -10 bot.log 2>/dev/null || echo "فایل لاگ موجود نیست"
    else
        echo "❌ ربات متوقف شده است"
        rm -f bot.pid
    fi
else
    echo "❌ ربات در حال اجرا نیست"
fi
EOF
    chmod +x status.sh
    
    # فایل logs.sh
    cat > logs.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.log" ]; then
    tail -50 bot.log
else
    echo "فایل لاگ موجود نیست"
fi
EOF
    chmod +x logs.sh
    
    # فایل update.sh
    cat > update.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🔄 بروزرسانی ربات..."
./stop.sh
git pull origin main
source venv/bin/activate
pip install -r requirements.txt --upgrade
./start-service.sh
echo "✅ بروزرسانی کامل شد"
EOF
    chmod +x update.sh
    
    # فایل uninstall.sh
    cat > uninstall.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🗑️ حذف ربات..."
./stop.sh

read -p "آیا می‌خواهید فایل‌های دانلود شده هم حذف شوند؟ (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf downloads
fi

cd ..
read -p "آیا می‌خواهید کل پوشه پروژه حذف شود؟ (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$(basename "$(pwd)")"
    echo "✅ تمام فایل‌ها حذف شدند"
else
    echo "⚠️ فقط ربات متوقف شد. فایل‌ها باقی ماندند."
fi
EOF
    chmod +x uninstall.sh
}

start_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست. ابتدا نصب کنید:"
        echo "  ./manager.sh install"
        exit 1
    }
    
    print_status "شروع ربات..."
    ./start-service.sh
}

stop_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    print_status "توقف ربات..."
    ./stop.sh
}

status_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    ./status.sh
}

pause_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    HOURS=${1:-1}
    print_status "توقف ربات به مدت $HOURS ساعت..."
    
    # اجرای pause.sh
    ./pause.sh
    
    # تنظیم تایمر برای resume خودکار
    nohup bash -c "sleep ${HOURS}h && cd '$PROJECT_DIR' && ./resume.sh" > /dev/null 2>&1 &
    
    print_status "ربات به مدت $HOURS ساعت متوقف خواهد شد و سپس خودکار ادامه می‌یابد"
}

resume_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    print_status "ادامه کار ربات..."
    ./resume.sh
}

logs_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    print_status "نمایش لاگ‌ها..."
    ./logs.sh
}

update_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    print_status "بروزرسانی ربات..."
    ./update.sh
}

uninstall_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    print_status "حذف ربات..."
    ./uninstall.sh
}

schedule_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    ACTION=$1
    START_TIME=$2
    END_TIME=$3
    
    if [ -z "$ACTION" ]; then
        print_error "لطفا عمل را مشخص کنید:"
        echo "  ./manager.sh schedule on [start_time] [end_time]"
        echo "  ./manager.sh schedule off"
        echo "مثال: ./manager.sh schedule on 08:00 23:00"
        exit 1
    fi
    
    if [ "$ACTION" = "on" ]; then
        START_TIME=${START_TIME:-"08:00"}
        END_TIME=${END_TIME:-"23:00"}
        
        print_status "تنظیم زمان‌بندی: $START_TIME تا $END_TIME"
        
        # به‌روزرسانی config.json
        python3 -c "
import json
with open('config.json', 'r') as f:
    config = json.load(f)
config['schedule']['enabled'] = True
config['schedule']['start_time'] = '$START_TIME'
config['schedule']['end_time'] = '$END_TIME'
with open('config.json', 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
"
        print_status "زمان‌بندی فعال شد: $START_TIME تا $END_TIME"
        
    elif [ "$ACTION" = "off" ]; then
        print_status "غیرفعال کردن زمان‌بندی..."
        
        python3 -c "
import json
with open('config.json', 'r') as f:
    config = json.load(f)
config['schedule']['enabled'] = False
with open('config.json', 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
"
        print_status "زمان‌بندی غیرفعال شد"
    else
        print_error "عمل نامعتبر: $ACTION"
        echo "استفاده:"
        echo "  ./manager.sh schedule on [start_time] [end_time]"
        echo "  ./manager.sh schedule off"
    fi
}

config_bot() {
    cd "$PROJECT_DIR" 2>/dev/null || {
        print_error "ربات نصب نیست"
        exit 1
    }
    
    print_status "ویرایش تنظیمات..."
    
    if command -v nano &> /dev/null; then
        nano config.json
    elif command -v vim &> /dev/null; then
        vim config.json
    elif command -v vi &> /dev/null; then
        vi config.json
    else
        echo "محتویات config.json:"
        cat config.json
        echo ""
        echo "برای ویرایش از ویرایشگر دلخواه استفاده کنید:"
        echo "  nano $PROJECT_DIR/config.json"
    fi
}

show_help() {
    echo "🤖 مدیریت ربات دانلود از شبکه‌های اجتماعی"
    echo "========================================"
    echo ""
    echo "دستورات:"
    echo ""
    echo "  ./manager.sh install     - نصب ربات"
    echo "  ./manager.sh start       - شروع ربات در پس‌زمینه"
    echo "  ./manager.sh stop        - توقف ربات"
    echo "  ./manager.sh status      - نمایش وضعیت ربات"
    echo "  ./manager.sh pause [N]   - توقف موقت برای N ساعت (پیش‌فرض: 1)"
    echo "  ./manager.sh resume      - ادامه کار ربات"
    echo "  ./manager.sh logs        - نمایش لاگ‌ها"
    echo "  ./manager.sh update      - بروزرسانی ربات"
    echo "  ./manager.sh config      - ویرایش تنظیمات"
    echo "  ./manager.sh schedule    - مدیریت زمان‌بندی"
    echo "  ./manager.sh uninstall   - حذف کامل ربات"
    echo "  ./manager.sh help        - نمایش این راهنما"
    echo ""
    echo "مثال‌ها:"
    echo "  ./manager.sh install"
    echo "  ./manager.sh start"
    echo "  ./manager.sh pause 3     # توقف 3 ساعته"
    echo "  ./manager.sh schedule on 09:00 18:00"
    echo "  ./manager.sh schedule off"
    echo ""
    echo "📞 پس از نصب، config.json را ویرایش کنید و توکن ربات را قرار دهید."
}

# بررسی آرگومان‌ها
case "$1" in
    install)
        install_bot
        ;;
    start)
        start_bot
        ;;
    stop)
        stop_bot
        ;;
    status)
        status_bot
        ;;
    pause)
        pause_bot "$2"
        ;;
    resume)
        resume_bot
        ;;
    logs)
        logs_bot
        ;;
    update)
        update_bot
        ;;
    config)
        config_bot
        ;;
    schedule)
        schedule_bot "$2" "$3" "$4"
        ;;
    uninstall)
        uninstall_bot
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -z "$1" ]; then
            show_help
        else
            print_error "دستور نامعتبر: $1"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac
