# BOLO Redesign - precise change list (NUI only)

Scope: html/app.js, html/index.html, html/style.css ONLY.
Server (server/main.lua) is KEPT AS-IS. Contract confirmed:
- getBolos -> items[] where each item has `images` (array of validated http(s) links).
- createBolo accepts `data.images` (array), trims, requires `^https?://`, cap 8, <=512 chars.
- cancelBolo unchanged. Callback names getBolos / createBolo / cancelBolo are NOT renamed.

Constraints honored: glass/lavender theme + stroke SVG icons kept; NO citizenid touched;
ASCII only (no em/en dashes - verified 0 in repo, keep 0); NUI focus logic untouched;
lightbox Esc still closes the image first; `node --check html/app.js` must stay clean.

================================================================
INVESTIGATION FINDINGS (current state, verified)
================================================================

(a) WHERE the bolo-to-bolo arrows / boloFocus live (TO REMOVE)
  app.js:
    - state.boloCount (line 41), state.boloFocus (line 42).
    - loadBolos(): `state.boloCount = items.length` + `state.boloFocus = 0` (lines 626-627);
      `updateBoloStep()` calls (lines 630 and 676).
    - focusBolo(dir) (lines 707-715) - steps the focused card, adds `.focused`, scrollIntoView.
    - updateBoloStep() (lines 716-720) - writes `#bolo-step-index` text.
    - keydown global nav, "section 4 / BOLOs tab" block (lines 1067-1072) - Left/Right -> focusBolo.
    - init(): `$('#bolo-prev')` and `$('#bolo-next')` wiring to focusBolo (lines 1174-1175).
  index.html:
    - `.bolo-stepper` block: #bolo-prev, #bolo-step-index, #bolo-next (lines 289-297).
  style.css:
    - `.bolo-stepper` (478), `.bolo-stepper .cam-ov-index` (479), `.bolo-card.focused` (480),
      plus the comment header on line 477.
  NOTE: `.cam-ov-index` (base rule line 601) and `.tnum` are SHARED with the camera overlay
  (#cam-ov-index, index.html 471). Remove ONLY the `.bolo-stepper` override, keep the base class.

(b) WHY "add link" is broken (traced end to end)
  The chain is actually WIRED in the current REDESIGN2 file:
    - HTML container `#bolo-images` (index.html 323) starts empty; button `#bolo-add-link` (324).
    - addBoloLinkRow(value) (app.js 680-694) builds a `.link-row` = `.bolo-link` input +
      `.link-del` remove button, binds the per-row remove (auto-reseeds one row if emptied).
    - resetBoloLinks() (695-700) clears and seeds ONE row; called in init at line 1176.
    - Add listener bound in init: `$('#bolo-add-link').addEventListener('click', () => addBoloLinkRow())` (1173).
    - Submit collects: boloLinkValues() (701-705) reads `#bolo-images .bolo-link`, trims, filters
      `^https?://`; createBolo() (745-764) sends them as `images` (line 749/752).
  Root-cause defect (structural, the thing to fix): the rows container, every per-row remove "x",
  AND the "Add link" button are all nested inside a single `<label>Image links (optional)</label>`
  (index.html 322-328). A `<label>` with no `for` is implicitly bound to its FIRST labelable
  descendant (the first `.bolo-link` input), so clicks on the label caption/padding forward focus
  to that input, and wrapping interactive controls (the add button + remove buttons) inside a label
  is a known footgun that makes the add/remove UX unreliable. The fix is to take the rows + add
  button OUT of the `<label>` (use a plain caption span) and harden the JS:
    - Guarantee exactly one initial row (keep resetBoloLinks in init).
    - Use event DELEGATION for "remove" on `#bolo-images` so dynamically created rows can never
      desync from their listener.
    - Tighten the SUBMIT collector to https-only (`^https://`) per the feedback (placeholder already
      says "https://..."). Server still accepts http(s), so this is a safe client tightening.

(c) HOW images render today + WHY height varies
  loadBolos() builds a `.bolo-gallery` (app.js 640-647): one `.bolo-thumb` button PER image, each
  thumb is `aspect-ratio:16/9` inside a grid `repeat(auto-fit, minmax(110px,1fr))` (style.css
  462-475). So the media block height = (number of thumb rows) x thumb height: 1 image = 1 row,
  3-5 images = 2-3 rows. The media area therefore grows with image COUNT, pushing `.bolo-desc` down
  and making cards different heights. Per-thumb onerror swaps the img -> `.thumb-ph` (app.js 668).
  Leftover: `.bolo-media` CSS (style.css 449-454) is a fixed 16/9 box with object-fit:cover but is
  NOT used by the current render (render uses `.bolo-gallery`). The redesign revives the single
  fixed `.bolo-media` box and drops the multi-thumb grid.

(d) LIGHTBOX wiring to PRESERVE (do not touch the behavior)
  - state.lightbox { images, index } (app.js 40).
  - isLightboxOpen (723), renderLightbox (724-735), openLightbox(images,index) (736-741),
    closeLightbox (742), lightboxStep (743).
  - Escape handler closes the image FIRST: `if (isLightboxOpen()) { closeLightbox(); return; }` (185).
  - Global keydown: when open, Left/Right call lightboxStep (1056-1061).
  - init wiring: #lb-close, #lb-prev, #lb-next, and backdrop mousedown-to-close (1179-1182).
  - index.html #lightbox node: #lb-close, #lb-prev, #lb-img, #lb-next, #lb-index (480-492).
  - style.css `.lightbox`/`.lb-img`/`.lb-nav`/`.lb-prev`/`.lb-next`/`.lb-close`/`.lb-index` (485-514).
  Only the OPEN trigger changes: the per-card image click calls openLightbox(thisBoloImgs, currentIdx).

================================================================
CHANGE LIST
================================================================

----- html/index.html -----

1. REMOVE the page-level BOLO stepper (lines 289-297): delete the whole
   `<div class="bolo-stepper"> ... #bolo-prev ... #bolo-step-index ... #bolo-next ... </div>`.
   Leave #bolo-refresh and #bolo-new-btn in `.head-actions`.

2. FIX add-link: replace the `<label>` wrapper (lines 322-328) so the rows + add button are NOT
   inside a label:
     FROM:
       <label>Image links (optional)
         <div id="bolo-images" class="link-rows"></div>
         <button type="button" id="bolo-add-link" class="btn-ghost small link-add"> ...Add link</button>
       </label>
     TO:
       <div class="link-field">
         <span class="link-cap">Image links (optional)</span>
         <div id="bolo-images" class="link-rows"></div>
         <button type="button" id="bolo-add-link" class="btn-ghost small link-add">
           <svg class="ic" viewBox="0 0 24 24" width="14" height="14"><path d="M12 5v14M5 12h14"/></svg>
           Add link
         </button>
       </div>
   (Use a NEW wrapper class `.link-field` - do NOT reuse the existing `.field` class, which is used
   by the person/vehicle result rows.)

3. KEEP `#bolo-list` (now just a scrollable grid of cards, line 338) and the entire #lightbox node
   (480-492) unchanged.

----- html/style.css -----

4. REMOVE the stepper/focus rules (lines 477-480): `.bolo-stepper`, `.bolo-stepper .cam-ov-index`,
   `.bolo-card.focused`, and the line-477 comment. Keep base `.cam-ov-index` (601) - shared by cameras.

5. REPLACE the multi-thumb gallery rules (lines 462-475: `.bolo-gallery`, `.bolo-thumb`,
   `.bolo-thumb:hover`, `.bolo-thumb img`, `.thumb-ph`) with the fixed single-image media box +
   inline nav:
       .bolo-media{ position:relative; width:100%; aspect-ratio:16/9; overflow:hidden;
                    background:rgba(255,255,255,.03); border-bottom:1px solid var(--hairline); }
       .bolo-media img{ width:100%; height:100%; object-fit:cover; display:block; cursor:zoom-in; }
       .bolo-img-ph{ position:absolute; inset:0; display:flex; align-items:center; justify-content:center;
                     color:var(--deco); }
       .bolo-img-nav{ position:absolute; top:50%; transform:translateY(-50%);
                      width:30px; height:30px; border-radius:50%; display:grid; place-items:center;
                      cursor:pointer; color:#fff; background:rgba(16,16,24,.62);
                      border:1px solid var(--glass-border); transition:.15s; }
       .bolo-img-nav:hover{ border-color:var(--accent); color:var(--accent); }
       .bolo-img-nav.prev{ left:8px; }
       .bolo-img-nav.next{ right:8px; }
       .bolo-img-count{ position:absolute; bottom:8px; right:8px;
                        font-family:var(--mono); font-size:11px; color:var(--text-2);
                        background:rgba(16,16,24,.62); border:1px solid var(--glass-border);
                        padding:2px 8px; border-radius:12px; }
   (The old `.bolo-media` rule on lines 449-454 is superseded by the one above; delete the old one to
   avoid duplication. If line 661 references `.bolo-media .media-ph span`, retarget it to
   `.bolo-img-ph span` or drop it.)

6. ADD the add-link field caption styles next to `.link-rows` (after line 551):
       .link-field{ display:flex; flex-direction:column; gap:6px; }
       .link-cap{ font-size:10.5px; letter-spacing:1px; text-transform:uppercase; color:var(--text-muted); }
   (`.link-rows`, `.link-row`, `.link-del`, `.link-add`, `.btn-remove` stay as-is.)

----- html/app.js -----

7. state: DELETE `boloCount` (41) and `boloFocus` (42) from `state`. Keep `lightbox` (40).

8. loadBolos() (619-677): remove `state.boloCount`/`state.boloFocus` (626-627) and both
   `updateBoloStep()` calls (630, 676). REPLACE the media build (639-647) and the thumb-wiring
   (663-670) with a per-card fixed media box + inline gallery:
     Media build (one image at a time; inline nav + counter only when >1; placeholder when 0):
       const multi = imgs.length > 1;
       let media =
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
     Per-card wiring (closure index `cur` -> independent of other cards; click opens lightbox scoped
     to THIS bolo's imgs at cur; onerror shows the placeholder in the SAME fixed box):
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
     Keep the existing `imgs` filter at line 635 (`^https?://`) so server-stored links still render.
     Keep the `.btn.danger` cancel wiring (671).

9. DELETE focusBolo() (707-715) and updateBoloStep() (716-720) entirely.

10. addBoloLinkRow / resetBoloLinks / boloLinkValues (679-705): keep addBoloLinkRow and
    resetBoloLinks. Tighten the SUBMIT collector to https-only:
       boloLinkValues(): change the filter from /^https?:\/\// to /^https:\/\//  (line 704).
    (Optional hardening: replace the per-row remove listener in addBoloLinkRow with a single
    delegated listener on `#bolo-images` for `.link-del` so rows can never lose their handler.)

11. Lightbox functions (722-743) and createBolo/cancelBolo (745-776): UNCHANGED, except createBolo
    already sends `images` from boloLinkValues - leave as-is.

12. Global keydown (1053-1073): DELETE the "section 4 / BOLOs tab" block (1067-1072) that maps
    Left/Right to focusBolo. KEEP the lightbox Left/Right block (1056-1061) and the cam-mode guard.

13. init() (1138-1215): DELETE the `#bolo-prev` and `#bolo-next` wiring (1174-1175). KEEP
    `$('#bolo-add-link').addEventListener('click', () => addBoloLinkRow())` (1173) and
    `resetBoloLinks()` (1176). KEEP all lightbox wiring (1179-1182).

================================================================
VERIFICATION CHECKLIST (run after edits)
================================================================
- `node --check html/app.js` -> clean.
- grep for leftovers returns nothing:
    grep -nE "boloFocus|boloCount|focusBolo|updateBoloStep|bolo-stepper|bolo-prev|bolo-next|bolo-step-index|bolo-gallery|bolo-thumb|thumb-ph|\.focused" html/app.js html/index.html html/style.css
- ASCII only (must print nothing new in the BOLO sections):
    grep -nP "[^\x00-\x7F]" html/app.js html/index.html html/style.css
    (Pre-existing non-ASCII `...` ellipsis and middle-dot live ONLY in dashboard/warrants/reports/
    cameras strings - not in BOLO code; do not introduce any in new BOLO code. Em/en dashes: 0.)
- Manual: each card is identical 16/9 shape regardless of image size/count; >1 image shows inline
  prev/next + "n / total"; clicking the image opens the lightbox scoped to that bolo; Esc closes the
  image first then a 2nd Esc closes the MDT; create form starts with one empty row, "Add link" adds
  rows, each row removes, submit sends only https links.
