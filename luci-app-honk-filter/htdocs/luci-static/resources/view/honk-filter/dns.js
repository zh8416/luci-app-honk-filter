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

function parseUpstreams(text) {
	if (!text) return [];
	return text.split('\n').map(function(line) {
		if (!line) return null;
		const p = line.split('\t');
		return { address: p[0] || '', group: p[1] || 'default', outbound: p[2] || 'auto' };
	}).filter(function(x) { return x && x.address; });
}

function groupSelect(value) {
	const s = E('select', {}, [
		E('option', { 'value': 'default' }, _('Domestic (direct)')),
		E('option', { 'value': 'remote' }, _('Remote (proxy)'))
	]);
	s.value = value === 'remote' ? 'remote' : 'default';
	return s;
}

function outboundSelect(value) {
	const s = E('select', {}, [
		E('option', { 'value': 'auto' }, _('Auto (by group)')),
		E('option', { 'value': 'direct' }, _('Direct')),
		E('option', { 'value': 'proxy' }, _('Proxy'))
	]);
	s.value = (value === 'direct' || value === 'proxy') ? value : 'auto';
	return s;
}

return view.extend({
	load: function() {
		return f.dnsRead().catch(function() { return {}; });
	},

	render: function(cfg) {
		installStyles();
		cfg = cfg || {};

		let rows = parseUpstreams(cfg.upstreams);
		if (!rows.length) {
			if (cfg.default_upstream)
				rows.push({ address: cfg.default_upstream, group: 'default', outbound: 'direct' });
			if (cfg.remote_upstream)
				rows.push({ address: cfg.remote_upstream, group: 'remote', outbound: 'proxy' });
		}

		const bootstrap = E('input', { 'type': 'text', 'value': cfg.bootstrap || '' });
		const fallback = E('select', {}, [
			E('option', { 'value': 'remote' }, _('Remote (proxy DNS)')),
			E('option', { 'value': 'default' }, _('Default (direct DNS)')),
			E('option', { 'value': 'accept' }, _('Accept'))
		]);
		fallback.value = cfg.fallback || 'remote';

		const cacheSw = switchControl('hkf-dns-cache', cfg.cache === true || cfg.cache === 1 || cfg.cache === 'true');
		const ipv6Sw = switchControl('hkf-dns-ipv6', cfg.ipv6 === true || cfg.ipv6 === 1 || cfg.ipv6 === 'true');

		const tbody = E('tbody');

		function redraw() {
			while (tbody.firstChild)
				tbody.removeChild(tbody.firstChild);
			rows.forEach(function(r, i) {
				const addr = E('input', { 'type': 'text', 'value': r.address, 'style': 'width:100%' });
				addr.addEventListener('change', function() { r.address = addr.value.trim(); });
				const grp = groupSelect(r.group);
				grp.addEventListener('change', function() { r.group = grp.value; });
				const out = outboundSelect(r.outbound);
				out.addEventListener('change', function() { r.outbound = out.value; });
				const del = E('button', { 'class': 'hkf-btn danger', 'type': 'button' }, _('Remove'));
				del.addEventListener('click', function() { rows.splice(i, 1); redraw(); });
				tbody.appendChild(E('tr', {}, [
					E('td', {}, [ addr ]), E('td', {}, [ grp ]), E('td', {}, [ out ]),
					E('td', { 'class': 'actions' }, [ del ])
				]));
			});
		}
		redraw();

		const addBtn = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Add DNS upstream'));
		addBtn.addEventListener('click', function() {
			rows.push({ address: '', group: 'default', outbound: 'auto' });
			redraw();
		});

		const table = E('table', { 'class': 'hkf-table' }, [
			E('thead', {}, [ E('tr', {}, [
				E('th', {}, _('Address')), E('th', {}, _('Group')),
				E('th', {}, _('Outbound')), E('th', {}, _('Actions'))
			]) ]), tbody
		]);

		const saveBtn = E('button', { 'class': 'hkf-btn primary', 'type': 'button' }, _('Save'));
		const resetBtn = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Reset to defaults'));

		saveBtn.addEventListener('click', function() {
			const payload = {
				default_upstream: rows.length ? rows[0].address : '',
				remote_upstream: rows.length > 1 ? rows[1].address : '',
				bootstrap: bootstrap.value.trim(),
				fallback: fallback.value,
				cache: cacheSw.querySelector('input').checked,
				ipv6: ipv6Sw.querySelector('input').checked,
				upstreams: rows.filter(function(r) { return r.address; }).map(function(r) {
					return [ r.address, r.group, r.outbound ].join('\t');
				}).join('\n')
			};
			saveBtn.disabled = true;
			f.dnsSave(JSON.stringify(payload)).then(function(res) {
				saveBtn.disabled = false;
				if (f.isOk(res)) ui.addNotification(null, E('p', {}, _('DNS settings saved.')));
				else ui.addNotification(null, E('p', {}, f.msg(res, _('Save failed'))));
			}).catch(function(e) { saveBtn.disabled = false; ui.addNotification(null, E('p', {}, e.message)); });
		});

		resetBtn.addEventListener('click', function() {
			f.dnsReset().then(function(res) {
				if (f.isOk(res)) location.reload();
				else ui.addNotification(null, E('p', {}, f.msg(res, _('Reset failed'))));
			});
		});

		const upstreamCard = E('div', { 'class': 'hkf-card' }, [
			E('div', { 'class': 'hkf-card-title' }, [ E('h3', {}, _('DNS upstreams')) ]),
			table,
			E('div', { 'class': 'hkf-toolbar', 'style': 'margin-top:12px' }, [ addBtn ]),
			E('p', { 'class': 'hkf-note' },
				_('Honk supports multiple named upstreams. The first domestic and first remote entry become default/remote used by the stock routing rules; extra entries can be referenced in Doona or custom DNS routes. One entry holds exactly one address.'))
		]);

		const formCard = E('div', { 'class': 'hkf-card' }, [
			E('div', { 'class': 'hkf-card-title' }, [ E('h3', {}, _('DNS routing')) ]),
			E('div', { 'class': 'hkf-grid' }, [
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
				_('Settings are written into Honk\'s own dns {} and global {} blocks after validation. A failed validation never replaces the running config.'))
		]);

		return E('div', { 'class': 'hkf-page cbi-map' }, [
			E('div', { 'class': 'hkf-header' }, [
				E('div', {}, [
					E('h2', {}, _('Honk DNS Routing')),
					E('p', {}, _('Native DNS split routing — configured through Honk itself.'))
				])
			]),
			upstreamCard, formCard, noteCard
		]);
	}
});
