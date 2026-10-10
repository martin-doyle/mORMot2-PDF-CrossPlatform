# mORMot2 PDF Cross-Platform — Agent Reference

Cross-platform PDF and report engine for Windows, Linux and macOS, based on mORMot2.
The original document (`reference/mormot.ui.pdf.pas`) was Windows/GDI-only; this project abstracts all platform calls behind interfaces.

---

## Skills — Mandatory First Step

**RULE: Read the relevant skill file(s) BEFORE doing anything else — before reading source files, before searching, before planning.**

Skills contain complete, distilled API and architectural knowledge. The main source files are very large (mormot.pdf.pas is 11,800+ lines, mormot.pdf.canvas.pas 3,000+, mormot.ui.report.pas 2,900+); reading them without necessity wastes context and time.

| Skill | When to use |
|---|---|
| `.claude/skills/pdf-engine.md` | TPdfDocument, TPdfDocumentVcl, TPdfCanvas — full API, enums, encryption, FPImage |
| `.claude/skills/report-engine.md` | TGDIPages — all methods, tables, command recording, global helpers |
| `.claude/skills/platform-backends.md` | IFontProvider/Enumerator/DC, optional IFontShaper/IFontSubsetter (mormot.lib.core) — interfaces, backends, data types |
| `.claude/skills/call-graph.md` | Execution paths: registration → rendering → serialization (font lifecycle 4a–4d, image, bookmarks) |
| `.claude/skills/fonts.md` | Font handling deep reference: dual-instance model, CMAP loading, text rendering chains, RTL/Arabic |

### Source File Access — Restricted

**Do NOT read source files in `src/` without explicit user permission.**

If a skill does not contain sufficient detail for the task:
1. State specifically what information is missing from the skill.
2. Ask the user: "The skill does not cover [X]. May I read [file] to check [specific thing]?"
3. Wait for confirmation before opening any source file.

Permitted without asking:
- Reading demo files in `examples/`
- Reading test files in `tests/`
- Reading `docs/` documentation
- Reading skill files in `.claude/skills/`
- Reading `CLAUDE.md` itself

All files under `src/` require justification and user approval before reading.

---

## Status

| File | Purpose | Status |
|---|---|---|
| `src/pdf/mormot.pdf.pas` | PDF engine (cross-platform) | Production |
| `src/core/mormot.ui.report.pas` | Report engine (`TGDIPages`) | Production |
| `src/core/mormot.ui.reportpreview.pas` | Preview window and printing for `TGDIPages` (LCL) | Production |
| `src/core/mormot.ui.pdfcanvas.pas` | TCanvas bridge (`TPdfDocumentVcl`) | Production |
| `src/pdf/mormot.pdf.canvas.pas` | VCL/LCL adapter: `TBitmap`/`TGraphic` images; `TPdfDocumentGdi`, `RenderMetaFile`, printer helpers (Windows) - R-28 Phase 2 | Production |
| `src/pdf/mormot.pdf.types.pas` | PDF types; former font type names as aliases of mormot.lib.core | Production |
| mORMot2 `src/lib/mormot.lib.uniscribe.pas` | GDI backend (Windows), Uniscribe shaper and FontSub subsetter, beside their bindings | Production |
| mORMot2 `src/lib/mormot.lib.freetype.pas` | FreeType2 backend (POSIX) | Production |
| mORMot2 `src/lib/mormot.lib.harfbuzz.pas` | HarfBuzz shaper (RTL/complex scripts) and hb-subset subsetter (R-12) | Production |
| `src/pdf/mormot.pdf.fpimage.pas` | FPImage bitmap adapter | Production |

## File Structure

