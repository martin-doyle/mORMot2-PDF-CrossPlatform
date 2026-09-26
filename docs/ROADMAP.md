# mORMot PDF Cross-Platform — Implementation Roadmap

Open work only. Finished work is in the git history, and the technical knowledge
it produced in `.claude/skills/` — this file repeats neither.

**State on 2026-09-26.** The engine is cross-platform, writes PDF 1.7, and its
tagged output passes PAC 2024 with accepted warnings only (W-1, a Figure in
`pdf_demo`; W-2, e-mail addresses without links in `zugferd_demo`) and veraPDF
`ua1`. PDF/A-3U with PDF/UA-1 is verified (R-17). Fonts are embedded and subset
on all three platforms; tables carry `THead`/`TBody`/`TFoot` row groups. All
three platforms build with FPC; `test_runner` is green with 229 assertions on
Windows, 288 on macOS and 268 on Linux (re-run on 2026-09-26).
**Layer 1 builds on Delphi 7** (R-19, done): 125 assertions on Win32, and the
tagged Unicode test file passes PAC 2024 and veraPDF `ua1` from Delphi 7/Win32
and FPC/Win64 alike. The macOS run found a heap-dependent `.ttc` defect in the
FreeType backend, fixed (`fonts.md` §3). The Linux re-run is done up to
veraPDF on its files (V). **Next:** R-21, R-23, then R-20.

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
| Delphi 7 build and Win32 run (R-19) | **Windows** VM with Delphi 7 (`dcc32`) |
| `veraPDF` (`ua1`, `3b`, `3u`, `3a`) | installed on macOS since 2026-09-22; the Windows and Linux files are copied there |

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

### R-21 — Compiler Switches From `mormot.defines.inc` — before R-20

**Why.** mORMot2 never writes `{$mode}` itself: every unit starts with
`{$I mormot.defines.inc}`, which sets `{$MODE DELPHI}` and `{$H+}` under FPC
and the feature conditionals (`HASINLINE`, `UNICODE`, `CPUX86`, `OSWINDOWS` …)
for every compiler. This project does it three ways:

| Form | Units |
|---|---|
| `{$I mormot.defines.inc}` | `mormot.ui.pdf`, `tests/test_runner.lpr` |
| `{$I ..\mormot.defines.inc}` | `mormot.lib.uniscribe`, `mormot.ui.core`, `mormot.ui.gdiplus` — Delphi finds it only through the extra include path in `tests/build_delphi7.bat` |
| `{$ifdef FPC}{$mode delphi}{$endif}` | `mormot.pdf.types`, `mormot.pdf.gdi`, `mormot.ui.pdfcanvas`, `mormot.ui.report`, `mormot.pdf.fpimage`, `mormot.pdf.freetype`, `mormot.pdf.harfbuzz`, `mormot.pdf.hbsubset`, the test units |

The third form is where it went wrong: in `mormot.pdf.types` and
`mormot.pdf.gdi` the switch sits after `uses` and does not take effect, so
`string` was `ShortString` there (found in R-19 step 3, patched with `{$H+}`).

