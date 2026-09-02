#!/bin/bash
# SysInfo Live USB Builder
# ساخت ISO سفارشی Alpine Linux با teaiso
#
# نیازمندی‌ها: Ubuntu/Debian
# استفاده: sudo ./build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"

echo "╔══════════════════════════════════════════╗"
echo "║      SysInfo Live USB Builder           ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── بررسی root ───
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root"
    echo "Usage: sudo $0"
    exit 1
fi

# ─── نصب نیازمندی‌ها ───
echo "[1/4] Installing dependencies..."
apt update -qq
apt install -y -qq \
    xorriso grub-pc-bin grub-efi mtools make python3 \
    dosfstools e2fsprogs squashfs-tools python3-yaml \
    gcc wget curl unzip xz-utils zstd git

# ─── کلون teaiso اگه نیست ───
echo "[2/4] Setting up teaiso..."
if [ ! -d "$SCRIPT_DIR/teaiso" ]; then
    git clone https://gitlab.com/tearch-linux/applications-and-tools/teaiso "$SCRIPT_DIR/teaiso"
fi

cd "$SCRIPT_DIR/teaiso"
make
if [ "$(id -u)" -ne 0 ]; then
    sudo make install
else
    make install
fi
cd "$SCRIPT_DIR"

# ─── پیکربندی پارتیشن writable (FAT32 برای خواندن در ویندوز/مک/لینوکس) ───
# 1) حجم: از 4MB به 256MB افزایش
# 2) فرمت: از ext4 به FAT32 تغییر تا بدون ابزار اضافه روی همه سیستم‌ها دیده شود
echo "[2.5/4] Configuring writable partition (FAT32, 256MB)..."
if [ -f "/usr/lib/teaiso/common/isowork.py" ]; then
    sed -i '/writable.img/s/bs=4M count=1 oflag=sync/bs=4M count=64 oflag=sync/' /usr/lib/teaiso/common/isowork.py
    sed -i '/writable.img/s|mkfs.ext4 -b 1024 -L writable|mkfs.vfat -F 32 -n writable|' /usr/lib/teaiso/common/isowork.py
    echo "  patched writable.img: 256MB, FAT32 (label: writable)"
else
    echo "  WARNING: could not find teaiso isowork.py to patch writable config"
fi

# ─── ساخت ISO ───
echo "[3/4] Building ISO..."
mkdir -p "$OUTPUT_DIR"
mkteaiso --profile="$SCRIPT_DIR" --output="$OUTPUT_DIR/" --debug 2>&1

# ─── ساخت flash script ───
cat > "$OUTPUT_DIR/flash.sh" <<'FLASH'
#!/bin/bash
# SysInfo Flash - ساخت فلش بوت‌پذیر
# استفاده: sudo ./flash.sh /dev/sdX

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: $0 /dev/sdX"
    echo ""
    echo "Available devices:"
    lsblk -dno NAME,SIZE,MODEL
    exit 1
fi

DEVICE="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ISO_FILE=$(ls "$SCRIPT_DIR"/*.iso 2>/dev/null | head -1)

if [ -z "$ISO_FILE" ]; then
    echo "ERROR: No ISO file found"
    exit 1
fi

echo "WARNING: This will destroy all data on $DEVICE"
echo "ISO: $ISO_FILE"
echo ""
read -p "Continue? (yes/no): " CONFIRM
[ "$CONFIRM" != "yes" ] && echo "Aborted." && exit 0

echo "Writing ISO to $DEVICE..."
dd if="$ISO_FILE" of="$DEVICE" bs=4M status=progress conv=fsync
echo ""
echo "Done! Boot from $DEVICE"
FLASH
chmod +x "$OUTPUT_DIR/flash.sh"

# ─── خلاصه ───
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           BUILD COMPLETE!                ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "ISO file: $(ls $OUTPUT_DIR/*.iso 2>/dev/null | head -1)"
echo ""
echo "Flash to USB:"
echo "  sudo $OUTPUT_DIR/flash.sh /dev/sdX"
echo ""
echo "Or manually:"
echo "  sudo dd if=$OUTPUT_DIR/*.iso of=/dev/sdX bs=4M status=progress"
echo ""
echo "Test in QEMU:"
echo "  qemu-system-x86_64 -cdrom $OUTPUT_DIR/*.iso -m 1024"
echo ""
