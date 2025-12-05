#!/usr/bin/env python3
"""
ربات تلگرام دانلود از یوتیوب، اینستاگرام، توییتر، تیک‌تاک، فیسبوک
نسخه اصلاح شده و تست شده
"""

import os
import json
import logging
import tempfile
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

class DownloadBot:
    def __init__(self, config_path='config.json'):
        self.config = self.load_config(config_path)
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        # ایجاد پوشه دانلود
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # کیفیت‌های پیش‌فرض
        self.quality_options = {
            'youtube': [
                {'label': '📹 بهترین کیفیت (1080p)', 'format': 'bestvideo[height<=1080]+bestaudio/best[height<=1080]'},
                {'label': '📹 کیفیت خوب (720p)', 'format': 'bestvideo[height<=720]+bestaudio/best[height<=720]'},
                {'label': '📹 کیفیت متوسط (480p)', 'format': 'bestvideo[height<=480]+bestaudio/best[height<=480]'},
                {'label': '🎵 فقط صدا (MP3)', 'format': 'bestaudio/best'}
            ]
        }
    
    def load_config(self, config_path):
        """بارگذاری تنظیمات"""
        default_config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'keep_files_days': 7
        }
        
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        
        # ذخیره تنظیمات پیش‌فرض
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(default_config, f, indent=4, ensure_ascii=False)
        
        return default_config
    
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
                                        'ext': fmt.get('ext', ''),
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
    
    def create_quality_keyboard(self, platform):
        """ایجاد کیبورد کیفیت"""
        keyboard = []
        
        if platform in self.quality_options:
            for option in self.quality_options[platform]:
                keyboard.append([
                    InlineKeyboardButton(
                        option['label'],
                        callback_data=f"quality_{platform}_{option['format'].replace('+', '_').replace('[', '_').replace(']', '_')}"
                    )
                ])
        
        keyboard.append([InlineKeyboardButton("❌ لغو", callback_data="cancel")])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def download_video(self, url, format_spec):
        """دانلود ویدیو"""
        try:
            # ایجاد فایل موقت
            temp_file = tempfile.NamedTemporaryFile(
                suffix='.mp4',
                delete=False,
                dir=str(self.download_dir)
            )
            temp_path = temp_file.name
            temp_file.close()
            
            ydl_opts = {
                'format': format_spec,
                'outtmpl': temp_path.replace('.mp4', '.%(ext)s'),
                'quiet': False,
                'progress_hooks': [self.progress_hook],
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # تبدیل به mp4 اگر لازم باشد
                if not filename.endswith(('.mp4', '.mp3', '.m4a')):
                    import subprocess
                    new_filename = filename.rsplit('.', 1)[0] + '.mp4'
                    subprocess.run(['ffmpeg', '-i', filename, '-c', 'copy', new_filename], 
                                  capture_output=True)
                    filename = new_filename
                
                return filename, info
                
        except Exception as e:
            logger.error(f"خطا در دانلود: {e}")
            return None, None
    
    def progress_hook(self, d):
        """نمایش پیشرفت دانلود"""
        if d['status'] == 'downloading':
            percent = d.get('_percent_str', '0%').strip()
            logger.info(f"در حال دانلود: {percent}")
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /start"""
        user = update.effective_user
        welcome_text = f"""
سلام {user.first_name}! 👋

🤖 **ربات دانلود از شبکه‌های اجتماعی**

📥 **پشتیبانی از:**
• YouTube
• Instagram  
• Twitter/X
• TikTok
• Facebook
• و هر لینک مستقیم

🎯 **نحوه استفاده:**
1. لینک ویدیو را بفرستید
2. کیفیت مورد نظر را انتخاب کنید
3. ویدیو دانلود و ارسال می‌شود

⚙️ **دستورات:**
/start - نمایش این راهنما
/help - راهنمای کامل
/status - وضعیت ربات (فقط ادمین)

⚠️ **محدودیت:**
• حداکثر حجم: {self.config['telegram']['max_file_size']}MB
• فایل‌ها بعد از {self.config.get('keep_files_days', 7)} روز حذف می‌شوند
        """
        await update.message.reply_text(welcome_text, parse_mode='Markdown')
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /help"""
        help_text = """
📖 **راهنمای استفاده:**

1. **ارسال لینک:**
   - لینک ویدیو را از شبکه‌های اجتماعی بفرستید
   - ربات به طور خودکار پلتفرم را تشخیص می‌دهد

2. **انتخاب کیفیت:**
   - ربات کیفیت‌های موجود را نمایش می‌دهد
   - کیفیت مورد نظر را انتخاب کنید

3. **دریافت ویدیو:**
   - ویدیو دانلود و برای شما ارسال می‌شود
   - فایل موقت پس از ارسال حذف می‌شود

⚠️ **توجه:**
- برای برخی سایت‌ها ممکن است نیاز به VPN باشد
- دانلود ویدیو‌های طولانی ممکن است زمان‌بر باشد
- در صورت خطا، لینک را دوباره ارسال کنید
        """
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /status"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است!")
            return
        
        status_text = f"""
📊 **وضعیت ربات:**

• ✅ ربات فعال
• 📁 پوشه دانلود: {self.download_dir}
• 📦 فایل‌های ذخیره شده: {len(list(self.download_dir.glob('*')))}
• 👤 آیدی شما: {user_id}
• ⚙️ حداکثر حجم: {self.config['telegram']['max_file_size']}MB
        """
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پردازش پیام‌های دریافتی"""
        message = update.message
        url = message.text
        
        if not url.startswith(('http://', 'https://')):
            await message.reply_text("⚠️ لطفاً یک لینک معتبر ارسال کنید.")
            return
        
        logger.info(f"لینک دریافت شد از {message.from_user.first_name}: {url[:50]}")
        
        # دریافت اطلاعات ویدیو
        await message.reply_text("🔍 در حال دریافت اطلاعات...")
        video_info = await self.get_video_info(url)
        
        if not video_info:
            await message.reply_text("❌ خطا در دریافت اطلاعات ویدیو.")
            return
        
        # نمایش اطلاعات
        title = video_info['title']
        platform = video_info['platform']
        duration = video_info['duration']
        
        minutes = duration // 60
        seconds = duration % 60
        
        info_text = f"""
