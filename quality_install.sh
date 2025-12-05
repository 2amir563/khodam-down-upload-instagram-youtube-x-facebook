#!/bin/bash
# Telegram Download Bot with Quality Selection - One-command Installer
# Run: bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)

set -e

echo "===================================================================="
echo "🤖 Telegram Download Bot with Quality Selection - INSTALLER"
echo "===================================================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}→${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Installation directory
INSTALL_DIR="/opt/quality-tg-bot"

# Step 1: Cleanup old installation
print_info "Step 1: Cleaning previous installation..."
if [ -d "$INSTALL_DIR" ]; then
    print_warning "Found existing installation at $INSTALL_DIR"
    if [ -f "$INSTALL_DIR/manage.sh" ]; then
        cd "$INSTALL_DIR"
        ./manage.sh stop 2>/dev/null || true
    fi
    rm -rf "$INSTALL_DIR" 2>/dev/null || true
    print_success "Old installation cleaned"
fi

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Step 2: Install system dependencies
print_info "Step 2: Installing system dependencies..."
apt-get update -y

# Install required packages
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    wget \
    ffmpeg \
    nano \
    cron \
    git \
    psmisc \
    tree

print_success "System dependencies installed"

# Step 3: Create virtual environment
print_info "Step 3: Setting up Python environment..."
python3 -m venv venv
source venv/bin/activate

# Step 4: Install Python packages
print_info "Step 4: Installing Python packages..."
pip install --upgrade pip
pip install --no-cache-dir \
    python-telegram-bot==20.7 \
    yt-dlp==2025.11.12 \
    requests==2.32.5 \
    tqdm==4.66.5

print_success "Python packages installed"

# Step 5: Create main bot file
print_info "Step 5: Creating bot files..."

# Create bot.py
cat > bot.py << 'BOTPY'
#!/usr/bin/env python3
"""
Telegram Download Bot with Quality Selection
Support: YouTube, Instagram, Twitter/X, TikTok, Facebook, Direct files
Author: @2amir563
GitHub: https://github.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook
"""

import os
import json
import logging
import asyncio
import threading
import time
import re
from datetime import datetime, timedelta
from pathlib import Path
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes
from telegram.error import TelegramError, NetworkError
import yt_dlp
import requests

