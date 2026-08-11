#!/usr/bin/env bash
set -eo pipefail

REPO="CHKayanami/clash-rs"
MAKEFILE="clash-rs/Makefile"

# 支持传入指定版本号，例如: ./update-clash-rs.sh 0.1.7
INPUT_VER="$1"

echo "🔍 正在检查 $REPO 的最新发布版本..."

get_release_json() {
  local json=""
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [ -n "$token" ]; then
    json=$(curl -sL -H "User-Agent: OpenWrt-nikki-build" -H "Authorization: Bearer $token" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)
    if [[ "$json" == *'"tag_name"'* ]]; then
      echo "$json"
      return 0
    fi
  fi
  curl -sL -H "User-Agent: OpenWrt-nikki-build" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true
}

RELEASE_JSON=$(get_release_json)
TAG_NAME=""

if command -v jq >/dev/null 2>&1; then
  TAG_NAME=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty' 2>/dev/null || true)
fi

if [ -z "$TAG_NAME" ] || [ "$TAG_NAME" = "null" ]; then
  TAG_NAME=$(echo "$RELEASE_JSON" | grep -o '"tag_name": "[^"]*' | head -n1 | cut -d'"' -f4 2>/dev/null || true)
fi

if [ -z "$TAG_NAME" ]; then
  echo "❌ 获取最新版本失败！GitHub API 响应如下："
  echo "$RELEASE_JSON"
  exit 1
fi

if [ -n "$INPUT_VER" ]; then
  VERSION="$INPUT_VER"
else
  VERSION="${TAG_NAME#v}"
  if [ "$VERSION" = "latest" ]; then
    VERSION="0.1.7"
  fi
fi

echo "✨ 最新发布 Tag 为: $TAG_NAME (Package Version: $VERSION)"

echo "📥 正在实时下载并计算各架构的 SHA256 哈希值..."

get_hash() {
  local target="$1"
  local url="https://github.com/${REPO}/releases/download/${TAG_NAME}/clash-rs-minimal-${target}.tar.gz"
  curl -sL -H "User-Agent: OpenWrt-nikki-build" "$url" | sha256sum | awk '{print $1}'
}

HASH_X86_64=$(get_hash "x86_64-unknown-linux-musl")
echo "  - x86_64: $HASH_X86_64"

HASH_AARCH64=$(get_hash "aarch64-unknown-linux-musl")
echo "  - aarch64: $HASH_AARCH64"

HASH_ARMV7=$(get_hash "armv7-unknown-linux-musleabihf")
echo "  - armv7: $HASH_ARMV7"

HASH_RISCV64=$(get_hash "riscv64gc-unknown-linux-musl")
echo "  - riscv64: $HASH_RISCV64"

HASH_I686=$(get_hash "i686-unknown-linux-musl")
echo "  - i686: $HASH_I686"

echo "📝 正在更新 $MAKEFILE ..."

cat > "$MAKEFILE" << EOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=clash-rs
PKG_VERSION:=$VERSION
PKG_RELEASE:=1

# 架构映射与 SHA256 校验码
ifneq (\$(findstring x86_64,\$(ARCH)),)
  CLASH_TARGET:=x86_64-unknown-linux-musl
  CLASH_HASH:=$HASH_X86_64
else ifneq (\$(findstring aarch64,\$(ARCH)),)
  CLASH_TARGET:=aarch64-unknown-linux-musl
  CLASH_HASH:=$HASH_AARCH64
else ifneq (\$(findstring arm,\$(ARCH)),)
  CLASH_TARGET:=armv7-unknown-linux-musleabihf
  CLASH_HASH:=$HASH_ARMV7
else ifneq (\$(findstring riscv64,\$(ARCH)),)
  CLASH_TARGET:=riscv64gc-unknown-linux-musl
  CLASH_HASH:=$HASH_RISCV64
else ifneq (\$(findstring i386,\$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
  CLASH_HASH:=$HASH_I686
else ifneq (\$(findstring i686,\$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
  CLASH_HASH:=$HASH_I686
endif

PKG_HASH:=\$(CLASH_HASH)

PKG_SOURCE:=clash-rs-minimal-\$(CLASH_TARGET).tar.gz
PKG_SOURCE_URL:=https://github.com/${REPO}/releases/download/${TAG_NAME}/
PKG_BUILD_DIR:=\$(BUILD_DIR)/clash-rs-minimal-\$(CLASH_TARGET)

include \$(INCLUDE_DIR)/package.mk

define Package/clash-rs
  SECTION:=net
  CATEGORY:=Network
  TITLE:=clash-rs proxy core (Latest Prebuilt from ${REPO})
endef

define Build/Compile
	# 预编译最新版无需编译，解压即用
endef

define Package/clash-rs/install
	\$(INSTALL_DIR) \$(1)/usr/bin
	\$(INSTALL_BIN) \$(PKG_BUILD_DIR)/clash-rs \$(1)/usr/bin/clash-rs
endef

\$(eval \$(call BuildPackage,clash-rs))
EOF

echo "🎉 $MAKEFILE 已成功更新至版本 $VERSION ！"
