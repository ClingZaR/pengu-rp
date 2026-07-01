# pengu_core PD Interaction System - Build Plan

Data-driven, DB-backed PD interaction points for PenguRP (qbx_core + ox_lib + oxmysql).
Generalises the existing hold-Alt mechanic in client/armory.lua into a typed point list
loaded from a DB table, with an owner-only placement command. ASCII only, luac clean.

--------------------------------------------------------------------------------
## 1. Investigation findings (verified against the live resources)

### 1a. qbx_police garage  ([qbx]/qbx_police/client/job.lua + config/client.lua)
- `config.authorizedVehicles` is keyed by GRADE LEVEL (0..4). Each value is a map of
  `spawnModel = 'Display Label'`, e.g. `police = 'Police Car 1'`, `sheriff = 'Sheriff Car 1'`.
  In this install grades 0-4 all have the SAME 8-vehicle list (police, police2, police3,
  police4, policeb, policet, sheriff, sheriff2). `config.whitelistedVehicles = {}` (empty).
- The garage menu does: `local authorizedVehicles = config.authorizedVehicles[grade.level]`,
  then `for veh, label in pairs(...)` -> ox_lib context option that calls `takeOutVehicle(veh)`.
- Spawn callback (server, qbx_police/server/main.lua:108), GLOBAL and cross-resource callable:
  `lib.callback.await('qbx_policejob:server:spawnVehicle', false, model, coords, plate, giveKeys, vehId)`
  Server-side it does `qbx.spawnVehicle{ model=..., spawnSource=coords, warp=GetPlayerPed(src) }`,
  sets the plate, and if `giveKeys == true` calls `qbx_vehiclekeys:GiveKeys`. Returns a netId.
  `coords` is a vec4 (x,y,z,heading). Plate pattern in qbx: `policePlatePrefix('LSPD') .. random`.
- Duty toggle (job.lua:427):
  ```lua
  function ToggleDuty()
      TriggerServerEvent('QBCore:ToggleDuty')
      TriggerServerEvent('police:server:UpdateCurrentCops')
  end
  ```
  `QBCore:ToggleDuty` is handled in qbx_core/server/events.lua:228 (confirmed). bcso and sasp
  exist as jobs in qbx_core/shared/jobs.lua (both job.type == 'leo', same as police).

  NOTE: pengu_core CANNOT `require` qbx_police's `config.client` (module scope is per-resource),
  so the vehicle list is MIRRORED into the pengu_core CONFIG below. The spawn callback IS global.

### 1b. ox_inventory shop open path  ([ox]/ox_inventory/modules/shops/server.lua)
- `lib.callback.register('ox_inventory:openShop', ...)` is the open path. The distance gate is:
  ```lua
  if type(shop.coords) == 'vector3' and #(GetEntityCoords(GetPlayerPed(source)) - shop.coords) > 10 then
      return
  end
  ```
  The gate ONLY runs when `shop.coords` is a `vector3`. If `shop.coords` is nil it is SKIPPED.
- How `shop.coords` gets set: a shop registered WITH a `locations` table is stored raw (no
  `.items`), so openShop calls `createShop(type, id)` which sets `coords = locations[id]` (a
  vector3) -> gate applies. `createShop` returns nil if `locations[id]` is nil, so "open with a
  nil-location id" does NOT work for a locations-based shop (it just fails the open).
- THE CLEAN BYPASS (no patching ox_inventory): register a shop with NO `locations`. In
  `registerShopType` the else-branch builds the shop with `items = properties.inventory`, `slots`,
  `groups`, and crucially NO `coords` field. In openShop, `shop.items` is truthy so `createShop`
  is skipped, `shop.coords` is nil so the vector3 gate is skipped, and `shop.groups` is still
  enforced via `server.hasGroup`. RegisterShop export confirmed at server.lua:117
  `exports('RegisterShop', ...)`.
- The existing PoliceArmoury (data/shops.lua:107) uses `groups = shared.police`. `shared.police`
  comes from convar `inventory:police` (default `["police","sheriff"]`); the cfg does NOT override
  it. Since pengu_core registers its OWN global shop it sets the group map explicitly (below) to
  cover police/bcso/sasp/sheriff.
