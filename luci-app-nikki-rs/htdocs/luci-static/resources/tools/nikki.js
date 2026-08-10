'use strict';
'require baseclass';
'require uci';
'require fs';
'require rpc';
'require request';

const callRCList = rpc.declare({
    object: 'rc',
    method: 'list',
    params: ['name'],
    expect: { '': {} }
});

const callRCInit = rpc.declare({
    object: 'rc',
    method: 'init',
    params: ['name', 'action'],
    expect: { '': {} }
});

const callFileWrite = rpc.declare({
    object: 'file',
    method: 'write',
    params: ['path', 'data', 'append', 'mode']
});

const callNikkiVersion = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'version',
    expect: { '': {} }
});

const callNikkiProfile = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'profile',
    params: ['defaults'],
    expect: { '': {} }
});

const callNikkiUpdateSubscription = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'update_subscription',
    params: ['section_id'],
    expect: { '': {} }
});

const callNikkiUpdateRuleProvider = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'update_rule_provider',
    params: ['section_id'],
    expect: { '': {} }
});

const callNikkiUpdateChinaMainlandIP = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'update_china_mainland_ip',
    expect: { '': {} }
});

const callNikkiUpdateChinaMainlandIP6 = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'update_china_mainland_ip6',
    expect: { '': {} }
});

const callNikkiAPI = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'api',
    params: ['method', 'path', 'query', 'body'],
    expect: { '': {} }
});

const callNikkiGetIdentifiers = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'get_identifiers',
    expect: { '': {} }
});

const callNikkiDebug = rpc.declare({
    object: 'luci.nikki-rs',
    method: 'debug',
    expect: { '': {} }
});

const homeDir = '/etc/nikki-rs';
const profilesDir = `${homeDir}/profiles`;
const subscriptionsDir = `${homeDir}/subscriptions`;
const mixinFilePath = `${homeDir}/mixin.yaml`;
const runDir = `${homeDir}/run`;
const runProfilePath = `${runDir}/config.yaml`;
const providersDir = `${homeDir}/providers`;
const ruleProvidersDir = `${providersDir}/rule`;
const dnsDir = `${homeDir}/dns`;
const blackFilterPath = `${dnsDir}/black_filter`;
const fakeIpFilterPath = `${dnsDir}/fake_ip_filter`;
const fallbackFilterPath = `${dnsDir}/fallback_filter`;
const logDir = `/var/log/nikki-rs`;
const appLogPath = `${logDir}/app.log`;
const coreLogPath = `${logDir}/core.log`;
const debugLogPath = `${logDir}/debug.log`;
const nftDir = `${homeDir}/nftables`;
const proxyWhitelistPath = `${nftDir}/proxy_whitelist.txt`;
const proxyWhitelist6Path = `${nftDir}/proxy_whitelist6.txt`;

return baseclass.extend({
    homeDir: homeDir,
    profilesDir: profilesDir,
    subscriptionsDir: subscriptionsDir,
    mixinFilePath: mixinFilePath,
    runDir: runDir,
    runProfilePath: runProfilePath,
    ruleProvidersDir: ruleProvidersDir,
    dnsDir: dnsDir,
    blackFilterPath: blackFilterPath,
    fakeIpFilterPath: fakeIpFilterPath,
    fallbackFilterPath: fallbackFilterPath,
    proxyWhitelistPath: proxyWhitelistPath,
    proxyWhitelist6Path: proxyWhitelist6Path,
    appLogPath: appLogPath,
    coreLogPath: coreLogPath,
    debugLogPath: debugLogPath,

    status: async function () {
        return (await callRCList('nikki-rs')) ? ['nikki-rs']?.running;
    },

    reload: function () {
        return callRCInit('nikki-rs', 'reload');
    },

    restart: function () {
        return callRCInit('nikki-rs', 'restart');
    },

    writefile: function (path, data, mode) {
        data = (data != null) ? String(data) : '';
        mode = (mode != null) ? mode : 0o644;

        const encoder = new TextEncoder();
        const decoder = new TextDecoder();
        const chunkSize = 8 * 1024;

        const bytes = encoder.encode(data);

        if (bytes.length <= chunkSize) {
            return callFileWrite(path, data, false, mode);
        }

        let promise = Promise.resolve();
        for (let offset = 0; offset < bytes.length; offset += chunkSize) {
            const chunkStart = offset;
            const chunkEnd = Math.min(offset + chunkSize, bytes.length);
            const isLastChunk = chunkEnd === bytes.length;
            const chunkBytes = bytes.slice(chunkStart, chunkEnd);
            const chunk = decoder.decode(chunkBytes, { stream: !isLastChunk });
            const append = offset > 0;
            promise = promise.then(() => callFileWrite(path, chunk, append, mode));
        }

        return promise;
    },

    version: function () {
        return callNikkiVersion();
    },

    profile: function (defaults) {
        return callNikkiProfile(defaults);
    },

    updateSubscription: function (section_id) {
        return callNikkiUpdateSubscription(section_id);
    },

    updateRuleProvider: function (section_id) {
        return callNikkiUpdateRuleProvider(section_id);
    },

    updateChinaMainlandIP: function () {
        return callNikkiUpdateChinaMainlandIP();
    },

    updateChinaMainlandIP6: function () {
        return callNikkiUpdateChinaMainlandIP6();
    },

    updateDashboard: function () {
        return callNikkiAPI('POST', '/upgrade/ui');
    },

    openDashboard: async function () {
        const profile = await callNikkiProfile({
            'external-ui-name': null,
            'external-controller': null,
            'secret': null
        });
        const uiName = profile['external-ui-name'];
        const apiListen = profile['external-controller'];
        const apiSecret = profile['secret'] ?? '';
        if (!apiListen) {
            return Promise.reject('API has not been configured');
        }

        const protocol = 'http';
        const port = apiListen.substring(apiListen.lastIndexOf(':') + 1);

        const params = {
            host: window.location.hostname,
            hostname: window.location.hostname,
            port: port,
            secret: apiSecret
        };
        const query = new URLSearchParams(params).toString();
        let url;
        if (uiName) {
            url = `${protocol}://${window.location.hostname}:${port}/ui/${uiName}/?${query}`;
        } else {
            url = `${protocol}://${window.location.hostname}:${port}/ui/?${query}`;
        }

        setTimeout(function () { window.open(url, '_blank') }, 0);

        return Promise.resolve();
    },

    getIdentifiers: function () {
        return callNikkiGetIdentifiers();
    },

    listProfiles: function () {
        return L.resolveDefault(fs.list(this.profilesDir), []);
    },

    getAppLog: function () {
        return L.resolveDefault(fs.read_direct(this.appLogPath));
    },

    getCoreLog: function () {
        return L.resolveDefault(fs.read_direct(this.coreLogPath));
    },

    clearAppLog: function () {
        return this.writefile(this.appLogPath, '');
    },

    clearCoreLog: function () {
        return this.writefile(this.coreLogPath, '');
    },

    debug: function () {
        return callNikkiDebug();
    },
})
