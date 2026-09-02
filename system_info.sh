#!/bin/sh
# SysInfo Collector - جمع‌آوری جامع اطلاعات سخت‌افزاری
# اجرا هنگام بوت از روی فلش USB

set -e

LOG="/tmp/sysinfo.log"
exec > "$LOG" 2>&1

echo "=== SysInfo Collector Started at $(date) ==="

# ─── پیدا کردن فلش USB (خود فلشی که بوت شده) ───
find_boot_device() {
    BOOT_DEV=""
    # روش 1: پیدا کردن از mount point
    BOOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//' | head -1)
    # روش 2: پیدا کردن از /proc/cmdline
    if [ -z "$BOOT_DEV" ]; then
        BOOT_DEV=$(cat /proc/cmdline 2>/dev/null | grep -oP 'burner=\K[^ ]+' | head -1)
    fi
    # روش 3: lsblk
    if [ -z "$BOOT_DEV" ]; then
        BOOT_DEV=$(lsblk -dno NAME,TRAN 2>/dev/null | grep -i usb | awk '{print "/dev/"$1}' | head -1)
    fi
    echo "$BOOT_DEV"
}

BOOT_DEV=$(find_boot_device)
echo "Boot device: $BOOT_DEV"

# ─── مونت کردن فلش برای ذخیره خروجی ───
MOUNT_POINT="/mnt/usb"
mkdir -p "$MOUNT_POINT"

# تلاش برای مونت کردن فلش
MOUNTED=0
for part in "${BOOT_DEV}1" "${BOOT_DEV}2" "${BOOT_DEV}" "/dev/sdb1" "/dev/sdc1"; do
    if [ -b "$part" ]; then
        mount "$part" "$MOUNT_POINT" 2>/dev/null && MOUNTED=1 && break
    fi
done

# اگه فلش مونت نشد، از رم استفاده کن
if [ "$MOUNTED" -eq 0 ]; then
    echo "WARNING: USB not mounted, using RAM disk"
    MOUNT_POINT="/tmp/sysinfo_output"
    mkdir -p "$MOUNT_POINT"
fi

# ─── ساخت پوشه خروجی ───
SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null | tr -d ' \n\r' || echo "unknown")
MANUFACTURER=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "unknown")
PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${MOUNT_POINT}/sysinfo_${TIMESTAMP}_${SERIAL}"
mkdir -p "$OUTPUT_DIR"

echo "Output directory: $OUTPUT_DIR"

# ─── تابع کمکی برای ذخیره خروجی ───
collect() {
    local name="$1"
    local cmd="$2"
    local outfile="$OUTPUT_DIR/${name}.txt"
    echo "Collecting: $name"
    eval "$cmd" > "$outfile" 2>&1 || echo "ERROR: Failed to collect $name"
}

# ─── جمع‌آوری اطلاعات ───

# 1. اطلاعات سیستم (DMI)
echo "--- Collecting DMI info ---"
collect "01_dmi_full"        "dmidecode"
collect "02_dmi_bios"        "dmidecode -t bios"
collect "03_dmi_baseboard"   "dmidecode -t baseboard"
collect "04_dmi_chassis"     "dmidecode -t chassis"
collect "05_dmi_cpu"         "dmidecode -t processor"
collect "06_dmi_memory"      "dmidecode -t memory"

# 2. CPU
echo "--- Collecting CPU info ---"
collect "10_lscpu"           "lscpu"
collect "11_cpuinfo"         "cat /proc/cpuinfo"

# 3. RAM
echo "--- Collecting Memory info ---"
collect "20_free"            "free -h"
collect "21_meminfo"         "cat /proc/meminfo"

# 4. دیسک
echo "--- Collecting Disk info ---"
collect "30_lsblk"           "lsblk -f"
collect "31_lsblk_detail"    "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,SERIAL"
collect "32_fdisk"           "fdisk -l"
collect "33_df"              "df -h"
collect "34_blkid"           "blkid"

# SMART
for disk in $(lsblk -dno NAME 2>/dev/null | grep -E '^sd|^nvme|^vd'); do
    echo "Collecting SMART for /dev/$disk"
    collect "35_smart_${disk}" "smartctl -a /dev/$disk"
done

# 5. شبکه
echo "--- Collecting Network info ---"
collect "40_ip_addr"         "ip addr"
collect "41_ip_route"        "ip route"
collect "42_ip_link"         "ip -s link"
collect "43_netstat"         "ss -tulnp"
collect "44_arp"             "ip neigh"

# 6. PCI Devices
echo "--- Collecting PCI info ---"
collect "50_lspci"           "lspci"
collect "51_lspci_v"         "lspci -v"
collect "52_lspci_nn"        "lspci -nn"
collect "53_lspci_tv"        "lspci -tv"

# 7. USB Devices
echo "--- Collecting USB info ---"
collect "60_lsusb"           "lsusb"
collect "61_lsusb_v"         "lsusb -v"

# 8. GPU
echo "--- Collecting GPU info ---"
collect "70_gpu_lspci"       "lspci | grep -i -E 'vga|3d|display'"