- policelocker stash: registered by qbx_police/server/main.lua:596
  `exports.ox_inventory:RegisterStash('policelocker', 'Police Locker', 30, 100000, true)` -> opened
  with `exports.ox_inventory:openInventory('stash', { id = 'policelocker' })`. No location gate.

### 1c. Clothing  ([standalone]/illenium-appearance/game/util.lua)
- illenium does NOT export an "apply outfit preset" function. It exports per-component setters:
  `exports['illenium-appearance']:setPedComponent(ped, { component_id, drawable, texture })` and
  `setPedComponents(ped, components)`. Internally `setPedComponent` is literally
  `SetPedComponentVariation(ped, component_id, drawable, texture, 0)` (util.lua:300). There is also
  `setPedAppearance` / `setPlayerAppearance` for full appearance objects, and a job-outfit event
  `illenium-appearance:client:loadJobOutfit` (DB driven, not needed here).
- CONCLUSION: plain `SetPedComponentVariation(PlayerPedId(), comp, drawable, tex, 0)` applies AND
  visibly sticks for a temporary uniform/armor toggle (illenium only re-syncs saved appearance on
  respawn / model change / resource restart). We use SetPedComponentVariation directly (zero
  dependency). illenium's `setPedComponents` export is an equivalent fallback if ever needed.
- Body armor / vest is component 9 (freemode). `SetPedComponentVariation(ped,9,drawable,0,0)` plus
  `SetPedArmour(ped,100)` gives both the visible vest and the armor value.

### 1d. ACE check  (server.cfg:105-108)
- `add_ace identifier.fivem:19230951 / identifier.license:... / identifier.fivem:18393609
  pengu.placement allow` are bound DIRECTLY to the owner identifiers (NOT to group.admin).
- `IsPlayerAceAllowed(src, 'pengu.placement')` resolves the player's identifiers against the ace
  store, so it returns true ONLY for those owner identifiers. Confirmed correct for /pdloc gating.

### 1e. Why hold-Alt still reads (unchanged from armory.lua)
- ox_target uses SetNuiFocusKeepInput, so `IsControlPressed(0,19)` (Left Alt) keeps reading while
  the eye is up. The new points carry NO ox_target options, so there is no competing bind.

--------------------------------------------------------------------------------
## 2. DB schema

Created on resource start (CREATE TABLE IF NOT EXISTS), seeded only when empty.

```sql
CREATE TABLE IF NOT EXISTS pengu_pd_locations (
    id         INT AUTO_INCREMENT PRIMARY KEY,
    type       VARCHAR(24)  NOT NULL,
    label      VARCHAR(64)  NOT NULL DEFAULT '',
    x          FLOAT        NOT NULL,
    y          FLOAT        NOT NULL,
    z          FLOAT        NOT NULL,
    heading    FLOAT        NOT NULL DEFAULT 0.0,
    created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);
```

Seed rows (inserted only if `SELECT COUNT(*) == 0`), all heading 0.0:

| type     | label            | x        | y         | z      |
|----------|------------------|----------|-----------|--------|
| armory   | MRPD Armoury     | 453.21   | -980.03   | 30.68  |
| armory   | Paleto Armoury   | -443.37  | 6008.47   | 31.63  |
| locker   | MRPD Locker      | 449.80   | -987.00   | 30.84  |
| clothing | MRPD Wardrobe    | 461.40   | -981.60   | 30.70  |
| garage   | MRPD Garage      | 454.50   | -1017.00  | 28.40  |
| duty     | MRPD Duty        | 440.00   | -974.90   | 30.69  |

(MRPD-area guesses; the admin moves them live with /pdloc.)

--------------------------------------------------------------------------------
## 3. Point types and their hold-Alt action (all leo-only: job.type == 'leo')

| type     | hint label        | action on hold-Alt complete                                     |
|----------|-------------------|-----------------------------------------------------------------|
| armory   | Armoury           | open the pengu global armoury shop (no distance gate, see s.4)   |
| locker   | Locker            | `openInventory('stash', { id = 'policelocker' })`               |
| clothing | Police Wardrobe   | open ox_lib context "Police Wardrobe" (see s.5)                  |
| garage   | Police Garage     | open ox_lib vehicle menu for the player's grade (see s.6)        |
| duty     | Toggle Duty       | `ToggleDuty()` -> ToggleDuty + UpdateCurrentCops (see s.7)       |

