#!/bin/sh

. "$IPKG_INSTROOT/etc/nikki-rs/scripts/include.sh"

# check nikki-rs.config.init
init=$(uci -q get nikki-rs.config.init); [ -z "$init" ] && return

# generate random string for api secret and authentication password
random=$(awk 'BEGIN{srand(); printf "%06d", int(rand() * 1000000)}')

# set nikki-rs.mixin.api_secret
uci set nikki-rs.mixin.api_secret="$random"

# set nikki-rs.@authentication[0].password
uci set nikki-rs.@authentication[0].password="$random"

# remove nikki-rs.config.init
uci del nikki-rs.config.init

# commit
uci commit nikki-rs

# exit with 0
exit 0

