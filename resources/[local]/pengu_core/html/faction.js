// PenguRP - faction management NUI (/faction). Renders the getData snapshot from the server into
// a Members tab (roster + invite/promote/demote/fire) and a Ranks tab (rename + permissions), gated
// by the viewer's permissions. Actions POST to client/factions.lua which relays to the server.
(function () {
  'use strict';

  function nui(cb, body) {
    return fetch('https://pengu_core/' + cb, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    });
  }
  function act(kind, extra) { nui('factionAction', Object.assign({ kind: kind }, extra || {})); }

  const menu    = document.getElementById('faction-menu');
  const elTitle = document.getElementById('fac-title');
  const elSub   = document.getElementById('fac-sub');
  const elTabs  = document.getElementById('fac-tabs');
  const elBody  = document.getElementById('fac-body');

  let data = null;
  let tab  = 'members';
  const PERM_META = {
    members: { name: 'Manage members', desc: 'Invite, fire, promote & demote' },
    ranks:   { name: 'Manage ranks',   desc: 'Rename ranks & set permissions' },
    loadout: { name: 'Manage loadout', desc: 'Armory, fleet & wardrobe access' },
  };

  function el(tag, cls, txt) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }

  // Server-mirrored: need 'members' perm, target below my rank (or I'm boss), not myself.
  function canManage(m) {
    if (!data.myPerms.members || m.isSelf) return false;
    return data.isBoss || m.level < data.myLevel;
  }

  function renderMembers() {
    elBody.innerHTML = '';
    if (data.myPerms.members) {
      const box = el('div', 'fac-invite');
      const input = el('input', 'rank-name');
      input.type = 'text';
      input.placeholder = 'Player name or server ID';
      input.maxLength = 48;
      const send = el('div', 'fac-wide', 'Invite');
      send.style.margin = '0';
      function submit() {
        const v = input.value.trim();
        if (!v) return;
        act('invite', { value: v });
        input.value = '';
      }
      send.addEventListener('click', submit);
      input.addEventListener('keydown', function (e) { if (e.key === 'Enter') submit(); });
      box.appendChild(input);
      box.appendChild(send);
      elBody.appendChild(box);
    }
    const members = data.members || [];
    if (!members.length) { elBody.appendChild(el('div', 'fac-empty', 'No members online.')); return; }
    members.forEach(function (m) {
      const row = el('div', 'fac-row' + (m.isSelf ? ' me' : ''));
      const who = el('div', 'who');
      who.appendChild(el('div', 'nm', m.name + (m.isboss ? '  ★' : '')));
      if (m.isSelf) who.appendChild(el('div', 'rk', 'You'));
      row.appendChild(who);
      row.appendChild(el('div', 'rank-badge', m.label || m.rank));
      if (canManage(m)) {
        const acts = el('div', 'fac-acts');
        const up = el('div', 'fac-btn labeled' + (m.level >= data.maxGrade ? ' disabled' : ''));
        up.title = 'Promote to next rank';
        up.innerHTML = '<span class="fac-btn-ic">&#8593;</span> Promote';
        up.addEventListener('click', function () { act('promote', { src: m.src }); });
        const dn = el('div', 'fac-btn labeled' + (m.level <= 0 ? ' disabled' : ''));
        dn.title = 'Demote to previous rank';
        dn.innerHTML = '<span class="fac-btn-ic">&#8595;</span> Demote';
        dn.addEventListener('click', function () { act('demote', { src: m.src }); });
        const fire = el('div', 'fac-btn labeled danger');
        fire.title = 'Remove from faction';
        fire.innerHTML = '<span class="fac-btn-ic">&#10005;</span> Remove';
        fire.addEventListener('click', function () { act('fire', { src: m.src }); });
        acts.appendChild(up); acts.appendChild(dn); acts.appendChild(fire);
        row.appendChild(acts);
      }
      elBody.appendChild(row);
    });
  }

  function renderRankCard(r) {
    const isLowest = r.level === 0;
    const card = el('div', 'fac-rank-card' + (r.isBoss ? ' leader' : '') + (isLowest ? ' entry' : ''));

    const head = el('div', 'rc-head');
    const gradeLabel = r.isBoss ? 'Grade ' + r.level + ' — Highest'
                     : isLowest ? 'Grade ' + r.level + ' — Entry'
                     : 'Grade ' + r.level;
    head.appendChild(el('div', 'rc-grade', gradeLabel));
    const name = el('input', 'rc-name');
    name.type = 'text'; name.value = r.label; name.maxLength = 32; name.spellcheck = false;
    name.placeholder = 'Rank name';
    head.appendChild(name);
    if (r.isBoss) head.appendChild(el('div', 'rc-leader-tag', 'Leader'));
    card.appendChild(head);

    const permsBox = el('div', 'rc-perms');
    const switches = {};
    (data.permKeys || []).forEach(function (k) {
      const on   = r.isBoss || !!r.perms[k];
      const meta = PERM_META[k] || { name: k, desc: '' };
      const tog  = el('div', 'rc-toggle' + (on ? ' on' : '') + (r.isBoss ? ' locked' : ''));
      const info = el('div', 'rc-toggle-info');
      info.appendChild(el('div', 'rc-toggle-name', meta.name));
      info.appendChild(el('div', 'rc-toggle-desc', meta.desc));
      tog.appendChild(info);
      const sw = el('div', 'rc-switch'); sw.appendChild(el('div', 'rc-knob'));
      tog.appendChild(sw);
      if (!r.isBoss) tog.addEventListener('click', function () { tog.classList.toggle('on'); markDirty(); });
      switches[k] = tog;
      permsBox.appendChild(tog);
    });
    card.appendChild(permsBox);

    const foot = el('div', 'rc-foot');
    foot.appendChild(el('div', r.isBoss ? 'rc-leader-note' : 'rc-spacer',
      r.isBoss ? 'Full control - permissions locked' : null));
    const save = el('button', 'rc-save', 'Save');
    save.type = 'button'; save.disabled = true;
    foot.appendChild(save);
    card.appendChild(foot);

    function isDirty() {
      if (name.value !== r.label) return true;
      if (r.isBoss) return false;
      return (data.permKeys || []).some(function (k) {
        return switches[k].classList.contains('on') !== !!r.perms[k];
      });
    }
    function markDirty() {
      const d = isDirty();
      save.disabled = !d;
      save.classList.remove('saved');
      save.classList.toggle('dirty', d);
      if (d) save.textContent = 'Save';
    }
    name.addEventListener('input', markDirty);

    save.addEventListener('click', function () {
      if (save.disabled) return;
      act('rankLabel', { grade: r.level, label: name.value });
      if (!r.isBoss) {
        const granted = (data.permKeys || []).filter(function (k) { return switches[k].classList.contains('on'); });
        act('rankPerms', { grade: r.level, perms: granted });
      }
      save.disabled = true;
      save.classList.remove('dirty');
      save.classList.add('saved');
      save.textContent = 'Saved ✓';
    });

    return card;
  }

  function renderRanks() {
    elBody.innerHTML = '';
    if (!data.myPerms.ranks) {
      elBody.appendChild(el('div', 'fac-empty', 'You do not have permission to manage ranks.'));
      return;
    }
    elBody.appendChild(el('div', 'fac-hint',
      'Ranks are listed highest to lowest. Rename each rank, then toggle which actions it can perform. The top rank (Leader) always has full control.'));
    const ranks = (data.ranks || []).slice().sort(function (a, b) { return b.level - a.level; });
    ranks.forEach(function (r) { elBody.appendChild(renderRankCard(r)); });
  }

  function renderTabs() {
    elTabs.innerHTML = '';
    const tabs = [{ id: 'members', label: 'Members' }];
    if (data.myPerms.ranks) tabs.push({ id: 'ranks', label: 'Ranks' });
    tabs.forEach(function (t) {
      const b = el('div', 'fac-tab' + (tab === t.id ? ' active' : ''), t.label);
      b.addEventListener('click', function () { tab = t.id; render(); });
      elTabs.appendChild(b);
    });
  }

  function render() {
    if (!data) return;
    elTitle.innerHTML = (data.label || 'Faction') + ' <span>Faction</span>';
    const myRank = ((data.ranks || []).find(function (r) { return r.level === data.myLevel; }) || {}).label || '';
    elSub.textContent = 'You: ' + myRank + (data.isBoss ? '  (Leader)' : '');
    if (tab === 'ranks' && !data.myPerms.ranks) tab = 'members';
    renderTabs();
    if (tab === 'ranks') renderRanks(); else renderMembers();
  }

  function close() { menu.classList.add('hidden'); }

  window.addEventListener('message', function (e) {
    const m = e.data || {};
    if (m.action === 'factionOpen') { data = m.data; tab = 'members'; menu.classList.remove('hidden'); render(); }
    else if (m.action === 'factionData') { if (m.data) { data = m.data; render(); } }
    else if (m.action === 'factionClose') { close(); }
  });

  document.getElementById('fac-close').addEventListener('click', function () { nui('factionClose'); close(); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !menu.classList.contains('hidden')) { nui('factionClose'); close(); }
  });
})();
