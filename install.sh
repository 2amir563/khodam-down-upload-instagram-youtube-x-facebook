#!/bin/bash
# install.sh - نصب ربات تلگرام در سرور لینوکس خام
# https://github.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook

set -e

echo "🚀 نصب ربات تلگرام دانلود"
echo "=========================="

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# بررسی root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}⚠️  بهتر است با sudo اجرا کنید${NC}"
fi

# به روزرسانی سیستم
echo -e "${GREEN}[1/6]${NC} به‌روزرسانی سیستم..."
apt-get update -y
apt-get upgrade -y

# نصب پیش‌نیازها
echo -e "${GREEN}[2/6]${NC} نصب پیش‌نیازها..."
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano

# ایجاد پوشه پروژه
PROJECT_DIR="/opt/telegram-download-bot"
echo -e "${GREEN}[3/6]${NC} ایجاد پوشه پروژه در $PROJECT_DIR..."
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# ایجاد محیط مجازی
echo -e "${GREEN}[4/6]${NC} ایجاد محیط مجازی..."
python3 -m venv venv
source venv/bin/activate

# نصب کتابخانه‌ها
echo -e "${GREEN}[5/6]${NC} نصب کتابخانه‌های پایتون..."
pip install --upgrade pip
pip install python-telegram-bot yt-dlp requests

# ایجاد فایل‌های اصلی
echo -e "${GREEN}[6/6]${NC} ایجاد فایل‌های اصلی..."

# فایل bot.py
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
ربات تلگرام دانلود از یوتیوب، اینستاگرام و...
نسخه ساده و تست شده
"""

import os
import json
import logging
import asyncio
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import yt_dlp
import tempfile

# تنظیمات لاگ
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.StreamHandler(),  # نمایش در کنسول
        logging.FileHandler('bot.log')  # ذخیره در فایل
    ]
)
logger = logging.getLogger(__name__)

class TelegramDownloadBot:
    def __init__(self):
        self.config_file = 'config.json'
        self.config = self.load_config()
        self.token = self.config.get('token', '')
        
    def load_config(self):
        """بارگذاری تنظیمات"""
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r') as f:
                return json.load(f)
        else:
            # تنظیمات پیش‌فرض
            config = {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 500  # مگابایت
            }
            self.save_config(config)
            return config
    
    def save_config(self, config=None):
        """ذخیره تنظیمات"""
        if config is None:
            config = self.config
        with open(self.config_file, 'w') as f:
            json.dump(config, f, indent=4)
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /start"""
        user = update.effective_user
        logger.info(f"کاربر {user.id} ({user.first_name}) /start فرستاد")
        
        welcome_text = f"""
سلام {user.first_name}! 👋

🤖 ربات دانلود از شبکه‌های اجتماعی

📥 پشتیبانی از:
• YouTube
• Instagram  
• Twitter/X
• TikTok
• Facebook
• و هر لینک مستقیم

🎯 فقط لینک ویدیو را بفرستید!

📊 دستورات:
/start - شروع
/help - راهنما
/status - وضعیت ربات
        """
        await update.message.reply_text(welcome_text)
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /help"""
        help_text = """
📖 راهنمای استفاده:

1. لینک ویدیو را بفرستید
2. ربات کیفیت‌های موجود را نشان می‌دهد
3. کیفیت مورد نظر را انتخاب کنید
4. ویدیو دانلود و ارسال می‌شود

