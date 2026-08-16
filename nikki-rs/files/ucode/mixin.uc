#!/usr/bin/ucode

'use strict';

import { readfile } from 'fs';
import { cursor } from 'uci';
import { connect } from 'ubus';
import { uci_bool, uci_int, uci_array, trim_all, parse_proxy_links, parse_yaml_proxy, load_ip_list } from '/etc/nikki-rs/ucode/include.uc';

const uci = cursor();
const ubus = connect();

const config = {};

const outbound_interface = uci.get('nikki-rs', 'mixin', 'outbound_interface');
const outbound_interface_status = ubus.call('network.interface', 'status', { 'interface': outbound_interface });
const outbound_device = outbound_interface_status?.l3_device ?? outbound_interface_status?.device ?? '';

config['log-level'] = uci.get('nikki-rs', 'mixin', 'log_level');
config['mode'] = uci.get('nikki-rs', 'mixin', 'mode');
config['find-process-mode'] = uci.get('nikki-rs', 'mixin', 'match_process');
config['interface-name'] = outbound_device;
config['ipv6'] = uci_bool(uci.get('nikki-rs', 'mixin', 'ipv6'));

if (!uci_bool(uci.get('nikki-rs', 'mixin', 'ui_internal'))) {
	config['external-ui'] = uci.get('nikki-rs', 'mixin', 'ui_path');
	config['external-ui-name'] = uci.get('nikki-rs', 'mixin', 'ui_name');
	config['external-ui-url'] = uci.get('nikki-rs', 'mixin', 'ui_url');
}
config['external-controller'] = uci.get('nikki-rs', 'mixin', 'api_listen');
config['secret'] = uci.get('nikki-rs', 'mixin', 'api_secret');

config['allow-lan'] = uci_bool(uci.get('nikki-rs', 'mixin', 'allow_lan'));
config['port'] = uci_int(uci.get('nikki-rs', 'mixin', 'http_port'));
config['socks-port'] = uci_int(uci.get('nikki-rs', 'mixin', 'socks_port'));
config['mixed-port'] = uci_int(uci.get('nikki-rs', 'mixin', 'mixed_port'));
config['redir-port'] = uci_int(uci.get('nikki-rs', 'mixin', 'redir_port'));
config['tproxy-port'] = uci_int(uci.get('nikki-rs', 'mixin', 'tproxy_port'));

if (uci_bool(uci.get('nikki-rs', 'mixin', 'overwrite_mmdb'))) {
	config['mmdb'] = uci.get('nikki-rs', 'mixin', 'mmdb') || 'Country.mmdb';
	config['mmdb-download-url'] = uci.get('nikki-rs', 'mixin', 'mmdb_download_url') || 'https://cdn.jsdelivr.net/gh/DustinWin/ruleset_geodata@mihomo-geodata/Country.mmdb';
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'overwrite_geosite'))) {
	config['geosite'] = uci.get('nikki-rs', 'mixin', 'geosite') || 'geosite.dat';
	config['geosite-download-url'] = uci.get('nikki-rs', 'mixin', 'geosite_download_url') || 'https://cdn.jsdelivr.net/gh/DustinWin/ruleset_geodata@mihomo-geodata/geosite-lite.dat';
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'overwrite_asn_mmdb'))) {
	config['asn-mmdb'] = uci.get('nikki-rs', 'mixin', 'asn_mmdb') || 'Country-ASN.mmdb';
	config['asn-mmdb-download-url'] = uci.get('nikki-rs', 'mixin', 'asn_mmdb_download_url') || 'https://cdn.jsdelivr.net/gh/DustinWin/ruleset_geodata@mihomo-geodata/Country-ASN.mmdb';
}

if (uci_bool(uci.get('nikki-rs', 'mixin', 'authentication'))) {
	config['authentication'] = [];
	uci.foreach('nikki-rs', 'authentication', (section) => {
		if (!uci_bool(section.enabled)) {
			return;
		}
		push(config['authentication'], `${section.username}:${section.password}`);
	});
}

config['tun'] = {};
config['tun']['enable'] = uci_bool(uci.get('nikki-rs', 'mixin', 'tun_enabled'));
config['tun']['enable-tcp'] = uci_bool(uci.get('nikki-rs', 'mixin', 'tun_enable_tcp'));
config['tun']['device'] = uci.get('nikki-rs', 'mixin', 'tun_device');
config['tun']['stack'] = uci.get('nikki-rs', 'mixin', 'tun_stack');
config['tun']['mtu'] = uci_int(uci.get('nikki-rs', 'mixin', 'tun_mtu'));
config['tun']['gso'] = uci_bool(uci.get('nikki-rs', 'mixin', 'tun_gso'));
config['tun']['gso-max-size'] = uci_int(uci.get('nikki-rs', 'mixin', 'tun_gso_max_size'));
if (uci_bool(uci.get('nikki-rs', 'mixin', 'tun_dns_hijack'))) {
	config['tun']['dns-hijack'] = uci_array(uci.get('nikki-rs', 'mixin', 'tun_dns_hijacks'));
}

