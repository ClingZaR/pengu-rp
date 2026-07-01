// PenguRP - in-house clothing designer NUI (chief). Named categories with Prev/Next
// arrows for item + colour, a live "5 / 120" position readout per row, and a live ped
// preview (the client applies each change). Receives clothOpen/clothUpdate/clothClose.
(function () {
  'use strict';

  function nui(path, body) {
    return fetch('https://pengu_core/' + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    });
  }

  const editor = document.getElementById('cloth-editor');
  const rowsEl = document.getElementById('cloth-rows');
  const nameInput = document.getElementById('cloth-name');

  // key -> { item: <span>, color: <span> } counter elements, for live updates.
  const counters = {};

  // info = { isProp, item, itemMax, color, colorMax }. item: comp 0..max-1 / prop -1(none)..max-1.
  function fmtItem(info) {
    if (!info) return '-';
    if (info.isProp && info.item < 0) return 'Off';
    if (!info.itemMax || info.itemMax <= 0) return '-';
    return (info.item + 1) + ' / ' + info.itemMax;
  }
  function fmtColor(info) {
    if (!info || !info.colorMax || info.colorMax <= 0) return '-';
    return (info.color + 1) + ' / ' + info.colorMax;
  }

  function arrowGroup(key, target) {
    const wrap = document.createElement('div');
    wrap.className = 'cloth-arrows';
    const prev = document.createElement('button');
    prev.className = 'cloth-arrow';
    prev.innerHTML = '&#9664;';
    prev.addEventListener('click', function () { nui('clothChange', { key: key, target: target, dir: -1 }); });
    const count = document.createElement('span');
    count.className = 'cloth-count';
    count.textContent = '-';
    const next = document.createElement('button');
    next.className = 'cloth-arrow';
    next.innerHTML = '&#9654;';
    next.addEventListener('click', function () { nui('clothChange', { key: key, target: target, dir: 1 }); });
    wrap.appendChild(prev);
    wrap.appendChild(count);
    wrap.appendChild(next);
    return { wrap: wrap, count: count };
  }

  function group(labelText, key, target) {
    const g = document.createElement('div');
    g.className = 'cloth-group';
    const l = document.createElement('span');
    l.className = 'cloth-group-lbl';
    l.textContent = labelText;
    const ag = arrowGroup(key, target);
    g.appendChild(l);
    g.appendChild(ag.wrap);
    return { el: g, count: ag.count };
  }

  function setCounts(key, info) {
    const c = counters[key];
    if (!c) return;
    if (c.item) c.item.textContent = fmtItem(info);
    if (c.color) c.color.textContent = fmtColor(info);
  }

  function buildRows(cats) {
    rowsEl.innerHTML = '';
    for (const k in counters) delete counters[k];
    (cats || []).forEach(function (c) {
      const row = document.createElement('div');
      row.className = 'cloth-row';
      const label = document.createElement('div');
      label.className = 'cloth-label';
      label.textContent = c.label;
      const controls = document.createElement('div');
      controls.className = 'cloth-controls';
      const itemG = group('Item', c.key, 'item');
      const colorG = group('Color', c.key, 'color');
      controls.appendChild(itemG.el);
      controls.appendChild(colorG.el);
      row.appendChild(label);
      row.appendChild(controls);
      rowsEl.appendChild(row);
      counters[c.key] = { item: itemG.count, color: colorG.count };
      setCounts(c.key, c.info);
    });
  }

  window.addEventListener('message', function (e) {
    const d = e.data || {};
    if (d.action === 'clothOpen') {
      buildRows(d.cats);
      if (nameInput) nameInput.value = d.name || '';
      editor.classList.remove('hidden');
    } else if (d.action === 'clothUpdate') {
      if (d.info && d.info.key) setCounts(d.info.key, d.info);
    } else if (d.action === 'clothClose') {
      editor.classList.add('hidden');
    }
  });

  const bind = function (id, fn) {
    const el = document.getElementById(id);
    if (el) el.addEventListener('click', fn);
  };
  bind('cloth-rot-l', function () { nui('clothRotate', { dir: -1 }); });
  bind('cloth-rot-r', function () { nui('clothRotate', { dir: 1 }); });
  bind('cloth-save', function () { nui('clothSave', { name: (nameInput.value || '').trim() || 'Outfit' }); });
  bind('cloth-cancel', function () { nui('clothCancel', {}); });

  // Keyboard fallback: Esc cancels the designer (no save).
  document.addEventListener('keydown', function (e) {
    if (!editor || editor.classList.contains('hidden')) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      nui('clothCancel', {});
    }
  });
})();
