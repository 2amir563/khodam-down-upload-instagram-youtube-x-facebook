#!/bin/bash
# auto-install.sh - نصب کامل ربات با یک دستور
# اجرا: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/auto-install.sh)

set -e

echo "🚀 نصب خودکار ربات تلگرام دانلود"
echo "================================="

# رنگ‌ها
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# اطلاعات سرور
SERVER_IP=$(curl -s ifconfig.me)
INSTALL_DIR="/opt/telegram-downloader"
SCRIPT_URL="https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/auto-install.sh"

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# مرحله 1: بررسی و نصب پیش‌نیازها
print_info "1. بررسی و نصب پیش‌نیازهای سیستم..."
apt-get update -y
apt-get upgrade -y
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano cron

# مرحله 2: ایجاد پوشه پروژه
print_info "2. ایجاد پوشه پروژه..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# مرحله 3: ایجاد محیط مجازی
print_info "3. ایجاد محیط مجازی پایتون..."
python3 -m venv venv
source venv/bin/activate

# مرحله 4: نصب کتابخانه‌ها
print_info "4. نصب کتابخانه‌های پایتون..."
pip install --upgrade pip
pip install python-telegram-bot==20.7 yt-dlp==2025.11.12 requests==2.32.5

# مرحله 5: ایجاد فایل‌های اصلی
print_info "5. ایجاد فایل‌های اصلی..."

# فایل bot.py با قابلیت پاکسازی خودکار
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
ربات تلگرام دانلود با پاکسازی خودکار فایل‌ها
فایل‌ها بعد از 2 دقیقه به طور خودکار پاک می‌شوند
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
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    filters,
    ContextTypes
)
import yt_dlp
import tempfile