```
src/
  pdf/                          the units under their trunk names (R-28)
    mormot.pdf.pas              PDF objects, TPdfDocument, TPdfCanvas - no VCL/LCL
    mormot.pdf.canvas.pas       TBitmap/TGraphic images, TPdfDocumentGdi and EMF (Windows)
    mormot.pdf.defines.inc      the USE_* switches of mormot.pdf and mormot.pdf.canvas
    mormot.pdf.types.pas        PDF types, aliases of the mormot.lib.core font types
    mormot.pdf.fpimage.pas      Bitmap embedding (FPImage)
  core/                         the units of the later phases
    mormot.ui.report.pas        TGDIPages — layout engine, no forms or printer
    mormot.ui.reportpreview.pas ShowReportPreview, PrintReport (LCL)
    mormot.ui.pdfcanvas.pas     TPdfDocumentVcl, TPdfVclCanvas
    mormot.ui.core.pas          UI helper functions   } the trunk's units of mORMot2 src/ui (only the include path differs),
    mormot.ui.gdiplus.pas       GDI+ support (Windows) } which is not on the search path
  (the backends are mORMot2 units in src/lib: mormot.lib.uniscribe on Windows
   (GDI), mormot.lib.freetype and mormot.lib.harfbuzz - shaper and subsetter,
   each library optional - on POSIX)
examples/
  pdf_demo/           Demo 1 — TPdfDocumentVcl, TCanvas API, Tagged PDF (console)
  report_demo/        Demo 2 — TGDIPages, GUI preview, tagged PDF
  markdown_demo/      Demo 3 — TGDIPages, semantics, tables, LineHeightFactor (console)
  mormot_demo/        Demo 4 — TGDIPages + mORMot ORM + TTableLayout, GUI, tagged PDF
  chinese_demo/       Demo 5 — CJK text, subset embedding (console)
  rtl_demo/           Demo 6 — Arabic RTL, HarfBuzz/Uniscribe shaping (console)
  zugferd_demo/       Demo 7 — PDF/A-3U + PDF/UA-1, ZUGFeRD/Factur-X invoice with embedded XML (console)
  layer1_demo/        Demo 8 — TPdfDocument/TPdfCanvas alone, tagged; FPC, Delphi 7 and Delphi 2010 (console)
  (each demo folder carries a short README.md; the source header of its .lpr
   (`layer1_demo`: .dpr) says the same thing in two sentences)
tests/
  test_runner.lpr              runs every suite below (green: 506 assertions on Windows with FPC, Delphi 13 and Delphi 7, with the CJK and symbol faces of Windows 11 - Delphi 2010 last measured at 448 (#27); 477 on macOS with Geeza Pro, Hiragino Sans GB and Helvetica, 453 on Linux with fonts-noto-cjk — the rest are skips; the golden files add two per case with or without a baseline. Delphi 13, measured before the golden files: 259 on Windows, 171 on Linux64, 129 on Android64, layer 1 only)
  test_defines.inc             PDF_HASVCLCANVAS: the TCanvas bridge suites (all compilers since R-20)
  build_delphi7.bat            dcc32 build of one project (R-19)
  build_delphi2010.bat         the same with Delphi 2010, warnings on (R-25, Unicode Delphi)
  delphi7_core.dpr             Delphi 7 compile guard for the core units
  delphi13/test_runner.dproj   Delphi 13 IDE project: Win32, Win64, Linux64, Android64 (R-27)
  delphi13/android/            FMX host for Android: build.cmd, run-emulator.cmd -Run, BUILD-FREETYPE.md
  no_hbsubset.sh               Linux: tests and console demos with libharfbuzz-subset hidden
  pdfcheck.lpr                 refactoring check tool: run the demos, compare their PDFs normalized, structure roles, fonts (docs/REFACTORING.md)
  pdf_inspect.pas              reading written PDFs back: inflate, normalize, roles, fonts — shared by the tests and pdfcheck
  test_pdf_crossplatform.pas   platform backend, text shaper, TTC extraction
  test_pdf_smoke.pas           PDF basics, tagged output, struct tree, tagged Unicode, the shaping switch (through TPdfCanvas; one bridge test)
  test_report_crossplatform.pas report engine, tables, tagged export
  test_pdf_subset.pas          font subsetting: IFontSubsetter and TPdfDocument
  test_pdf_pdfa.pas            PDF/A-3: associated files, XMP schemas, PdfMetadataFacturX, level U
  test_pdf_golden.pas          golden files: generated PDFs against this machine's baseline (layers 1-2)
  test_pdf_images.pas          golden files of the image paths (raw pixels on every compiler; TBitmap formats, reuse, color key, JPEG) and of EMF (TPdfDocumentGdi, RenderMetaFile; Windows)
  test_report_golden.pas       the same for TGDIPages (layer 3)
  test_coordinates.pas         page geometry
  test_report_coordinates.pas  report geometry
reference/
  mormot.ui.pdf.pas   Original Windows/GDI file (12,514 lines, reference only)
docs/
  DEMOS.md            Learning path: the 8 demos step by step
  API_REFERENCE.md    TCanvas methods, TReportFormat, TTableLayout
  ROADMAP.md          Open work in detail, completed work as one line each
  REFACTORING.md      mORMot Refactoring: integration into the trunk as src/pdf (R-28)
  CI.md               GitHub Actions for FPC/Lazarus: rule, install options, this project's jobs (R-24)
CHANGELOG.md          Released versions; a release's entry is written from ROADMAP "To Announce", the one list of user-visible changes
.claude/skills/
  pdf-engine.md       TPdfDocument, TPdfDocumentVcl, TPdfCanvas — full API, enums, encryption, FPImage
  report-engine.md    TGDIPages — all methods, tables, command recording, global helpers
  platform-backends.md IFontProvider/Enumerator/DC, IFontShaper/IFontSubsetter — interfaces, backends, registration, the shaping switch
  call-graph.md       Complete call graph: font lifecycle (4a–4d), rendering, image, bookmarks
  fonts.md            Font handling deep reference: dual-instance model, CMAP loading, text rendering chains, RTL/Arabic
```