# ==================== CONFIGURATION ====================
CONFIG_FILE = 'config.json'
LOG_FILE = 'bot.log'

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class TelegramDownloadBot:
    def __init__(self):
        self.config = self.load_config()
        self.token = self.config['telegram']['token']
        self.admin_ids = self.config['telegram'].get('admin_ids', [])
        
        # Bot states
        self.is_paused = False
        self.paused_until = None
        self.active_hours = self.config.get('active_hours', {})
        
        # Create download directory
        self.download_dir = Path(self.config.get('download_dir', 'downloads'))
        self.download_dir.mkdir(exist_ok=True)
        
        # User sessions
        self.user_sessions = {}
        
        # Start cleanup thread
        self.start_cleanup_thread()
        
        logger.info("🤖 Telegram Download Bot Initialized")
        print(f"📱 Bot Token: {self.token[:15]}...")
        print(f"📁 Download Dir: {self.download_dir}")
    
    def load_config(self):
        """Load or create configuration"""
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                logger.error(f"Error loading config: {e}")
        
        # Default configuration
        default_config = {
            'telegram': {
                'token': 'YOUR_BOT_TOKEN_HERE',
                'admin_ids': [],
                'max_file_size': 2000,
                'download_timeout': 300
            },
            'download_dir': 'downloads',
            'cleanup_minutes': 2,
            'active_hours': {
                'enabled': False,
                'start': 9,
                'end': 22
            },
            'rate_limit': {
                'enabled': True,
                'requests_per_minute': 10
            }
        }
        
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(default_config, f, indent=4, ensure_ascii=False)
        
        return default_config
    
    def save_config(self):
        """Save configuration to file"""
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(self.config, f, indent=4, ensure_ascii=False)
    
    def start_cleanup_thread(self):
        """Start background cleanup thread"""
        def cleanup_worker():
            while True:
                try:
                    self.cleanup_old_files()
                    time.sleep(60)  # Check every minute
                except Exception as e:
                    logger.error(f"Cleanup error: {e}")
                    time.sleep(60)
        
        thread = threading.Thread(target=cleanup_worker, daemon=True)
        thread.start()
        logger.info("🧹 Auto cleanup thread started")
    
    def cleanup_old_files(self):
        """Remove files older than configured minutes"""
        cleanup_minutes = self.config.get('cleanup_minutes', 2)
        cutoff_time = time.time() - (cleanup_minutes * 60)
        deleted_count = 0
        
        for file_path in self.download_dir.glob('*'):
            if file_path.is_file():
                try:
                    if file_path.stat().st_mtime < cutoff_time:
                        file_path.unlink()
                        deleted_count += 1
                except Exception as e:
                    logger.error(f"Failed to delete {file_path}: {e}")
        
        if deleted_count > 0:
            logger.info(f"Cleaned {deleted_count} old files")
    
    # ==================== PLATFORM DETECTION ====================
    def detect_platform(self, url):
        """Detect which platform the URL belongs to"""
        url_lower = url.lower()
        
        platform_patterns = {
            'youtube': ['youtube.com', 'youtu.be'],
            'instagram': ['instagram.com', 'instagr.am'],
            'twitter': ['twitter.com', 'x.com', 't.co'],
            'tiktok': ['tiktok.com', 'vt.tiktok.com'],
            'facebook': ['facebook.com', 'fb.com', 'fb.watch'],
            'reddit': ['reddit.com', 'redd.it'],
            'pinterest': ['pinterest.com', 'pin.it'],
            'linkedin': ['linkedin.com']
        }
        
        for platform, patterns in platform_patterns.items():
            for pattern in patterns:
                if pattern in url_lower:
                    return platform
        
        return 'generic'
    
    # ==================== FORMAT EXTRACTION ====================
    async def get_available_formats(self, url, platform):
        """Get available formats with sizes for a URL"""
        try:
            ydl_opts = {
                'quiet': True,
                'no_warnings': True,
                'extract_flat': False,
                'socket_timeout': 30,
                'http_headers': {
                    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
                }
            }
            
            # Platform-specific options
            if platform == 'instagram':
                ydl_opts['cookiefile'] = 'cookies.txt'
            
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                formats = []
                
                if 'formats' in info:
                    for fmt in info['formats']:
                        # Skip audio-only for video selection
                        if fmt.get('vcodec') == 'none' and fmt.get('acodec') != 'none':
                            continue
                        
                        # Skip storyboards
                        if 'storyboard' in str(fmt.get('format_note', '')).lower():
                            continue
                        
                        # Get file size
                        filesize = fmt.get('filesize')
                        if not filesize and fmt.get('tbr') and info.get('duration'):
                            # Estimate size: bitrate * duration
                            duration = info.get('duration', 60)
                            filesize = (fmt['tbr'] * 1000 * duration) / 8  # Bytes
                        
                        if not filesize:
                            continue
                        
                        size_mb = filesize / (1024 * 1024)
                        max_size = self.config['telegram']['max_file_size']
                        
                        if size_mb > max_size:
                            continue
                        
                        # Format details
                        resolution = fmt.get('resolution', 'N/A')
                        format_note = fmt.get('format_note', '')
                        ext = fmt.get('ext', 'mp4')
                        format_id = fmt.get('format_id', 'best')
                        
                        # Create display label
                        if resolution == 'N/A' and format_note:
                            quality_label = format_note
                        elif resolution != 'N/A':
                            quality_label = resolution
                        else:
                            quality_label = 'Unknown'
                        
                        formats.append({
                            'format_id': format_id,
                            'quality': quality_label,
                            'resolution': resolution,
                            'ext': ext,
                            'size_mb': round(size_mb, 1),
                            'format_note': format_note,
                            'vcodec': fmt.get('vcodec'),
                            'acodec': fmt.get('acodec')
                        })
                
                # Sort by quality (highest first)
                def sort_key(f):
                    res = f['resolution']
                    if res == 'N/A':
                        return (0, -f['size_mb'])
                    if 'x' in res:
                        try:
                            w, h = map(int, res.split('x'))
                            return (-h, -w, -f['size_mb'])
                        except:
                            return (0, -f['size_mb'])
                    return (0, -f['size_mb'])
                
                formats.sort(key=sort_key)
                
                # Remove duplicates
                unique_formats = []
                seen = set()
                for f in formats:
                    key = (f['quality'], f['size_mb'])
                    if key not in seen:
                        seen.add(key)
                        unique_formats.append(f)
                
                return unique_formats[:6]  # Return top 6 formats
        
        except Exception as e:
            logger.error(f"Error getting formats: {e}")
            return []
    
    # ==================== KEYBOARD CREATION ====================
    def create_quality_keyboard(self, formats, platform, url_hash):
        """Create inline keyboard for quality selection"""
        keyboard = []
        
        if formats:
            for fmt in formats:
                label = f"📹 {fmt['quality']} - {fmt['size_mb']}MB"
                if len(label) > 30:
                    label = label[:27] + "..."
                
                callback_data = f"dl_{platform}_{fmt['format_id']}_{url_hash}"
                keyboard.append([InlineKeyboardButton(label, callback_data=callback_data)])
        
        # Add audio option for YouTube
        if platform == 'youtube':
            keyboard.append([
                InlineKeyboardButton("🎵 MP3 Audio Only", callback_data=f"dl_{platform}_bestaudio_{url_hash}")
            ])
        
        # Add cancel button
        keyboard.append([InlineKeyboardButton("❌ Cancel", callback_data="cancel")])
        
        return InlineKeyboardMarkup(keyboard)
    
    # ==================== MESSAGE HANDLERS ====================
    async def start_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /start command"""
        user = update.effective_user
        
        # Check if bot is paused
        if await self.check_bot_availability(update):
            return
        
        welcome_msg = f"""
