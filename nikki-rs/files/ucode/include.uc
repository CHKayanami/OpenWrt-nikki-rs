import { readfile, popen, writefile } from 'fs';

export function uci_bool(obj) {
	return obj == null ? null : obj == '1';
};

export function uci_int(obj) {
	return obj == null ? null : int(obj);
};

export function uci_array(obj) {
	if (obj == null) {
		return [];
	}
	if (type(obj) == 'array') {
		return uniq(obj);
	}
	return [obj];
};

export function trim_all(obj) {
	if (obj == null) {
		return null;
	}
	if (type(obj) == 'string') {
		if (length(obj) == 0) {
			return null;
		}
		return obj;
	}
	if (type(obj) == 'array') {
		if (length(obj) == 0) {
			return null;
		}
		return obj;
	}
	if (type(obj) == 'object') {
		const obj_keys = keys(obj);
		for (let key in obj_keys) {
			obj[key] = trim_all(obj[key]);
			if (obj[key] == null) {
				delete obj[key];
			}
		}
		if (length(keys(obj)) == 0) {
			return null;
		}
		return obj;
	}
	return obj;
};

export function get_cgroups_version() {
	return system('mount | grep -q -w "^cgroup"') == 0 ? 1 : 2;
};

export function get_users() {
	return map(split(readfile('/etc/passwd'), '\n'), (x) => split(x, ':')[0]);
};

export function get_groups() {
	return map(split(readfile('/etc/group'), '\n'), (x) => split(x, ':')[0]);
};

export function get_cgroups() {
	const result = [];
	if (get_cgroups_version() == 2) {
		const cgroup_path = '/sys/fs/cgroup/';
		const process = popen(`find ${cgroup_path} -type d -mindepth 1`);
		if (process) {
			for (let line = process.read('line'); length(line); line = process.read('line')) {
				push(result, substr(trim(line), length(cgroup_path)));
			}
		}
	}
	return result;
};

export function load_profile() {
	let result = {};
	const process = popen('yq -M -p yaml -o json /etc/nikki-rs/run/config.yaml');
	if (process) {
		result = json(process);
		process.close();
	}
	return result;
};


export function load_ip_list(filepath) {
	const result = [];
	const file_content = readfile(filepath);
	if (file_content != null) {
		const lines = split(trim(file_content), '\n');
		for (let line in lines) {
			line = trim(line);
			if (length(line) > 0 && substr(line, 0, 1) != '#') {
				push(result, line);
			}
		}
	}
	return result;
};

export function urldecode(str) {
	if (str == null) return '';
	let s = replace(str, /\+/g, ' ');
	let res = '';
	let len = length(s);
	let i = 0;
	while (i < len) {
		if (substr(s, i, 1) == '%' && i + 2 < len) {
			let hex = substr(s, i + 1, 2);
			if (match(hex, /^[0-9A-Fa-f]{2}$/)) {
				res += sprintf('%c', hexint(hex));
				i += 3;
				continue;
			}
		}
		res += substr(s, i, 1);
		i++;
	}
	return res;
};

export function parse_query(query_str) {
	const params = {};
	if (query_str == null || length(query_str) == 0) return params;
	const pairs = split(query_str, '&');
	for (let pair in pairs) {
		if (length(pair) == 0) continue;
		const eq = index(pair, '=');
		if (eq > 0) {
			const k = urldecode(substr(pair, 0, eq));
			const v = urldecode(substr(pair, eq + 1));
			params[k] = v;
		} else {
			params[urldecode(pair)] = '';
		}
	}
	return params;
};

