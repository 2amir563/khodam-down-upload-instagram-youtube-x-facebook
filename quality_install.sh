#!/bin/bash
# quality_install.sh - Install Telegram bot with quality selection
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)

set -e

echo "🎯 Installing Telegram Download Bot with Quality Selection"
echo "=========================================================="

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
apt-get install -y python3 python3-pip python3-venv git curl wget ffmpeg nano cron

# Step 3: Create virtual environment
print_blue "3. Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Step 4: Install Python packages
print_blue "4. Installing Python packages..."
pip install --upgrade pip
pip install python-telegram-bot==20.7 yt-dlp==2025.11.12 requests==2.32.5 tqdm

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
5. Working hours control
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
import mimetypes
import re

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
        self.active_hours = self.config.get('active_hours', {})
        
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
            'auto_cleanup_minutes': 2,
            'active_hours': {
                'enabled': False,
                'start': 9,
                'end': 22
            }
        }
        
        with open(config_file, 'w', encoding='utf-8') as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        
        return config
    
    def check_active_hours(self):
        """Check if bot should be active based on hours"""
        if not self.active_hours.get('enabled', False):
            return True
        
        current_hour = datetime.now().hour
        start = self.active_hours.get('start', 9)
        end = self.active_hours.get('end', 22)
        
        if start <= end:
            return start <= current_hour <= end
        else:
            return current_hour >= start or current_hour <= end
    
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
        elif 'reddit.com' in url_lower:
            return 'reddit'
        else:
            return 'generic'
    
    async def get_video_formats(self, url, platform):
        """Get available formats with sizes"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
            }
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                
                formats = []
                
                if platform == 'instagram':
                    # Instagram special handling
                    return self.get_instagram_formats(info)
                
                if 'formats' in info:
                    for fmt in info['formats']:
                        if not fmt.get('filesize'):
                            # Try to estimate size
                            if fmt.get('tbr'):
                                # Estimate: tbr * duration / 8 bits per byte
                                duration = info.get('duration', 60)
                                estimated_size = (fmt['tbr'] * duration * 1000) / (8 * 1024 * 1024)  # MB
                                fmt['filesize'] = estimated_size * 1024 * 1024
                            else:
                                continue
                        
                        # Skip audio-only for video selection
                        if fmt.get('vcodec') == 'none' and fmt.get('acodec') != 'none':
                            continue
                        
                        resolution = fmt.get('resolution', 'N/A')
                        if resolution == 'audio only':
                            continue
                        
                        format_note = fmt.get('format_note', '')
                        if not format_note and resolution != 'N/A':
                            format_note = resolution
                        
                        # Skip weird formats
                        if 'storyboard' in str(format_note).lower():
                            continue
                        
                        # Calculate size
                        size_mb = fmt['filesize'] / (1024 * 1024)
                        max_size = self.config['telegram']['max_file_size']
                        
                        if size_mb > max_size:
                            continue
                        
                        format_id = fmt.get('format_id', 'best')
                        ext = fmt.get('ext', 'mp4')
                        
                        # Clean up resolution display
                        if resolution == 'N/A':
                            if format_note:
                                resolution_display = format_note
                            else:
                                resolution_display = 'Unknown'
                        else:
                            resolution_display = resolution
                        
                        formats.append({
                            'format_id': format_id,
                            'resolution': resolution,
                            'format_note': format_note,
                            'ext': ext,
                            'filesize_mb': round(size_mb, 1),
                            'quality': f"{resolution_display} - {size_mb:.1f}MB",
                            'vcodec': fmt.get('vcodec', 'unknown')
                        })
                
                # Remove duplicates and sort by quality
                unique_formats = []
                seen = set()
                for fmt in formats:
                    key = (fmt['resolution'], round(fmt['filesize_mb'], 1))
                    if key not in seen:
                        seen.add(key)
                        unique_formats.append(fmt)
                
                # Sort by resolution (highest first)
                def sort_key(fmt):
                    res = fmt['resolution']
                    if res == 'N/A':
                        return (0, 0)
                    if 'x' in res:
                        try:
                            w, h = map(int, res.split('x'))
                            return (-h, -fmt['filesize_mb'])
                        except:
                            return (0, -fmt['filesize_mb'])
                    return (0, -fmt['filesize_mb'])
                
                unique_formats.sort(key=sort_key)
                
                return unique_formats[:8]  # Return top 8 formats
                
        except Exception as e:
            logger.error(f"Error getting formats for {platform}: {e}")
            return []
    
    def get_instagram_formats(self, info):
        """Extract Instagram formats"""
        formats = []
        
        try:
            # Instagram often has multiple formats
            if 'formats' in info:
                for fmt in info['formats']:
                    if fmt.get('format_id') in ['0', '1', '2']:
                        size_mb = fmt.get('filesize', 0) / (1024 * 1024) if fmt.get('filesize') else 0
                        if size_mb == 0 and fmt.get('tbr'):
                            duration = info.get('duration', 30)
                            size_mb = (fmt['tbr'] * duration * 1000) / (8 * 1024 * 1024)
                        
                        formats.append({
                            'format_id': fmt['format_id'],
                            'resolution': fmt.get('resolution', 'Unknown'),
                            'format_note': fmt.get('format_note', 'Instagram'),
                            'ext': fmt.get('ext', 'mp4'),
                            'filesize_mb': round(size_mb, 1),
                            'quality': f"{fmt.get('format_note', 'Instagram')} - {size_mb:.1f}MB"
                        })
            
            # If no formats found, create default options
            if not formats:
                duration = info.get('duration', 30)
                default_sizes = [
                    ('best', 'Best Quality', 5),
                    ('worst', 'Lowest Quality', 1)
                ]
                
                for fmt_id, name, multiplier in default_sizes:
                    formats.append({
                        'format_id': fmt_id,
                        'resolution': 'Unknown',
                        'format_note': name,
                        'ext': 'mp4',
                        'filesize_mb': round(duration * multiplier, 1),
                        'quality': f"{name} - {duration * multiplier:.1f}MB"
                    })
            
            return formats
            
        except Exception as e:
            logger.error(f"Error processing Instagram formats: {e}")
            return []
    
    def create_quality_keyboard(self, formats, platform, url):
        """Create keyboard for quality selection"""
        keyboard = []
        
        if platform in ['youtube', 'twitter', 'instagram'] and formats:
            for fmt in formats:
                quality_label = fmt['quality']
                if len(quality_label) > 40:
                    quality_label = quality_label[:37] + "..."
                
                callback_data = f"dl_{platform}_{fmt['format_id']}_{hash(url) % 10000}"
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
                        callback_data=f"dl_{platform}_bestaudio_{hash(url) % 10000}"
                    )
                ])
        else:
            # Default options if no formats
            keyboard.append([
                InlineKeyboardButton("📹 Best Quality", callback_data=f"dl_generic_best_{hash(url) % 10000}")
            ])
        
        # Add cancel button
        keyboard.append([
            InlineKeyboardButton("❌ Cancel", callback_data="cancel")
        ])
        
        return InlineKeyboardMarkup(keyboard)
    
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        # Check if bot is paused
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        # Check active hours
        if not self.check_active_hours():
            start_hour = self.active_hours.get('start', 9)
            end_hour = self.active_hours.get('end', 22)
            await update.message.reply_text(
                f"⏰ Bot is only active from {start_hour}:00 to {end_hour}:00\n"
                f"Current time: {datetime.now().strftime('%H:%M')}"
            )
            return
        
        welcome = f"""