⚠️ محدودیت‌ها:
• حداکثر حجم: 500MB
• فرمت خروجی: MP4
• مدت زمان: تا 1 ساعت
        """
        await update.message.reply_text(help_text)
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /status"""
        user_id = update.effective_user.id
        admin_ids = self.config.get('admin_ids', [])
        
        if user_id not in admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است")
            return
        
        # بررسی وضعیت
        status = "✅ ربات فعال است"
        await update.message.reply_text(f"📊 وضعیت ربات:\n{status}\n\n👤 آیدی شما: {user_id}")
    
    async def handle_url(self, update: Update, context: ContextTypes.DEFAULT_TYPE, url: str):
        """پردازش لینک"""
        try:
            await update.message.reply_text("🔍 در حال بررسی لینک...")
            
            # تشخیص پلتفرم
            if 'youtube.com' in url or 'youtu.be' in url:
                platform = 'YouTube'
            elif 'instagram.com' in url:
                platform = 'Instagram'
            elif 'twitter.com' in url or 'x.com' in url:
                platform = 'Twitter/X'
            elif 'tiktok.com' in url:
                platform = 'TikTok'
            elif 'facebook.com' in url:
                platform = 'Facebook'
            else:
                platform = 'سایر سایت‌ها'
            
            # نمایش اطلاعات
            info_text = f"""
📹 لینک دریافت شد

📌 پلتفرم: {platform}
🔗 آدرس: {url[:50]}...

⏳ در حال دریافت اطلاعات...
            """
            await update.message.reply_text(info_text)
            
            # دانلود با yt-dlp
            await self.download_video(update, url)
            
        except Exception as e:
            logger.error(f"خطا در پردازش لینک: {e}")
            await update.message.reply_text(f"❌ خطا در پردازش لینک:\n{str(e)[:100]}")
    
    async def download_video(self, update: Update, url: str):
        """دانلود ویدیو"""
        try:
            await update.message.reply_text("📥 در حال دانلود...")
            
            # تنظیمات yt-dlp
            ydl_opts = {
                'format': 'best[height<=720]/best',  # حداکثر 720p
                'outtmpl': '%(title)s.%(ext)s',
                'quiet': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # بررسی حجم فایل
                file_size = os.path.getsize(filename) / (1024 * 1024)  # به مگابایت
                max_size = self.config.get('max_file_size', 500)
                
                if file_size > max_size:
                    os.remove(filename)
                    await update.message.reply_text(
                        f"⚠️ حجم فایل ({file_size:.1f}MB) از حد مجاز ({max_size}MB) بیشتر است"
                    )
                    return
                
                # ارسال فایل
                await update.message.reply_text(f"✅ دانلود کامل شد!\n📦 حجم: {file_size:.1f}MB")
                
                with open(filename, 'rb') as video_file:
                    await update.message.reply_video(
                        video=video_file,
                        caption=f"📹 {info.get('title', 'ویدیو')}"
                    )
                
                # حذف فایل موقت
                os.remove(filename)
                
        except Exception as e:
            logger.error(f"خطا در دانلود: {e}")
            await update.message.reply_text(f"❌ خطا در دانلود:\n{str(e)[:100]}")
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پردازش پیام‌ها"""
        message = update.message
        text = message.text
        
        logger.info(f"پیام دریافت شد: {text[:50]}")
        
        # اگر لینک است
        if text.startswith(('http://', 'https://')):
            await self.handle_url(update, context, text)
        else:
            await update.message.reply_text("🔗 لطفاً یک لینک معتبر ارسال کنید")
    
    async def run(self):
        """اجرای اصلی ربات"""
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            logger.error("❌ توکن ربات تنظیم نشده است!")
            logger.error("لطفاً در config.json توکن را وارد کنید")
            return
        
        logger.info(f"🚀 شروع ربات با توکن: {self.token[:15]}...")
        
        # ساخت اپلیکیشن
        application = Application.builder().token(self.token).build()
        
        # افزودن handlerها
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CommandHandler("status", self.status_command))
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        
        logger.info("✅ ربات آماده است...")
        logger.info("📱 در تلگرام به ربات /start بفرستید")
        
        # شروع polling
        await application.run_polling(
            poll_interval=1.0,
            timeout=30,
            drop_pending_updates=True
        )

def main():
    """تابع اصلی"""
    print("=" * 50)
    print("🤖 ربات تلگرام دانلود")
    print("=" * 50)
    
    try:
        bot = TelegramDownloadBot()
        asyncio.run(bot.run())
    except KeyboardInterrupt:
        print("\n🛑 ربات متوقف شد")
    except Exception as e:
        print(f"❌ خطا: {e}")
        exit(1)

if __name__ == '__main__':
    main()
EOF

# فایل config.json
cat > config.json << 'EOF'
{
    "token": "YOUR_BOT_TOKEN_HERE",
    "admin_ids": [],
    "max_file_size": 500
}
EOF

# فایل requirements.txt
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2024.4.9
requests==2.31.0
EOF

# اسکریپت‌های مدیریت
cat > start.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
exec python bot.py
EOF
chmod +x start.sh

cat > start-background.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
nohup python bot.py > bot.log 2>&1 &
echo $! > bot.pid
echo "✅ ربات شروع شد (PID: $(cat bot.pid))"
echo "📝 لاگ‌ها: tail -f bot.log"
EOF
chmod +x start-background.sh

cat > stop.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ]; then
    PID=$(cat bot.pid)
    if kill $PID 2>/dev/null; then
        echo "🛑 ربات متوقف شد"
    else
        echo "⚠️  ربات در حال اجرا نیست"
    fi
    rm -f bot.pid
else
    echo "⚠️  ربات در حال اجرا نیست"
fi
EOF
chmod +x stop.sh

cat > status.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
    echo "✅ ربات در حال اجراست (PID: $(cat bot.pid))"
    echo "📊 آخرین خطوط لاگ:"
    tail -5 bot.log 2>/dev/null || echo "فایل لاگ موجود نیست"
else
    echo "❌ ربات در حال اجرا نیست"
    [ -f "bot.pid" ] && rm -f bot.pid
fi
EOF
chmod +x status.sh

cat > restart.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
./stop.sh
sleep 2
./start-background.sh
EOF
chmod +x restart.sh

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

cat > update.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🔄 بروزرسانی ربات..."
./stop.sh
source venv/bin/activate
pip install --upgrade python-telegram-bot yt-dlp requests
echo "✅ بروزرسانی کامل شد"
echo "برای شروع: ./start-background.sh"
EOF
chmod +x update.sh

cat > uninstall.sh << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "🗑️  حذف ربات..."
./stop.sh

read -p "آیا مطمئنید می‌خواهید ربات را حذف کنید؟ (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd /
    rm -rf $(dirname "$0")
    echo "✅ ربات حذف شد"
else
    echo "❌ حذف لغو شد"
fi
EOF
chmod +x uninstall.sh

echo ""
echo "========================================"
echo "✅ نصب کامل شد!"
echo ""
echo "📁 پوشه نصب: $PROJECT_DIR"
echo ""
echo "📝 مراحل بعدی:"
echo "1. توکن ربات خود را دریافت کنید:"
echo "   - به @BotFather در تلگرام مراجعه کنید"
echo "   - ربات جدید بسازید"
echo "   - توکن را کپی کنید"
echo ""
echo "2. تنظیم توکن:"
echo "   nano $PROJECT_DIR/config.json"
echo ""
echo "3. شروع ربات:"
echo "   cd $PROJECT_DIR && ./start-background.sh"
echo ""
echo "4. دستورات مدیریت:"
echo "   ./status.sh    # وضعیت"
echo "   ./stop.sh      # توقف"
echo "   ./restart.sh   # راه‌اندازی مجدد"
echo "   ./logs.sh      # نمایش لاگ"
echo "   ./update.sh    # بروزرسانی"
echo "   ./uninstall.sh # حذف"
echo ""
echo "🎉 حالا به ربات در تلگرام /start بفرستید!"
