# mORMot PDF Cross-Platform — Implementation Roadmap

Open work only. Finished work is in the git history, and the technical knowledge
it produced in `.claude/skills/` — this file repeats neither.

**State on 2026-09-22.** The engine is cross-platform, writes PDF 1.7, and its
tagged output passes PAC 2024 with one accepted warning (W-1, a Figure in
`pdf_demo`). Fonts are embedded and subset on all three platforms; tables carry
`THead`/`TBody`/`TFoot` row groups. All three platforms build, and `test_runner`
is green on each (222 assertions).

---

## Working Method

**One fix at a time.** Implement, verify, accept, then start the next. Changes
to `BeginStructContent` and the structure tree are unattributable when bundled —
a PAC error like "unbalanced marked content" then names no culprit.

| Role | System |
|---|---|
| Development, build, fast iteration | **Linux** |
| PAC 2024 + tag-tree inspection | **Windows** (only platform; mandatory) |
| Third-platform verification per change | macOS |
| `veraPDF` (`ua1`, `3b`, `3u`, `3a`) | installed on macOS since 2026-09-22; not yet part of the routine runs |

**PAC caveat.** The traffic-light status is not enough: a flat tree of
individually valid `Table`/`TR`/`TD` elements passes while the nesting is
broken. Always open the *Logical Structure* view as well.

**Toolchain.** The paths of the individual development machines are not part of
this repository; record them in `CLAUDE.local.md` (not versioned,
`CLAUDE.local.md.example` shows the format). A Lazarus installed outside the
distribution packages usually leaves `lazbuild` off `PATH` — use the full path
then. What holds regardless of the machine:

**Linux.** Linking the demos needs the GTK2 development symlinks, which
distributions do not always install: symlink `libgtk-x11-2.0.so`,
`libgdk-x11-2.0.so` and `libatk-1.0.so` to their `.so.0` files in a scratch
directory and build with `lazbuild --opt=-Fl<dir>`.

**Windows.** Target **x86_64-win64**; an aarch64-win64 FPC is not usable —
mORMot2 ships no static libraries for it. Build every project with `-B`: stale
`.ppu` files in `examples/*/lib/` outlive a unit-path change and will hide it.
Where the only `pdftotext` available is xpdf's rather than poppler's, there is
no `-bbox` — use `-layout` for column and line alignment. Without `pdffonts`,
`/BaseFont` survives as plain text in an uncompressed file, so
`grep -a -oE "/BaseFont[ ]*/[A-Za-z0-9+,#_-]+"` tells a subset (six-letter
prefix) from a whole face well enough.

**macOS.** Target **aarch64-darwin**. Linking prints a wall of `ld: warning:
object file ... built for newer macOS version (11.0) than being linked
(10.15)` — noise from the prebuilt mORMot2 units, not an error. HarfBuzz from
Homebrew (`/opt/homebrew/lib`) is on one of the paths `mormot.pdf.hbsubset`
probes, so no linker flag is needed; `hb-info` ships with it and is the
quickest way to tell a CFF face from a `glyf` one. Where the poppler tools are
missing, output is checked by file size and by reading the font dictionaries
with `python3` — inflating the object streams first, since the tagged demos
deflate `/BaseFont` out of reach of the grep.

**`--export` needs no display on macOS.** The Cocoa widgetset runs both GUI
demos headless; the `xvfb-run` advice is Linux/GTK2 only.

**Checking a change.** Build all six demos and `test_runner`, then compare the
PDFs with the previous run: file size, `pdffonts`, `pdftotext` output, and the
pages rendered with `pdftoppm -r 110 -png` compared pixel by pixel. A change
that is meant to be invisible has to come out pixel-identical. A pixel
comparison is valid **within** one platform only — see V below.

---

## Open

### V — Verification Outstanding

All three platforms build and pass `test_runner`. What is left is the
cross-platform comparison and the paths no pass has covered.

| What | Why it matters |
|---|---|
| ~~Linux rebuild of all six demos~~ | **done 2026-09-23** together with the U-1 re-measurement below: all six were rebuilt and checked |
| ~~PAC 2024 on the macOS-built PDFs~~ | **done 2026-09-23**: all four tagged demos green in PAC, alongside the veraPDF 106/106 |
| ~~Linux re-measurement after U-1~~ | **done 2026-09-23**: all six demos rebuilt on Linux and run through veraPDF. 7.21.5 went 5 → 0, 64 → 0, 63 → 0, 99 → 0 on the four tagged demos, which now pass `ua1` 106/106; the two untagged ones clear 7.21.5 as well |
| ~~PAC 2024 on `mormot_demo`~~ | **done 2026-09-23**, with the sample database: green, and the 5-page table is **one** `Table` in the structure. The counts hold on the Linux file too — 207 `TR` = 1 header + 206 data rows, 1030 `TD` = 206 × 5 columns, and `TH` stays 5. A repeated header that opened a second `THead` would give `TH` 25 and `TR` 211, so this measures the artifact marking directly |
| ~~Run on a machine **without** `libharfbuzz-subset`~~ | **done 2026-09-23** via `tests/no_hbsubset.sh` (Linux, aarch64, HarfBuzz 6.1.0). All three `libharfbuzz-subset.so*` files masked inside a mount namespace: the suite stays green at 197 assertions against 222 with the library, the two subset suites standing down (19 → 7 and 22 → 9) instead of failing. **The loader's missing-library path is now measured, not simulated.** What is still untested is a HarfBuzz *older than 2.9*, which loads but lacks `hb_subset_or_fail` — that needs an old distribution, e.g. Debian 11 |

