#!/bin/sh

. "$IPKG_INSTROOT/etc/nikki-rs/scripts/include.sh"

# check nikki-rs.config.init
init=$(uci -q get nikki-rs.config.init); [ -z "$init" ] && return

# generate random string for api secret and authentication password
random=$(awk 'BEGIN{srand(); printf "%06d", int(rand() * 1000000)}')

# set nikki-rs.mixin.api_secret
if [ -z "$(uci -q get nikki-rs.mixin.api_secret)" ]; then
	uci set nikki-rs.mixin.api_secret="$random"
fi

# set nikki-rs.@authentication[0].password
if uci -q get nikki-rs.@authentication[0] >/dev/null; then
	if [ -z "$(uci -q get nikki-rs.@authentication[0].password)" ]; then
		uci set nikki-rs.@authentication[0].password="$random"
	fi
fi

# remove nikki-rs.config.init
uci del nikki-rs.config.init

# commit
uci commit nikki-rs

# exit with 0
exit 0