config['dns'] = {};
config['dns']['enable'] = uci_bool(uci.get('nikki-rs', 'mixin', 'dns_enabled'));
config['dns']['listen'] = uci.get('nikki-rs', 'mixin', 'dns_listen');
config['dns']['ipv6'] = uci_bool(uci.get('nikki-rs', 'mixin', 'dns_ipv6'));
config['dns']['enhanced-mode'] = uci.get('nikki-rs', 'mixin', 'dns_mode');
config['dns']['fake-ip-range'] = uci.get('nikki-rs', 'mixin', 'fake_ip_range');
config['dns']['fake-ip-range6'] = uci.get('nikki-rs', 'mixin', 'fake_ip6_range');
config['dns']['fake-ip-ttl'] = uci_int(uci.get('nikki-rs', 'mixin', 'fake_ip_ttl'));
config['dns']['fake-ip-filter-mode'] = uci.get('nikki-rs', 'mixin', 'fake_ip_filter_mode');
if (uci_bool(uci.get('nikki-rs', 'mixin', 'fake_ip_filter'))) {
	config['dns']['fake-ip-filter'] = uci_array(uci.get('nikki-rs', 'mixin', 'fake_ip_filters'));
}
const fake_ip_filter = load_ip_list('/etc/nikki-rs/dns/fake_ip_filter');
if (length(fake_ip_filter) > 0) {
	if (config['dns']['fake-ip-filter'] == null) {
		config['dns']['fake-ip-filter'] = [];
	}
	push(config['dns']['fake-ip-filter'], ...fake_ip_filter);
}

const fallback_filter = load_ip_list('/etc/nikki-rs/dns/fallback_filter');
if (length(fallback_filter) > 0) {
	if (config['dns']['fallback-filter'] == null) {
		config['dns']['fallback-filter'] = {};
	}
	if (config['dns']['fallback-filter']['domain'] == null) {
		config['dns']['fallback-filter']['domain'] = [];
	}
	push(config['dns']['fallback-filter']['domain'], ...fallback_filter);
}

if (uci_bool(uci.get('nikki-rs', 'mixin', 'black_filter'))) {
	config['dns']['black-filter'] = uci_array(uci.get('nikki-rs', 'mixin', 'black_filters'));
}
const black_filter = load_ip_list('/etc/nikki-rs/dns/black_filter');
if (length(black_filter) > 0) {
	if (config['dns']['black-filter'] == null) {
		config['dns']['black-filter'] = [];
	}
	push(config['dns']['black-filter'], ...black_filter);
}

config['dns']['respect-rules'] = uci_bool(uci.get('nikki-rs', 'mixin', 'dns_respect_rules'));
config['dns']['use-hosts'] = uci_bool(uci.get('nikki-rs', 'mixin', 'dns_hosts'));
if (uci_bool(uci.get('nikki-rs', 'mixin', 'hosts'))) {
	config['hosts'] = {};
	const format_hosts_ip = (ip) => {
		let ips = uci_array(ip);
		if (length(ips) == 0) {
			return null;
		}
		for (let item in ips) {
			if (index(item, '.') != -1 && index(item, ':') == -1) {
				return item;
			}
		}
		return ips[0];
	};
	uci.foreach('nikki-rs', 'hosts', (section) => {
		if (!uci_bool(section.enabled)) {
			return;
		}
		let formatted_ip = format_hosts_ip(section.ip);
		if (formatted_ip != null) {
			config['hosts'][section.domain_name] = formatted_ip;
		}
	});
	if (uci_bool(uci.get('nikki-rs', 'mixin', 'dnsmasq_hosts'))) {
		let domain_suffix = '';
		uci.foreach('dhcp', 'dnsmasq', (section) => {
			if (section.domain) {
				domain_suffix = section.domain;
			}
		});
		uci.foreach('dhcp', 'domain', (section) => {
			if (section.name && section.ip) {
				let formatted_ip = format_hosts_ip(section.ip);
				if (formatted_ip != null) {
					let names = uci_array(section.name);
					for (let name in names) {
						let subnames = split(name, ' ');
						for (let subname in subnames) {
							if (length(subname) > 0) {
								config['hosts'][subname] = formatted_ip;
							}
						}
					}
				}
			}
		});
		uci.foreach('dhcp', 'host', (section) => {
			if (section.name && section.ip) {
				let formatted_ip = format_hosts_ip(section.ip);
				if (formatted_ip != null) {
					let names = uci_array(section.name);
					for (let name in names) {
						let subnames = split(name, ' ');
						for (let subname in subnames) {
							if (length(subname) > 0) {
								config['hosts'][subname] = formatted_ip;
								if (domain_suffix != '' && index(subname, '.') == -1) {
									config['hosts'][subname + '.' + domain_suffix] = formatted_ip;
								}
							}
						}
					}
				}
			}
		});
	}
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'dns_nameserver'))) {
	config['dns']['default-nameserver'] = [];
	config['dns']['proxy-server-nameserver'] = [];
	config['dns']['direct-nameserver'] = [];
	config['dns']['nameserver'] = [];
	config['dns']['fallback'] = [];
	uci.foreach('nikki-rs', 'nameserver', (section) => {
		if (!uci_bool(section.enabled)) {
			return;
		}
		push(config['dns'][section.type], ...uci_array(section.nameserver));
	})
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'dns_proxy_server_nameserver'))) {
	config['dns']['proxy-server-nameserver'] = uci_array(uci.get('nikki-rs', 'mixin', 'dns_proxy_server_nameservers'));
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'dns_nameserver_policy'))) {
	config['dns']['nameserver-policy'] = {};
	uci.foreach('nikki-rs', 'nameserver_policy', (section) => {
		if (!uci_bool(section.enabled)) {
			return;
		}
		config['dns']['nameserver-policy'][section.matcher] = uci_array(section.nameserver);
	});
}

