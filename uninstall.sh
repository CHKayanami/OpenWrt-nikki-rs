#!/bin/sh

# Nikki's uninstaller

repository_url="https://openwrt-nikki-rs.alamayachk.workers.dev"

# uninstall
if [ -x "/bin/opkg" ]; then
	opkg list-installed luci-i18n-nikki-rs-* | cut -d ' ' -f 1 | xargs opkg remove
	opkg remove luci-app-nikki-rs
	opkg remove nikki-rs
	opkg remove clash-rs
elif [ -x "/usr/bin/apk" ]; then
	apk list --installed --manifest luci-i18n-nikki-rs-* | cut -d ' ' -f 1 | xargs apk del
	apk del luci-app-nikki-rs
	apk del nikki-rs
	apk del clash-rs
fi
# remove config
rm -f /etc/config/nikki-rs
# remove files
rm -rf /etc/nikki-rs
# remove log
rm -rf /var/log/nikki-rs
# remove temp
rm -rf /var/run/nikki-rs
# remove feed
if [ -x "/bin/opkg" ]; then
	if grep -q nikki-rs /etc/opkg/customfeeds.conf; then
		sed -i '/nikki-rs/d' /etc/opkg/customfeeds.conf
	fi
	wget -O "nikki-rs.pub" "$repository_url/key-build.pub"
	opkg-key remove nikki-rs.pub
	rm -f nikki-rs.pub
elif [ -x "/usr/bin/apk" ]; then
	if grep -q nikki-rs /etc/apk/repositories.d/customfeeds.list; then
		sed -i '/nikki-rs/d' /etc/apk/repositories.d/customfeeds.list
	fi
	rm -f /etc/apk/keys/nikki-rs.pem
fi
