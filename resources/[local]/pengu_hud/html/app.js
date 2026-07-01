'use strict';

// --- STATUS ICON DEFINITIONS (stroke SVG paths, viewBox 0 0 24 24) ---
const ICONS = {
  heart:   'M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z',
  shield:  'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1Z',
  food:    'M3 2v7a2 2 0 0 0 2 2 2 2 0 0 0 2-2V2M7 2v20M21 15V2a5 5 0 0 0-5 5v6a2 2 0 0 0 2 2h3v7',
  droplet: 'M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z',
  zap:     'M13 2 4 14h6l-1 8 9-12h-6l1-8z',
  wind:    'M12.8 19.6A2 2 0 1 0 14 16H2M17.5 8a2.5 2.5 0 1 1 1.8 4.3H2M9.8 4.4A2 2 0 1 1 11 8H2',
  brain:   'M9.5 2A2.5 2.5 0 0 1 12 4.5v15a2.5 2.5 0 0 1-4.96.44 2.5 2.5 0 0 1-2.96-3.08 3 3 0 0 1-.34-5.58 2.5 2.5 0 0 1 1.32-4.24A2.5 2.5 0 0 1 7 2.5 2.5 2.5 0 0 1 9.5 2ZM14.5 2A2.5 2.5 0 0 0 12 4.5v15a2.5 2.5 0 0 0 4.96.44 2.5 2.5 0 0 0 2.96-3.08 3 3 0 0 0 .34-5.58 2.5 2.5 0 0 0-1.32-4.24A2.5 2.5 0 0 0 17 2.5 2.5 2.5 0 0 0 14.5 2Z',
};

const STATUS = [
  { key: 'health',  icon: 'heart',   color: v => v > 50 ? '#4ade80' : v > 25 ? '#fb923c' : '#f87171' },
  { key: 'armor',   icon: 'shield',  color: () => '#60a5fa' },
  { key: 'hunger',  icon: 'food',    color: v => v > 60 ? '#facc15' : v > 30 ? '#fb923c' : '#f87171' },
  { key: 'thirst',  icon: 'droplet', color: v => v > 60 ? '#38bdf8' : v > 30 ? '#fb923c' : '#f87171' },
  { key: 'stamina', icon: 'zap',     color: v => v > 30 ? '#a3e635' : '#fb923c', hideWhen: v => v >= 100 },
  { key: 'oxygen',  icon: 'wind',    color: v => v > 40 ? '#67e8f9' : '#f87171', hideWhen: v => v >= 100 },
  { key: 'stress',  icon: 'brain',   color: v => v < 30 ? '#c084fc' : v < 70 ? '#fb923c' : '#f87171', hideWhen: v => v <= 0 },
];

const fills  = {};
const sicons = {};
const items  = {};

function buildStatus() {
  const row = document.getElementById('status-row');

  // /aduty admin-duty indicator: leftmost, icon-only, shown only while on admin duty.
  const adm = document.createElement('div');
  adm.className = 'si si-aduty hidden';
  adm.id = 'si-aduty';
  adm.innerHTML =
    `<svg class="si-icon" viewBox="0 0 24 24" id="i-aduty">` +
      `<path d="${ICONS.shield}"/>` +
      `<path d="M9.2 12l1.9 1.9L15 9.9"/>` +
    `</svg>`;
  row.appendChild(adm);

  STATUS.forEach(def => {
    const el = document.createElement('div');
    el.className = 'si';
    el.dataset.key = def.key;
    el.innerHTML =
      `<svg class="si-icon" viewBox="0 0 24 24" id="i-${def.key}"><path d="${ICONS[def.icon]}"/></svg>` +
      `<div class="si-bar"><div class="si-fill" id="f-${def.key}"></div></div>`;
    row.appendChild(el);
    items[def.key]  = el;
    sicons[def.key] = document.getElementById('i-' + def.key);
    fills[def.key]  = document.getElementById('f-' + def.key);
    if (def.hideWhen) el.classList.add('hidden'); // start hidden until relevant
  });
}

