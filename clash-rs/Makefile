include $(TOPDIR)/rules.mk

PKG_NAME:=clash-rs
PKG_VERSION:=0.20.0-alpha
PKG_RELEASE:=1

# 架构映射与 SHA256 校验码
ifneq ($(findstring x86_64,$(ARCH)),)
  CLASH_TARGET:=x86_64-unknown-linux-musl
  CLASH_HASH:=e14c3ce6f6df7f6ad36702100d8cd3ceed35fa0fde53ec67c898a1a7b30164a1
else ifneq ($(findstring aarch64,$(ARCH)),)
  CLASH_TARGET:=aarch64-unknown-linux-musl
  CLASH_HASH:=a5ed70ca9ef6fd7e62072d7e1b7ccf83aab508fe71151be229d8bd3bf787919e
else ifneq ($(findstring arm,$(ARCH)),)
  CLASH_TARGET:=armv7-unknown-linux-musleabihf
  CLASH_HASH:=7ea01c1d8d061d2d20fdec5b1621c7a2ed1586e8da56f3a50af2cb5dd22e6532
else ifneq ($(findstring riscv64,$(ARCH)),)
  CLASH_TARGET:=riscv64gc-unknown-linux-musl
  CLASH_HASH:=e30a64574b718085cc8a043831f9010a48af0c4139254f04698403e3173939c5
else ifneq ($(findstring i386,$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
  CLASH_HASH:=2a6d3a5c9560e6d48b289d817df0dd5201160e37748ba0b94b69623e0661ba32
else ifneq ($(findstring i686,$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
  CLASH_HASH:=2a6d3a5c9560e6d48b289d817df0dd5201160e37748ba0b94b69623e0661ba32
endif

PKG_HASH:=$(CLASH_HASH)

PKG_SOURCE:=clash-rs-minimal-$(CLASH_TARGET).tar.gz
PKG_SOURCE_URL:=https://github.com/CHKayanami/clash-rs/releases/download/latest/
PKG_BUILD_DIR:=$(BUILD_DIR)/clash-rs-minimal-$(CLASH_TARGET)

include $(INCLUDE_DIR)/package.mk

define Package/clash-rs
  SECTION:=net
  CATEGORY:=Network
  TITLE:=clash-rs proxy core (Latest Prebuilt from CHKayanami/clash-rs)
endef

define Build/Compile
	# 预编译最新版无需编译，解压即用
endef

define Package/clash-rs/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/clash-rs $(1)/usr/bin/clash-rs
endef

$(eval $(call BuildPackage,clash-rs))
