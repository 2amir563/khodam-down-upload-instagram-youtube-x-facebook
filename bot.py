#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ربات تلگرام دانلود از یوتیوب، اینستاگرام، توییتر، تیک‌تاک، فیسبوک و...
نویسنده: 2amir563
"""

import os
import json
import logging
import asyncio
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
import tempfile
import sys

# تنظیمات ابتدایی
import configparser
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
import requests
from urllib.parse import urlparse

# تنظیمات لاگ
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DownloadBot:
    def __init__(self, config_path='config.json'):
        """مقداردهی اولیه ربات"""
        self.config = self.load_config(config_path)
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        self.schedule = self.config.get('schedule', {})
        self.paused = False
        self.pause_until = None
        self.current_mode = 'active'  # active, scheduled, paused
        
        # پوشه‌های مورد نیاز
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # حالت برنامه
        self.running = True
        
        # تنظیمات کیفیت
        self.quality_options = {
            'youtube': [
                {'label': 'بالاترین کیفیت (1080p)', 'code': 'best', 'format': 'bestvideo[height<=1080]+bestaudio/best[height<=1080]'},
                {'label': 'کیفیت متوسط (720p)', 'code': '720p', 'format': 'bestvideo[height<=720]+bestaudio/best[height<=720]'},
                {'label': 'کیفیت پایین (480p)', 'code': '480p', 'format': 'bestvideo[height<=480]+bestaudio/best[height<=480]'},
                {'label': 'فقط صدا (MP3)', 'code': 'audio', 'format': 'bestaudio/best'}
            ],
            'instagram': [
                {'label': 'بالاترین کیفیت', 'code': 'best', 'format': 'best'},
                {'label': 'کیفیت متوسط', 'code': 'medium', 'format': 'worst'},
            ],
            'twitter': [
                {'label': 'بالاترین کیفیت', 'code': 'best', 'format': 'best'},
                {'label': 'MP4', 'code': 'mp4', 'format': 'best[ext=mp4]'},
            ],
            'tiktok': [
                {'label': 'بدون واترمارک', 'code': 'nowm', 'format': 'best'},
                {'label': 'MP4', 'code': 'mp4', 'format': 'best[ext=mp4]'},
            ],
            'facebook': [
                {'label': 'HD', 'code': 'hd', 'format': 'best[height<=720]'},
                {'label': 'SD', 'code': 'sd', 'format': 'best[height<=480]'},
            ]
        }
    
    def load_config(self, config_path):
        """بارگذاری تنظیمات از فایل"""
        default_config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000  # مگابایت
            },
            'server': {
                'port': 3152,
                'web_password': 'admin123',
                'web_enabled': False,
                'host': '0.0.0.0'
            },
            'schedule': {
                'enabled': False,
                'start_time': '08:00',
                'end_time': '23:00',
                'days': [0, 1, 2, 3, 4, 5, 6]  # 0=شنبه, 6=جمعه
            },
            'download_dir': 'downloads',
            'keep_files_days': 7,
            'temp_pause_hours': 0
        }
        
        if os.path.exists(config_path):
            with open(config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                # ادغام با تنظیمات پیش‌فرض
                for key in default_config:
                    if key not in config:
                        config[key] = default_config[key]
                    elif isinstance(default_config[key], dict):
                        for subkey in default_config[key]:
                            if subkey not in config[key]:
                                config[key][subkey] = default_config[key][subkey]
                return config
        else:
            # ذخیره تنظیمات پیش‌فرض
            with open(config_path, 'w', encoding='utf-8') as f:
                json.dump(default_config, f, indent=4, ensure_ascii=False)
            return default_config
    
    def save_config(self):
        """ذخیره تنظیمات"""
        with open('config.json', 'w', encoding='utf-8') as f:
            json.dump(self.config, f, indent=4, ensure_ascii=False)
    
    def detect_platform(self, url):
        """تشخیص پلتفرم از روی URL"""
        domain = urlparse(url).netloc.lower()
        
        if 'youtube.com' in domain or 'youtu.be' in domain:
            return 'youtube'
        elif 'instagram.com' in domain:
            return 'instagram'
        elif 'twitter.com' in domain or 'x.com' in domain:
            return 'twitter'
        elif 'tiktok.com' in domain:
            return 'tiktok'
        elif 'facebook.com' in domain or 'fb.com' in domain:
            return 'facebook'
        else:
            return 'generic'
    
    async def get_video_info(self, url, platform):
        """دریافت اطلاعات ویدیو"""
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': True,
        }
        
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                if info:
                    title = info.get('title', 'بدون عنوان')
                    duration = info.get('duration', 0)
                    thumbnail = info.get('thumbnail', '')
                    
                    # دریافت فرمت‌های موجود
                    formats = []
                    if 'formats' in info:
                        for fmt in info['formats']:
                            if fmt.get('filesize'):
                                size_mb = fmt['filesize'] / (1024 * 1024)
                                formats.append({
                                    'format_id': fmt.get('format_id', 'unknown'),
                                    'ext': fmt.get('ext', 'unknown'),
                                    'resolution': fmt.get('resolution', 'unknown'),
                                    'filesize_mb': round(size_mb, 2)
                                })
                    
                    return {
                        'title': title,
                        'duration': duration,
                        'thumbnail': thumbnail,
                        'formats': formats,
                        'platform': platform
                    }
        except Exception as e:
            logger.error(f"Error getting video info: {e}")
            return None
    
    def create_quality_keyboard(self, platform, formats):
        """ایجاد کیبورد برای انتخاب کیفیت"""
        keyboard = []
        
        # گزینه‌های پیش‌فرض بر اساس پلتفرم
        for option in self.quality_options.get(platform, []):
            # پیدا کردن حجم تخمینی
            estimated_size = "نامشخص"
            for fmt in formats:
                if option['code'] in fmt.get('format_id', ''):
                    estimated_size = f"{fmt['filesize_mb']}MB"
                    break
            
            keyboard.append([InlineKeyboardButton(
                f"{option['label']} (~{estimated_size})",
                callback_data=f"quality_{platform}_{option['code']}"
            )])
        
        # گزینه سفارشی
        if formats:
            keyboard.append([InlineKeyboardButton(
                "نمایش همه فرمت‌ها",
                callback_data=f"showall_{platform}"
            )])
        
        keyboard.append([InlineKeyboardButton("لغو", callback_data="cancel")])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def download_video(self, url, quality, platform):
        """دانلود ویدیو با کیفیت مشخص"""
        temp_file = tempfile.NamedTemporaryFile(
            suffix='.mp4',
            delete=False,
            dir=str(self.download_dir)
        )
        temp_path = temp_file.name
        temp_file.close()
        
        ydl_opts = {
            'outtmpl': temp_path.replace('.mp4', '.%(ext)s'),
            'quiet': False,
            'progress_hooks': [self.download_progress_hook],
        }
        
        # تنظیم فرمت بر اساس کیفیت انتخاب شده
        if platform in self.quality_options:
            for option in self.quality_options[platform]:
                if option['code'] == quality:
                    ydl_opts['format'] = option['format']
                    break
        
        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # تبدیل فرمت اگر لازم باشد
                if not filename.endswith('.mp4'):
                    new_filename = filename.rsplit('.', 1)[0] + '.mp4'
                    os.rename(filename, new_filename)
                    filename = new_filename
                
                return filename
        except Exception as e:
            logger.error(f"Download error: {e}")
            # پاک کردن فایل موقت در صورت خطا
            if os.path.exists(temp_path):
                os.unlink(temp_path)
            return None
    
    def download_progress_hook(self, d):
        """هوک پیشرفت دانلود"""
        if d['status'] == 'downloading':
            percent = d.get('_percent_str', '0%').strip()
            speed = d.get('_speed_str', 'N/A')
            eta = d.get('_eta_str', 'N/A')
            logger.info(f"Downloading: {percent} at {speed}, ETA: {eta}")
    
    async def download_generic_file(self, url):
        """دانلود فایل عمومی از URL"""
        try:
            response = requests.get(url, stream=True, timeout=30)
            response.raise_for_status()
            
            # استخراج نام فایل
            filename = os.path.basename(urlparse(url).path)
            if not filename:
                filename = f"file_{int(time.time())}"
            
            filepath = self.download_dir / filename
            
            with open(filepath, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            return str(filepath)
        except Exception as e:
            logger.error(f"Generic download error: {e}")
            return None
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /start"""
        user = update.effective_user
        welcome_text = f"""
سلام {user.first_name}! 👋

من ربات دانلود از شبکه‌های اجتماعی هستم. می‌توانم از این سایت‌ها برای شما دانلود کنم:
• YouTube
• Instagram
• Twitter/X
• TikTok
• Facebook
• و هر لینک مستقیم دیگر

🎯 فقط کافیه لینک مورد نظر رو برام بفرستی!

📱 دستورات موجود:
/start - نمایش این راهنما
/help - راهنمای کامل
/status - وضعیت ربات
/schedule - تنظیم زمان‌بندی
/pause [ساعت] - توقف موقت
/resume - ادامه کار
/stats - آمار دانلود
"""
        
        await update.message.reply_text(welcome_text)
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /help"""
        help_text = """
