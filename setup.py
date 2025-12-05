#!/usr/bin/env python3
"""
اسکریپت نصب آسان ربات
"""

import os
import sys
import subprocess
import requests

def run_command(cmd):
    """اجرای دستور و نمایش خروجی"""
    print(f"🌀 اجرا: {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(f"⚠️  {result.stderr}")
    return result.returncode

def main():
    print("🤖 نصب ربات تلگرام دانلود")
    print("=" * 40)
    
    # بررسی Python
    print("🔍 بررسی Python...")
    if run_command("python3 --version") != 0:
        print("❌ Python3 نصب نیست")
        sys.exit(1)
    
    # نصب پیش‌نیازها
    print("📦 نصب پیش‌نیازهای سیستم...")
    run_command("apt-get update -y")
    run_command("apt-get install -y python3-pip python3-venv git curl wget ffmpeg")
    
    # دانلود اسکریپت نصب
    print("📥 دانلود اسکریپت نصب...")
    try:
        response = requests.get("https://raw.githubusercontent.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook/main/install.sh")
        with open("/tmp/install_bot.sh", "w") as f:
            f.write(response.text)
        
        run_command("chmod +x /tmp/install_bot.sh")
        
        print("🚀 شروع نصب...")
        run_command("/tmp/install_bot.sh")
        
    except Exception as e:
        print(f"❌ خطا در دانلود: {e}")
        print("📋 نصب دستی:")
        print("git clone https://github.com/2amir563/khodam-down-upload-instagram-youtube-x-facebook.git")
        print("cd khodam-down-upload-instagram-youtube-x-facebook")
        print("chmod +x install.sh")
        print("./install.sh")

if __name__ == "__main__":
    main()