Visuals are UNCHANGED from armory.lua: blue `DrawMarker(1,...)` cylinder, `[Hold Alt] <label>`
hint via DrawText, and the lavender (225,199,249) `DrawRect` progress bar; DRAW_DIST 12.0,
USE_DIST 1.8, HOLD_MS 1500, ALT control 19. Those helper functions move verbatim into client/pd.lua.

--------------------------------------------------------------------------------
## 4. Armory open method (the chosen bypass)

pengu_core SERVER registers a GLOBAL (no-location) shop on start, so opening it skips the vector3
distance gate while keeping the police group check:

```lua
-- server/pd.lua  (runs once on start)
exports.ox_inventory:RegisterShop('PenguArmoury', {
    name = 'Police Armoury',
    groups = { police = 0, bcso = 0, sasp = 0, sheriff = 0 }, -- enforced server-side, no distance
    inventory = {
        { name = 'WEAPON_PISTOL',       price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'WEAPON_STUNGUN',      price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'ammo-9',              price = 0 },
        { name = 'WEAPON_FLASHLIGHT',   price = 0 },
        { name = 'WEAPON_NIGHTSTICK',   price = 0 },
        { name = 'handcuffs',           price = 0 },
        { name = 'forensic_kit',        price = 0 },
        { name = 'fingerprint_scanner', price = 0 },
        { name = 'hydrogen_peroxide',   price = 0 },
        { name = 'evidence_box',        price = 0 },
        { name = 'WEAPON_CARBINERIFLE', price = 0, metadata = { registered = true, serial = 'POL' }, grade = 3 },
        { name = 'ammo-rifle',          price = 0, grade = 3 },
    },
    -- NO `locations` key on purpose -> registerShopType else-branch -> shop.items set, shop.coords nil
})
```

CLIENT opens it from wherever the point is (no id, no coords):
```lua
exports.ox_inventory:openInventory('shop', { type = 'PenguArmoury' })
```
Security kept: ox_inventory's `server.hasGroup` rejects non-police; the hold-Alt proximity + leo
check gate the trigger. The list above MIRRORS data/shops.lua PoliceArmoury (single tunable place
now lives in pengu_core; the old PoliceArmoury entry in shops.lua may stay for reference or be
trimmed - it is no longer used by the hold-Alt flow). `grade` slot rules still work because the
shop has `groups`.

--------------------------------------------------------------------------------
## 5. Clothing - "Police Wardrobe" context menu

`lib.registerContext{ id='pengu_wardrobe', title='Police Wardrobe', options={...} }` then
`lib.showContext('pengu_wardrobe')`. Options: Officer Uniform, SWAT, Body Armor, Remove Armor.

Gender detect: `GetEntityModel(PlayerPedId()) == GetHashKey('mp_m_freemode_01')` -> male, else female.

Apply = loop the preset and `SetPedComponentVariation(ped, comp, drawable, texture, 0)`.

CONFIG table at the TOP of client/pd.lua (clearly commented, easy to tune - these are reasonable
vanilla freemode police/tactical values; the admin refines them later):