**Work:** `{$I mormot.defines.inc}` before `interface` in every unit, drop the
`..\`, then drop the include path trick from the build script. One unit at a
time, `test_runner` on all three platforms after each.

**The risk — enum size.** `mormot.defines.inc` also sets `{$MINENUMSIZE 1}`
under FPC. A record handed to a C library needs 4-byte enums, as in C. Before
switching `mormot.pdf.freetype`, `mormot.pdf.harfbuzz` and `mormot.pdf.hbsubset`,
check every record of their bindings for enum fields (or set
`{$MINENUMSIZE 4}` locally around the bindings). The Windows API units are
Delphi's and FPC's own and not affected.

**With it:** a pass over the older `{$ifdef FPC}` in `src/` — e.g.
`CreateFontIndirectW(@lf)` against `(lf)` in `mormot.pdf.gdi` — for a mORMot2
function that makes the branch unnecessary. The rule is in `CLAUDE.md`
(Coding Conventions): mORMot2 first, `{$ifdef}` last, named after the feature.

### R-23 — A Layer 1 Demo for Delphi — after R-21, before R-20

**Why.** Layer 1 builds on Delphi 7 (R-19), but all seven demos go through
layer 2 or 3 — `TPdfDocumentVcl` or `TGDIPages` — so none of them builds
there. `test_runner` covers the engine; a Delphi user has nothing to start
from.

**Work.** A console demo on `TPdfDocument`/`TPdfCanvas` alone: text in an
embedded TrueType face, lines and rectangles, tagged output (`H1`, `P`,
`Figure` with alternate text). The source header states the coordinate system
(PDF points, Y origin at the bottom). An image only if one path serves both
compilers — `mormot.pdf.fpimage` is FPC-only. Built with FPC (`.lpi`, to
`bin/<cpu-os>`) and Delphi 7 (`build_delphi7.bat`), writing
`<demo>_<os>.pdf` like the other demos. Text goes in as the layer 1 API takes
it, so the `string` encoding question stays with R-20.

**Check:** veraPDF `ua1` and PAC on the files of both compilers, the same
`pdftotext` output and structure tree.

**For R-20:** the reference. A page drawn through the bridge under Delphi has
to give the same text and structure as the same page through layer 1.

### R-20 — Delphi: the TCanvas Bridge and `TGDIPages` — priority 2

**The obstacle, checked against the source 2026-09-25.** `TPdfVclCanvas =
class(TCanvas)` overrides `TextOut`, `TextExtent`, `TextWidth`, `TextHeight`,
`Rectangle`, `Ellipse`, `RoundRect`, `Draw`, `DoMoveTo` and `DoLineTo` — all
virtual in the LCL. In Delphi 7's `Graphics.pas` only `Changed`, `Changing` and
`CreateHandle` are virtual; `DoMoveTo`/`DoLineTo` do not exist; and the unit
uses `LCLIntf`/`LCLType` unconditionally.

With `reintroduce` it would compile, but a call through a `TCanvas` reference —
`C := Doc.VclCanvas; C.TextOut(…)` in every demo, and
`TGDIPages.RenderPageToCanvas(ACanvas: TCanvas)` — binds statically to the VCL
method. That draws through GDI onto the measuring DC, and the PDF stays empty.
**FPC shows the same effect today** for the four methods the bridge already
reintroduces (`FillRect`, `Polyline`, `Polygon`, `StretchDraw`): this is why
`RenderPageToCanvas` uses `Rectangle` instead of `FillRect`.

**Approach — option B.** Under Delphi the caller holds the concrete type:
`VclCanvas` returns `TPdfVclCanvas`, the methods are reintroduced, and
`TGDIPages` gets a render path taking a `TPdfVclCanvas`. The preview keeps
drawing on a real VCL canvas. The limit has to be documented: code that draws
through a plain `TCanvas` reference writes nothing into the PDF.

**Decide before starting — the encoding of `string` under Delphi.** The bridge
decodes its `string` as UTF-8 (`TPdfVclCanvas.TextOut` → `UTF8Decode`), which
is the LCL convention. In Delphi 7 a `string` literal is in the ANSI code page,
so `'Größe'` would arrive garbled. Proposed: follow mORMot2 — under Delphi,
`string` is converted from the ANSI code page (`StringToSynUnicode`), and
Unicode comes in through a separately named `RawUtf8` method. Not an overload:
under FPC both types are `AnsiString`, and the call would be ambiguous. FPC
stays as it is.

Also: the GUI demos need a `.dfm` instead of the `.lfm` under Delphi; the
`--export` path comes first.

**Not part of R-20:** Delphi 2010 and later have `TCustomCanvas` with virtual
drawing methods (not verified here), where overriding might work without typed
references. Checking that needs a current Delphi, e.g. a Community Edition.

**Rejected — option C**, the EMF route of the original `TPdfDocumentGdi`: EMF
carries no structure, so there is no tagged output, and the original in
`mORMot2/src/ui` already does this on Delphi 7.

### R-22 — Source Comments Back to the Why — priority 3

**The rule** (`CLAUDE.md`, Coding Conventions, since 2026-09-26): a source
comment says in a line or two why the code is as it is. Findings may sit in the
source while a fix is in progress; once it is accepted they move to the skill
(what future work needs) or the commit message (how it was found), and the
comment shrinks to the rule it protects.

**The state.** The older code carries the investigations themselves —
measurements, validator runs, spec clauses argued out, roadmap IDs — above all
`mormot.ui.pdf.pas` (`PrepareForSaving`, `PrepareFontSubsets`, the text
rendering chains), also `mormot.ui.report.pas`, the backends and the test
units. Part of it repeats the skills, part of it is found nowhere else.

**Work.** Unit by unit, one commit each; `mormot.ui.pdf.pas` by section. For
every long comment: is the knowledge in a skill? If not, move it there first,
then cut the comment. Comments only — `test_runner` gives the same assertion
count, and the demo PDFs are byte-identical apart from date and `/ID`.
The `///` API documentation inherited from the original mORMot2 units stays.

