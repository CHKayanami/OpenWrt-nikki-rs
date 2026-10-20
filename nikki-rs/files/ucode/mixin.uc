#!/usr/bin/ucode

'use strict';

import { readfile } from 'fs';
import { cursor } from 'uci';
import { connect } from 'ubus';
import { uci_bool, uci_int, uci_array, uci_ports, uci_dscps, uci_fwmarks, trim_all, parse_proxy_links, parse_yaml_proxy, load_ip_list } from '/etc/nikki-rs/ucode/include.uc';

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
config['quic'] = uci_bool(uci.get('nikki-rs', 'mixin', 'quic'));

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

if (uci_bool(uci.get('nikki-rs', 'ebpf', 'enabled'))) {
	config['ebpf'] = {
		'enable': true,
		'lan-interface': uci_array(uci.get('nikki-rs', 'ebpf', 'lan_interface')),
		'wan-interface': uci.get('nikki-rs', 'ebpf', 'wan_interface'),
		'tproxy-port': uci_int(uci.get('nikki-rs', 'ebpf', 'tproxy_port')) || 12345,
		'auto-direct-offload': uci_bool(uci.get('nikki-rs', 'ebpf', 'auto_direct_offload')),
		'bypass-dscps': uci_dscps(uci.get('nikki-rs', 'ebpf', 'bypass_dscps') || uci.get('nikki-rs', 'ebpf', 'bypass_dscp')),
		'bypass-fwmarks': uci_fwmarks(uci.get('nikki-rs', 'ebpf', 'bypass_fwmarks') || uci.get('nikki-rs', 'ebpf', 'bypass_fwmark')),
		'lan': {
			'bypass-src-ports': uci_ports(uci.get('nikki-rs', 'ebpf', 'bypass_src_ports')),
			'proxy-src-ports': uci_ports(uci.get('nikki-rs', 'ebpf', 'proxy_src_ports')),
			'bypass-src-ips': uci_array(uci.get('nikki-rs', 'ebpf', 'bypass_src_ips')),
			'proxy-src-ips': uci_array(uci.get('nikki-rs', 'ebpf', 'proxy_src_ips')),
			'proxy-src-macs': uci_array(uci.get('nikki-rs', 'ebpf', 'proxy_src_macs'))
		},
		'host': {
			'proxy-local': uci_bool(uci.get('nikki-rs', 'ebpf', 'proxy_local')),
			'proxy-processes': uci_array(uci.get('nikki-rs', 'ebpf', 'proxy_processes')),
			'bypass-processes': uci_array(uci.get('nikki-rs', 'ebpf', 'bypass_processes'))
		},
		'target': {
			'bypass-dst-ports': uci_ports(uci.get('nikki-rs', 'ebpf', 'bypass_dst_ports')),
			'proxy-dst-ports': uci_ports(uci.get('nikki-rs', 'ebpf', 'proxy_dst_ports')),
			'bypass-dst-ips': uci_array(uci.get('nikki-rs', 'ebpf', 'bypass_dst_ips')),
			'proxy-dst-ips': uci_array(uci.get('nikki-rs', 'ebpf', 'proxy_dst_ips'))
		}
	};
}

