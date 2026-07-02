/* ============================================================
   pengu_mdt - NUI logic (REDESIGN2)
   Talks to the client relay via fetch(https://pengu_mdt/<cb>).

   Server callbacks (role-gated server-side, by NAME only - NO citizen IDs):
     getDashboard {}                         -> { units:[{callsign, members:[name], unassigned?}] }
     searchPerson {name}                     -> { found,name,mugshot,phone,totals,outstanding[],history[],prints,wanted:{level,reason} }
     searchVehicle {plate}                   -> { found,owner,model,plate,vin,phone }
     getPenalCode {}                         -> { charges, modifiers }
     placeCharges {name,items[{code,modifiers[]}]} -> { success, message }
     setWanted {name,level,reason}           -> { success, message, wanted:{level,reason} }  (LEO only)
     getBolos {}                             -> { items[] }
     createBolo {type,title,description,images[]} / cancelBolo {id}
     getWarrants {}                          -> { items:[{name,charges,months,fine,wanted}] }
     getCameras {}                           -> { feeds:[{id,label}] }
     getBodycam {}                           -> { items:[{id,officer,captured_at,image}] }
     searchMedical {name}                    -> { found,name,items:[{action,detail,medic,created_at}] }  (EMS only)
     getRecentMedical {}                     -> { items:[{patient,action,detail,medic,created_at}] }     (EMS only)
   Client-only callbacks:
     closeMdt, viewCamera {id}, exitCamera {},
     toggleBodycam {} -> {on}  (real captures: the client snaps a frame via
     screenshot-basic on toggle + every 60s, we downscale it here and hand it
     back via bodycamProcessed)
   Messages: {action:'open', role:'leo'|'court'|'ems'} {action:'close'}
   Roles: 'court' (judge/lawyer) is read-only - the Arrest Calculator and
   Units tabs, BOLO create form and every action button are hidden (CSS
   .role-court .leo-only). 'ems' (on-duty ambulance) sees ONLY the Medical
   tab (CSS .role-ems hides every other rail tab; .ems-only hides Medical
   from leo/court - medical privacy). The server enforces the same role on
   every callback, so hiding here is presentation only.
   ============================================================ */