### V — Verification Outstanding

All three platforms build and pass `test_runner` (229 assertions on Windows,
288 on macOS, 268 on Linux). The tagged demos pass veraPDF `ua1`
106/106 on all three and PAC 2024 — measured again on 2026-09-26 for the
Windows and macOS files, `zugferd_demo` also `3u` 148/148 and Mustang. That was the stated gate for a first version tag, and
the project still has none.

| Open | Why it matters |
|---|---|
| HarfBuzz older than 2.9 | loads, but lacks `hb_subset_or_fail`. The **missing** library is covered by `tests/no_hbsubset.sh`; an old one needs an old distribution, e.g. Debian 11 |
| The U-2 width fix on Linux | exercised on macOS only: no Linux Arabic face reaches the shaper width path (`fonts.md` §10), and `TestShapedGlyphWidthFromHmtx` skips itself there |
| veraPDF in the routine runs | installed on macOS with `ua1`, `3a`, `3b`, `3u` (path in `CLAUDE.local.md`); run by hand on each platform's files, not scripted |
| veraPDF on the Linux files after R-19 | re-run on 2026-09-26: 268 assertions green, all seven demos compared with the previous run — identical apart from the date and the new `/CIDToGIDMap /Identity` in `chinese_demo` and `rtl_demo`. Still open: `ua1` on `tests/bin/aarch64-linux/tagged_unicode_lowlevel.pdf` and the tagged demos, `3u` on `zugferd_demo` |
| The `.ttc` fix on Linux | `TestTtcFaceExtraction` skips itself: the Linux machine has no `.ttc` installed (e.g. `fonts-noto-cjk` would bring one) |
| Delphi beyond layer 1 | the TCanvas bridge and `TGDIPages` — R-20; only Delphi 7 has been built |
| A build check after the demo and build changes | `abd8181`, `bfd3f30`, `2665675` touched project files, demo file names, titles, `{$R *.res}` and docs — no `src/`, so no validator re-run. Windows done. **Linux:** checked up to `bfd3f30`; still to do: rebuild with `-B` after the rename (`report_demo.lpi`, the three `.lpr` with `{$R *.res}`), `test_runner` 268. **macOS:** nothing built yet — every project with `-B`, `test_runner` 288, each demo writes `<demo>_osx.pdf` next to its executable, `report_demo --export` |

**Comparing the platforms — but not pixel by pixel.** The demos resolve
different families (Calibri/Cambria/Consolas, Liberation, Trebuchet MS/Georgia/
Andale Mono), so different advance widths, line breaks and page counts are
correct behaviour, not a defect. B-5 made the measurement platform-independent
*for one face*, not the faces themselves. What must match: `pdftotext` output,
the structure tree (roles and their counts), `pdffonts` (embedded, subset,
`uni`), page count and the PAC result. A true cross-platform render diff would
need a demo that forces one face on all three systems — worth building only if
this comparison is to be automated.

**The two checkers do not overlap.** veraPDF found U-1, which PAC had passed,
and PAC checks the tag tree, which veraPDF cannot judge. A PDF/UA claim needs
both.

### PDF/A — What R-17 Left Open — unprioritised

R-17 reached its goal on 2026-09-24: PDF/A-3U with PDF/UA-1, and A-3A and
A-3B with it, verified on all three platforms with veraPDF, Mustang and PAC.
What is left:

- **A-1B**, the commonest level overall, was to be pulled along and is not
  verified; nor are A-1A, A-2A and A-2B. Object streams, xref streams and
  transparency (R-2, R-3, R-7) are forbidden under A-1 — the first thing to
  check there.
- **The CJK peer with a `glyf` face** on Linux or Windows — see the peer entry
  below.
- **`CreateFileAttachment` accepts any file at any level**, although A-1
  forbids embedded files and A-2 allows only PDF/A ones. The caller has to
  know.
- **The engine does not enforce `Tagged` for the A levels**; untagged `pdfa3A`
  fails `3a` on 6.7.2.2 and 6.7.3.3. The documentation says so.

**Do not remove the unverified levels.** `PdfA` is public API and the
constructor takes `APdfA`; dropping enum members breaks callers of a library
whose point is to make the Windows unit available elsewhere. A-1 is not
obsolete — an archive demanding A-1 rejects A-3 precisely because A-3 permits
arbitrary attachments. Say in the documentation which levels are verified
instead.