**Comparing the platforms — but not pixel by pixel.** The demos resolve
different families (Calibri/Cambria/Consolas, Liberation, Trebuchet MS/Georgia/
Andale Mono), so different advance widths, line breaks and page counts are
correct behaviour, not a defect. B-5 made the measurement platform-independent
*for one face*, not the faces themselves. What must match: `pdftotext` output,
the structure tree (roles and their counts), `pdffonts` (embedded, subset,
`uni`), page count and the PAC result. A true cross-platform render diff would
need a demo that forces one face on all three systems — worth building only if
this comparison is to be automated.

**veraPDF is installed** (1.30.2 greenfield, on the macOS machine; the path is
in `CLAUDE.local.md`). It has the `ua1`, `3a`, `3b` and `3u` profiles, so it
serves both this section and R-17 — the objective, scriptable half of the
comparison above, where PAC offers only a GUI and cannot check PDF/A at all. It
is not yet part of the routine verification runs.

**Its first runs found a POSIX defect PAC never reported — U-1 below, fixed
2026-09-23, with U-2 beside it.** All four tagged demos now pass PDF/UA 106/106
on **all three platforms**, verified by veraPDF, and PAC 2024 passes the same
four. `chinese_demo` and `rtl_demo` are untagged, but clear 7.21.5 everywhere
too.

**All three platforms are now green on the tagged demos**, in **both** checkers
— veraPDF 106/106 and PAC 2024, `mormot_demo` included. That was the stated gate
for a first version tag, and the project still has none.

Two things the green does not cover, worth naming before tagging rather than
after: the U-2 fix is exercised on macOS only, because no Linux Arabic face
reaches the code it repairs (see its entry); and while the **missing**
`libharfbuzz-subset` is now covered by `tests/no_hbsubset.sh`, a HarfBuzz
*older than 2.9* — which loads but lacks `hb_subset_or_fail` — still is not.

### U-1 — Glyph Widths Disagree With the Embedded Font Program (POSIX) — done 2026-09-23

**Found 2026-09-22** by the first veraPDF runs ever made on this project, over
the Linux, macOS and Windows PDFs of 2026-09-20. **PAC 2024 passed the files
veraPDF fails**, which is the point worth keeping: the two checkers do not
overlap, so a PDF/UA claim needs both.

ISO 14289-1 **7.21.5** — the `/Widths` (and `/W`) entries must agree with the
widths in the embedded font program.

| PDF | Platform | Before | After |
|---|---|---|---|
| `pdf_demo_windows_final` | **Windows** | PASS — 106/106 | unchanged |
| `markdown_demo_windows_final` | **Windows** | PASS — 106/106 | unchanged |
| `report_demo_windows` | **Windows** | PASS — 106/106 | unchanged |
| `mormot_demo_windows` | **Windows** | PASS — 106/106 | unchanged |
| `output_crossplat.pdf` | macOS | 105 passed, 7.21.5 ×11 | **PASS — 106/106** |
| `markdown_demo.pdf` | macOS | 105 passed, 7.21.5 ×83 | **PASS — 106/106** |
| `report_demo` (`--export`) | macOS | 7.21.5 ×63 (Linux figure) | **PASS — 106/106** |
| `mormot_demo` (`--export`) | macOS | 7.21.5 ×99 (Linux figure) | **PASS — 106/106** |
| `pdf_demo_linux_fix1` | **Linux** | 7.21.5 ×5 | **PASS — 106/106** |
| `markdown_demo_linux_fix1` | **Linux** | 7.21.5 ×64 | **PASS — 106/106** |
| `report_demo_linux_fix1` | **Linux** | 7.21.5 ×63 | **PASS — 106/106** |
| `mormot_demo_linux_fix1` | **Linux** | 7.21.5 ×99 | **PASS — 106/106** |

