include $(TOPDIR)/rules.mk

PKG_NAME:=clash-rs
PKG_VERSION:=latest
PKG_RELEASE:=1

# 架构映射表
ifeq ($(ARCH),x86_64)
  CLASH_TARGET:=x86_64-unknown-linux-musl
endif
ifeq ($(ARCH),aarch64)
  CLASH_TARGET:=aarch64-unknown-linux-musl
endif
ifeq ($(ARCH),arm)
  CLASH_TARGET:=armv7-unknown-linux-musleabihf
endif

PKG_SOURCE:=clash-rs-minimal-$(CLASH_TARGET).tar.gz
PKG_SOURCE_URL:=https://github.com/CHKayanami/clash-rs/releases/latest/download/

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
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/clash $(1)/usr/bin/clash-rs
endef

$(eval $(call BuildPackage,clash-rs))
