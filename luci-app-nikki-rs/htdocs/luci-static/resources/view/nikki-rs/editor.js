'use strict';
'require form';
'require view';
'require uci';
'require fs';
'require tools.nikki-rs as nikki';

return view.extend({
    load: function () {
        return Promise.all([
            uci.load('nikki-rs'),
            nikki.listProfiles(),
        ]);
    },
    render: function (data) {
        const subscriptions = uci.sections('nikki-rs', 'subscription');
        const profiles = data[1];

        let m, s, o;

        m = new form.Map('nikki-rs');

        s = m.section(form.NamedSection, 'editor', 'editor', _('Editor'));

        o = s.option(form.ListValue, '_file', _('Choose File'));
        o.optional = true;

        for (const profile of profiles) {
            o.value(nikki.profilesDir + '/' + profile.name, _('File:') + profile.name);
        };

        for (const subscription of subscriptions) {
            o.value(nikki.subscriptionsDir + '/' + subscription['.name'] + '.yaml', _('Subscription:') + subscription.name);
        };

        o.value(nikki.mixinFilePath, _('File for Mixin'));
        o.value(nikki.runProfilePath, _('Profile for Startup'));
        o.value(nikki.blackFilterPath, _('Black Filter File'));
        o.value(nikki.fakeIpFilterPath, _('Fake IP Filter File'));
        o.value(nikki.fallbackFilterPath, _('Fallback Filter File'));
        o.value(nikki.proxyWhitelistPath, _('Proxy Whitelist File (IPv4)'));
        o.value(nikki.proxyWhitelist6Path, _('Proxy Whitelist File (IPv6)'));

        o.write = function (section_id, formvalue) {
            return true;
        };
        o.onchange = function (event, section_id, value) {
            return L.resolveDefault(fs.read_direct(value), '').then(function (content) {
                m.lookupOption('_file_content', section_id)[0].getUIElement(section_id).setValue(content);
            });
        };

        o = s.option(form.TextValue, '_file_content',);
        o.rows = 25;
        o.wrap = false;
        o.write = function (section_id, formvalue) {
            const path = m.lookupOption('_file', section_id)[0].formvalue(section_id);
            return nikki.writefile(path, formvalue);
        };
        o.remove = function (section_id) {
            const path = m.lookupOption('_file', section_id)[0].formvalue(section_id);
            return nikki.writefile(path);
        };

        return m.render();
    },
    handleSaveApply: function (ev, mode) {
        return this.handleSave(ev).finally(function () {
            return mode === '0' ? nikki.reload() : nikki.restart();
        });
    },
    handleReset: null
});
