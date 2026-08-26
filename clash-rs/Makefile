include $(TOPDIR)/rules.mk

PKG_NAME:=clash-rs
PKG_VERSION:=0.20.0_alpha
PKG_RELEASE:=1

# 架构映射与 SHA256 校验码
ifneq ($(findstring x86_64,$(ARCH)),)
  CLASH_TARGET:=x86_64-unknown-linux-musl
  CLASH_HASH:=81f936ac4a50f56827cb5e6548f73860f73b10324cb521d5c6a37fb29e4a63be
else ifneq ($(findstring aarch64,$(ARCH)),)
  CLASH_TARGET:=aarch64-unknown-linux-musl
  CLASH_HASH:=9829d29e5b90f71078a1b445408d5c460fc59cd3a7a839ea1f226b34d57bcfae
else ifneq ($(findstring arm,$(ARCH)),)
  CLASH_TARGET:=armv7-unknown-linux-musleabihf
  CLASH_HASH:=c950ce1dd1d175627f291b09883ee1130ad710b3f0c696c347a0d48d967d8d31
else ifneq ($(findstring riscv64,$(ARCH)),)
  CLASH_TARGET:=riscv64gc-unknown-linux-musl
  CLASH_HASH:=e0323fa58982529eacd647be91fe9a212b3029b4859185904b16d48775774dda
else ifneq ($(findstring i386,$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
  CLASH_HASH:=f60fdbad9bbe707ba4744a51b1d167a4aaf8c31b37b7c8f959c5274902d9fa31
else ifneq ($(findstring i686,$(ARCH)),)
  CLASH_TARGET:=i686-unknown-linux-musl
  CLASH_HASH:=f60fdbad9bbe707ba4744a51b1d167a4aaf8c31b37b7c8f959c5274902d9fa31
endif

PKG_HASH:=$(CLASH_HASH)

PKG_FLAGS:=nonshared

PKG_SOURCE:=clash-rs-minimal-$(CLASH_TARGET).tar.gz
PKG_SOURCE_URL:=https://github.com/CHKayanami/clash-rs/releases/download/v0.20.0-alpha/
PKG_BUILD_DIR:=$(BUILD_DIR)/clash-rs-minimal-$(CLASH_TARGET)

include $(INCLUDE_DIR)/package.mk

define Package/clash-rs
  SECTION:=net
  CATEGORY:=Network
  TITLE:=clash-rs proxy core (Latest Prebuilt from CHKayanami/clash-rs)
  URL:=https://github.com/CHKayanami/clash-rs
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) --strip-components=1 -C $(PKG_BUILD_DIR)
endef

define Build/Compile
	true
endef

define Package/clash-rs/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/clash-rs $(1)/usr/bin/clash-rs
endef

$(eval $(call BuildPackage,clash-rs))
