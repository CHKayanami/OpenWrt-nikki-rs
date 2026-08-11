include $(TOPDIR)/rules.mk

PKG_NAME:=clash-rs
PKG_VERSION:=0.1.6
PKG_RELEASE:=1
PKG_HASH:=skip

PKG_ARCH_ONLY:=x86_64 aarch64 arm riscv64 i386 i686

# 架构映射表
ifneq ($(findstring x86_64,$(ARCH)),)
  CLASH_TARGET:=x86_64-unknown-linux-musl
else ifneq ($(findstring aarch64,$(ARCH)),)
  CLASH_TARGET:=aarch64-unknown-linux-musl
else ifneq ($(findstring arm,$(ARCH)),)
  CLASH_TARGET:=armv7-unknown-linux-musleabihf
else ifneq ($(findstring riscv64,$(ARCH)),)
  CLASH_TARGET:=riscv64gc-unknown-linux-musl
else ifneq ($(findstring i386,$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
else ifneq ($(findstring i686,$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
endif

PKG_SOURCE:=clash-rs-minimal-$(CLASH_TARGET).tar.gz
PKG_SOURCE_URL:=https://github.com/CHKayanami/clash-rs/releases/latest/download/
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
