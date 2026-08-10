#!/bin/sh

. "$IPKG_INSTROOT/etc/nikki-rs/scripts/include.sh"

uci -q batch <<-EOF > /dev/null
	del firewall.nikki_rs
	set firewall.nikki_rs=include
	set firewall.nikki_rs.type=script
	set firewall.nikki_rs.path=$FIREWALL_INCLUDE_SH
	set firewall.nikki_rs.fw4_compatible=1
	commit firewall
EOF