Both defects were in `TPdfFreeTypeFontProvider.GetCharABCWidths`, exactly where
the first analysis placed them — in `mormot.pdf.freetype`, not in
`mormot.ui.pdf`. Windows was the reference for what the values should be, and
POSIX now matches it on **both** POSIX platforms: the Linux files were rebuilt
and measured on 2026-09-23, with the before/after counts in the table above
taken on the same machine and the same profile. PAC 2024 passes the same four
files, and the RTL alignment was checked by eye.

**(b) The genuinely wrong widths — an ANSI/Unicode mix-up.** The engine calls
`GetCharABCWidths(dc, 32, 255, W)` and indexes the result by WinAnsi byte,
because the Windows counterpart is `GetCharABCWidthsA` — an **ANSI** call that
maps the byte through the DC codepage (1252). The FreeType backend passed the
same byte straight to `FT_Load_Char`, which expects a **Unicode code point**.
For 32..127 and 160..255 the two agree, which is why this stayed hidden. For
**128..159 they do not**: those bytes are the unassigned C1 controls in Unicode
but printable punctuation in WinAnsi. `FT_Load_Char` missed the CMAP and
returned the `.notdef` advance.

Two characters were affected in practice, both common in prose:

| Byte | WinAnsi | Font program | Written | Source of the wrong value |
|---|---|---|---|---|
| `#$95` | bullet U+2022 | Georgia 392.58 | **1000** | Georgia `.notdef` = 1000 |
| `#$95` | bullet U+2022 | Trebuchet 524.41 | **501** | Trebuchet `.notdef` ≈ 500 |
| `#$97` | em dash U+2014 | Georgia 856.93 | **1000** | Georgia `.notdef` = 1000 |
| `#$97` | em dash U+2014 | Trebuchet 734.38 | **501** | Trebuchet `.notdef` ≈ 500 |

That is the whole of (b): 1 check in `pdf_demo`, 8 in `markdown_demo`, which is
why the counts matched across Linux and macOS despite different font families —
the same two characters in the same demo text, and `.notdef` on both. The
earlier guess that `/DW` or `fDefaultWidth` was the source was wrong; the
recurring `750`/`778` in the first notes were the `abcB` component, not the
written advance. `report_demo` and `mormot_demo` showed no (b) simply because
their text has no bullet and no em dash.

The fix translates the byte before the lookup, with
`WinAnsiConvert.AnsiToWide[]` — the same table `mormot.ui.pdf` already uses for
`/ToUnicode`.

**(a) The rounding — three roundings where one was needed.** `MulDiv` in the
backend rounds to nearest, so scaling one value can be off by at most 0.5,
comfortably inside the ±1 the rule allows. But the backend scaled `abcA`,
`abcB` and `abcC` **separately**, and every consumer sums the three. Three
roundings accumulate to ±1.5, and the observed deviations of up to 2.8 units
follow from that. Nothing was wrong with the metrics — only with rounding them
three times.

The fix scales the advance **once** and gives `abcB` the remainder after the
two bearings, so `abcA + abcB + abcC` equals the scaled advance by
construction. Both bearings stay individually correct, which is what the other
callers of the ABC triple need.

**Regression test:** `TestWinAnsiHighRangeWidths` in
`test_pdf_crossplatform.pas` asserts that the bullet and em dash have sane
advances (em dash wider than `M`, bullet narrower) and — the check that
actually bites — that neither equals the `.notdef` advance. Verified to fail
3/8 against the pre-fix backend. Total assertions 222 → 230.

**Bearing on R-17:** PDF/A-3A includes the PDF/UA requirements, so R-17 no
longer inherits a known POSIX defect through the A level.

**`chinese_demo` and `rtl_demo` are not tagged**, so `ua1` is the wrong profile
for them; their extra failures (7.1, 6.2) are artifacts of that choice. Their
7.21.5 hits were re-measured after the fix anyway, because 7.21.5 is about the
font dictionary and does not depend on tagging:

| Demo | Before | After |
|---|---|---|
| `chinese_demo` | 7.21.5 ×1 | **none** |
| `rtl_demo` | 7.21.5 ×9 | **×1** — see U-2 |

Both carry Latin text in a WinAnsi font beside the CJK/Arabic, and that is what
the fix cleared: `chinese_demo`'s single hit was the em dash, 8 of `rtl_demo`'s
9 were the em dash and Latin rounding. The CID `/W` path was never in scope
here, and one hit in it remains.

### U-2 — One Shaped Arabic Glyph Has a Wrong `/W` Entry (macOS) — done 2026-09-23

**Found 2026-09-23** while re-measuring `rtl_demo` after U-1. It is what is left
of that demo's nine 7.21.5 hits once the WinAnsi ones are gone, and it is a
**different defect in a different code path** — the CID `/W` array, not
`/Widths`.

    WQQPKW+GeezaPro  gid 273   font program 407.7758   /W entry 316   diff -92

