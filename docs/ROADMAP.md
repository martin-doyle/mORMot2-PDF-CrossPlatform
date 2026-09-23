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
| Linux rebuild of all six demos | the R-15/R-15a/R-16 engine changes are argued to be POSIX-neutral from the `{$ifdef}` structure, not measured. Expect every PDF unchanged except `chinese_demo` and `rtl_demo`, which no longer pin the whole face |
| PAC 2024 on the macOS-built PDFs | the macOS pass checked sizes and fonts, not the tag tree; PAC runs only on Windows. veraPDF has since covered the mechanical half, and after U-1 the macOS demos pass it 106/106 |
| Linux re-measurement after U-1 | the U-1 fix is in `mormot.pdf.freetype`, shared by Linux and macOS, and macOS went from 11/83 failures to none. Linux should follow, but has not been run |
| PAC 2024 on `mormot_demo` | it ran on macOS (tag tree complete by inspection: 1 `Table` with `THead`/`TBody`/`TFoot`, 207 `TR`, 5 `TH`, 1030 `TD`), but has never been through PAC |
| Run on a machine **without** `libharfbuzz-subset` | `TestSubsetFallbackWithoutSubsetter` only simulates it by clearing `PdfFontSubsetter`; the loader path itself — missing library, or HarfBuzz older than 2.9 — has never run |

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
2026-09-23.** All four tagged demos now pass PDF/UA 106/106 on Windows and
macOS; **Linux is still to be re-measured**, the fix being in shared POSIX
code.

Once all three platforms are green, that is the point for a first version tag —
the project has none.

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

Both defects were in `TPdfFreeTypeFontProvider.GetCharABCWidths`, exactly where
the first analysis placed them — in `mormot.pdf.freetype`, not in
`mormot.ui.pdf`. Windows was the reference for what the values should be, and
POSIX now matches it. **Linux is still to be re-measured**; the fix is in
shared POSIX code and the macOS numbers cover the same path, but that is an
argument, not a measurement.

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

### R-17 — Verify PDF/A-3A, and Add the U Conformance Level

**Asked for by the community.** Nothing is promised; this entry records what
would have to happen for the claim to be defensible.

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

#### Clarify first — both before any estimate is believed

1. **Read every `fPdfA` branch.** There are 13 outside the accessors: 5855,
   7317, 7331, 7504, 8208, 8210, 8331, 8446, 8479, 8481, 8503, 9079, 9622.
   Those checked so far are right, but each `fPdfA <> pdfaNone` that means
   "PDF/A-1" is too strict under A-3, and each A-1 rule applied to all levels
   likewise. A reading pass, not a change.
2. ~~**Install veraPDF.**~~ **Done 2026-09-22** — 1.30.2 greenfield on macOS,
   with the `3a`, `3b` and `3u` profiles. Its first run found **U-1**, which
   R-17 inherits through the A level — on POSIX only; Windows passes PDF/UA
   outright.

#### The one real gap: `pdfa3U`

`TPdfALevel` has only A and B. **ZUGFeRD/Factur-X from version 2 requires
PDF/A-3U**, and does not accept A in its place. Adding it is an enum member
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

#### What A-3A costs beyond A-3B

The full logical structure — which exists and is PAC-green (P3, B-1…B-14,
R-14). A-3A is therefore the cheapest hard level this engine could claim, but
it is the only PDF/A variant needing **two** checkers on **two** platforms:
veraPDF for conformance anywhere, PAC 2024 for the tag tree on Windows only.

#### ZUGFeRD demo — `examples/zugferd_demo/`

Buildable here without outside material, and a pure integration proof of the
existing API. Three parts, one of which is new work:

- **The XML** — a static `factur-x.xml` (MINIMUM or BASIC-WL profile) in the
  demo folder, embedded as it is. Generating UN/CEFACT invoice XML is invoice
  semantics, not PDF, and is **not** in scope. Test material, not a feature.
- **The embedding** — `CreateFileAttachment(..., afrData)`; the file name
  `factur-x.xml` and `/AFRelationship /Data` are both prescribed by ZUGFeRD 2.1.
  Existing API, nothing to write.
- **The XMP extension schema** — the `fx:` namespace through
  `fPdfAMetadaExtension`, which takes raw XML. This is the error-prone part and
  the only new code: veraPDF checks the `pdfaExtension` description strictly.
  Either a helper in the library or at least one correct specimen in the demo,
  so callers do not each invent it.

#### Tests

Alongside `TestPdfA1StillWholeFace`, per level: `/AF` present in the catalog,
`/AFRelationship` set, subsetting allowed under A-3 (the opposite of the A-1
assertion), encryption raising, and `/ToUnicode` on every font for U. Note that
the tagged demos write object streams, so these have to inflate before
searching — a plain text search silently finds nothing.

#### Scope — by how widespread the level is, not by what is easy

| Level | Spread | Plan |
|---|---|---|
| **A-3A** | what was asked | **target** |
| **A-3U** | ZUGFeRD/Factur-X v2 — by far the commonest A-3 case | included; A implies U |
| **A-1B** | archives, public authorities; the commonest level overall | pull along — partly covered already |
| A-3B, A-2B | staging posts | fall out of the above |
| A-1A, A-2A | rare, own PAC run each | leave as implemented, unverified |

**Untested ground:** object streams, xref streams and transparency (R-2, R-3,
R-7) are forbidden under A-1 and allowed under A-3, so A-3 is the first PDF/A
context they run in at all. Most likely place for surprises.

**Order**, one step at a time: clarification and veraPDF → A-3B on the ZUGFeRD
demo → U → A with PAC → A-1B pulled along. Each step is checkable on its own.

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

### R-13 — RTL Shaper Advance Test — unprioritised

**Effort:** 0.5 day | **File:** `tests/`

Linux fonts (Noto Naskh Arabic) resolve shaped glyphs through the CMAP, so the
shaper's own advance path never runs there — a bug in it is invisible on Linux
and fatal on macOS. Add a test against a font **without** Arabic presentation
forms. Background: `.claude/skills/fonts.md` §10.

`TestUseUniscribeIsPortable` (from R-16) is a compile-time guard, not an output
check: nothing yet asserts that shaped Arabic actually reaches the PDF. An
end-to-end test belongs with this item, checking the `/ToUnicode` entries for
`U+FExx` after drawing with `UseUniscribe` set.

### EMF/MetaFile and GDI+ Gradients — no work planned

Windows-only (`TPdfDocumentGdi`), not portable.
