// SPDX-License-Identifier: GPL-3.0-only

'use strict';
'require ui';
'require view';
'require view.honk-filter.rpc as f';

function installStyles() {
	if (document.querySelector('link[data-hkf-style]'))
		return;
	const link = E('link', {
		'rel': 'stylesheet',
		'data-hkf-style': '',
		'href': L.resource('view/honk-filter/filter.css')
	});
	document.head.appendChild(link);
}

function card(title, body, titleExtra) {
	const head = E('div', { 'class': 'hkf-card-title' }, [ E('h3', {}, title) ]);
	if (titleExtra)
		head.appendChild(titleExtra);
	return E('div', { 'class': 'hkf-card' }, [ head, body ]);
}

function badge(enabled) {
	return E('span', { 'class': 'hkf-badge %s'.format(enabled ? 'on' : 'off') },
		enabled ? _('Enabled') : _('Disabled'));
}

function fmtTime(ts) {
	if (!ts || ts === 0) return '—';
	try {
		return (new Date(ts * 1000)).toLocaleString();
	} catch (e) { return '—'; }
}

function switchControl(id, checked, onChange) {
	const input = E('input', { 'type': 'checkbox', 'id': id });
	input.checked = !!checked;
	input.addEventListener('change', function() { onChange(input.checked); });
	return E('label', { 'class': 'hkf-switch' }, [ input, E('span', { 'class': 'hkf-slider' }) ]);
}