📖 راهنمای استفاده از ربات:

1️⃣ ارسال لینک:
• لینک ویدیو از شبکه‌های اجتماعی را بفرستید
• ربات به طور خودکار پلتفرم را تشخیص می‌دهد
• کیفیت‌های موجود را به شما نشان می‌دهد
• بعد از انتخاب کیفیت، دانلود شروع می‌شود

2️⃣ دستورات مدیریتی:
• /status - وضعیت فعلی ربات
• /pause [تعداد ساعت] - توقف موقت ربات
• /resume - ادامه کار ربات
• /schedule - تنظیم زمان‌بندی کار ربات
• /stats - آمار دانلودها

3️⃣ محدودیت‌ها:
• حداکثر سایز فایل: 2GB
• فرمت خروجی: MP4 (پیش‌فرض)
• فایل‌ها بعد از 7 روز حذف می‌شوند

❓ اگر مشکلی دارید، لینک را دوباره بفرستید یا بات را ریستارت کنید.
"""
        await update.message.reply_text(help_text)
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /status"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است!")
            return
        
        status_text = f"""
📊 وضعیت ربات:

• حالت فعلی: {'⏸ متوقف' if self.paused else '▶ فعال'}
• حالت زمان‌بندی: {'✅ فعال' if self.schedule.get('enabled') else '❌ غیرفعال'}
• زمان‌بندی: {self.schedule.get('start_time', '--')} تا {self.schedule.get('end_time', '--')}
• پورت وب: {'✅ ' + str(self.config['server']['port']) if self.config['server']['web_enabled'] else '❌ غیرفعال'}
• فایل‌های دانلود شده: {len(list(self.download_dir.glob('*')))}
• آیدی شما: {user_id}
"""
        
        if self.pause_until:
            status_text += f"\n• توقف تا: {self.pause_until}"
        
        await update.message.reply_text(status_text)
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """پردازش پیام‌های دریافتی"""
        # بررسی توقف ربات
        if self.paused:
            if self.pause_until and datetime.now() < self.pause_until:
                remaining = self.pause_until - datetime.now()
                hours = int(remaining.total_seconds() // 3600)
                minutes = int((remaining.total_seconds() % 3600) // 60)
                await update.message.reply_text(
                    f"⏸ ربات موقتاً متوقف شده است.\n"
                    f"⏳ زمان باقی‌مانده: {hours} ساعت و {minutes} دقیقه"
                )
                return
            else:
                self.paused = False
                self.pause_until = None
        
        # بررسی زمان‌بندی
        if self.schedule.get('enabled'):
            now = datetime.now()
            current_time = now.strftime("%H:%M")
            current_day = now.weekday()  # Monday = 0
            
            start_time = self.schedule.get('start_time', '00:00')
            end_time = self.schedule.get('end_time', '23:59')
            days = self.schedule.get('days', [])
            
            if current_day not in days or not (start_time <= current_time <= end_time):
                await update.message.reply_text(
                    f"⏰ ربات فقط در ساعات زیر فعال است:\n"
                    f"📅 روزها: {', '.join([str(d) for d in days])}\n"
                    f"🕐 ساعت: {start_time} تا {end_time}"
                )
                return
        
        message = update.message
        url = message.text
        
        if not url.startswith(('http://', 'https://')):
            await message.reply_text("⚠️ لطفاً یک لینک معتبر ارسال کنید.")
            return
        
        # تشخیص پلتفرم
        platform = self.detect_platform(url)
        
        if platform == 'generic':
            # دانلود مستقیم فایل
            await message.reply_text("📥 در حال دانلود فایل...")
            filepath = await self.download_generic_file(url)
            
            if filepath and os.path.exists(filepath):
                filesize = os.path.getsize(filepath) / (1024 * 1024)
                
                if filesize > self.config['telegram']['max_file_size']:
                    await message.reply_text(
                        f"⚠️ حجم فایل ({filesize:.1f}MB) از حد مجاز "
                        f"({self.config['telegram']['max_file_size']}MB) بیشتر است."
                    )
                    os.unlink(filepath)
                    return
                
                await message.reply_document(
                    document=open(filepath, 'rb'),
                    caption=f"📁 فایل دانلود شده\n🔗 {url}"
                )
                os.unlink(filepath)
            else:
                await message.reply_text("❌ خطا در دانلود فایل.")
        else:
            # دریافت اطلاعات ویدیو
            await message.reply_text("🔍 در حال دریافت اطلاعات...")
            video_info = await self.get_video_info(url, platform)
            
            if not video_info:
                await message.reply_text("❌ خطا در دریافت اطلاعات ویدیو.")
                return
            
            # نمایش اطلاعات و کیفیت‌ها
            title = video_info['title'][:50] + "..." if len(video_info['title']) > 50 else video_info['title']
            info_text = f"""