# تنظیمات لاگ
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class AutoCleanDownloadBot:
    def __init__(self, config_path='config.json'):
        self.config = self.load_config(config_path)
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        self.cleanup_interval = self.config.get('cleanup_interval', 120)  # 2 دقیقه پیش‌فرض
        
        # ایجاد پوشه‌ها
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # لیست فایل‌های دانلود شده با زمان ایجاد
        self.downloaded_files = {}
        
        # شروع پاکسازی خودکار
        self.start_auto_cleanup()
        
        logger.info(f"🤖 ربات با پاکسازی خودکار ({self.cleanup_interval} ثانیه) راه‌اندازی شد")
    
    def load_config(self, config_path):
        """بارگذاری تنظیمات"""
        default_config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'cleanup_interval': 120,  # 2 دقیقه
            'keep_files_days': 7
        }
        
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                # ادغام با پیش‌فرض
                for key in default_config:
                    if key not in config:
                        config[key] = default_config[key]
                return config
        
        # ذخیره پیش‌فرض
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(default_config, f, indent=4, ensure_ascii=False)
        
        return default_config
    
    def start_auto_cleanup(self):
        """شروع پاکسازی خودکار در thread جداگانه"""
        def cleanup_worker():
            while True:
                try:
                    self.cleanup_old_files()
                    time.sleep(self.cleanup_interval)  # هر X ثانیه چک کن
                except Exception as e:
                    logger.error(f"خطا در پاکسازی خودکار: {e}")
                    time.sleep(60)
        
        # شروع thread پاکسازی
        cleanup_thread = threading.Thread(target=cleanup_worker, daemon=True)
        cleanup_thread.start()
        logger.info(f"✅ پاکسازی خودکار هر {self.cleanup_interval} ثانیه فعال شد")
    
    def cleanup_old_files(self):
        """پاکسازی فایل‌های قدیمی"""
        try:
            now = time.time()
            files_deleted = 0
            
            for file_path in self.download_dir.glob('*'):
                if file_path.is_file():
                    # اگر فایل بیشتر از 2 دقیقه عمر کرده
                    file_age = now - file_path.stat().st_mtime
                    if file_age > self.cleanup_interval:
                        try:
                            file_path.unlink()
                            files_deleted += 1
                            logger.debug(f"پاکسازی: {file_path.name} (عمر: {file_age:.0f} ثانیه)")
                        except Exception as e:
                            logger.error(f"خطا در پاکسازی {file_path}: {e}")
            
            if files_deleted > 0:
                logger.info(f"🧹 {files_deleted} فایل قدیمی پاکسازی شد")
                
        except Exception as e:
            logger.error(f"خطا در پاکسازی: {e}")
    
    def detect_platform(self, url):
        """تشخیص پلتفرم"""
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
    
    async def get_video_info(self, url):
        """دریافت اطلاعات ویدیو"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                if info:
                    title = info.get('title', 'بدون عنوان')[:100]
                    duration = info.get('duration', 0)
                    
                    # تخمین حجم
                    formats = []
                    if 'formats' in info:
                        for fmt in info['formats']:
                            if fmt.get('filesize'):
                                size_mb = fmt['filesize'] / (1024 * 1024)
                                if size_mb < self.config['telegram']['max_file_size']:
                                    formats.append({
                                        'format_id': fmt.get('format_id', ''),
                                        'resolution': fmt.get('resolution', ''),
                                        'filesize_mb': round(size_mb, 1)
                                    })
                    
                    return {
                        'title': title,
                        'duration': duration,
                        'formats': formats,
                        'platform': self.detect_platform(url)
                    }
        except Exception as e:
            logger.error(f"خطا در دریافت اطلاعات: {e}")
            return None
    
    def create_quality_keyboard(self, platform, formats):
        """ایجاد کیبورد کیفیت"""
        keyboard = []
        
        # گزینه‌های پیش‌فرض برای یوتیوب
        if platform == 'youtube' and formats:
            # گروه‌بندی فرمت‌ها
            video_formats = [f for f in formats if 'video' in f.get('format_id', '') or 'mp4' in f.get('format_id', '')]
            audio_formats = [f for f in formats if 'audio' in f.get('format_id', '') or 'm4a' in f.get('format_id', '')]
            
            # اضافه کردن ویدیو
            for fmt in video_formats[:3]:  # حداکثر 3 گزینه
                if fmt.get('resolution'):
                    keyboard.append([
                        InlineKeyboardButton(
                            f"📹 {fmt['resolution']} (~{fmt['filesize_mb']}MB)",
                            callback_data=f"format_{fmt['format_id']}"
                        )
                    ])
            
            # اضافه کردن صدا
            if audio_formats:
                for fmt in audio_formats[:1]:
                    keyboard.append([
                        InlineKeyboardButton(
                            f"🎵 MP3 (~{fmt['filesize_mb']}MB)",
                            callback_data=f"format_{fmt['format_id']}"
                        )
                    ])
        else:
            # گزینه‌های عمومی
            keyboard.append([
                InlineKeyboardButton("📹 بهترین کیفیت", callback_data="format_best")
            ])
            keyboard.append([
                InlineKeyboardButton("📹 کیفیت متوسط", callback_data="format_worst")
            ])
        
        keyboard.append([InlineKeyboardButton("❌ لغو", callback_data="cancel")])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def download_video(self, url, format_id):
        """دانلود ویدیو"""
        temp_file = None
        try:
            ydl_opts = {
                'format': format_id,
                'outtmpl': str(self.download_dir / '%(title).50s.%(ext)s'),
                'quiet': False,
                'progress_hooks': [self.progress_hook],
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                temp_file = filename
                
                # ثبت زمان ایجاد فایل
                self.downloaded_files[filename] = time.time()
                
                # بررسی حجم
                file_size = os.path.getsize(filename) / (1024 * 1024)
                max_size = self.config['telegram']['max_file_size']
                
                if file_size > max_size:
                    logger.warning(f"حجم زیاد: {file_size:.1f}MB > {max_size}MB")
                    return None, None, "حجم فایل زیاد است"
                
                return filename, info, None
                
        except Exception as e:
            logger.error(f"خطا در دانلود: {e}")
            return None, None, str(e)
    
    def progress_hook(self, d):
        """نمایش پیشرفت"""
        if d['status'] == 'downloading':
            percent = d.get('_percent_str', '0%').strip()
            speed = d.get('_speed_str', 'N/A')
            logger.info(f"دانلود: {percent} با سرعت {speed}")
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /start"""
        user = update.effective_user
        welcome_text = f"""
سلام {user.first_name}! 👋

🤖 **ربات دانلود با پاکسازی خودکار**

📥 **پشتیبانی از:**
• YouTube • Instagram • Twitter/X
• TikTok • Facebook • لینک مستقیم

⚡ **ویژگی‌های ویژه:**
✅ پاکسازی خودکار فایل‌ها بعد از ۲ دقیقه
✅ انتخاب کیفیت دلخواه
✅ مدیریت آسان

🎯 **نحوه استفاده:**
1. لینک ویدیو را بفرستید
2. کیفیت مورد نظر را انتخاب کنید
3. ویدیو دانلود و ارسال می‌شود
4. فایل در سرور بعد از ۲ دقیقه پاک می‌شود

⚠️ **محدودیت:**
• حداکثر حجم: {self.config['telegram']['max_file_size']}MB
• فایل‌ها بعد از ۲ دقیقه به طور خودکار پاک می‌شوند

📊 **دستورات:**
/start - شروع
/help - راهنما
/status - وضعیت
/clean - پاکسازی دستی
        """
        await update.message.reply_text(welcome_text, parse_mode='Markdown')
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /help"""
        help_text = """