## Architecture

3 layers + platform abstraction layer:

```
TGDIPages (mormot.ui.report)          <- High-level layout
    | RenderPageToCanvas()
TPdfDocumentVcl / TPdfVclCanvas       <- TCanvas bridge
    | automatic coordinate conversion
TPdfCanvas / TPdfDocument (mormot.pdf) <- Low-level PDF
    | via interfaces
IFontProvider (→ IFontFace) / IFontEnumerator
    |                + optional: IFontShaper, IFontSubsetter
GDI (Windows)  /  FreeType2 (Linux/macOS)
+ Uniscribe shaping   + HarfBuzz shaping and hb-subset when the libraries load
  and FontSub subsetting
```

For all execution paths through this architecture: `.claude/skills/call-graph.md`
For interface and backend details: `.claude/skills/platform-backends.md`

## The 8 Demos

| Demo | API | Type | Highlights |
|---|---|---|---|
| pdf_demo | `TPdfDocumentVcl` | Console | TCanvas basics, Tagged PDF (H1/P/Figure, Table with THead/TBody) |
| report_demo | `TGDIPages` | GUI | WYSIWYG preview, tagged PDF export, `TTableLayout`, `--export` batch mode |
| markdown_demo | `TGDIPages` | Console | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| mormot_demo | `TGDIPages` + ORM | GUI | SQLite via TRestClientDB, TTableLayout, tagged PDF, `--export` batch mode |
| chinese_demo | `TPdfDocumentVcl` | Console | CJK text, subset embedding |
| rtl_demo | `TPdfDocumentVcl` | Console | Arabic RTL, HarfBuzz/Uniscribe shaping |
| zugferd_demo | `TGDIPages` | Console | PDF/A-3U + PDF/UA-1, page read from the embedded XML, `AddExportPdfAttachment`, `PdfMetadataFacturX`, sample invoice XML of XRechnung for Delphi |
| layer1_demo | `TPdfDocument` | Console | Layer 1 only, PDF points (Y=0 bottom), tagged H1/H2/P/Figure and a Table with THead/TBody/TFoot, UTF-8 via `TextOutW`; `uses mormot.pdf` alone, no VCL/LCL; builds with Delphi 7, as do all console demos |

