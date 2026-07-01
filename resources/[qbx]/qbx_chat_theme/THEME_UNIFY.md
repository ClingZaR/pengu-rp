# THEME_UNIFY — why "Status Check: Committed suicide" looks unthemed, and how to fix it

## TL;DR

The death/status line (e.g. `Status Check: Committed suicide`) is emitted by
**qbx_medical** and **qbx_ambulancejob** via `TriggerEvent('chat:addMessage', {...})`
**with NO `templateId`**. With no template id, the chat engine falls back to this
theme's `default` template, which is the **system-card** style (`.message-wrapper`:
dark pill background, message-icon, mantine `--font-family`). The RP messages
(`/me`, `/do`, `/stats`, …) instead use the `rp:*` templates rendered as `.rp-line`
(transparent background, bold Arial, black text-outline). So the status line renders
in a different visual family — that is the mismatch.

Secondary issue: those emits also pass `color = { 255, 0, 0 }` (they want red), but
the theme's `default` template HTML never references the color, so the intended red is
also dropped.

Fix: add one new themed template `rp:status` (an `.rp-line` variant) and point the
three emit sites at it. No arg changes are required.

---

## 1) How the themed RP messages work

Templates are registered by this resource through the `chat_theme 'qbox_chat'` block in
`fxmanifest.lua` (the `msgTemplates` table), styled by `theme/app.css`, with runtime
CSS vars injected by `theme/app.js` (fetches NUI `config` and sets `--main-color`,
`--font-family`, icon urls, etc.). There is **no `chat:addTemplate`/`addTemplate` call
anywhere** — every template lives in the `msgTemplates` table.

Two distinct visual families:

- **System / console cards** — template ids `default`, `defaultAlt`, `print`, `join`,
  `quit`. HTML wrapper class `.message-wrapper`. Styled in `app.css` as a **dark pill**
  (`background: rgba(0,0,0,0.45)`, rounded, left icon, `font-family: var(--font-family)`).

- **RP lines** — template ids `user`, `rp:me`, `rp:do`, `rp:ooc`, `rp:dispatch`,
  `rp:success`, `rp:faction`, `rp:law`, `pengu:stats`. HTML wrapper class `.rp-line`
  (plus a modifier like `.rp-me`, `.rp-stats`). Styled in `app.css` as **transparent
  background, bold Arial (`--rp-font`), black 8-direction text-outline (`--outline`)**,
  per-type colors via `--c-*` vars.

Examples of the themed path:
- `/me /do /ooc` → `server/rp-commands.lua` sends `templateId = 'rp:me' | 'rp:do' | 'rp:ooc'`.
- `/stats` → `pengu_core/client/stats.lua` → `pengu_core:requestStats` →
  `pengu_core/server/stats.lua` sends `templateId = 'pengu:stats'` →
  rendered by `.rp-line.rp-stats` (`fxmanifest.lua:79`, CSS `app.css:250-260`).

So a message is "themed like the RP lines" **iff** it passes a `templateId` that maps to
an `.rp-line` template. The status/death line passes none.

---

## 2) Where the "Status Check" / death line comes from

- `"Status Check"` is the locale string `info.status` in both
  `qbx_medical/locales/en.json:11` and `qbx_ambulancejob/locales/en.json:32`.
- `"Committed suicide"` (and `Bled out`, `Died`, `Killed / …`, etc.) is the
  `damagereason` field on each weapon in `qbx_core/shared/weapons.lua`
  (e.g. `weapon_fall → damagereason = 'Committed suicide'`,
  `weapon_bleeding → 'Bled out'`). These come from `exports.qbx_core:GetWeapons()`.

### Exact emit sites (all unthemed — no `templateId`)

**A. `qbx_medical/client/damage/damage.lua:208-212`** — fires once per new weapon that
damages you (this is the one that prints `Status Check: Committed suicide` on a fall death):
```lua
TriggerEvent('chat:addMessage', {
    color = { 255, 0, 0 },
    multiline = false,
    args = { locale('info.status'), WEAPONS?[weaponHash]?.damagereason or 'Unknown' }
})
```

**B. `qbx_ambulancejob/client/job.lua:94-98`** — medic status check, one line per damage cause:
```lua
TriggerEvent('chat:addMessage', {
    color = { 255, 0, 0 },
    multiline = false,
    args = { locale('info.status'), WEAPONS[hash].damagereason }
})
```

