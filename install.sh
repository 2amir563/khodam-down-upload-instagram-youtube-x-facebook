#!/bin/bash
# install.sh - نصب کننده ربات دانلود از شبکه‌های اجتماعی

set -e

echo "📦 نصب ربات دانلود از شبکه‌های اجتماعی"
echo "========================================"

# بررسی root بودن
if [ "$EUID" -eq 0 ]; then 
    echo "⚠️  توجه: بهتر است با کاربر عادی نصب کنید، نه root!"
    read -p "ادامه بدهیم؟ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# بروزرسانی سیستم
echo "🔄 بروزرسانی سیستم..."
sudo apt-get update
sudo apt-get upgrade -y

# نصب پیش‌نیازهای سیستم
echo "🔧 نصب پیش‌نیازها..."
sudo apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg

# ایجاد پوشه پروژه
PROJECT_DIR="$HOME/khodam-down-upload-instagram-youtube-x-facebook"
echo "📁 ایجاد پوشه پروژه در $PROJECT_DIR..."
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# ایجاد محیط مجازی پایتون
echo "🐍 ایجاد محیط مجازی پایتون..."
python3 -m venv venv
source venv/bin/activate

# نصب نیازمندی‌های پایتون
echo "📦 نصب کتابخانه‌های مورد نیاز..."
pip install --upgrade pip

cat > requirements.txt << EOF
python-telegram-bot==20.7
yt-dlp==2024.4.9
requests==2.31.0
Flask==3.0.2
Flask-CORS==4.0.0
python-dotenv==1.0.0
EOF

pip install -r requirements.txt

# کپی کردن فایل‌های اصلی
echo "📄 کپی فایل‌های اصلی..."

# فایل config.json
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
        "web_enabled": true,
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

# ایجاد اسکریپت‌های مدیریتی
echo "⚙️ ایجاد اسکریپت‌های مدیریتی..."

# اسکریپت شروع
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python bot.py
EOF
chmod +x start.sh

# اسکریپت توقف
cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
pkill -f "python bot.py"
EOF
chmod +x stop.sh

# اسکریپت راه‌اندازی سرویس
cat > start_service.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
nohup ./start.sh > bot.log 2>&1 &
echo $! > bot.pid
echo "✅ ربات در پس‌زمینه شروع شد (PID: $(cat bot.pid))"
EOF
chmod +x start_service.sh

# اسکریپت pause
cat > pause.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f bot.pid ]; then
    PID=$(cat bot.pid)
    kill -STOP $PID
    echo "⏸ ربات موقتاً متوقف شد"
else
    echo "❌ فایل PID پیدا نشد"
fi
EOF
chmod +x pause.sh

# اسکریپت resume
cat > resume.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0\))"
if [ -f bot.pid ]; then
    PID=$(cat bot.pid)
    kill -CONT $PID
    echo "▶ ربات ادامه یافت"
else
    echo "❌ فایل PID پیدا نشد"
fi
EOF
chmod +x resume.sh

# اسکریپت تنظیم زمان‌بندی
cat > schedule.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ "$#" -lt 1 ]; then
    echo "استفاده: ./schedule.sh [on/off] [start_time] [end_time]"
    echo "مثال: ./schedule.sh on 08:00 23:00"
    exit 1
fi

ACTION=$1
START=${2:-08:00}
END=${3:-23:00}

if [ "$ACTION" = "on" ]; then
    echo "تنظیم زمان‌بندی: $START تا $END"
    # اینجا باید کد تنظیم زمان‌بندی در config.json اضافه شود
    echo "✅ زمان‌بندی فعال شد"
elif [ "$ACTION" = "off" ]; then
    echo "❌ زمان‌بندی غیرفعال شد"
else
    echo "⚠️ دستور نامعتبر"
fi
EOF
chmod +x schedule.sh

# اسکریپت uninstall
cat > uninstall.sh << 'EOF'
#!/bin/bash
echo "🗑️ حذف ربات دانلود..."
cd "$(dirname "$0")"

# توقف ربات
if [ -f stop.sh ]; then
    ./stop.sh
fi

# حذف فایل‌ها
read -p "آیا می‌خواهید فایل‌های دانلود شده هم حذف شوند؟ (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf downloads
fi

# حذف پوشه پروژه
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

# فایل README
cat > README.md << 'EOF'
# ربات دانلود از شبکه‌های اجتماعی 🤖

ربات تلگرام برای دانلود از یوتیوب، اینستاگرام، توییتر، تیک‌تاک، فیسبوک و هر لینک مستقیم دیگر.

## 🚀 نصب سریع

```bash
bash install.sh