export function parse_host_port(host_port, default_port) {
	if (host_port == null) return { server: '', port: default_port };
	let hp = trim(host_port);
	let server = hp;
	let port = default_port;

	const bracket_close = rindex(hp, ']');
	if (bracket_close >= 0) {
		server = substr(hp, 0, bracket_close + 1);
		const remainder = substr(hp, bracket_close + 1);
		const colon_idx = index(remainder, ':');
		if (colon_idx >= 0) {
			const p = int(substr(remainder, colon_idx + 1));
			if (p > 0) port = p;
		}
	} else {
		const colons = split(hp, ':');
		if (length(colons) == 2) {
			server = colons[0];
			const p = int(colons[1]);
			if (p > 0) port = p;
		} else if (length(colons) > 2) {
			server = hp;
		}
	}

	server = replace(server, /[\[\]"]/g, '');
	server = trim(server);

	return { server: server, port: port };
};

function parse_anytls(link) {
	let name = '';
	let rest = substr(link, 9);
	const hash_idx = index(rest, '#');
	if (hash_idx >= 0) {
		name = urldecode(substr(rest, hash_idx + 1));
		rest = substr(rest, 0, hash_idx);
	}
	let query_str = '';
	const query_idx = index(rest, '?');
	if (query_idx >= 0) {
		query_str = substr(rest, query_idx + 1);
		rest = substr(rest, 0, query_idx);
	}
	const at_idx = index(rest, '@');
	if (at_idx < 0) return null;

	const password = urldecode(substr(rest, 0, at_idx));
	const host_port = substr(rest, at_idx + 1);
	const hp = parse_host_port(host_port, 443);
	const server = hp.server;
	const port = hp.port;

	const params = parse_query(query_str);
	const proxy = {
		name: length(name) > 0 ? name : `${server}:${port}`,
		type: 'anytls',
		server: server,
		port: port,
		password: password,
		udp: true
	};

	const sni = params.sni ?? params.peer ?? params.servername;
	if (sni != null && length(sni) > 0) {
		proxy.sni = sni;
	} else if (is_ip(server)) {
		proxy.sni = 'itunes.apple.com';
	} else {
		proxy.sni = server;
	}

	const insecure = params.insecure ?? params['skip-cert-verify'] ?? params.allowInsecure;
	if (insecure == '1' || insecure == 'true') {
		proxy['skip-cert-verify'] = true;
	}

	const fp = params.fp ?? params['client-fingerprint'] ?? params.fingerprint;
	if (fp != null && length(fp) > 0) {
		proxy['client-fingerprint'] = fp;
	}

	if (params.alpn != null && length(params.alpn) > 0) {
		proxy.alpn = split(params.alpn, ',');
	}

	const idle_check = params['idle-session-check-interval'] ?? params.idle_session_check_interval;
	if (idle_check != null && length(idle_check) > 0) {
		proxy['idle-session-check-interval'] = int(idle_check);
	}

	const idle_timeout = params['idle-session-timeout'] ?? params.idle_session_timeout;
	if (idle_timeout != null && length(idle_timeout) > 0) {
		proxy['idle-session-timeout'] = int(idle_timeout);
	}

	const min_idle = params['min-idle-session'] ?? params.min_idle_session;
	if (min_idle != null && length(min_idle) > 0) {
		proxy['min-idle-session'] = int(min_idle);
	}

	return proxy;
}

function parse_vless(link) {
	let name = '';
	let rest = substr(link, 8);
	const hash_idx = index(rest, '#');
	if (hash_idx >= 0) {
		name = urldecode(substr(rest, hash_idx + 1));
		rest = substr(rest, 0, hash_idx);
	}
	let query_str = '';
	const query_idx = index(rest, '?');
	if (query_idx >= 0) {
		query_str = substr(rest, query_idx + 1);
		rest = substr(rest, 0, query_idx);
	}
	const at_idx = index(rest, '@');
	if (at_idx < 0) return null;

	const uuid = urldecode(substr(rest, 0, at_idx));
	const host_port = substr(rest, at_idx + 1);
	const hp = parse_host_port(host_port, 443);
	const server = hp.server;
	const port = hp.port;

	const params = parse_query(query_str);
	const proxy = {
		name: length(name) > 0 ? name : `${server}:${port}`,
		type: 'vless',
		server: server,
		port: port,
		uuid: uuid,
		udp: true
	};

	if (params.flow != null && length(params.flow) > 0) {
		proxy.flow = params.flow;
	}

	const net_type = params.type ?? params.net;
	if (net_type != null && length(net_type) > 0) {
		proxy.network = net_type;
	}

	const sec = params.security;
	if (sec == 'tls') {
		proxy.tls = true;
	} else if (sec == 'reality') {
		proxy.tls = true;
		const reality_opts = {};
		if (params.pbk != null) reality_opts['public-key'] = params.pbk;
		if (params.sid != null) reality_opts['short-id'] = params.sid;
		if (params.spx != null) reality_opts['spider-x'] = params.spx;
		proxy['reality-opts'] = reality_opts;
	}

	const sni = params.sni ?? params.servername;
	if (sni != null && length(sni) > 0) {
		proxy.servername = sni;
	} else if (proxy.tls) {
		proxy.servername = is_ip(server) ? 'itunes.apple.com' : server;
	}

	if (params.fp != null && length(params.fp) > 0) {
		proxy['client-fingerprint'] = params.fp;
	}

	if (params.alpn != null && length(params.alpn) > 0) {
		proxy.alpn = split(params.alpn, ',');
	}

	if (proxy.network == 'ws') {
		const ws_opts = {};
		if (params.path != null) ws_opts.path = params.path;
		if (params.host != null) ws_opts.headers = { Host: params.host };
		proxy['ws-opts'] = ws_opts;
	} else if (proxy.network == 'grpc') {
		if (params.serviceName != null) {
			proxy['grpc-opts'] = { 'grpc-service-name': params.serviceName };
		}
	}

	return proxy;
}

function parse_vmess(link) {
	let b64 = substr(link, 8);
	const hash_idx = index(b64, '#');
	let name_override = '';
	if (hash_idx >= 0) {
		name_override = urldecode(substr(b64, hash_idx + 1));
		b64 = substr(b64, 0, hash_idx);
	}
	let str = b64dec(b64);
	if (str == null) return null;
	let vobj = json(str);
	if (vobj == null) return null;

	let server = replace(vobj.add ?? '', /[\[\]"]/g, '');
	server = trim(server);

	const proxy = {
		name: length(name_override) > 0 ? name_override : (vobj.ps ?? 'vmess'),
		type: 'vmess',
		server: server,
		port: int(vobj.port),
		uuid: vobj.id,
		alterId: int(vobj.aid ?? 0),
		cipher: vobj.scy ?? 'auto',
		udp: true
	};
	if (vobj.tls == 'tls') {
		proxy.tls = true;
		if (vobj.sni != null && length(vobj.sni) > 0) proxy.servername = vobj.sni;
		else if (vobj.host != null && length(vobj.host) > 0) proxy.servername = vobj.host;
		else proxy.servername = is_ip(server) ? 'itunes.apple.com' : server;
	}
	if (vobj.net != null && length(vobj.net) > 0) {
		proxy.network = vobj.net;
	}
	if (vobj.net == 'ws') {
		const ws_opts = {};
		if (vobj.path != null) ws_opts.path = vobj.path;
		if (vobj.host != null) ws_opts.headers = { Host: vobj.host };
		proxy['ws-opts'] = ws_opts;
	}
	if (vobj.fp != null && length(vobj.fp) > 0) {
		proxy['client-fingerprint'] = vobj.fp;
	}
	return proxy;
}

function parse_ss(link) {
	let name = '';
	let rest = substr(link, 5);
	const hash_idx = index(rest, '#');
	if (hash_idx >= 0) {
		name = urldecode(substr(rest, hash_idx + 1));
		rest = substr(rest, 0, hash_idx);
	}
	let query_str = '';
	const query_idx = index(rest, '?');
	if (query_idx >= 0) {
		query_str = substr(rest, query_idx + 1);
		rest = substr(rest, 0, query_idx);
	}

	let cipher = '', password = '', host_port = '';
	const at_idx = index(rest, '@');
	if (at_idx >= 0) {
		let userinfo = substr(rest, 0, at_idx);
		host_port = substr(rest, at_idx + 1);
		if (index(userinfo, ':') < 0) {
			userinfo = b64dec(userinfo) ?? userinfo;
		}
		const colon_user = index(userinfo, ':');
		if (colon_user >= 0) {
			cipher = urldecode(substr(userinfo, 0, colon_user));
			password = urldecode(substr(userinfo, colon_user + 1));
		}
	} else {
		let decoded = b64dec(rest);
		if (decoded != null) {
			const at = index(decoded, '@');
			if (at >= 0) {
				let userinfo = substr(decoded, 0, at);
				host_port = substr(decoded, at + 1);
				const colon_u = index(userinfo, ':');
				if (colon_u >= 0) {
					cipher = urldecode(substr(userinfo, 0, colon_u));
					password = urldecode(substr(userinfo, colon_u + 1));
				}
			}
		}
	}
	const hp = parse_host_port(host_port, 8388);
	const server = hp.server;
	const port = hp.port;
	if (length(server) == 0) return null;
	return {
		name: length(name) > 0 ? name : `${server}:${port}`,
		type: 'ss',
		server: server,
		port: port,
		cipher: cipher,
		password: password,
		udp: true
	};
}

function parse_trojan(link) {
	let name = '';
	let rest = substr(link, 9);
	const hash_idx = index(rest, '#');
	if (hash_idx >= 0) {
		name = urldecode(substr(rest, hash_idx + 1));
		rest = substr(rest, 0, hash_idx);
	}
	let query_str = '';
	const query_idx = index(rest, '?');
	if (query_idx >= 0) {
		query_str = substr(rest, query_idx + 1);
		rest = substr(rest, 0, query_idx);
	}
	const at_idx = index(rest, '@');
	if (at_idx < 0) return null;

	const password = urldecode(substr(rest, 0, at_idx));
	const host_port = substr(rest, at_idx + 1);
	const hp = parse_host_port(host_port, 443);
	const server = hp.server;
	const port = hp.port;
	const params = parse_query(query_str);
	const proxy = {
		name: length(name) > 0 ? name : `${server}:${port}`,
		type: 'trojan',
		server: server,
		port: port,
		password: password,
		udp: true
	};
	const sni = params.sni ?? params.peer;
	if (sni != null && length(sni) > 0) {
		proxy.sni = sni;
	} else if (is_ip(server)) {
		proxy.sni = 'itunes.apple.com';
	} else {
		proxy.sni = server;
	}
	if (params.type != null && length(params.type) > 0) proxy.network = params.type;
	if (proxy.network == 'ws') {
		const ws_opts = {};
		if (params.path != null) ws_opts.path = params.path;
		if (params.host != null) ws_opts.headers = { Host: params.host };
		proxy['ws-opts'] = ws_opts;
	}
	return proxy;
}

function is_ip(str) {
	if (str == null) return false;
	str = replace(str, /[\[\]"]/g, '');
	str = trim(str);
	if (match(str, /^(\d{1,3}\.){3}\d{1,3}$/)) return true;
	if (index(str, ':') >= 0) return true;
	return false;
}

function parse_hysteria2(link) {
	let name = '';
	let scheme_len = index(link, 'hy2://') == 0 ? 6 : 12;
	let rest = substr(link, scheme_len);
	const hash_idx = index(rest, '#');
	if (hash_idx >= 0) {
		name = urldecode(substr(rest, hash_idx + 1));
		rest = substr(rest, 0, hash_idx);
	}
	let query_str = '';
	const query_idx = index(rest, '?');
	if (query_idx >= 0) {
		query_str = substr(rest, query_idx + 1);
		rest = substr(rest, 0, query_idx);
	}
	const at_idx = index(rest, '@');
	let password = '';
	let host_port = rest;
	if (at_idx >= 0) {
		password = urldecode(substr(rest, 0, at_idx));
		host_port = substr(rest, at_idx + 1);
	}
	const hp = parse_host_port(host_port, 443);
	const server = hp.server;
	const port = hp.port;

	const params = parse_query(query_str);
	const proxy = {
		name: length(name) > 0 ? name : `${server}:${port}`,
		type: 'hysteria2',
		server: server,
		port: port,
		password: password
	};

	const sni = params.sni ?? params.peer;
	if (sni != null && length(sni) > 0) {
		proxy.sni = sni;
	} else if (is_ip(server)) {
		proxy.sni = 'itunes.apple.com';
	} else {
		proxy.sni = server;
	}

	const insecure = params.insecure ?? params['skip-cert-verify'] ?? params.allowInsecure;
	if (insecure == '1' || insecure == 'true') {
		proxy['skip-cert-verify'] = true;
	}

	if (params.alpn != null && length(params.alpn) > 0) {
		proxy.alpn = split(params.alpn, ',');
	}

	if (params.obfs != null && length(params.obfs) > 0) {
		proxy.obfs = params.obfs;
		const obfs_pass = params['obfs-password'] ?? params['obfs_password'] ?? params['obfs-pass'] ?? params['obfs_pass'];
		if (obfs_pass != null && length(obfs_pass) > 0) {
			proxy['obfs-password'] = obfs_pass;
		}
	}
	const ports = params.ports ?? params.mport;
	if (ports != null && length(ports) > 0) {
		proxy.ports = ports;
	}

	return proxy;
}

function parse_tuic(link) {
	let name = '';
	let rest = substr(link, 7);
	const hash_idx = index(rest, '#');
	if (hash_idx >= 0) {
		name = urldecode(substr(rest, hash_idx + 1));
		rest = substr(rest, 0, hash_idx);
	}
	let query_str = '';
	const query_idx = index(rest, '?');
	if (query_idx >= 0) {
		query_str = substr(rest, query_idx + 1);
		rest = substr(rest, 0, query_idx);
	}
	const at_idx = index(rest, '@');
	if (at_idx < 0) return null;

	const user_pass = substr(rest, 0, at_idx);
	const host_port = substr(rest, at_idx + 1);
	let uuid = '', password = '';
	const colon_up = index(user_pass, ':');
	if (colon_up >= 0) {
		uuid = urldecode(substr(user_pass, 0, colon_up));
		password = urldecode(substr(user_pass, colon_up + 1));
	} else {
		uuid = urldecode(user_pass);
	}
	const hp = parse_host_port(host_port, 8443);
	const server = hp.server;
	const port = hp.port;

	const params = parse_query(query_str);
	const proxy = {
		name: length(name) > 0 ? name : `${server}:${port}`,
		type: 'tuic',
		server: server,
		port: port,
		uuid: uuid,
		password: password
	};
	const sni = params.sni ?? params.peer;
	if (sni != null && length(sni) > 0) {
		proxy.sni = sni;
	} else if (is_ip(server)) {
		proxy.sni = 'itunes.apple.com';
	} else {
		proxy.sni = server;
	}
	if (params.congestion_control != null) proxy['congestion-controller'] = params.congestion_control;
	return proxy;
}

export function parse_proxy_link(link) {
	if (link == null) return null;
	link = trim(link);
	if (length(link) == 0) return null;

	if (index(link, 'anytls://') == 0) return parse_anytls(link);
	if (index(link, 'vless://') == 0) return parse_vless(link);
	if (index(link, 'vmess://') == 0) return parse_vmess(link);
	if (index(link, 'ss://') == 0) return parse_ss(link);
	if (index(link, 'trojan://') == 0) return parse_trojan(link);
	if (index(link, 'hysteria2://') == 0 || index(link, 'hy2://') == 0) return parse_hysteria2(link);
	if (index(link, 'tuic://') == 0) return parse_tuic(link);

	if (substr(link, 0, 1) == '{' && substr(link, -1) == '}') {
		return json(link);
	}

	return null;
};

export function parse_proxy_links(content) {
	const proxies = [];
	if (content == null) return proxies;
	content = trim(content);
	if (length(content) == 0) return proxies;

	const lines = split(content, '\n');
	for (let line in lines) {
		line = trim(line);
		if (length(line) == 0 || substr(line, 0, 1) == '#') continue;
		const parsed = parse_proxy_link(line);
		if (parsed != null) {
			push(proxies, parsed);
		}
	}
	return proxies;
};

export function parse_yaml_proxy(str) {
	if (str == null) return null;
	str = trim(str);
	if (length(str) == 0) return null;
	if (substr(str, 0, 1) == '{' && substr(str, -1) == '}') {
		const obj = json(str);
		return obj != null ? [obj] : null;
	}
	const tmpfile = '/var/run/nikki-rs/proxy_tmp.yaml';
	writefile(tmpfile, str);
	const process = popen(`yq -M -p yaml -o json ${tmpfile}`);
	let result = null;
	if (process) {
		result = json(process);
		process.close();
	}
	if (result != null) {
		if (type(result) == 'object') {
			return [result];
		} else if (type(result) == 'array') {
			return result;
		}
	}
	return null;
};