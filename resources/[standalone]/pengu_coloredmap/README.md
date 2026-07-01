# pengu_coloredmap

Colored GTA **pause map + gameplay radar** with **street labels** (postal + street-name atlas).

**This is [NeenGame/neen-atlasmap](https://github.com/NeenGame/neen-atlasmap)** (MIT), the
`map-postalmap-streetname` variant, installed verbatim. It is a true FiveM stream resource maintained
for current game builds — it replaced an earlier attempt that wrapped a GTA 1.69 single-player `.oiv`
pack, which flickered, lagged, broke on zoom, and left the radar grey on this build-3751 server.

## Why this one works (and the OIV didn't)
- **Radar color** comes from the streamed `stream/ytd/minimap_*.ytd` + `minimap_sea_*.ytd` tiles (real,
  not stubs). The `.ydd` are intentionally tiny stubs that blank the HD geometry so the pause map shows
  the flat colored atlas at every zoom (that's the "atlas" look, and it's what avoids the zoom-break).
- **Zoom + radar binding** is done at runtime by `client.lua` via `SetMapZoomDataLevel(0..8)` and
  `SetRadarZoom(1100)` (re-applied every 10s). This is the supported replacement for `mapzoomdata.meta`,
  which **FiveM cannot stream**. (FiveM also ignores `minimap.ymt` entirely — neither is used here.)
- Current Scaleform (`minimap.gfx` build 3570; geometry unchanged 3570->3751, so it works on 3751).

## Coexists with the square minimap
`pengu_hud` makes the radar square purely via mask/clip/position (`SetMinimapComponentPosition`,
`SetMinimapClipType`, `AddReplaceTexture radarmasksm->squaremap`). It never touches map color or zoom,
and no other resource calls `SetRadarZoom`/`SetMapZoomDataLevel` — so this resource owns color+zoom,
pengu_hud owns the shape. They don't conflict.

## Apply
```
refresh
restart pengu_coloredmap
```
then **fully disconnect and reconnect** (streamed map assets load on a fresh connect). You should get a
colored pause map AND a colored square radar, both with street names. If the radar is briefly grey on
spawn, the 10s `SetRadarZoom` loop self-corrects.

## Notes
- Auto-starts via `ensure [standalone]` in server.cfg — no cfg edit needed.
- Running Cayo Perico's IPL? Set `EnableCayoMiniMap = true` at the top of `client.lua`.
- Do NOT also run a second map/minimap resource (e.g. re-enabling qbx_hud's minimap) — one owner only,
  or the radar flickers/greys again.
- Source kept verbatim (incl. LICENSE). To update, re-pull a newer neen-atlasmap release for your build.
