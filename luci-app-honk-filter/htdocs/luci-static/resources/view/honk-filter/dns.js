// SPDX-License-Identifier: GPL-3.0-only

'use strict';
'require ui';
'require view';
'require view.honk-filter.rpc as f';

function installStyles() {
	if (document.querySelector('link[data-hkf-style]'))
		return;
	document.head.appendChild(E('link', {
		'rel': 'stylesheet', 'data-hkf-style': '',
		'href': L.resource('view/honk-filter/filter.css')
	}));
}

function field(label, control, hint) {
	const cell = E('div', {}, [ control ]);
	if (hint) cell.appendChild(E('div', { 'class': 'hint' }, hint));
	return E('div', { 'class': 'hkf-field' }, [ E('label', {}, label), cell ]);
}

function switchControl(id, checked) {
	const input = E('input', { 'type': 'checkbox', 'id': id });
	input.checked = !!checked;
	return E('label', { 'class': 'hkf-switch' }, [ input, E('span', { 'class': 'hkf-slider' }) ]);
}

return view.extend({
	load: function() {
		return f.dnsRead().catch(function() { return {}; });
	},

	render: function(cfg) {
		installStyles();
		cfg = cfg || {};

		const defaultUp = E('input', { 'type': 'text', 'value': cfg.default_upstream || '' });
		const remoteUp = E('input', { 'type': 'text', 'value': cfg.remote_upstream || '' });
		const bootstrap = E('input', { 'type': 'text', 'value': cfg.bootstrap || '' });
		const fallback = E('select', {}, [
			E('option', { 'value': 'remote' }, _('Remote (proxy DNS)')),
			E('option', { 'value': 'default' }, _('Default (direct DNS)')),
			E('option', { 'value': 'accept' }, _('Accept'))
		]);
		fallback.value = cfg.fallback || 'remote';

		const cacheSw = switchControl('hkf-dns-cache', cfg.cache === true || cfg.cache === 1 || cfg.cache === 'true');
		const ipv6Sw = switchControl('hkf-dns-ipv6', cfg.ipv6 === true || cfg.ipv6 === 1 || cfg.ipv6 === 'true');

		const saveBtn = E('button', { 'class': 'hkf-btn primary', 'type': 'button' }, _('Save'));
		const resetBtn = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Reset to defaults'));

		saveBtn.addEventListener('click', function() {
			const cache = cacheSw.querySelector('input').checked;
			const ipv6 = ipv6Sw.querySelector('input').checked;
			saveBtn.disabled = true;
			f.dnsSave(defaultUp.value.trim(), remoteUp.value.trim(), bootstrap.value.trim(), fallback.value, cache, ipv6)
				.then(function(res) {
					saveBtn.disabled = false;
					if (f.isOk(res)) ui.addNotification(null, E('p', {}, _('DNS settings saved.')));
					else ui.addNotification(null, E('p', {}, f.msg(res, _('Save failed'))));
				})
				.catch(function(e) { saveBtn.disabled = false; ui.addNotification(null, E('p', {}, e.message)); });
		});

		resetBtn.addEventListener('click', function() {
			f.dnsReset().then(function(res) {
				if (f.isOk(res)) location.reload();
				else ui.addNotification(null, E('p', {}, f.msg(res, _('Reset failed'))));
			});
		});

		const formCard = E('div', { 'class': 'hkf-card' }, [
			E('div', { 'class': 'hkf-card-title' }, [ E('h3', {}, _('DNS upstream & routing')) ]),
			E('div', { 'class': 'hkf-grid' }, [
				field(_('Domestic DNS (default)'), defaultUp, _('Used for domestic domains, e.g. https://223.5.5.5/dns-query')),
				field(_('Remote DNS (proxy)'), remoteUp, _('Used for foreign domains, e.g. https://8.8.8.8/dns-query')),
				field(_('Bootstrap resolver'), bootstrap, _('Resolves the DNS server addresses themselves, e.g. 1.1.1.1:53')),
				field(_('Fallback'), fallback, _('Which upstream to use when no rule matches'))
			]),
			E('div', { 'class': 'hkf-grid', 'style': 'margin-top:8px' }, [
				field(_('DNS cache'), cacheSw, _('Cache resolved results across restarts')),
				field(_('IPv6 (AAAA)'), ipv6Sw, _('Allow AAAA answers'))
			]),
			E('div', { 'class': 'hkf-toolbar', 'style': 'margin-top:14px' }, [ saveBtn, resetBtn ])
		]);

		const noteCard = E('div', { 'class': 'hkf-card' }, [
			E('h3', {}, _('About')),
			E('p', { 'class': 'hkf-note' },
				_('These settings write into Honk\'s own dns {} and global {} blocks after validation. A failed validation never replaces the running config. Advanced DNS features (Apple optimization, anti-leak, HTTPS/SVCB filtering) are planned for a later release.'))
		]);

		return E('div', { 'class': 'hkf-page cbi-map' }, [
			E('div', { 'class': 'hkf-header' }, [
				E('div', {}, [
					E('h2', {}, _('Honk DNS Routing')),
					E('p', {}, _('Native DNS split routing — configured through Honk itself.'))
				])
			]),
			formCard, noteCard
		]);
	}
});
