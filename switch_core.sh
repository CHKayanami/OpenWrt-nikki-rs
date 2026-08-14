#!/bin/sh
set -e

# ==============================================================================
# Nikki RS - clash-rs core switch script (minimal <-> standard)
# ==============================================================================

REPO="CHKayanami/clash-rs"
TAG="latest"
CLASH_BIN="$(command -v clash-rs 2>/dev/null || echo "/usr/bin/clash-rs")"

# 1. Detect current core version and type
CURRENT_INFO=""
CURRENT_TYPE=""
TARGET_TYPE=""

if [ -x "$CLASH_BIN" ]; then
    VERSION_OUTPUT="$("$CLASH_BIN" -v 2>&1 || "$CLASH_BIN" -V 2>&1 || true)"
    CURRENT_INFO="$VERSION_OUTPUT"
    
    if echo "$VERSION_OUTPUT" | grep -qi "standard"; then
        CURRENT_TYPE="standard"
        TARGET_TYPE="minimal"
    elif echo "$VERSION_OUTPUT" | grep -qi "minimal"; then
        CURRENT_TYPE="minimal"
        TARGET_TYPE="standard"
    else
        # If unable to identify directly from -v output, assume minimal and switch to standard
        CURRENT_TYPE="minimal (inferred)"
        TARGET_TYPE="standard"
    fi
else
    CURRENT_INFO="Not installed (or path not found: $CLASH_BIN)"
    CURRENT_TYPE="none"
    TARGET_TYPE="standard"
fi

# 2. Detect CPU architecture and platform (Target Triple)
OS="$(uname -s)"
ARCH="$(uname -m)"
TARGET_TRIPLE=""

detect_libc() {
    if [ -f /etc/openwrt_release ]; then
        echo "musl"
        return
    fi
    if ldd /bin/sh 2>&1 | grep -qi "musl" || ls /lib/ld-musl* >/dev/null 2>&1; then
        echo "musl"
    elif ldd --version 2>&1 | grep -qi "musl"; then
        echo "musl"
    elif ldd --version 2>&1 | grep -qi "glibc\|gnu"; then
        echo "gnu"
    else
        echo "musl"
    fi
}

case "$OS" in
    Linux)
        LIBC="$(detect_libc)"
        case "$ARCH" in
            x86_64|amd64)
                [ "$LIBC" = "gnu" ] && TARGET_TRIPLE="x86_64-unknown-linux-gnu" || TARGET_TRIPLE="x86_64-unknown-linux-musl"
                ;;
            aarch64|arm64)
                [ "$LIBC" = "gnu" ] && TARGET_TRIPLE="aarch64-unknown-linux-gnu" || TARGET_TRIPLE="aarch64-unknown-linux-musl"
                ;;
            armv7*|armv8l|armhf|arm)
                [ "$LIBC" = "gnu" ] && TARGET_TRIPLE="armv7-unknown-linux-gnueabihf" || TARGET_TRIPLE="armv7-unknown-linux-musleabihf"
                ;;
            riscv64)
                TARGET_TRIPLE="riscv64gc-unknown-linux-musl"
                ;;
            i686|i386|x86)
                TARGET_TRIPLE="i686-unknown-linux-musl"
                ;;
            *)
                echo "❌ Unsupported CPU architecture: $ARCH"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "❌ This script only supports OpenWrt / Linux systems (Current OS: $OS)"
        exit 1
        ;;
esac

# 3. Construct download URL
# Ensure fallback to standard if switching from none
[ "$TARGET_TYPE" = "none" ] && TARGET_TYPE="standard"

ARCHIVE_NAME="clash-rs-${TARGET_TYPE}-${TARGET_TRIPLE}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE_NAME}"

# 4. Display current and target information
echo "=================================================="
echo "         Nikki RS Core Switch Tool"
echo "=================================================="
echo "[Current Status]"
echo "  - Core Path   : $CLASH_BIN"
echo "  - Core Version: $CURRENT_INFO"
echo "  - Core Type   : $CURRENT_TYPE"
echo "--------------------------------------------------"
echo "[Switch Target]"
echo "  - Target Type : $TARGET_TYPE"
echo "  - Arch Triple : $TARGET_TRIPLE"
echo "  - Package File: $ARCHIVE_NAME"
echo "  - Download URL: $DOWNLOAD_URL"
echo "=================================================="
echo ">> Switching core to [$TARGET_TYPE]..."

# 5. Download package
download_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --progress-bar "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        echo "❌ Error: Neither curl nor wget was found in the system. Please install one first!"
        return 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/clash-rs-switch.XXXXXX 2>/dev/null || mktemp -d 2>/dev/null || echo "/tmp/clash-rs-switch")"
mkdir -p "$TMP_DIR"
ARCHIVE_PATH="$TMP_DIR/$ARCHIVE_NAME"

echo "📥 Downloading latest release from GitHub..."
if ! download_file "$DOWNLOAD_URL" "$ARCHIVE_PATH"; then
    echo "❌ Download failed! Please check your network connection or GitHub access."
    rm -rf "$TMP_DIR"
    exit 1
fi

# 6. Extract and verify
echo "📦 Extracting package..."
if ! tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"; then
    echo "❌ Extraction failed!"
    rm -rf "$TMP_DIR"
    exit 1
fi

NEW_BIN="$(find "$TMP_DIR" -type f -name "clash-rs" | head -n1)"
if [ -z "$NEW_BIN" ] || [ ! -f "$NEW_BIN" ]; then
    echo "❌ Binary 'clash-rs' not found in extracted package!"
    rm -rf "$TMP_DIR"
    exit 1
fi

chmod +x "$NEW_BIN"

# 7. Replace binary core
TARGET_DIR="$(dirname "$CLASH_BIN")"
mkdir -p "$TARGET_DIR"

echo "🔄 Replacing core binary ($CLASH_BIN)..."
if ! (cp -f "$NEW_BIN" "${CLASH_BIN}.new" && chmod +x "${CLASH_BIN}.new" && mv -f "${CLASH_BIN}.new" "$CLASH_BIN"); then
    echo "❌ Failed to replace binary! Root privileges may be required, please run with root or sudo."
    rm -rf "$TMP_DIR"
    exit 1
fi

# 8. Restart service if running
if [ -x "/etc/init.d/nikki-rs" ]; then
    if /etc/init.d/nikki-rs status >/dev/null 2>&1 || [ -f "/var/run/nikki-rs.pid" ] || [ -f "/var/run/nikki-rs/nikki-rs.pid" ]; then
        echo "🔄 Restarting nikki-rs service..."
        /etc/init.d/nikki-rs restart >/dev/null 2>&1 || true
    fi
fi

# 9. Clean up temporary files
rm -rf "$TMP_DIR"

echo "=================================================="
echo "🎉 Core switch completed successfully!"
echo "🔍 Current core version:"
"$CLASH_BIN" -v || "$CLASH_BIN" -V || true
echo "=================================================="
