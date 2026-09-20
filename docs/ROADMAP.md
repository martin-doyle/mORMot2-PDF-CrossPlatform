# mORMot PDF Cross-Platform — Implementation Roadmap

Open work in detail, finished work as one line each. The technical knowledge of
a finished item lives in `.claude/skills/` (that is what agents read), its
reasoning in the git history — this file repeats neither.

**State on 2026-09-20.** The engine is cross-platform, writes PDF 1.7, and its
tagged output passes PAC 2024 with one accepted warning (W-1, a Figure in
`pdf_demo`). Layout is measured with the PDF font engine on every platform, so
line breaks no longer depend on the widgetset. Fonts are embedded and, on
Linux/macOS, subset (R-12); tables carry `THead`/`TBody`/`TFoot` row groups
(R-14). Five of the six demos are verified on Linux; `mormot_demo` waits for a
sample database.

**Windows pass, 2026-09-20 — complete.** All six demos and `test_runner` build
and link on Windows (x86_64-win64, FPC 3.2.2 / Lazarus), and PAC 2024 is green
on the tagged demos. The pass closed **R-15** and **R-15a** (subsetting by glyph
ID, once per face, on every platform) and **R-16** (Arabic was never shaped
there). All six demos now embed subsets; none pins the whole face any more.

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
| `veraPDF --flavour ua1` | any; not installed on the dev machine yet |

**PAC caveat.** The traffic-light status is not enough: a flat tree of
individually valid `Table`/`TR`/`TD` elements passes while the nesting is
broken. Always open the *Logical Structure* view as well.

**Toolchain on the Linux development machine.** `lazbuild` lives at
`/home/parallels/fpc-fixes/lazarus/lazbuild` (not on `PATH`), the mORMot2
sources at `/home/parallels/synopse/mORMot2`. Linking the demos needs GTK2
development symlinks, which are absent: symlink `libgtk-x11-2.0.so`,
`libgdk-x11-2.0.so` and `libatk-1.0.so` to their `.so.0` files in a scratch
directory and build with `lazbuild --opt=-Fl<dir>`. Available for checking
output: `pdffonts`, `pdfinfo`, `pdftotext`, `pdftoppm`, `python3`. Missing:
`qpdf`, `mutool`, `veraPDF`, ImageMagick.

**Toolchain on the Windows machine.** `lazbuild` at `C:\lazarus\lazbuild.exe`
with its bundled FPC 3.2.2 (`C:\lazarus\fpc\3.2.2\bin\x86_64-win64`), mORMot2
sources beside this repo. Target is **x86_64-win64**; an aarch64-win64 FPC is
not usable — mORMot2 ships no static libraries for it. Build every project with
`-B`: stale `.ppu` files in `examples/*/lib/` outlive a unit-path change and
will hide it. For checking output there is only `pdftotext`, and it is xpdf
4.00, not poppler — no `-bbox`, so use `-layout` for column and line alignment.
Missing: `pdffonts`, `pdfinfo`, `pdftoppm`, `python3`, `strings`. `/BaseFont`
survives as plain text in the file, so
`grep -a -oE "/BaseFont[ ]*/[A-Za-z0-9+,#_-]+"` substitutes for `pdffonts` well
enough to tell a subset (six-letter prefix) from a whole face.

**Checking a change.** Build all six demos and `test_runner`, then compare the
PDFs with the previous run: file size, `pdffonts`, `pdftotext` output, and the
pages rendered with `pdftoppm -r 110 -png` compared pixel by pixel. A change
that is meant to be invisible has to come out pixel-identical.

---

## Open

### V — Verification Outstanding on Other Platforms

R-12 and R-14 are merged and accepted on Linux, and the Windows pass is done.
macOS has not been built since, and Linux has not been rebuilt since R-15.

| What | Where | Why it matters |
|---|---|---|
| ~~PAC 2024~~ | [`docs/samples/`](samples/) — the Linux-built PDFs of both demos | done — green, W-1 the only warning |
| macOS build, `test_runner`, demos | R-12, R-14 | Geeza Pro is the only face that exercises the PUA glyph path (`fonts.md` §10); macOS also has the `.ttc` CJK face |
| ~~Windows build, `test_runner`, demos~~ | R-12, R-14 | done — builds and links; subsetting arrived with R-15, so the comparison is against R-15's own figures, not against the pre-R-12 state. Found R-16 |
| Linux rebuild of all six demos | R-15, R-15a, R-16 | the engine changes are argued to be POSIX-neutral from the `{$ifdef}` structure, not measured. Expect every PDF unchanged except `chinese_demo` and `rtl_demo`, which no longer pin the whole face |
| `mormot_demo` run | R-14, tagged export, `--export` batch mode, table colours | needs a sample database; the demo compiles but has never run |
| Run on a machine **without** `libharfbuzz-subset` | R-12 fallback | `TestSubsetFallbackWithoutSubsetter` only simulates it by clearing `PdfFontSubsetter`; the loader path itself — missing library, or HarfBuzz older than 2.9 — has never run |