Glyph 273's true advance is 407.78, and the neighbouring glyphs 268 and 272
have the **same** advance in the face and are written correctly as 407. Only
273 is wrong, so this is not a scaling or rounding error — the value 316 comes
from somewhere other than `hmtx`.

**Its `/ToUnicode` entry identifies the path:** code `<0111>` maps to `<E111>`,
a PUA value. Per `fonts.md` §10 that is the Step 3 marker — the glyph was
registered by `GetAndMarkGlyphAsUsedWithWidth`, and its width is the **HarfBuzz
`x_advance`**, not the `hmtx` value. So U-2 lives in the shaper width path.

**This is the path `fonts.md` §10 warns is invisible on Linux.** Geeza Pro has
no Arabic presentation forms in its CMAP, so macOS takes Step 3; Noto Naskh
Arabic on Linux has them and takes Step 2, where the HarfBuzz advance is
computed and discarded. Expect this to reproduce on macOS only, and note that
P3-A already went wrong once by writing HarfBuzz advances into `/W`
unconditionally — `x_advance` is legitimately 0 for cursive-attachment medial
forms. Whatever fixes 316 must not reintroduce that.

**Verified against the embedded font program, not just against veraPDF**
(2026-09-23, after the question was raised whether this is a false alarm). The
subset in the PDF was extracted and read directly: it has 365 glyphs with
`numOfLongHorMetrics` 365 and keeps the original glyph IDs, so no renumbering
can confuse the index, and its own `hmtx` gives gid 273 an advance of 902/2212
= 407.7758. The `/W` entry of 316 contradicts the very file it ships with.
**veraPDF is right.**

**But the rendering is correct, and that is the interesting part.** The text
run is

    [<00F1><00F4><0105> 91<0111> -91<0159>] TJ

— a `TJ` array with explicit adjustments of **+91 and −91** bracketing exactly
this glyph. The deficit is 407.78 − 316 = **91.78**. The shaper's positioning
pass notices that the advance it asked for and the width in the dictionary
disagree, and emits a kerning correction that cancels the error out. The glyph
lands in the right place; only the dictionary lies.

That makes U-2 **a conformance defect, not a layout defect**: invisible in any
viewer, fatal to a PDF/UA claim, and it would become visible the moment the
compensation is removed or a consumer reads `/W` without replaying the `TJ`
offsets (text extraction, reflow, a screen reader computing positions).

**The cause, measured with HarfBuzz directly.** Shaping the word gives

    gid 241 adv 292   gid 244 adv 297   gid 261 adv 614
    gid 273 adv 317 x_offset -91        gid 345 adv 439

Four of the five advances equal the face's own `hmtx` value within rounding.
Only gid 273 differs — by exactly its GPOS offset. HarfBuzz returns the
**positioned** advance: a cursively attached glyph is shifted left by 91 and its
advance shortened by the same 91, so the pen still lands correctly. `/W` must
state what the font program states, which is the *unpositioned* advance.
`GetAndMarkGlyphAsUsedWithWidth` stored the shaper's value, so the dictionary
disagreed with the face while the page stayed correct.

**The fix, in `mormot.ui.pdf`:** `/W` now comes from a new `GlyphHmtxWidth()`,
which reads `hmtx`/`head`/`hhea` through the platform backend and caches them
per font instance; the shaper's advance is kept only as a fallback when those
tables cannot be read. Because the viewer advances the pen by `/W`, correcting
it alone **would have moved the text** — so `AddUnicodeHexTextHarfBuzz` now adds
`Widths[i] - Advances[i]` into the `TJ` kerning of every glyph, which makes the
emitted run reproduce the shaper's advances whatever `/W` says. That also picks
up the sub-unit rounding the old fast path ignored, so a run with no GPOS
offsets at all can now emit small corrections.

Verified on the rendering, not only on the checker: the run is

    [<00F1> -1<00F4> -1<0105> 91<0111><0159> -1] TJ

with `/W` 292 296 614 **407** 438, giving a pen movement of 292+296+614+407+438
− (−1−1+91−1) = **1959** — exactly HarfBuzz's total, unchanged from before the
fix. Only the dictionary changed.

**Regression test:** `TestShapedGlyphWidthFromHmtx` shapes the word, requires a
face that actually applies a GPOS offset (skipping otherwise, which is what
Linux does), then builds a PDF and reads the `/W` entry back out of it,
asserting it equals the `hmtx` advance and **not** the shaper's. Verified to
fail 2/9 against the pre-fix engine. Total assertions 230 → 239.

