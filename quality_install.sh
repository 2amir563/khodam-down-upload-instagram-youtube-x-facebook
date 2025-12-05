#!/bin/bash
# quality_install.sh - Install Telegram bot with quality selection
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)

set -e

echo "🎯 Installing Telegram Bot with Quality Selection"
echo "================================================"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_green() { echo -e "${GREEN}[✓]${NC} $1"; }
print_red() { echo -e "${RED}[✗]${NC} $1"; }
print_blue() { echo -e "${BLUE}[i]${NC} $1"; }

# Install directory
INSTALL_DIR="/opt/quality-tg-bot"

# Step 1: Cleanup
print_blue "1. Cleaning old installations..."
pkill -f "python.*bot.py" 2>/dev/null || true
rm -rf "$INSTALL_DIR" 2>/dev/null || true
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 2: Install dependencies
print_blue "2. Installing system dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano cron psmisc

# Step 3: Create virtual environment
print_blue "3. Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Step 4: Install Python packages
print_blue "4. Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.7 yt-dlp==2025.11.12 requests==2.32.5

# Step 5: Create bot.py with quality selection
print_blue "5. Creating bot.py with quality selection..."
cat > bot.py << 'EOF'
#!/usr/bin/env python3
"""
Telegram Download Bot with Quality Selection
Features:
1. Quality selection for YouTube/Twitter/Instagram with file sizes
2. Original format preservation for direct files
3. Auto cleanup every 2 minutes
4. Pause/Resume functionality
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
from telegram.error import TelegramError
import yt_dlp
import requests

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
        cleanup_minutes = self.config.get('auto_cleanup_minutes', 2)
        cutoff_time = time.time() - (cleanup_minutes * 60)
        files_deleted = 0
        
        for file_path in self.download_dir.glob('*'):
            if file_path.is_file():
                file_age = time.time() - file_path.stat().st_mtime
                if file_age > (cleanup_minutes * 60):
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
        else:
            return 'generic'
    
    async def get_video_formats(self, url, platform='youtube'):
        """Get available formats with sizes"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'socket_timeout': 30,
            }
            
            # Instagram needs cookies
            if platform == 'instagram':
                ydl_opts.update({
                    'cookiefile': 'cookies.txt',
                    'extractor_args': {
                        'instagram': {
                            'requested_formats': 'dash',
                            'skip_dash_manifest': False,
                        }
                    }
                })
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                formats = []
                if 'formats' in info:
                    for fmt in info['formats']:
                        # Skip audio-only for video selection
                        if fmt.get('vcodec') == 'none' and fmt.get('acodec') != 'none':
                            continue
                        
                        resolution = fmt.get('resolution', 'N/A')
                        if resolution == 'audio only':
                            continue
                        
                        # Skip storyboards
                        if 'storyboard' in str(fmt.get('format_note', '')).lower():
                            continue
                        
                        # Get file size
                        filesize = fmt.get('filesize')
                        if not filesize and fmt.get('tbr') and info.get('duration'):
                            duration = info.get('duration', 60)
                            filesize = (fmt['tbr'] * 1000 * duration) / 8
                        
                        if not filesize:
                            continue
                        
                        format_note = fmt.get('format_note', '')
                        if not format_note and resolution != 'N/A':
                            format_note = resolution
                        
                        # Calculate size
                        size_mb = filesize / (1024 * 1024)
                        max_size = self.config['telegram']['max_file_size']
                        
                        if size_mb > max_size:
                            continue
                        
                        format_id = fmt.get('format_id', 'best')
                        ext = fmt.get('ext', 'mp4')
                        
                        # Create display label
                        if resolution == 'N/A' and format_note:
                            quality_label = f"{format_note} - {size_mb:.1f}MB"
                        elif resolution != 'N/A':
                            quality_label = f"{resolution} - {size_mb:.1f}MB"
                        else:
                            quality_label = f"Unknown - {size_mb:.1f}MB"
                        
                        formats.append({
                            'format_id': format_id,
                            'resolution': resolution,
                            'format_note': format_note,
                            'ext': ext,
                            'filesize_mb': round(size_mb, 2),  # 2 decimal places
                            'quality': quality_label
                        })
                
                # Sort by quality (highest first)
                def sort_key(fmt):
                    res = fmt['resolution']
                    if res == 'N/A':
                        return (0, -fmt['filesize_mb'])
                    if 'x' in res:
                        try:
                            w, h = map(int, res.split('x'))
                            return (-h, -w, -fmt['filesize_mb'])
                        except:
                            return (0, -fmt['filesize_mb'])
                    return (0, -fmt['filesize_mb'])
                
                formats.sort(key=sort_key)
                
                # Return top formats
                return formats[:8]
                
        except Exception as e:
            logger.error(f"Error getting formats for {url}: {e}")
            return []
    
    def create_quality_keyboard(self, formats, platform):
        """Create keyboard for quality selection"""
        keyboard = []
        
        if platform in ['youtube', 'twitter'] and formats:
            for fmt in formats:
                quality_label = fmt['quality']
                if len(quality_label) > 40:
                    quality_label = quality_label[:37] + "..."
                
                callback_data = f"download_{platform}_{fmt['format_id']}"
                keyboard.append([
                    InlineKeyboardButton(
                        f"🎬 {quality_label}",
                        callback_data=callback_data
                    )
                ])
            
            # Add audio option for YouTube
            if platform == 'youtube':
                keyboard.append([
                    InlineKeyboardButton(
                        "🎵 MP3 Audio Only",
                        callback_data="download_youtube_bestaudio"
                    )
                ])
        
        # For Instagram, show fewer options
        elif platform == 'instagram' and formats:
            for fmt in formats[:3]:  # Only show top 3 for Instagram
                quality_label = fmt['quality']
                if len(quality_label) > 40:
                    quality_label = quality_label[:37] + "..."
                
                callback_data = f"download_instagram_{fmt['format_id']}"
                keyboard.append([
                    InlineKeyboardButton(
                        f"📸 {quality_label}",
                        callback_data=callback_data
                    )
                ])
        
        else:
            # Default option
            keyboard.append([
                InlineKeyboardButton("📹 Best Quality", callback_data="download_generic_best")
            ])
        
        # Add cancel button
        keyboard.append([
            InlineKeyboardButton("❌ Cancel", callback_data="cancel")
        ])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        welcome = f"""
Hello {user.first_name}! 👋

🤖 **Telegram Download Bot with Quality Selection**

📥 **Supported Platforms:**
✅ YouTube (choose quality with file size)
✅ Twitter/X (choose quality with file size)
✅ Instagram (basic download)
✅ TikTok  
✅ Facebook
✅ Direct files

🎯 **How to use:**
1. Send YouTube/Twitter link → Choose quality
2. Send other links → Auto download
3. Send direct file → Keeps original format

⚡ **Features:**
• Quality selection for YouTube/Twitter
• Shows file size for each quality
• Auto cleanup every 2 minutes
• Pause/Resume bot
• Preserves file formats

🛠️ **Commands:**
/start - This menu
/help - Detailed help
/status - Bot status (admin)
/pause [hours] - Pause bot (admin)
/resume - Resume bot (admin)
/clean - Clean files (admin)

💡 **Files auto deleted after 2 minutes**
"""
        
        await update.message.reply_text(welcome, parse_mode='Markdown')
        logger.info(f"User {user.id} started bot")
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        text = update.message.text.strip()
        user = update.effective_user
        
        logger.info(f"Message from {user.id}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            platform = self.detect_platform(text)
            
            # Save URL for callback
            context.user_data['last_url'] = text
            context.user_data['last_platform'] = platform
            
            if platform in ['youtube', 'twitter']:
                # Show quality selection
                await update.message.reply_text(f"🔍 Getting available qualities from {platform}...")
                formats = await self.get_video_formats(text, platform)
                
                if formats:
                    info_text = f"📹 **{platform.capitalize()} Video**\n\n"
                    info_text += "🎬 **Available Qualities:**\n"
                    
                    for i, fmt in enumerate(formats[:3], 1):
                        info_text += f"{i}. {fmt['quality']}\n"
                    
                    if len(formats) > 3:
                        info_text += f"... and {len(formats) - 3} more\n"
                    
                    await update.message.reply_text(info_text, parse_mode='Markdown')
                    
                    keyboard = self.create_quality_keyboard(formats, platform)
                    await update.message.reply_text(
                        "👇 Select quality:",
                        reply_markup=keyboard
                    )
                    
                else:
                    # Fallback if no formats
                    await update.message.reply_text("📥 Downloading with best quality...")
                    await self.download_media(update, context, text, 'best', platform)
            
            elif platform == 'instagram':
                # Instagram needs special handling
                await update.message.reply_text("📸 Downloading from Instagram...")
                await self.download_instagram(update, context, text)
            
            else:
                # Other platforms
                await update.message.reply_text(f"📥 Downloading from {platform}...")
                await self.download_media(update, context, text, 'best', platform)
        
        else:
            await update.message.reply_text(
                "Please send a valid URL starting with http:// or https://\n\n"
                "🌟 **Special:** YouTube/Twitter links show quality options!"
            )
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle callback queries"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ Download cancelled.")
            return
        
        if data.startswith('download_'):
            # Parse: download_platform_format_id
            parts = data.split('_')
            if len(parts) >= 3:
                platform = parts[1]
                format_id = parts[2]
                
                url = context.user_data.get('last_url')
                if not url:
                    await query.edit_message_text("❌ URL not found!")
                    return
                
                await query.edit_message_text(f"⏳ Downloading {format_id} quality...")
                
                if platform == 'instagram':
                    await self.download_instagram(update, context, url, query)
                else:
                    await self.download_media(update, context, url, format_id, platform, query)
    
    async def download_media(self, update: Update, context: ContextTypes.DEFAULT_TYPE, url, format_spec, platform, query=None):
        """Download media with specific format"""
        try:
            # Create progress message
            if query:
                progress_msg = query.message
                chat_id = progress_msg.chat_id
            else:
                progress_msg = await update.message.reply_text("⏬ Starting download...")
                chat_id = update.effective_chat.id
            
            # Prepare download options
            timestamp = int(time.time())
            ydl_opts = {
                'format': format_spec,
                'quiet': False,
                'outtmpl': str(self.download_dir / f'{timestamp}_%(title).100s.%(ext)s'),
                'progress_hooks': [self.create_progress_hook(progress_msg)],
                'http_headers': {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                },
                'socket_timeout': 30,
                'retries': 3,
            }
            
            # Platform-specific options
            if platform == 'instagram':
                ydl_opts['cookiefile'] = 'cookies.txt'
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # Find actual file
                actual_file = self.find_downloaded_file(filename)
                
                if actual_file and os.path.exists(actual_file):
                    file_size = os.path.getsize(actual_file) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(actual_file)
                        error_msg = f"❌ File too large: {file_size:.1f}MB (max: {max_size}MB)"
                        if query:
                            await query.edit_message_text(error_msg)
                        else:
                            await progress_msg.edit_text(error_msg)
                        return
                    
                    # Send file to Telegram
                    await self.send_telegram_file(update, actual_file, info, query)
                    
                    # Schedule deletion
                    self.schedule_file_deletion(actual_file)
                    
                else:
                    error_msg = "❌ File not found after download"
                    if query:
                        await query.edit_message_text(error_msg)
                    else:
                        await progress_msg.edit_text(error_msg)
                        
        except yt_dlp.utils.DownloadError as e:
            error_msg = str(e)
            if "Private video" in error_msg:
                error_msg = "❌ Video is private or requires login"
            elif "Unavailable" in error_msg:
                error_msg = "❌ Video is unavailable"
            elif "Too many requests" in error_msg:
                error_msg = "❌ Rate limited. Please try again later"
            elif "login" in error_msg.lower():
                error_msg = "❌ Login required (Instagram needs cookies)"
            
            if query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
            logger.error(f"Download error: {e}")
        
        except Exception as e:
            error_msg = f"❌ Download failed: {str(e)[:100]}"
            if query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
            logger.error(f"Unexpected error: {e}", exc_info=True)
    
    async def download_instagram(self, update: Update, context: ContextTypes.DEFAULT_TYPE, url, query=None):
        """Special handling for Instagram"""
        try:
            # Create progress message
            if query:
                progress_msg = query.message
            else:
                progress_msg = await update.message.reply_text("📸 Downloading from Instagram...")
            
            # Try with yt-dlp first
            ydl_opts = {
                'format': 'best',
                'quiet': False,
                'outtmpl': str(self.download_dir / '%(title).100s.%(ext)s'),
                'http_headers': {
                    'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15'
                },
                'socket_timeout': 30,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                actual_file = self.find_downloaded_file(filename)
                
                if actual_file and os.path.exists(actual_file):
                    await self.send_telegram_file(update, actual_file, info, query)
                    self.schedule_file_deletion(actual_file)
                else:
                    error_msg = "❌ Failed to download Instagram content"
                    if query:
                        await query.edit_message_text(error_msg)
                    else:
                        await progress_msg.edit_text(error_msg)
                        
        except Exception as e:
            error_msg = f"❌ Instagram download failed: {str(e)[:100]}"
            if query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
            logger.error(f"Instagram error: {e}")
    
    def create_progress_hook(self, progress_msg):
        """Create progress hook for yt-dlp"""
        def hook(d):
            if d['status'] == 'downloading':
                percent = d.get('_percent_str', '0%').strip()
                speed = d.get('_speed_str', 'N/A')
                eta = d.get('_eta_str', 'N/A')
                
                # We'll update in the main download function
                pass
        
        return hook
    
    def find_downloaded_file(self, base_filename):
        """Find the actual downloaded file"""
        base = os.path.splitext(base_filename)[0]
        
        for ext in ['.mp4', '.mkv', '.webm', '.m4a', '.mp3', '.flv', '.avi', '.mov']:
            test_file = base + ext
            if os.path.exists(test_file):
                return test_file
        
        if os.path.exists(base_filename):
            return base_filename
        
        return None
    
    async def send_telegram_file(self, update, filepath, info, query=None):
        """Send file to Telegram with appropriate method"""
        try:
            file_size = os.path.getsize(filepath) / (1024 * 1024)
            title = info.get('title', os.path.basename(filepath))[:100]
            duration = info.get('duration', 0)
            
            caption = f"✅ **Download Complete!**\n"
            caption += f"📁 **Title:** {title}\n"
            caption += f"📊 **Size:** {file_size:.2f} MB"  # Fixed: 2 decimal places
            
            if duration > 0:
                mins = int(duration) // 60
                secs = int(duration) % 60
                caption += f"\n⏱️ **Duration:** {mins}:{secs:02d}"
            
            # Determine file type
            file_ext = os.path.splitext(filepath)[1].lower()
            
            with open(filepath, 'rb') as f:
                if file_ext in ['.mp3', '.m4a', '.opus', '.flac', '.wav']:
                    if query:
                        await update.message.reply_audio(
                            audio=f,
                            caption=caption,
                            title=title[:64],
                            duration=int(duration),
                            parse_mode='Markdown'
                        )
                    else:
                        await update.message.reply_audio(
                            audio=f,
                            caption=caption,
                            title=title[:64],
                            duration=int(duration),
                            parse_mode='Markdown'
                        )
                elif file_ext in ['.mp4', '.mkv', '.webm', '.mov', '.avi']:
                    if query:
                        await update.message.reply_video(
                            video=f,
                            caption=caption,
                            duration=int(duration),
                            supports_streaming=True,
                            parse_mode='Markdown'
                        )
                    else:
                        await update.message.reply_video(
                            video=f,
                            caption=caption,
                            duration=int(duration),
                            supports_streaming=True,
                            parse_mode='Markdown'
                        )
                elif file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
                    if query:
                        await update.message.reply_photo(
                            photo=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
                    else:
                        await update.message.reply_photo(
                            photo=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
                else:
                    if query:
                        await update.message.reply_document(
                            document=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
                    else:
                        await update.message.reply_document(
                            document=f,
                            caption=caption,
                            parse_mode='Markdown'
                        )
            
            success_msg = f"✅ File sent successfully!\n📊 Size: {file_size:.2f}MB"
            
            if query:
                await query.edit_message_text(success_msg)
            else:
                await update.message.reply_text(success_msg)
                
        except TelegramError as e:
            error_msg = f"❌ Telegram error: {str(e)[:100]}"
            if query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
            logger.error(f"Telegram send error: {e}")
        except Exception as e:
            error_msg = f"❌ Error sending file: {str(e)[:100]}"
            if query:
                await query.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
            logger.error(f"Send error: {e}")
    
    def schedule_file_deletion(self, filepath):
        """Schedule file deletion after 2 minutes"""
        def delete_later():
            time.sleep(120)
            if os.path.exists(filepath):
                try:
                    os.remove(filepath)
                    logger.info(f"Auto deleted: {os.path.basename(filepath)}")
                except Exception as e:
                    logger.error(f"Error deleting {filepath}: {e}")
        
        threading.Thread(target=delete_later, daemon=True).start()
    
    # Other commands...
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        await update.message.reply_text(
            "📖 **Help**\n\n"
            "Send YouTube/Twitter link → Choose quality\n"
            "Send Instagram link → Auto download\n"
            "Send other links → Auto download\n"
            "Files auto deleted after 2 minutes",
            parse_mode='Markdown'
        )
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        await update.message.reply_text(
            f"📊 **Status**\n\n"
            f"✅ Bot active\n"
            f"📁 Files in cache: {len(files)}\n"
            f"💾 Cache size: {total_size:.2f}MB\n"
            f"👤 Your ID: {user.id}",
            parse_mode='Markdown'
        )
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        hours = 1
        if context.args:
            try:
                hours = int(context.args[0])
                if hours < 1 or hours > 720:
                    hours = 1
            except:
                hours = 1
        
        self.is_paused = True
        self.paused_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸️ Bot paused for {hours} hour(s)\n"
            f"Resume at: {self.paused_until.strftime('%Y-%m-%d %H:%M')}"
        )
    
    async def resume_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        self.is_paused = False
        self.paused_until = None
        await update.message.reply_text("▶️ Bot resumed!")
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        count = len(files)
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        for f in files:
            try:
                f.unlink()
            except Exception as e:
                logger.error(f"Error deleting {f}: {e}")
        
        await update.message.reply_text(f"🧹 Cleaned {count} files ({total_size:.2f}MB)")
    
    def run(self):
        """Run the bot"""
        print("=" * 60)
        print("🤖 Telegram Download Bot with Quality Selection")
        print("=" * 60)
        
        # Check token
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Bot token not configured!")
            print("📝 Edit config.json and add your bot token")
            print("🔑 Get token from @BotFather on Telegram")
            print("💻 Replace 'YOUR_BOT_TOKEN_HERE' with your actual token")
            return
        
        print(f"✅ Token: {self.token[:15]}...")
        print(f"✅ Admins: {len(self.admin_ids)}")
        print(f"✅ Max file size: {self.config['telegram']['max_file_size']}MB")
        print(f"✅ Download dir: {self.download_dir}")
        print("✅ Bot ready!")
        print("📱 Send YouTube/Twitter link to test quality selection")
        print("=" * 60)
        
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
        
        # Run bot
        app.run_polling(drop_pending_updates=True)

def main():
    try:
        bot = QualityDownloadBot()
        bot.run()
    except KeyboardInterrupt:
        print("\n🛑 Bot stopped by user")
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        time.sleep(5)

if __name__ == '__main__':
    main()
EOF

# Step 6: Create config.json
print_blue "6. Creating config.json..."
cat > config.json << 'EOF'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "download_dir": "downloads",
    "auto_cleanup_minutes": 2
}
EOF

# Step 7: Create management script
print_blue "7. Creating management script..."
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Quality bot management
# Location: /opt/quality-tg-bot

cd /opt/quality-tg-bot

case "$1" in
    start)
        echo "🚀 Starting Quality Bot..."
        
        # Check if bot is already running
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "⚠️ Bot is already running (PID: $(cat bot.pid))"
            exit 1
        fi
        
        # Check if token is configured
        if grep -q "YOUR_BOT_TOKEN_HERE" config.json; then
            echo "❌ ERROR: Bot token not configured!"
            echo ""
            echo "📝 Please edit config.json first:"
            echo "   nano config.json"
            echo ""
            echo "🔑 Get token from @BotFather on Telegram"
            echo "💻 Replace 'YOUR_BOT_TOKEN_HERE' with your actual token"
            exit 1
        fi
        
        source venv/bin/activate
        
        # Clear old log
        > bot.log 2>/dev/null || true
        
        # Start bot
        nohup python bot.py >> bot.log 2>&1 &
        PID=$!
        echo $PID > bot.pid
        
        echo "✅ Bot started successfully! (PID: $PID)"
        echo "📝 Logs: tail -f bot.log"
        echo "📊 Status: ./manage.sh status"
        echo ""
        echo "🎯 Features ready:"
        echo "   • YouTube quality selection"
        echo "   • Twitter quality selection"
        echo "   • Instagram download"
        echo "   • Auto cleanup every 2 minutes"
        ;;
    stop)
        echo "🛑 Stopping bot..."
        if [ -f "bot.pid" ]; then
            PID=$(cat bot.pid)
            if ps -p $PID > /dev/null 2>&1; then
                kill $PID
                sleep 2
                if ps -p $PID > /dev/null 2>&1; then
                    kill -9 $PID
                    echo "⚠️ Force killed bot (PID: $PID)"
                else
                    echo "✅ Bot stopped (PID: $PID)"
                fi
            else
                echo "⚠️ Bot not running"
            fi
            rm -f bot.pid
        else
            echo "⚠️ No PID file found"
        fi
        ;;
    restart)
        echo "🔄 Restarting bot..."
        ./manage.sh stop
        sleep 3
        ./manage.sh start
        ;;
    status)
        echo "📊 Bot Status:"
        echo "==============="
        
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            PID=$(cat bot.pid)
            echo "✅ Bot is RUNNING (PID: $PID)"
            echo "⏰ Uptime: $(ps -p $PID -o etime= | xargs)"
            
            # Check config
            TOKEN=$(grep -o '"token": "[^"]*"' config.json | cut -d'"' -f4)
            if [ "$TOKEN" = "YOUR_BOT_TOKEN_HERE" ]; then
                echo "❌ CONFIG ERROR: Token not set!"
            else
                echo "✅ Token: ${TOKEN:0:15}..."
            fi
            
            # Show recent logs
            echo ""
            echo "📝 Recent activity:"
            if [ -f "bot.log" ]; then
                tail -10 bot.log | while read line; do
                    echo "  $line"
                done
            else
                echo "  No log file yet"
            fi
            
            # Show downloads
            if [ -d "downloads" ]; then
                COUNT=$(ls -1 downloads/ 2>/dev/null | wc -l)
                SIZE=$(du -sh downloads/ 2>/dev/null | cut -f1)
                echo "📁 Downloads cache: $COUNT files ($SIZE)"
            fi
            
        else
            echo "❌ Bot is NOT RUNNING"
            [ -f "bot.pid" ] && rm -f bot.pid
        fi
        ;;
    logs)
        echo "📝 Bot logs:"
        if [ -f "bot.log" ]; then
            if [ "$2" = "-f" ] || [ "$2" = "--follow" ]; then
                tail -f bot.log
            elif [ "$2" = "-e" ] || [ "$2" = "--errors" ]; then
                echo "🔍 Showing errors:"
                grep -i "error\|exception\|failed\|traceback" bot.log | tail -50
            else
                tail -50 bot.log
            fi
        else
            echo "No log file found"
        fi
        ;;
    config)
        echo "⚙️ Editing configuration..."
        if [ ! -f "config.json" ]; then
            echo "Creating default config..."
            cat > config.json << CONFIG
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000
    },
    "download_dir": "downloads",
    "auto_cleanup_minutes": 2
}
CONFIG
        fi
        
        nano config.json
        echo ""
        echo "💡 Restart after changes: ./manage.sh restart"
        ;;
    test)
        echo "🔍 Testing installation..."
        source venv/bin/activate
        
        echo ""
        echo "1. Testing Python imports..."
        python3 -c "
