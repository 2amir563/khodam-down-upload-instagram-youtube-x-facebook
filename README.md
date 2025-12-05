

```
bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/setup.sh) install
```

مرحله 3: پیکربندی و راه‌اندازی
bash
# 1. رفتن به پوشه ربات
```
cd ~/khodam-bot
```

# 2. ویرایش تنظیمات
```
nano config.json
```
# توکن ربات تلگرام خود را وارد کنید

# 3. شروع ربات

```
./start-background.sh
```

دستورات مدیریتی سریع
پس از نصب، این دستورات ساده را استفاده کنید:

کار	دستور
وضعیت ربات	./status.sh
شروع ربات	./start-background.sh
توقف ربات	./stop.sh
راه‌اندازی مجدد	./restart.sh
توقف موقت 3 ساعت	./pause.sh 3
ادامه کار	./resume.sh
نمایش لاگ‌ها	./logs.sh
ویرایش تنظیمات	./config-edit.sh
زمان‌بندی روشن	./schedule.sh on 09:00 18:00
زمان‌بندی خاموش	./schedule.sh off













 دستور نصب یک خطی در سرور
```
bash <(curl -s https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/manager.sh) install
```

پیکربندی ربات

```
./manager.sh config
```

راه‌اندازی ربات

```
./manager.sh start
```

دستورات مدیریتی کامل
پس از نصب، می‌توانید با این دستورات ربات را مدیریت کنید:

دستور	توضیح
./manager.sh start	شروع ربات در پس‌زمینه
./manager.sh stop	توقف ربات
./manager.sh status	نمایش وضعیت ربات
./manager.sh pause 3	توقف موقت به مدت 3 ساعت
./manager.sh resume	ادامه کار ربات
./manager.sh logs	نمایش لاگ‌های ربات
./manager.sh update	بروزرسانی ربات از گیت‌هاب
./manager.sh config	ویرایش تنظیمات ربات
./manager.sh schedule on 08:00 23:00	فعال کردن زمان‌بندی
./manager.sh schedule off	غیرفعال کردن زمان‌بندی
./manager.sh uninstall	حذف کامل ربات
ویژگی‌های فایل مدیریتی
✅ نصب خودکار: همه پیش‌نیازها را بررسی و نصب می‌کند

✅ مدیریت آسان: فقط با یک فایل همه کارها را انجام دهید

✅ توقف موقت: با تایمر خودکار برای ادامه

✅ زمان‌بندی: تنظیم ساعات کار ربات

✅ بروزرسانی خودکار: از گیت‌هاب آپدیت می‌شود

✅ لاگ‌گیری: نمایش لاگ‌ها به راحتی

✅ حذف کامل: همه چیز پاک می‌شود