**Confirmed to be macOS-only, by measurement** (2026-09-23). The Linux
`rtl_demo` was checked for the marker: its `/ToUnicode` holds 25 real code
points and **no PUA entry at all**, so every shaped glyph resolved through the
CMAP (Step 2) and the Step 3 width path never ran. The U-2 fix is therefore
*not* covered by the Linux pass — as `fonts.md` §10 predicts, and the reason
the test skips itself there rather than reporting a false green.

### R-17 — Verify PDF/A-3A, and Add the U Conformance Level

**Asked for by the community.** Nothing is promised; this entry records what
would have to happen for the claim to be defensible.

**Goal (set 2026-09-24): PDF/A-3U and PDF/UA-1 in one file.** The community
asks explicitly for PDF/A **combined with** PDF/UA, so A-3U is mandatory for
this project, not an option. That does not depend on what ZUGFeRD itself
accepts. The ZUGFeRD demo is therefore tagged from the start and checked
against `3u` **and** `ua1`. A-3A stays the next level up.

**Effort:** 1 day of clarification, then 2–4 days | **Files:**
`src/core/mormot.ui.pdf.pas`, `tests/`, `examples/zugferd_demo/`

**The engine already implements PDF/A-3.** This was checked against the code,
not assumed: `TPdfALevel` has `pdfa3A`/`pdfa3B`; the XMP packet writes
`pdfaid:part`/`conformance` from `PDFA_APART`/`PDFA_CONFORMANCE` per level; the
catalog gets an sRGB `OutputIntent` with an embedded ICC profile (`GTS_PDFA1`,
which stays the identifier for A-2 and A-3); `pdfa2A` and above raise
`FileFormat` to 1.7; encryption raises; `CreateFileAttachmentFrom` writes
`/AFRelationship`, `/Subtype` (MIME), `/Params` with `/Size`, `/CreationDate`
and `/ModDate`, `/Names/EmbeddedFiles`, and — from `pdfa2A` up — the catalog
`/AF` array that ZUGFeRD files usually lack. The `/CIDSet` guard that forces a
whole face is `fPdfA in [pdfa1A, pdfa1B]`, so A-2 and A-3 subset.

So this item is **verification plus one missing enum value**, not an
implementation.

**Verification status today — no level is verified.** There is one test,
`TestPdfA1StillWholeFace`, and it asserts one property (A-1 embeds the whole
face, no subset tag). No demo sets `PdfA` — all six run `pdfaNone`, so no PDF/A
output has ever been looked at. No conformance checker has ever run.

#### Progress — 2026-09-24, macOS

**First PDF/A output, first defect: tagged PDF/A crashed on `Free`.** Any
level (1B, 2B and 3B were each tried) combined with `Tagged := True` freed one
object twice in `FreeDoc`. `NewDoc` gave PDF/A its own **direct**
`StructTreeRoot` plus `MarkInfo` in the catalog. Two consequences:

- The Tagged setup in `AddPage` runs only while `fStructTree = nil`, so it was
  skipped: no `/Lang`, no `DisplayDocTitle`. veraPDF `ua1` failed 7.1-10 and
  7.2 (the language rules, for metadata, outline and every piece of text).
- `SerializeStructTree` adds the tree root as `/P` of the document element. An
  indirect object is referenced there, but a direct one is **owned** by every
  dictionary it is added to, so it was released twice.

Fix: the PDF/A block in `NewDoc` no longer creates either entry; the Tagged
setup does, as it does without PDF/A. Untagged PDF/A now carries no
`StructTreeRoot` and no `/MarkInfo`, which is correct for the B levels (it used
to claim `/Marked true` with an empty tree). Regression test
`TestTaggedPdfA` in `test_pdf_smoke.pas`: fails with `EAccessViolation`
against the old engine, passes now. Assertions 239 → 245.

**Measured on the ZUGFeRD demo** (`examples/zugferd_demo/`, PDF/A-3B, veraPDF
1.30.2):

| Variant | `3b` | `ua1` |
|---|---|---|
| tagged + `factur-x.xml` | 144/146 — 6.6.2.3.1 ×2 | **106/106** |
| tagged, no attachment | 144/146 — the same | **106/106** |
| untagged + `factur-x.xml` | **146/146** | — |

- **PDF/A-3B itself holds**, the attachment included: `/AF`,
  `/AFRelationship /Data`, `/Subtype /text#2Fxml` and `/Params` pass.
- **The one remaining failure is `pdfuaid:part`** with no extension schema.
  PDF/A-2/3 do not predefine the `pdfuaid` namespace, so the packet needs a
  `pdfaExtension` description of it whenever PDF/A and Tagged meet. This is an
  engine fix in `SaveToStreamDirectBegin`, not demo work.

**Found while reading, not yet fixed:**