return view.extend({
	load: function() {
		return Promise.all([
			f.status().catch(function() { return {}; }),
			f.sources().catch(function() { return { sources: [] }; }),
			f.logs().catch(function() { return { logs: '' }; })
		]);
	},

	render: function(data) {
		installStyles();

		const status = data[0] || {};
		const sourceList = (data[1] && data[1].sources) || [];
		const logs = (data[2] && data[2].logs) || '';

		const enabled = !!(status.enabled === true || status.enabled === 1 || status.enabled === 'true');
		const active = !!(status.active === true || status.active === 1 || status.active === 'true');
		const rules = status.rules || 0;
		const last = fmtTime(status.last_update);

		/* ---- status card ---- */
		const statusBadge = badge(active);
		const toggle = switchControl('hkf-enable', enabled, function(on) {
			ui.showModal(_('Applying…'), E('p', {}, _('Please wait.')));
			f.setEnabled(on).then(function(res) {
				ui.hideModal();
				if (f.isOk(res)) {
					const m = f.msg(res, '');
					if (on && /applied:0/.test(m))
						ui.addNotification(null, E('p', {}, _('Filter enabled but 0 domains: add/download a rule source first.')));
					location.reload();
				}
				else { ui.addNotification(null, E('p', {}, f.msg(res, _('Failed to apply')))); }
			}).catch(function(e) {
				ui.hideModal();
				ui.addNotification(null, E('p', {}, e.message));
			});
		});
		const stats = E('div', { 'class': 'hkf-stats' }, [
			E('div', { 'class': 'hkf-stat' }, [
				E('div', { 'class': 'hkf-stat-label' }, _('Engine status')),
				E('div', { 'class': 'hkf-stat-value' }, [ statusBadge ])
			]),
			E('div', { 'class': 'hkf-stat' }, [
				E('div', { 'class': 'hkf-stat-label' }, _('Active domains')),
				E('div', { 'class': 'hkf-stat-value' }, String(rules))
			]),
			E('div', { 'class': 'hkf-stat' }, [
				E('div', { 'class': 'hkf-stat-label' }, _('Last update')),
				E('div', { 'class': 'hkf-stat-value' }, [ E('small', {}, last) ])
			]),
			E('div', { 'class': 'hkf-stat' }, [
				E('div', { 'class': 'hkf-stat-label' }, _('Enable filter')),
				E('div', { 'class': 'hkf-stat-value' }, [ toggle ])
			])
		]);
		const rebuildBtn = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Rebuild rules'));
		rebuildBtn.addEventListener('click', function() {
			rebuildBtn.disabled = true;
			f.rebuild().then(function(res) {
				rebuildBtn.disabled = false;
				if (f.isOk(res)) { ui.addNotification(null, E('p', {}, _('Rebuilt: %s domains').format((res.message || '').split(':')[1] || '?'))); }
				else { ui.addNotification(null, E('p', {}, f.msg(res, _('Rebuild failed')))); }
			}).catch(function(e) { rebuildBtn.disabled = false; ui.addNotification(null, E('p', {}, e.message)); });
		});
		const statusCard = card(_('Status'), E('div', {}, [
			stats,
			E('div', { 'class': 'hkf-toolbar', 'style': 'margin-top:14px' }, [ rebuildBtn ]),
			E('p', { 'class': 'hkf-note' }, _('Rules are written directly into Honk as native block rules. No AdGuardHome or mosdns process is started.'))
		]));

		/* ---- sources card ---- */
		const tbody = E('tbody');
		if (!sourceList.length) {
			tbody.appendChild(E('tr', {}, [ E('td', { 'colspan': '5', 'class': 'hkf-empty' }, _('No rule sources configured yet.')) ]));
		} else {
			sourceList.forEach(function(s) {
				const sEnabled = !!(s.enabled === true || s.enabled === 1 || s.enabled === 'true');
				const upBtn = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Update'));
				upBtn.addEventListener('click', function() {
					upBtn.disabled = true;
					f.sourceUpdate(s.section).then(function(res) {
						upBtn.disabled = false;
						const ok = f.isOk(res);
						ui.addNotification(null, E('p', {}, (ok ? _('Update: ') : _('Update failed: ')) + f.msg(res, '')));
						if (ok) setTimeout(function() { location.reload(); }, 2500);
					}).catch(function(e) { upBtn.disabled = false; ui.addNotification(null, E('p', {}, e.message)); });
				});
				const rmBtn = E('button', { 'class': 'hkf-btn danger', 'type': 'button' }, _('Remove'));
				rmBtn.addEventListener('click', function() {
					f.sourceRemove(s.section).then(function() { location.reload(); });
				});
				const sw = switchControl('hkf-src-' + s.section, sEnabled, function(on) {
					f.sourceToggle(s.section, on).then(function() { location.reload(); });
				});
				tbody.appendChild(E('tr', {}, [
					E('td', {}, s.name || s.section),
					E('td', {}, s.format || 'auto'),
					E('td', {}, [ sw ]),
					E('td', {}, s.fail_count ? (_('fails: %s').format(s.fail_count)) : fmtTime(s.last_update)),
					E('td', { 'class': 'actions' }, [ upBtn, ' ', rmBtn ])
				]));
			});
		}
		const table = E('table', { 'class': 'hkf-table' }, [
			E('thead', {}, [ E('tr', {}, [
				E('th', {}, _('Name')), E('th', {}, _('Format')), E('th', {}, _('Enabled')),
				E('th', {}, _('Last update')), E('th', {}, _('Actions'))
			]) ]), tbody
		]);

		const nameIn = E('input', { 'type': 'text', 'placeholder': _('e.g. EasyList China') });
		const urlIn = E('input', { 'type': 'text', 'placeholder': 'https://example.com/rules.txt' });
		const fmtIn = E('select', {}, [
			E('option', { 'value': 'auto' }, _('Auto')),
			E('option', { 'value': 'hosts' }, 'hosts'),
			E('option', { 'value': 'abp' }, 'ABP'),
			E('option', { 'value': 'domain' }, _('Plain domain'))
		]);
		const addBtn = E('button', { 'class': 'hkf-btn primary', 'type': 'button' }, _('Add online source'));
		addBtn.addEventListener('click', function() {
			const name = nameIn.value.trim(), url = urlIn.value.trim();
			if (!name || !url) { ui.addNotification(null, E('p', {}, _('Name and URL are required.'))); return; }
			addBtn.disabled = true;
			f.sourceAdd(name, url, fmtIn.value, '', 86400, true).then(function(res) {
				addBtn.disabled = false;
				if (f.isOk(res)) {
					ui.addNotification(null, E('p', {}, _('Source added: ') + f.msg(res, '')));
					setTimeout(function() { location.reload(); }, 2500);
				}
				else ui.addNotification(null, E('p', {}, f.msg(res, _('Failed to add'))));
			}).catch(function(e) { addBtn.disabled = false; ui.addNotification(null, E('p', {}, e.message)); });
		});

		const uploadIn = E('textarea', { 'placeholder': _('Paste offline rule package content here (one rule per line)…') });
		const uploadBtn = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Import offline package'));
		uploadBtn.addEventListener('click', function() {
			const text = uploadIn.value.trim();
			if (!text) { ui.addNotification(null, E('p', {}, _('Paste rule content first.'))); return; }
			uploadBtn.disabled = true;
			f.importText(text).then(function(res) {
				uploadBtn.disabled = false;
				if (f.isOk(res)) { uploadIn.value = ''; location.reload(); }
				else ui.addNotification(null, E('p', {}, f.msg(res, _('Import failed'))));
			}).catch(function(e) { uploadBtn.disabled = false; ui.addNotification(null, E('p', {}, e.message)); });
		});

		const sourcesCard = card(_('Rule sources'), E('div', {}, [
			table,
			E('div', { 'class': 'hkf-grid', 'style': 'margin-top:16px' }, [
				E('div', {}, [
					E('div', { 'class': 'hkf-field' }, [ E('label', {}, _('Source name')), nameIn ]),
					E('div', { 'class': 'hkf-field' }, [ E('label', {}, _('Rule URL')), urlIn ]),
					E('div', { 'class': 'hkf-field' }, [ E('label', {}, _('Format')), fmtIn ]),
					addBtn
				]),
				E('div', {}, [
					E('div', { 'class': 'hkf-field' }, [
						E('label', {}, _('Offline rule package')), uploadIn,
						E('div', { 'class': 'hint' }, _('Paste plain-domain / hosts / ABP rules. Stored as an offline source.'))
					]),
					uploadBtn
				])
			]),
			E('p', { 'class': 'hkf-note', 'style': 'margin-top:12px' },
				_('Supported rule formats: plain domain, hosts (0.0.0.0 domain), ABP (||domain^) and @@ whitelist. Complex regex and $modifier rules are skipped.'))
		]));

		/* ---- custom / whitelist card ---- */
		const customIn = E('input', { 'type': 'text', 'placeholder': 'ads.example.com' });
		const customAdd = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Add'));
		customAdd.addEventListener('click', function() {
			const d = customIn.value.trim(); if (!d) return;
			f.customAdd(d).then(function() { customIn.value = ''; location.reload(); });
		});
		const wlIn = E('input', { 'type': 'text', 'placeholder': 'whitelist.example.com' });
		const wlAdd = E('button', { 'class': 'hkf-btn', 'type': 'button' }, _('Add'));
		wlAdd.addEventListener('click', function() {
			const d = wlIn.value.trim(); if (!d) return;
			f.whitelistAdd(d).then(function() { wlIn.value = ''; location.reload(); });
		});
		const customCard = card(_('Custom rules & whitelist'), E('div', { 'class': 'hkf-grid' }, [
			E('div', { 'class': 'hkf-field' }, [
				E('label', {}, _('Custom blocked domain')),
				E('div', { 'class': 'hkf-row' }, [ customIn, customAdd ])
			]),
			E('div', { 'class': 'hkf-field' }, [
				E('label', {}, _('Whitelisted domain')),
				E('div', { 'class': 'hkf-row' }, [ wlIn, wlAdd ])
			])
		]));

		/* ---- log card ---- */
		const logBox = E('div', { 'class': 'hkf-log' }, logs || _('No log entries yet.'));
		const logCard = card(_('Update log'), logBox);

		return E('div', { 'class': 'hkf-page cbi-map' }, [
			E('div', { 'class': 'hkf-header' }, [
				E('div', {}, [
					E('h2', {}, _('Honk AdBlock')),
					E('p', {}, _('Native ad filtering powered by Honk — no extra DNS layer.'))
				])
			]),
			statusCard, sourcesCard, customCard, logCard
		]);
	}
});
