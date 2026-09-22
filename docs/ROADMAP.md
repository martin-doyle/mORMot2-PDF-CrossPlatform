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
| PAC 2024 on the macOS-built PDFs | the macOS pass checked sizes and fonts, not the tag tree; PAC runs only on Windows. veraPDF has since covered the mechanical half on all three platforms (U-1) |
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

**Its first runs found a POSIX defect PAC never reported — see U-1 below.**
Windows passes PDF/UA outright (106/106); Linux and macOS do not.

Once all three platforms are green, that is the point for a first version tag —
the project has none.

### U-1 — Glyph Widths Disagree With the Embedded Font Program (POSIX) — unprioritised

**Found 2026-09-22** by the first veraPDF runs ever made on this project, over
the Linux, macOS and Windows PDFs of 2026-09-20. **PAC 2024 passed the files
veraPDF fails**, which is the point worth keeping: the two checkers do not
overlap, so a PDF/UA claim needs both.

ISO 14289-1 **7.21.5** — the `/Widths` (and `/W`) entries must agree with the
widths in the embedded font program.

| PDF | Platform | Result | rounding | real |
|---|---|---|---|---|
| `pdf_demo_windows_final` | **Windows** | **PASS — 106/106** | 0 | 0 |
| `markdown_demo_windows_final` | **Windows** | **PASS — 106/106** | 0 | 0 |
| `report_demo_windows` | **Windows** | **PASS — 106/106** | 0 | 0 |
| `mormot_demo_windows` | **Windows** | **PASS — 106/106** | 0 | 0 |
| `pdf_demo_linux_final1` | Linux | 105 passed, 7.21.5 ×5 | 4 | **1** |
| `markdown_demo_linux_final` | Linux | 105 passed, 7.21.5 ×64 | 56 | **8** |
| `report_demo_linux_final1` | Linux | 105 passed, 7.21.5 ×63 | 63 | 0 |
| `mormot_demo_linux_final1` | Linux | 105 passed, 7.21.5 ×99 | 99 | 0 |
| `output_crossplat.pdf` | macOS | 105 passed, 7.21.5 ×11 | 10 | **1** |
| `markdown_demo.pdf` | macOS | 105 passed, 7.21.5 ×83 | 75 | **8** |

**Windows is clean, POSIX is not.** Every Windows file passes all 106 rules; no
width deviates at all. So this is **not** a property of the engine — GDI's
`GetCharABCWidths` returns the same integers that end up in the dictionary,
while the POSIX path does not. The defect is in `IPdfPlatformFont` on
FreeType, and the fix belongs in `mormot.pdf.freetype`, not in
`mormot.ui.pdf`. Windows is the reference for what the values should be.

**This is the second time a difference between the platforms turned out to be a
POSIX shortcoming rather than a platform property** — R-15b is the other. Same
conclusion: align by improving POSIX, not by relaxing Windows.

Two distinct defects hide under the one clause:

**(a) Rounding — the large majority.** One to three units: `722.16796875` in the
face against `725` in the dictionary, `556.15234375` against `555`. FreeType
returns 26.6 fixed-point values that get rounded on the way into the dictionary,
while veraPDF reads the exact `hmtx` value. Both directions occur, so it is not
a systematic floor or ceiling. Invisible in rendering, but it is what makes the
rule fail.

**(b) Genuinely wrong widths — 9 checks in two files.** Not rounding:

    font=556.15234375  dict=750   diff=+194
    font=350.09765625  dict=750   diff=+400
    font=1000          dict=750   diff=-250
    font=889.16015625  dict=778   diff=-111

The recurring `750` and `778` on the dictionary side look like a default width
written instead of the measured one — `/DW`, `fDefaultWidth`, or a glyph whose
measurement failed and fell back. Chase this half first: a wrong width is a
wrong advance and can move text visibly, whereas (a) cannot.

**The (b) counts match across the two POSIX platforms exactly** — 1 for
`pdf_demo`, 8 for `markdown_demo`, on Linux and macOS, with entirely different
font families (Liberation Sans vs Trebuchet MS). Same glyphs, same count, and
zero on Windows. `report_demo` and `mormot_demo` show no (b) at all, so it
correlates with something those two demos do not do.

**Bearing on R-17:** PDF/A-3A includes the PDF/UA requirements, so this is
inherited there — on POSIX only. Worth settling before the A level is claimed.

**`chinese_demo` and `rtl_demo` are not tagged**, so `ua1` is the wrong profile
for them; their extra failures (7.1, 6.2) are artifacts of that choice. They do
also hit 7.21.5.

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