📹 **{title}**

📌 پلتفرم: {platform.upper()}
⏱ مدت: {video_info['duration'] // 60}:{video_info['duration'] % 60:02d}
🎬 فرمت‌های موجود: {len(video_info['formats'])}
            """
            
            await message.reply_text(
                info_text,
                parse_mode='Markdown'
            )
            
            # نمایش کیبورد کیفیت
            keyboard = self.create_quality_keyboard(platform, video_info['formats'])
            await message.reply_text(
                "✅ لطفاً کیفیت مورد نظر را انتخاب کنید:",
                reply_markup=keyboard
            )
            
            # ذخیره URL در context
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
            _, platform, quality = data.split('_')
            
            await query.edit_message_text(f"⏳ در حال دانلود با کیفیت {quality}...")
            
            # دریافت URL از context
            url = context.user_data.get('last_url')
            if not url:
                await query.edit_message_text("❌ خطا: لینک پیدا نشد.")
                return
            
            # دانلود ویدیو
            filepath = await self.download_video(url, quality, platform)
            
            if filepath and os.path.exists(filepath):
                filesize = os.path.getsize(filepath) / (1024 * 1024)
                
                if filesize > self.config['telegram']['max_file_size']:
                    await query.edit_message_text(
                        f"⚠️ حجم فایل ({filesize:.1f}MB) از حد مجاز بیشتر است."
                    )
                    os.unlink(filepath)
                    return
                
                await context.bot.send_video(
                    chat_id=query.message.chat_id,
                    video=open(filepath, 'rb'),
                    caption=f"✅ دانلود با کیفیت {quality} تکمیل شد!\n📦 حجم: {filesize:.1f}MB"
                )
                os.unlink(filepath)
            else:
                await query.edit_message_text("❌ خطا در دانلود ویدیو.")
        
        elif data.startswith('showall_'):
            _, platform = data.split('_')
            # نمایش تمام فرمت‌ها (پیاده‌سازی کامل‌تر در نسخه بعدی)
            await query.edit_message_text("این قابلیت در نسخه بعدی اضافه خواهد شد.")
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /pause"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است!")
            return
        
        hours = 1  # پیش‌فرض: 1 ساعت
        if context.args:
            try:
                hours = int(context.args[0])
            except ValueError:
                hours = 1
        
        self.paused = True
        self.pause_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸ ربات به مدت {hours} ساعت متوقف شد.\n"
            f"🕐 تا ساعت: {self.pause_until.strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"برای ادامه از دستور /resume استفاده کنید."
        )
    
    async def resume_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /resume"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است!")
            return
        
        self.paused = False
        self.pause_until = None
        
        await update.message.reply_text("▶ ربات فعال شد.")
    
    async def schedule_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /schedule"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است!")
            return
        
        if context.args:
            # تنظیم زمان‌بندی
            if context.args[0] == 'on':
                self.schedule['enabled'] = True
                if len(context.args) >= 3:
                    self.schedule['start_time'] = context.args[1]
                    self.schedule['end_time'] = context.args[2]
                await update.message.reply_text("✅ زمان‌بندی فعال شد.")
            elif context.args[0] == 'off':
                self.schedule['enabled'] = False
                await update.message.reply_text("❌ زمان‌بندی غیرفعال شد.")
            else:
                await update.message.reply_text(
                    "⚠️ فرمت دستور:\n"
                    "/schedule on 08:00 23:00\n"
                    "/schedule off"
                )
        else:
            # نمایش وضعیت فعلی
            status = "فعال ✅" if self.schedule.get('enabled') else "غیرفعال ❌"
            await update.message.reply_text(
                f"⏰ وضعیت زمان‌بندی: {status}\n"
                f"🕐 ساعت کار: {self.schedule.get('start_time', '--')} تا {self.schedule.get('end_time', '--')}\n"
                f"📅 روزهای هفته: {', '.join([str(d) for d in self.schedule.get('days', [])])}"
            )
    
    async def stats_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """دستور /stats"""
        user_id = update.effective_user.id
        
        if user_id not in self.admin_ids:
            await update.message.reply_text("⛔ این دستور فقط برای ادمین‌ها است!")
            return
        
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        stats_text = f"""
📊 آمار ربات:

• تعداد فایل‌های موقت: {len(files)}
• حجم کل فایل‌ها: {total_size:.1f} MB
• پوشه دانلود: {self.download_dir}
• ربات فعال از: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
• پورت وب: {'فعال' if self.config['server']['web_enabled'] else 'غیرفعال'}
"""
        
        await update.message.reply_text(stats_text)
    
    def cleanup_old_files(self):
        """پاکسازی فایل‌های قدیمی"""
        keep_days = self.config.get('keep_files_days', 7)
        cutoff_time = time.time() - (keep_days * 24 * 3600)
        
        for file in self.download_dir.glob('*'):
            if file.is_file() and file.stat().st_mtime < cutoff_time:
                try:
                    file.unlink()
                    logger.info(f"Deleted old file: {file}")
                except Exception as e:
                    logger.error(f"Error deleting file {file}: {e}")
    
    async def run(self):
        """اجرای اصلی ربات"""
        # پاکسازی فایل‌های قدیمی
        self.cleanup_old_files()
        
        # ساخت اپلیکیشن تلگرام
        application = Application.builder().token(self.token).build()
        
        # افزودن handlerها
        application.add_handler(CommandHandler("start", self.start_command))
        application.add_handler(CommandHandler("help", self.help_command))
        application.add_handler(CommandHandler("status", self.status_command))
        application.add_handler(CommandHandler("pause", self.pause_command))
        application.add_handler(CommandHandler("resume", self.resume_command))
        application.add_handler(CommandHandler("schedule", self.schedule_command))
        application.add_handler(CommandHandler("stats", self.stats_command))
        application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        application.add_handler(CallbackQueryHandler(self.handle_callback))
        
        # شروع ربات
        await application.initialize()
        await application.start()
        
        logger.info("🤖 ربات شروع به کار کرد!")
        
        # اجرای وب سرور اگر فعال باشد
        if self.config['server']['web_enabled']:
            web_thread = threading.Thread(target=self.run_web_server)
            web_thread.daemon = True
            web_thread.start()
            logger.info(f"🌐 وب سرور روی پورت {self.config['server']['port']} شروع شد")
        
        # نگه داشتن برنامه در حال اجرا
        while self.running:
            await asyncio.sleep(1)
            
            # پاکسازی دوره‌ای فایل‌های قدیمی (هر 6 ساعت)
            if int(time.time()) % (6 * 3600) < 60:
                self.cleanup_old_files()
        
        # توقف ربات
        await application.stop()
    
    def run_web_server(self):
        """اجرای وب سرور ساده"""
        try:
            from web_dashboard import run_web_server
            run_web_server(self.config, self)
        except ImportError:
            logger.warning("Web dashboard not available")
    
    def stop(self):
        """توقف ربات"""
        self.running = False
        logger.info("🛑 ربات متوقف شد")

def main():
    """تابع اصلی اجرا"""
    bot = DownloadBot()
    
    try:
        # اجرای ربات
        asyncio.run(bot.run())
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt received. Stopping bot...")
        bot.stop()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