- `CreateFileAttachment(FileName, …)` takes no `/AFRelationship` (always
  `Alternative`) and writes `/Params /Size 0`, because the size is taken from
  the empty `Buffer` while the content comes through the stream. Use
  `CreateFileAttachmentFrom` with the buffer until then.
- `PdfMetadataZugferd` already exists: the `fx:` extension schema, but with
  XRechnung values (`xrechnung.xml`, Version 3). The `fx:` part of R-17 is
  therefore a parameterised variant of it, not new code.
- Setting `PdfA` as a property calls `NewDoc`; pass it to the constructor.

#### Clarify first — both before any estimate is believed

1. **Read every `fPdfA` branch.** There are 13 outside the accessors. As of
   `v0.9.0` they sit at 5881, 7410, 7424, 7597, 8301, 8303, 8424, 8539, 8572,
   8574, 8596, 9172, 9715 — but line numbers move, so find them with
   `grep -n fPdfA src/core/mormot.ui.pdf.pas` rather than trusting this list.
   Those checked so far are right, but each `fPdfA <> pdfaNone` that means
   "PDF/A-1" is too strict under A-3, and each A-1 rule applied to all levels
   likewise. A reading pass, not a change.
2. ~~**Install veraPDF.**~~ **Done 2026-09-22** — 1.30.2 greenfield on macOS,
   with the `3a`, `3b` and `3u` profiles. Its first run found **U-1**, which
   R-17 would have inherited through the A level. **Both U-1 and U-2 are fixed
   as of `v0.9.0`**, so R-17 no longer starts with a known width defect: PDF/UA
   is green on all three platforms, and the A level builds on that rather than
   having to clear it first.

#### The one real gap: `pdfa3U`

`TPdfALevel` has only A and B. **The project goal requires PDF/A-3U** (see
the goal above); whether ZUGFeRD itself insists on U was never confirmed and no
longer matters. Adding it is an enum member
plus one character in each of `PDFA_APART` and `PDFA_CONFORMANCE` — but the
substance is proving that `/ToUnicode` is written for *every* font, without
exception, which is what U means.

**A implies U.** PDF/A-3A requires everything 3U requires, so the U work is a
subset of the A work, not an extra.

**The risk is already located.** `/ToUnicode` is written for any PDF/A and any
tagged document, but guarded by `fFirstChar <> 0` — a font with no used WinAnsi
characters gets none. That is exactly the unused WinAnsi peer beside a CJK font
(see its own entry above): selected with `Tf`, drawing nothing, and under A/U
possibly required to carry a `/ToUnicode` it cannot have. poppler already
reports it. Whether veraPDF calls it a violation is the first thing to measure,
and it may make that entry a prerequisite of this one rather than a loose end.

#### Where to start, concretely

Half a day before any of the above is worth arguing about, because no PDF/A
output has ever been looked at:

1. Take `pdf_demo` or `markdown_demo`, set `PdfA := pdfa3B`, and run the result
   through `verapdf -f 3b`. That is the cheapest possible first measurement and
   it needs no code change. A-3B is the weakest level, so whatever it reports
   is a genuine defect rather than a level mismatch.
2. Repeat with `pdfa3A` and `-f 3a`. The difference between the two runs is
   exactly what the A level costs here, measured instead of estimated.
3. Only then read the 13 `fPdfA` branches, with the failures in hand — they
   will point at which branch is too strict or too lax, instead of the reading
   pass having to anticipate it.

The `pdfa3U` enum member is best added *after* step 2, since A implies U: if
3A comes out clean, U is nearly free; if it does not, the failures decide
whether U is reachable on its own.

#### What A-3A costs beyond A-3B

The full logical structure — which exists and is PAC-green (P3, B-1…B-14,
R-14). A-3A is therefore the cheapest hard level this engine could claim, but
it is the only PDF/A variant needing **two** checkers on **two** platforms:
veraPDF for conformance anywhere, PAC 2024 for the tag tree on Windows only.

#### ZUGFeRD demo — `examples/zugferd_demo/`

**Terms and scope — decided 2026-09-24.**

| Term | What it is | Form |
|---|---|---|
| EN 16931 | European standard for the *content* of an e-invoice | data model; XML in UBL or UN/CEFACT CII syntax |
| XRechnung | Germany's national specification of EN 16931, maintained by KoSIT, for invoices to public authorities | pure XML, no PDF |
| ZUGFeRD 2.x (DE) = Factur-X 1.x (FR) | one joint Franco-German standard for **hybrid** invoices: PDF/A-3 with embedded CII XML | profiles MINIMUM, BASIC WL, BASIC, EN 16931, EXTENDED |
| ZUGFeRD profile XRECHNUNG | ZUGFeRD only, unknown to Factur-X: an XRechnung inside a ZUGFeRD PDF as `xrechnung.xml` | hybrid |

