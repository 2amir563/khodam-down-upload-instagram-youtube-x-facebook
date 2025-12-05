cd /opt/final-tg-bot

# بکاپ از کد فعلی
cp bot.py bot.py.backup

# کد جدید با همه اصلاحات
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
FINAL Telegram Download Bot with Quality Selection
"""

import os
import json
import logging
import asyncio
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes
import yt_dlp
import requests
import mimetypes

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('bot.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class QualityDownloadBot:
    def __init__(self):
        self.config = self.load_config()
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        # Bot state
        self.is_paused = False
        self.paused_until = None
        
        # Create directories
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # Start auto cleanup
        self.start_auto_cleanup()
        
        logger.info("🤖 Quality Download Bot initialized")
        print(f"✅ Token: {self.token[:15]}...")
    
    def load_config(self):
        """Load configuration"""
        config_file = 'config.json'
        if os.path.exists(config_file):
            with open(config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        
        # Default config
        config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000
            },
            'download_dir': 'downloads',
            'auto_cleanup_minutes': 2
        }
        
        with open(config_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        
        return config
    
    def start_auto_cleanup(self):
        """Start auto cleanup thread"""
        def cleanup_worker():
            while True:
                try:
                    self.cleanup_old_files()
                    time.sleep(60)
                except Exception as e:
                    logger.error(f"Cleanup error: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=cleanup_worker, daemon=True)
        thread.start()
        logger.info("🧹 Auto cleanup started")
    
    def cleanup_old_files(self):
        """Cleanup files older than 2 minutes"""
        cutoff_time = time.time() - (2 * 60)
        files_deleted = 0
        
        for file_path in self.download_dir.glob('*'):
            if file_path.is_file():
                file_age = time.time() - file_path.stat().st_mtime
                if file_age > (2 * 60):
                    try:
                        file_path.unlink()
                        files_deleted += 1
                    except Exception as e:
                        logger.error(f"Error deleting {file_path}: {e}")
        
        if files_deleted > 0:
            logger.info(f"Cleaned {files_deleted} old files")
    
    def detect_platform(self, url):
        """Detect platform from URL"""
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
        elif any(url_lower.endswith(ext) for ext in ['.exe', '.zip', '.rar', '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx']):
            return 'direct_binary'
        elif any(ext in url_lower for ext in ['.mp4', '.mp3', '.avi', '.mkv', '.mov', '.wav', '.jpg', '.jpeg', '.png', '.gif']):
            return 'direct_media'
        else:
            return 'generic'
    
    async def get_video_formats(self, url, platform):
        """Get available formats with sizes for YouTube and Twitter"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'listformats': True,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                formats = []
                if 'formats' in info:
                    for fmt in info['formats']:
                        # Skip formats without size
                        if not fmt.get('filesize'):
                            continue
                        
                        # Skip audio-only for video selection
                        if fmt.get('vcodec') == 'none' and fmt.get('acodec') != 'none':
                            continue
                        
                        # Get resolution
                        resolution = fmt.get('resolution', 'N/A')
                        if resolution == 'audio only':
                            continue
                        
                        # Get format note
                        format_note = fmt.get('format_note', '')
                        if not format_note and resolution != 'N/A':
                            format_note = resolution
                        
                        # Calculate size in MB
                        size_mb = fmt['filesize'] / (1024 * 1024)
                        
                        # Check if within limits
                        max_size = self.config['telegram']['max_file_size']
                        if size_mb > max_size:
                            continue
                        
                        formats.append({
                            'format_id': fmt['format_id'],
                            'resolution': resolution,
                            'format_note': format_note,
                            'ext': fmt.get('ext', 'mp4'),
                            'filesize_mb': round(size_mb, 1),
                            'quality': f"{format_note} ({resolution}) - {size_mb:.1f}MB"
                        })
                
                # Sort by resolution (highest first)
                formats.sort(key=lambda x: (
                    -int(x['resolution'].split('x')[0]) if 'x' in x['resolution'] else 0,
                    -x['filesize_mb']
                ))
                
                # Return top 5 formats
                return formats[:5]
                
        except Exception as e:
            logger.error(f"Error getting formats: {e}")
            return []
    
    def create_quality_keyboard(self, formats, platform):
        """Create keyboard for quality selection"""
        keyboard = []
        
        if platform in ['youtube', 'twitter']:
            for fmt in formats:
                quality_label = fmt['quality']
                if len(quality_label) > 50:
                    quality_label = quality_label[:47] + "..."
                
                keyboard.append([
                    InlineKeyboardButton(
                        f"🎬 {quality_label}",
                        callback_data=f"download_{platform}_{fmt['format_id']}"
                    )
                ])
            
            # Add audio option for YouTube
            if platform == 'youtube':
                keyboard.append([
                    InlineKeyboardButton(
                        "🎵 MP3 Audio Only",
                        callback_data="download_audio_bestaudio"
                    )
                ])
        
        # Add cancel button
        keyboard.append([
            InlineKeyboardButton("❌ Cancel", callback_data="cancel")
        ])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        # Check if paused
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\n"
                f"Will resume in: {hours}h {minutes}m"
            )
            return
        
        welcome = f"""
Hello {user.first_name}! 👋

🤖 **Telegram Download Bot**

📥 **Supported Platforms:**
✅ YouTube (with quality selection)
✅ Twitter/X (with quality selection)
✅ Instagram
✅ TikTok  
✅ Facebook
✅ Direct file links (preserves original format)

⚡ **Features:**
• Quality selection for YouTube/Twitter
• Auto cleanup (files deleted after 2 min)
• Pause/Resume functionality
• Preserves original file formats

🛠️ **Commands:**
/start - This menu
/help - Detailed help
/status - Bot status (admin only)
/pause [hours] - Pause bot (admin)
/resume - Resume bot (admin)
/clean - Clean temp files (admin)

🎯 **How to use:**
Just send me a video link!
For YouTube/Twitter, you can select quality.

💡 **Note:** Files are auto deleted after 2 minutes
"""
        
        await update.message.reply_text(welcome, parse_mode='Markdown')
        logger.info(f"User {user.id} started bot")
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        # Check if paused
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\n"
                f"Will resume in: {hours}h {minutes}m\n"
                f"Use /resume to resume now (admin only)"
            )
            return
        
        text = update.message.text
        user = update.effective_user
        
        logger.info(f"Message from {user.first_name}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            platform = self.detect_platform(text)
            
            if platform in ['youtube', 'twitter']:
                # Get formats and show quality selection
                await update.message.reply_text("🔍 Getting available qualities...")
                formats = await self.get_video_formats(text, platform)
                
                if formats:
                    info_text = f"""
📹 **{platform.capitalize()} Video Detected**

🎬 **Available Qualities:**
"""
                    for i, fmt in enumerate(formats[:3], 1):
                        info_text += f"{i}. {fmt['quality']}\n"
                    
                    if len(formats) > 3:
                        info_text += f"... and {len(formats) - 3} more\n"
                    
                    info_text += "\n👇 Please select quality:"
                    
                    await update.message.reply_text(info_text, parse_mode='Markdown')
                    
                    keyboard = self.create_quality_keyboard(formats, platform)
                    await update.message.reply_text(
                        "Select your preferred quality:",
                        reply_markup=keyboard
                    )
                    
                    # Save URL and formats for callback
                    context.user_data['last_url'] = text
                    context.user_data['last_platform'] = platform
                    context.user_data['last_formats'] = formats
                else:
                    # Fallback to direct download if no formats
                    await update.message.reply_text("📥 Downloading with default quality...")
                    await self.download_with_format(update, text, 'best[height<=720]')
            
            elif platform in ['direct_binary', 'direct_media']:
                # Direct file download - preserve original format
                await update.message.reply_text("📥 Downloading file...")
                await self.download_direct_file(update, text, preserve_format=True)
            
            else:
                # Other platforms (Instagram, TikTok, Facebook, generic)
                await update.message.reply_text("📥 Downloading...")
                await self.download_with_format(update, text, 'best')
        
        else:
            await update.message.reply_text(
                "Please send a valid URL starting with http:// or https://\n\n"
                "🌟 **Special features:**\n"
                "• YouTube/Twitter: Quality selection\n"
                "• Direct files: Original format preserved\n"
                "• All platforms supported"
            )
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle callback queries for quality selection"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ Download cancelled.")
            return
        
        if data.startswith('download_'):
            parts = data.split('_')
            if len(parts) >= 3:
                platform = parts[1]
                format_id = '_'.join(parts[2:])
                
                url = context.user_data.get('last_url')
                if not url:
                    await query.edit_message_text("❌ URL not found!")
                    return
                
                await query.edit_message_text(f"⏳ Downloading with selected quality...")
                
                if format_id == 'bestaudio':
                    # Download audio only
                    await self.download_with_format(update, url, 'bestaudio', is_callback=True, query=query)
                else:
                    # Download with specific format
                    await self.download_with_format(update, url, format_id, is_callback=True, query=query)
    
    async def download_with_format(self, update: Update, url, format_spec, is_callback=False, query=None):
        """Download with specific format"""
        try:
            ydl_opts = {
                'format': format_spec,
                'quiet': True,
                'no_warnings': True,
                'outtmpl': str(self.download_dir / '%(title).100s.%(ext)s'),
                'merge_output_format': 'mp4',
            }
            
            # Show downloading message
            if is_callback and query:
                message = query.message
            else:
                message = update.message
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                if os.path.exists(filename):
                    file_size = os.path.getsize(filename) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(filename)
                        error_msg = f"❌ File too large: {file_size:.1f}MB > {max_size}MB"
                        if is_callback and query:
                            await query.edit_message_text(error_msg)
                        else:
                            await update.message.reply_text(error_msg)
                        return
                    
                    # Send file
                    with open(filename, 'rb') as f:
                        if filename.endswith(('.mp3', '.m4a', '.wav', '.ogg', '.flac')):
                            await message.reply_audio(
                                audio=f,
                                caption=f"🎵 {info.get('title', 'Audio')[:50]}\nSize: {file_size:.1f}MB"
                            )
                        else:
                            await message.reply_video(
                                video=f,
                                caption=f"📹 {info.get('title', 'Video')[:50]}\nSize: {file_size:.1f}MB"
                            )
                    
                    success_msg = f"✅ Download complete! ({file_size:.1f}MB)"
                    if is_callback and query:
                        await query.edit_message_text(success_msg)
                    else:
                        await update.message.reply_text(success_msg)
                    
                    logger.info(f"Download successful: {filename}")
                    
                    # Schedule deletion
                    self.schedule_file_deletion(filename)
                    
                else:
                    error_msg = "❌ File not found after download"
                    if is_callback and query:
                        await query.edit_message_text(error_msg)
                    else:
                        await update.message.reply_text(error_msg)
                        
        except Exception as e:
            logger.error(f"Download error: {e}")
            error_msg = f"❌ Error: {str(e)[:100]}"
            if is_callback and query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
    
    async def download_direct_file(self, update: Update, url, preserve_format=True):
        """Download direct file link and preserve original format"""
        try:
            # Get filename from URL
            filename = os.path.basename(url.split('?')[0])
            if not filename or len(filename) < 3:
                # Generate filename with correct extension
                response = requests.head(url, allow_redirects=True, timeout=10)
                content_type = response.headers.get('content-type', '')
                
                # Try to get filename from Content-Disposition
                content_disposition = response.headers.get('content-disposition', '')
                if 'filename=' in content_disposition:
                    import re
                    match = re.search(r'filename=["\']?([^"\']+)["\']?', content_disposition)
                    if match:
                        filename = match.group(1)
                
                # If still no filename, generate one
                if not filename or len(filename) < 3:
                    ext = mimetypes.guess_extension(content_type) or '.bin'
                    filename = f"file_{int(time.time())}{ext}"
            
            filepath = self.download_dir / filename
            
            # Download file
            await update.message.reply_text(f"📥 Downloading: {filename}")
            
            response = requests.get(url, stream=True, timeout=60)
            response.raise_for_status()
            
            total_size = int(response.headers.get('content-length', 0))
            downloaded = 0
            
            with open(filepath, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        
                        # Show progress every 10%
                        if total_size > 0:
                            percent = (downloaded / total_size) * 100
                            if percent % 10 < 0.1:
                                await update.message.edit_text(f"📥 Downloading: {int(percent)}%")
            
            file_size = os.path.getsize(filepath) / (1024 * 1024)
            max_size = self.config['telegram']['max_file_size']
            
            if file_size > max_size:
                os.remove(filepath)
                await update.message.reply_text(
                    f"❌ File too large: {file_size:.1f}MB > {max_size}MB limit"
                )
                return
            
            # Send file with correct method based on type
            with open(filepath, 'rb') as f:
                # Determine file type
                if filename.endswith(('.mp3', '.m4a', '.wav', '.ogg', '.flac', '.aac')):
                    await update.message.reply_audio(
                        audio=f,
                        caption=f"🎵 {filename}\nSize: {file_size:.1f}MB"
                    )
                elif filename.endswith(('.mp4', '.avi', '.mkv', '.mov', '.webm', '.flv', '.wmv')):
                    await update.message.reply_video(
                        video=f,
                        caption=f"📹 {filename}\nSize: {file_size:.1f}MB"
                    )
                elif filename.endswith(('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp')):
                    await update.message.reply_photo(
                        photo=f,
                        caption=f"🖼️ {filename}\nSize: {file_size:.1f}MB"
                    )
                elif filename.endswith(('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx')):
                    await update.message.reply_document(
                        document=f,
                        caption=f"📄 {filename}\nSize: {file_size:.1f}MB"
                    )
                elif filename.endswith(('.exe', '.zip', '.rar', '.7z', '.tar', '.gz')):
                    await update.message.reply_document(
                        document=f,
                        caption=f"📦 {filename}\nSize: {file_size:.1f}MB"
                    )
                else:
                    await update.message.reply_document(
                        document=f,
                        caption=f"📁 {filename}\nSize: {file_size:.1f}MB"
                    )
            
            await update.message.reply_text(f"✅ Download complete! ({file_size:.1f}MB)")
            
            # Schedule deletion
            self.schedule_file_deletion(filepath)
            
        except Exception as e:
            logger.error(f"Direct download error: {e}")
            await update.message.reply_text(f"❌ Download error: {str(e)[:100]}")
    
    def schedule_file_deletion(self, filepath):
        """Schedule file deletion after 2 minutes"""
        def delete_later():
            time.sleep(120)
            if os.path.exists(filepath):
                try:
                    os.remove(filepath)
                    logger.info(f"Auto deleted: {os.path.basename(filepath)}")
                except:
                    pass
        
        threading.Thread(target=delete_later, daemon=True).start()
    
    # سایر دستورات (status, pause, resume, clean, help) همانند قبل...
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        status_text = f"""
📊 **Bot Status**

🤖 **Basic Info:**
• Status: {'⏸️ Paused' if self.is_paused else '✅ Active'}
• Paused until: {self.paused_until.strftime('%Y-%m-%d %H:%M') if self.paused_until else 'Not paused'}

⚙️ **Settings:**
• Max file size: {self.config['telegram']['max_file_size']}MB
• Auto cleanup: Every 2 minutes

📁 **Storage:**
• Temp files: {len(files)}
• Total size: {total_size:.1f}MB

👤 **User Info:**
• Your ID: {user.id}
• Admin: {'✅ Yes' if user.id in self.admin_ids else '❌ No'}
"""
        
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Pause bot for X hours"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        hours = 1
        if context.args:
            try:
                hours = int(context.args[0])
                if hours > 24:
                    hours = 24
            except:
                hours = 1
        
        self.is_paused = True
        self.paused_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸️ Bot paused for {hours} hour(s)\n"
            f"Will resume at: {self.paused_until.strftime('%Y-%m-%d %H:%M:%S')}"
        )
        
        logger.info(f"Bot paused by {user.id} for {hours} hours")
    
    async def resume_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Resume bot immediately"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        self.is_paused = False
        self.paused_until = None
        
        await update.message.reply_text("▶️ Bot resumed successfully!")
        logger.info(f"Bot resumed by {user.id}")
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Clean temp files"""
        user = update.effective_user
        
        if user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only command!")
            return
        
        files = list(self.download_dir.glob('*'))
        files_count = len(files)
        
        for file_path in files:
            if file_path.is_file():
                try:
                    file_path.unlink()
                except:
                    pass
        
        await update.message.reply_text(f"🧹 Cleaned {files_count} temporary files")
        logger.info(f"Cleaned {files_count} files by {user.id}")
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
📖 **Help Guide**

🌟 **Special Features:**
• YouTube: Quality selection with size info
• Twitter/X: Quality selection with size info  
• Direct files: Original format preserved
• All platforms supported

🔗 **How to use:**
1. Send a YouTube/Twitter link
2. Select quality from list
3. File downloads with your chosen quality

📁 **File Types:**
• Videos: MP4, AVI, MKV, etc.
• Audio: MP3, M4A, WAV, etc.
• Images: JPG, PNG, GIF, etc.
• Documents: PDF, DOC, XLS, etc.
• Executables: EXE (original format kept)

⚙️ **Admin Commands:**
/status - Bot status
/pause [hours] - Pause bot
/resume - Resume bot
/clean - Clean temp files

⏰ **Auto Cleanup:**
Files auto deleted after 2 minutes
"""
        
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    def run(self):
        """Run the bot"""
        print("=" * 50)
        print("🤖 QUALITY TELEGRAM DOWNLOAD BOT")
        print("=" * 50)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Bot token not configured!")
            print("Please edit config.json and add your bot token")
            return
        
        print("✅ All checks passed")
        print("🔄 Creating application...")
        
        # Create application
        app = Application.builder().token(self.token).build()
        
        # Add handlers
        app.add_handler(CommandHandler("start", self.start_command))
        app.add_handler(CommandHandler("help", self.help_command))
        app.add_handler(CommandHandler("status", self.status_command))
        app.add_handler(CommandHandler("pause", self.pause_command))
        app.add_handler(CommandHandler("resume", self.resume_command))
        app.add_handler(CommandHandler("clean", self.clean_command))
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        app.add_handler(CallbackQueryHandler(self.handle_callback))
        
        print("✅ Bot ready with quality selection!")
        print("📱 Send a YouTube link to test quality selection")
        print("=" * 50)
        
        # Run polling
        app.run_polling()

def main():
    """Main function"""
    try:
        bot = QualityDownloadBot()
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

# حالا ربات را ری‌استارت کنید
./manage.sh restart

# لاگ‌ها را بررسی کنید
tail -f bot.log