### Order of Work (agreed 2026-09-20)

1. ~~**Windows first.**~~ **Done 2026-09-20.** The worry was that the code might
   not compile there at all — the R-12 hook casts `HDC` to `TPdfPlatformDC` and
   declares `sub` inside the `{$ifdef USE_UNISCRIBE}` branch. It compiles. All
   six demos, `test_runner` and PAC 2024 are green. What the pass cost was one
   unit-path fix across the `.lpi` files (they pointed at mORMot2's own
   Windows-only `src/lib` instead of this project's), and what it found was
   **R-16**.
2. ~~**R-15.**~~ **Done 2026-09-20.** Taken before R-16 because it affects five
   of the six demos while R-16 affects one, and because the two turned out not
   to touch each other: `rtl_demo` pins `EmbeddedWholeTtf := true`, so R-15
   changes nothing about the output R-16 is diagnosed from. Its Arabic
   acceptance step had to wait for R-16, and passed once R-16 landed:
   `rtl_demo` 2,072,378 → 88,198 B with the shaped presentation forms intact.
3. ~~**R-16.**~~ **Done 2026-09-20.** Windows is now green end to end.
4. **macOS in two passes.** First **without** HarfBuzz installed: that covers
   the loader-absent row of the table above at no extra cost. Then
   `brew install harfbuzz` and repeat, with Geeza Pro for the PUA glyph path
   and the `.ttc` CJK face.
5. **Compare the platforms — but not pixel by pixel.** The demos resolve
   different families (Calibri/Cambria/Consolas, Liberation, Trebuchet
   MS/Georgia/Andale Mono), so different advance widths, line breaks and page
   counts are correct behaviour, not a defect. B-5 made the measurement
   platform-independent *for one face*, not the faces themselves. What must
   match: `pdftotext` output, the structure tree (roles and their counts),
   `pdffonts` (embedded, subset, `uni`), page count and the PAC result. A
   pixel comparison stays valid **within** one platform, before against after.
   A true cross-platform render diff would need a demo that forces one face on
   all three systems — worth building only if this comparison is to be
   automated.
6. **`veraPDF --flavour ua1`** has never run. It checks PDF/UA mechanically and
   is scriptable, unlike PAC's GUI — the objective half of step 5. R-15 made
   this more pressing: Windows tagged output is subset now, so the `/ToUnicode`
   round-trip is carried by the subset rather than by a whole face.

`mormot_demo` joins whichever pass is current when its sample database is
ready. Once all three platforms are green, that is the point for a first
version tag — the project has none.

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

The same is true of **CFF/OpenType outlines**. On POSIX hb-subset refuses them
and `PrepareFontSubsets` falls back to the whole face. What `CreateFontPackage`
does with a CFF face is untested — every face in the demos is `glyf`-based.

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

R-16 was the mirror case and its regression test is in place —
`TestUseUniscribeIsPortable` pins the property that had silently compiled away.
That test is a compile-time guard, not an output check: nothing yet asserts that
shaped Arabic actually reaches the PDF. An end-to-end test belongs with this
item, checking the `/ToUnicode` entries for `U+FExx` after drawing with
`UseUniscribe` set.

### EMF/MetaFile and GDI+ Gradients — no work planned

Windows-only (`TPdfDocumentGdi`), not portable.

---

## Completed

Details are in the git history and in `.claude/skills/`; the note below is what
still constrains new work.

| ID | What | Note that still applies |
|---|---|---|
| P1-A…P1-C | CJK fonts per platform, PDF 1.7 output | PDF/A and Tagged raise `FileFormat` on their own |
| P2-A | HarfBuzz RTL shaping (Linux/macOS) | the FT face must be sized before shaping, or every advance comes back 0 — `fonts.md` §10 |
| P2-C | Font zoom in the preview (`FontScale`) | |
| P3 | Tagged PDF — text structure tags | |
| R-1…R-4 | AES-128, xref streams, object streams, XMP | object streams hide dictionaries from a plain text search in tests |
| R-5, R-6 | Table and figure tags | emitted flat; B-1 gave them their nesting |
| R-7…R-9 | Transparency, `LineHeightFactor`, repeated table header | a repeated header row is an artifact, never a second `THead` |
| B-1 | Nested struct tags for tables and lists | containers own no marked-content region |
| B-2 | One tag per paragraph instead of one per line | a block interrupted by a page break is reopened, not restarted |
| B-3 | One tag per sentence, styled runs as `Span` | only the coordinate-less overloads share a line and a tag |
| B-4, B-5 | Layout and text metrics from the PDF font engine, not the LCL | the font flags decide the metrics, so they must be set before the first draw command |
| B-6 | `/Alt` as a PDF string, on the `StructElem` | |
| P-6 | Tagged output selects the PDF/UA font mode | `Tagged` raises when set after the first page |
| B-7…B-11 | PAC findings: `DisplayDocTitle`, XMP stream and title, `/Scope` on `TH`, tagged path objects | |
| B-12…B-14 | Graphics state inside a path object, `Figure` without `/BBox`, headings without bookmarks | `DrawHeading` writes the bookmark; a centred text does not |
| W-1 | "Possibly inappropriate use of figure" (`pdf_demo`) | accepted, documented in the demo |
| R-12 | Font subsetting on POSIX via hb-subset | PDF/A-1, symbol fonts and CFF faces keep the whole face; the input is the union of code points **and** glyph IDs |
| R-14 | Table row groups `THead`/`TBody`/`TFoot`, `DrawTableFooter` | `TGDIPages` emits the groups itself; the low-level API leaves them to the caller |
| R-15 | Windows: `CreateFontPackage` keep list as glyph IDs (`TTFCFP_FLAGS_GLYPHLIST`) | accepted for Latin, CJK and Arabic; `PdfCanSubsetRetainingGids` is now the one place that decides whether tagged output may subset |
| R-15a | Both platforms subset once per face, through `PrepareFontSubsets` | the Windows subsetter moved out of `PrepareForSaving` into `TPdfFontTrueType.SubsetWithFontPackage`, called per face; the `.ttc` detection moved with it |
| R-16 | Arabic was never shaped on Windows | `UseUniscribe` was declared inside `{$ifdef USE_UNISCRIBE}`, a symbol defined in `mormot.ui.pdf` that does not reach its callers — so `{$ifdef USE_UNISCRIBE} Doc.UseUniscribe := true; {$endif}` compiled to nothing. **Never gate a client-side assignment on a symbol the unit defines for itself** |
| — | `report_demo`, `mormot_demo`: tagged export, `TTableLayout`, `--export` batch mode | the batch mode still needs a display (`TGDIPages` is an LCL control) |
| — | Crash fix: stale `fUsedWide[]` address in `GetWideCharWidth` | found on aarch64: the call that indexes the array also reallocates it |

### Measured Effect of R-12 (Linux)

| PDF | Before | After |
|---|---|---|
| `markdown_demo.pdf` (tagged) | 1,428,389 B | 46,407 B |
| `output_crossplat.pdf` (tagged) | 800,923 B | 19,256 B |
| CJK, `EmbeddedWholeTtf := False` | 2,309,640 B | 10,848 B |
| Arabic, `EmbeddedWholeTtf := False` | 500,092 B | 15,090 B |

Every page pixel-identical, `pdftotext` unchanged, every face `emb=yes sub=yes`.
Windows was unaffected until R-15.

### Measured Effect of R-15 (Windows)

| PDF | Before | After |
|---|---|---|
| `markdown_demo.pdf` (tagged) | 4,325,899 B | 230,392 B |
| `output_crossplat.pdf` (tagged) | 2,796,454 B | 114,809 B |
| CJK, `EmbeddedWholeTtf := False` | 23,924,686 B | 39,279 B |
| Arabic, after R-16 let it subset | 2,072,378 B | 88,198 B |

`markdown_demo` is the only one R-15a improved further, 253,296 → 230,392 B:
it was embedding `Calibri` and `Cambria` twice, and now embeds 7 streams for its
7 faces. The other two had no face used by more than one font object.

`pdftotext` output byte-identical in every case. Every subset keeps its `cmap`
and its `numGlyphs` — 7048 → 7048 for Calibri, 30209 → 30209 for Microsoft
YaHei — which is what makes Identity-H and `/ToUnicode` survive. Two runs of one
document now produce the same subset tags; the files differ only in `/ID`.

What R-15 also fixed, both pre-existing and both found by the test suite:

- **PDF/A-1 was subset on Windows.** `PrepareForSaving` had no equivalent of the
  `fPdfA in [pdfa1A, pdfa1B]` guard R-12 put on `PrepareFontSubsets`, so
  PDF/A-1 documents lost the whole face they are required to keep (no `/CIDSet`
  is written). `TestPdfA1StillWholeFace` had been failing on Windows before any
  R-15 work.
- **The Type0 font kept the untagged name.** Only its descendant CIDFont and the
  `/FontDescriptor` got the subset tag, because the assignment was guarded by
  `WinAnsiFont.GetSubset <> nil`, which is never true on the Windows path. 9.6.4
  wants the two to agree. Invisible before, since Windows rarely subset; R-15
  made it the normal case.