📖 **راهنمای کامل:**

🔗 **ارسال لینک:**
- لینک ویدیو را از هر شبکه اجتماعی بفرستید
- ربات به طور خودکار پلتفرم را تشخیص می‌دهد

🎛️ **انتخاب کیفیت:**
- ربات کیفیت‌های موجود را نمایش می‌دهد
- کیفیت مورد نظر را انتخاب کنید

📥 **دریافت ویدیو:**
- ویدیو دانلود و برای شما ارسال می‌شود
- فایل در سرور ذخیره می‌شود

🧹 **پاکسازی خودکار:**
- فایل‌ها بعد از ۲ دقیقه به طور خودکار پاک می‌شوند
- برای پاکسازی سریع از /clean استفاده کنید

⚙️ **دستورات مدیریتی:**
/start - نمایش راهنما
/help - راهنمای کامل
/status - وضعیت ربات (ادمین)
/clean - پاکسازی دستی فایل‌ها
        """
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /status"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است!")
            return
        
        # شمارش فایل‌ها
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        status_text = f"""
📊 **وضعیت ربات:**

✅ ربات فعال
📁 پوشه دانلود: {self.download_dir}
📦 فایل‌های فعلی: {len(files)}
💾 حجم کل: {total_size:.1f}MB
⏰ پاکسازی هر: {self.cleanup_interval} ثانیه
👤 آیدی شما: {user_id}
🔄 آخرین پاکسازی: {time.ctime() if files else 'همین الان'}
        """
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پاکسازی دستی"""
        try:
            files_before = list(self.download_dir.glob('*'))
            files_count = len(files_before)
            
            for file_path in files_before:
                if file_path.is_file():
                    try:
                        file_path.unlink()
                    except:
                        pass
            
            files_after = list(self.download_dir.glob('*'))
            cleaned = files_count - len(files_after)
            
            await update.message.reply_text(
                f"🧹 پاکسازی انجام شد!\n"
                f"✅ {cleaned} فایل پاک شد\n"
                f"📁 باقی مانده: {len(files_after)} فایل"
            )
            
            logger.info(f"پاکسازی دستی: {cleaned} فایل پاک شد")
            
        except Exception as e:
            await update.message.reply_text(f"❌ خطا در پاکسازی: {e}")
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پردازش پیام‌ها"""
        message = update.message
        url = message.text
        
        if not url.startswith(('http://', 'https://')):
            await message.reply_text("⚠️ لطفاً یک لینک معتبر ارسال کنید.")
            return
        
        logger.info(f"لینک دریافت شد از {message.from_user.first_name}: {url[:50]}")
        
        # دریافت اطلاعات
        await message.reply_text("🔍 در حال بررسی لینک...")
        video_info = await self.get_video_info(url)
        
        if not video_info:
            await message.reply_text("❌ خطا در دریافت اطلاعات ویدیو.")
            return
        
        # نمایش اطلاعات
        title = video_info['title']
        platform = video_info['platform']
        duration = video_info['duration']
        
        minutes = duration // 60 if duration else 0
        seconds = duration % 60 if duration else 0
        
        info_text = f"""