**The demo targets profile EN 16931 with `factur-x.xml`**: the common
European case, a ZUGFeRD invoice in Germany and a Factur-X invoice in France.
MINIMUM and BASIC WL do not count as e-invoices in Germany since 2025. The
XRECHNUNG profile was considered and dropped, because the one reason for it
— invoices to German authorities — does not involve a PDF at all: the federal
platforms (ZRE, OZG-RE) take XRechnung, or ZUGFeRD profile XRECHNUNG "als
rein strukturierte XML-Datei" (e-rechnung-bund.de FAQ, checked 2026-09-24).
**Invoices to authorities (B2G) are therefore out of scope**, and the
documentation should say so: this project produces hybrid invoices for the
exchange between businesses (B2B).

**The engine stays neutral towards these standards**: it writes PDF/A-3,
embeds any file as an associated file (`/AF`) and takes any XMP extension. It
neither generates nor validates invoice XML.

An integration proof of the existing API. **The invoice has to be genuinely
valid**: someone in the community will run the PDF through a ZUGFeRD checker
or read it into accounting software. Three parts, one of which is new work:

- **The XML** — third-party test data, not written here: test case `01.01a` of
  the [KoSIT xrechnung-testsuite](https://github.com/itplr-kosit/xrechnung-testsuite)
  (release `v2026-08-31`, Apache-2.0), embedded byte-identical as
  `xrechnung.xml` for now. XRechnung 3.0 in CII syntax, so EN 16931 level.
  **Next:** one change, the specification identifier to
  `urn:cen.eu:en16931:2017` and the name to `factur-x.xml` for profile
  EN 16931 — allowed by Apache-2.0 when marked, so recorded in
  `THIRD_PARTY.md`, and revalidated with Mustang. Provenance, checksum and license text are in the
  demo folder (`THIRD_PARTY.md`, `xrechnung.LICENSE.txt`), `.gitattributes`
  keeps the line endings. The page draws the same content.
  Generating invoice XML is invoice semantics, not PDF, and is **not** in scope.
- **The embedding** — `CreateFileAttachmentFrom(..., afrAlternative)` (the
  overload taking a file name has no relationship parameter). Which
  relationship profile EN 16931 prescribes is to be confirmed with Mustang in
  step 2.
- **The XMP extension schema** — the `fx:` namespace through
  `PdfAMetadaExtension`, which takes raw XML. `PdfMetadataZugferd` already
  holds a specimen, but for profile XRECHNUNG; profile EN 16931 needs other
  values, so a parameterised helper beside it rather than a second constant.

**Sources ruled out, 2026-09-24:** the official FeRD samples — only the schemas
and Schematron are Apache-2.0, copying the rest needs the AWV's prior consent;
the copies of them in Mustang's and LandrixSoftware's repositories, which
those projects' licenses do not cover; the CEN examples (EUPL-1.2, and
`CII_example1` fails its own arithmetic); XRechnung-for-Delphi (GPL-3.0).

**Checker:** Mustang-CLI 2.26.0 (Apache-2.0) validates the whole file — PDF/A
through its bundled veraPDF, the `fx:` XMP, and the XML against XSD and
Schematron. First run: the XML is valid, the PDF fails on the missing `fx:`
properties and the missing `pdfuaid` schema only.

#### Tests

Alongside `TestPdfA1StillWholeFace`, per level: `/AF` present in the catalog,
`/AFRelationship` set, subsetting allowed under A-3 (the opposite of the A-1
assertion), encryption raising, and `/ToUnicode` on every font for U. Note that
the tagged demos write object streams, so these have to inflate before
searching — a plain text search silently finds nothing.

#### Scope — by how widespread the level is, not by what is easy

| Level | Spread | Plan |
|---|---|---|
| **A-3U + UA-1** | what the community asked for; also the commonest A-3 case (ZUGFeRD/Factur-X) | **target, mandatory** |
| **A-3A** | the next level up | target; A implies U |
| **A-1B** | archives, public authorities; the commonest level overall | pull along — partly covered already |
| A-3B, A-2B | staging posts | fall out of the above |
| A-1A, A-2A | rare, own PAC run each | leave as implemented, unverified |

**Untested ground:** object streams, xref streams and transparency (R-2, R-3,
R-7) are forbidden under A-1 and allowed under A-3, so A-3 is the first PDF/A
context they run in at all. Most likely place for surprises.

**Order**, one step at a time: clarification and veraPDF → tagged A-3B on the
ZUGFeRD demo (`3b` + `ua1`) → `fx:` XMP → U (`3u` + `ua1`) → A with PAC → A-1B
pulled along. Each step is checkable on its own.

