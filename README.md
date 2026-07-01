# PenguRP

A heavy-RP FiveM server built on the **Qbox (qbx_core) + ox stack**. All custom gameplay systems live in the `resources/[local]/pengu_*` folders. Third-party resources that required editing are patched via the `overrides/` folder.

---

## Tech Stack

| Layer | Resource |
|---|---|
| Core framework | qbx_core (Qbox) |
| Inventory | ox_inventory |
| Target / interact | ox_target |
| Door locks | ox_doorlock |
| MySQL | oxmysql |
| UI library | ox_lib |
| Voice | pma-voice |
| Phone | npwd |
| Appearance | illenium-appearance |
| MDT | pengu_mdt (custom) + ps-mdt (full reports) |
| Dispatch | ps-dispatch |
| Prison | xt-prison |
| Colored map | neen-atlasmap (pengu_coloredmap) |

---

## Prerequisites

- Linux VPS — Ubuntu 22.04 LTS recommended
- **FiveM server license key** from [keymaster.fivem.net](https://keymaster.fivem.net)
- **txAdmin** (bundled with the FiveM server artifact)
- **MariaDB 10.6+** or MySQL 8+
- Git, curl, wget

---

## Installation

### 1. Install FiveM + txAdmin

Follow the official [FiveM Linux server guide](https://docs.fivem.net/docs/server-manual/setting-up-a-server-txadmin/).

### 2. Deploy the Qbox Base via txAdmin

In txAdmin:
1. Go to **Setup** → **Recipe Deployer**
2. Select the **Qbox Project** recipe
3. Complete the deployer — this installs qbx_core, ox stack, all [qbx] and [ox] resources, and seeds the base database

> Build target: `sv_enforceGameBuild 3751` (already set in `server.cfg`)

### 3. Install Additional Third-Party Resources

Download and place each resource into `resources/` under the appropriate category folder. All are free / open source.

#### `[standalone]` resources

| Resource | Source |
|---|---|
| `ps-mdt` v3.1.2 | [github.com/Project-Sloth/ps-mdt](https://github.com/Project-Sloth/ps-mdt) |
| `ps-dispatch` | [github.com/Project-Sloth/ps-dispatch](https://github.com/Project-Sloth/ps-dispatch) |
| `ps_lib` | [github.com/Project-Sloth/ps_lib](https://github.com/Project-Sloth/ps_lib) |
| `PolyZone` | [github.com/mkafrin/PolyZone](https://github.com/mkafrin/PolyZone) |
| `xt-prison` | [github.com/XenoTech-Inc/xt-prison](https://github.com/XenoTech-Inc/xt-prison) |
| `scully_emotemenu` | [github.com/Scullyy/scully_emotemenu](https://github.com/Scullyy/scully_emotemenu) |
| `illenium-appearance` | [github.com/iLLeniumStudios/illenium-appearance](https://github.com/iLLeniumStudios/illenium-appearance) |
| `Renewed-Banking` | [github.com/Renewed-Scripts/Renewed-Banking](https://github.com/Renewed-Scripts/Renewed-Banking) |
| `MugShotBase64` | [github.com/TayMcKenzieNZ/MugShotBase64](https://github.com/TayMcKenzieNZ/MugShotBase64) |
| `noob-evidences` v1.2.3 | [github.com/thenoobprogrammer34/noob-evidences](https://github.com/thenoobprogrammer34/noob-evidences) |

#### `[voice]` resources

| Resource | Source |
|---|---|
| `pma-voice` | [github.com/AvarianKnight/pma-voice](https://github.com/AvarianKnight/pma-voice) |
| `mm_radio` | [github.com/MartMoest/mm_radio](https://github.com/MartMoest/mm_radio) |

#### `[npwd]` + phone

| Resource | Source |
|---|---|
| `npwd` | [github.com/project-error/npwd](https://github.com/project-error/npwd) |
| `qbx_npwd` | [github.com/Qbox-project/qbx_npwd](https://github.com/Qbox-project/qbx_npwd) |

#### Screenshot + misc

| Resource | Source / Note |
|---|---|
| `screenshot-basic` | Not currently installed — add if you want MDT mugshot uploads via FiveManage |
| `qbx_smallresources` | Included in Qbox recipe (hunger/thirst/stress tracking) |

### 4. Copy Custom Resources from This Repo

```bash
# from your clone of this repo:
cp -r resources/[local]/   /path/to/resources/
cp -r resources/[standalone]/pengu_coloredmap  /path/to/resources/[standalone]/
cp -r resources/[qbx]/qbx_chat_theme          /path/to/resources/[qbx]/
```

### 5. Apply Third-Party Overrides

Several 3rd-party resource files have been patched (jail wiring, chat templates, CSS reskin, etc.).
The patched versions live in `overrides/` mirroring the resource path.

```bash
bash setup.sh /path/to/your/resources
```

Or manually copy each file — `overrides/[foo]/bar/file.lua` replaces `resources/[foo]/bar/file.lua`.

**What each override patches:**

| File | What changed |
|---|---|
| `[ox]/ox_inventory/data/items.lua` | Added all PenguRP items (chop parts, drug items, evidence kit, cola, medikit, etc.) |
| `[ox]/ox_inventory/data/shops.lua` | Added PoliceArmoury (ALT-hold target shop at MRPD + Paleto) and PenguArmoury (data-driven PD armoury) |
| `[ox]/ox_inventory/data/weapons.lua` | Ammo and attachment definitions |
| `[ox]/ox_inventory/web/images/WEAPON_*.png` | All 114 weapon icons replaced with official GTA V weapon-wheel HUD icons (sourced from wiki.rage.mp) |
| `[ox]/ox_target/web/*` | Added optional `holdTime` opt-in feature (hold-to-interact ring on the eye cursor) — dormant unless a target explicitly passes `holdTime` |
| `[ox]/ox_doorlock/sql/pengu_mrpd.sql` | 12 MRPD door entries (front entrance + interior locked doors for police/bcso/sasp) |
| `[standalone]/ps-mdt/server/backend/sentencing.lua` | Wired "Send to Jail" button to `exports['xt-prison']:JailPlayerById` instead of the dead QB event |
| `[standalone]/xt-prison/server/sv_commands.lua` | Added `JailPlayerById` export; renamed built-in `/jail` to `/xtjail` so `pengu_mdt` owns `/jail` |
| `[standalone]/ps-dispatch/html/index.css` | Glass theme reskin to match PenguRP HUD (override block appended — JS bundle untouched) |
| `[qbx]/qbx_core/server/events.lua` | Duty toggle notifications routed to `pengu:admin` chat template |
| `[qbx]/qbx_medical/client/damage/damage.lua` | Death/revive status lines use `rp:status` chat template |
| `[qbx]/qbx_ambulancejob/client/job.lua` | Same — nil-safe `WEAPONS?[hash]?.damagereason` guard |

> **Warning:** If you ever run `npm run build` inside `ps-dispatch/ui/`, it will wipe the override block in `index.css`. Re-apply `overrides/[standalone]/ps-dispatch/html/index.css` afterward.

### 6. Import SQL

Run these in order in your database client (HeidiSQL / DBeaver / mysql CLI):

```sql
-- 1. Base framework SQL (already done by the Qbox recipe deployer)

-- 2. Any 3rd-party resource SQLs that weren't auto-applied
--    (check each resource's README — most auto-create tables on first boot)

-- 3. PenguRP custom seeds
SOURCE sql/pengu_mrpd.sql;    -- MRPD door locks (12 rows into ox_doorlock)
SOURCE sql/penal_seed.sql;    -- 161 penal codes into mdt_penal_codes (for ps-mdt /mdtfull)
```

All `pengu_*` resource tables are created automatically on first boot via `MySQL.query.await(CREATE TABLE IF NOT EXISTS ...)`.

### 7. Configure server.cfg

Edit `server.cfg` and replace every `CHANGEME` field:

```cfg
sv_licenseKey "CHANGEME_GET_FROM_KEYMASTER_FIVEM_NET"
set mysql_connection_string "mysql://DB_USER:DB_PASSWORD@localhost/DB_NAME?charset=utf8mb4"
```

Get your license key at [keymaster.fivem.net](https://keymaster.fivem.net).

### 8. Admin Permissions Setup

In `server.cfg`, replace the placeholder admin identifiers with your own:

```cfg
add_principal identifier.fivem:YOUR_FIVEM_ID    group.admin
add_principal identifier.license:YOUR_LICENSE_HASH group.admin
```

Find your identifiers in the txAdmin live console — they appear when you connect:
```
Player "YourName" connecting. Identifiers: fivem:12345678, license:abc123...
```

Also update every `pengu.*` ace block:
```cfg
add_ace identifier.fivem:YOUR_FIVEM_ID pengu.placement allow
# ... (one block per pengu.* ace — see server.cfg)
```

### 9. voice.cfg

Create `voice.cfg` next to `server.cfg` (referenced by `exec voice.cfg`):

```cfg
setr voice_enableProximityCycle true
setr voice_defaultCycle "1,3,9"
setr voice_defaultMode 1
setr voice_syncData true
```

### 10. ox.cfg

Create `ox.cfg` next to `server.cfg` (referenced by `exec ox.cfg`):

```cfg
setr inventory:slots 50
setr inventory:weight 30000
setr inventory:give true
setr inventory:drop true
setr inventory:hotkeys true
```

---

## First Boot Checklist

After starting the server for the first time:

- [ ] Connect and confirm you have `group.admin` (txAdmin panel should show your rank)
- [ ] Run `/aduty` to enter admin duty (required for all placement commands)
- [ ] Run `/turflist` — should say "no zones" (expected — you place them)
- [ ] Run `/dealerlist` — should say "no dealers placed" (expected)
- [ ] Run `/lablist` — should say "no labs" (expected)
- [ ] Verify the MRPD doors lock: go to Mission Row PD front door — should be open to public; interior doors should require police job
- [ ] Confirm MDT opens with `/mdt` (on-duty leo) and `/mdtfull` (full ps-mdt)
- [ ] Restart `ox_doorlock` after MRPD SQL import: `restart ox_doorlock`
- [ ] Check `restart pengu_turf` runs clean (no BOOT FAILED in console)

---

## Custom Resource Reference

All 16 custom resources live in `resources/[local]/`. They are all luac-clean and ASCII-only.

### `pengu_core`
The central resource. Handles:
- PD interaction system (armory, locker, clothing, garage, duty points via `/pdloc add|remove|list`)
- F1 keybind menu, F6 free cursor, U voice-range cycle
- Faction system (`/faction`, `/factionlock`) — whitelist gates for PD/EMS
- Marriage system (`/marry`, `/divorce`)
- Siren hotkeys (Q/E for leo air horn)
- `/stats` → chat, jail teleport helpers
- `pengu:admin` and `rp:status` chat templates (also patched into qbx_chat_theme)
- Off-duty civ clothing restore on clock-out

### `pengu_hud`
Custom glass HUD:
- Status bars (hunger, thirst, stress, oxygen, stamina — hidden when normal)
- Voice activity indicator (pma-voice native `MumbleIsPlayerTalking`)
- Speedometer with engine light, seatbelt warning, fuel gauge
- Square minimap raised left of HUD
- F7 settings panel

### `pengu_mdt`
Simplified police MDT (the day-to-day tool, replaces ps-mdt for quick checks):
- 8 tabs: Dashboard/Active Units, Person Search, Vehicle Search, Arrest Calculator, BOLOs, Warrants, Reports, Cameras
- No citizenid exposed in UI (anti-metagaming — all by name)
- `/jail [playerid]` — proximity-gated to DOC or MRPD cells, sums outstanding charges, runs xt-prison
- Charge placement stores `status='outstanding'`; Warrants tab shows online players with outstanding charges
- `/mdt` and `F11` to open; LEO + on-duty only
- Full 161-charge State of San Andreas penal code (`shared/penalcode.lua`)

### `pengu_traffic`
Traffic enforcement for LEO:
- Radar gun (speed checks)
- Spike strips
- Traffic camera fines (server-authoritative: reporter's own plate + must match a named camera location)

### `pengu_gangs`
Gang progression system:
- 6 gangs: lostmc, ballas, vagos, cartel, families, triads
- Levels 1–8 with perks (maxZones, repMultiplier, etc.)
- Criminal XP system feeds into gang rep
- `/gangstat`, `/ganginfo`
- Admin: `/gangrep`, `/ganglevel`, `/gangpenalty`, `/gangreset`

### `pengu_turf`
Block-based territory control:
- Admin places rectangular CORE bases (`/turf core <gang>`) and contested zones (`/turf add <key> [label]`)
- World auto-expands via 80m grid cells when gangs tag walls or work dealers on open ground
- Influence sources: **graffiti tags** (spraycan item) + **controlled dealers** (from pengu_dealers)
- Organic expansion capped by gang level `maxZones`
- Per-zone perks: drug_bonus, import_discount, crate_speed, rep_mult, stash (safehouse)
- Map renders as gang-colored rectangle blips; enter-notification on zone border cross
- Admin: `/turf mark|add|core|remove|setcore|setperk|setowner|reset|list|here`

### `pengu_drugs`
Drug production system:
- **Weed field** (`weed_field`): respawning plant nodes, harvest `weed_og-kush`
- **Coca field** (`coca_field`): respawning nodes, harvest `coca_leaf`
- **Weed Press** lab: processes `weed_og-kush` → `weed_brick`
- **Cocaine** lab: `coca_leaf` → `coke_brick`
- **Meth Supply + Meth** labs: full chain
- Labs placed via `/labadd <type> <group> [label]` (admin, on /aduty)
- Sale bonus inside controlled turf (`Config.saleBonusPct`)

### `pengu_launder`
Dirty money laundering:
- Laundromats placed via `/washloc add|remove|list`
- Wash cycles, rival rob mechanic, police detection risk

### `pengu_chopshop`
Chop shop economy:
- Randomized **wanted car list** (refreshes hourly), published to GlobalState
- Strip a wanted car at a chop point → random 3–5 part types (`chop_*` items)
- Parts carry source-car provenance in metadata — mechanic dealer only buys from current wanted list
- Admin: `/choploc add|remove|list`

### `pengu_dealers`
Illegal dealer NPC system:
- 6 dealer types: `mechanic`, `drug_dealer`, `doctor`, `weapons`, `armor`, `general`
- Each dealer tracks gang **influence** (0–100); controlling gang (≥80, strict highest) projects turf
- Influence decays every 10 min — must keep working the dealer
- Standing shown inside dealer menu (crown on controller)
- **Gang outfit system**: `/gangoutfit set <gang> <type> <component> <drawable> [texture]` — controlled dealer peds wear gang clothing. Live re-skins on takeover via GlobalState bags
- Admin: `/dealeradd`, `/dealerremove`, `/dealerlist`, `/dealerinfluence`, `/gangoutfit`

### `pengu_blackmarket`
Weapon import system:
- Arms dealer (type `weapons` in pengu_dealers) is the storefront
- Ordering costs dirty money + gang level gate → spawns a **crate** at a random drop point
- Player picks up crate (carry animation), drops it with `/dropcrate`, pries open with crowbar
- Rival gangs can **intercept** crates (2-step server-authoritative claim + timer)
- Admin test commands: `/spawntestcrate`, `/givecrowbar`, `/giveblackmoney`, `/clearcrates`

### `pengu_jobs`
Civilian jobs:
- Job locations placed via `/jobloc add|remove|list`
- Supports multiple legal job types with interaction points

### `pengu_business`
Player-owned business system:
- Businesses placed via `/bizloc add|remove|list`
- Ownership transfer, revenue tracking

### `pengu_prison`
Prison labor system (wraps xt-prison):
- Labor tasks inside Bolingbroke
- Time reduction for completing labor

### `pengu_fire`
Fire department system:
- Fire incidents, equipment, dispatch integration

### `pengu_xp`
Experience point system:
- Categories: `criminal`, `drugs`, `civic`
- Feeds into pengu_gangs rep accumulation
- `exports.pengu_xp:Award(src, category, amount)`

---

## Admin Commands Quick Reference

All placement commands require `/aduty` (admin duty) first.

### PD System (`pengu_core`)
| Command | Description |
|---|---|
| `/pdloc add <type> [label]` | Place a PD interaction point (armory/locker/clothing/garage/duty) |
| `/pdloc remove <id>` | Remove a PD point |
| `/pdloc list` | List all PD points |

### Turf (`pengu_turf`)
| Command | Description |
|---|---|
| `/turf core <gang> [label]` | Drop a permanent gang HQ block at your feet |
| `/turf mark` → walk → `/turf add <key> [label]` | Place a rectangular contested zone (mark corner A, walk to corner B) |
| `/turf remove <key>` | Remove a zone |
| `/turf setperk <key> <perk>` | Assign a perk to a zone |
| `/turf list` / `/turflist` | List all zones |
| `/turf here` | Show what zone you're standing in |
| `/turf reset <key>` | Reset a zone's influence to neutral |

### Dealers (`pengu_dealers`)
| Command | Description |
|---|---|
| `/dealeradd <type> [label]` | Place a dealer ped at your position |
| `/dealerremove <id>` | Remove a dealer |
| `/dealerlist` | List all dealers |
| `/dealerinfluence <gang>` | Show a gang's influence across all dealers |
| `/gangoutfit set <gang> <type> <comp> <draw> [tex]` | Set gang clothing on controlled dealer peds |
| `/gangoutfit clear <gang> [type]` | Remove gang outfit config |
| `/gangoutfit list [gang]` | Show configured outfits |

### Drug Labs (`pengu_drugs`)
| Command | Description |
|---|---|
| `/labadd <type> <group> [label]` | Add a lab/field interaction point to a named group |
| `/labenable <group>` | Enable a lab group |
| `/labdisable <group>` | Disable a lab group (props stay, shows as closed) |
| `/labremove <id>` | Remove a single lab point |
| `/lablist` | List all labs |

### Gang Management (`pengu_gangs`)
| Command | Description |
|---|---|
| `/gangrep <gang> <amount>` | Award/deduct gang rep |
| `/ganglevel <gang> <level>` | Force-set a gang's level |
| `/gangpenalty <gang> <amount>` | Apply a rep penalty |
| `/gangreset <gang>` | Wipe a gang's rep and level |

### MDT (`pengu_mdt`)
| Command | Description |
|---|---|
| `/mdt` or `F11` | Open the simplified MDT (on-duty LEO only) |
| `/mdtfull` | Open full ps-mdt (reports, warrants, evidence, roster) |
| `/jail <playerid>` | Imprison a player (must be within 50m of DOC or MRPD cells) |

### Chop Shop (`pengu_chopshop`)
| Command | Description |
|---|---|
| `/choploc add [label]` | Place a chop shop interaction point |
| `/choploc remove <id>` | Remove a chop point |
| `/choploc list` | List all chop points |

### Laundromat (`pengu_launder`)
| Command | Description |
|---|---|
| `/washloc add [label]` | Place a laundromat |
| `/washloc remove <id>` | Remove a laundromat |
| `/washloc list` | List all laundromats |

---

## Gear/Outfit Component Reference (for `/gangoutfit`)

When setting gang dealer outfits, use these GTA V ped component IDs:

| ID | Component |
|---|---|
| 1 | Mask / face covering / bandana |
| 3 | Torso / arms (must match top) |
| 7 | Accessories / neck chain |
| 8 | Undershirt |
| 11 | **Top / jacket** ← the main one |

**Tips by dealer type:**
- `drug_dealer` (`g_m_y_lost_01`), `weapons` (`g_m_m_armboss_01`), `armor`, `general` — use **component 11** (top/jacket)
- `mechanic` (`s_m_y_xmech_01`) wears overalls — try **component 8** (undershirt) or **component 1** (face bandana) instead
- `doctor` (`s_m_m_doctor_01`) — leave unset (neutral role). Use **component 7** (accessory) if you want something subtle

To find drawable IDs: use a ped component browser in-game or check [forge.plebmasters.de/clothingdb](https://forge.plebmasters.de/clothingdb).

---

## Key Config Files

| File | Purpose |
|---|---|
| `server.cfg` | All convars, ensures, ace permissions |
| `resources/[local]/pengu_turf/shared/config.lua` | Influence rates, decay, grid size, gang colours |
| `resources/[local]/pengu_gangs/shared/config.lua` | Gang levels, rep thresholds, perks |
| `resources/[local]/pengu_dealers/shared/config.lua` | Dealer influence thresholds, decay, item prices |
| `resources/[local]/pengu_chopshop/shared/config.lua` | Wanted car refresh rate, parts per chop, prices |
| `resources/[local]/pengu_blackmarket/shared/config.lua` | Weapon catalog, crate drop locations, prices |
| `resources/[local]/pengu_mdt/shared/penalcode.lua` | Full 161-charge penal code |
| `resources/[local]/pengu_hud/shared/config.lua` | HUD position, colours |

---

## Notes

- **ox_inventory weapon icons** are the official GTA V HUD silhouettes sourced from wiki.rage.mp/wiki/Weapons. 114 `WEAPON_*.png` files in `overrides/[ox]/ox_inventory/web/images/`. The 9 remaining custom RP items (handcuffs, license, etc.) were not on the wiki and keep their original icons.
- **ps-dispatch** CSS override is appended to `html/index.css`. Never run `npm run build` inside `ps-dispatch/ui/` without re-applying the override after.
- **ox_target holdTime ring** in the overrides is dormant (opt-in per target). It only activates if a target passes `holdTime = <ms>`.
- **xt-prison** has its built-in `/jail` renamed to `/xtjail` — `pengu_mdt` owns `/jail`.
- **qbx_hud** is stopped in `server.cfg` — `pengu_hud` replaces it entirely. Do not re-ensure qbx_hud.
- **qbx_spawn** is stopped — qbx_core handles spawn natively (last location / default spawn, no menu).

---

## License

Private — all rights reserved. Not for public distribution.
