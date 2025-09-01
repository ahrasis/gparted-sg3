#!/bin/bash
# save as: build-gparted-sg3.sh

set -e

echo "=== GParted Custom ISO Builder with sg3_utils ==="

# Store original directory
ORIGINAL_DIR="$(pwd)"

# Install required tools
echo "[1/8] Installing required packages..."
sudo apt update
sudo apt install -y squashfs-tools genisoimage sg3-utils wget curl dosfstools

# Get latest GParted version
echo "[2/8] Finding latest GParted version..."
LATEST_URL="https://gparted.org/download.php"
ISO_URL=$(curl -s $LATEST_URL | grep -o 'https://downloads.sourceforge.net/gparted/gparted-live-[0-9.-]*-amd64.iso' | head -1)

if [ -z "$ISO_URL" ]; then
    echo "Error: Could not find latest GParted download URL"
    exit 1
fi

ISO_FILENAME=$(basename "$ISO_URL")

# Check if ISO already exists
if [ -f "$ISO_FILENAME" ]; then
    echo "ISO already exists, skipping download: $ISO_FILENAME"
else
    echo "Downloading: $ISO_FILENAME"
    echo "[3/8] Downloading latest GParted ISO..."
    wget --progress=bar:force "$ISO_URL" -O "$ISO_FILENAME" 2>&1 | tail -f -n +6
fi

# Create workspace with your preferred name
WORK_DIR="gparted-sg3"
echo "[4/8] Preparing workspace..."
# Remove existing directory if it exists
if [ -d "$WORK_DIR" ]; then
    echo "Removing existing work directory..."
    sudo rm -rf "$WORK_DIR"
fi
mkdir -p "$WORK_DIR/iso-extract"
mkdir -p "$WORK_DIR/squashfs-root"

# Extract ISO
echo "[5/8] Extracting ISO contents..."
sudo mount -o loop "$ISO_FILENAME" /mnt
cp -a /mnt/. "$WORK_DIR/iso-extract/"
sudo umount /mnt

# Check for boot directories
BOOT_DIR=""
BOOT_BIN=""
BOOT_CAT=""

if [ -d "$WORK_DIR/iso-extract/syslinux" ]; then
    BOOT_DIR="syslinux"
    BOOT_BIN="syslinux/isolinux.bin"  # Some systems use isolinux.bin in syslinux directory
    BOOT_CAT="syslinux/boot.cat"
    if [ ! -f "$WORK_DIR/iso-extract/$BOOT_BIN" ]; then
        BOOT_BIN="syslinux/syslinux.bin"  # Try syslinux.bin if isolinux.bin doesn't exist
    fi
elif [ -d "$WORK_DIR/iso-extract/isolinux" ]; then
    BOOT_DIR="isolinux"
    BOOT_BIN="isolinux/isolinux.bin"
    BOOT_CAT="isolinux/boot.cat"
elif [ -d "$WORK_DIR/iso-extract/boot/isolinux" ]; then
    BOOT_DIR="boot/isolinux"
    BOOT_BIN="boot/isolinux/isolinux.bin"
    BOOT_CAT="boot/isolinux/boot.cat"
else
    echo "Error: Could not find boot directory in extracted ISO"
    echo "Contents of extracted ISO:"
    ls -la "$WORK_DIR/iso-extract/"
    exit 1
fi

# Verify boot files exist
if [ ! -f "$WORK_DIR/iso-extract/$BOOT_BIN" ]; then
    echo "Error: Boot binary not found: $BOOT_BIN"
    exit 1
fi

if [ ! -f "$WORK_DIR/iso-extract/$BOOT_CAT" ]; then
    echo "Warning: Boot catalog not found: $BOOT_CAT"
    BOOT_CAT=""  # Some systems don't use a boot catalog
fi

echo "Found boot directory: $BOOT_DIR"
echo "Using boot binary: $BOOT_BIN"
echo "Using boot catalog: $BOOT_CAT"

# Extract SquashFS
echo "[6/8] Extracting and modifying filesystem..."
sudo unsquashfs -f -d "$WORK_DIR/squashfs-root" "$WORK_DIR/iso-extract/live/filesystem.squashfs"

