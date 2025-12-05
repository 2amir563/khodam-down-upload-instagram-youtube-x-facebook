#!/bin/bash
# manage.sh - مدیریت ربات تلگرام

cd /opt/telegram-download-bot

case "$1" in
    start)
        echo "🚀 شروع ربات..."
        source venv/bin/activate
        nohup python bot.py > bot.log 2>&1 &
        echo $! > bot.pid
        echo "✅ ربات شروع شد (PID: $(cat bot.pid))"
        echo "📝 لاگ‌ها: tail -f bot.log"
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
        ./manage.sh stop
        sleep 2
        ./manage.sh start
        ;;
    status)
        echo "📊 وضعیت ربات:"
        if [ -f "bot.pid" ] && ps -p $(cat bot.pid) > /dev/null 2>&1; then
            echo "✅ ربات در حال اجراست (PID: $(cat bot.pid))"
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
        ;;
    test)
        echo "🔍 تست اتصال..."
        source venv/bin/activate
        python3 -c "
import requests
import json
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
    update)
        echo "🔄 بروزرسانی..."
        ./manage.sh stop
        source venv/bin/activate
        pip install --upgrade python-telegram-bot yt-dlp requests
        echo "✅ بروزرسانی کامل شد"
        ;;
    clean)
        echo "🧹 پاکسازی فایل‌های موقت..."
        rm -rf downloads/*
        rm -f bot.log
        echo "✅ پاکسازی انجام شد"
        ;;
    *)
        echo "🤖 مدیریت ربات تلگرام دانلود"
        echo "=========================="
        echo ""
        echo "دستورات:"
        echo "  ./manage.sh start     # شروع ربات"
        echo "  ./manage.sh stop      # توقف ربات"
        echo "  ./manage.sh restart   # راه‌اندازی مجدد"
        echo "  ./manage.sh status    # وضعیت ربات"
        echo "  ./manage.sh logs      # نمایش لاگ‌ها"
        echo "  ./manage.sh config    # ویرایش تنظیمات"
        echo "  ./manage.sh test      # تست اتصال"
        echo "  ./manage.sh update    # بروزرسانی"
        echo "  ./manage.sh clean     # پاکسازی فایل‌ها"
        echo ""
        echo "📁 پوشه: /opt/telegram-download-bot"
        ;;
esac