**C. `qbx_ambulancejob/client/job.lua:102-106`** — medic status check, bleed level:
```lua
TriggerEvent('chat:addMessage', {
    color = { 255, 0, 0 },
    multiline = false,
    args = { locale('info.status'), locale('info.is_status', status.bleedState) }
})
```

In all three: `args = { {0}=label, {1}=reason }`, i.e. `{0}="Status Check"`, `{1}=reason`.

---

## 3) Why it is unthemed (root cause)

1. **No `templateId`** → the chat engine uses this theme's `default` template
   (`fxmanifest.lua:46`):
   ```
   default = '<p class="message-wrapper"><span class="author alt"><span>{0}</span></span><span><span>{1}</span></span></p>'
   ```
   That is the **system-card** style (`.message-wrapper`, `app.css:79-93`): dark pill,
   message icon (`.alt`), mantine `--font-family`. It is the *wrong visual family* — it
   does NOT use `.rp-line` (transparent + outlined bold Arial) like `/me /do /stats`.
   So `Status Check` shows as the icon "author" and `Committed suicide` as the body of a
   dark pill, instead of an outlined RP line.

2. **The `color = {255,0,0}` is silently dropped.** The theme's `default` template HTML
   has no color placeholder, so even the intended red never shows.

There is no bug in qbx_chat_theme's parsing; the message simply never opts into an
`rp:*` template, so it cannot match any `.rp-line` CSS.

**Exact identifiers:**
- Offending template id: `default` (fallback) → class `.message-wrapper`.
- Desired class family: `.rp-line` (new modifier `.rp-status`).
- Emit sites to retheme: the three `TriggerEvent('chat:addMessage', …)` calls listed in §2.

---

## 4) Precise fix plan

Minimal, arg-compatible: add one template + CSS to this theme, then add a single
`templateId` line at each of the three emit sites (args already match `{0}=label`,
`{1}=reason`).

### 4a. Add the template — `fxmanifest.lua`, inside `msgTemplates` (next to `pengu:stats`)
```lua
-- [Status Check] death/medical status line (qbx_medical, qbx_ambulancejob)
-- args: {0}=label ("Status Check")  {1}=reason ("Committed suicide" / "Bled out" / ...)
['rp:status'] = '<div class="rp-line rp-status"><span class="stag">[{0}]</span> {1}</div>',
```

### 4b. Add the CSS — `theme/app.css` (near the other `.rp-*` blocks, ~line 248)
```css
/* -- [Status Check] death / medical status line -- */
.rp-status        { color: #ff6b6b; }
.rp-status .stag  { color: #ff3b3b; font-weight: 700; }
```
(Optionally add `--c-status: #ff6b6b;` / `--c-status-tag: #ff3b3b;` to `:root` and
reference them, to match the existing `--c-*` convention.)

Result rendering: `[Status Check] Committed suicide` — transparent background, bold
outlined Arial, red — i.e. the same RP-line family as `/me`, `/do`, `/stats`.

### 4c. Retheme the three emit sites (add `templateId = 'rp:status'`)

These files are outside this resource (qbx_medical / qbx_ambulancejob), so the edits are
small and will need re-applying after those resources are updated (or fork/patch them).

- **`qbx_medical/client/damage/damage.lua:208`**
  ```lua
  TriggerEvent('chat:addMessage', {
      templateId = 'rp:status',
      multiline = false,
      args = { locale('info.status'), WEAPONS?[weaponHash]?.damagereason or 'Unknown' }
  })
  ```
- **`qbx_ambulancejob/client/job.lua:94`** and **`:102`** — same change: add
  `templateId = 'rp:status',` and (optionally) drop the now-unused `color = {255,0,0}`
  line (the red now comes from `.rp-status` CSS).

No arg reordering needed because the new template consumes `{0}`/`{1}` exactly as the
emits already pass them.

### Notes / alternatives
- If you also want a leading `[HH:MM:SS]` timestamp like the other RP lines, change the
  template to `'<div class="rp-line rp-status"><span class="ts">[{0}]</span> <span class="stag">[{1}]</span> {2}</div>'`
  and prepend `os.date('%H:%M:%S')` to `args` at each emit site (`os.date` is available
  client-side in FiveM). The minimal fix above intentionally avoids touching the args.
- Editing third-party resources is the only way to attach a `templateId`, because
  `chat:addMessage` is dispatched directly to the chat NUI; this theme cannot intercept
  a no-templateId message and re-skin it after the fact without overriding `chat:addMessage`.
- Leaving the genuine `default`/`print`/`join`/`quit` system cards as pills is correct —
  only the status/death line should move into the `.rp-line` family.