Detailed description with code examples: `docs/DEMOS.md`

## Design Patterns for Agents

### Command Recording

`TGDIPages` records all commands as a `TDrawCommand` array — no direct canvas rendering.
Rendering only happens in `RenderPageToCanvas(ACanvas, PageIndex)`, called by preview and PDF export.

New features: add a command, do not draw directly on canvas. Follow the pattern from existing Draw* methods.

Important: `RenderPageToCanvas` uses `ACanvas.Rectangle()` instead of `FillRect()`, because `FillRect` does not trigger brush synchronisation in `TPdfVclCanvas`.

### Coordinate Systems

| Layer | Unit | Y origin |
|---|---|---|
| `TGDIPages` | 1/100mm | top (Y=0) |
| `TPdfVclCanvas` | pixels (96 DPI) | top (Y=0) |
| `TPdfCanvas` | PDF points (72 DPI) | bottom (Y=0) |

Conversions happen automatically in `TPdfVclCanvas`. Only convert manually when accessing `TPdfCanvas` directly.

### Font Handling

Two modes — do not mix:

| Mode | Property | Fonts |
|---|---|---|
| Type1 (no embedding) | `StandardFontsReplace := True` | Helvetica, Times, Courier |
| TrueType (with embedding) | `EmbeddedTTF := True` | OS-specific via `GetExportFonts()` (report) or `GetPdfFonts()` (layers 1–2) |

**Tagged PDF selects the mode itself.** `Tagged := True` / `ExportPdfTagged := True`
forces the TrueType mode, because PDF/UA does not allow non-embedded base-14
fonts. The faces are subset on every platform — `libharfbuzz-subset` on
Linux/macOS, `CreateFontPackage` with a glyph keep list on Windows (R-15) —
both keeping glyph IDs, so `/ToUnicode` stays valid. Both
have to be set **before the first page is drawn** — the font flags decide which
metrics the layout is measured with — and both raise `ESynException` if set later.

Full details including dual-instance model, CMAP loading, text rendering chains, and RTL/Arabic limitations: `.claude/skills/fonts.md`

### Tagged Tables

`TGDIPages` groups the rows itself: `DrawTableHeader` opens `THead`, the first
`DrawTableRow` switches to `TBody`, `DrawTableFooter` (a totals line) switches
to `TFoot`, `EndTable` closes both group and table. A header row repeated on a
continuation page is an artifact and opens no second `THead`.

With the low-level API the caller opens the groups, as `pdf_demo` shows.
Details: `.claude/skills/report-engine.md` (Tables), `.claude/skills/call-graph.md` (Path 10)

### One Unit per Layer

A program uses the unit of its layer: `mormot.ui.report` (layer 3),
`mormot.ui.pdfcanvas` with `mormot.pdf` (layer 2), `mormot.pdf`
(layer 1). What a layer's API takes from below is re-exported by that layer —
`mormot.ui.report` re-exports the PDF/A levels, `TPdfFileFormat`, `afr*` and
`PdfMetadataFacturX`. Never put `mormot.pdf` beside `mormot.ui.report`:
both declare `psA4`, and `TRect` differs from the LCL's, so the uses order
decides which one a name means. Details: `.claude/skills/report-engine.md`

The platform units need no `uses` in a program: `mormot.pdf` brings
`mormot.lib.uniscribe`, or `mormot.lib.freetype` and `mormot.lib.harfbuzz`; a
missing HarfBuzz library only leaves shaping or subsetting off, a missing
`libfreetype` makes `TPdfDocument.Create` raise.
**Shaping is one switch**, `UseUniscribe` — Uniscribe on Windows, HarfBuzz on
Linux/macOS, only for runs of a script that needs it (or `RightToLeftText`
runs). `RightToLeftText` is the direction only. Never set either behind a
conditional. Details: `.claude/skills/platform-backends.md` (Registration)