config['sniffer'] = {};
config['sniffer']['enable'] = uci_bool(uci.get('nikki-rs', 'mixin', 'sniffer'));
config['sniffer']['force-dns-mapping'] = uci_bool(uci.get('nikki-rs', 'mixin', 'sniffer_sniff_dns_mapping'));
config['sniffer']['parse-pure-ip'] = uci_bool(uci.get('nikki-rs', 'mixin', 'sniffer_sniff_pure_ip'));
if (uci_bool(uci.get('nikki-rs', 'mixin', 'sniffer_force_domain_name'))) {
	config['sniffer']['force-domain'] = uci_array(uci.get('nikki-rs', 'mixin', 'sniffer_force_domain_names'));
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'sniffer_ignore_domain_name'))) {
	config['sniffer']['skip-domain'] = uci_array(uci.get('nikki-rs', 'mixin', 'sniffer_ignore_domain_names'));
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'sniffer_sniff'))) {
	config['sniffer']['sniff'] = {};
	uci.foreach('nikki-rs', 'sniff', (section) => {
		if (!uci_bool(section.enabled) || !section.protocol) {
			return;
		}
		config['sniffer']['sniff'][section.protocol] = {
			ports: uci_array(section.port),
			'override-destination': uci_bool(section.overwrite_destination)
		};
	});
}

if (uci_bool(uci.get('nikki-rs', 'mixin', 'rule_provider'))) {
	config['rule-providers'] = {};
	uci.foreach('nikki-rs', 'rule_provider', (section) => {
		if (!uci_bool(section.enabled)) {
			return;
		}
		let file_path = section.file_path;
		if (section.type == 'http' && (file_path == null || length(file_path) == 0)) {
			file_path = sprintf('/etc/nikki-rs/providers/rule/%s.%s', section.name, section.file_format ?? 'yaml');
		}
		config['rule-providers'][section.name] = {
			type: 'file',
			path: file_path,
			format: section.file_format,
			behavior: section.behavior,
		};
	});
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'rule'))) {
	config['nikki-rules'] = [];
	uci.foreach('nikki-rs', 'rule', (section) => {
		if (!uci_bool(section.enabled)) {
			return;
		}
		const rule = [ section.type, section.matcher, section.node, uci_bool(section.no_resolve) ? 'no-resolve' : null ];
		push(config['nikki-rules'], join(',', filter(rule, (item) => item != null && item != '')));
	})
}
if (uci_bool(uci.get('nikki-rs', 'mixin', 'proxy_node'))) {
	config['nikki-proxies'] = [];
	uci.foreach('nikki-rs', 'proxy_node', (section) => {
		if (!uci_bool(section.enabled)) {
			return;
		}
		let parsed_list = null;
		if (section.yaml != null && length(trim(section.yaml)) > 0) {
			parsed_list = parse_yaml_proxy(section.yaml);
		}
		if (parsed_list == null && section.link != null && length(trim(section.link)) > 0) {
			parsed_list = parse_proxy_links(section.link);
		}
		if (parsed_list != null) {
			for (let p in parsed_list) {
				if (section.name != null && length(trim(section.name)) > 0 && length(parsed_list) == 1) {
					p.name = section.name;
				}
				push(config['nikki-proxies'], p);
			}
		}
	});
}

print(trim_all(config));