### W-2 — E-Mail Addresses Without a Link Element (`zugferd_demo`) — accepted

PAC 2024 passes the demo but keeps one quality hint: "Link in text does not
have a Link element". It points at `seller@email.de` and `buyer@info.de`,
which the invoice data carries and the page draws as plain text. Not a
PDF/UA failure — veraPDF `ua1` passes 106/106 and PAC is green. A real link
would need a tagged link annotation, which the engine cannot write (R-18),
so the hint is accepted, like W-1.

### R-18 — Tagged Link Annotations — only on explicit request

`CreateHyperLink` writes a link annotation, but the engine has no `Link`
structure role: `TPdfStructRole` has no `psrLink`, and nothing writes the
object reference (`OBJR`) to the annotation, its `/StructParent` or the
parent-tree entry behind it.

**Measured 2026-09-24 (macOS):** a tagged document with one
`CreateHyperLink(…, 'mailto:…')` fails veraPDF `ua1` on four rules, 102/106 —
7.18.1-2 (annotation without `/Contents`), 7.18.3-1 (page without
`/Tabs /S`), 7.18.5-1 (link not tagged as a `Link` element), 7.18.5-2 (link
without an alternate description). **So `CreateHyperLink` does not belong in
tagged output today.**

**`TGDIPages.DrawLink` is safe but not a link.** Measured with a URL
(`DrawLink('example.com', 'https://example.com')`, tagged export): the text is
drawn link-styled and tagged as a `Span` inside the line's `P`, the URL is
dropped — no annotation, no `/URI` — and `ua1` passes 106/106. Conformant,
not clickable. `markdown_demo` calls it without a URL at all.

Work: the role, `OBJR` and `/StructParent` for annotations, the parent-tree
entries, `/Contents` and `/Tabs /S`; then `mailto:` links for addresses, and
`DrawLink` writing a real annotation for its URL. Done, it would also clear
W-2. Not planned: build it only when someone asks for it.

### The Unused WinAnsi Peer Beside a CJK or Arabic Font — unprioritised

The engine creates a WinAnsi peer beside every Identity-H font and emits a `Tf`
for it, but for a face that draws only CJK or Arabic that instance shows
nothing — `SetFont` selects the WinAnsi instance and writes `Tf` at once, and
the text output switches to the CID font right after (`/F1 18 Tf /F2 18 Tf`).
poppler reports `Unknown font tag` for it. Pre-existing and unrelated to CFF
(it appears on files from before R-15c).

**Measured with a `glyf` face on Windows, 2026-09-26 — not cosmetic.** The
peer was a `/TrueType` font without `/FirstChar`, `/LastChar` and `/Widths`,
which ISO 32000-1 table 111 requires for a simple TrueType font, because they
were written only when a character was used. PAC 2024 stopped on it ("'FirstChar'
not defined in TrueType font"), on the R-19 test file (Microsoft YaHei and
Tahoma) from both compilers. `chinese_demo` and `rtl_demo` carry the same
peer, but are untagged, so PAC had never run on them. On macOS the Hiragino
peer is a `/Type1` (a CFF face), and veraPDF passed PDF/A-3U and PDF/UA-1 with
it on 2026-09-24.

**Stopgap, done 2026-09-26:** a peer with no used character gets
`/FirstChar 32 /LastChar 32` and the width of the space, so the dictionary is
valid; `TestTaggedUnicode` asserts that no simple TrueType font lacks
`/FirstChar` (fails 1/5 without the change).

**The fix still open:** stop emitting the peer — write `Tf` only when text is
shown, and leave an unused peer out of the page resources and the file. That
touches the font lifecycle on every platform — see `fonts.md` §4 on the
dual-instance model. Whether the `/Type1` peer of a CFF face needs the same
stopgap (it too lacks `/Widths`) is to be checked with it.

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

### R-13 — Shaped Arabic on the Windows Path — unprioritised

**Effort:** 0.5 day | **File:** `tests/`

The advance half is done (`TestShapedGlyphWidthFromHmtx`, see `fonts.md` §10).
Left is the end-to-end half: `TestUseUniscribeIsPortable` (from R-16) is a
compile-time guard, not an output check. Nothing yet asserts that shaped Arabic
reaches the PDF on the Windows path — by checking the `/ToUnicode` entries for
`U+FExx` after drawing with `UseUniscribe` set. A Windows-side test; under
R-19 it would run on Win32 as well.

### EMF/MetaFile and GDI+ Gradients — no work planned

Windows-only (`TPdfDocumentGdi`), not portable.
