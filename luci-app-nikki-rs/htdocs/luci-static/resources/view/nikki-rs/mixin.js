'use strict';
'require form';
'require view';
'require uci';
'require fs';
'require network';
'require poll';
'require tools.widgets as widgets';
'require tools.nikki as nikki';

function isIP(host) {
    if (!host) return false;
    host = host.replace(/[\[\]"]/g, '').trim();
    if (/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    if (host.includes(':')) return true;
    return false;
}

function parseQuery(queryString) {
    const params = {};
    if (!queryString) return params;
    const pairs = queryString.split('&');
    for (const pair of pairs) {
        if (!pair) continue;
        const eq = pair.indexOf('=');
        if (eq > 0) {
            const k = decodeURIComponent(pair.substring(0, eq));
            const v = decodeURIComponent(pair.substring(eq + 1));
            params[k] = v;
        } else {
            params[decodeURIComponent(pair)] = '';
        }
    }
    return params;
}

function parseHostPort(hostPort, defaultPort = 443) {
    if (!hostPort) return { server: '', port: defaultPort };
    let hp = hostPort.trim();
    let server = hp;
    let port = defaultPort;

    const bracketClose = hp.lastIndexOf(']');
    if (bracketClose >= 0) {
        server = hp.substring(0, bracketClose + 1);
        const remainder = hp.substring(bracketClose + 1);
        const colonIdx = remainder.indexOf(':');
        if (colonIdx >= 0) {
            const p = parseInt(remainder.substring(colonIdx + 1), 10);
            if (!isNaN(p)) port = p;
        }
    } else {
        const colons = hp.split(':');
        if (colons.length === 2) {
            server = colons[0];
            const p = parseInt(colons[1], 10);
            if (!isNaN(p)) port = p;
        } else if (colons.length > 2) {
            server = hp;
        }
    }

    server = server.replace(/[\[\]"]/g, '').trim();
    return { server, port };
}

function parseLinkToObject(link) {
    if (!link) return null;
    link = link.trim();
    if (!link) return null;

    if (link.startsWith('anytls://')) {
        let rest = link.substring(9);
        let name = '';
        const hashIdx = rest.indexOf('#');
        if (hashIdx >= 0) {
            name = decodeURIComponent(rest.substring(hashIdx + 1));
            rest = rest.substring(0, hashIdx);
        }
        let queryStr = '';
        const queryIdx = rest.indexOf('?');
        if (queryIdx >= 0) {
            queryStr = rest.substring(queryIdx + 1);
            rest = rest.substring(0, queryIdx);
        }
        const atIdx = rest.indexOf('@');
        if (atIdx < 0) return null;
        const password = decodeURIComponent(rest.substring(0, atIdx));
        const hostPort = rest.substring(atIdx + 1);
        const { server, port } = parseHostPort(hostPort, 443);
        const params = parseQuery(queryStr);
        const obj = {
            name: name || `${server}:${port}`,
            type: 'anytls',
            server: server,
            port: port,
            password: password,
            udp: true
        };
        const sni = params.sni || params.peer || params.servername;
        if (sni) {
            obj.sni = sni;
        } else if (isIP(server)) {
            obj.sni = 'itunes.apple.com';
        } else {
            obj.sni = server;
        }
        const insecure = params.insecure || params['skip-cert-verify'] || params.allowInsecure;
        if (insecure === '1' || insecure === 'true') {
            obj['skip-cert-verify'] = true;
        }
        const fp = params.fp || params['client-fingerprint'] || params.fingerprint;
        if (fp) {
            obj['client-fingerprint'] = fp;
        }
        if (params.alpn) {
            obj.alpn = params.alpn.split(',');
        }
        const idleCheck = params['idle-session-check-interval'] || params.idle_session_check_interval;
        if (idleCheck) {
            obj['idle-session-check-interval'] = parseInt(idleCheck, 10);
        }
        const idleTimeout = params['idle-session-timeout'] || params.idle_session_timeout;
        if (idleTimeout) {
            obj['idle-session-timeout'] = parseInt(idleTimeout, 10);
        }
        const minIdle = params['min-idle-session'] || params.min_idle_session;
        if (minIdle) {
            obj['min-idle-session'] = parseInt(minIdle, 10);
        }
        return obj;
    }

    if (link.startsWith('vless://')) {
        let rest = link.substring(8);
        let name = '';
        const hashIdx = rest.indexOf('#');
        if (hashIdx >= 0) {
            name = decodeURIComponent(rest.substring(hashIdx + 1));
            rest = rest.substring(0, hashIdx);
        }
        let queryStr = '';
        const queryIdx = rest.indexOf('?');
        if (queryIdx >= 0) {
            queryStr = rest.substring(queryIdx + 1);
            rest = rest.substring(0, queryIdx);
        }
        const atIdx = rest.indexOf('@');
        if (atIdx < 0) return null;
        const uuid = decodeURIComponent(rest.substring(0, atIdx));
        const hostPort = rest.substring(atIdx + 1);
        const { server, port } = parseHostPort(hostPort, 443);
        const params = parseQuery(queryStr);
        const obj = {
            name: name || `${server}:${port}`,
            type: 'vless',
            server: server,
            port: port,
            uuid: uuid,
            udp: true
        };
        if (params.flow) obj.flow = params.flow;
        const netType = params.type || params.net;
        if (netType) obj.network = netType;
        const sec = params.security;
        if (sec === 'tls') {
            obj.tls = true;
        } else if (sec === 'reality') {
            obj.tls = true;
            const realityOpts = {};
            if (params.pbk) realityOpts['public-key'] = params.pbk;
            if (params.sid) realityOpts['short-id'] = params.sid;
            if (params.spx) realityOpts['spider-x'] = params.spx;
            obj['reality-opts'] = realityOpts;
        }
        const sni = params.sni || params.servername;
        if (sni) {
            obj.servername = sni;
        } else if (obj.tls) {
            obj.servername = isIP(server) ? 'itunes.apple.com' : server;
        }
        if (params.fp) obj['client-fingerprint'] = params.fp;
        if (params.alpn) obj.alpn = params.alpn.split(',');
        if (obj.network === 'ws') {
            const wsOpts = {};
            if (params.path) wsOpts.path = params.path;
            if (params.host) wsOpts.headers = { Host: params.host };
            obj['ws-opts'] = wsOpts;
        } else if (obj.network === 'grpc') {
            if (params.serviceName) {
                obj['grpc-opts'] = { 'grpc-service-name': params.serviceName };
            }
        }
        return obj;
    }

    if (link.startsWith('vmess://')) {
        let b64 = link.substring(8);
        let nameOverride = '';
        const hashIdx = b64.indexOf('#');
        if (hashIdx >= 0) {
            nameOverride = decodeURIComponent(b64.substring(hashIdx + 1));
            b64 = b64.substring(0, hashIdx);
        }
        try {
            const jsonStr = window.atob(b64);
            const vobj = JSON.parse(jsonStr);
            const server = (vobj.add || '').replace(/[\[\]"]/g, '').trim();
            const obj = {
                name: nameOverride || vobj.ps || 'vmess',
                type: 'vmess',
                server: server,
                port: parseInt(vobj.port, 10),
                uuid: vobj.id,
                alterId: parseInt(vobj.aid || 0, 10),
                cipher: vobj.scy || 'auto',
                udp: true
            };
            if (vobj.tls === 'tls') {
                obj.tls = true;
                const sni = vobj.sni || vobj.host;
                if (sni) {
                    obj.servername = sni;
                } else {
                    obj.servername = isIP(server) ? 'itunes.apple.com' : server;
                }
            }
            if (vobj.net) obj.network = vobj.net;
            if (vobj.net === 'ws') {
                const wsOpts = {};
                if (vobj.path) wsOpts.path = vobj.path;
                if (vobj.host) wsOpts.headers = { Host: vobj.host };
                obj['ws-opts'] = wsOpts;
            }
            if (vobj.fp) obj['client-fingerprint'] = vobj.fp;
            return obj;
        } catch (e) {
            return null;
        }
    }

    if (link.startsWith('ss://')) {
        let rest = link.substring(5);
        let name = '';
        const hashIdx = rest.indexOf('#');
        if (hashIdx >= 0) {
            name = decodeURIComponent(rest.substring(hashIdx + 1));
            rest = rest.substring(0, hashIdx);
        }
        let cipher = '', password = '', hostPort = '';
        const atIdx = rest.indexOf('@');
        if (atIdx >= 0) {
            let userinfo = rest.substring(0, atIdx);
            hostPort = rest.substring(atIdx + 1);
            if (!userinfo.includes(':')) {
                try { userinfo = window.atob(userinfo); } catch (e) { }
            }
            const colonUser = userinfo.indexOf(':');
            if (colonUser >= 0) {
                cipher = decodeURIComponent(userinfo.substring(0, colonUser));
                password = decodeURIComponent(userinfo.substring(colonUser + 1));
            }
        } else {
            try {
                const decoded = window.atob(rest);
                const at = decoded.indexOf('@');
                if (at >= 0) {
                    let userinfo = decoded.substring(0, at);
                    hostPort = decoded.substring(at + 1);
                    const colonU = userinfo.indexOf(':');
                    if (colonU >= 0) {
                        cipher = decodeURIComponent(userinfo.substring(0, colonU));
                        password = decodeURIComponent(userinfo.substring(colonU + 1));
                    }
                }
            } catch (e) { }
        }
        const { server, port } = parseHostPort(hostPort, 8388);
        if (!server) return null;
        return {
            name: name || `${server}:${port}`,
            type: 'ss',
            server: server,
            port: port,
            cipher: cipher,
            password: password,
            udp: true
        };
    }

    if (link.startsWith('trojan://')) {
        let rest = link.substring(9);
        let name = '';
        const hashIdx = rest.indexOf('#');
        if (hashIdx >= 0) {
            name = decodeURIComponent(rest.substring(hashIdx + 1));
            rest = rest.substring(0, hashIdx);
        }
        let queryStr = '';
        const queryIdx = rest.indexOf('?');
        if (queryIdx >= 0) {
            queryStr = rest.substring(queryIdx + 1);
            rest = rest.substring(0, queryIdx);
        }
        const atIdx = rest.indexOf('@');
        if (atIdx < 0) return null;
        const password = decodeURIComponent(rest.substring(0, atIdx));
        const hostPort = rest.substring(atIdx + 1);
        const { server, port } = parseHostPort(hostPort, 443);
        const params = parseQuery(queryStr);
        const obj = {
            name: name || `${server}:${port}`,
            type: 'trojan',
            server: server,
            port: port,
            password: password,
            udp: true
        };
        const sni = params.sni || params.peer;
        if (sni) {
            obj.sni = sni;
        } else {
            obj.sni = isIP(server) ? 'itunes.apple.com' : server;
        }
        if (params.type) obj.network = params.type;
        if (obj.network === 'ws') {
            const wsOpts = {};
            if (params.path) wsOpts.path = params.path;
            if (params.host) wsOpts.headers = { Host: params.host };
            obj['ws-opts'] = wsOpts;
        }
        return obj;
    }

    if (link.startsWith('hysteria2://') || link.startsWith('hy2://')) {
        let schemeLen = link.startsWith('hy2://') ? 6 : 12;
        let rest = link.substring(schemeLen);
        let name = '';
        const hashIdx = rest.indexOf('#');
        if (hashIdx >= 0) {
            name = decodeURIComponent(rest.substring(hashIdx + 1));
            rest = rest.substring(0, hashIdx);
        }
        let queryStr = '';
        const queryIdx = rest.indexOf('?');
        if (queryIdx >= 0) {
            queryStr = rest.substring(queryIdx + 1);
            rest = rest.substring(0, queryIdx);
        }
        const atIdx = rest.indexOf('@');
        let password = '';
        let hostPort = rest;
        if (atIdx >= 0) {
            password = decodeURIComponent(rest.substring(0, atIdx));
            hostPort = rest.substring(atIdx + 1);
        }
        const { server, port } = parseHostPort(hostPort, 443);
        const params = parseQuery(queryStr);
        const obj = {
            name: name || `${server}:${port}`,
            type: 'hysteria2',
            server: server,
            port: port,
            password: password
        };
        const sni = params.sni || params.peer;
        if (sni) {
            obj.sni = sni;
        } else if (isIP(server)) {
            obj.sni = 'itunes.apple.com';
        } else {
            obj.sni = server;
        }
        const insecure = params.insecure || params['skip-cert-verify'] || params.allowInsecure;
        if (insecure === '1' || insecure === 'true') {
            obj['skip-cert-verify'] = true;
        }
        if (params.alpn) {
            obj.alpn = params.alpn.split(',');
        }
        if (params.obfs) {
            obj.obfs = params.obfs;
            const obfsPass = params['obfs-password'] || params['obfs_password'] || params['obfs-pass'] || params['obfs_pass'];
            if (obfsPass) obj['obfs-password'] = obfsPass;
        }
        const ports = params.ports || params.mport;
        if (ports) obj.ports = ports;
        return obj;
    }

    if (link.startsWith('tuic://')) {
        let rest = link.substring(7);
        let name = '';
        const hashIdx = rest.indexOf('#');
        if (hashIdx >= 0) {
            name = decodeURIComponent(rest.substring(hashIdx + 1));
            rest = rest.substring(0, hashIdx);
        }
        let queryStr = '';
        const queryIdx = rest.indexOf('?');
        if (queryIdx >= 0) {
            queryStr = rest.substring(queryIdx + 1);
            rest = rest.substring(0, queryIdx);
        }
        const atIdx = rest.indexOf('@');
        if (atIdx < 0) return null;
        const userPass = rest.substring(0, atIdx);
        const hostPort = rest.substring(atIdx + 1);
        let uuid = '', password = '';
        const colonUp = userPass.indexOf(':');
        if (colonUp >= 0) {
            uuid = decodeURIComponent(userPass.substring(0, colonUp));
            password = decodeURIComponent(userPass.substring(colonUp + 1));
        } else {
            uuid = decodeURIComponent(userPass);
        }
        const { server, port } = parseHostPort(hostPort, 8443);
        const params = parseQuery(queryStr);
        const obj = {
            name: name || `${server}:${port}`,
            type: 'tuic',
            server: server,
            port: port,
            uuid: uuid,
            password: password
        };
        const sni = params.sni || params.peer;
        if (sni) {
            obj.sni = sni;
        } else if (isIP(server)) {
            obj.sni = 'itunes.apple.com';
        } else {
            obj.sni = server;
        }
        if (params.congestion_control) obj['congestion-controller'] = params.congestion_control;
        return obj;
    }

    return null;
}

function objectToYaml(obj, indent = 0) {
    if (obj === null || obj === undefined) return '';
    const spaces = ' '.repeat(indent);
    let result = '';

    if (Array.isArray(obj)) {
        for (const item of obj) {
            if (typeof item === 'object' && item !== null) {
                const keys = Object.keys(item);
                if (keys.length > 0) {
                    result += `${spaces}- ${keys[0]}: ${formatYamlValue(item[keys[0]])}\n`;
                    for (let i = 1; i < keys.length; i++) {
                        const key = keys[i];
                        const val = item[key];
                        if (typeof val === 'object' && val !== null) {
                            result += `${spaces}  ${key}:\n${objectToYaml(val, indent + 4)}`;
                        } else {
                            result += `${spaces}  ${key}: ${formatYamlValue(val)}\n`;
                        }
                    }
                }
            } else {
                result += `${spaces}- ${formatYamlValue(item)}\n`;
            }
        }
        return result;
    }

    for (const key of Object.keys(obj)) {
        const val = obj[key];
        if (val === undefined || val === null) continue;
        if (typeof val === 'object' && !Array.isArray(val)) {
            result += `${spaces}${key}:\n${objectToYaml(val, indent + 2)}`;
        } else if (Array.isArray(val)) {
            result += `${spaces}${key}:\n`;
            for (const sub of val) {
                result += `${spaces}  - ${formatYamlValue(sub)}\n`;
            }
        } else {
            result += `${spaces}${key}: ${formatYamlValue(val)}\n`;
        }
    }
    return result;
}

function formatYamlValue(val) {
    if (typeof val === 'boolean') return val ? 'true' : 'false';
    if (typeof val === 'number') return String(val);
    if (typeof val === 'string') {
        if (/^[a-zA-Z0-9_\-\.\:\/]+$/.test(val) && val !== 'true' && val !== 'false') {
            return val;
        }
        return JSON.stringify(val);
    }
    return String(val);
}

return view.extend({
    load: function () {
        return Promise.all([
            uci.load('nikki-rs'),
            network.getNetworks(),
        ]);
    },
    render: function (data) {
        const networks = data[1];

        let m, s, o, so;

        m = new form.Map('nikki-rs');

        s = m.section(form.NamedSection, 'mixin', 'mixin', _('Mixin Option'));

        s.tab('general', _('General Config'));

        o = s.taboption('general', form.ListValue, 'log_level', _('Log Level'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('silent');
        o.value('error');
        o.value('warning');
        o.value('info');
        o.value('debug');

        o = s.taboption('general', form.ListValue, 'mode', _('Mode'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('global', _('Global Mode'));
        o.value('rule', _('Rule Mode'));
        o.value('direct', _('Direct Mode'));

        o = s.taboption('general', form.ListValue, 'match_process', _('Match Process'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('off');
        o.value('strict');
        o.value('always');

        o = s.taboption('general', form.ListValue, 'outbound_interface', _('Outbound Interface'));
        o.optional = true;
        o.placeholder = _('Unmodified');

        for (const network of networks) {
            if (network.getName() === 'loopback') {
                continue;
            }
            o.value(network.getName());
        }

        o = s.taboption('general', form.ListValue, 'ipv6', 'IPv6');
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        s.tab('external_control', _('External Control Config'));

        o = s.taboption('external_control', form.Value, 'ui_path', _('UI Path'));
        o.placeholder = _('Unmodified');

        o = s.taboption('external_control', form.Value, 'ui_name', _('UI Name'));
        o.placeholder = _('Unmodified');

        o = s.taboption('external_control', form.Value, 'ui_url', _('UI Url'));
        o.placeholder = _('Unmodified');
        o.value('https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip', 'Zashboard (CDN Fonts)');
        o.value('https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip', 'Zashboard');
        o.value('https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip', 'MetaCubeXD');
        o.value('https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip', 'YACD');
        o.value('https://github.com/MetaCubeX/Razord-meta/archive/refs/heads/gh-pages.zip', 'Razord');

        o = s.taboption('external_control', form.Value, 'api_listen', _('API Listen'));
        o.datatype = 'ipaddrport(1)';
        o.placeholder = _('Unmodified');

        o = s.taboption('external_control', form.Value, 'api_secret', _('API Secret'));
        o.password = true;
        o.placeholder = _('Unmodified');

        o = s.taboption('external_control', form.ListValue, 'selection_cache', _('Save Proxy Selection'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        s.tab('inbound', _('Inbound Config'));

        o = s.taboption('inbound', form.ListValue, 'allow_lan', _('Allow Lan'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        o = s.taboption('inbound', form.Value, 'http_port', _('HTTP Port'));
        o.datatype = 'port';
        o.placeholder = _('Unmodified');

        o = s.taboption('inbound', form.Value, 'socks_port', _('SOCKS Port'));
        o.datatype = 'port';
        o.placeholder = _('Unmodified');

        o = s.taboption('inbound', form.Value, 'mixed_port', _('Mixed Port'));
        o.datatype = 'port';
        o.placeholder = _('Unmodified');

        o = s.taboption('inbound', form.Value, 'redir_port', _('Redirect Port'));
        o.datatype = 'port';
        o.placeholder = _('Unmodified');

        o = s.taboption('inbound', form.Value, 'tproxy_port', _('TPROXY Port'));
        o.datatype = 'port';
        o.placeholder = _('Unmodified');

        o = s.taboption('inbound', form.Flag, 'authentication', _('Overwrite Authentication'));
        o.rmempty = false;

        o = s.taboption('inbound', form.SectionValue, '_authentications', form.TableSection, 'authentication', _('Edit Authentications'));
        o.retain = true;
        o.depends('authentication', '1');

        o.subsection.addremove = true;
        o.subsection.anonymous = true;
        o.subsection.sortable = true;

        so = o.subsection.option(form.Flag, 'enabled', _('Enable'));
        so.rmempty = false;

        so = o.subsection.option(form.Value, 'username', _('Username'));
        so.rmempty = false;

        so = o.subsection.option(form.Value, 'password', _('Password'));
        so.password = true;
        so.rmempty = false;

        s.tab('tun', _('TUN Config'));

        o = s.taboption('tun', form.ListValue, 'tun_enabled', _('Enable'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        o = s.taboption('tun', form.Value, 'tun_device', _('Device Name'));
        o.placeholder = _('Unmodified');

        o = s.taboption('tun', form.ListValue, 'tun_stack', _('Stack'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('system', 'System');
        o.value('gvisor', 'gVisor');
        o.value('mixed', 'Mixed');

        o = s.taboption('tun', form.Value, 'tun_mtu', _('MTU'));
        o.datatype = 'uinteger';
        o.placeholder = _('Unmodified');

        o = s.taboption('tun', form.ListValue, 'tun_gso', _('GSO'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        o = s.taboption('tun', form.Value, 'tun_gso_max_size', _('GSO Max Size'));
        o.datatype = 'uinteger';
        o.placeholder = _('Unmodified');

        o = s.taboption('tun', form.Flag, 'tun_dns_hijack', _('Overwrite DNS Hijack'));
        o.rmempty = false;

        o = s.taboption('tun', form.DynamicList, 'tun_dns_hijacks', _('Edit DNS Hijacks'));
        o.retain = true;
        o.depends('tun_dns_hijack', '1');
        o.value('tcp://any:53');
        o.value('udp://any:53');

        s.tab('dns', _('DNS Config'));

        o = s.taboption('dns', form.ListValue, 'dns_enabled', _('Enable'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        o = s.taboption('dns', form.Value, 'dns_listen', _('DNS Listen'));
        o.datatype = 'ipaddrport(1)';
        o.placeholder = _('Unmodified');

        o = s.taboption('dns', form.ListValue, 'dns_ipv6', 'IPv6');
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        o = s.taboption('dns', form.ListValue, 'dns_mode', _('DNS Mode'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('redir-host', 'Redir-Host');
        o.value('fake-ip', 'Fake-IP');

        o = s.taboption('dns', form.Value, 'fake_ip_range', _('Fake-IP Range'));
        o.datatype = 'cidr4';
        o.placeholder = _('Unmodified');

        o = s.taboption('dns', form.Value, 'fake_ip6_range', _('Fake-IP6 Range'));
        o.datatype = 'cidr6';
        o.placeholder = _('Unmodified');

        o = s.taboption('dns', form.Value, 'fake_ip_ttl', _('Fake-IP TTL'));
        o.datatype = 'uinteger';
        o.placeholder = _('Unmodified');

        o = s.taboption('dns', form.Flag, 'fake_ip_filter', _('Overwrite Fake-IP Filter'));
        o.rmempty = false;

        o = s.taboption('dns', form.DynamicList, 'fake_ip_filters', _('Edit Fake-IP Filters'));
        o.retain = true;
        o.depends('fake_ip_filter', '1');

        o = s.taboption('dns', form.Flag, 'black_filter', _('Overwrite Black Filter'));
        o.rmempty = false;

        o = s.taboption('dns', form.DynamicList, 'black_filters', _('Edit Black Filters'));
        o.retain = true;
        o.depends('black_filter', '1');

        o = s.taboption('dns', form.ListValue, 'dns_respect_rules', _('Respect Rules'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        o = s.taboption('dns', form.ListValue, 'dns_hosts', _('Use Hosts'));
        o.optional = true;
        o.placeholder = _('Unmodified');
        o.value('0', _('Disable'));
        o.value('1', _('Enable'));

        o = s.taboption('dns', form.Flag, 'hosts', _('Overwrite Hosts'));
        o.rmempty = false;

        o = s.taboption('dns', form.Flag, 'dnsmasq_hosts', _('Import dnsmasq Hosts'));
        o.rmempty = false;
        o.depends('hosts', '1');

        o = s.taboption('dns', form.SectionValue, '_hosts', form.TableSection, 'hosts', _('Edit Hosts'));
        o.retain = true;
        o.depends('hosts', '1');

        o.subsection.addremove = true;
        o.subsection.anonymous = true;
        o.subsection.sortable = true;

        so = o.subsection.option(form.Flag, 'enabled', _('Enable'));
        so.rmempty = false;

        so = o.subsection.option(form.Value, 'domain_name', _('Domain Name'));
        so.rmempty = false;

        so = o.subsection.option(form.DynamicList, 'ip', 'IP');

        o = s.taboption('dns', form.Flag, 'dns_nameserver', _('Overwrite Nameserver'));
        o.rmempty = false;

        o = s.taboption('dns', form.SectionValue, '_dns_nameservers', form.TableSection, 'nameserver', _('Edit Nameservers'));
        o.retain = true;
        o.depends('dns_nameserver', '1');

        o.subsection.addremove = true;
        o.subsection.anonymous = true;
        o.subsection.sortable = true;

        so = o.subsection.option(form.Flag, 'enabled', _('Enable'));
        so.rmempty = false;

        so = o.subsection.option(form.ListValue, 'type', _('Type'));
        so.value('default-nameserver');
        so.value('proxy-server-nameserver');
        so.value('direct-nameserver');
        so.value('nameserver');
        so.value('fallback');

        so = o.subsection.option(form.DynamicList, 'nameserver', _('Nameserver'));

        o = s.taboption('dns', form.Flag, 'dns_proxy_server_nameserver_policy', _('Overwrite Proxy Server Nameserver Policy'));
        o.rmempty = false;

        o = s.taboption('dns', form.SectionValue, '_dns_proxy_server_nameserver_policies', form.TableSection, 'proxy_server_nameserver_policy', _('Edit Proxy Server Nameserver Policies'));
        o.retain = true;
        o.depends('dns_proxy_server_nameserver_policy', '1');

        o.subsection.addremove = true;
        o.subsection.anonymous = true;
        o.subsection.sortable = true;

        so = o.subsection.option(form.Flag, 'enabled', _('Enable'));
        so.rmempty = false;

        so = o.subsection.option(form.Value, 'matcher', _('Matcher'));
        so.rmempty = false;

        so = o.subsection.option(form.DynamicList, 'nameserver', _('Nameserver'));

        s.tab('rule', _('Rule Config'));

        o = s.taboption('rule', form.Flag, 'rule_provider', _('Append Rule Provider'));
        o.rmempty = false;

        o = s.taboption('rule', form.Flag, 'rule_provider_scheduled_update', _('Scheduled Update Rule Providers'));
        o.default = 0;
        o.depends('rule_provider', '1');

        o = s.taboption('rule', form.Value, 'rule_provider_scheduled_update_cron', _('Scheduled Update Cron'));
        o.default = '0 3 * * *';
        o.rmempty = false;
        o.depends({ rule_provider: '1', rule_provider_scheduled_update: '1' });

        o = s.taboption('rule', form.SectionValue, '_rule_providers', form.GridSection, 'rule_provider', _('Edit Rule Providers'));
        o.retain = true;
        o.depends('rule_provider', '1');

        o.subsection.anonymous = true;
        o.subsection.addremove = true;
        o.subsection.sortable = true;

        so = o.subsection.option(form.Flag, 'enabled', _('Enable'));
        so.default = 1;
        so.editable = true;
        so.modalonly = false;
        so.rmempty = false;

        so = o.subsection.option(form.Value, 'name', _('Name'));
        so.rmempty = false;

        so = o.subsection.option(form.ListValue, 'type', _('Type'));
        so.default = 'http';
        so.rmempty = false;
        so.value('http');
        so.value('file');

        so = o.subsection.option(form.Value, 'update', _('Update At'));
        so.modalonly = false;
        so.optional = true;
        so.readonly = true;

        so = o.subsection.option(form.Button, 'update_rule_provider');
        so.editable = true;
        so.inputstyle = 'positive';
        so.inputtitle = _('Update');
        so.modalonly = false;
        so.onclick = function (_, section_id) {
            return nikki.updateRuleProvider(section_id).then(function () {
                window.location.reload();
            });
        };

        so = o.subsection.option(form.Value, 'url', _('Url'));
        so.modalonly = true;
        so.rmempty = false;
        so.depends('type', 'http');

        so = o.subsection.option(form.Value, 'user_agent', _('User Agent'));
        so.optional = true;
        so.modalonly = true;
        so.depends('type', 'http');
        so.value('clash');
        so.value('clash.meta');
        so.value('mihomo');
        so.value('clash-rs');

        so = o.subsection.option(form.Value, 'file_size_limit', _('File Size Limit'));
        so.datatype = 'uinteger';
        so.default = 0;
        so.modalonly = true;
        so.depends('type', 'http');

        so = o.subsection.option(form.FileUpload, 'file_path', _('File Path'));
        so.modalonly = true;
        so.rmempty = false;
        so.root_directory = nikki.ruleProvidersDir;
        so.depends('type', 'file');

        so = o.subsection.option(form.ListValue, 'file_format', _('File Format'));
        so.default = 'yaml';
        so.value('mrs');
        so.value('yaml');
        so.value('text');

        so = o.subsection.option(form.ListValue, 'behavior', _('Behavior'));
        so.default = 'classical';
        so.rmempty = false;
        so.value('classical');
        so.value('domain');
        so.value('ipcidr');

        o = s.taboption('rule', form.Flag, 'rule', _('Append Rule'));
        o.rmempty = false;

        o = s.taboption('rule', form.SectionValue, '_rules', form.TableSection, 'rule', _('Edit Rules'));
        o.retain = true;
        o.depends('rule', '1');

        o.subsection.anonymous = true;
        o.subsection.addremove = true;
        o.subsection.sortable = true;

        so = o.subsection.option(form.Flag, 'enabled', _('Enable'));
        so.default = 1;
        so.rmempty = false;

        so = o.subsection.option(form.Value, 'type', _('Type'));
        so.rmempty = false;
        so.value('RULE-SET', _('Rule Set'));
        so.value('DOMAIN', _('Domain Name'));
        so.value('DOMAIN-SUFFIX', _('Domain Name Suffix'));
        so.value('DOMAIN-WILDCARD', _('Domain Name Wildcard'));
        so.value('DOMAIN-KEYWORD', _('Domain Name Keyword'));
        so.value('DOMAIN-REGEX', _('Domain Name Regex'));
        so.value('IP-CIDR', _('Destination IP'));
        so.value('DST-PORT', _('Destination Port'));
        so.value('PROCESS-NAME', _('Process Name'));
        so.value('GEOSITE', _('Domain Name Geo'));
        so.value('GEOIP', _('Destination IP Geo'));

        so = o.subsection.option(form.Value, 'matcher', _('Matcher'));
        so.rmempty = false;
        so.depends({ 'type': /MATCH/i, '!reverse': true });

        so = o.subsection.option(form.Value, 'node', _('Node'));
        so.default = 'GLOBAL';
        so.value('GLOBAL');
        so.value('DIRECT');
        so.value('REJECT');
        so.value('REJECT-DROP');

        so = o.subsection.option(form.Flag, 'no_resolve', _('No Resolve'));
        so.rmempty = false;
        so.depends('type', /IP-CIDR6?/i);
        so.depends('type', /IP-ASN/i);
        so.depends('type', /GEOIP/i);

        s.tab('proxy_node', _('Proxy Node Config'));

        o = s.taboption('proxy_node', form.Flag, 'proxy_node', _('Append Proxy Node'));
        o.rmempty = false;

        o = s.taboption('proxy_node', form.SectionValue, '_proxy_nodes', form.GridSection, 'proxy_node', _('Edit Proxy Nodes'), _('Supported protocols: %s').format('anytls, vless, vmess, ss, trojan, hysteria2 (hy2), tuic'));
        o.retain = true;
        o.depends('proxy_node', '1');

        o.subsection.anonymous = true;
        o.subsection.addremove = true;
        o.subsection.sortable = true;

        so = o.subsection.option(form.Flag, 'enabled', _('Enable'));
        so.default = 1;
        so.editable = true;
        so.modalonly = false;
        so.rmempty = false;

        var nameOption = o.subsection.option(form.Value, 'name', _('Name'));
        nameOption.placeholder = _('Extracted from link if empty');

        var linkOption = o.subsection.option(form.TextValue, 'link', _('Node Link'), _('Supported protocols: %s').format('anytls, vless, vmess, ss, trojan, hysteria2 (hy2), tuic'));
        linkOption.rmempty = false;
        linkOption.rows = 3;
        linkOption.placeholder = 'anytls://... or vless://...';

        var yamlOption = o.subsection.option(form.TextValue, 'yaml', _('YAML Configuration'));
        yamlOption.rows = 8;
        yamlOption.placeholder = _('Automatically generated from link or edit manually');
        yamlOption.modalonly = true;

        so = o.subsection.option(form.Button, 'regenerate');
        so.editable = true;
        so.inputstyle = 'action';
        so.inputtitle = _('Regenerate');
        so.modalonly = false;
        so.onclick = function (ev, section_id) {
            var linkVal = uci.get('nikki-rs', section_id, 'link');

            if (!linkVal) {
                alert(_('Please save the node link first, then click Regenerate.'));
                return Promise.resolve();
            }

            var parsedObj = parseLinkToObject(linkVal);
            if (!parsedObj) {
                alert(_('Failed to parse node link.'));
                return Promise.resolve();
            }

            var nameVal = uci.get('nikki-rs', section_id, 'name');
            if (nameVal && nameVal.trim() !== '') {
                parsedObj.name = nameVal.trim();
            } else if (parsedObj.name) {
                uci.set('nikki-rs', section_id, 'name', parsedObj.name);
            }

            var yamlStr = objectToYaml(parsedObj);
            uci.set('nikki-rs', section_id, 'yaml', yamlStr);

            return uci.save().then(function () {
                window.location.reload();
            });
        };

        var origHandleModalSave = o.subsection.handleModalSave;
        o.subsection.handleModalSave = function (modalMap, ev) {
            var section_id = modalMap.section;
            var linkFormVal = modalMap.lookupOption('link', section_id)[0].getUIElement(section_id).getValue();
            var yamlEl = modalMap.lookupOption('yaml', section_id)[0].getUIElement(section_id);
            var yamlFormVal = yamlEl.getValue(section_id);
            var nameFormVal = modalMap.lookupOption('name', section_id)[0].getUIElement(section_id).getValue();

            if (linkFormVal && (!yamlFormVal || !yamlFormVal.trim())) {
                var parsedObj = parseLinkToObject(linkFormVal);
                if (parsedObj) {
                    if (nameFormVal && nameFormVal.trim() !== '') {
                        parsedObj.name = nameFormVal.trim();
                    } else if (parsedObj.name) {
                        var nameEl = nameOption.getUIElement(section_id);
                        if (nameEl) nameEl.setValue(parsedObj.name);
                    }
                    var yamlStr = objectToYaml(parsedObj);
                    yamlEl.setValue(yamlStr);

                }
            }

            return origHandleModalSave.apply(this, arguments);
        };

        s.tab('mixin_file_content', _('Mixin File Content'));

        o = s.taboption('mixin_file_content', form.Flag, 'mixin_file_content', _('Enable'), _('Please go to the editor tab to edit the file for mixin'));
        o.rmempty = false;

        return m.render();
    }
});