### Platform Abstraction

New platform feature: use interface method, do not add `{$ifdef}` inside `mormot.pdf.pas`.
Details on interfaces and registration: `.claude/skills/platform-backends.md`

## Coding Conventions (mORMot2 style)

- **Language: English only** — all code, comments, and identifiers must be in English
- **Prefer mORMot2 functions** over FPC/LCL alternatives (e.g. `FormatUtf8` over `Format`, `RawUtf8` over `string` for internal strings, `DateToIso8601(Now, false)` over `FormatDateTime('yyyymmdd', …)` for file names)
- **Check that a mORMot2 function exists in this tree** before using it: the version here has no `DateToString8`, though older notes suggested it
- **Compiler differences: mORMot2 first, `{$ifdef}` last** — Delphi 7 is a
  target (R-19), so FPC-only RTL and language features break the build:
  - a missing or different RTL function: the mORMot2 function that matches the
    **string type of the data** — `PosEx` for `RawUtf8`/`RawByteString`,
    `PosExString` for `string`, `MinPtrInt` for `Min`. They are implemented per
    compiler and convert nothing; a `RawUtf8` function fed a `string` makes
    the compiler convert on Unicode Delphi
  - a missing language feature with no library counterpart (`Default()`,
    `for..in`, records with methods, `Exit(Value)`): write it the old way,
    for every compiler
  - `{$ifdef}` only for a genuine difference, named after the **feature**, not
    the compiler: `PDF_HASVCLCANVAS` (tests/test_defines.inc), not `FPC`.
    Compiler switches come from `{$I mormot.defines.inc}`, never from a bare
    `{$mode delphi}` (roadmap R-21)
- `RawUtf8` instead of `string` for internal strings
- **No non-ASCII in string literals** — in `src/`, demos and tests: FPC
  converts such a literal under `{$CODEPAGE UTF8}` (R-21: a default parameter
  `'• '` arrived as `'?'`), Unicode Delphi reads the UTF-8 file as the ANSI
  code page (R-25: `—` became `â€”`). Put the character in a `RawUtf8`
  constant, as code points for compilers with code-page strings and as UTF-8
  bytes for Delphi 7:
  `LIST_BULLET: RawUtf8 = {$ifdef HASCODEPAGE} #$2022' ' {$else} #$E2#$80#$A2' ' {$endif};`
  Never the bytes alone: Unicode Delphi reads `#$E2` as a character of the
  ANSI code page and encodes it again. Code points with four digits
  (`#$00E4`, not `#$E4`) — only those are independent of the code page. On
  Delphi 2010 a single such character outside cp1252 draws W1062; the bytes
  are right
- No blank lines between `begin`/`end` blocks
- Interfaces with reference counting (`TInterfacedObject`)
- Error handling via `ESynException`
- No RTTI where avoidable
- **Comments: short, the why only.** A source comment says in a line or two
  why the code is as it is, so nobody removes what looks redundant. While a
  fix is in progress, findings may sit in the source; once it is accepted,
  move them to the matching skill in `.claude/skills/` (what future work needs
  to know) or the commit message (how it was found: measurements, validator
  output, dead ends), and cut the comment back to the rule it protects. One
  home per fact — do not retell a skill paragraph in the code. The older code
  does not follow this yet (roadmap R-22)

## Build Commands