👋 Hello {user.first_name}!

🤖 **Telegram Download Bot with Quality Selection**

📥 **Supported Platforms:**
✅ YouTube - Choose quality with file size
✅ Instagram - Multiple quality options  
✅ Twitter/X - Best available quality
✅ TikTok - Videos & music
✅ Facebook - Videos & reels
✅ Direct files - Preserves original format

🎯 **How to use:**
1. Send YouTube/Instagram link → Choose quality
2. Send Twitter/TikTok link → Auto download
3. Send direct file → Keeps original format

⚡ **Features:**
• Quality selection for YouTube/Instagram
• Shows file size for each quality
• Auto cleanup every 2 minutes
• Pause/Resume functionality
• Working hours control

📋 **Commands:**
/start - This menu
/help - Detailed help
/status - Bot status

🛠️ **Admin Commands:**
/pause [hours] - Pause bot
/resume - Resume bot
/clean - Clean cache
/sethours [start] [end] - Set working hours

💡 **Note:** Files auto-deleted after 2 minutes
"""
        
        await update.message.reply_text(welcome_msg, parse_mode='Markdown')
        logger.info(f"User {user.id} started bot")
    
    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /help command"""
        help_text = """
📖 **Help Guide**

🔗 **Supported URLs:**
• YouTube: https://youtube.com/watch?v=...
• Instagram: https://instagram.com/p/...
• Twitter: https://twitter.com/.../status/...
• TikTok: https://tiktok.com/@.../video/...
• Facebook: https://facebook.com/watch/?v=...
• Any direct file link

🔄 **How to download:**
1. Send a valid URL
2. For YouTube/Instagram: Select quality
3. Wait for download to complete
4. File sent to Telegram
5. Auto-deleted after 2 minutes

⚙️ **Quality Selection:**
• YouTube: Shows all available resolutions
• Instagram: Shows available formats
• Others: Downloads best quality

⚠️ **Limitations:**
• Max file size: 2GB
• Some platforms may block downloads
• Rate limits may apply

❓ **Need help?**
Check /status for bot health
"""
        
        await update.message.reply_text(help_text, parse_mode='Markdown')
    
    async def handle_url_message(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle URL messages"""
        # Check bot availability
        if await self.check_bot_availability(update):
            return
        
        url = update.message.text.strip()
        user = update.effective_user
        
        logger.info(f"URL from {user.id}: {url[:50]}")
        
        # Validate URL
        if not url.startswith(('http://', 'https://')):
            await update.message.reply_text("❌ Please send a valid URL starting with http:// or https://")
            return
        
        # Detect platform
        platform = self.detect_platform(url)
        
        # Save to context
        context.user_data['last_url'] = url
        context.user_data['last_platform'] = platform
        context.user_data['url_hash'] = hash(url) % 10000
        
        # Show quality selection for supported platforms
        if platform in ['youtube', 'instagram']:
            await update.message.reply_text(f"🔍 Getting available qualities from {platform}...")
            
            formats = await self.get_available_formats(url, platform)
            
            if formats:
                # Show formats list
                formats_text = f"📊 **Available Qualities for {platform.capitalize()}**\n\n"
                for i, fmt in enumerate(formats[:5], 1):
                    formats_text += f"{i}. {fmt['quality']} - {fmt['size_mb']}MB\n"
                
                if len(formats) > 5:
                    formats_text += f"... and {len(formats) - 5} more\n"
                
                await update.message.reply_text(formats_text, parse_mode='Markdown')
                
                # Create keyboard
                keyboard = self.create_quality_keyboard(formats, platform, context.user_data['url_hash'])
                await update.message.reply_text("👇 Select quality:", reply_markup=keyboard)
            else:
                # Fallback to direct download
                await update.message.reply_text("📥 Downloading best quality...")
                await self.download_media(update, url, 'best', platform, source=update.message)
        else:
            # Direct download for other platforms
            platform_names = {
                'twitter': 'Twitter/X',
                'tiktok': 'TikTok',
                'facebook': 'Facebook',
                'generic': 'the link'
            }
            platform_name = platform_names.get(platform, platform)
            
            await update.message.reply_text(f"📥 Downloading from {platform_name}...")
            await self.download_media(update, url, 'best', platform, source=update.message)
    
    async def handle_callback(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle callback queries (quality selection)"""
        query = update.callback_query
        await query.answer()
        
        data = query.data
        
        if data == 'cancel':
            await query.edit_message_text("❌ Download cancelled.")
            return
        
        if data.startswith('dl_'):
            # Parse: dl_platform_format_id_hash
            parts = data.split('_')
            if len(parts) >= 4:
                platform = parts[1]
                format_id = parts[2]
                
                url = context.user_data.get('last_url')
                if not url:
                    await query.edit_message_text("❌ URL not found in session!")
                    return
                
                await query.edit_message_text(f"⏳ Downloading {format_id} quality...")
                await self.download_media(update, url, format_id, platform, source=query)
    
    # ==================== DOWNLOAD LOGIC ====================
    async def download_media(self, update: Update, url, format_id, platform, source=None):
        """Download media with specified format"""
        try:
            chat_id = None
            message_to_edit = None
            
            # Determine message source
            if hasattr(source, 'edit_message_text'):
                # From callback query
                chat_id = source.message.chat_id
                message_to_edit = source
                original_message = source.message
            else:
                # From regular message
                chat_id = source.chat_id
                original_message = source
            
            # Create progress message
            progress_msg = await original_message.reply_text("⏬ Starting download...")
            
            # Prepare download options
            timestamp = int(time.time())
            filename_template = f"{timestamp}_%(title).100s.%(ext)s"
            
            ydl_opts = {
                'format': format_id,
                'outtmpl': str(self.download_dir / filename_template),
                'quiet': False,
                'no_warnings': False,
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
            
            # Download file
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filename = ydl.prepare_filename(info)
                
                # Find actual file (yt-dlp may change extension)
                actual_file = self.find_downloaded_file(filename)
                
                if actual_file and os.path.exists(actual_file):
                    file_size = os.path.getsize(actual_file) / (1024 * 1024)
                    max_size = self.config['telegram']['max_file_size']
                    
                    if file_size > max_size:
                        os.remove(actual_file)
                        await progress_msg.edit_text(f"❌ File too large: {file_size:.1f}MB (max: {max_size}MB)")
                        return
                    
                    # Send to Telegram
                    await self.send_to_telegram(update, actual_file, info, progress_msg)
                    
                    # Schedule cleanup
                    self.schedule_file_deletion(actual_file)
                else:
                    await progress_msg.edit_text("❌ File not found after download")
        
        except yt_dlp.utils.DownloadError as e:
            error_msg = str(e)
            if "Private video" in error_msg:
                error_msg = "❌ Video is private or requires login"
            elif "Unavailable" in error_msg:
                error_msg = "❌ Video is unavailable"
            elif "Too many requests" in error_msg:
                error_msg = "❌ Rate limited. Please try again later"
            
            await progress_msg.edit_text(error_msg)
            logger.error(f"Download error: {e}")
        
        except Exception as e:
            error_msg = f"❌ Download failed: {str(e)[:100]}"
            await progress_msg.edit_text(error_msg)
            logger.error(f"Unexpected error: {e}", exc_info=True)
    
    def create_progress_hook(self, progress_msg):
        """Create progress hook for yt-dlp"""
        last_update = [0]
        
        async def update_progress_async(text):
            try:
                await progress_msg.edit_text(text[:200])
            except Exception as e:
                logger.debug(f"Progress update failed: {e}")
        
        def hook(d):
            if d['status'] == 'downloading':
                percent = d.get('_percent_str', '0%').strip()
                speed = d.get('_speed_str', 'N/A')
                eta = d.get('_eta_str', 'N/A')
                
                # Update every 10% progress
                try:
                    percent_num = float(percent.replace('%', ''))
                    if percent_num - last_update[0] >= 10:
                        text = f"⏬ Downloading... {percent}\n🚀 Speed: {speed}\n⏰ ETA: {eta}"
                        
                        # Run in background
                        asyncio.run_coroutine_threadsafe(
                            update_progress_async(text),
                            asyncio.get_event_loop()
                        )
                        last_update[0] = percent_num
                except:
                    pass
        
        return hook
    
    def find_downloaded_file(self, base_filename):
        """Find the actual downloaded file"""
        base = os.path.splitext(base_filename)[0]
        
        for ext in ['.mp4', '.mkv', '.webm', '.m4a', '.mp3', '.flv', '.avi']:
            test_file = base + ext
            if os.path.exists(test_file):
                return test_file
        
        # Check if base file exists
        if os.path.exists(base_filename):
            return base_filename
        
        # Check for files with similar names
        parent_dir = os.path.dirname(base_filename)
        if os.path.exists(parent_dir):
            for file in os.listdir(parent_dir):
                if file.startswith(os.path.basename(base)):
                    return os.path.join(parent_dir, file)
        
        return None
    
    async def send_to_telegram(self, update, filepath, info, progress_msg):
        """Send file to Telegram"""
        try:
            file_size = os.path.getsize(filepath) / (1024 * 1024)
            title = info.get('title', 'Downloaded File')[:100]
            duration = info.get('duration', 0)
            
            # Prepare caption
            caption = f"✅ **Download Complete!**\n"
            caption += f"📁 **Title:** {title}\n"
            caption += f"📊 **Size:** {file_size:.1f} MB"
            
            if duration > 0:
                mins = duration // 60
                secs = duration % 60
                caption += f"\n⏱️ **Duration:** {mins}:{secs:02d}"
            
            # Determine file type
            file_ext = os.path.splitext(filepath)[1].lower()
            
            with open(filepath, 'rb') as f:
                if file_ext in ['.mp3', '.m4a', '.opus', '.flac', '.wav']:
                    await update.message.reply_audio(
                        audio=f,
                        caption=caption,
                        title=title[:64],
                        duration=int(duration),
                        parse_mode='Markdown'
                    )
                elif file_ext in ['.mp4', '.mkv', '.webm', '.mov', '.avi']:
                    await update.message.reply_video(
                        video=f,
                        caption=caption,
                        duration=int(duration),
                        supports_streaming=True,
                        parse_mode='Markdown'
                    )
                elif file_ext in ['.jpg', '.jpeg', '.png', '.gif', '.webp']:
                    await update.message.reply_photo(
                        photo=f,
                        caption=caption,
                        parse_mode='Markdown'
                    )
                else:
                    await update.message.reply_document(
                        document=f,
                        caption=caption,
                        parse_mode='Markdown'
                    )
            
            await progress_msg.edit_text(f"✅ File sent successfully!\n📊 Size: {file_size:.1f}MB")
            
        except TelegramError as e:
            error_msg = f"❌ Telegram error: {str(e)[:100]}"
            await progress_msg.edit_text(error_msg)
            logger.error(f"Telegram send error: {e}")
        except Exception as e:
            error_msg = f"❌ Error sending file: {str(e)[:100]}"
            await progress_msg.edit_text(error_msg)
            logger.error(f"Send error: {e}")
    
    def schedule_file_deletion(self, filepath):
        """Schedule file deletion after 2 minutes"""
        def delete_after_delay():
            time.sleep(120)  # 2 minutes
            if os.path.exists(filepath):
                try:
                    os.remove(filepath)
                    logger.info(f"Auto-deleted: {os.path.basename(filepath)}")
                except Exception as e:
                    logger.error(f"Failed to auto-delete {filepath}: {e}")
        
        threading.Thread(target=delete_after_delay, daemon=True).start()
    
    # ==================== BOT CONTROLS ====================
    async def check_bot_availability(self, update):
        """Check if bot should respond"""
        # Check if paused
        if self.is_paused and self.paused_until and datetime.now() < self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            
            await update.message.reply_text(
                f"⏸️ Bot is paused\n"
                f"Will resume in: {hours}h {minutes}m\n"
                f"Resume time: {self.paused_until.strftime('%H:%M')}"
            )
            return True
        
        # Check active hours
        if self.active_hours.get('enabled', False):
            current_hour = datetime.now().hour
            start = self.active_hours.get('start', 9)
            end = self.active_hours.get('end', 22)
            
            is_active = start <= current_hour <= end if start <= end else current_hour >= start or current_hour <= end
            
            if not is_active:
                await update.message.reply_text(
                    f"⏰ Bot is only active from {start}:00 to {end}:00\n"
                    f"Current time: {datetime.now().strftime('%H:%M')}"
                )
                return True
        
        return False
    
    async def status_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /status command"""
        user = update.effective_user
        
        # Admin check
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("❌ Admin only command!")
            return
        
        # Gather status info
        files_count = len(list(self.download_dir.glob('*')))
        total_size = sum(f.stat().st_size for f in self.download_dir.glob('*') if f.is_file()) / (1024 * 1024)
        
        status_text = f"📊 **Bot Status**\n\n"
        status_text += f"🤖 **State:** {'⏸️ Paused' if self.is_paused else '✅ Active'}\n"
        
        if self.is_paused and self.paused_until:
            remaining = self.paused_until - datetime.now()
            hours = remaining.seconds // 3600
            minutes = (remaining.seconds % 3600) // 60
            status_text += f"⏰ **Resumes in:** {hours}h {minutes}m\n"
        
        if self.active_hours.get('enabled', False):
            start = self.active_hours.get('start', 9)
            end = self.active_hours.get('end', 22)
            status_text += f"🕐 **Active hours:** {start}:00 - {end}:00\n"
        
        status_text += f"📁 **Cache files:** {files_count}\n"
        status_text += f"💾 **Cache size:** {total_size:.1f} MB\n"
        status_text += f"👤 **Your ID:** `{user.id}`\n"
        status_text += f"🆔 **Admins:** {len(self.admin_ids)} users\n"
        
        await update.message.reply_text(status_text, parse_mode='Markdown')
    
    async def pause_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /pause command"""
        user = update.effective_user
        
        # Admin check
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("❌ Admin only command!")
            return
        
        # Get hours from command
        hours = 1
        if context.args:
            try:
                hours = int(context.args[0])
                if hours < 1:
                    hours = 1
                elif hours > 720:  # 30 days max
                    hours = 720
            except:
                hours = 1
        
        self.is_paused = True
        self.paused_until = datetime.now() + timedelta(hours=hours)
        
        await update.message.reply_text(
            f"⏸️ **Bot paused**\n"
            f"Duration: {hours} hour(s)\n"
            f"Resume at: {self.paused_until.strftime('%Y-%m-%d %H:%M')}\n\n"
            f"Use /resume to resume earlier"
        )
    
    async def resume_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /resume command"""
        user = update.effective_user
        
        # Admin check
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("❌ Admin only command!")
            return
        
        self.is_paused = False
        self.paused_until = None
        await update.message.reply_text("▶️ **Bot resumed successfully!**")
    
    async def clean_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /clean command"""
        user = update.effective_user
        
        # Admin check
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("❌ Admin only command!")
            return
        
        files = list(self.download_dir.glob('*'))
        count = len(files)
        total_size = sum(f.stat().st_size for f in files if f.is_file()) / (1024 * 1024)
        
        for f in files:
            try:
                f.unlink()
            except Exception as e:
                logger.error(f"Failed to delete {f}: {e}")
        
        await update.message.reply_text(f"🧹 **Cleaned {count} files** ({total_size:.1f} MB)")
    
    async def sethours_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle /sethours command"""
        user = update.effective_user
        
        # Admin check
        if self.admin_ids and user.id not in self.admin_ids:
            await update.message.reply_text("❌ Admin only command!")
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
                    
                    # Update config
                    self.config['active_hours'] = self.active_hours
                    self.save_config()
                    
                    await update.message.reply_text(
                        f"✅ **Active hours set**\n"
                        f"🕐 {start}:00 - {end}:00\n\n"
                        f"Bot will only work during these hours"
                    )
                else:
                    await update.message.reply_text("❌ Hours must be between 0-23")
            except ValueError:
                await update.message.reply_text("❌ Invalid format. Use: /sethours 9 22")
        else:
            # Toggle on/off
            self.active_hours['enabled'] = not self.active_hours.get('enabled', False)
            
            if self.active_hours['enabled']:
                await update.message.reply_text("✅ Active hours enabled")
            else:
                await update.message.reply_text("✅ Active hours disabled")
    
    # ==================== BOT RUNNER ====================
    def run(self):
        """Start the bot"""
        print("\n" + "="*60)
        print("🤖 TELEGRAM DOWNLOAD BOT STARTING")
        print("="*60)
        
        # Check token
        if not self.token or self.token == 'YOUR_BOT_TOKEN_HERE':
            print("❌ ERROR: Bot token not configured!")
            print(f"📝 Edit file: {os.path.abspath(CONFIG_FILE)}")
            print("🔑 Get token from @BotFather on Telegram")
            print("💡 Replace 'YOUR_BOT_TOKEN_HERE' with your actual token")
            return
        
        print(f"✅ Token: {self.token[:15]}...")
        print(f"✅ Admins: {len(self.admin_ids)}")
        print(f"✅ Max file size: {self.config['telegram']['max_file_size']}MB")
        print(f"✅ Download dir: {self.download_dir}")
        
        if self.active_hours.get('enabled', False):
            print(f"✅ Active hours: {self.active_hours.get('start')}:00 - {self.active_hours.get('end')}:00")
        
        print("\n📱 Bot is ready! Features:")
        print("   • YouTube quality selection")
        print("   • Instagram quality selection")
        print("   • Twitter/X, TikTok, Facebook support")
        print("   • Direct file downloads")
        print("   • Auto cleanup every 2 minutes")
        print("   • Pause/Resume functionality")
        print("="*60 + "\n")
        
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
        app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, self.handle_url_message))
        app.add_handler(CallbackQueryHandler(self.handle_callback))
        
        # Run bot
        print("🔄 Starting bot polling...")
        app.run_polling(drop_pending_updates=True)

def main():
    """Main entry point"""
    try:
        bot = TelegramDownloadBot()
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
BOTPY

# Create config.json
cat > config.json << 'CONFIG'
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000,
        "download_timeout": 300
    },
    "download_dir": "downloads",
    "cleanup_minutes": 2,
    "active_hours": {
        "enabled": false,
        "start": 9,
        "end": 22
    },
    "rate_limit": {
        "enabled": true,
        "requests_per_minute": 10
    }
}
CONFIG

# Create management script
cat > manage.sh << 'MANAGE'
#!/bin/bash
# Telegram Download Bot Management Script
# Location: /opt/quality-tg-bot

INSTALL_DIR="/opt/quality-tg-bot"
cd "$INSTALL_DIR"

case "$1" in
    start)
        echo "🚀 Starting Telegram Download Bot..."
        source venv/bin/activate
        
        # Check if already running
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "⚠️ Bot is already running (PID: $(cat bot.pid))"
            exit 1
        fi
        
        # Check config
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
        echo "   • Instagram quality selection"
        echo "   • Twitter/X, TikTok, Facebook"
        echo "   • Direct file downloads"
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
        echo "📊 Telegram Download Bot Status"
        echo "================================"
        
        # Check if running
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
            echo "📝 Recent logs:"
            if [ -f "bot.log" ]; then
                tail -5 bot.log | while IFS= read -r line; do
                    echo "  $line"
                done
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
        
        # Show installation info
        echo ""
        echo "📁 Installation: $INSTALL_DIR"
        echo "🐍 Python: $(python3 --version 2>/dev/null || echo 'Not found')"
        echo "🔧 Virtual env: $( [ -d "venv" ] && echo 'Active' || echo 'Missing' )"
        ;;
    
    logs)
        echo "📝 Bot logs:"
        if [ -f "bot.log" ]; then
            if [ "$2" = "-f" ] || [ "$2" = "--follow" ]; then
                tail -f bot.log
            elif [ "$2" = "-e" ] || [ "$2" = "--errors" ]; then
                echo "🔍 Showing errors:"
                grep -i "error\|exception\|failed\|traceback" bot.log | tail -50
            elif [ "$2" = "-c" ] || [ "$2" = "--clean" ]; then
                > bot.log
                echo "✅ Logs cleared"
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
            cat > config.json << DEFAULT_CONFIG
{
    "telegram": {
        "token": "YOUR_BOT_TOKEN_HERE",
        "admin_ids": [],
        "max_file_size": 2000,
        "download_timeout": 300
    },
    "download_dir": "downloads",
    "cleanup_minutes": 2,
    "active_hours": {
        "enabled": false,
        "start": 9,
        "end": 22
    }
}
DEFAULT_CONFIG
        fi
        
        nano config.json
        
        echo ""
        echo "📋 Configuration tips:"
        echo "   • Get token from @BotFather"
        echo "   • Add your Telegram ID to admin_ids"
        echo "   • Restart after changes: ./manage.sh restart"
        ;;
    
    test)
        echo "🔍 Testing installation..."
        source venv/bin/activate
        
        echo ""
        echo "1. Testing Python imports:"
        python3 -c "
try:
    import telegram, yt_dlp, requests, json, os, asyncio
    print('✅ All imports successful')
    print(f'   • python-telegram-bot: {telegram.__version__}')
    print(f'   • yt-dlp: {yt_dlp.version.__version__}')
    print(f'   • requests: {requests.__version__}')
except Exception as e:
    print(f'❌ Import error: {e}')
"
        
        echo ""
        echo "2. Testing configuration:"
        python3 -c "
import json, os
try:
    if os.path.exists('config.json'):
        with open('config.json', 'r') as f:
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
        echo "3. Testing directories:"
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
        
        # Optional: clear logs
        if [ "$2" = "--all" ]; then
            > bot.log 2>/dev/null || true
            echo "✅ Logs cleared"
        fi
        ;;
    
    update)
        echo "🔄 Updating bot..."
        ./manage.sh stop
        
        echo "Downloading latest installer..."
        curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh -o /tmp/update_bot.sh
        
        if [ $? -eq 0 ]; then
            echo "Running update..."
            bash /tmp/update_bot.sh
        else
            echo "❌ Failed to download update"
        fi
        ;;
    
    uninstall)
        echo "🗑️ Uninstalling bot..."
        echo ""
        echo "⚠️  WARNING: This will remove ALL bot files!"
        echo ""
        read -p "Type 'YES' to confirm uninstall: " CONFIRM
        
        if [ "$CONFIRM" = "YES" ]; then
            ./manage.sh stop
            
            # Remove installation directory
            rm -rf "$INSTALL_DIR"
            
            # Remove from crontab
            crontab -l 2>/dev/null | grep -v "$INSTALL_DIR" | crontab -
            
            echo ""
            echo "✅ Bot completely uninstalled!"
            echo "📁 Removed: $INSTALL_DIR"
        else
            echo "❌ Uninstall cancelled"
        fi
        ;;
    
    autostart)
        echo "⚙️ Configuring auto-start on reboot..."
        
        # Check if already configured
        if crontab -l 2>/dev/null | grep -q "$INSTALL_DIR/manage.sh start"; then
            echo "✅ Auto-start already configured"
        else
            # Add to crontab
            (crontab -l 2>/dev/null; echo "@reboot cd $INSTALL_DIR && $INSTALL_DIR/manage.sh start") | crontab -
            echo "✅ Auto-start configured"
            echo "   Bot will start automatically on system reboot"
        fi
        
        echo ""
        echo "Current crontab entries:"
        crontab -l 2>/dev/null | grep -v "^#"
        ;;
    
    *)
        echo "🤖 Telegram Download Bot Management"
        echo "==================================="
        echo ""
        echo "📁 Location: $INSTALL_DIR"
        echo ""
        echo "📋 Available commands:"
        echo ""
        echo "  Basic commands:"
        echo "    start     - Start the bot"
        echo "    stop      - Stop the bot"
        echo "    restart   - Restart the bot"
        echo "    status    - Check bot status"
        echo "    logs      - View logs (-f to follow, -e for errors)"
        echo ""
        echo "  Configuration:"
        echo "    config    - Edit configuration"
        echo "    test      - Test installation"
        echo "    debug     - Run in debug mode"
        echo ""
        echo "  Maintenance:"
        echo "    clean     - Clean cache files"
        echo "    update    - Update bot to latest version"
        echo "    uninstall - Uninstall bot (WARNING: irreversible)"
        echo "    autostart - Auto-start on reboot"
        echo ""
        echo "🎯 Features:"
        echo "  • YouTube quality selection with file sizes"
        echo "  • Instagram quality selection"
        echo "  • Twitter/X, TikTok, Facebook support"
        echo "  • Direct file downloads (preserves format)"
        echo "  • Auto cleanup every 2 minutes"
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
MANAGE

# Create requirements.txt
cat > requirements.txt << 'REQUIREMENTS'
python-telegram-bot==20.7
yt-dlp==2025.11.12
requests==2.32.5
tqdm==4.66.5
REQUIREMENTS

# Create README
cat > README.md << 'README'
# Telegram Download Bot with Quality Selection 🤖

A powerful Telegram bot for downloading media from various platforms with quality selection.

## 🚀 One-Command Installation

```bash
bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/quality_install.sh)
