include $(TOPDIR)/rules.mk

PKG_NAME:=nikki-rs
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL3.0+
PKG_MAINTAINER:=Joseph Mory <morytyann@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/nikki-rs
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Transparent Proxy with clash-rs on OpenWrt.
  URL:=https://github.com/nikkinikki-org
  DEPENDS:=+ca-bundle +curl +yq firewall4 +ip-full +kmod-inet-diag +kmod-nft-socket +kmod-nft-tproxy +kmod-tun +kmod-dummy +clash-rs
endef

define Package/nikki-rs/conffiles
/etc/config/nikki-rs
/etc/nikki-rs/mixin.yaml
/etc/nikki-rs/profiles/default.yaml
/etc/nikki-rs/nftables/proxy_whitelist.txt
/etc/nikki-rs/nftables/proxy_whitelist6.txt
/etc/nikki-rs/dns/black_filter
/etc/nikki-rs/dns/fake_ip_filter
/etc/nikki-rs/dns/fallback_filter
endef

define Package/nikki-rs/install
	$(INSTALL_DIR) $(1)/etc/nikki-rs
	$(INSTALL_DIR) $(1)/etc/nikki-rs/ucode
	$(INSTALL_DIR) $(1)/etc/nikki-rs/scripts
	$(INSTALL_DIR) $(1)/etc/nikki-rs/dns
	$(INSTALL_DIR) $(1)/etc/nikki-rs/nftables
	$(INSTALL_DIR) $(1)/etc/nikki-rs/profiles
	$(INSTALL_DIR) $(1)/etc/nikki-rs/subscriptions
	$(INSTALL_DIR) $(1)/etc/nikki-rs/providers
	$(INSTALL_DIR) $(1)/etc/nikki-rs/providers/rule
	$(INSTALL_DIR) $(1)/etc/nikki-rs/providers/proxy
	$(INSTALL_DIR) $(1)/etc/nikki-rs/run
	$(INSTALL_DIR) $(1)/etc/nikki-rs/run/providers
	$(INSTALL_DIR) $(1)/etc/nikki-rs/run/providers/rule
	$(INSTALL_DIR) $(1)/etc/nikki-rs/run/providers/proxy

	$(INSTALL_DATA) $(CURDIR)/files/mixin.yaml $(1)/etc/nikki-rs/mixin.yaml
	$(INSTALL_DATA) $(CURDIR)/files/default.yaml $(1)/etc/nikki-rs/profiles/default.yaml

	$(INSTALL_BIN) $(CURDIR)/files/ucode/include.uc $(1)/etc/nikki-rs/ucode/include.uc
	$(INSTALL_BIN) $(CURDIR)/files/ucode/mixin.uc $(1)/etc/nikki-rs/ucode/mixin.uc
	$(INSTALL_BIN) $(CURDIR)/files/ucode/hijack.ut $(1)/etc/nikki-rs/ucode/hijack.ut

	$(INSTALL_BIN) $(CURDIR)/files/scripts/include.sh $(1)/etc/nikki-rs/scripts/include.sh
	$(INSTALL_BIN) $(CURDIR)/files/scripts/firewall_include.sh $(1)/etc/nikki-rs/scripts/firewall_include.sh
	$(INSTALL_BIN) $(CURDIR)/files/scripts/debug.sh $(1)/etc/nikki-rs/scripts/debug.sh

	$(INSTALL_DATA) $(CURDIR)/files/dns/black_filter $(1)/etc/nikki-rs/dns/black_filter
	$(INSTALL_DATA) $(CURDIR)/files/dns/fake_ip_filter $(1)/etc/nikki-rs/dns/fake_ip_filter
	$(INSTALL_DATA) $(CURDIR)/files/dns/fallback_filter $(1)/etc/nikki-rs/dns/fallback_filter

	$(INSTALL_DATA) $(CURDIR)/files/nftables/geoip_cn.txt $(1)/etc/nikki-rs/nftables/geoip_cn.txt
	$(INSTALL_DATA) $(CURDIR)/files/nftables/geoip6_cn.txt $(1)/etc/nikki-rs/nftables/geoip6_cn.txt
	$(INSTALL_DATA) $(CURDIR)/files/nftables/proxy_whitelist.txt $(1)/etc/nikki-rs/nftables/proxy_whitelist.txt
	$(INSTALL_DATA) $(CURDIR)/files/nftables/proxy_whitelist6.txt $(1)/etc/nikki-rs/nftables/proxy_whitelist6.txt

	$(INSTALL_DATA) $(CURDIR)/files/rule/* $(1)/etc/nikki-rs/providers/rule/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/nikki-rs.conf $(1)/etc/config/nikki-rs

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/nikki-rs.init $(1)/etc/init.d/nikki-rs

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(CURDIR)/files/uci-defaults/firewall.sh $(1)/etc/uci-defaults/99_firewall_nikki-rs
	$(INSTALL_BIN) $(CURDIR)/files/uci-defaults/init.sh $(1)/etc/uci-defaults/99_init_nikki-rs
	$(INSTALL_BIN) $(CURDIR)/files/uci-defaults/migrate.sh $(1)/etc/uci-defaults/99_migrate_nikki-rs

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) $(CURDIR)/files/nikki-rs.upgrade $(1)/lib/upgrade/keep.d/nikki-rs
endef

define Package/nikki-rs/postrm
#!/bin/sh
if [ -z $${IPKG_INSTROOT} ]; then
	uci -q batch <<-EOF > /dev/null
		del firewall.nikki_rs
		commit firewall
	EOF
fi
endef

define Build/Compile

endef

$(eval $(call BuildPackage,nikki-rs))