```bash
# Windows:
"C:\lazarus\lazbuild.exe" examples/pdf_demo/pdf_demo_crossplat.lpi -B
"C:\lazarus\lazbuild.exe" examples/report_demo/report_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/markdown_demo/markdown_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/mormot_demo/mormot_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/chinese_demo/chinese_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/rtl_demo/rtl_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/zugferd_demo/zugferd_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/layer1_demo/layer1_demo.lpi -B
"C:\lazarus\lazbuild.exe" tests/test_runner.lpi -B
tests\bin\x86_64-win64\test_runner.exe --noenter
"C:\lazarus\lazbuild.exe" tests/pdfcheck.lpi -B   # refactoring checks: docs/REFACTORING.md

# Linux/macOS:
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
lazbuild examples/markdown_demo/markdown_demo.lpi -B
lazbuild examples/chinese_demo/chinese_demo.lpi -B
lazbuild examples/rtl_demo/rtl_demo.lpi -B
lazbuild examples/report_demo/report_demo.lpi -B
lazbuild examples/mormot_demo/mormot_demo.lpi -B
lazbuild examples/zugferd_demo/zugferd_demo.lpi -B
lazbuild examples/layer1_demo/layer1_demo.lpi -B
lazbuild tests/test_runner.lpi -B && tests/bin/<cpu-os>/test_runner
lazbuild tests/pdfcheck.lpi -B

# Delphi 7 (Win32; layer 1, the bridge and the TGDIPages core) — MORMOT2 must point to the mORMot2 checkout:
tests\build_delphi7.bat tests\test_runner.lpr
bin\d7\test_runner\test_runner.exe --noenter
tests\build_delphi7.bat examples\layer1_demo\layer1_demo.dpr
tests\build_delphi7.bat examples\markdown_demo\markdown_demo.lpr
rem the other demos the same way, from their .lpr; the GUI demos as the
rem batch export only (--export), zugferd_demo and mormot_demo run from their
rem demo folder, where they find factur-x.xml and data\

rem Delphi 2010 (Win32, R-25: Unicode Delphi) - the same projects the same way:
tests\build_delphi2010.bat tests\test_runner.lpr
bin\d2010\test_runner\test_runner.exe --noenter
```

On Windows every test runner waits for Enter at the end unless it gets a
parameter — pass `--noenter` when it runs unattended.

**Golden files.** `test_runner --golden-record` writes this machine's baseline
to `golden/<os>_<cpu>_<compiler>/` next to the executable (not versioned:
embedded faces depend on the fonts installed); a normal run compares against
it and skips without one. Record on the commit before a change, then run on the
change: a difference names the object, the byte and the line of each side,
and the new file is kept as `<case>.actual.pdf`. Compared after inflating the
streams and blanking `/ID`, subset tags, dates, `/Length` and offsets
(`pdf_inspect.NormalizePdf`, also used by `pdfcheck`). The golden files stay
in that folder: never copied with the demo PDFs, never given to veraPDF or
PAC — how a check session runs and what goes where: `docs/REFACTORING.md`,
"A Check Session".