**Do not remove the unverified levels.** `PdfA` is public API and the
constructor takes `APdfA`; dropping enum members breaks callers of a library
whose point is to make the Windows unit available elsewhere. A-1 is not
obsolete — an archive demanding A-1 rejects A-3 precisely because A-3 permits
arbitrary attachments. Say in the documentation which levels are verified
instead.

### The Unused WinAnsi Peer Beside a CJK Font — unprioritised

The engine creates a WinAnsi peer beside every Identity-H font and emits a `Tf`
for it, but for a CJK face that instance draws nothing — the content stream
selects `F1`/`F3` and immediately switches to `F2`/`F4`. poppler reports
`Unknown font tag` for it. Pre-existing and unrelated to CFF (it appears on
files from before R-15c). The fix is to stop emitting the peer when it has no
used characters, which touches the font lifecycle on every platform — see
`fonts.md` §4 on the dual-instance model.

**R-17 may promote this from cosmetic to blocking.** `/ToUnicode` is guarded by
`fFirstChar <> 0`, so the peer carries none — and PDF/A-3U and -3A require one
for every font.

### R-15b — Symbolic Fonts Are Not Subset on POSIX — unprioritised

**Effort:** 0.5 day | **Files:** `src/core/mormot.ui.pdf.pas`,
`src/platform/unix/mormot.pdf.freetype.pas`

The one remaining difference between the platforms that is **not** a property of
the platform. `PrepareFontSubsets` skips a symbolic font when
`PdfFontSubsetter <> nil`: such a font reaches its glyphs through the `(3,0)`
cmap under the `F0xx` convention, and `AddToSubsetRequest` knows neither those
code points nor the glyph IDs behind them, so hb-subset would drop every glyph
the WinAnsi instance draws. Keeping the whole face is the safe answer there.

Windows does not need the exclusion since R-15a: `AddWinAnsiGlyphs` resolves the
characters to glyph indices through the face itself, which works whatever cmap
the lookup goes through. Aligning the two therefore means **improving POSIX**,
not restricting Windows — give `IPdfPlatformFont` a character-to-glyph lookup
(FreeType has `FT_Get_Char_Index`) and let `AddToSubsetRequest` fill the glyph
list on both platforms, then drop the exclusion.

Neither side is verified: no demo and no test uses a symbolic face, so the
Windows claim above is an argument from the code, not a measurement. Whoever
takes this should add a demo or test with Wingdings/Symbol first.

Related and equally untested: what `CreateFontPackage` does with a **CFF** face
on Windows. POSIX subsets CFF since R-15c; every face in the demos is
`glyf`-based, so the Windows CFF path has never run. Whether PDF/A or tagged
output impose extra `/FontFile3` conditions is likewise unchecked —
`chinese_demo`, the only CFF case, is neither.

### R-10 — Table Row Pagination — unprioritised

**Effort:** 2–3 days | **File:** `src/core/mormot.ui.report.pas`

A table row taller than the remaining page space forces a page break before the
row. Let the row split: partial cell content on the current page, the rest on
the next. The split row's cells have to stay inside **one** `TR` element
referencing both pages — `TPdfDocumentVcl.ResumeStructContent` does this for
text blocks (B-2) and is the model to follow.

### R-11 — TTC Face Index — unprioritised

**Effort:** 1 day | **Files:** `src/platform/unix/mormot.pdf.freetype.pas`,
`src/core/mormot.pdf.types.pas`

Only face index 0 of a `.ttc` is reachable, because `TPdfFontMap` carries no
face index. Add one so the remaining faces can be selected by name. The
FreeType backend already extracts a single face as a standalone sfnt
(`ExtractSfntFromTtc`), so the embedding side needs no change.

### R-13 — RTL Shaper Advance Test — mostly done 2026-09-23

**Effort:** 0.5 day remaining | **File:** `tests/`

The advance half is **done**, as a by-product of U-2.
`TestShapedGlyphWidthFromHmtx` is exactly what this item asked for: it shapes
Arabic, requires a face that applies a GPOS offset — which Noto Naskh Arabic
does not, so the test skips itself on Linux instead of reporting a false green
— and then asserts against the generated PDF that `/W` carries the `hmtx`
advance rather than the shaper's. It fails 2/9 against the pre-U-2 engine, so it
guards the path that is invisible on Linux and was fatal on macOS. Background:
`.claude/skills/fonts.md` §10.

**What is left** is the end-to-end half. `TestUseUniscribeIsPortable` (from
R-16) is a compile-time guard, not an output check: nothing yet asserts that
shaped Arabic actually reaches the PDF on the Windows path, by checking the
`/ToUnicode` entries for `U+FExx` after drawing with `UseUniscribe` set. That
is a Windows-side test and remains open.

### EMF/MetaFile and GDI+ Gradients — no work planned

Windows-only (`TPdfDocumentGdi`), not portable.