function updateStatus(data) {
  STATUS.forEach(def => {
    const v = Math.min(100, Math.max(0, Math.round(data[def.key] ?? 100)));
    const c = def.color(v);
    fills[def.key].style.width      = v + '%';
    fills[def.key].style.background = c;
    sicons[def.key].style.stroke    = c;
    // oxygen/stress: only show when out of their normal range
    if (def.hideWhen) items[def.key].classList.toggle('hidden', def.hideWhen(v));
  });
  if ('aduty' in data) setAduty(!!data.aduty);
}

function setAduty(on) {
  const el = document.getElementById('si-aduty');
  if (el) el.classList.toggle('hidden', !on);
}

// --- SPEEDOMETER (glass card, fuel bar, engine light) ---
const speedo     = document.getElementById('speedometer');
const speedNum   = document.getElementById('speed-num');
const speedUnit  = document.getElementById('speed-unit');
const fuelFill   = document.getElementById('fuel-fill');
const beltIcon   = document.getElementById('belt-icon');
const engineIcon = document.getElementById('engine-icon');
const gearLabel  = document.getElementById('gear-label');

function updateVehicle(data) {
  if (!data.show) { speedo.classList.add('hidden'); return; }
  if (localStorage.getItem('hide_speedo') === 'true') { speedo.classList.add('hidden'); return; }
  speedo.classList.remove('hidden');

  const spd = data.speed || 0;
  speedNum.textContent  = spd;
  speedUnit.textContent = data.unit || 'MPH';

  const fuel = Math.min(100, Math.max(0, data.fuel ?? 100));
  fuelFill.style.width      = fuel + '%';
  fuelFill.style.background  = fuel > 30 ? '#7CFFA0' : fuel > 15 ? '#facc15' : '#ff5a5a';

  const g = data.gear ?? 0;
  gearLabel.textContent = spd < 1 ? 'N' : g === 0 ? 'R' : g;

  beltIcon.classList.toggle('on',  !!data.seatbelt);
  beltIcon.classList.toggle('off', !data.seatbelt);

  // Check-engine light: healthy > 650, warn 300-650 (yellow), crit < 300 (red, blinking)
  const eng = data.engine;
  if (eng === undefined || eng > 650) {
    engineIcon.classList.add('hidden');
    engineIcon.classList.remove('warn', 'crit');
  } else if (eng > 300) {
    engineIcon.classList.remove('hidden', 'crit');
    engineIcon.classList.add('warn');
  } else {
    engineIcon.classList.remove('hidden', 'warn');
    engineIcon.classList.add('crit');
  }
}

// --- VOICE METER ---
const voiceEl    = document.getElementById('voice');
const voiceMic   = document.getElementById('voice-mic');
const voiceLabel = document.getElementById('voice-label');
const voiceBars  = Array.from(document.querySelectorAll('#voice .vb'));
const VOICE_LABELS = { 1: 'Whisper', 2: 'Normal', 3: 'Shout' };

function updateVoice(data) {
  const lvl = data.level || 2;
  voiceBars.forEach((b, i) => {
    const on = (i + 1) <= lvl;
    b.classList.toggle('on', on);
    b.classList.toggle('talking', on && !!data.talking);
  });
  voiceLabel.textContent = VOICE_LABELS[lvl] || 'Normal';
  voiceEl.classList.toggle('talking', !!data.talking);
}

// --- VISIBILITY ---
let hudVisible = false;
const PANELS = { 'status-row': 'status' };

function applyVisibility() {
  Object.entries(PANELS).forEach(([id, key]) => {
    const hidden = localStorage.getItem('hide_' + key) === 'true';
    document.getElementById(id).classList.toggle('hidden', !hudVisible || hidden);
  });
  voiceEl.classList.toggle('hidden', !hudVisible);
  if (!hudVisible) speedo.classList.add('hidden');
}

function setHUDVisible(v) { hudVisible = v; applyVisibility(); }

