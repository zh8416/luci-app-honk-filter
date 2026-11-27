// SPDX-License-Identifier: GPL-3.0-only

'use strict';
'require baseclass';
'require rpc';

const fStatus = rpc.declare({ object: 'honk-filter', method: 'status', expect: { '': {} } });
const fSources = rpc.declare({ object: 'honk-filter', method: 'sources', expect: { '': {} } });
const fLogs = rpc.declare({ object: 'honk-filter', method: 'logs', expect: { '': {} } });
const fDnsRead = rpc.declare({ object: 'honk-filter', method: 'dns_read', expect: { '': {} } });

const fSourceAdd = rpc.declare({
	object: 'honk-filter', method: 'source_add',
	params: [ 'name', 'url', 'format', 'ua', 'interval', 'enabled' ], expect: { '': {} }
});
const fSourceRemove = rpc.declare({ object: 'honk-filter', method: 'source_remove', params: [ 'section' ], expect: { '': {} } });
const fSourceToggle = rpc.declare({ object: 'honk-filter', method: 'source_toggle', params: [ 'section', 'enabled' ], expect: { '': {} } });
const fSourceUpdate = rpc.declare({ object: 'honk-filter', method: 'source_update', params: [ 'section' ], expect: { '': {} } });
const fRebuild = rpc.declare({ object: 'honk-filter', method: 'rebuild', expect: { '': {} } });
const fSetEnabled = rpc.declare({ object: 'honk-filter', method: 'set_enabled', params: [ 'enabled' ], expect: { '': {} } });
const fWhitelistAdd = rpc.declare({ object: 'honk-filter', method: 'whitelist_add', params: [ 'domain' ], expect: { '': {} } });
const fWhitelistRemove = rpc.declare({ object: 'honk-filter', method: 'whitelist_remove', params: [ 'domain' ], expect: { '': {} } });
const fCustomAdd = rpc.declare({ object: 'honk-filter', method: 'custom_add', params: [ 'domain' ], expect: { '': {} } });
const fCustomRemove = rpc.declare({ object: 'honk-filter', method: 'custom_remove', params: [ 'domain' ], expect: { '': {} } });
const fDnsSave = rpc.declare({
	object: 'honk-filter', method: 'dns_save',
	params: [ 'default_upstream', 'remote_upstream', 'bootstrap', 'fallback', 'cache', 'ipv6' ], expect: { '': {} }
});
const fDnsReset = rpc.declare({ object: 'honk-filter', method: 'dns_reset', expect: { '': {} } });
const fImportText = rpc.declare({ object: 'honk-filter', method: 'import_text', params: [ 'content' ], expect: { '': {} } });

function isOk(result) {
	return !!(result && (result.ok === true || result.ok === 1 || result.ok === 'true'));
}

function msg(result, fallback) {
	return (result && result.message) || fallback || '';
}

return baseclass.extend({
	status: fStatus,
	sources: fSources,
	logs: fLogs,
	dnsRead: fDnsRead,
	sourceAdd: fSourceAdd,
	sourceRemove: fSourceRemove,
	sourceToggle: fSourceToggle,
	sourceUpdate: fSourceUpdate,
	rebuild: fRebuild,
	setEnabled: fSetEnabled,
	whitelistAdd: fWhitelistAdd,
	whitelistRemove: fWhitelistRemove,
	customAdd: fCustomAdd,
	customRemove: fCustomRemove,
	dnsSave: fDnsSave,
	dnsReset: fDnsReset,
	importText: fImportText,
	isOk: isOk,
	msg: msg
});