📹 **{title}**

📌 پلتفرم: {platform.upper()}
⏱ مدت زمان: {minutes}:{seconds:02d}
🎬 فرمت‌های موجود: {len(video_info['formats'])}
        """
        
        await message.reply_text(info_text, parse_mode='Markdown')
        
        # نمایش کیفیت‌ها
        keyboard = self.create_quality_keyboard(platform)
        await message.reply_text(
            "✅ لطفاً کیفیت مورد نظر را انتخاب کنید:",
            reply_markup=keyboard
        )
        
        # ذخیره اطلاعات برای callback
        context.user_data['last_url'] = url
        context.user_data['last_platform'] = platform
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پردازش callback کیبورد"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ عملیات لغو شد.")
            return
        
        if data.startswith('quality_'):
            # استخراج اطلاعات
            parts = data.split('_')
            platform = parts[1]
            format_spec = '_'.join(parts[2:]).replace('_', ' ').replace('  ', '+').replace('  ', '[').replace('  ', ']')
            
            await query.edit_message_text(f"⏳ در حال دانلود...")
            
            # دریافت URL از context
            url = context.user_data.get('last_url')
            if not url:
                await query.edit_message_text("❌ خطا: لینک پیدا نشد.")
                return
            
            # دانلود ویدیو
            filename, info = await self.download_video(url, format_spec)
            
            if filename and os.path.exists(filename):
                file_size = os.path.getsize(filename) / (1024 * 1024)
                max_size = self.config['telegram']['max_file_size']
                
                if file_size > max_size:
                    await query.edit_message_text(
                        f"⚠️ حجم فایل ({file_size:.1f}MB) از حد مجاز ({max_size}MB) بیشتر است."
                    )
                    os.unlink(filename)
                    return
                
                # ارسال ویدیو
                try:
                    with open(filename, 'rb') as f:
                        if filename.endswith('.mp3'):
                            await context.bot.send_audio(
                                chat_id=query.message.chat_id,
                                audio=f,
                                caption=f"🎵 {info.get('title', 'صدا')}\n📦 حجم: {file_size:.1f}MB"
                            )
                        else:
                            await context.bot.send_video(
                                chat_id=query.message.chat_id,
                                video=f,
                                caption=f"📹 {info.get('title', 'ویدیو')}\n📦 حجم: {file_size:.1f}MB"
                            )
                    
                    await query.edit_message_text("✅ دانلود با موفقیت انجام شد!")
                    
                except Exception as e:
                    logger.error(f"خطا در ارسال فایل: {e}")
                    await query.edit_message_text(f"❌ خطا در ارسال فایل: {str(e)[:100]}")
                
                finally:
                    # حذف فایل موقت
                    try:
                        os.unlink(filename)
                    except:
                        pass
            else:
                await query.edit_message_text("❌ خطا در دانلود ویدیو.")
    
    async def run(self):
        """اجرای اصلی ربات"""
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            logger.error("❌ توکن ربات تنظیم نشده است!")
            print("❌ توکن ربات تنظیم نشده است!")
            print("لطفاً در config.json توکن را وارد کنید")
            return
        
        logger.info(f"🚀 شروع ربات با توکن: {self.token[:15]}...")
        print(f"🤖 شروع ربات دانلود...")
        print(f"✅ توکن: {self.token[:15]}...")
        
        # ساخت اپلیکیشن
        application = Application.builder().token(self.token).build()
        
        # افزودن handlerها
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CommandHandler("status", self.status_command))
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
            drop_pending_updates=True,
            allowed_updates=Update.ALL_TYPES
        )

def main():
    """تابع اصلی"""
    print("=" * 50)
    print("🤖 ربات تلگرام دانلود از شبکه‌های اجتماعی")
    print("=" * 50)
    
    try:
        bot = DownloadBot()
        
        # اجرای ربات
        import asyncio
        asyncio.run(bot.run())
        
    except KeyboardInterrupt:
        print("\n🛑 ربات توسط کاربر متوقف شد")
    except Exception as e:
        print(f"❌ خطا: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