// Ordered request rules select domestic DNS, foreign DNS (Fake IP or real IP), or reject.
if (uci_bool(uci.get('nikki-rs', 'mixin', 'dns2_enabled'))) {
	const get = (key, fallback) => uci.get('nikki-rs', 'mixin', 'dns2_' + key) ?? fallback;
	const domestic = uci_array(get('domestic_servers', ['223.5.5.5']));
	const foreign = uci_array(get('foreign_servers', ['1.1.1.1']));
	const mode = get('foreign_mode', 'fakeip');
	if (index(['fakeip', 'real'], mode) < 0) die('Invalid DNS2 foreign mode');
	const listen = get('listen', '[::]:1053');
	const request = [];
	uci.foreach('nikki-rs', 'dns2_rule', (section) => {
		if (!uci_bool(section.enabled)) return;
		if (index(['direct-dns', 'proxy-dns', 'reject'], section.target) < 0)
			die('Invalid DNS2 target');
		const rule = { invert: uci_bool(section.invert) };
		let conditions = 0;
		for (let field in [
			['domains', 'domain'], ['rule_sets', 'rule-set'],
			['query_types', 'query-type'], ['source_ip_cidrs', 'source-ip-cidr']
		]) {
			const values = filter(uci_array(section[field[0]]), (value) => length(trim(value)) > 0);
			if (length(values)) {
				rule[field[1]] = values;
				conditions++;
			}
		}
		if (!conditions) die('DNS2 routing rule requires at least one matching condition');
		if (section.target == 'reject') {
			rule.action = 'reject';
			rule['reject-code'] = section.reject_code || 'nxdomain';
		} else {
			rule.upstream = section.target;
		}
		push(request, rule);
	});
	const fallback = get('fallback', 'proxy-dns');
	if (index(['direct-dns', 'proxy-dns'], fallback) < 0) die('Invalid DNS2 fallback');
	push(request, { fallback: fallback });
	const hosts = {};
	if (uci_bool(get('use_hosts', '1')) && uci_bool(get('dnsmasq_hosts', '1'))) {
		let suffix = '';
		uci.foreach('dhcp', 'dnsmasq', (section) => {
			if (section.domain) suffix = section.domain;
		});
		const import_host = (section, qualify) => {
			const ips = uci_array(section.ip);
			if (!section.name || !length(ips)) return;
			for (let names in uci_array(section.name)) {
				for (let name in split(names, ' ')) {
					if (!length(name)) continue;
					hosts[name] = ips;
					if (qualify && suffix != '' && index(name, '.') == -1)
						hosts[name + '.' + suffix] = ips;
				}
			}
		};
		uci.foreach('dhcp', 'domain', (section) => import_host(section, false));
		uci.foreach('dhcp', 'host', (section) => import_host(section, true));
	}
	// Explicit DNS2 hosts take precedence over imported dnsmasq entries.
	uci.foreach('nikki-rs', 'dns2_hosts', (section) => {
		if (uci_bool(section.enabled) && section.domain) hosts[section.domain] = uci_array(section.ip);
	});
	config['dns']['enable'] = false;
	config['dns2'] = {
		enable: true,
		listen: listen,
		ipv6: uci_bool(get('ipv6', '1')),
		'use-hosts': uci_bool(get('use_hosts', '1')),
		hosts: hosts,
		'hosts-files': uci_array(get('hosts_files', [])),
		'default-nameserver': uci_array(get('bootstrap', ['223.5.5.5'])),
		'proxy-server-nameserver': uci_array(get('proxy_servers', [])),
		'optimistic-cache-ttl': uci_int(get('optimistic_cache_ttl', '0')),
		'stale-cache-retention': uci_int(get('stale_cache_retention', '3600')),
		'cache-capacity': uci_int(get('cache_capacity', '4096')),
		upstreams: [
			{ tag: 'direct-dns', type: 'remote', servers: domestic },
			mode == 'real' ? { tag: 'proxy-dns', type: 'remote', servers: foreign }
			: { tag: 'proxy-dns', type: 'fakeip', 'inet4-range': get('fake_ip_range', '198.18.0.1/16'),
				'inet6-range': get('fake_ip6_range', 'fc00::/18'), ttl: uci_int(get('fake_ip_ttl', '1')) }
		],
		routing: { request: request }
	};
	const domestic_subnet = trim(get('domestic_client_subnet', ''));
	const foreign_subnet = trim(get('foreign_client_subnet', ''));
	if (length(domestic_subnet)) config['dns2']['upstreams'][0]['client-subnet'] = domestic_subnet;
	if (mode == 'real' && length(foreign_subnet)) config['dns2']['upstreams'][1]['client-subnet'] = foreign_subnet;
	const foreign_proxy = trim(get('foreign_proxy', 'DIRECT'));
	if (mode == 'real' && length(foreign_proxy) && lc(foreign_proxy) != 'direct')
		config['dns2']['upstreams'][1]['proxy'] = foreign_proxy;

}

print(trim_all(config));