👋 Hello {user.first_name}!

🤖 **Telegram Download Bot with Quality Selection**

📥 **Supported Platforms:**
✅ YouTube - Choose quality with file size
✅ Instagram - Multiple quality options
✅ Twitter/X - Best available quality
✅ TikTok  
✅ Facebook
✅ Direct files - Keeps original format

🎯 **How to use:**
1. Send YouTube/Instagram link → Choose quality
2. Send Twitter/TikTok link → Auto download
3. Send direct file → Keeps original format

⚡ **Features:**
• Quality selection for YouTube/Instagram
• Shows file size for each quality
• Auto cleanup every 2 minutes
• Pause/Resume bot
• Working hours control
• Preserves original file formats

🛠️ **Admin Commands:**
/start - This menu
/help - Detailed help
/status - Bot status
/pause [hours] - Pause bot
/resume - Resume bot
/clean - Clean files
/sethours [start] [end] - Set working hours

💡 **Files auto deleted after 2 minutes**
"""
        
        await update.message.reply_text(welcome, parse_mode='Markdown')
        logger.info(f"User {user.id} started bot")
    
    async def handle_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle text messages"""
        # Check if bot is paused
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            await update.message.reply_text(
                f"⏸️ Bot is paused\nWill resume in: {hours}h {minutes}m"
            )
            return
        
        # Check active hours
        if not self.check_active_hours():
            start_hour = self.active_hours.get('start', 9)
            end_hour = self.active_hours.get('end', 22)
            await update.message.reply_text(
                f"⏰ Bot is only active from {start_hour}:00 to {end_hour}:00"
            )
            return
        
        text = update.message.text.strip()
        user = update.effective_user
        
        logger.info(f"Message from {user.first_name}: {text[:50]}")
        
        if text.startswith(('http://', 'https://')):
            platform = self.detect_platform(text)
            
            # Save URL and platform for callback
            context.user_data['last_url'] = text
            context.user_data['last_platform'] = platform
            
            if platform in ['youtube', 'instagram']:
                # Show quality selection for YouTube and Instagram
                await update.message.reply_text(f"🔍 Getting available qualities from {platform}...")
                formats = await self.get_video_formats(text, platform)
                
                if formats:
                    info_text = f"📹 **{platform.capitalize()} Video**\n\n"
                    info_text += "🎬 **Available Qualities:**\n"
                    
                    for i, fmt in enumerate(formats[:5], 1):
                        info_text += f"{i}. {fmt['quality']}\n"
                    
                    if len(formats) > 5:
                        info_text += f"... and {len(formats) - 5} more\n"
                    
                    await update.message.reply_text(info_text, parse_mode='Markdown')
                    
                    keyboard = self.create_quality_keyboard(formats, platform, text)
                    await update.message.reply_text(
                        "👇 Select quality:",
                        reply_markup=keyboard
                    )
                    
                else:
                    # Fallback if no formats
                    await update.message.reply_text("📥 Downloading with best quality...")
                    await self.download_media(update, text, 'best', platform, update.message)
            
            else:
                # Other platforms: Twitter, TikTok, Facebook, etc.
                await update.message.reply_text(f"📥 Downloading from {platform}...")
                await self.download_media(update, text, 'best', platform, update.message)
        
        else:
            await update.message.reply_text(
                "Please send a valid URL starting with http:// or https://\n\n"
                "🌟 **Special:** YouTube/Instagram links show quality options!"
            )
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle callback queries"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ Download cancelled.")
            return
        
        if data.startswith('dl_'):
            # Parse callback data: dl_platform_format_id_hash
            parts = data.split('_')
            if len(parts) >= 3:
                platform = parts[1]
                format_id = parts[2]
                
                url = context.user_data.get('last_url')
                if not url:
                    await query.edit_message_text("❌ URL not found!")
                    return
                
                await query.edit_message_text(f"⏳ Downloading {platform}...")
                await self.download_media(update, url, format_id, platform, query)
    
    async def download_media(self, update: Update, url, format_spec, platform, source=None):
        """Download media with specific format"""
        try:
            msg = None
            if hasattr(source, 'edit_message_text'):
                # From callback query
                msg = source
                chat_id = msg.message.chat_id
            else:
                # From message
                msg = source
                chat_id = msg.chat_id
            
            # Prepare download options
            ydl_opts = {
                'format': format_spec,
                'quiet': False,
                'outtmpl': str(self.download_dir / f'%(id)s_%(title).100s.%(ext)s'),
                'progress_hooks': [self.create_progress_hook(update, msg)],
                'http_headers': {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            }
            
            # Platform-specific options
            if platform == 'instagram':
                ydl_opts['cookiefile'] = 'cookies.txt'
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # Check if file exists (yt-dlp might change extension)
                actual_filename = None
                base_name = os.path.splitext(filename)[0]
                
                for ext in ['.mp4', '.mkv', '.webm', '.m4a', '.mp3', '.flv', '.avi']:
                    if os.path.exists(base_name + ext):
                        actual_filename = base_name + ext
                        break
                
                if not actual_filename and os.path.exists(filename):
                    actual_filename = filename
                
                if actual_filename and os.path.exists(actual_filename):
                    file_size = os.path.getsize(actual_filename) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(actual_filename)
                        error_msg = f"❌ File too large: {file_size:.1f}MB (max: {max_size}MB)"
                        if hasattr(msg, 'edit_message_text'):
                            await msg.edit_message_text(error_msg)
                        else:
                            await update.message.reply_text(error_msg)
                        return
                    
                    # Send file
                    await self.send_telegram_file(update, actual_filename, info, msg)
                    
                    # Schedule deletion
                    self.schedule_file_deletion(actual_filename)
                    
                else:
                    error_msg = "❌ File not found after download"
                    if hasattr(msg, 'edit_message_text'):
                        await msg.edit_message_text(error_msg)
                    else:
                        await update.message.reply_text(error_msg)
                        
        except Exception as e:
            logger.error(f"Download error: {e}", exc_info=True)
            error_msg = f"❌ Error: {str(e)[:200]}"
            if hasattr(msg, 'edit_message_text'):
                await msg.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
    
    def create_progress_hook(self, update, msg):
        """Create progress hook for yt-dlp"""
        last_update = [0]
        
        def hook(d):
            if d['status'] == 'downloading':
                percent = d.get('_percent_str', '0%').strip()
                speed = d.get('_speed_str', 'N/A')
                eta = d.get('_eta_str', 'N/A')
                
                # Only update every 5% to avoid rate limiting
                try:
                    percent_num = float(percent.replace('%', ''))
                    if percent_num - last_update[0] >= 5:
                        progress_msg = f"⏬ Downloading... {percent}\nSpeed: {speed}\nETA: {eta}"
                        
                        # Try to update message (in background)
                        asyncio.run_coroutine_threadsafe(
                            self.update_progress(msg, progress_msg),
                            asyncio.get_event_loop()
                        )
                        last_update[0] = percent_num
                except:
                    pass
        
        return hook
    
    async def update_progress(self, msg, text):
        """Update progress message"""
        try:
            if hasattr(msg, 'edit_message_text'):
                await msg.edit_message_text(text[:200])
        except:
            pass  # Ignore errors
    
    async def send_telegram_file(self, update, filepath, info, msg=None):
        """Send file to Telegram with appropriate method"""
        try:
            file_size = os.path.getsize(filepath) / (1024 * 1024)
            title = info.get('title', os.path.basename(filepath))
            duration = info.get('duration', 0)
            
            caption = f"📹 {title[:100]}\n"
            caption += f"📊 Size: {file_size:.1f}MB"
            if duration > 0:
                caption += f" | ⏱️ {duration//60}:{duration%60:02d}"
            
            with open(filepath, 'rb') as f:
                # Determine file type
                if filepath.endswith(('.mp3', '.m4a', '.opus', '.flac')):
                    await update.message.reply_audio(
                        audio=f,
                        caption=caption,
                        title=title[:64],
                        duration=int(duration) if duration else None
                    )
                elif filepath.endswith(('.mp4', '.mkv', '.webm', '.mov', '.avi')):
                    await update.message.reply_video(
                        video=f,
                        caption=caption,
                        duration=int(duration) if duration else None,
                        supports_streaming=True
                    )
                elif filepath.endswith(('.jpg', '.jpeg', '.png', '.gif', '.webp')):
                    await update.message.reply_photo(
                        photo=f,
                        caption=caption
                    )
                else:
                    await update.message.reply_document(
                        document=f,
                        caption=caption
                    )
            
            success_msg = f"✅ Download complete!\n📁 {title[:50]}\n💾 {file_size:.1f}MB"
            
            if hasattr(msg, 'edit_message_text'):
                await msg.edit_message_text(success_msg)
            else:
                await update.message.reply_text(success_msg)
                
        except TelegramError as e:
            logger.error(f"Telegram error: {e}")
            error_msg = f"❌ Telegram error: {str(e)[:100]}"
            if hasattr(msg, 'edit_message_text'):
                await msg.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
        except Exception as e:
            logger.error(f"Error sending file: {e}")
            error_msg = f"❌ Error sending file: {str(e)[:100]}"
            if hasattr(msg, 'edit_message_text'):
                await msg.edit_message_text(error_msg)
            else:
                await update.message.reply_text(error_msg)
    
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
    
    # Admin commands
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        await update.message.reply_text(
            "📖 **Help**\n\n"
            "Send YouTube/Instagram link → Choose quality with file size\n"
            "Send Twitter/TikTok/Facebook link → Auto download\n"
            "Send direct file → Keeps original format\n\n"
            "Files auto deleted after 2 minutes\n\n"
            "🛠️ **Admin Commands:**\n"
            "/status - Bot status\n"
            "/pause [hours] - Pause bot\n"
            "/resume - Resume bot\n"
            "/clean - Clean files\n"
            "/sethours [start] [end] - Set working hours\n"
            "/logs - View logs",
            parse_mode='Markdown'
        )
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        files = list(self.download_dir.glob('*'))
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        status_text = f"📊 **Bot Status**\n\n"
        status_text += f"✅ Bot: {'Active' if not self.is_paused else 'Paused'}\n"
        
        if self.is_paused and self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            status_text += f"⏸️ Paused for: {hours}h {minutes}m\n"
        
        if self.active_hours.get('enabled', False):
            start = self.active_hours.get('start', 9)
            end = self.active_hours.get('end', 22)
            status_text += f"⏰ Active hours: {start}:00 - {end}:00\n"
        
        status_text += f"📁 Files in cache: {len(files)}\n"
        status_text += f"💾 Cache size: {total_size:.1f}MB\n"
        status_text += f"👤 Your ID: {user.id}\n"
        status_text += f"🤖 Platform: {self.detect_platform.__name__}"
        
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        hours = 1
        if context.args:
            try:
                hours = int(context.args[0])
                if hours < 1 or hours > 720:  # Max 30 days
                    hours = 1
            except:
                hours = 1
        
        self.is_paused = True
        self.paused_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸️ Bot paused for {hours} hour(s)\n"
            f"⏰ Resume at: {self.paused_until.strftime('%Y-%m-%d %H:%M')}\n\n"
            f"Use /resume to resume earlier"
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
        
        await update.message.reply_text(f"🧹 Cleaned {count} files ({total_size:.1f}MB)")
    
    async def sethours_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        if len(context.args) >= 2:
            try:
                start = int(context.args[0])
                end = int(context.args[1])
                
                if 0 <= start <= 23 and 0 <= end <= 23:
                    self.active_hours = {
                        'enabled': True,
                        'start': start,
                        'end': end
                    }
                    
                    # Save to config
                    self.config['active_hours'] = self.active_hours
                    with open('config.json', 'w') as f:
                        json.dump(self.config, f, indent=4)
                    
                    await update.message.reply_text(
                        f"✅ Active hours set to {start}:00 - {end}:00\n"
                        f"Bot will only work during these hours"
                    )
                else:
                    await update.message.reply_text("❌ Hours must be between 0-23")
            except ValueError:
                await update.message.reply_text("❌ Invalid hours. Use: /sethours 9 22")
        else:
            # Toggle on/off
            self.active_hours['enabled'] = not self.active_hours.get('enabled', False)
            await update.message.reply_text(
                f"✅ Active hours {'enabled' if self.active_hours['enabled'] else 'disabled'}"
            )
    
    async def logs_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        user = update.effective_user
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("⛔ Admin only!")
            return
        
        try:
            with open('bot.log', 'r') as f:
                lines = f.readlines()
                last_lines = lines[-20:]  # Last 20 lines
                log_text = ''.join(last_lines)
                
                if len(log_text) > 4000:
                    log_text = "...\n" + log_text[-4000:]
                
                await update.message.reply_text(f"📝 Last 20 log lines:\n```\n{log_text}\n```", parse_mode='MarkdownV2')
        except Exception as e:
            await update.message.reply_text(f"❌ Error reading logs: {e}")
    
    def run(self):
        """Run the bot"""
        print("=" * 50)
        print("🤖 Telegram Download Bot with Quality Selection")
        print("=" * 50)
        
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Configure token in config.json")
            print("Edit config.json and add your bot token")
            print(f"File: {os.path.abspath('config.json')}")
            return
        
        print(f"✅ Token: {self.token[:15]}...")
        print(f"✅ Admins: {len(self.admin_ids)}")
        print(f"✅ Max file size: {self.config['telegram']['max_file_size']}MB")
        
        if self.active_hours.get('enabled', False):
            print(f"✅ Active hours: {self.active_hours.get('start')}:00 - {self.active_hours.get('end')}:00")
        
        print("✅ Bot ready!")
        print("📱 Send YouTube/Instagram link to test quality selection")
        print("=" * 50)
        
        # Create application
        app = Application.builder().token(self.token).build()
        
        # Add handlers
        app.add_handler(CommandHandler("start", self.start_command))
        app.add_handler(CommandHandler("help", self.help_command))
        app.add_handler(CommandHandler("status", self.status_command))
        app.add_handler(CommandHandler("pause", self.pause_command))
        app.add_handler(CommandHandler("resume", self.resume_command))
        app.add_handler(CommandHandler("clean", self.clean_command))
        app.add_handler(CommandHandler("sethours", self.sethours_command))
        app.add_handler(CommandHandler("logs", self.logs_command))
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_message))
        app.add_handler(CallbackQueryHandler(self.handle_callback))
        
        # Run bot
        app.run_polling()

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
    "auto_cleanup_minutes": 2,
    "active_hours": {
        "enabled": false,
        "start": 9,
        "end": 22
    }
}
EOF