```lua
-- ===================== CLOTHING PRESETS (tune these in-game) =====================
-- Freemode component ids: 3 arms/torso, 4 legs, 6 shoes, 7 accessory, 8 undershirt,
-- 9 body-armor/vest, 11 top/jacket. Each entry = { comp, drawable, texture }.
local WARDROBE = {
    male = { -- mp_m_freemode_01
        uniform = { -- Officer Uniform (patrol)
            { 8, 58, 0 },  -- undershirt
            { 3,  0, 0 },  -- arms/torso
            { 11, 55, 0 }, -- top: police shirt
            { 4, 35, 0 },  -- legs: police trousers
            { 6, 25, 0 },  -- shoes: boots
            { 7,  0, 0 },  -- accessory: none
            { 9,  0, 0 },  -- vest off for plain uniform
        },
        swat = { -- SWAT / tactical
            { 8, 15, 0 },  -- undershirt
            { 3, 11, 0 },  -- arms
            { 11, 38, 0 }, -- top: tactical
            { 4, 31, 0 },  -- legs: tactical trousers
            { 6, 24, 0 },  -- shoes: tactical boots
            { 7,  5, 0 },  -- accessory
            { 9, 16, 0 },  -- heavy vest
        },
        armorVest = { comp = 9, drawable = 1, texture = 0 }, -- visible police vest (Body Armor)
    },
    female = { -- mp_f_freemode_01
        uniform = {
            { 8, 35, 0 },
            { 3,  0, 0 },
            { 11, 48, 0 },
            { 4, 34, 0 },
            { 6, 25, 0 },
            { 7,  0, 0 },
            { 9,  0, 0 },
        },
        swat = {
            { 8, 14, 0 },
            { 3, 11, 0 },
            { 11, 35, 0 },
            { 4, 32, 0 },
            { 6, 25, 0 },
            { 7,  5, 0 },
            { 9, 17, 0 },
        },
        armorVest = { comp = 9, drawable = 1, texture = 0 },
    },
}
-- ================================================================================
```

Actions:
- Officer Uniform: apply `WARDROBE[gender].uniform`.
- SWAT: apply `WARDROBE[gender].swat`.
- Body Armor: `SetPedArmour(ped, 100)` AND
  `SetPedComponentVariation(ped, v.comp, v.drawable, v.texture, 0)` where v = `WARDROBE[gender].armorVest`.
- Remove Armor: `SetPedArmour(ped, 0)` AND `SetPedComponentVariation(ped, 9, 0, 0, 0)`.

(SetPedComponentVariation applies + sticks for a temporary toggle; no illenium call required.
 More granular customization comes later.)

--------------------------------------------------------------------------------
## 6. Garage approach (reuse qbx_police spawn callback)

Mirror the authorizedVehicles list into pengu_core CONFIG (top of client/pd.lua), keyed by grade,
then build an ox_lib context menu and spawn through the GLOBAL qbx callback. Plate uses the qbx
LSPD prefix style.

```lua
local POLICE_VEHICLES = { -- mirror of qbx_police config.authorizedVehicles (model = label)
    [0] = { police='Police Car 1', police2='Police Car 2', police3='Police Car 3', police4='Police Car 4',
            policeb='Police Car 5', policet='Police Car 6', sheriff='Sheriff Car 1', sheriff2='Sheriff Car 2' },
    -- grades 1..4 identical in this install; fall back to grade 0 if a level is missing.
}
```

```lua
local function openGarage(point)
    local grade = exports.qbx_core:GetPlayerData().job.grade.level
    local list  = POLICE_VEHICLES[grade] or POLICE_VEHICLES[0]
    local options = {}
    for model, label in pairs(list) do
        options[#options+1] = { title = label, onSelect = function() spawnPolice(model, point) end }
    end
    lib.registerContext({ id = 'pengu_pd_garage', title = 'Police Garage', options = options })
    lib.showContext('pengu_pd_garage')
end

local function spawnPolice(model, point)
    local coords = vec4(point.coords.x, point.coords.y, point.coords.z, point.heading or 0.0)
    local plate  = 'LSPD' .. tostring(math.random(1000, 9999))
    local netId  = lib.callback.await('qbx_policejob:server:spawnVehicle', false, model, coords, plate, true)
    -- callback warps the officer in + gives keys server-side; nothing else needed for a simple spawn.
end
```

Kept simple and functional (no impound/store logic; that stays in qbx_police). Spawn point and
heading come from the garage DB row, so moving the point with /pdloc moves the spawn.

--------------------------------------------------------------------------------
## 7. Duty + locker

```lua
-- duty
local function toggleDuty()
    TriggerServerEvent('QBCore:ToggleDuty')
    TriggerServerEvent('police:server:UpdateCurrentCops')
end
-- locker
local function openLocker()
    exports.ox_inventory:openInventory('stash', { id = 'policelocker' })
end
```
Mirrors qbx_police exactly; UpdateCurrentCops keeps the cop count in sync.

--------------------------------------------------------------------------------
## 8. Admin placement command + live sync

