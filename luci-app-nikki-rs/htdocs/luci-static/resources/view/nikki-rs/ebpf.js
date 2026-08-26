'use strict';
'require form';
'require view';
'require uci';
'require network';
'require tools.widgets as widgets';
'require tools.nikki-rs as nikki';

return view.extend({
    load: function () {
        return Promise.all([
            uci.load('nikki-rs'),
            network.getHostHints(),
            network.getDevices(),
            nikki.getIdentifiers(),
        ]);
    },
    render: function (data) {
        const hosts = data[1].hosts;
        const devices = data[2];

        if (!uci.get('nikki-rs', 'ebpf')) {
            uci.add('nikki-rs', 'ebpf', 'ebpf');
            uci.set('nikki-rs', 'ebpf', 'enabled', '0');
            uci.set('nikki-rs', 'ebpf', 'lan_interface', ['br-lan']);
            uci.set('nikki-rs', 'ebpf', 'tproxy_port', '12345');
            uci.set('nikki-rs', 'ebpf', 'tproxy_udp_port', '12345');
            uci.set('nikki-rs', 'ebpf', 'auto_direct_offload', '1');
            uci.set('nikki-rs', 'ebpf', 'bypass_dscp', ['4']);
            uci.set('nikki-rs', 'ebpf', 'bypass_src_ports', ['22', '67', '68', '5353']);
            uci.set('nikki-rs', 'ebpf', 'proxy_local', '1');
            uci.set('nikki-rs', 'ebpf', 'bypass_dst_ips', [
                '127.0.0.0/8',
                '169.254.0.0/16',
                '224.0.0.0/4',
                '::1/128',
                'fe80::/10',
                'ff00::/8'
            ]);
            uci.set('nikki-rs', 'ebpf', 'proxy_dst_ports', '21 22 80 110 143 194 443 465 853 993 995 8080 8443');
        }

        let m, s, o;

        m = new form.Map('nikki-rs');

        s = m.section(form.NamedSection, 'ebpf', 'ebpf', _('eBPF Config'));

        // Tab: General
        s.tab('general', _('General'));

        o = s.taboption('general', form.Flag, 'enabled', _('Enable'), _('When enabled, the Proxy Config will be ineffective.'));
        o.rmempty = false;

        o = s.taboption('general', form.DynamicList, 'lan_interface', _('LAN Interface'), _('LAN interfaces to attach eBPF ingress filter.'));
        o.default = ['br-lan'];
        o.rmempty = false;
        for (const dev of devices) {
            const name = dev.getName();
            if (name === 'lo' || name === 'loopback') {
                continue;
            }
            o.value(name);
        }

        o = s.taboption('general', form.Value, 'wan_interface', _('WAN Interface'), _('WAN interface to attach eBPF egress filter.'));
        for (const dev of devices) {
            const name = dev.getName();
            if (name === 'lo' || name === 'loopback') {
                continue;
            }
            o.value(name);
        }

        o = s.taboption('general', form.Value, 'tproxy_port', _('TPROXY Port (TCP)'), _('TCP transparent proxy port inside daens.'));
        o.datatype = 'port';
        o.default = '12345';
        o.rmempty = false;

        o = s.taboption('general', form.Value, 'tproxy_udp_port', _('TPROXY UDP Port'), _('UDP transparent proxy port inside daens.'));
        o.datatype = 'port';
        o.default = '12345';
        o.rmempty = false;

        o = s.taboption('general', form.Flag, 'auto_direct_offload', _('Auto Direct Offload'), _('Automatically offload DIRECT traffic to eBPF dynamic bypass map.'));
        o.default = '1';
        o.rmempty = false;

        o = s.taboption('general', form.DynamicList, 'bypass_dscp', _('Bypass DSCP'), _('Traffic with matching DSCP (0-63) values will bypass proxy directly.'));
        o.datatype = 'range(0, 63)';
        o.default = ['4'];

        o = s.taboption('general', form.DynamicList, 'bypass_fwmark', _('Bypass FWMark'), _('Traffic with matching firewall mark (e.g. 0x200 or 512) will bypass proxy directly.'));
        o.validate = function(section_id, value) {
            if (!value) return true;
            if (/^(0x[0-9a-fA-F]+|[0-9]+)$/.test(value)) {
                const n = parseInt(value, value.startsWith('0x') ? 16 : 10);
                if (n >= 0 && n <= 4294967295) return true;
            }
            return _('Expecting a valid decimal (0-4294967295) or hex (0x0-0xffffffff) fwmark');
        };

        // Tab: LAN Proxy (局域网代理)
        s.tab('lan', _('LAN Proxy'));

        o = s.taboption('lan', form.DynamicList, 'proxy_src_ips', _('Proxy Client IPs / CIDRs'), _('Specific LAN client IPs or CIDRs to proxy (if empty, all clients except bypassed ones will be proxied).'));
        for (const mac in hosts) {
            const host = hosts[mac];
            for (const ip of host.ipaddrs) {
                const hint = host.name ?? mac;
                o.value(ip, hint ? '%s (%s)'.format(ip, hint) : ip);
            }
            for (const ip of host.ip6addrs) {
                const hint = host.name ?? mac;
                o.value(ip, hint ? '%s (%s)'.format(ip, hint) : ip);
            }
        }

        o = s.taboption('lan', form.DynamicList, 'bypass_src_ips', _('Bypass Client IPs / CIDRs'), _('Specific LAN client IPs or CIDRs to bypass directly (direct connection, no proxy).'));
        for (const mac in hosts) {
            const host = hosts[mac];
            for (const ip of host.ipaddrs) {
                const hint = host.name ?? mac;
                o.value(ip, hint ? '%s (%s)'.format(ip, hint) : ip);
            }
            for (const ip of host.ip6addrs) {
                const hint = host.name ?? mac;
                o.value(ip, hint ? '%s (%s)'.format(ip, hint) : ip);
            }
        }

        o = s.taboption('lan', form.DynamicList, 'proxy_src_ports', _('Proxy Source Ports'), _('Source ports to proxy (if set, ONLY traffic from these source ports will be proxied).'));
        o.datatype = 'port';

        o = s.taboption('lan', form.DynamicList, 'bypass_src_ports', _('Bypass Source Ports'), _('Source ports to bypass (e.g. 22, 67, 68, 5353).'));
        o.datatype = 'port';
        o.default = ['22', '67', '68', '5353'];

        // Tab: Router Proxy (路由器代理)
        s.tab('router', _('Router Proxy'));

        o = s.taboption('router', form.Flag, 'proxy_local', _('Proxy Router Traffic'), _('Proxy traffic originating from the local router/gateway.'));
        o.default = '1';
        o.rmempty = false;

        o = s.taboption('router', form.DynamicList, 'proxy_processes', _('Proxy Processes'), _('Process whitelist: ONLY traffic originating from these process names will be proxied on the router.'));

        o = s.taboption('router', form.DynamicList, 'bypass_processes', _('Bypass Processes'), _('Process blacklist: Traffic originating from these process names will always bypass proxy.'));

        // Tab: WAN Proxy (公网代理)
        s.tab('wan', _('WAN Proxy'));

        o = s.taboption('wan', form.DynamicList, 'proxy_dst_ips', _('Proxy Destination IPs / CIDRs'), _('Destination IP whitelist: if set, ONLY traffic to matching IPs/CIDRs will be proxied.'));

        o = s.taboption('wan', form.DynamicList, 'bypass_dst_ips', _('Bypass Destination IPs / CIDRs'), _('Destination IPs, CIDRs or reserved ranges to bypass directly (e.g. 127.0.0.0/8, 169.254.0.0/16, ::1/128).'));
        o.default = [
            '127.0.0.0/8',
            '169.254.0.0/16',
            '224.0.0.0/4',
            '::1/128',
            'fe80::/10',
            'ff00::/8'
        ];

        o = s.taboption('wan', form.Value, 'proxy_dst_ports', _('Proxy Destination Ports'), _('Destination ports to proxy (if set, ONLY traffic to these ports will be proxied).'));
        o.rmempty = false;
        o.value('0-65535', _('All Port'));
        o.value('21 22 80 110 143 194 443 465 853 993 995 8080 8443', _('Commonly Used Port'));
        o.default = '21 22 80 110 143 194 443 465 853 993 995 8080 8443';

        o = s.taboption('wan', form.DynamicList, 'bypass_dst_ports', _('Bypass Destination Ports'), _('Destination ports to bypass directly (e.g. 123, 500, 4500).'));
        o.datatype = 'port';

        return m.render();
    }
});