(function () {
  'use strict';

  const RESOURCE =
    (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'pengu_mdt';

  // ------------------------------------------------------------------
  // State
  // ------------------------------------------------------------------
  const state = {
    penal: { charges: [], modifiers: [] },
    chargeByCode: {},
    modByIdMap: {},
    cart: [],                 // [{code,title,class,months,fine,blockedModifiers,mods:[id]}]
    target: null,             // { name }  (carried from Person Search - NO cid)
    activeCam: null,          // { id, label }
    feeds: [],                // [{id,label}] from loadCameras (for prev/next)
    bodycam: false,
    role: 'leo',              // 'leo' | 'court' (read-only) | 'ems' (Medical tab only)
    loadingPenal: false,
    loaded: { dashboard: false, bolos: false, warrants: false, cameras: false, bodycam: false },
    lightbox: { images: [], index: 0 }    // images of the BOLO currently in the viewer
  };

  // ------------------------------------------------------------------
  // Icons (inner SVG paths) for JS-rendered empty states
  // ------------------------------------------------------------------
  const ICON = {
    units:  '<circle cx="9" cy="8" r="3.2"/><path d="M3 19c0-3.2 2.7-5.4 6-5.4"/><path d="M15 13.8c2.6.5 4.5 2.6 4.5 5.2"/><path d="M16 5.6a3 3 0 0 1 0 5.4"/>',
    eye:    '<path d="M2 12s3.5-6.5 10-6.5S22 12 22 12s-3.5 6.5-10 6.5S2 12 2 12z"/><circle cx="12" cy="12" r="2.8"/>',
    shield: '<path d="M12 3l7 3v5c0 4.5-3 7.8-7 9-4-1.2-7-4.5-7-9V6l7-3z"/><path d="M9.5 12l1.8 1.8L15 10"/>',
    file:   '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/>',
    camera: '<rect x="3" y="7" width="12" height="10" rx="2"/><path d="M15 10l6-3v10l-6-3z"/>',
    image:  '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9.5" r="1.6"/><path d="M5 17l4.5-4.5 3 3L16 11l3 3"/>'
  };

  // ------------------------------------------------------------------
  // DOM helpers
  // ------------------------------------------------------------------
  const $  = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const app = $('#app');

  const escapeHtml = (s) =>
    String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const money = (n) => '$' + (Number(n) || 0).toLocaleString('en-US');

  const fmtDate = (s) => (!s ? '-' : String(s).replace('T', ' ').slice(0, 16));

  function emptyHTML(iconInner, title, sub) {
    return `<div class="empty-state">` +
      `<svg class="ic empty-ic" viewBox="0 0 24 24" width="40" height="40">${iconInner}</svg>` +
      `<p class="empty-title">${escapeHtml(title)}</p>` +
      (sub ? `<p class="empty-sub">${escapeHtml(sub)}</p>` : '') +
      `</div>`;
  }

  function spinnerHTML(label) {
    return `<div class="loading-box"><div class="spinner"></div><span>${escapeHtml(label || 'Loading...')}</span></div>`;
  }

  // shows a spinner into el only if work takes > 300ms (no flicker on fast calls)
  function delayedSpinner(el, label) {
    let done = false;
    const t = setTimeout(() => { if (!done && el) el.innerHTML = spinnerHTML(label); }, 300);
    return () => { done = true; clearTimeout(t); };
  }

  // class normaliser -> { key, label }
  function classMeta(cls) {
    const c = String(cls || '').toLowerCase();
    if (c.indexOf('fel') >= 0) return { key: 'felony', label: 'Felony' };
    if (c.indexOf('mis') >= 0) return { key: 'misdemeanor', label: 'Misd.' };
    if (c.indexOf('cit') >= 0) return { key: 'citation', label: 'Citation' };
    if (!c) return { key: 'other', label: '-' };
    return { key: 'other', label: cls.charAt(0).toUpperCase() + cls.slice(1) };
  }

  // base64 / url / data-uri -> usable <img> src
  function mugSrc(s) {
    if (!s) return '';
    const v = String(s);
    if (v.startsWith('data:') || v.startsWith('http')) return v;
    return 'data:image/png;base64,' + v;
  }

  // comma-joined modifier ids -> readable labels (falls back to raw)
  function modLabels(str) {
    if (!str) return '';
    return String(str).split(',').map((id) => {
      const m = state.modByIdMap[id.trim()];
      return m ? (m.label || id) : id;
    }).filter(Boolean).join(', ');
  }

  // ------------------------------------------------------------------
  // NUI fetch wrapper
  // ------------------------------------------------------------------
  async function nui(name, data = {}) {
    try {
      const res = await fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
      });
      if (!res.ok) return null;
      const txt = await res.text();
      if (!txt) return null;
      try { return JSON.parse(txt); } catch (_) { return txt; }
    } catch (err) {
      console.error('[pengu_mdt] nui error:', name, err);
      return null;
    }
  }

  function setBusy(sel, busy) {
    const el = $(sel);
    if (!el) return;
    el.classList.toggle('is-busy', !!busy);
    el.disabled = !!busy;
  }

  // ------------------------------------------------------------------
  // Toast
  // ------------------------------------------------------------------
  let toastTimer;
  function toast(msg, type = 'ok') {
    const t = $('#toast');
    t.textContent = msg;
    t.className = 'toast show ' + type;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.className = 'toast'; }, 3800);
  }

  // ------------------------------------------------------------------
  // Open / close
  // ------------------------------------------------------------------
  function openMdt(plate, role) {
    const newRole = (role === 'court' || role === 'ems') ? role : 'leo';
    if (state.role !== newRole) {
      // role changed since last open (job change) -> stale caches must reload
      state.loaded = { dashboard: false, bolos: false, warrants: false, cameras: false, bodycam: false };
    }
    state.role = newRole;
    app.classList.toggle('role-court', newRole === 'court');
    app.classList.toggle('role-ems', newRole === 'ems');
    app.classList.remove('hidden');
    if (newRole === 'ems') {
      showTab('medical');       // ems landing (and only) tab - no penal code needed
    } else {
      loadPenalCode();          // static; needed by calculator + modifier labels
      if (newRole === 'court') {
        showTab('person');      // court landing tab (Units is LEO-only)
      } else {
        // leo keeps its last tab across opens - unless the role just changed
        // away from ems and the ems-only Medical tab is still active
        const active = $('.tab-panel.active');
        if (active && active.dataset.tab === 'medical') showTab('dashboard');
        loadDashboard(true);    // landing tab
      }
    }
    if (plate) {                // radar HUD: jump to the vehicle tab + run the plate
      showTab('vehicle');
      const pi = document.querySelector('#vehicle-plate');
      if (pi) { pi.value = plate; }
      searchVehicle();
    }
  }
  function hideMdt() {
    app.classList.add('hidden');
    state.activeCam = null;     // client force-exits the cam on close
    exitCamMode();              // never reopen stuck in cam-mode
  }
  function closeMdt() {
    hideMdt();
    nui('closeMdt', {});
  }

  window.addEventListener('message', (e) => {
    const d = e.data || {};
    if (d.action === 'open') openMdt(d.plate, d.role);
    else if (d.action === 'close') hideMdt();
    else if (d.action === 'camFeed') {            // initial feed open OR arrow switch
      state.activeCam = { id: d.id, label: d.label };
      markActiveCam();
      setCamVision(d.vision || 'off');
    }
    else if (d.action === 'camVision') setCamVision(d.vision || 'off');
    else if (d.action === 'camExit') {            // client tore the cam down + restored focus
      state.activeCam = null;
      exitCamMode();
      markActiveCam();
    }
    else if (d.action === 'bookingViewfinder') {  // booking-camera overlay on/off
      const vf = $('#booking-viewfinder');
      if (vf) {
        if (d.on) { $('#vf-name').textContent = d.name || ''; vf.classList.remove('hidden'); }
        else vf.classList.add('hidden');
      }
    }
    else if (d.action === 'downscaleMugshot') {   // raw booking photo -> resize -> return small
      downscaleMugshot(d.src);
    }
    else if (d.action === 'downscaleBodycam') {   // raw bodycam frame -> resize -> return small
      downscaleImage(d.src, 'bodycamProcessed', 480, 0.7);
    }
    else if (d.action === 'bodycamState') {       // client force-stopped the cam (unload etc.)
      state.bodycam = !!d.on;
      updateBodycam();
    }
  });

  // Resize a raw screenshot data URI down to a small image and hand it back to
  // the client via the named NUI callback (which sends it to the server). Runs
  // entirely in our own NUI, so it never depends on screenshot-basic's page
  // being patched. Used by both booking mugshots and bodycam frames.
  function downscaleImage(src, cbName, maxW, quality) {
    const done = (small) => nui(cbName, { src: small || '' });
    if (!src) { done(''); return; }
    const im = new Image();
    im.onload = () => {
      try {
        const w = maxW || 512;
        const scale = Math.min(1, w / (im.width || w));
        const c = document.createElement('canvas');
        c.width = Math.max(1, Math.round((im.width || w) * scale));
        c.height = Math.max(1, Math.round((im.height || w) * scale));
        c.getContext('2d').drawImage(im, 0, 0, c.width, c.height);
        done(c.toDataURL('image/jpeg', quality || 0.82));
      } catch (e) { done(''); }
    };
    im.onerror = () => done('');
    im.src = src;
  }
  function downscaleMugshot(src) { downscaleImage(src, 'mugProcessed', 512, 0.82); }

  document.addEventListener('keydown', (e) => {
    if (app.classList.contains('hidden')) return;
    // F11 toggles the MDT shut from inside (the game keymapping cannot fire while the NUI is focused).
    if (e.key === 'F11') {
      e.preventDefault();
      closeMdt();
      return;
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      // The lightbox owns Esc first so it closes the image, not the MDT.
      if (isLightboxOpen()) { closeLightbox(); return; }
      // Esc closes the MDT. Cam-mode has no NUI focus, so this only fires with
      // the panel up; cam-mode exit is owned by the client Backspace key.
      closeMdt();
    }
  });

  // click the area OUTSIDE the panel closes the MDT. (Cam-mode has no cursor, so
  // this only fires with the panel up.)
  app.addEventListener('mousedown', (e) => {
    if (e.target !== app) return;
    closeMdt();
  });

  // ------------------------------------------------------------------
  // Tabs
  // ------------------------------------------------------------------
  // Tabs the court role can never land on (their rail buttons are hidden by
  // CSS; this guard also covers programmatic showTab calls).
  const COURT_BLOCKED_TABS = { dashboard: true, calculator: true };

  function showTab(tab) {
    if (state.role === 'ems') tab = 'medical';       // ems sees ONLY Medical
    else if (tab === 'medical') tab = 'person';      // Medical is ems-only (privacy)
    if (state.role === 'court' && COURT_BLOCKED_TABS[tab]) tab = 'person';
    $$('.rail-btn').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
    $$('.tab-panel').forEach((p) => p.classList.toggle('active', p.dataset.tab === tab));

    if (tab === 'dashboard' && !state.loaded.dashboard) loadDashboard();
    else if (tab === 'calculator') loadPenalCode();
    else if (tab === 'bolos' && !state.loaded.bolos) loadBolos();
    else if (tab === 'warrants') loadWarrants();   // auto-refresh every open
    else if (tab === 'medical') loadRecentMedical();  // auto-refresh every open
    else if (tab === 'cameras') {
      // live feeds are LEO-only (hidden + denied for court); the bodycam
      // archive loads for both roles
      if (state.role !== 'court' && !state.loaded.cameras) loadCameras();
      if (!state.loaded.bodycam) loadBodycam();
    }
  }

  // ------------------------------------------------------------------
  // Dashboard - Active Units
  // ------------------------------------------------------------------
  async function loadDashboard(silent) {
    const list = $('#dash-list');
    const stop = delayedSpinner(list, 'Loading units...');
    const data = await nui('getDashboard', {});
    stop();
    state.loaded.dashboard = true;
    const units = (data && Array.isArray(data.units)) ? data.units : [];
    if (!units.length) {
      list.innerHTML = emptyHTML(ICON.units, 'No units on duty', 'No LEO officers are currently clocked in.');
      return;
    }
    const frag = document.createDocumentFragment();
    units.forEach((u) => {
      const row = document.createElement('div');
      row.className = 'list-row';
      const members = Array.isArray(u.members) ? u.members : [];
      const title = u.unassigned ? 'Unassigned' : ('Unit ' + (u.callsign || '-'));
      const membersHtml = members.length ? members.map(escapeHtml).join(', ') : 'No members';
      const count = members.length + (members.length === 1 ? ' officer' : ' officers');
      row.innerHTML =
        `<span class="callsign">${escapeHtml(u.unassigned ? '-' : (u.callsign || '-'))}</span>` +
        `<div class="list-main">` +
          `<div class="list-top"><span class="list-title">${escapeHtml(title)}</span></div>` +
          `<div class="list-meta">${membersHtml}</div>` +
        `</div>` +
        `<span class="pill green"><span class="duty-dot"></span>${count}</span>`;
      frag.appendChild(row);
    });
    list.innerHTML = '';
    list.appendChild(frag);
    if (!silent) { /* no-op: refresh handled by caller */ }
  }

  // ------------------------------------------------------------------
  // Penal code
  // ------------------------------------------------------------------
  async function loadPenalCode() {
    if (state.loadingPenal || state.penal.charges.length) return;
    state.loadingPenal = true;
    const data = await nui('getPenalCode', {});
    state.loadingPenal = false;
    if (data && Array.isArray(data.charges)) {
      state.penal.charges = data.charges;
      state.penal.modifiers = Array.isArray(data.modifiers) ? data.modifiers : [];
      indexPenal();
    }
    renderAvailable();
  }

  function indexPenal() {
    state.chargeByCode = {};
    state.modByIdMap = {};
    state.penal.charges.forEach((c) => { if (c.code) state.chargeByCode[c.code] = c; });
    state.penal.modifiers.forEach((m) => { if (m.id) state.modByIdMap[m.id] = m; });
  }

  // ------------------------------------------------------------------
  // Vehicle search
  // ------------------------------------------------------------------
  async function searchVehicle() {
    const plate = $('#vehicle-plate').value.trim();
    if (!plate) { toast('Enter a plate to search.', 'warn'); return; }
    $('#veh-empty').classList.add('hidden');
    $('#veh-results').classList.add('hidden');
    setBusy('#veh-search-btn', true);
    const stop = searchLoading($('#veh-body'));
    const data = await nui('searchVehicle', { plate });
    stop();
    setBusy('#veh-search-btn', false);
    renderVehicle(data);
  }

  function renderVehicle(data) {
    const empty = $('#veh-empty');
    const results = $('#veh-results');
    if (!data || !data.found) {
      results.classList.add('hidden');
      empty.classList.remove('hidden');
      empty.innerHTML = data
        ? emptyHTML(ICON.image, 'No vehicle found', 'No registration matches that plate.')
        : emptyHTML(ICON.image, 'Search unavailable', 'Are you on duty as an officer?');
      return;
    }
    empty.classList.add('hidden');
    results.classList.remove('hidden');
    $('#veh-owner').textContent = data.owner || '-';
    $('#veh-model').textContent = data.model || '-';
    $('#veh-plate').textContent = data.plate || '-';
    $('#veh-vin').textContent = data.vin || '-';
    $('#veh-phone').textContent = data.phone || '-';
  }

  // ------------------------------------------------------------------
  // Person search
  // ------------------------------------------------------------------
  async function searchPerson() {
    const name = $('#person-name').value.trim();
    if (!name) { toast('Enter a name to search.', 'warn'); return; }
    $('#per-empty').classList.add('hidden');
    $('#per-results').classList.add('hidden');
    setBusy('#per-search-btn', true);
    const stop = searchLoading($('#per-body'));
    const data = await nui('searchPerson', { name });
    stop();
    setBusy('#per-search-btn', false);
    renderPerson(data);
  }

  function renderPerson(data) {
    const empty = $('#per-empty');
    const results = $('#per-results');
    if (!data || !data.found) {
      results.classList.add('hidden');
      empty.classList.remove('hidden');
      empty.innerHTML = data
        ? emptyHTML(ICON.units, 'No citizen found', 'No record matches that name.')
        : emptyHTML(ICON.units, 'Search unavailable', 'Are you on duty as an officer?');
      return;
    }
    empty.classList.add('hidden');
    results.classList.remove('hidden');

    $('#per-name').textContent = data.name || '-';
    $('#per-phone').textContent = data.phone || '-';

    // Fingerprints on file? Boolean only (no cid is ever sent); green = on file, red = not.
    const prints = $('#per-prints');
    if (prints) {
      if (data.prints) { prints.textContent = 'On File'; prints.className = 'prints-yes'; }
      else { prints.textContent = 'Not on File'; prints.className = 'prints-no'; }
    }

    // mugshot (reserved box; downscaled small at capture so it returns inline)
    const img = $('#per-mug');
    const ph = $('#per-mug-ph');
    const phText = ph.querySelector('span');
    const src = mugSrc(data.mugshot);
    if (src) {
      img.onerror = () => {
        img.classList.add('hidden'); ph.classList.remove('hidden');
        if (phText) phText.textContent = 'No photo on record';
      };
      img.src = src;
      img.classList.remove('hidden');
      ph.classList.add('hidden');
    } else {
      img.removeAttribute('src');
      img.classList.add('hidden');
      ph.classList.remove('hidden');
      if (phText) phText.textContent = 'No photo on record';
    }

    const t = data.totals || {};
    $('#per-total-charges').textContent = t.charges || 0;
    $('#per-total-citations').textContent = t.citations || 0;
    $('#per-total-imprisonments').textContent = t.imprisonments || 0;

    renderWanted(data.wanted);

    renderOutstanding(Array.isArray(data.outstanding) ? data.outstanding : []);
    renderHistory(Array.isArray(data.history) ? data.history : []);

    // carry the NAME as the arrest target (NO cid anywhere)
    state.target = { name: data.name };
    updateTargetChip();
  }

  // ------------------------------------------------------------------
  // Wanted level (0-5). Stars are inline SVG (no unicode chars anywhere).
  // LEO can set it (select + reason + Set -> setWanted); court is read-only
  // (.wanted-set carries .leo-only). The server re-checks the role.
  // ------------------------------------------------------------------
  const STAR_PATH = '<path d="M12 3.2l2.5 5.4 5.9.7-4.4 4 1.2 5.8-5.2-2.9-5.2 2.9 1.2-5.8-4.4-4 5.9-.7z"/>';

  function starsHTML(level, size) {
    let html = '';
    for (let i = 1; i <= 5; i++) {
      html += `<svg class="wanted-star${i <= level ? ' on' : ''}" viewBox="0 0 24 24" width="${size}" height="${size}" aria-hidden="true">${STAR_PATH}</svg>`;
    }
    return html;
  }

  function wantedLevelOf(w) {
    const n = Number(w && typeof w === 'object' ? w.level : w) || 0;
    return Math.max(0, Math.min(5, Math.floor(n)));
  }

  function renderWanted(w) {
    const bar = $('#per-wanted-bar');
    if (!bar) return;
    const level = wantedLevelOf(w);
    $('#per-wanted-stars').innerHTML = starsHTML(level, 15);
    const txt = $('#per-wanted-text');
    txt.textContent = level > 0 ? `WANTED ${level}/5` : 'NOT WANTED';
    txt.className = 'wanted-text' + (level >= 3 ? ' danger' : (level > 0 ? ' warn' : ''));
    bar.classList.toggle('is-high', level >= 3);
    const reason = (level > 0 && w && w.reason) ? String(w.reason) : '';
    const reasonEl = $('#per-wanted-reason');
    reasonEl.textContent = reason;
    reasonEl.title = reason;
    const sel = $('#wanted-level-sel');
    if (sel) sel.value = String(level);
  }

  async function setWantedFromUI() {
    if (!state.target || !state.target.name) { toast('Search a person first.', 'warn'); return; }
    const level = Number($('#wanted-level-sel').value) || 0;
    const reason = $('#wanted-reason-inp').value.trim();
    setBusy('#wanted-set-btn', true);
    const res = await nui('setWanted', { name: state.target.name, level, reason });
    setBusy('#wanted-set-btn', false);
    if (res && res.success) {
      toast(res.message || 'Wanted level updated.', 'ok');
      $('#wanted-reason-inp').value = '';
      renderWanted(res.wanted || { level, reason });
      state.loaded.warrants = false;   // warrant rows show stars - refetch on next open
    } else {
      toast((res && res.message) || 'Failed to set wanted level.', 'err');
    }
  }

  function renderOutstanding(rows) {
    const body = $('#per-outstanding-body');
    $('#per-out-count').textContent = String(rows.length);
    if (!rows.length) {
      body.innerHTML = `<tr class="empty-row"><td colspan="6">No outstanding charges.</td></tr>`;
      return;
    }
    const frag = document.createDocumentFragment();
    rows.forEach((r) => {
      const cm = classMeta(r.class);
      const mods = modLabels(r.modifiers);
      const tr = document.createElement('tr');
      tr.innerHTML =
        `<td class="mono">${escapeHtml(r.code || '-')}</td>` +
        `<td>${escapeHtml(r.title || '-')}</td>` +
        `<td><span class="badge ${cm.key}">${escapeHtml(cm.label)}</span></td>` +
        `<td class="num mono">${Number(r.months) || 0}</td>` +
        `<td class="num mono">${money(r.fine)}</td>` +
        `<td class="mods-cell">${mods ? escapeHtml(mods) : '-'}</td>`;
      frag.appendChild(tr);
    });
    body.innerHTML = '';
    body.appendChild(frag);
  }

  // Record History (rap sheet): PAST processed charges/citations, most-recent
  // first. Mirrors renderOutstanding; reuses classMeta + the .plea-badge mapping.
  // The plea per charge comes from its imprisonment case (N/A for citations).
  // NO citizen ids - name-only, like the rest of the tab.
  // Record History class filter (sticky across person searches).
  const HIST_FILTER = { felony: true, misdemeanor: true, citation: true };
  function histShown(key) { return (key in HIST_FILTER) ? HIST_FILTER[key] : true; } // 'other' always shown

  function applyHistoryFilter() {
    const body = $('#per-history-body');
    if (!body) return;
    const rows = body.querySelectorAll('tr.hist-row');
    let shown = 0;
    rows.forEach((tr) => {
      const on = histShown(tr.dataset.cls || 'other');
      tr.classList.toggle('hidden', !on);
      if (on) shown++;
    });
    const emptyTr = body.querySelector('.hist-empty');
    if (emptyTr) emptyTr.classList.toggle('hidden', shown > 0 || rows.length === 0);
    $('#per-history-count').textContent = rows.length ? (shown + ' / ' + rows.length) : '0';
  }

  function renderHistory(rows) {
    const body = $('#per-history-body');
    if (!rows.length) {
      body.innerHTML = `<tr class="empty-row"><td colspan="4">No record history.</td></tr>`;
      $('#per-history-count').textContent = '0';
      return;
    }
    const frag = document.createDocumentFragment();
    rows.forEach((r) => {
      const cm = classMeta(r.class);

      // plea: 'na' on citations (no plea applies) -> muted N/A; otherwise the plea-badge.
      const plea = String(r.plea || 'pending').toLowerCase();
      let pleaCell;
      if (plea === 'na') {
        pleaCell = `<span class="dim">N/A</span>`;
      } else {
        const pleaMeta = ({
          guilty:     { key: 'guilty',     label: 'Guilty' },
          not_guilty: { key: 'not_guilty', label: 'Not Guilty' },
          pending:    { key: 'pending',    label: 'Pending' }
        })[plea] || { key: 'pending', label: 'Pending' };
        pleaCell = `<span class="plea-badge ${pleaMeta.key}">${escapeHtml(pleaMeta.label.toUpperCase())}</span>`;
      }

      const tr = document.createElement('tr');
      tr.className = 'hist-row';
      tr.dataset.cls = cm.key;
      tr.innerHTML =
        `<td class="mono">${escapeHtml(r.code || '-')}</td>` +
        `<td>${escapeHtml(r.title || '-')}</td>` +
        `<td><span class="badge ${cm.key}">${escapeHtml(cm.label)}</span></td>` +
        `<td>${pleaCell}</td>`;
      frag.appendChild(tr);
    });
    const emptyTr = document.createElement('tr');
    emptyTr.className = 'empty-row hist-empty hidden';
    emptyTr.innerHTML = `<td colspan="4">No records match the selected filters.</td>`;
    frag.appendChild(emptyTr);
    body.innerHTML = '';
    body.appendChild(frag);
    applyHistoryFilter();
  }

  // search loading overlay (appended to a panel-body)
  function searchLoading(bodyEl) {
    let done = false, node = null;
    const t = setTimeout(() => {
      if (done || !bodyEl) return;
      node = document.createElement('div');
      node.className = 'loading-box';
      node.innerHTML = '<div class="spinner"></div><span>Searching...</span>';
      bodyEl.appendChild(node);
    }, 300);
    return () => { done = true; clearTimeout(t); if (node) node.remove(); };
  }

  // ------------------------------------------------------------------
  // Arrest calculator - available list
  // ------------------------------------------------------------------
  function renderAvailable() {
    const list = $('#available-list');
    if (!list) return;
    const q = $('#charge-search').value.trim().toLowerCase();

    if (!state.penal.charges.length) {
      list.innerHTML = `<div class="empty pad">${state.loadingPenal ? 'Loading penal code...' : 'Penal code unavailable.'}</div>`;
      $('#available-count').textContent = '0';
      return;
    }

    const charges = state.penal.charges.filter((c) =>
      !q || (`${c.code} ${c.title} ${c.category || ''} ${c.description || ''}`).toLowerCase().includes(q));

    $('#available-count').textContent = String(charges.length);

    if (!charges.length) {
      list.innerHTML = `<div class="empty pad">No charges match "${escapeHtml(q)}".</div>`;
      return;
    }

    const inCart = new Set(state.cart.map((c) => c.code));
    const frag = document.createDocumentFragment();

    charges.forEach((c) => {
      const added = inCart.has(c.code);
      const cm = classMeta(c.class);
      const row = document.createElement('div');
      row.className = 'charge-row';
      row.innerHTML =
        `<div class="charge-row-main">` +
          `<span class="code">${escapeHtml(c.code)}</span>` +
          `<span class="charge-row-title">${escapeHtml(c.title)}</span>` +
          `<span class="badge ${cm.key}">${escapeHtml(cm.label)}</span>` +
        `</div>` +
        `<div class="charge-row-meta">` +
          `<span class="meta-pill">${Number(c.months) || 0} min</span>` +
          `<span class="meta-pill">${money(c.fine)}</span>` +
          `<button class="btn-ghost desc-toggle">Details</button>` +
          `<button class="btn-add ${added ? 'is-added' : ''}" ${added ? 'disabled' : ''}>${added ? 'Added' : 'Add'}</button>` +
        `</div>` +
        `<div class="charge-desc hidden">${escapeHtml(c.description || 'No description on file.')}</div>`;

      row.querySelector('.desc-toggle').addEventListener('click', () => {
        row.querySelector('.charge-desc').classList.toggle('hidden');
      });
      if (!added) row.querySelector('.btn-add').addEventListener('click', () => addToCart(c.code));
      frag.appendChild(row);
    });

    list.innerHTML = '';
    list.appendChild(frag);
  }

  // ------------------------------------------------------------------
  // Cart
  // ------------------------------------------------------------------
  function addToCart(code) {
    if (state.cart.some((c) => c.code === code)) return;
    const base = state.chargeByCode[code];
    if (!base) return;
    state.cart.push({
      code: base.code,
      title: base.title,
      class: base.class,
      months: Number(base.months) || 0,
      fine: Number(base.fine) || 0,
      blockedModifiers: base.blockedModifiers || [],
      mods: []
    });
    renderCart(); renderAvailable(); recompute();
  }

  function removeFromCart(code) {
    state.cart = state.cart.filter((c) => c.code !== code);
    renderCart(); renderAvailable(); recompute();
  }

  function clearCart() {
    if (!state.cart.length) return;
    state.cart = [];
    renderCart(); renderAvailable(); recompute();
  }

  function toggleMod(code, modId) {
    const item = state.cart.find((c) => c.code === code);
    if (!item) return;
    const i = item.mods.indexOf(modId);
    if (i >= 0) item.mods.splice(i, 1); else item.mods.push(modId);
    renderCart(); recompute();
  }

  function multFor(mods) {
    let m = 1;
    mods.forEach((id) => {
      const mod = state.modByIdMap[id];
      if (mod && Number(mod.mult)) m *= Number(mod.mult);
    });
    return m;
  }

  // mirrors the server's authoritative floor(x*mult + 0.5)
  function itemValues(item) {
    const mult = multFor(item.mods);
    return {
      months: Math.floor((item.months || 0) * mult + 0.5),
      fine: Math.floor((item.fine || 0) * mult + 0.5)
    };
  }

  function renderCart() {
    const list = $('#cart-list');
    if (!state.cart.length) {
      list.innerHTML = emptyHTML(ICON.file, 'No charges added', 'Add charges from the list to build a record.');
      return;
    }
    const frag = document.createDocumentFragment();

    state.cart.forEach((item) => {
      const v = itemValues(item);
      const cm = classMeta(item.class);
      const blocked = item.blockedModifiers || [];
      const chips = state.penal.modifiers
        .filter((m) => !blocked.includes(m.id))
        .map((m) => {
          const on = item.mods.includes(m.id);
          const tip = `${m.description || ''} (x${m.mult})`;
          return `<button class="mod-chip ${on ? 'active' : ''}" data-mod="${escapeHtml(m.id)}" title="${escapeHtml(tip)}">${escapeHtml(m.label)}</button>`;
        }).join('');

      const row = document.createElement('div');
      row.className = 'cart-row';
      row.innerHTML =
        `<div class="cart-head">` +
          `<span class="code">${escapeHtml(item.code)}</span>` +
          `<span class="cart-title">${escapeHtml(item.title)}</span>` +
          `<span class="badge ${cm.key}">${escapeHtml(cm.label)}</span>` +
          `<button class="btn-remove" title="Remove">&times;</button>` +
        `</div>` +
        `<div class="cart-mods">${chips || '<span class="dim small">No modifiers available for this charge.</span>'}</div>` +
        `<div class="cart-calc"><span>${v.months} min jail</span><span>${money(v.fine)} fine</span></div>`;

      row.querySelector('.btn-remove').addEventListener('click', () => removeFromCart(item.code));
      row.querySelectorAll('.mod-chip').forEach((chip) =>
        chip.addEventListener('click', () => toggleMod(item.code, chip.dataset.mod)));
      frag.appendChild(row);
    });

    list.innerHTML = '';
    list.appendChild(frag);
  }

  function recompute() {
    let jail = 0, fine = 0;
    state.cart.forEach((item) => { const v = itemValues(item); jail += v.months; fine += v.fine; });
    $('#summary-jail').textContent = String(jail);
    $('#summary-fine').textContent = money(fine);
    $('#summary-count').textContent = String(state.cart.length);
    updatePlaceBtn();
  }

  function updateTargetChip() {
    const chip = $('#target-chip');
    const name = $('#target-name');
    if (state.target && state.target.name) {
      chip.classList.remove('empty');
      name.textContent = state.target.name;
    } else {
      chip.classList.add('empty');
      name.textContent = 'No target - search a person first';
    }
    updatePlaceBtn();
  }

  function updatePlaceBtn() {
    $('#btn-place').disabled = !(state.target && state.target.name && state.cart.length);
  }

  // ------------------------------------------------------------------
  // Place charges (records OUTSTANDING only - no jail, no fine)
  // ------------------------------------------------------------------
  async function placeCharges() {
    if (!state.target || !state.target.name) { toast('Set a target via Person Search first.', 'warn'); return; }
    if (!state.cart.length) { toast('Add at least one charge.', 'warn'); return; }

    const items = state.cart.map((c) => ({ code: c.code, modifiers: c.mods.slice() }));
    setBusy('#btn-place', true);
    const res = await nui('placeCharges', { name: state.target.name, items });
    setBusy('#btn-place', false);
    updatePlaceBtn();

    if (res && res.success) {
      toast(res.message || 'Charges recorded as outstanding.', 'ok');
      clearCart();
    } else {
      toast((res && res.message) || 'Failed to place charges.', 'err');
    }
  }

  // ------------------------------------------------------------------
  // Inline create-form toggling
  // ------------------------------------------------------------------
  function toggleForm(formSel, show) {
    const f = $(formSel);
    if (!f) return false;
    const willShow = (show === undefined) ? f.classList.contains('hidden') : show;
    f.classList.toggle('hidden', !willShow);
    return willShow;
  }

  // ------------------------------------------------------------------
  // BOLOs
  // ------------------------------------------------------------------
  async function loadBolos() {
    const list = $('#bolo-list');
    if (state.role === 'court') {
      // court cannot read BOLOs (server denies getBolos); show an honest
      // notice instead of a misleading "no active BOLOs" empty state
      state.loaded.bolos = true;
      list.innerHTML = emptyHTML(ICON.eye, 'Restricted section', 'BOLO alerts are limited to law enforcement.');
      return;
    }
    const stop = delayedSpinner(list, 'Loading BOLOs...');
    const data = await nui('getBolos', {});
    stop();
    state.loaded.bolos = true;
    const items = (data && Array.isArray(data.items)) ? data.items : [];
    if (!items.length) {
      list.innerHTML = emptyHTML(ICON.eye, 'No active BOLOs', 'Create one to alert other officers.');
      return;
    }
    const frag = document.createDocumentFragment();
    items.forEach((b) => {
      const imgs = Array.isArray(b.images) ? b.images.filter((u) => /^https?:\/\//.test(u)) : [];
      const card = document.createElement('div');
      card.className = 'bolo-card';

      // Fixed 16:9 media box: ONE image at a time so differing image heights
      // never change the card/description layout. Inline prev/next + counter
      // only when this bolo has more than one image.
      const multi = imgs.length > 1;
      const media =
        '<div class="bolo-media">' +
          (imgs.length
            ? '<img class="bolo-img" loading="lazy" alt="BOLO image" src="' + escapeHtml(imgs[0]) + '" />'
            : '') +
          '<span class="bolo-img-ph' + (imgs.length ? ' hidden' : '') + '">' +
            '<svg class="ic" viewBox="0 0 24 24" width="26" height="26">' + ICON.image + '</svg>' +
          '</span>' +
          (multi
            ? '<button type="button" class="bolo-img-nav prev" aria-label="Previous image">' +
                '<svg class="ic" viewBox="0 0 24 24" width="18" height="18"><path d="M15 6l-6 6 6 6"/></svg></button>' +
              '<button type="button" class="bolo-img-nav next" aria-label="Next image">' +
                '<svg class="ic" viewBox="0 0 24 24" width="18" height="18"><path d="M9 6l6 6-6 6"/></svg></button>' +
              '<span class="bolo-img-count tnum">1 / ' + imgs.length + '</span>'
            : '') +
        '</div>';

      card.innerHTML =
        media +
        `<div class="bolo-body">` +
          `<div class="bolo-top">` +
            `<span class="chip">${escapeHtml(b.type || 'other')}</span>` +
            `<span class="bolo-title">${escapeHtml(b.title || 'Untitled')}</span>` +
          `</div>` +
          `<div class="bolo-desc">${escapeHtml(b.description || 'No details provided.')}</div>` +
          `<div class="bolo-foot">` +
            `<span class="bolo-meta">${escapeHtml(b.officer || 'Unknown')} - ${escapeHtml(fmtDate(b.created_at))}</span>` +
            `<button class="btn danger sm">Cancel</button>` +
          `</div>` +
        `</div>`;

      // Per-card inline gallery: a closure index `cur` keeps THIS card's
      // current image independent of every other card. Clicking the image
      // opens the lightbox scoped to THIS bolo's images at `cur`; a bad URL
      // swaps to the themed placeholder inside the SAME fixed box.
      if (imgs.length) {
        const box = card.querySelector('.bolo-media');
        const im  = box.querySelector('.bolo-img');
        const ph  = box.querySelector('.bolo-img-ph');
        const cnt = box.querySelector('.bolo-img-count');
        let cur = 0;
        const show = (i) => {
          cur = (i + imgs.length) % imgs.length;
          im.classList.remove('hidden'); ph.classList.add('hidden');
          im.src = imgs[cur];
          if (cnt) cnt.textContent = (cur + 1) + ' / ' + imgs.length;
        };
        im.addEventListener('error', () => { im.classList.add('hidden'); ph.classList.remove('hidden'); });
        im.addEventListener('click', () => openLightbox(imgs, cur));
        const prev = box.querySelector('.bolo-img-nav.prev');
        const next = box.querySelector('.bolo-img-nav.next');
        if (prev) prev.addEventListener('click', (e) => { e.stopPropagation(); show(cur - 1); });
        if (next) next.addEventListener('click', (e) => { e.stopPropagation(); show(cur + 1); });
      }
      card.querySelector('.btn.danger').addEventListener('click', (e) => cancelBolo(b.id, e.currentTarget));
      frag.appendChild(card);
    });
    list.innerHTML = '';
    list.appendChild(frag);
  }

  // ---- BOLO image-link rows (repeatable; each row has its own remove button) ----
  function addBoloLinkRow(value) {
    const wrap = $('#bolo-images');
    if (!wrap) return;
    const row = document.createElement('div');
    row.className = 'link-row';
    row.innerHTML =
      '<input type="text" class="bolo-link" placeholder="https://... image URL" autocomplete="off" spellcheck="false" />' +
      '<button type="button" class="btn-remove link-del" title="Remove link" aria-label="Remove link">&times;</button>';
    if (value) row.querySelector('.bolo-link').value = value;
    // Removal is handled by a single delegated listener on #bolo-images
    // (bound in init) so dynamically created rows can never lose their handler.
    wrap.appendChild(row);
  }
  function resetBoloLinks() {
    const wrap = $('#bolo-images');
    if (!wrap) return;
    wrap.innerHTML = '';
    addBoloLinkRow();
  }
  function boloLinkValues() {
    return $$('#bolo-images .bolo-link')
      .map((i) => i.value.trim())
      .filter((v) => /^https:\/\//.test(v)); // https-only client pre-filter; the server re-validates
  }

  // ---- Fullscreen lightbox: one BOLO's images, contain on a dark scrim ----
  function isLightboxOpen() { return !$('#lightbox').classList.contains('hidden'); }
  function renderLightbox() {
    const lb = state.lightbox, n = lb.images.length;
    if (!n) { closeLightbox(); return; }
    if (lb.index < 0) lb.index = n - 1;
    if (lb.index >= n) lb.index = 0;
    const img = $('#lb-img');
    img.onerror = () => { img.removeAttribute('src'); }; // contain box stays, blank on bad URL
    img.src = lb.images[lb.index];
    $('#lb-index').textContent = (lb.index + 1) + ' / ' + n;
    $('#lb-prev').classList.toggle('hidden', n < 2);
    $('#lb-next').classList.toggle('hidden', n < 2);
  }
  function openLightbox(images, index) {
    state.lightbox.images = (images || []).slice();
    state.lightbox.index = Number(index) || 0;
    $('#lightbox').classList.remove('hidden');
    renderLightbox();
  }
  function closeLightbox() { $('#lightbox').classList.add('hidden'); }
  function lightboxStep(dir) { state.lightbox.index += dir; renderLightbox(); }

  async function createBolo() {
    const type = $('#bolo-type').value;
    const title = $('#bolo-title').value.trim();
    const description = $('#bolo-desc').value.trim();
    const images = boloLinkValues();
    if (!title) { toast('Enter a BOLO title.', 'warn'); return; }
    setBusy('#bolo-create', true);
    const res = await nui('createBolo', { type, title, description, images });
    setBusy('#bolo-create', false);
    if (res && res.success) {
      toast(res.message || 'BOLO created.', 'ok');
      $('#bolo-title').value = '';
      $('#bolo-desc').value = '';
      resetBoloLinks();
      toggleForm('#bolo-form', false);
      loadBolos();
    } else {
      toast((res && res.message) || 'Failed to create BOLO.', 'err');
    }
  }

  async function cancelBolo(id, btn) {
    if (btn) { btn.disabled = true; btn.classList.add('is-busy'); }
    const res = await nui('cancelBolo', { id });
    if (res && res.success) {
      toast(res.message || 'BOLO cancelled.', 'ok');
      loadBolos();
    } else {
      toast((res && res.message) || 'Failed to cancel BOLO.', 'err');
      if (btn) { btn.disabled = false; btn.classList.remove('is-busy'); }
    }
  }

  // ------------------------------------------------------------------
  // Warrants (derived, read-only) - name - charges - months - fine
  // ------------------------------------------------------------------
  async function loadWarrants() {
    const list = $('#warrant-list');
    const stop = delayedSpinner(list, 'Loading warrants...');
    const data = await nui('getWarrants', {});
    stop();
    state.loaded.warrants = true;
    const items = (data && Array.isArray(data.items)) ? data.items : [];
    if (!items.length) {
      list.innerHTML = emptyHTML(ICON.shield, 'No active warrants', 'Suspects with outstanding charges.');
      return;
    }
    const frag = document.createDocumentFragment();
    items.forEach((w) => {
      const wl = wantedLevelOf(w.wanted);
      const wantedPill = wl > 0
        ? `<span class="pill wanted-pill ${wl >= 3 ? 'danger' : 'warn'}">${starsHTML(wl, 12)}<span class="pv tnum">${wl}/5</span></span>`
        : '';
      const row = document.createElement('div');
      row.className = 'list-row';
      row.innerHTML =
        `<div class="list-main">` +
          `<div class="list-top"><span class="list-title">${escapeHtml(w.name || 'Unknown')}</span></div>` +
          `<div class="list-meta">Outstanding charges on record</div>` +
        `</div>` +
        `<div class="list-right">` +
          wantedPill +
          `<span class="pill danger"><span class="pv tnum">${Number(w.charges) || 0}</span> charges</span>` +
          `<span class="pill warn"><span class="pv tnum">${Number(w.months) || 0}</span> min</span>` +
          `<span class="pill"><span class="pv tnum">${money(w.fine)}</span> fine</span>` +
          `<button class="btn-ghost small view-rec">View Record</button>` +
        `</div>`;
      row.querySelector('.view-rec').addEventListener('click', () => openWarrantRecord(w.name));
      frag.appendChild(row);
    });
    list.innerHTML = '';
    list.appendChild(frag);
  }

  // Open a warrant suspect in Person Search (NAME only - never any id).
  function openWarrantRecord(name) {
    if (!name) return;
    showTab('person');
    $('#person-name').value = name;
    searchPerson();
  }

  // ------------------------------------------------------------------
  // Medical (EMS role only; the server rejects everyone else). Patient
  // history by NAME + the newest-30 recent activity feed. NO citizen ids.
  // ------------------------------------------------------------------
  function medBadge(action) {
    const key = String(action || '').toLowerCase() === 'revive' ? 'revive' : 'treatment';
    const label = key === 'revive' ? 'Revive' : 'Treatment';
    return `<span class="badge ${key}">${label}</span>`;
  }

  async function searchMedical() {
    const name = $('#med-patient-name').value.trim();
    if (!name) { toast('Enter a patient name to search.', 'warn'); return; }
    $('#med-empty').classList.add('hidden');
    $('#med-results').classList.add('hidden');
    setBusy('#med-search-btn', true);
    const stop = searchLoading($('#med-body'));
    const data = await nui('searchMedical', { name });
    stop();
    setBusy('#med-search-btn', false);
    renderMedical(data);
  }

  function renderMedical(data) {
    const empty = $('#med-empty');
    const results = $('#med-results');
    if (!data || !data.found) {
      results.classList.add('hidden');
      empty.classList.remove('hidden');
      empty.innerHTML = data
        ? emptyHTML(ICON.units, 'No patient found', 'No record matches that name.')
        : emptyHTML(ICON.units, 'Search unavailable', 'Are you on duty as EMS?');
      return;
    }
    empty.classList.add('hidden');
    results.classList.remove('hidden');
    $('#med-patient').textContent = data.name || '-';
    const items = Array.isArray(data.items) ? data.items : [];
    $('#med-hist-count').textContent = String(items.length);
    const body = $('#med-history-body');
    if (!items.length) {
      body.innerHTML = `<tr class="empty-row"><td colspan="4">No incident history on file.</td></tr>`;
      return;
    }
    const frag = document.createDocumentFragment();
    items.forEach((r) => {
      const tr = document.createElement('tr');
      tr.innerHTML =
        `<td>${medBadge(r.action)}</td>` +
        `<td>${escapeHtml(r.detail || '-')}</td>` +
        `<td>${escapeHtml(r.medic || 'Unknown')}</td>` +
        `<td class="mono">${escapeHtml(r.created_at || '-')}</td>`;
      frag.appendChild(tr);
    });
    body.innerHTML = '';
    body.appendChild(frag);
  }

  async function loadRecentMedical() {
    const list = $('#med-recent-list');
    if (!list) return;
    const stop = delayedSpinner(list, 'Loading activity...');
    const data = await nui('getRecentMedical', {});
    stop();
    const items = (data && Array.isArray(data.items)) ? data.items : [];
    const count = $('#med-recent-count');
    if (count) count.textContent = String(items.length);
    if (!items.length) {
      list.innerHTML = emptyHTML(ICON.file, 'No recent activity',
        'Revives and treatments are logged here as they happen.');
      return;
    }
    const frag = document.createDocumentFragment();
    items.forEach((r) => {
      const row = document.createElement('div');
      row.className = 'list-row click';
      row.innerHTML =
        `<div class="list-main">` +
          `<div class="list-top"><span class="list-title">${escapeHtml(r.patient || 'Unknown')}</span>${medBadge(r.action)}</div>` +
          `<div class="list-meta">${escapeHtml(r.detail || '-')} - by ${escapeHtml(r.medic || 'Unknown')}</div>` +
        `</div>` +
        `<span class="pill"><span class="pv tnum">${escapeHtml(r.created_at || '-')}</span></span>`;
      // click -> open that patient's full history in the search above
      row.addEventListener('click', () => {
        $('#med-patient-name').value = r.patient || '';
        searchMedical();
      });
      frag.appendChild(row);
    });
    list.innerHTML = '';
    list.appendChild(frag);
  }

  // ------------------------------------------------------------------
  // Cameras
  // ------------------------------------------------------------------
  async function loadCameras() {
    const grid = $('#camera-grid');
    const stop = delayedSpinner(grid, 'Loading feeds...');
    const data = await nui('getCameras', {});
    stop();
    state.loaded.cameras = true;
    const feeds = (data && Array.isArray(data.feeds)) ? data.feeds : [];
    state.feeds = feeds;        // keep for overlay prev/next cycling
    if (!feeds.length) {
      grid.innerHTML = emptyHTML(ICON.camera, 'No camera feeds', 'No surveillance feeds are configured.');
      return;
    }
    const frag = document.createDocumentFragment();
    feeds.forEach((f) => {
      const tile = document.createElement('button');
      tile.className = 'cam-tile';
      tile.dataset.id = f.id;
      tile.innerHTML =
        `<span class="cam-thumb"><svg class="ic" viewBox="0 0 24 24" width="22" height="22">${ICON.camera}</svg></span>` +
        `<span class="cam-tile-label">${escapeHtml(f.label || f.id)}</span>`;
      tile.addEventListener('click', () => viewCamera(f.id, f.label || f.id));
      frag.appendChild(tile);
    });
    grid.innerHTML = '';
    grid.appendChild(frag);
    markActiveCam();
  }

  // ------------------------------------------------------------------
  // Bodycam Archive - recent captures (newest 30), officer + timestamp.
  // Clicking an entry opens the frame in the existing fullscreen lightbox.
  // Available to both roles (court is read-only; server enforces).
  // ------------------------------------------------------------------
  async function loadBodycam() {
    const list = $('#bodycam-list');
    if (!list) return;
    const stop = delayedSpinner(list, 'Loading captures...');
    const data = await nui('getBodycam', {});
    stop();
    state.loaded.bodycam = true;
    const items = (data && Array.isArray(data.items)) ? data.items : [];
    const count = $('#bodycam-count');
    if (count) count.textContent = String(items.length);
    if (!items.length) {
      list.innerHTML = emptyHTML(ICON.camera, 'No bodycam captures',
        'Frames are archived while an officer bodycam is recording.');
      return;
    }
    const frag = document.createDocumentFragment();
    items.forEach((c) => {
      const src = mugSrc(c.image);
      const row = document.createElement('div');
      row.className = 'list-row' + (src ? ' click' : '');
      row.innerHTML =
        `<span class="cam-thumb bodycam-thumb">` +
          (src
            ? `<img class="bodycam-thumb-img" alt="Bodycam frame" src="${escapeHtml(src)}" />`
            : `<svg class="ic" viewBox="0 0 24 24" width="20" height="20">${ICON.camera}</svg>`) +
        `</span>` +
        `<div class="list-main">` +
          `<div class="list-top"><span class="list-title">${escapeHtml(c.officer || 'Unknown officer')}</span></div>` +
          `<div class="list-meta mono">${escapeHtml(c.captured_at || '-')}</div>` +
        `</div>` +
        (src ? `<span class="pill">View</span>` : `<span class="pill warn">No image</span>`);
      if (src) row.addEventListener('click', () => openLightbox([src], 0));
      const thumb = row.querySelector('.bodycam-thumb-img');
      if (thumb) thumb.addEventListener('error', () => {
        thumb.outerHTML = `<svg class="ic" viewBox="0 0 24 24" width="20" height="20">${ICON.camera}</svg>`;
      });
      frag.appendChild(row);
    });
    list.innerHTML = '';
    list.appendChild(frag);
  }

  // ---- Camera mode: the overlay is INFO ONLY. There is no cursor in cam-mode
  // (the client drops NUI focus), so all look / zoom / feed-switch / vision /
  // exit input is read on the CLIENT each frame. The client then drives the
  // overlay via camFeed / camVision / camExit messages. ----

  // Reflect the client's vision state on the overlay badge ('off'|'night'|'thermal').
  function setCamVision(mode) {
    const el = $('#cam-ov-vision');
    if (!el) return;
    el.classList.toggle('hidden', mode === 'off');
    el.textContent = mode === 'thermal' ? 'THERMAL' : 'NIGHT VISION';
  }

  // Hide the MDT panel + drop the dim so the player sees the live CCTV view.
  function enterCamMode() {
    app.classList.add('cam-mode');
    $('#cam-overlay').classList.remove('hidden');
    setCamVision('off');
  }
  function exitCamMode() {
    app.classList.remove('cam-mode');
    $('#cam-overlay').classList.add('hidden');
    setCamVision('off');
  }

  // Drive the overlay (name + "N / total") and the active-tile highlight.
  function markActiveCam() {
    const id = state.activeCam && state.activeCam.id;
    $$('#camera-grid .cam-tile').forEach((t) => t.classList.toggle('active', t.dataset.id === id));
    if (state.activeCam) {
      const n = state.feeds.length;
      const i = state.feeds.findIndex((f) => f.id === id);
      $('#cam-ov-name').textContent = state.activeCam.label || '-';
      $('#cam-ov-index').textContent = (n ? (i >= 0 ? i + 1 : 1) : 1) + ' / ' + (n || 1);
    }
  }

  // Open a feed from a tile click (cursor present, panel up). On success the
  // client has already hidden the cursor and entered mouse-look; we just switch
  // the UI into cam-mode. Feed name / index / vision come from the client's
  // camFeed message (markActiveCam stays authoritative for name + index).
  async function viewCamera(id, label) {
    const res = await nui('viewCamera', { id });
    if (res && res.ok) {
      state.activeCam = { id, label };
      enterCamMode();
      markActiveCam();
    } else {
      toast('Could not open that feed.', 'err');
    }
  }

  // ------------------------------------------------------------------
  // Global key + wheel navigation (each mode owns its keys; never hijack typing)
  // ------------------------------------------------------------------
  // Left/Right: lightbox image when open. (BOLOs are a plain scrollable
  // grid now - no page-level card stepping.)
  document.addEventListener('keydown', (e) => {
    if (app.classList.contains('hidden')) return;
    // Lightbox owns Left/Right (Esc is handled by the Escape listener).
    if (isLightboxOpen()) {
      if (e.key === 'ArrowLeft') { e.preventDefault(); lightboxStep(-1); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); lightboxStep(1); }
    }
  });

  // Cam-mode input (mouse look, scroll zoom, arrows feed-switch, Space night
  // vision, Backspace exit) is read entirely on the CLIENT each frame - the NUI
  // page has no focus in cam-mode, so it cannot receive key or wheel events.

  // ------------------------------------------------------------------
  // Bodycam REC toggle. The client owns the REAL capture loop (a frame on
  // toggle + every 60s via screenshot-basic); we just reflect its on/off
  // state on the button and the corner REC indicator.
  // ------------------------------------------------------------------
  let recTimer = null, recStart = 0;
  function tickRec() {
    const s = Math.floor((Date.now() - recStart) / 1000);
    const mm = String(Math.floor(s / 60)).padStart(2, '0');
    const ss = String(s % 60).padStart(2, '0');
    $('#rec-time').textContent = `${mm}:${ss}`;
  }
  function updateBodycam() {
    $('#bodycam-rec').classList.toggle('hidden', !state.bodycam);
    const btn = $('#bodycam-btn');
    btn.classList.toggle('primary', state.bodycam);
    $('#bodycam-label').textContent = state.bodycam ? 'Bodycam: On' : 'Bodycam: Off';
    if (state.bodycam) {
      recStart = Date.now(); tickRec();
      clearInterval(recTimer);
      recTimer = setInterval(tickRec, 1000);
    } else {
      clearInterval(recTimer); recTimer = null;
      $('#rec-time').textContent = '00:00';
    }
  }
  async function toggleBodycam() {
    const res = await nui('toggleBodycam', {});
    state.bodycam = !!(res && res.on);
    updateBodycam();
  }

  // ------------------------------------------------------------------
  // Init / wiring
  // ------------------------------------------------------------------
  function init() {
    $$('.rail-btn').forEach((b) => b.addEventListener('click', () => showTab(b.dataset.tab)));
    $('#close-btn').addEventListener('click', closeMdt);

    // Dashboard
    $('#dash-refresh').addEventListener('click', () => loadDashboard());

    // Vehicle
    $('#veh-search-btn').addEventListener('click', searchVehicle);
    $('#vehicle-plate').addEventListener('keydown', (e) => { if (e.key === 'Enter') searchVehicle(); });

    // Person
    $('#per-search-btn').addEventListener('click', searchPerson);
    $('#person-name').addEventListener('keydown', (e) => { if (e.key === 'Enter') searchPerson(); });

    // Record History show/hide filter chips (sticky across searches).
    $('#per-history-filters').addEventListener('click', (e) => {
      const chip = e.target.closest('.filter-chip');
      if (!chip || !(chip.dataset.filter in HIST_FILTER)) return;
      const key = chip.dataset.filter;
      HIST_FILTER[key] = !HIST_FILTER[key];
      chip.classList.toggle('off', !HIST_FILTER[key]);
      chip.setAttribute('aria-pressed', String(HIST_FILTER[key]));
      applyHistoryFilter();
    });
    $('#per-to-calc').addEventListener('click', () => {
      if (!state.target || !state.target.name) { toast('Search a person first.', 'warn'); return; }
      updateTargetChip();
      showTab('calculator');
      toast('Target set: ' + state.target.name, 'ok');
    });

    // Wanted level setter (LEO only; hidden for court via .leo-only)
    $('#wanted-set-btn').addEventListener('click', setWantedFromUI);
    $('#wanted-reason-inp').addEventListener('keydown', (e) => { if (e.key === 'Enter') setWantedFromUI(); });

    // Calculator
    let searchTimer;
    $('#charge-search').addEventListener('input', () => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(renderAvailable, 120);
    });
    $('#cart-clear').addEventListener('click', clearCart);
    $('#btn-place').addEventListener('click', placeCharges);

    // BOLOs
    $('#bolo-refresh').addEventListener('click', loadBolos);
    $('#bolo-new-btn').addEventListener('click', () => toggleForm('#bolo-form'));
    $('#bolo-cancel').addEventListener('click', () => toggleForm('#bolo-form', false));
    $('#bolo-form').addEventListener('submit', (e) => { e.preventDefault(); createBolo(); });
    $('#bolo-add-link').addEventListener('click', () => addBoloLinkRow());
    // Delegated removal so dynamically added rows always work; never leave zero rows.
    $('#bolo-images').addEventListener('click', (e) => {
      const del = e.target.closest('.link-del');
      if (!del) return;
      const row = del.closest('.link-row');
      if (row) row.remove();
      if (!$$('#bolo-images .link-row').length) addBoloLinkRow();
    });
    resetBoloLinks();   // start the create form with one empty link row

    // Lightbox (fullscreen BOLO image viewer)
    $('#lb-close').addEventListener('click', closeLightbox);
    $('#lb-prev').addEventListener('click', () => lightboxStep(-1));
    $('#lb-next').addEventListener('click', () => lightboxStep(1));
    $('#lightbox').addEventListener('mousedown', (e) => { if (e.target.id === 'lightbox') closeLightbox(); });

    // Warrants auto-refresh on tab open (no manual refresh button)

    // Reports

    // Cameras: tiles wire their own click in loadCameras, and the in-feed
    // overlay is info-only now (no cursor in cam-mode), so there are no overlay
    // buttons to wire. Bodycam toggle + archive refresh remain.
    $('#bodycam-btn').addEventListener('click', toggleBodycam);
    $('#bodycam-archive-refresh').addEventListener('click', loadBodycam);

    // Medical (EMS role only; the tab is hidden for everyone else)
    $('#med-search-btn').addEventListener('click', searchMedical);
    $('#med-patient-name').addEventListener('keydown', (e) => { if (e.key === 'Enter') searchMedical(); });
    $('#med-recent-refresh').addEventListener('click', loadRecentMedical);

    renderCart();
    recompute();
    updateTargetChip();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