// --- SETTINGS ---
const Settings = {
  open(unit) {
    unit = unit || localStorage.getItem('speed_unit') || 'MPH';
    document.getElementById('btn-mph').classList.toggle('active', unit === 'MPH');
    document.getElementById('btn-kph').classList.toggle('active', unit === 'KPH');
    document.getElementById('tog-status').checked     = localStorage.getItem('hide_status')     !== 'true';
    document.getElementById('tog-speedo').checked     = localStorage.getItem('hide_speedo')     !== 'true';
    document.getElementById('settings-overlay').classList.remove('hidden');
  },
  close() {
    document.getElementById('settings-overlay').classList.add('hidden');
    fetch('https://pengu_hud/closeSettings', { method: 'POST', body: '{}' });
  },
  setUnit(u) {
    localStorage.setItem('speed_unit', u);
    document.getElementById('btn-mph').classList.toggle('active', u === 'MPH');
    document.getElementById('btn-kph').classList.toggle('active', u === 'KPH');
    fetch('https://pengu_hud/saveSettings', { method: 'POST', body: JSON.stringify({ speedUnit: u }) });
  },
  toggleEl(key, checked) {
    localStorage.setItem('hide_' + key, !checked);
    applyVisibility();
  },
  reset() {
    ['status', 'speedo'].forEach(k => localStorage.removeItem('hide_' + k));
    localStorage.removeItem('speed_unit');
    this.setUnit('MPH');
    applyVisibility();
    this.open('MPH');
  },
};

// --- DRUG EFFECT ICONS ---
// stroke-style (outline) SVG inner markup per icon key.
const EFFECT_ICONS = {
  bolt:  '<path d="M13 2 4 14h6l-1 8 9-12h-6z"/>',
  snow:  '<path d="M12 2v20M4 6l16 12M20 6 4 18"/>',
  fire:  '<path d="M12 2c1 4 5 5 5 9a5 5 0 0 1-10 0c0-2 1-3 2-4 0 2 1 3 2 3 0-3-1-5-1-8z"/>',
  heart: '<path d="M12 21s-7-4.5-9.5-9A5 5 0 0 1 12 6a5 5 0 0 1 9.5 6C19 16.5 12 21 12 21z"/>',
  pill:  '<rect x="3" y="9" width="18" height="6" rx="3"/><path d="M12 9v6"/>',
  leaf:  '<path d="M12 22c0-8 4-12 9-13-1 9-5 13-9 13zM12 22C12 14 8 10 3 9c1 9 5 13 9 13z"/>',
};
const effectsRow = document.getElementById('effects-row');
function renderEffects(list) {
  if (!Array.isArray(list) || list.length === 0) {
    effectsRow.classList.add('hidden');
    effectsRow.innerHTML = '';
    return;
  }
  effectsRow.classList.remove('hidden');
  effectsRow.innerHTML = list.map((e) => {
    const icon = EFFECT_ICONS[e.icon] || EFFECT_ICONS.pill;
    const deg = Math.round(Math.max(0, Math.min(1, e.pct || 0)) * 360); // ring depletes with time left
    return '<div class="fx-chip" style="--deg:' + deg + 'deg" title="' + (e.label || '') + '">'
      + '<svg class="fx-ic" viewBox="0 0 24 24">' + icon + '</svg>'
      + '<span class="fx-secs">' + (e.secs || 0) + 's</span></div>';
  }).join('');
}

// --- MESSAGE HANDLER ---
window.addEventListener('message', ({ data }) => {
  switch (data.action) {
    case 'show':           setHUDVisible(!!data.visible);       break;
    case 'status':         if (hudVisible) updateStatus(data);  break;
    case 'aduty':          setAduty(!!data.on);                 break;
    case 'vehicle':        if (hudVisible) updateVehicle(data); break;
    case 'voice':          if (hudVisible) updateVoice(data);   break;
    case 'effects':        renderEffects(data.list);            break;
    case 'toggleSettings': Settings.open(data.unit);            break;
  }
});

document.addEventListener('keydown', e => {
  if (e.key === 'Escape' && !document.getElementById('settings-overlay').classList.contains('hidden')) {
    Settings.close();
  }
});

// --- INIT ---
buildStatus();
