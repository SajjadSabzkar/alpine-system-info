#!/usr/bin/env bash
# SysInfo Live USB - Alpine Linux Customization Script
# این اسکریپت هنگام ساخت ISO اجرا میشه و سیستم‌عامل رو سفارشی میکنه

set -e

echo "=== Customizing Alpine Linux for SysInfo Collection ==="

# ─── آپدیت پکیج‌ها ───
apk update
apk upgrade

# ─── نصب پکیج‌های اضافی ───
apk add lshw --repository=https://dl-cdn.alpinelinux.org/alpine/v3.22/community 2>/dev/null || true

# ─── اطمینان از اجرایی بودن اسکریپت جمع‌آوری اطلاعات ───
chmod +x /usr/sbin/system_info.sh

# ─── تنظیم رمز root ───
echo -e "live\nlive" | passwd root

# ─── ایجاد اسکریپت auto-login ───
cat << 'AUTOLOGIN' > /usr/sbin/autologin
#!/bin/sh
exec /bin/login -f root
AUTOLOGIN
chmod +x /usr/sbin/autologin

# ─── فعال کردن auto-login در inittab ───
sed -i 's@:respawn:/sbin/getty@:respawn:/sbin/getty -n -l /usr/sbin/autologin@g' /etc/inittab

# ─── ایجاد OpenRC service ───
cat << 'SERVICE' > /etc/init.d/system_info_service
#!/sbin/openrc-run

description="SysInfo Auto-Collector"

depend() {
    # نمی‌توان از sysinit استفاده کرد چون سرویسی با این نام در OpenRC وجود ندارد
    need root localmount
    after bootmisc udev mdev
}

start() {
    ebegin "Starting SysInfo Collector"
    # صبر برای شناسایی کامل دستگاه‌ها توسط udev / mdev
    sleep 5
    /usr/sbin/system_info.sh &
    eend 0
}
SERVICE
chmod +x /etc/init.d/system_info_service
rc-update add system_info_service default

# ─── پاکسازی ───
apk cache clean 2>/dev/null || true

echo "=== Customization Complete ==="
