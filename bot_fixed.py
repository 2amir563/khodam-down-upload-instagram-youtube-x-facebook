cd /opt/telegram-downloader

cat > simple_test.py << 'EOF'
#!/usr/bin/env python3
import logging
import json
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters

# Setup logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

# Read token
with open('config.json', 'r') as f:
    TOKEN = json.load(f)['telegram']['token']

async def start(update: Update, context):
    await update.message.reply_text('Bot is working! ✅')

async def echo(update: Update, context):
    await update.message.reply_text(f'You said: {update.message.text}')

def main():
    print("🤖 Starting test bot...")
    print(f"Token: {TOKEN[:15]}...")
    
    app = Application.builder().token(TOKEN).build()
    
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo))
    
    print("✅ Bot ready")
    print("📱 Send /start in Telegram")
    
    app.run_polling()

if __name__ == '__main__':
    main()
EOF

# تست
./manage.sh stop
source venv/bin/activate
python simple_test.py