# Step 7: Create management script
print_blue "7. Creating management script..."
cat > manage.sh << 'EOF'
#!/bin/bash
# manage.sh - Quality bot management
# Working directory
INSTALL_DIR="/opt/quality-tg-bot"

cd "$INSTALL_DIR"

case "$1" in
    start)
        echo "🚀 Starting Quality Download Bot..."
        source venv/bin/activate
        
        # Clean old logs
        > bot.log
        
        # Check if bot is already running
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "⚠️ Bot already running (PID: $(cat bot.pid))"
            exit 1
        fi
        
        # Start bot in background
        nohup python bot.py >> bot.log 2>&1 &
        PID=$!
        echo $PID > bot.pid
        
        echo "✅ Bot started (PID: $PID)"
        echo "📝 Logs: tail -f bot.log"
        echo ""
        echo "🎯 Features enabled:"
        echo "   • Quality selection for YouTube/Instagram"
        echo "   • Shows file sizes for each quality"
        echo "   • Twitter/TikTok/Facebook support"
        echo "   • Preserves original file formats"
        echo "   • Auto cleanup every 2 minutes"
        echo "   • Pause/Resume functionality"
        echo "   • Working hours control"
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
                fi
                echo "✅ Bot stopped (PID: $PID)"
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
            echo "✅ Bot running (PID: $PID)"
            
            # Check config
            if [ -f "config.json" ]; then
                TOKEN=$(grep -o '"token": "[^"]*"' config.json | cut -d'"' -f4)
                if [ "$TOKEN" = "YOUR_BOT_TOKEN_HERE" ]; then
                    echo "❌ Token not configured!"
                else
                    echo "✅ Token configured: ${TOKEN:0:15}..."
                fi
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
            
            # Show download directory
            if [ -d "downloads" ]; then
                COUNT=$(ls -1 downloads/ 2>/dev/null | wc -l)
                SIZE=$(du -sh downloads/ 2>/dev/null | cut -f1)
                echo "📁 Downloads: $COUNT files ($SIZE)"
            fi
        else
            echo "❌ Bot not running"
            [ -f "bot.pid" ] && rm -f bot.pid
        fi
        ;;
    logs)
        echo "📝 Bot logs:"
        echo "============"
        if [ -f "bot.log" ]; then
            if [ "$2" = "-f" ] || [ "$2" = "--follow" ]; then
                tail -f bot.log
            elif [ "$2" = "-e" ] || [ "$2" = "--errors" ]; then
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
    "auto_cleanup_minutes": 2,
    "active_hours": {
        "enabled": false,
        "start": 9,
        "end": 22
    }
}
CONFIG
        fi
        
        nano config.json
        echo ""
        echo "💡 Changes require restart: ./manage.sh restart"
        ;;
    test)
        echo "🔍 Testing installation..."
        source venv/bin/activate
        
        echo ""
        echo "1. Testing Python imports..."
        python3 -c "