# 9. lshw (جامع)
echo "--- Collecting lshw ---"
collect "80_lshw_short"      "lshw -short"
collect "81_lshw_html"       "lshw -html"

# 10. BIOS/Firmware
echo "--- Collecting BIOS/Firmware ---"
collect "90_bios_version"    "cat /sys/class/dmi/id/bios_version 2>/dev/null"
collect "91_bios_date"       "cat /sys/class/dmi/id/bios_date 2>/dev/null"
collect "92_board_vendor"    "cat /sys/class/dmi/id/board_vendor 2>/dev/null"
collect "93_board_name"      "cat /sys/class/dmi/id/board_name 2>/dev/null"
collect "94_product_name"    "cat /sys/class/dmi/id/product_name 2>/dev/null"
collect "95_product_serial"  "cat /sys/class/dmi/id/product_serial 2>/dev/null"

# 11. Kernel و سیستم‌عامل
echo "--- Collecting OS/Kernel info ---"
collect "100_uname"          "uname -a"
collect "101_lsmod"          "lsmod"

# 12. Temperature و Sensor
echo "--- Collecting Sensors ---"
collect "110_temps"          "sensors" 2>/dev/null || echo "sensors not available" > "$OUTPUT_DIR/110_temps.txt"

# 13. Power/Battery
echo "--- Collecting Power info ---"
collect "120_battery"        "cat /sys/class/power_supply/BAT*/status 2>/dev/null" || echo "No battery" > "$OUTPUT_DIR/120_battery.txt"
collect "121_battery_cap"    "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null" || echo "N/A" > "$OUTPUT_DIR/121_battery_cap.txt"

# 14. System Logs
echo "--- Collecting System logs ---"
collect "140_dmesg"          "dmesg"
collect "141_dmesg_errors"   "dmesg | grep -i -E 'error|fail|warn'"

# ─── ساخت خلاصه ───
echo "--- Generating summary ---"
cat > "$OUTPUT_DIR/00_summary.txt" <<SUMMARY
╔══════════════════════════════════════════════════════════╗
║              SYSINFO COLLECTION REPORT                  ║
╚══════════════════════════════════════════════════════════╝

Date:           $(date)
Hostname:       $(hostname)

Manufacturer:   $MANUFACTURER
Product:        $PRODUCT
Serial:         $SERIAL

BIOS:           $(cat /sys/class/dmi/id/bios_vendor 2>/dev/null) $(cat /sys/class/dmi/id/bios_version 2>/dev/null)
Board:          $(cat /sys/class/dmi/id/board_name 2>/dev/null)

CPU:            $(lscpu | grep 'Model name' | sed 's/Model name:\s*//')
Cores:          $(lscpu | grep '^CPU(s):' | awk '{print $2}')
RAM:            $(free -h | awk '/Mem:/{print $2}')

Disks:
$(lsblk -dno NAME,SIZE,MODEL 2>/dev/null)

GPU:            $(lspci | grep -i 'vga\|3d\|display' | head -1 | sed 's/.*: //')

Network:
$(ip -o link show 2>/dev/null | awk -F': ' '!/lo/{print "  " $2 ": "}' | while read line; do
    iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
    ip addr show "$iface" 2>/dev/null | grep 'inet ' | awk '{print "    IP: " $2}'
    echo "$line"
done)

USB Devices:    $(lsusb 2>/dev/null | wc -l) connected

Total files:    $(ls "$OUTPUT_DIR" | wc -l)
SUMMARY

# ─── ساخت JSON ───
cat > "$OUTPUT_DIR/summary.json" <<JSON
{
  "timestamp": "$(date -Iseconds)",
  "serial": "$SERIAL",
  "manufacturer": "$MANUFACTURER",
  "product": "$PRODUCT",
  "bios": "$(cat /sys/class/dmi/id/bios_version 2>/dev/null)",
  "board": "$(cat /sys/class/dmi/id/board_name 2>/dev/null)",
  "cpu": "$(lscpu | grep 'Model name' | sed 's/Model name:\s*//')",
  "cores": $(lscpu | grep '^CPU(s):' | awk '{print $2}'),
  "ram": "$(free -h | awk '/Mem:/{print $2}')",
  "gpu": "$(lspci | grep -i 'vga\|3d\|display' | head -1 | sed 's/.*: //')",
  "disk_count": $(lsblk -dno NAME 2>/dev/null | wc -l),
  "usb_count": $(lsusb 2>/dev/null | wc -l)
}
JSON

# ─── لیست فایل‌ها ───
ls -la "$OUTPUT_DIR" > "$OUTPUT_DIR/file_list.txt"

echo "=== SysInfo Collection Complete ==="
echo "Total files: $(ls "$OUTPUT_DIR" | wc -l)"
echo "Output: $OUTPUT_DIR"

# ─── خاموش کردن سیستم ───
echo ""
echo "========================================="
echo "  SysInfo Collection Complete!"
echo "  System will shut down in 10 seconds..."
echo "========================================="
sleep 10
poweroff
