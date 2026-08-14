#!/bin/sh
set -e

# ==============================================================================
# Nikki RS - clash-rs 核心切换脚本 (minimal <-> standard)
# ==============================================================================

REPO="CHKayanami/clash-rs"
TAG="latest"
CLASH_BIN="$(command -v clash-rs 2>/dev/null || echo "/usr/bin/clash-rs")"

# 1. 检查并获取当前核心版本与类型
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
        # 无法直接从 -v 输出识别时，默认当前为 minimal，目标切为 standard
        CURRENT_TYPE="minimal (推测)"
        TARGET_TYPE="standard"
    fi
else
    CURRENT_INFO="未安装 (或路径未找到: $CLASH_BIN)"
    CURRENT_TYPE="none"
    TARGET_TYPE="standard"
fi

# 2. 识别系统架构与平台 (Target Triple)
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
                echo "❌ 不支持的 CPU 架构: $ARCH"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "❌ 本脚本仅支持 OpenWrt / Linux 系统 (当前系统: $OS)"
        exit 1
        ;;
esac

# 3. 构造下载 URL
# 确保如果是从 none 切换，提供标准类型
[ "$TARGET_TYPE" = "none" ] && TARGET_TYPE="standard"

ARCHIVE_NAME="clash-rs-${TARGET_TYPE}-${TARGET_TRIPLE}.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARCHIVE_NAME}"

# 4. 显示当前及目标信息
echo "=================================================="
echo "         Nikki RS 核心版本切换工具"
echo "=================================================="
echo "【当前状态】"
echo "  - 核心路径: $CLASH_BIN"
echo "  - 当前版本: $CURRENT_INFO"
echo "  - 核心类型: $CURRENT_TYPE"
echo "--------------------------------------------------"
echo "【切换目标】"
echo "  - 目标类型: $TARGET_TYPE"
echo "  - 系统架构: $TARGET_TRIPLE"
echo "  - 下载文件: $ARCHIVE_NAME"
echo "  - 下载链接: $DOWNLOAD_URL"
echo "=================================================="

# 5. 等待用户输入 y 确认
printf "是否确认切换核心为 [%s] 版本？[y/N]: " "$TARGET_TYPE"
read -r CONFIRM

case "$CONFIRM" in
    [yY]|[yY][eE][sS])
        echo ">> 确认切换，开始下载..."
        ;;
    *)
        echo ">> 已取消操作。"
        exit 0
        ;;
esac

# 6. 下载工具检测与下载
download_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --progress-bar "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        echo "❌ 错误: 系统中未找到 curl 或 wget，请先安装！"
        return 1
    fi
}

TMP_DIR="$(mktemp -d /tmp/clash-rs-switch.XXXXXX 2>/dev/null || mktemp -d 2>/dev/null || echo "/tmp/clash-rs-switch")"
mkdir -p "$TMP_DIR"
ARCHIVE_PATH="$TMP_DIR/$ARCHIVE_NAME"

echo "📥 正在从 GitHub 下载最新版本..."
if ! download_file "$DOWNLOAD_URL" "$ARCHIVE_PATH"; then
    echo "❌ 下载失败！请检查网络连接或 GitHub 访问。"
    rm -rf "$TMP_DIR"
    exit 1
fi

# 7. 解压并校验
echo "📦 正在解压核心文件..."
if ! tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"; then
    echo "❌ 解压失败！"
    rm -rf "$TMP_DIR"
    exit 1
fi

NEW_BIN="$(find "$TMP_DIR" -type f -name "clash-rs" | head -n1)"
if [ -z "$NEW_BIN" ] || [ ! -f "$NEW_BIN" ]; then
    echo "❌ 解压包中未找到 clash-rs 二进制文件！"
    rm -rf "$TMP_DIR"
    exit 1
fi

chmod +x "$NEW_BIN"

# 8. 替换二进制核心
TARGET_DIR="$(dirname "$CLASH_BIN")"
mkdir -p "$TARGET_DIR"

echo "🔄 正在替换核心文件 ($CLASH_BIN) ..."
if ! (cp -f "$NEW_BIN" "${CLASH_BIN}.new" && chmod +x "${CLASH_BIN}.new" && mv -f "${CLASH_BIN}.new" "$CLASH_BIN"); then
    echo "❌ 替换文件失败！可能需要 root 权限，请尝试以 root 或 sudo 执行。"
    rm -rf "$TMP_DIR"
    exit 1
fi

# 9. 如果 nikki-rs 服务正在运行，则重启服务
if [ -x "/etc/init.d/nikki-rs" ]; then
    if /etc/init.d/nikki-rs status >/dev/null 2>&1 || [ -f "/var/run/nikki-rs.pid" ] || [ -f "/var/run/nikki-rs/nikki-rs.pid" ]; then
        echo "🔄 正在重启 nikki-rs 服务..."
        /etc/init.d/nikki-rs restart >/dev/null 2>&1 || true
    fi
fi

# 10. 清理临时文件
rm -rf "$TMP_DIR"

echo "=================================================="
echo "🎉 核心切换完成！"
echo "🔍 当前核心信息："
"$CLASH_BIN" -v || "$CLASH_BIN" -V || true
echo "=================================================="