try:
    import telegram, yt_dlp, requests, json, os, asyncio
    print('✅ All imports OK')
    print(f'   yt-dlp: {yt_dlp.version.__version__}')
    print(f'   telegram: {telegram.__version__}')
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
            print('   Edit config.json and add your bot token')
        else:
            print(f'✅ Token: {token[:15]}...')
        
        max_size = config['telegram']['max_file_size']
        print(f'✅ Max file size: {max_size}MB')
        
        admins = config['telegram'].get('admin_ids', [])
        print(f'✅ Admins: {len(admins)} users')
        
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
        echo "📋 Test summary:"
        echo "   Run: ./manage.sh start"
        echo "   Check: ./manage.sh status"
        echo "   View logs: ./manage.sh logs"
        ;;
    debug)
        echo "🐛 Starting bot in debug mode..."
        ./manage.sh stop
        sleep 2
        source venv/bin/activate
        echo "Starting bot with debug output..."
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
        
        # Clean logs
        if [ -f "bot.log" ]; then
            > bot.log
            echo "✅ Logs cleared"
        fi
        ;;
    update)
        echo "🔄 Updating bot..."
        ./manage.sh stop
        cd /tmp
        
        echo "Downloading latest version..."
        wget -q https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh -O update.sh
        bash update.sh
        
        echo "✅ Update complete!"
        echo "Restart bot: ./manage.sh start"
        ;;
    uninstall)
        echo "🗑️ Uninstalling bot..."
        echo ""
        echo "⚠️  WARNING: This will remove all bot files!"
        echo ""
        read -p "Type 'UNINSTALL' to confirm: " confirm
        
        if [ "$confirm" = "UNINSTALL" ]; then
            ./manage.sh stop
            cd /
            
            # Remove installation directory
            rm -rf "$INSTALL_DIR"
            
            # Remove from crontab
            crontab -l 2>/dev/null | grep -v "$INSTALL_DIR" | crontab -
            
            echo ""
            echo "✅ Bot uninstalled successfully!"
            echo "All files removed from $INSTALL_DIR"
        else
            echo "❌ Uninstall cancelled"
        fi
        ;;
    autostart)
        echo "⚙️ Configuring auto-start on reboot..."
        
        # Check if already in crontab
        if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/manage.sh start"; then
            echo "✅ Auto-start already configured"
        else
            # Add to crontab
            (crontab -l 2>/dev/null; echo "@reboot cd $INSTALL_DIR && $INSTALL_DIR/manage.sh start") | crontab -
            echo "✅ Auto-start configured"
            echo "   Bot will start automatically on system reboot"
        fi
        
        echo ""
        echo "Current crontab:"
        crontab -l 2>/dev/null | grep -v "^#"
        ;;
    backup)
        echo "💾 Creating backup..."
        BACKUP_DIR="/tmp/quality-bot-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        # Copy important files
        cp -r config.json bot.py manage.sh requirements.txt "$BACKUP_DIR/" 2>/dev/null
        
        echo "✅ Backup created in: $BACKUP_DIR"
        echo "Files:"
        ls -la "$BACKUP_DIR/"
        ;;
    *)
        echo "🤖 Quality Download Bot Management"
        echo "================================="
        echo ""
        echo "📁 Directory: $INSTALL_DIR"
        echo ""
        echo "📋 Available commands:"
        echo "  start       - Start the bot"
        echo "  stop        - Stop the bot"
        echo "  restart     - Restart the bot"
        echo "  status      - Check bot status"
        echo "  logs        - View logs (-f to follow, -e for errors)"
        echo "  config      - Edit configuration"
        echo "  test        - Test installation"
        echo "  debug       - Run in debug mode"
        echo "  clean       - Clean cache files"
        echo "  update      - Update bot to latest version"
        echo "  uninstall   - Uninstall bot (WARNING: irreversible)"
        echo "  autostart   - Configure auto-start on reboot"
        echo "  backup      - Create backup"
        echo ""
        echo "🎯 Features:"
        echo "  • Quality selection for YouTube/Instagram"
        echo "  • File size display for each quality"
        echo "  • Twitter/TikTok/Facebook support"
        echo "  • Direct file download (preserves format)"
        echo "  • Auto cleanup (2 minutes)"
        echo "  • Pause/Resume functionality"
        echo "  • Working hours control"
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

chmod +x manage.sh

# Step 8: Create requirements.txt
print_blue "8. Creating requirements.txt..."
cat > requirements.txt << 'EOF'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
tqdm==4.66.5
EOF

# Step 9: Create README
print_blue "9. Creating README.md..."
cat > README.md << 'EOF'
# Telegram Download Bot with Quality Selection 🤖

A powerful Telegram bot that downloads media from various platforms with quality selection support.

## 🌟 Features

- **Quality Selection**: Choose different qualities for YouTube & Instagram
- **File Size Display**: See file size for each quality before downloading
- **Multi-Platform Support**:
  - YouTube (quality selection)
  - Instagram (quality selection)
  - Twitter/X
  - TikTok
  - Facebook
  - Direct files (preserves original format)
- **Auto Cleanup**: Files automatically deleted after 2 minutes
- **Pause/Resume**: Temporarily disable the bot
- **Working Hours**: Set specific hours when bot should be active
- **Admin Controls**: Manage bot with various commands

## 🚀 Installation

### One-line Install (Recommended)
```bash
bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)