📹 **{title}**

📌 پلتفرم: {platform.upper()}
⏱ مدت: {minutes}:{seconds:02d}
🎬 فرمت‌های موجود: {len(video_info['formats'])}
💡 فایل بعد از ۲ دقیقه به طور خودکار پاک می‌شود
        """
        
        await message.reply_text(info_text, parse_mode='Markdown')
        
        # نمایش کیفیت‌ها
        keyboard = self.create_quality_keyboard(platform, video_info['formats'])
        await message.reply_text(
            "✅ لطفاً کیفیت مورد نظر را انتخاب کنید:",
            reply_markup=keyboard
        )
        
        # ذخیره اطلاعات
        context.user_data['last_url'] = url
        context.user_data['last_formats'] = video_info['formats']
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پردازش callback"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ عملیات لغو شد.")
            return
        
        if data.startswith('format_'):
            format_id = data.replace('format_', '')
            
            await query.edit_message_text(f"⏳ در حال دانلود با فرمت {format_id}...")
            
            url = context.user_data.get('last_url')
            if not url:
                await query.edit_message_text("❌ لینک پیدا نشد!")
                return
            
            # دانلود
            filename, info, error = await self.download_video(url, format_id)
            
            if error:
                await query.edit_message_text(f"❌ خطا در دانلود:\n{error}")
                return
            
            if filename and os.path.exists(filename):
                file_size = os.path.getsize(filename) / (1024 * 1024)
                
                try:
                    # ارسال فایل
                    with open(filename, 'rb') as f:
                        if filename.endswith('.mp3') or filename.endswith('.m4a'):
                            await context.bot.send_audio(
                                chat_id=query.message.chat_id,
                                audio=f,
                                caption=f"🎵 {info.get('title', 'صدا')[:50]}\n"
                                        f"📦 حجم: {file_size:.1f}MB\n"
                                        f"⏰ پاکسازی: بعد از ۲ دقیقه"
                            )
                        else:
                            await context.bot.send_video(
                                chat_id=query.message.chat_id,
                                video=f,
                                caption=f"📹 {info.get('title', 'ویدیو')[:50]}\n"
                                        f"📦 حجم: {file_size:.1f}MB\n"
                                        f"⏰ پاکسازی: بعد از ۲ دقیقه"
                            )
                    
                    await query.edit_message_text("✅ دانلود کامل شد! فایل ارسال گردید.")
                    logger.info(f"فایل ارسال شد: {filename} ({file_size:.1f}MB)")
                    
                except Exception as e:
                    await query.edit_message_text(f"❌ خطا در ارسال فایل: {str(e)[:100]}")
                    logger.error(f"ارسال فایل خطا: {e}")
            else:
                await query.edit_message_text("❌ فایل دانلود شده پیدا نشد!")
    
    async def run(self):
        """اجرای اصلی"""
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            logger.error("❌ توکن تنظیم نشده!")
            print("❌ لطفاً توکن ربات را در config.json وارد کنید")
            return
        
        logger.info(f"🚀 شروع ربات با توکن: {self.token[:15]}...")
        print(f"🤖 ربات با پاکسازی خودکار شروع شد")
        print(f"⏰ فایل‌ها هر {self.cleanup_interval} ثانیه پاکسازی می‌شوند")
        
        # ساخت اپلیکیشن
        application = Application.builder().token(self.token).build()
        
        # افزودن handlerها
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CommandHandler("status", self.status_command))
        application.add_handler(CommandHandler("clean", self.clean_command))
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        application.add_handler(CallbackQueryHandler(self.handle_callback))
        
        logger.info("✅ ربات آماده است...")
        print("✅ ربات آماده است")
        print("📱 در تلگرام به ربات /start بفرستید")
        print("=" * 50)
        
        # شروع polling
        await application.run_polling(
            poll_interval=1.0,
            timeout=30,
            drop_pending_updates=True
        )

def main():
    """تابع اصلی"""
    print("=" * 50)
    print("🤖 ربات تلگرام با پاکسازی خودکار")
    print("=" * 50)
    
    try:
        bot = AutoCleanDownloadBot()
        
        import asyncio
        asyncio.run(bot.run())
        
    except KeyboardInterrupt:
        print("\n🛑 ربات متوقف شد")
    except Exception as e:
        print(f"❌ خطا: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
EOF

# فایل config.json
cat > config.json << 'EOF'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "download_dir": "downloads",
    "cleanup_interval": 120,
    "keep_files_days": 7
}
EOF

# فایل requirements.txt
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
schedule==1.2.1
EOF

# اسکریپت مدیریت
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - مدیریت کامل ربات
# استفاده: ./manage.sh [command]

cd "$(dirname "$0")"

case "$1" in
    start)
        echo "🚀 شروع ربات..."
        source venv/bin/activate
        nohup python bot.py > bot.log 2>&1 &
        echo $! > bot.pid
        echo "✅ ربات شروع شد (PID: $(cat bot.pid))"
        echo "📝 لاگ: tail -f bot.log"
        echo "🧹 پاکسازی خودکار: هر ۲ دقیقه"
        ;;
    stop)
        echo "🛑 توقف ربات..."
        if [ -f "bot.pid" ]; then
            kill $(cat bot.pid) 2>/dev/null
            rm -f bot.pid
            echo "✅ ربات متوقف شد"
        else
            echo "⚠️ ربات در حال اجرا نیست"
        fi
        ;;
    restart)
        echo "🔄 راه‌اندازی مجدد..."
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        echo "📊 وضعیت ربات:"
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ ربات در حال اجراست (PID: $(cat bot.pid))"
            echo "📁 فایل‌های موقت: $(ls -1 downloads/ 2>/dev/null | wc -l) عدد"
            echo "📝 آخرین خطوط لاگ:"
            tail -5 bot.log 2>/dev/null || echo "فایل لاگ موجود نیست"
        else
            echo "❌ ربات در حال اجرا نیست"
            [ -f "bot.pid" ] && rm -f bot.pid
        fi
        ;;
    logs)
        echo "📝 لاگ‌های ربات:"
        echo "=================="
        if [ -f "bot.log" ]; then
            tail -50 bot.log
        else
            echo "فایل لاگ موجود نیست"
        fi
        ;;
    config)
        echo "⚙️ ویرایش تنظیمات..."
        nano config.json
        echo "💡 پس از ویرایش: ./manage.sh restart"
        ;;
    test)
        echo "🔍 تست اتصال..."
        source venv/bin/activate
        python3 -c "
import requests, json
try:
    with open('config.json') as f:
        token = json.load(f)['telegram']['token']
    
    print(f'✅ توکن: {token[:15]}...')
    
    url = f'https://api.telegram.org/bot{token}/getMe'
    r = requests.get(url, timeout=10)
    
    if r.status_code == 200:
        data = r.json()
        if data['ok']:
            print(f'✅ اتصال موفق!')
            print(f'🤖 ربات: {data[\"result\"][\"first_name\"]}')
            print(f'📱 @{data[\"result\"][\"username\"]}')
        else:
            print(f'❌ خطا: {data.get(\"description\", \"Unknown\")}')
    else:
        print(f'❌ HTTP Error: {r.status_code}')
except Exception as e:
    print(f'❌ خطا: {e}')
        "
        ;;
    clean)
        echo "🧹 پاکسازی فایل‌های موقت..."
        rm -rf downloads/*
        echo "✅ تمام فایل‌های موقت پاک شدند"
        ;;
    update)
        echo "🔄 بروزرسانی..."
        $0 stop
        source venv/bin/activate
        pip install --upgrade python-telegram-bot yt-dlp requests schedule
        echo "✅ بروزرسانی کامل شد"
        $0 start
        ;;
    autostart)
        echo "⚙️ تنظیم راه‌اندازی خودکار..."
        CRON_JOB="@reboot cd $INSTALL_DIR && ./manage.sh start"
        (crontab -l 2>/dev/null | grep -v "manage.sh" ; echo "$CRON_JOB") | crontab -
        echo "✅ راه‌اندازی خودکار تنظیم شد"
        ;;
    uninstall)
        echo "🗑️ حذف ربات..."
        $0 stop
        read -p "آیا مطمئنید؟ (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
            crontab -l 2>/dev/null | grep -v "manage.sh" | crontab -
            echo "✅ ربات حذف شد"
        else
            echo "❌ حذف لغو شد"
        fi
        ;;
    *)
        echo "🤖 مدیریت ربات تلگرام با پاکسازی خودکار"
        echo "======================================"
        echo ""
        echo "📁 پوشه: $INSTALL_DIR"
        echo ""
        echo "📋 دستورات:"
        echo "  ./manage.sh start      # شروع ربات"
        echo "  ./manage.sh stop       # توقف ربات"
        echo "  ./manage.sh restart    # راه‌اندازی مجدد"
        echo "  ./manage.sh status     # وضعیت ربات"
        echo "  ./manage.sh logs       # نمایش لاگ‌ها"
        echo "  ./manage.sh config     # ویرایش تنظیمات"
        echo "  ./manage.sh test       # تست اتصال"
        echo "  ./manage.sh clean      # پاکسازی فایل‌ها"
        echo "  ./manage.sh update     # بروزرسانی"
        echo "  ./manage.sh autostart  # راه‌اندازی خودکار"
        echo "  ./manage.sh uninstall  # حذف کامل"
        echo ""
        echo "🎯 ویژگی: فایل‌ها بعد از ۲ دقیقه به طور خودکار پاک می‌شوند"
        ;;
esac
EOF

chmod +x manage.sh

# نصب schedule برای پاکسازی
source venv/bin/activate
pip install schedule==1.2.1

# مرحله 6: تنظیمات اولیه
print_info "6. تنظیمات اولیه..."
echo ""
echo "🔧 لطفاً توکن ربات خود را تنظیم کنید:"
echo "   nano $INSTALL_DIR/config.json"
echo ""
echo "توکن را از @BotFather دریافت و جایگزین YOUR_BOT_TOKEN_HERE کنید"

# مرحله 7: راه‌اندازی
print_info "7. راه‌اندازی اولیه..."
./manage.sh start

sleep 3

# مرحله 8: نمایش اطلاعات
print_info "8. بررسی نصب..."
./manage.sh status

echo ""
echo "========================================"
print_status "✅ نصب کامل شد!"
echo ""
echo "📋 اطلاعات نصب:"
echo "   📁 پوشه: $INSTALL_DIR"
echo "   🤖 ربات: Telegram Download Bot"
echo "   🧹 پاکسازی: هر ۲ دقیقه"
echo "   ⚡ مدیریت: ./manage.sh"
echo ""
echo "🎯 دستورات سریع:"
echo "   cd $INSTALL_DIR"
echo "   ./manage.sh status    # وضعیت"
echo "   ./manage.sh logs      # لاگ‌ها"
echo "   ./manage.sh config    # ویرایش تنظیمات"
echo ""
echo "🚀 برای راه‌اندازی خودکار بعد از ریستارت:"
echo "   ./manage.sh autostart"
echo ""
echo "📱 در تلگرام:"
echo "   1. به ربات مراجعه کنید"
echo "   2. /start بفرستید"
echo "   3. لینک ویدیو بفرستید"
echo ""
echo "🔗 سرور: $SERVER_IP"
echo "========================================"
