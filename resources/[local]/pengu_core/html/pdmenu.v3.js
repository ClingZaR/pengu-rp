/* ============================================================
   PenguRP - Police Services menu logic.
   Opened by the pdloc garage / clothing / armory points via a
   SendNUIMessage({ action:'openPdMenu', ... }). Renders a card grid
   and relays clicks back to the client over fetch callbacks.
   ============================================================ */
(function () {
  'use strict';

  var RES = 'pengu_core';

  // Inner SVG paths for the card / header icons (Lucide-style strokes).
  var ICON = {
    services: '<path d="M12 3l7 3v5c0 4.5-3 7.8-7 9-4-1.2-7-4.5-7-9V6l7-3z"/><path d="M9.5 12l1.8 1.8L15 10"/>',
    gear:  '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    plus:  '<path d="M12 5v14M5 12h14"/>',
    wrench:'<path d="M14.7 6.3a4 4 0 0 0-5.4 5.3L3 18l3 3 6.4-6.3a4 4 0 0 0 5.3-5.4l-2.6 2.6-2.3-.6-.6-2.3z"/>',
    trash: '<path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>',
    check: '<path d="M20 6L9 17l-5-5"/>',
    car:   '<path d="M5 11l1.6-4.2A2 2 0 0 1 8.5 5.5h7a2 2 0 0 1 1.9 1.3L19 11"/><rect x="3" y="11" width="18" height="6" rx="2"/><circle cx="7.5" cy="17" r="1.4"/><circle cx="16.5" cy="17" r="1.4"/>',
    suv:   '<path d="M4 12l1-5h14l1 5"/><rect x="2.5" y="12" width="19" height="6" rx="2"/><circle cx="7" cy="18" r="1.5"/><circle cx="17" cy="18" r="1.5"/><path d="M9 7v5M14 7v5"/>',
    bike:  '<circle cx="5.5" cy="17" r="3"/><circle cx="18.5" cy="17" r="3"/><path d="M5.5 17l4-7h5l2 4"/><path d="M9.5 10h4"/>',
    van:   '<path d="M3 7h11v10H3z"/><path d="M14 10h4l3 3v4h-7z"/><circle cx="7" cy="18" r="1.5"/><circle cx="17.5" cy="18" r="1.5"/>',
    heli:  '<path d="M3 5h12M9 5v4M5 9h11l4 3h1a1 1 0 0 1 0 4h-9a6 6 0 0 1-6-4z"/><path d="M9 16v3h6"/><path d="M19 19h3"/>',
    shirt: '<path d="M16 3l5 3-2 4-2-1v12H7V9L5 10 3 6l5-3 1.5 1.5a3 3 0 0 0 5 0z"/>',
    vest:  '<path d="M9 3l3 2 3-2 4 3-2 4v9H7v-9L5 6z"/><path d="M12 5v14"/>',
    armor: '<path d="M12 3l7 3v5c0 4.5-3 7.8-7 9-4-1.2-7-4.5-7-9V6l7-3z"/>',
    remove:'<circle cx="12" cy="12" r="9"/><path d="M8 12h8"/>',
    pistol:'<path d="M4 8h12v4h-3l-2 4H8l-1-4H4z"/><path d="M7 12v3"/>',
    taser: '<path d="M13 2L4 14h6l-1 8 9-12h-6z"/>',
    baton: '<path d="M5 19L19 5"/><path d="M16 4l4 4"/><circle cx="6.5" cy="17.5" r="1.5"/>',
    ammo:  '<rect x="6" y="3" width="4" height="9" rx="1"/><path d="M6 12h4v6a2 2 0 0 1-4 0z"/><rect x="14" y="5" width="4" height="9" rx="1"/><path d="M14 14h4v4a2 2 0 0 1-4 0z"/>',
    cuffs: '<circle cx="7" cy="12" r="4"/><circle cx="17" cy="12" r="4"/><path d="M10.5 11h3M10.5 13h3"/>',
    kit:   '<rect x="3" y="7" width="18" height="12" rx="2"/><path d="M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"/><path d="M12 11v4M10 13h4"/>',
    scan:  '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><path d="M9 9c0-1.5 1.3-2.5 3-2.5s3 1 3 2.5v3c0 2-1 3.5-3 3.5"/>',
    spray: '<rect x="8" y="8" width="8" height="12" rx="2"/><path d="M10 8V5h4v3"/><path d="M16 6h2M16 9h2M19 5v5"/>',
    box:   '<path d="M3 8l9-4 9 4-9 4z"/><path d="M3 8v8l9 4 9-4V8"/><path d="M12 12v8"/>',
    item:  '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M9 9h6v6H9z"/>'
  };

  var el = function (id) { return document.getElementById(id); };

  function svg(key) {
    var p = ICON[key] || ICON.item;
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
           'stroke-linecap="round" stroke-linejoin="round">' + p + '</svg>';
  }

  function nui(path, body) {
    return fetch('https://' + RES + '/' + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {})
    }).then(function (r) { return r.json().catch(function () { return {}; }); })
      .catch(function () { return {}; });
  }

  var open = false;
  var mode = null;
  var view = 'cards';            // cards | manage | picker | editor | armoryManage | armoryPicker | wardrobeManage
  var editorCar = null;          // car currently in the mod editor
  var editorMods = null;         // working copy of its mods

  function hide() {
    if (!open) return;
    open = false;
    el('pd-menu').classList.add('hidden');
    el('pd-body').innerHTML = '<div id="pd-grid"></div>';
    nui('pdMenuClose', {});
  }

  // Header helper: title (may contain a <span>), subtitle, badge icon, back arrow.
  function setHeader(title, sub, icon, showBack) {
    el('pd-title').innerHTML = title;
    el('pd-sub').textContent = sub || '';
    el('pd-badge').innerHTML = svg(icon || 'services');
    var back = el('pd-back');
    if (back) back.classList.toggle('show', !!showBack);
  }

  function render(d) {
    mode = d.mode || 'garage';
    view = 'cards';
    setHeader(d.title || 'POLICE <span>SERVICES</span>', d.sub || '', d.headIcon || 'services', false);
    el('pd-foot').innerHTML = d.footer ||
      '<b>Click</b> a card to select &nbsp;&middot;&nbsp; <b>Esc</b> to close';

    el('pd-body').innerHTML = '<div id="pd-grid"></div>';
    var grid = el('pd-grid');
    var items = Array.isArray(d.items) ? d.items : [];
    items.forEach(function (it) {
      var card = document.createElement('div');
      card.className = 'pm-card' + (it.locked ? ' locked' : '');
      var badge = it.badge
        ? '<span class="pm-badge' + (it.badgeKind === 'danger' ? ' danger' : '') + '">' +
          escapeHtml(it.badge) + '</span>'
        : '';
      card.innerHTML =
        badge +
        '<div class="pm-ico">' + svg(it.icon) + '</div>' +
        '<div class="pm-name">' + escapeHtml(it.name || '') + '</div>' +
        (it.meta ? '<div class="pm-meta">' + escapeHtml(it.meta) + '</div>' : '');
      if (!it.locked) {
        card.addEventListener('click', function () {
          nui('pdMenuSelect', { mode: mode, id: it.id }).then(function (res) {
            if (res && res.close) hide();
          });
        });
      }
      grid.appendChild(card);
    });

    // Search bar - shown for long lists (the vehicle bay). Filters cards live.
    var wrap = el('pd-search-wrap');
    var search = el('pd-search');
    var showSearch = mode === 'garage' || items.length > 8;
    if (wrap) wrap.classList.toggle('hidden', !showSearch);
    if (search) {
      search.value = '';
      search.placeholder = mode === 'garage' ? 'Search vehicles...' : 'Search...';
      search.oninput = showSearch ? function () { filterCards(search.value); } : null;
    }

    var ov = el('overlay');   // the menu and the F1 keybinds overlay are exclusive
    if (ov) ov.classList.add('hidden');
    el('pd-menu').classList.remove('hidden');
    open = true;
  }

  function filterCards(q) {
    q = String(q || '').trim().toLowerCase();
    var grid = el('pd-grid');
    if (!grid) return; // a fleet view rebuilt the body; this handler is stale
    var cards = grid.querySelectorAll('.pm-card');
    var shown = 0;
    cards.forEach(function (c) {
      var nm = c.querySelector('.pm-name');
      var match = !q || (nm && nm.textContent.toLowerCase().indexOf(q) !== -1);
      c.style.display = match ? '' : 'none';
      if (match) shown += 1;
    });
    var empty = grid.querySelector('.pm-empty');
    if (shown === 0) {
      if (!empty) {
        empty = document.createElement('div');
        empty.className = 'pm-empty';
        empty.textContent = 'No matches';
        grid.appendChild(empty);
      }
      empty.style.display = '';
    } else if (empty) {
      empty.style.display = 'none';
    }
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // ---------- Fleet management views (chief) ----------
  var WHEEL_TYPES = [['0','Sport'],['1','Muscle'],['2','Lowrider'],['3','SUV'],['4','Offroad'],['5','Tuner'],['6','Bike'],['7','High End'],['8','Benny Original'],['9','Benny Bespoke'],['10','Open Wheel'],['11','Street'],['12','Track']];
  var TINT_OPTS  = [['0','None'],['1','Pure Black'],['2','Dark Smoke'],['3','Light Smoke'],['4','Stock'],['5','Limo']];
  var XENON_OPTS = [['-1','Default'],['0','White'],['1','Blue'],['2','Electric Blue'],['3','Mint'],['4','Lime'],['5','Yellow'],['6','Gold'],['7','Orange'],['8','Red'],['9','Pink'],['10','Hot Pink'],['11','Purple'],['12','Blacklight']];

  function secEl(title) {
    var s = document.createElement('div'); s.className = 'pm-section';
    var t = document.createElement('div'); t.className = 'pm-sec-title'; t.textContent = title;
    s.appendChild(t); return s;
  }
  function fieldEl(label, ctl) {
    var f = document.createElement('div'); f.className = 'pm-field';
    var l = document.createElement('div'); l.className = 'pm-field-label'; l.textContent = label;
    var c = document.createElement('div'); c.className = 'pm-field-ctl';
    if (Array.isArray(ctl)) ctl.forEach(function (e) { c.appendChild(e); }); else c.appendChild(ctl);
    f.appendChild(l); f.appendChild(c); return f;
  }
  function ctlSlider(min, max, val, onChange) {
    var r = document.createElement('input'); r.type = 'range'; r.className = 'pm-range';
    r.min = min; r.max = max; r.value = val;
    var v = document.createElement('span'); v.className = 'pm-range-val'; v.textContent = val;
    r.addEventListener('input', function () { v.textContent = r.value; onChange(parseInt(r.value, 10)); });
    return [r, v];
  }
  function ctlToggle(checked, onChange) {
    var w = document.createElement('label'); w.className = 'pm-switch';
    var i = document.createElement('input'); i.type = 'checkbox'; i.checked = !!checked;
    var t = document.createElement('span'); t.className = 'pm-track';
    i.addEventListener('change', function () { onChange(i.checked); });
    w.appendChild(i); w.appendChild(t); return w;
  }
  function ctlColor(hex, onChange) {
    var w = document.createElement('div'); w.className = 'pm-color';
    var i = document.createElement('input'); i.type = 'color'; i.value = hex || '#ffffff';
    i.addEventListener('input', function () { onChange(i.value); });
    w.appendChild(i); return w;
  }
  function ctlSelect(opts, val, onChange) {
    var s = document.createElement('select'); s.className = 'pm-select';
    opts.forEach(function (o) {
      var op = document.createElement('option'); op.value = o[0]; op.textContent = o[1];
      if (String(o[0]) === String(val)) op.selected = true; s.appendChild(op);
    });
    s.addEventListener('change', function () { onChange(s.value); });
    return s;
  }
  function ctlNumber(min, max, val, onChange) {
    var i = document.createElement('input'); i.type = 'number'; i.className = 'pm-num';
    i.min = min; i.max = max; i.value = val;
    i.addEventListener('change', function () {
      var n = parseInt(i.value, 10); if (isNaN(n)) n = min; if (n < min) n = min; if (n > max) n = max;
      i.value = n; onChange(n);
    });
    return i;
  }
  function ctlText(val, onChange) {
    var i = document.createElement('input'); i.type = 'text'; i.className = 'pm-num';
    i.style.width = '96px'; i.value = val || '';
    i.addEventListener('change', function () { onChange(i.value); });
    return i;
  }
  function rgbHex(rgb) {
    if (!Array.isArray(rgb)) return '#ffffff';
    function h(n) { n = Math.max(0, Math.min(255, n || 0)); return ('0' + n.toString(16)).slice(-2); }
    return '#' + h(rgb[0]) + h(rgb[1]) + h(rgb[2]);
  }
  function hexRgb(hex) {
    hex = String(hex || '').replace('#', '');
    if (hex.length < 6) return [255, 255, 255];
    return [parseInt(hex.substr(0, 2), 16), parseInt(hex.substr(2, 2), 16), parseInt(hex.substr(4, 2), 16)];
  }
  function extrasToStr(ex) {
    if (typeof ex !== 'object' || !ex) return '';
    var t = []; for (var k in ex) { if (ex[k]) t.push(k); } return t.join(',');
  }
  function strToExtras(s) {
    var ex = {}; String(s || '').replace(/\d+/g, function (n) { ex[n] = true; return n; }); return ex;
  }

  function renderManager(d) {
    view = 'manage';
    setHeader('FLEET <span>MANAGER</span>', d.faction ? d.faction.toUpperCase() : '', 'gear', true);
    el('pd-search-wrap').classList.add('hidden');
    (function () { var _s = el('pd-search'); if (_s) _s.oninput = null; })();
    el('pd-foot').innerHTML = '<b>Add</b>, edit mods or remove vehicles';
    var body = el('pd-body'); body.innerHTML = '';

    var add = document.createElement('div'); add.className = 'pm-btn';
    add.innerHTML = svg('plus') + 'Add Vehicle';
    add.addEventListener('click', function () { nui('fleetPickerOpen'); });
    body.appendChild(add);

    var list = document.createElement('div'); list.className = 'pm-list';
    var cars = Array.isArray(d.cars) ? d.cars : [];
    if (!cars.length) {
      var e0 = document.createElement('div'); e0.className = 'pm-empty'; e0.textContent = 'No vehicles in the fleet'; list.appendChild(e0);
    }
    cars.forEach(function (c) {
      var row = document.createElement('div'); row.className = 'pm-row';
      row.innerHTML =
        '<div class="pm-ico">' + svg(c.icon || 'car') + '</div>' +
        '<div class="pm-row-main"><div class="pm-row-title">' + escapeHtml(c.label) + '</div>' +
          '<div class="pm-row-sub">' + escapeHtml(c.model) + (c.grade > 0 ? ' - G' + c.grade : '') + '</div></div>' +
        '<div class="pm-row-acts">' +
          '<div class="pm-iconbtn" data-a="edit" title="Edit mods">' + svg('wrench') + '</div>' +
          '<div class="pm-iconbtn danger" data-a="del" title="Remove">' + svg('trash') + '</div>' +
        '</div>';
      row.querySelector('[data-a="edit"]').addEventListener('click', function () { nui('fleetEditOpen', { id: c.id }); });
      row.querySelector('[data-a="del"]').addEventListener('click', function () { nui('fleetRemove', { id: c.id }); });
      list.appendChild(row);
    });
    body.appendChild(list);
  }

  function renderPicker(d) {
    view = 'picker';
    var all = Array.isArray(d.vehicles) ? d.vehicles : [];
    setHeader('ADD <span>VEHICLE</span>', 'All available models', 'car', true);
    var wrap = el('pd-search-wrap'); wrap.classList.remove('hidden');
    var search = el('pd-search'); search.value = ''; search.placeholder = 'Search ' + all.length + ' vehicles...';
    el('pd-foot').innerHTML = '<b>Click</b> a vehicle to add it';
    var body = el('pd-body'); body.innerHTML = '';
    var list = document.createElement('div'); list.className = 'pm-list'; body.appendChild(list);

    function draw(arr) {
      list.innerHTML = '';
      if (!arr.length) { var e1 = document.createElement('div'); e1.className = 'pm-empty'; e1.textContent = 'No matches'; list.appendChild(e1); return; }
      arr.slice(0, 150).forEach(function (v) {
        var row = document.createElement('div'); row.className = 'pm-row click';
        row.innerHTML = '<div class="pm-ico">' + svg('car') + '</div>' +
          '<div class="pm-row-main"><div class="pm-row-title">' + escapeHtml(v.label) + '</div>' +
          '<div class="pm-row-sub">' + escapeHtml(v.model) + '</div></div>';
        row.addEventListener('click', function () { nui('fleetAdd', { model: v.model, label: v.label }); });
        list.appendChild(row);
      });
      if (arr.length > 150) {
        var more = document.createElement('div'); more.className = 'pm-empty';
        more.textContent = '+ ' + (arr.length - 150) + ' more - keep typing to narrow'; list.appendChild(more);
      }
    }
    draw(all);
    search.oninput = function () {
      var q = search.value.trim().toLowerCase();
      draw(!q ? all : all.filter(function (v) {
        return v.label.toLowerCase().indexOf(q) !== -1 || v.model.toLowerCase().indexOf(q) !== -1;
      }));
    };
  }

  function renderEditor(d) {
    view = 'editor';
    editorCar = d.car || {};
    editorMods = (d.car && d.car.mods) ? JSON.parse(JSON.stringify(d.car.mods)) : {};
    var m = editorMods;
    m.performance = m.performance || {}; m.colors = m.colors || {};
    m.wheels = m.wheels || {}; m.neon = m.neon || {}; m.xenon = m.xenon || {};

    setHeader('EDIT <span>MODS</span>', editorCar.label || '', 'wrench', true);
    el('pd-search-wrap').classList.add('hidden');
    (function () { var _s = el('pd-search'); if (_s) _s.oninput = null; })();
    el('pd-foot').innerHTML = '<b>Save</b> applies to everyone in your faction';
    var body = el('pd-body'); body.innerHTML = '';

    var s1 = secEl('Performance');
    s1.appendChild(fieldEl('Engine',       ctlSlider(0, 4, m.performance.engine || 0, function (v) { m.performance.engine = v; })));
    s1.appendChild(fieldEl('Brakes',       ctlSlider(0, 3, m.performance.brakes || 0, function (v) { m.performance.brakes = v; })));
    s1.appendChild(fieldEl('Transmission', ctlSlider(0, 3, m.performance.transmission || 0, function (v) { m.performance.transmission = v; })));
    s1.appendChild(fieldEl('Suspension',   ctlSlider(0, 4, m.performance.suspension || 0, function (v) { m.performance.suspension = v; })));
    s1.appendChild(fieldEl('Armor',        ctlSlider(0, 5, m.performance.armor || 0, function (v) { m.performance.armor = v; })));
    s1.appendChild(fieldEl('Turbo',        ctlToggle(m.performance.turbo, function (v) { m.performance.turbo = v; })));
    body.appendChild(s1);

    var s2 = secEl('Paint & Tint');
    s2.appendChild(fieldEl('Primary colour',   ctlColor(rgbHex(m.colors.primary), function (h) { m.colors.primary = hexRgb(h); })));
    s2.appendChild(fieldEl('Secondary colour', ctlColor(rgbHex(m.colors.secondary), function (h) { m.colors.secondary = hexRgb(h); })));
    s2.appendChild(fieldEl('Window tint',      ctlSelect(TINT_OPTS, String(m.tint || 0), function (v) { m.tint = parseInt(v, 10); })));
    body.appendChild(s2);

    var s3 = secEl('Wheels');
    s3.appendChild(fieldEl('Wheel type',   ctlSelect(WHEEL_TYPES, String(m.wheels.type != null ? m.wheels.type : 0), function (v) { m.wheels.type = parseInt(v, 10); })));
    s3.appendChild(fieldEl('Wheel design', ctlNumber(0, 60, m.wheels.design || 0, function (v) { m.wheels.design = v; })));
    body.appendChild(s3);

    var s4 = secEl('Neon');
    s4.appendChild(fieldEl('Left',  ctlToggle(m.neon.left,  function (v) { m.neon.left = v; })));
    s4.appendChild(fieldEl('Right', ctlToggle(m.neon.right, function (v) { m.neon.right = v; })));
    s4.appendChild(fieldEl('Front', ctlToggle(m.neon.front, function (v) { m.neon.front = v; })));
    s4.appendChild(fieldEl('Back',  ctlToggle(m.neon.back,  function (v) { m.neon.back = v; })));
    s4.appendChild(fieldEl('Neon colour', ctlColor(rgbHex(m.neon.color), function (h) { m.neon.color = hexRgb(h); })));
    body.appendChild(s4);

    var s5 = secEl('Lights & Extras');
    s5.appendChild(fieldEl('Xenon headlights', ctlToggle(m.xenon.on, function (v) { m.xenon.on = v; })));
    s5.appendChild(fieldEl('Xenon colour',     ctlSelect(XENON_OPTS, String(m.xenon.color != null ? m.xenon.color : -1), function (v) { m.xenon.color = parseInt(v, 10); })));
    s5.appendChild(fieldEl('Livery',           ctlNumber(0, 20, m.livery || 0, function (v) { m.livery = v; })));
    s5.appendChild(fieldEl('Extras (e.g. 1,2)', ctlText(extrasToStr(m.extras), function (v) { m.extras = strToExtras(v); })));
    body.appendChild(s5);

    var save = document.createElement('div'); save.className = 'pm-btn';
    save.style.marginTop = '18px'; save.style.marginBottom = '6px';
    save.innerHTML = svg('check') + 'Save Preset';
    save.addEventListener('click', function () {
      nui('fleetSetMods', { id: editorCar.id, mods: editorMods }).then(function () { nui('reqManage'); });
    });
    body.appendChild(save);
  }

  // ---------- Armory management views (chief) ----------

  function renderArmoryManager(d) {
    view = 'armoryManage';
    setHeader('ARMORY <span>MANAGER</span>', d.faction ? d.faction.toUpperCase() : '', 'armor', true);
    el('pd-search-wrap').classList.add('hidden');
    (function () { var _s = el('pd-search'); if (_s) _s.oninput = null; })();
    el('pd-foot').innerHTML = '<b>Grade 0</b> = any officer &nbsp;&middot;&nbsp; changes save instantly';
    var body = el('pd-body'); body.innerHTML = '';

    var items = Array.isArray(d.items) ? d.items : [];
    // Add Item always available now (chiefs can stock ANY ox_inventory item).
    var add = document.createElement('div'); add.className = 'pm-btn';
    add.innerHTML = svg('plus') + 'Add Item';
    add.addEventListener('click', function () { nui('armoryPickerOpen'); });
    body.appendChild(add);

    var list = document.createElement('div'); list.className = 'pm-list';
    if (!items.length) {
      var e0 = document.createElement('div'); e0.className = 'pm-empty';
      e0.textContent = 'No items in the armory'; list.appendChild(e0);
    }
    items.forEach(function (it) {
      var row = document.createElement('div'); row.className = 'pm-row';
      var gradeInp = ctlNumber(0, 10, it.grade || 0, function (v) {
        nui('armorySetGrade', { id: it.id, grade: v });
      });
      gradeInp.style.width = '42px'; gradeInp.style.padding = '4px 6px';
      var countInp = ctlNumber(1, 100, it.count || 1, function (v) {
        nui('armorySetCount', { id: it.id, count: v });
      });
      countInp.style.width = '46px'; countInp.style.padding = '4px 6px';
      row.innerHTML =
        '<div class="pm-ico">' + svg(it.icon || 'item') + '</div>' +
        '<div class="pm-row-main"><div class="pm-row-title">' + escapeHtml(it.label) + '</div>' +
          '<div class="pm-row-sub">' + escapeHtml(it.item) + '</div></div>' +
        '<div class="pm-row-acts"></div>';
      var acts = row.querySelector('.pm-row-acts');
      function labelled(text, inp) {
        var w = document.createElement('div');
        w.style.cssText = 'display:flex;align-items:center;gap:4px;margin-right:4px';
        var l = document.createElement('span');
        l.textContent = text; l.style.cssText = 'font-size:11px;opacity:0.6';
        w.appendChild(l); w.appendChild(inp); return w;
      }
      acts.appendChild(labelled('x', countInp));
      acts.appendChild(labelled('G:', gradeInp));
      var del = document.createElement('div'); del.className = 'pm-iconbtn danger'; del.title = 'Remove';
      del.innerHTML = svg('trash');
      del.addEventListener('click', function () { nui('armoryRemove', { id: it.id }); });
      acts.appendChild(del);
      list.appendChild(row);
    });
    body.appendChild(list);
  }

  function renderArmoryPicker(d) {
    view = 'armoryPicker';
    var all = Array.isArray(d.catalog) ? d.catalog : [];
    setHeader('ADD <span>ITEM</span>', 'All items', 'armor', true);
    var wrap = el('pd-search-wrap'); wrap.classList.remove('hidden');
    var search = el('pd-search'); search.value = ''; search.placeholder = 'Search ' + all.length + ' items...';
    el('pd-foot').innerHTML = '<b>Click</b> an item to add it to the armory';
    var body = el('pd-body'); body.innerHTML = '';
    var list = document.createElement('div'); list.className = 'pm-list'; body.appendChild(list);

    function draw(arr) {
      list.innerHTML = '';
      if (!arr.length) {
        var e = document.createElement('div'); e.className = 'pm-empty';
        e.textContent = all.length ? 'No matches' : 'No items available';
        list.appendChild(e); return;
      }
      arr.slice(0, 150).forEach(function (it) {
        var row = document.createElement('div'); row.className = 'pm-row click';
        row.innerHTML = '<div class="pm-ico">' + svg(it.icon || 'item') + '</div>' +
          '<div class="pm-row-main"><div class="pm-row-title">' + escapeHtml(it.label) + '</div>' +
          '<div class="pm-row-sub">' + escapeHtml(it.item) + '</div></div>';
        row.addEventListener('click', function () { nui('armoryAdd', { item: it.item }); });
        list.appendChild(row);
      });
      if (arr.length > 150) {
        var more = document.createElement('div'); more.className = 'pm-empty';
        more.textContent = '+ ' + (arr.length - 150) + ' more - keep typing to narrow'; list.appendChild(more);
      }
    }
    draw(all);
    search.oninput = function () {
      var q = search.value.trim().toLowerCase();
      draw(!q ? all : all.filter(function (it) {
        return it.label.toLowerCase().indexOf(q) !== -1 || it.item.toLowerCase().indexOf(q) !== -1;
      }));
    };
  }

  // ---------- Wardrobe management view (chief) ----------

  function renderWardrobeManager(d) {
    view = 'wardrobeManage';
    // Ensure the panel is visible + interactive (it may have been hidden for the
    // clothing editor via 'hideForEditor'); without this the chief would be locked out.
    el('pd-menu').classList.remove('hidden'); open = true;
    setHeader('WARDROBE <span>MANAGER</span>', d.faction ? d.faction.toUpperCase() : '', 'shirt', true);
    el('pd-search-wrap').classList.add('hidden');
    (function () { var _s = el('pd-search'); if (_s) _s.oninput = null; })();
    el('pd-foot').innerHTML = '<b>Customize</b> (live preview) or <b>save</b> your current outfit &nbsp;&middot;&nbsp; <b>toggle</b> / <b>grade</b> / <b>remove</b>';
    var body = el('pd-body'); body.innerHTML = '';

    var items = Array.isArray(d.items) ? d.items : [];

    // Create row: name + two save modes (open the editor, or capture what you wear now).
    var addWrap = document.createElement('div');
    addWrap.style.cssText = 'display:flex;gap:8px;align-items:center;margin-bottom:8px;flex-wrap:wrap';
    var nameInp = document.createElement('input');
    nameInp.type = 'text'; nameInp.placeholder = 'Outfit name'; nameInp.maxLength = 40;
    nameInp.style.cssText = 'flex:1;min-width:120px;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.12);border-radius:8px;color:#fff;padding:8px 10px;font-size:13px;outline:none';
    function outfitName() { return (nameInp.value || '').trim() || 'Outfit'; }
    var custBtn = document.createElement('div'); custBtn.className = 'pm-btn';
    custBtn.style.marginBottom = '0'; custBtn.style.whiteSpace = 'nowrap';
    custBtn.innerHTML = svg('shirt') + 'Customize &amp; Save';
    custBtn.addEventListener('click', function () { nui('wardrobeCustomize', { name: outfitName() }); });
    var saveBtn = document.createElement('div'); saveBtn.className = 'pm-btn';
    saveBtn.style.marginBottom = '0'; saveBtn.style.whiteSpace = 'nowrap';
    saveBtn.innerHTML = svg('plus') + 'Save Current';
    saveBtn.addEventListener('click', function () { nui('wardrobeAddCurrent', { name: outfitName() }); });
    addWrap.appendChild(nameInp); addWrap.appendChild(custBtn); addWrap.appendChild(saveBtn);
    body.appendChild(addWrap);

    // Search box to filter the preset list.
    var searchInp = document.createElement('input');
    searchInp.type = 'text'; searchInp.placeholder = 'Search presets...';
    searchInp.style.cssText = 'width:100%;background:rgba(255,255,255,0.06);border:1px solid rgba(255,255,255,0.12);border-radius:8px;color:#fff;padding:8px 10px;font-size:13px;outline:none;margin-bottom:10px';
    body.appendChild(searchInp);

    var list = document.createElement('div'); list.className = 'pm-list';
    body.appendChild(list);

    function rowFor(it) {
      var row = document.createElement('div'); row.className = 'pm-row';
      var tog = ctlToggle(it.enabled, function (v) { nui('wardrobeToggle', { id: it.id, enabled: v }); });
      var gradeInp = ctlNumber(0, 10, it.grade || 0, function (v) { nui('wardrobeSetGrade', { id: it.id, grade: v }); });
      gradeInp.style.width = '42px'; gradeInp.style.padding = '4px 6px';
      row.innerHTML =
        '<div class="pm-ico">' + svg(it.icon || 'shirt') + '</div>' +
        '<div class="pm-row-main"><div class="pm-row-title">' + escapeHtml(it.name || it.preset) + '</div>' +
          (it.meta ? '<div class="pm-row-sub">' + escapeHtml(it.meta) + '</div>' : '') + '</div>' +
        '<div class="pm-row-acts"></div>';
      var acts = row.querySelector('.pm-row-acts');
      var gw = document.createElement('div');
      gw.style.cssText = 'display:flex;align-items:center;gap:4px;margin-right:4px';
      var gl = document.createElement('span');
      gl.textContent = 'G:'; gl.style.cssText = 'font-size:11px;opacity:0.6';
      gw.appendChild(gl); gw.appendChild(gradeInp); acts.appendChild(gw);
      acts.appendChild(tog);
      var wdel = document.createElement('div'); wdel.className = 'pm-iconbtn danger';
      wdel.title = 'Remove'; wdel.style.marginLeft = '6px';
      wdel.innerHTML = svg('trash');
      wdel.addEventListener('click', function () { nui('wardrobeRemove', { id: it.id }); });
      acts.appendChild(wdel);
      return row;
    }

    function draw(arr) {
      list.innerHTML = '';
      if (!arr.length) {
        var e0 = document.createElement('div'); e0.className = 'pm-empty';
        e0.textContent = items.length ? 'No matches' : 'No wardrobe presets'; list.appendChild(e0); return;
      }
      arr.forEach(function (it) { list.appendChild(rowFor(it)); });
    }
    draw(items);
    searchInp.addEventListener('input', function () {
      var q = searchInp.value.trim().toLowerCase();
      draw(!q ? items : items.filter(function (it) {
        return (it.name || it.preset || '').toLowerCase().indexOf(q) !== -1;
      }));
    });
  }

  window.addEventListener('message', function (e) {
    var d = e.data || {};
    if (d.action === 'openPdMenu') render(d);
    else if (d.action === 'closePdMenu') hide();
    // Visually hide the panel for an external editor (illenium) WITHOUT firing
    // pdMenuClose (which would yank NUI focus from that editor). Focus is managed
    // by the caller; renderWardrobeManager re-shows the panel on return.
    else if (d.action === 'hideForEditor') { open = false; el('pd-menu').classList.add('hidden'); }
    else if (d.action === 'fleetManage') renderManager(d);
    else if (d.action === 'fleetPicker') renderPicker(d);
    else if (d.action === 'fleetEditor') renderEditor(d);
    else if (d.action === 'armoryManage') renderArmoryManager(d);
    else if (d.action === 'armoryPicker') renderArmoryPicker(d);
    else if (d.action === 'wardrobeManage') renderWardrobeManager(d);
  });

  // Back arrow dispatch by current view.
  function goBack() {
    if (view === 'armoryPicker') nui('reqArmoryManage');
    else if (view === 'armoryManage') nui('reqArmory');
    else if (view === 'wardrobeManage') nui('reqWardrobe');
    else if (view === 'picker' || view === 'editor') nui('reqManage');
    else if (view === 'manage') nui('reqGarage');
    else hide();
  }

  // pdmenu.js loads before the inline keybinds script, so this listener fires
  // first; stopImmediatePropagation keeps Esc from also hitting that handler.
  document.addEventListener('keydown', function (e) {
    if (open && (e.key === 'Escape')) {
      e.preventDefault();
      e.stopImmediatePropagation();
      hide();
    }
  });

  document.addEventListener('DOMContentLoaded', function () {
    var close = el('pd-close');
    if (close) close.addEventListener('click', hide);
    var back = el('pd-back');
    if (back) back.addEventListener('click', goBack);
    var menu = el('pd-menu');
    if (menu) menu.addEventListener('click', function (e) { if (e.target === menu) hide(); });
  });
})();