# Set up chroot environment
sudo mount --bind /dev "$WORK_DIR/squashfs-root/dev"
sudo mount --bind /proc "$WORK_DIR/squashfs-root/proc"
sudo mount --bind /sys "$WORK_DIR/squashfs-root/sys"
sudo mount --bind /run "$WORK_DIR/squashfs-root/run"
sudo mount --bind /dev/pts "$WORK_DIR/squashfs-root/dev/pts"

# Install sg3_utils in chroot
echo "[7/8] Installing sg3_utils in the live environment..."
sudo chroot "$WORK_DIR/squashfs-root" /bin/bash -c "
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y sg3-utils
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
"

# Clean up mounts
sudo umount "$WORK_DIR/squashfs-root/dev/pts"
sudo umount "$WORK_DIR/squashfs-root/run"
sudo umount "$WORK_DIR/squashfs-root/sys"
sudo umount "$WORK_DIR/squashfs-root/proc"
sudo umount "$WORK_DIR/squashfs-root/dev"

# Rebuild SquashFS
echo "[8/8] Rebuilding custom ISO..."
sudo rm -f "$WORK_DIR/iso-extract/live/filesystem.squashfs"
sudo mksquashfs "$WORK_DIR/squashfs-root" "$WORK_DIR/iso-extract/live/filesystem.squashfs" -comp xz

# Update checksums
cd "$WORK_DIR/iso-extract"
find -type f -not -name md5sum.txt -not -path "./$BOOT_DIR/*" -exec md5sum {} \; > md5sum.txt


# Create new ISO with your preferred naming
#ORIGINAL_NAME=$(echo "$ISO_FILENAME" | sed 's|live-|gparted-sg3-|')
#OUTPUT_ISO="$ORIGINAL_DIR/$ORIGINAL_NAME"

# Return to original directory before creating ISO
#cd "$ORIGINAL_DIR"

# Create the ISO from the correct directory
#cd "$WORK_DIR/iso-extract"

# Build genisoimage command with appropriate options
#GENISO_CMD="sudo genisoimage -o \"$OUTPUT_ISO\" \
#    -b \"$BOOT_BIN\" \
#    -no-emul-boot \
#    -boot-load-size 4 \
#    -boot-info-table \
#    -J -r -V \"GParted Live with sg3_utils\" \
#    ."

# Add boot catalog if it exists
#if [ -n "$BOOT_CAT" ]; then
#    GENISO_CMD=$(echo "$GENISO_CMD" | sed "s/-b \"$BOOT_BIN\"/-b \"$BOOT_BIN\" -c \"$BOOT_CAT\"/")
#fi

# Execute the command
#eval "$GENISO_CMD"

# Create new ISO with your preferred naming
ORIGINAL_NAME=$(echo "$ISO_FILENAME" | sed 's/gparted-live-/gparted-sg3-/')
OUTPUT_ISO="$ORIGINAL_DIR/$ORIGINAL_NAME"

# Always return to original directory before entering work dir
cd "$ORIGINAL_DIR"
cd "$WORK_DIR/iso-extract"

# Extract original volume label from ISO
ORIG_LABEL=$(isoinfo -d -i "$ORIGINAL_DIR/$ISO_FILENAME" | grep '^Volume id:' | sed 's/Volume id:[[:space:]]*//')

# Append -sg3 to the label
VOLUME_LABEL="${ORIG_LABEL}-sg3"

# Show labels for confirmation
echo "Original ISO label: $ORIG_LABEL"
echo "New ISO label:      $VOLUME_LABEL"

# Build genisoimage command
GENISO_CMD=(sudo genisoimage -o "$OUTPUT_ISO" \
    -b "$BOOT_BIN" \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -J -r -V "$VOLUME_LABEL")

# Add boot catalog if it exists
if [ -n "$BOOT_CAT" ]; then
    GENISO_CMD+=(-c "$BOOT_CAT")
fi

# Add current directory at the end
GENISO_CMD+=(".")

# Execute the command
"${GENISO_CMD[@]}"


# Return to original directory
cd "$ORIGINAL_DIR"

# Cleanup
sudo rm -rf "$WORK_DIR"

echo ""
echo "=== SUCCESS ==="
echo "Custom ISO created: $OUTPUT_ISO"
echo "Size: $(du -h "$OUTPUT_ISO" | cut -f1)"
echo ""
echo "To verify contents:"
echo "  isoinfo -i $OUTPUT_ISO -l | grep -i sg3"
echo ""
echo "To write to USB:"
echo "  sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress && sync"