Every project builds to `bin/<cpu-os>/` — the executable, the PDF it writes
and its logs — and its units to `lib/<cpu-os>/` (`<cpu-os>` as FPC names the
target, e.g. `aarch64-linux`, `x86_64-win64`, `aarch64-darwin`). The Delphi
builds keep their own layout under `bin\d7\` and `bin\d2010\`.

A Lazarus installed outside the distribution packages — `fpcupdeluxe`, a
source build — usually leaves `lazbuild` off `PATH`; use the full path then.
Record the paths of your own machines in `CLAUDE.local.md`, which is not
versioned; `CLAUDE.local.md.example` shows the format, and Claude Code reads
the file alongside this one.

Two build notes that are not machine-specific: linking the demos on Linux needs
the GTK2 development symlinks, which distributions do not always install, and
the macOS linker prints `ld: warning: object file … built for newer macOS
version` for the prebuilt mORMot2 units — noise, not an error. See
`docs/ROADMAP.md` (Working Method).

The two GUI demos export without their window, which is how they are checked:
`report_demo --export out.pdf`. On Linux/GTK2 this still needs a
display (`xvfb-run` otherwise); on macOS Cocoa runs it headless. The report
itself is in each demo's `uReport.pas`; the form only passes its options.

## Open Items

- **mORMot Refactoring** (R-28, in progress): before any step of it, read
  `docs/REFACTORING.md` — its rules apply on top of this file
- **Font subsetting**: default (`EmbeddedWholeTtf = False`) on all platforms, two implementations, both keeping the original glyph IDs and therefore safe for CJK, shaped Arabic and tagged output. **Linux/macOS** (R-12): `IFontSubsetter` (`mormot.lib.core`) implemented by `mormot.lib.harfbuzz` (`libharfbuzz-subset`); 97–99.5% smaller PDFs. **Windows** (R-15): `IFontSubsetter` implemented by `mormot.lib.uniscribe` (`CreateFontPackage` with a glyph keep list, `TTFCFP_FLAGS_GLYPHLIST`; the face of a `.ttc` found from the bytes) - one path through `FontSubsetter` on every platform since R-28 Phase 1 W2. The whole face is embedded instead for PDF/A-1 (no `/CIDSet`), for symbol fonts on POSIX (R-15b) and when `libharfbuzz-subset` is missing. See `.claude/skills/fonts.md` §3, §9
- **CFF faces are subset too** (R-15c, done): a CFF-flavoured face goes to `/FontFile3` with `/Subtype /OpenType` as a `CIDFontType0`; `glyf` goes to `/FontFile2`. `PdfFontFileKey()` picks the key. Embedding CFF in `/FontFile2` is a spec violation (ISO 32000-1 9.9) — do not reintroduce it by assuming one key fits both
- **RTL / Arabic text**: one switch, `UseUniscribe` — HarfBuzz delivers correct ligatures on Linux/macOS, Windows uses Uniscribe; `RightToLeftText` is the direction only — see `.claude/skills/fonts.md` §10
- **Testing RTL**: Linux fonts (Noto Naskh Arabic) resolve shaped glyphs through the CMAP, so they never exercise the shaper's own advance path. Validate RTL work against a font without Arabic presentation forms — see `.claude/skills/fonts.md` §10
- **TTC collections**: only face index 0 is reachable; `TFontFileMap` (`mormot.lib.freetype`) has no face index, so the other faces of a `.ttc` cannot be selected by name
- **EMF/MetaFile**: Windows-only (`TPdfDocumentGdi`, `mormot.pdf.canvas`), not portable
- **GDI+/gradient fills**: Windows-only via EMF
- **Table pagination**: no row break within a cell (roadmap R-10)
- **Symbol fonts on POSIX**: excluded from subsetting, the whole face is embedded (roadmap R-15b); `TestSubsetSymbolFont` covers both sides where Wingdings, Webdings or Symbol is installed (Windows: subset by FontSub; macOS: Symbol embedded whole), no demo
- **PDF/A** (R-17): A-3U + PDF/UA-1, A-3A (tagged) and A-3B verified on all three platforms with veraPDF, Mustang and PAC; A-1 and A-2 implemented, unverified. Pass the level to the constructor — the `PdfA` setter calls `NewDoc`. A levels need `Tagged := True`. With PDF/A + Tagged the engine describes `pdfuaid` in the XMP extension schemas, inside the caller's `<pdfaExtension:schemas><rdf:Bag>` if `PdfAMetadaExtension` has one — keep that single list
- **E-invoices**: the engine writes the PDF/A-3 container (`CreateFileAttachmentFrom` + `PdfMetadataFacturX`; in `TGDIPages` `AddExportPdfAttachment` + `ExportPdfMetadataExtension`) and never generates or validates invoice XML. Scope is B2B (ZUGFeRD/Factur-X profile EN 16931); invoices to German authorities are pure XML and out of scope. Sample data only under the licence of this project (mORMot's MPL/GPL/LGPL)
- **Charts**: out of scope — no chart engine, as no invoice XML. A chart is an
  image from a chart library in a `Figure` with `/Alt`, its values as a table
  besides. `layer1_demo`'s figure is deliberately a set of shapes, not a
  chart. A chart example only on request (ROADMAP "Charts")
- **Links in tagged output**: no `Link` role, `OBJR` or `/StructParent` for annotations — `CreateHyperLink` in tagged output fails veraPDF `ua1` on four 7.18 rules (measured). `TGDIPages.DrawLink` draws link-styled text as a `Span` and drops the URL: conformant, not clickable (roadmap R-29, item 7)
- **Delphi** (R-19, R-21, R-23, R-25, R-27 done; R-20 steps 1–6 done): layer 1,
  the TCanvas bridge and the `TGDIPages` core build on Delphi 7 and Delphi
  2010 (Unicode Delphi), Win32; `test_runner` 506/506 on Delphi 7 (Delphi 2010 last measured at 448/448, #27). All six console
  demos and the `--export` of the two GUI demos build and give the same PDF as
  FPC (the GUI demos build their report in `uReport.pas`, without a form);
  PAC 2024 and veraPDF pass the files of both compilers. Open: the preview and
  the demo windows (R-20 steps 7, 8). Delphi 13 (R-27): `test_runner`
  green on Win32, Win64, Linux64 and Android64 — on Linux/Android layer 1
  and the backends only, Delphi has no VCL there (`USE_GRAPHICS_UNIT` off,
  no `TBitmap` images).
  Delphi 7's `TCanvas` drawing methods are static: the bridge reintroduces
  them (`PDF_CANVASVIRTUAL` off), so draw through a `TPdfVclCanvas`
  reference — `VclCanvas` has that type, `RenderPageToCanvas` casts. Text
  beyond ASCII goes through `TextOutUtf8` from a `RawUtf8` constant (see the
  literal rule in Coding Conventions): `TextOut` reads Delphi 7's `string` as
  ANSI. A console program needs `{$APPTYPE CONSOLE}` after the
  `mormot.defines.inc` include: FPC's project makes a console executable,
  dcc32 a GUI one without it, where `WriteLn` raises I/O error 105. Never put
  `mORMot2/src/ui` on a Delphi search path: it holds the original
  `mormot.ui.pdf`/`report`/`core` - the last two have the names of ours

Current verification status per platform, and the open items in detail:
`docs/ROADMAP.md`

## Dependencies

Build: FreePascal 3.2+ with Lazarus (what mORMot2 requires; used here: FPC 3.2.2 on Windows, 3.2.3 on Linux and macOS), or Delphi 7 / Delphi 2010 for Win32 (no preview window yet, R-20), or Delphi 13 for Win32, Win64, Linux64 and Android64 (R-27; on Linux/Android layer 1 only); mORMot2 sources of the trunk, not 2.4-stable (v0.10.0 is the last version for it), pinned per refactoring baseline (`docs/REFACTORING.md`, Phase 0 step 3) - during the refactoring a commit of the `pdf-font-layer` branch of `landrix/mORMot2`, the trunk plus the new `mormot.lib.*` units

Runtime Windows: none (GDI is part of the OS)

Runtime Linux: `libfreetype.so.6`
```bash
sudo apt install libfreetype6       # Debian/Ubuntu
sudo dnf install freetype           # Fedora/RHEL
```

Runtime macOS: `libfreetype.6.dylib` (`brew install freetype`)

Optional on Linux/macOS: HarfBuzz for shaping (`UseUniscribe`), and HarfBuzz 2.9+
with its subset library for font subsetting (without it, the whole face is
embedded — so on Ubuntu 22.04 and RHEL 9, which ship 2.7.4). Both are loaded
at run time; nothing to link. Versions per distribution:
`.claude/skills/platform-backends.md` (IFontSubsetter)
```bash
sudo apt install libharfbuzz0b libharfbuzz-subset0   # Debian 12+/Ubuntu 24.04+ for subsetting
sudo dnf install harfbuzz                            # Fedora/RHEL
brew install harfbuzz                                # macOS
```
