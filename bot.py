cd /opt/telegram-download-bot

# توقف ربات
./stop.sh

# ایجاد فایل bot.py جدید
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
ربات تلگرام دانلود از یوتیوب، اینستاگرام و...
نسخه اصلاح شده - بدون مشکل event loop
"""

import os
import json
import logging
import asyncio
import sys
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ContextTypes
import yt_dlp

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
        logger.info(f"ربات با توکن {self.token[:15]}... مقداردهی شد")
    
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
        temp_file = None
        try:
            await update.message.reply_text("📥 در حال دانلود...")
            
            # تنظیمات yt-dlp
            ydl_opts = {
                'format': 'best[height<=720]/best',  # حداکثر 720p
                'outtmpl': '%(title).50s.%(ext)s',
                'quiet': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                temp_file = filename
                
                # بررسی حجم فایل
                file_size = os.path.getsize(filename) / (1024 * 1024)  # به مگابایت
                max_size = self.config.get('max_file_size', 500)
                
                if file_size > max_size:
                    await update.message.reply_text(
                        f"⚠️ حجم فایل ({file_size:.1f}MB) از حد مجاز ({max_size}MB) بیشتر است"
                    )
                    return
                
                # ارسال فایل
                await update.message.reply_text(f"✅ دانلود کامل شد!\n📦 حجم: {file_size:.1f}MB")
                
                with open(filename, 'rb') as video_file:
                    await update.message.reply_video(
                        video=video_file,
                        caption=f"📹 {info.get('title', 'ویدیو')[:100]}"
                    )
                
        except Exception as e:
            logger.error(f"خطا در دانلود: {e}")
            await update.message.reply_text(f"❌ خطا در دانلود:\n{str(e)[:100]}")
        finally:
            # حذف فایل موقت
            if temp_file and os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                except:
                    pass
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پردازش پیام‌ها"""
        message = update.message
        text = message.text
        
        logger.info(f"پیام دریافت شد از {message.from_user.first_name}: {text[:50]}")
        
        # اگر لینک است
        if text.startswith(('http://', 'https://')):
            await self.handle_url(update, context, text)
        else:
            await update.message.reply_text("🔗 لطفاً یک لینک معتبر ارسال کنید")

def main():
    """تابع اصلی - نسخه اصلاح شده"""
    print("=" * 50)
    print("🤖 ربات تلگرام دانلود - نسخه اصلاح شده")
    print("=" * 50)
    
    try:
        # ایجاد نمونه ربات
        bot = TelegramDownloadBot()
        
        # بررسی توکن
        if not bot.token or bot.token == 'YOUR_BOT_TOKEN_HERE':
            logger.error("❌ توکن ربات تنظیم نشده است!")
            logger.error("لطفاً در config.json توکن را وارد کنید")
            print("❌ توکن ربات تنظیم نشده است!")
            print("لطفاً در config.json توکن را وارد کنید")
            return
        
        logger.info(f"🚀 شروع ربات با توکن: {bot.token[:15]}...")
        print(f"✅ توکن خوانده شد: {bot.token[:15]}...")
        print("🔄 ساخت اپلیکیشن...")
        
        # ساخت اپلیکیشن
        application = Application.builder().token(bot.token).build()
        
        # افزودن handlerها
        application.add_handler(CommandHandler("start", bot.start_command))
        application.add_handler(CommandHandler("help", bot.help_command))
        application.add_handler(CommandHandler("status", bot.status_command))
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, bot.handle_message))
        
        logger.info("✅ ربات آماده است...")
        logger.info("📱 در تلگرام به ربات /start بفرستید")
        print("✅ ربات آماده است")
        print("📱 در تلگرام به ربات /start بفرستید")
        print("=" * 50)
        
        # شروع polling - روش جدید بدون asyncio.run()
        application.run_polling(
            poll_interval=1.0,
            timeout=30,
            drop_pending_updates=True,
            close_loop=False  # مهم!
        )
        
    except KeyboardInterrupt:
        print("\n🛑 ربات متوقف شد")
        logger.info("ربات توسط کاربر متوقف شد")
    except Exception as e:
        print(f"❌ خطا: {e}")
        logger.error(f"خطای غیرمنتظره: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
EOF

# حالا ربات را شروع کنید
./start-background.sh

# بررسی لاگ
tail -f bot.log