try:
    import telegram, yt_dlp, requests, json, os
    print('✅ All imports OK')
    print(f'   • python-telegram-bot: {telegram.__version__}')
    print(f'   • yt-dlp: {yt_dlp.version.__version__}')
    print(f'   • requests: {requests.__version__}')
except Exception as e:
    print(f'❌ Import error: {e}')
    import traceback
    traceback.print_exc()
"
        
        echo ""
        echo "2. Testing configuration..."
        python3 -c "
import json, os
try:
    if os.path.exists('config.json'):
        with open('config.json') as f:
            config = json.load(f)
        
        token = config['telegram']['token']
        if token == 'YOUR_BOT_TOKEN_HERE':
            print('❌ Token not configured!')
            print('   Please edit config.json')
        else:
            print(f'✅ Token: {token[:15]}...')
        
        print(f'✅ Max file size: {config[\"telegram\"][\"max_file_size\"]}MB')
        print(f'✅ Admin users: {len(config[\"telegram\"].get(\"admin_ids\", []))}')
        
    else:
        print('❌ config.json not found!')
except Exception as e:
    print(f'❌ Config error: {e}')
"
        
        echo ""
        echo "3. Testing directories..."
        if [ -d "downloads" ]; then
            echo "✅ Downloads directory exists"
        else
            echo "⚠️ Creating downloads directory..."
            mkdir -p downloads
        fi
        
        if [ -d "venv" ]; then
            echo "✅ Virtual environment exists"
        else
            echo "❌ Virtual environment missing!"
        fi
        
        echo ""
        echo "🎯 Test complete!"
        echo "   Run: ./manage.sh start"
        echo "   Check: ./manage.sh status"
        ;;
    debug)
        echo "🐛 Starting in debug mode..."
        ./manage.sh stop 2>/dev/null
        sleep 2
        source venv/bin/activate
        echo "Running bot with debug output..."
        python bot.py
        ;;
    clean)
        echo "🧹 Cleaning cache..."
        if [ -d "downloads" ]; then
            COUNT=$(ls -1 downloads/ 2>/dev/null | wc -l)
            SIZE=$(du -sh downloads/ 2>/dev/null | cut -f1)
            rm -rf downloads/*
            mkdir -p downloads
            echo "✅ Cleaned $COUNT files ($SIZE)"
        else
            echo "✅ Downloads directory already clean"
        fi
        
        # Clear logs
        if [ "$2" = "--all" ]; then
            > bot.log 2>/dev/null || true
            echo "✅ Logs cleared"
        fi
        ;;
    uninstall)
        echo "🗑️ Uninstalling bot..."
        echo ""
        echo "⚠️  WARNING: This will remove ALL bot files!"
        echo ""
        read -p "Type 'YES' to confirm: " CONFIRM
        
        if [ "$CONFIRM" = "YES" ]; then
            ./manage.sh stop
            
            # Remove installation directory
            rm -rf /opt/quality-tg-bot
            
            # Remove from crontab
            crontab -l 2>/dev/null | grep -v "/opt/quality-tg-bot" | crontab -
            
            echo ""
            echo "✅ Bot completely uninstalled!"
            echo "📁 Removed: /opt/quality-tg-bot"
        else
            echo "❌ Uninstall cancelled"
        fi
        ;;
    autostart)
        echo "⚙️ Configuring auto-start on reboot..."
        
        # Check if already configured
        if crontab -l 2>/dev/null | grep -q "/opt/quality-tg-bot/manage.sh start"; then
            echo "✅ Auto-start already configured"
        else
            # Add to crontab
            (crontab -l 2>/dev/null; echo "@reboot cd /opt/quality-tg-bot && /opt/quality-tg-bot/manage.sh start") | crontab -
            echo "✅ Auto-start configured"
            echo "   Bot will start automatically on system reboot"
        fi
        
        echo ""
        echo "Current crontab entries:"
        crontab -l 2>/dev/null | grep -v "^#"
        ;;
    *)
        echo "🤖 Quality Download Bot Management"
        echo "================================="
        echo ""
        echo "📁 Directory: /opt/quality-tg-bot"
        echo ""
        echo "📋 Available commands:"
        echo "  start      - Start the bot"
        echo "  stop       - Stop the bot"
        echo "  restart    - Restart the bot"
        echo "  status     - Check bot status"
        echo "  logs       - View logs (-f to follow, -e for errors)"
        echo "  config     - Edit configuration"
        echo "  test       - Test installation"
        echo "  debug      - Run in debug mode"
        echo "  clean      - Clean cache files"
        echo "  uninstall  - Uninstall bot (WARNING: irreversible)"
        echo "  autostart  - Auto-start on reboot"
        echo ""
        echo "🎯 Features:"
        echo "  • YouTube quality selection with file sizes"
        echo "  • Twitter quality selection"
        echo "  • Instagram download"
        echo "  • Auto cleanup every 2 minutes"
        echo "  • Pause/Resume functionality"
        echo ""
        echo "🚀 Quick start:"
        echo "  1. ./manage.sh config    # Set your bot token"
        echo "  2. ./manage.sh start     # Start bot"
        echo "  3. ./manage.sh status    # Check status"
        echo ""
        echo "📞 Support: GitHub @2amir563"
        ;;
esac
EOF

# Set execute permission
chmod +x manage.sh

# Create requirements.txt
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
EOF

# Create cookies.txt template for Instagram
cat > cookies_template.txt << 'EOF'
# Instagram cookies file
# Get cookies from browser and paste here
# Format: netscape cookies format
# Or use browser extension to export cookies
EOF

print_green "✅ QUALITY BOT INSTALLATION COMPLETE!"
echo ""
echo "=" * 60
echo "📋 COMPLETE SETUP GUIDE"
echo "=" * 60
echo ""
echo "1. First, install the bot:"
echo "   bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)"
echo ""
echo "2. Configure the bot:"
echo "   cd /opt/quality-tg-bot"
echo "   nano config.json"
echo ""
echo "3. Replace 'YOUR_BOT_TOKEN_HERE' with your bot token"
echo "   (Get from @BotFather on Telegram)"
echo ""
echo "4. Add your Telegram ID to 'admin_ids' array"
echo "   Example: \"admin_ids\": [123456789],"
echo "   (Find your ID with @userinfobot)"
echo ""
echo "5. Set execute permission and start:"
echo "   chmod +x manage.sh"
echo "   ./manage.sh start"
echo ""
echo "6. Check status:"
echo "   ./manage.sh status"
echo ""
echo "7. Test the bot in Telegram:"
echo "   Send /start to your bot"
echo "   Send a YouTube or Twitter link"
echo "   Select quality and download!"
echo ""
echo "🔧 For Instagram (optional):"
echo "   You may need to add cookies for Instagram downloads"
echo "   Create cookies.txt file with your Instagram cookies"
echo ""
echo "📞 Support: GitHub @2amir563"
echo "=" * 60
