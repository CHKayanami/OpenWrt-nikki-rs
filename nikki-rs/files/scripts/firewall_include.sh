#!/bin/sh

. "$IPKG_INSTROOT/lib/functions.sh"
. "$IPKG_INSTROOT/etc/nikki-rs/scripts/include.sh"

# fw4 can reload before nikki-rs starts or after it has stopped.
[ -f "$STARTED_FLAG_PATH" ] && [ -f "$RUN_PROFILE_PATH" ] || exit 0

config_load nikki-rs
config_get_bool enabled "config" "enabled" 0
config_get_bool core_only "config" "core_only" 0
config_get tun_listener_name "core" "tun_listener_name"
config_get_bool proxy_enabled "proxy" "enabled" 0 
config_get tcp_mode "proxy" "tcp_mode"
config_get udp_mode "proxy" "udp_mode"
config_get_bool ebpf_enabled "ebpf" "enabled" 0

if [ "$enabled" = 1 ] && [ "$core_only" = 0 ] && [ "$proxy_enabled" = 1 ] && [ "$ebpf_enabled" = 0 ]; then
	if [ "$tcp_mode" = "tun" ] || [ "$udp_mode" = "tun" ]; then
		tun_device=$(yq -M "(.tun | select(.enable) | .device) // ([(.listeners // [])[] | select(.name == \"$tun_listener_name\" and .type == \"tun\") | .device][0])" "$RUN_PROFILE_PATH") || exit 1
		[ -n "$tun_device" ] && [ "$tun_device" != "null" ] || exit 1
		# Replace our rules in one transaction, including duplicates and rules
		# for a previous TUN device. Leave other fw4 rules untouched.
		fw4_rules=$(nft --json list table inet fw4) || exit 1
		delete_rules=$(
			for chain in input forward; do
				handles=$(printf '%s\n' "$fw4_rules" | jsonfilter -q -e "@['nftables'][@['rule']['chain']='$chain' && @['rule']['comment']='nikki-rs']['rule']['handle']")
				for handle in $handles; do
					printf 'delete rule inet fw4 %s handle %s\n' "$chain" "$handle"
				done
			done
		)
		tun_device=$(printf '%s' "$tun_device" | sed 's/\\/\\\\/g; s/"/\\"/g')
		nft -f - <<-EOF
			$delete_rules
			insert rule inet fw4 input iifname "$tun_device" counter accept comment "nikki-rs"
			insert rule inet fw4 forward oifname "$tun_device" counter accept comment "nikki-rs"
			insert rule inet fw4 forward iifname "$tun_device" counter accept comment "nikki-rs"
		EOF
		exit $?
	fi
fi


exit 0