SERVER (server/pd.lua):
- On start: ensure table, seed if empty, register the PenguArmoury shop (s.4).
- `lib.callback.register('pengu_core:getPDLocations', function() ... end)` -> returns all rows as
  `{ id, type, label, x, y, z, heading }`.
- Broadcast helper: `TriggerClientEvent('pengu_core:pdLocationsUpdated', -1, rows)` after any change.
- `RegisterCommand('pdloc', function(src, args) ... end, false)` gated FIRST by
  `if not IsPlayerAceAllowed(src, 'pengu.placement') then return end`. Subcommands:
  - `add <type> [label words...]`: validate type in {armory,locker,clothing,garage,duty}; read
    `local ped = GetPlayerPed(src)`, `coords = GetEntityCoords(ped)`, `h = GetEntityHeading(ped)`
    (server-side reads work for the caller's ped); INSERT; notify caller; re-broadcast.
  - `remove <id>`: DELETE WHERE id = ?; notify; re-broadcast.
  - `list`: SELECT all; print `id | type | label | x,y,z` lines back to the caller
    (chat:addMessage or qbx_core Notify per line).
- All notifications to the caller use `exports.qbx_core:Notify(src, msg, type)`.

CLIENT (client/pd.lua):
- On load (and on `playerLoaded`): `local rows = lib.callback.await('pengu_core:getPDLocations', false)`
  then `rebuildPoints(rows)`.
- `RegisterNetEvent('pengu_core:pdLocationsUpdated', function(rows) rebuildPoints(rows) end)`.
- `rebuildPoints` converts rows into the in-memory POINTS list:
  `{ type=..., label=..., coords=vec3(x,y,z), heading=..., action=ACTIONS[type] }`.
- The single CreateThread loop (same structure as armory.lua) iterates POINTS, draws the marker
  within DRAW_DIST, and on hold-Alt-complete near a point calls `point.action(point)`.
  `ACTIONS = { armory=openArmoury, locker=openLocker, clothing=openWardrobe, garage=openGarage, duty=toggleDuty }`.
- No restart needed: any /pdloc change re-broadcasts and the client rebuilds POINTS live.

--------------------------------------------------------------------------------
## 9. File list + fxmanifest changes

NEW files:
- `client/pd.lua`  - CONFIG (WARDROBE, POLICE_VEHICLES), hold-Alt visuals (moved verbatim from
  armory.lua), POINTS rebuild from callback/broadcast, the 5 ACTIONS.
- `server/pd.lua`  - table create+seed, PenguArmoury RegisterShop, getPDLocations callback,
  pdLocationsUpdated broadcast, /pdloc command (ace-gated).

REMOVED from manifest:
- `client/armory.lua` is SUPERSEDED by client/pd.lua (armory becomes the 'armory' point type).
  Keep the file on disk for reference or delete it, but drop it from client_scripts to avoid
  duplicate markers.

fxmanifest.lua (final relevant blocks):
```lua
client_scripts {
    '@ox_lib/init.lua',
    'client/stats.lua',
    'client/hotkeys.lua',
    'client/cursor.lua',
    'client/actions.lua',
    'client/voice.lua',
    'client/pd.lua',          -- was client/armory.lua
}

server_scripts {
    '@ox_lib/init.lua',       -- add: server/pd.lua uses lib.callback + lib.print
    '@oxmysql/lib/MySQL.lua',
    'server/stats.lua',
    'server/pd.lua',          -- new
}
```
(`@ox_lib/init.lua` is added to server_scripts so the server can use lib.callback.register.)

--------------------------------------------------------------------------------
## 10. Constraints honored
- Existing hold-Alt visuals kept byte-for-byte (marker + lavender DrawRect bar, Left Alt = 19).
- ASCII only, no em/en dashes.
- Self-contained: only depends on qbx_core, ox_lib, ox_inventory, oxmysql, and the GLOBAL qbx
  spawn callback (all already present). No other pengu_core file is touched except fxmanifest.lua.
- Security: leo-only client gate + ox_inventory group enforcement (armory) + ace gate (/pdloc).
- Designed to luac clean; no patching of ox_inventory or qbx_police required.
