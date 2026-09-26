# mORMot2 PDF Cross-Platform — Agent Reference

Cross-platform PDF and report engine for Windows, Linux and macOS, based on mORMot2.
The original document (`reference/mormot.ui.pdf.pas`) was Windows/GDI-only; this project abstracts all platform calls behind interfaces.

---

## Skills — Mandatory First Step

**RULE: Read the relevant skill file(s) BEFORE doing anything else — before reading source files, before searching, before planning.**

Skills contain complete, distilled API and architectural knowledge. The main source files are very large (mormot.ui.pdf.pas is 14,600+ lines, mormot.ui.report.pas 3,200+); reading them without necessity wastes context and time.

| Skill | When to use |
|---|---|
| `.claude/skills/pdf-engine.md` | TPdfDocument, TPdfDocumentVcl, TPdfCanvas — full API, enums, encryption, FPImage |
| `.claude/skills/report-engine.md` | TGDIPages — all methods, tables, command recording, global helpers |
| `.claude/skills/platform-backends.md` | IPdfPlatformFont/SystemFonts/DC, optional IPdfTextShaper/IPdfFontSubsetter — interfaces, backends, data types |
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
| `src/core/mormot.ui.pdf.pas` | PDF engine (cross-platform) | Production |
| `src/core/mormot.ui.report.pas` | Report engine (`TGDIPages`) | Production |
| `src/core/mormot.ui.pdfcanvas.pas` | TCanvas bridge (`TPdfDocumentVcl`) | Production |
| `src/core/mormot.pdf.types.pas` | Platform interfaces & types | Production |
| `src/platform/windows/mormot.pdf.gdi.pas` | GDI backend | Production |
| `src/platform/unix/mormot.pdf.freetype.pas` | FreeType2 backend | Production |
| `src/platform/unix/mormot.pdf.harfbuzz.pas` | HarfBuzz shaper (RTL/complex scripts) | Production |
| `src/platform/unix/mormot.pdf.hbsubset.pas` | hb-subset font subsetter (R-12) | Production |
| `src/core/mormot.pdf.fpimage.pas` | FPImage bitmap adapter | Production |

## File Structure

```
src/
  core/
    mormot.ui.pdf.pas           PDF objects, TPdfDocument, TPdfCanvas
    mormot.ui.report.pas        TGDIPages — layout engine
    mormot.ui.pdfcanvas.pas     TPdfDocumentVcl, TPdfVclCanvas
    mormot.pdf.types.pas        IPdfPlatformFont/SystemFonts/DC, types
    mormot.pdf.fpimage.pas      Bitmap embedding (FPImage)
    mormot.ui.core.pas          UI helper functions
    mormot.ui.gdiplus.pas       GDI+ support (Windows)
  platform/
    windows/mormot.pdf.gdi.pas  GDI backend (Windows)
    unix/mormot.pdf.freetype.pas FreeType2 backend (Linux/macOS)
    unix/mormot.pdf.harfbuzz.pas HarfBuzz text shaper (Linux/macOS, optional)
    unix/mormot.pdf.hbsubset.pas hb-subset font subsetter (Linux/macOS, optional)
  lib/
    mormot.lib.uniscribe.pas    Uniscribe text shaping (Windows, optional)
examples/
  pdf_demo/           Demo 1 — TPdfDocumentVcl, TCanvas API, Tagged PDF (console)
  report_demo/        Demo 2 — TGDIPages, GUI preview, tagged PDF
  markdown_demo/      Demo 3 — TGDIPages, semantics, tables, LineHeightFactor (console)
  mormot_demo/        Demo 4 — TGDIPages + mORMot ORM + TTableLayout, GUI, tagged PDF
  chinese_demo/       Demo 5 — CJK text, subset embedding (console)
  rtl_demo/           Demo 6 — Arabic RTL, HarfBuzz/Uniscribe shaping (console)
  zugferd_demo/       Demo 7 — PDF/A-3U + PDF/UA-1, ZUGFeRD/Factur-X invoice with embedded XML (console)
  layer1_demo/        Demo 8 — TPdfDocument/TPdfCanvas alone, tagged; FPC and Delphi 7 (console)
  (each demo folder carries a short README.md; the source header of its .lpr
   says the same thing in two sentences)
tests/
  test_runner.lpr              runs every suite below (green: 237 assertions on Windows with FPC, 127 with Delphi 7 — layer 1 suites only; 294 on macOS; 268 on Linux before R-21 — both +2 since the zero-real test — the rest are skips)
  test_defines.inc             PDF_HASVCLCANVAS: the TCanvas bridge suites (FPC until R-20)
  build_delphi7.bat            dcc32 build of one project (R-19); delphi7_core.dpr is the core compile guard
  test_pdf_crossplatform.pas   platform backend, text shaper, TTC extraction
  test_pdf_smoke.pas           PDF basics, tagged output, struct tree, tagged Unicode (all through TPdfCanvas)
  test_report_crossplatform.pas report engine, tables, tagged export
  test_pdf_subset.pas          font subsetting: IPdfFontSubsetter and TPdfDocument
  test_pdf_pdfa.pas            PDF/A-3: associated files, XMP schemas, PdfMetadataFacturX, level U
  test_coordinates.pas         page geometry
  test_report_coordinates.pas  report geometry
reference/
  mormot.ui.pdf.pas   Original Windows/GDI file (12,514 lines, reference only)
docs/
  DEMOS.md            Learning path: the 8 demos step by step
  API_REFERENCE.md    TCanvas methods, TReportFormat, TTableLayout
  ROADMAP.md          Open work in detail, completed work as one line each
.claude/skills/
  pdf-engine.md       TPdfDocument, TPdfDocumentVcl, TPdfCanvas — full API, enums, encryption, FPImage
  report-engine.md    TGDIPages — all methods, tables, command recording, global helpers
  platform-backends.md IPdfPlatformFont/SystemFonts/DC — interfaces, backends, data types
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
TPdfCanvas / TPdfDocument (mormot.ui.pdf) <- Low-level PDF
    | via interfaces
IPdfPlatformFont / IPdfSystemFonts / IPdfPlatformDC
    |                + optional: IPdfTextShaper, IPdfFontSubsetter
GDI (Windows)  /  FreeType2 (Linux/macOS)
                  + HarfBuzz shaping and hb-subset when the libraries load
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
| zugferd_demo | `TPdfDocumentVcl` | Console | PDF/A-3U + PDF/UA-1, `/AF` attachment, `PdfMetadataFacturX`, third-party invoice XML (KoSIT, Apache-2.0) |
| layer1_demo | `TPdfDocument` | Console | Layer 1 only, PDF points (Y=0 bottom), tagged H1/H2/P/Figure, UTF-8 via `TextOutW`; the only demo that builds with Delphi 7 |

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
| TrueType (with embedding) | `EmbeddedTTF := True` | OS-specific via `GetReportFonts()` |

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

### Platform Abstraction

New platform feature: use interface method, do not add `{$ifdef}` inside `mormot.ui.pdf.pas`.
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
- **No non-ASCII in string literals** in `src/`: `mormot.defines.inc` sets
  `{$CODEPAGE UTF8}`, and FPC converts such a literal — a default parameter
  value even at the call site, in the caller's settings (R-21: `'• '` arrived
  as `'?'`). Put the bytes in a `RawUtf8` constant (`#$E2#$80#$A2`) instead
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

# Delphi 7 (Win32, layer 1 only) — MORMOT2 must point to the mORMot2 checkout:
tests\build_delphi7.bat tests\test_runner.lpr
bin\d7\test_runner\test_runner.exe --noenter
tests\build_delphi7.bat examples\layer1_demo\layer1_demo.lpr
```

On Windows every test runner waits for Enter at the end unless it gets a
parameter — pass `--noenter` when it runs unattended.

Every project builds to `bin/<cpu-os>/` — the executable, the PDF it writes
and its logs — and its units to `lib/<cpu-os>/` (`<cpu-os>` as FPC names the
target, e.g. `aarch64-linux`, `x86_64-win64`, `aarch64-darwin`). The Delphi 7
build keeps its own layout under `bin\d7\`.

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
display (`xvfb-run` otherwise); on macOS Cocoa runs it headless.

## Open Items

- **Font subsetting**: default (`EmbeddedWholeTtf = False`) on all platforms, two implementations, both keeping the original glyph IDs and therefore safe for CJK, shaped Arabic and tagged output. **Linux/macOS** (R-12): `IPdfFontSubsetter` from `mormot.pdf.hbsubset` (`libharfbuzz-subset`); 97–99.5% smaller PDFs. **Windows** (R-15): `CreateFontPackage` with a glyph keep list (`TTFCFP_FLAGS_GLYPHLIST`). The whole face is embedded instead for PDF/A-1 (no `/CIDSet`), for symbol fonts on POSIX (R-15b) and when `libharfbuzz-subset` is missing. See `.claude/skills/fonts.md` §3, §9
- **CFF faces are subset too** (R-15c, done): a CFF-flavoured face goes to `/FontFile3` with `/Subtype /OpenType` as a `CIDFontType0`; `glyf` goes to `/FontFile2`. `PdfFontFileKey()` picks the key. Embedding CFF in `/FontFile2` was a spec violation poppler warned about — do not reintroduce it by assuming one key fits both
- **RTL / Arabic text**: HarfBuzz delivers correct ligatures on Linux/macOS; Windows uses Uniscribe — see `.claude/skills/fonts.md` §10
- **Testing RTL**: Linux fonts (Noto Naskh Arabic) resolve shaped glyphs through the CMAP, so they never exercise the shaper's own advance path. Validate RTL work against a font without Arabic presentation forms — see `.claude/skills/fonts.md` §10
- **TTC collections**: only face index 0 is reachable; `TPdfFontMap` has no face index, so the other faces of a `.ttc` cannot be selected by name
- **EMF/MetaFile**: Windows-only (`TPdfDocumentGdi`), not portable
- **GDI+/gradient fills**: Windows-only via EMF
- **Table pagination**: no row break within a cell (roadmap R-10)
- **Symbol fonts on POSIX**: excluded from subsetting, the whole face is embedded (roadmap R-15b); neither side is covered by a demo or test
- **PDF/A** (R-17): A-3U + PDF/UA-1, A-3A (tagged) and A-3B verified on all three platforms with veraPDF, Mustang and PAC; A-1 and A-2 implemented, unverified. Pass the level to the constructor — the `PdfA` setter calls `NewDoc`. A levels need `Tagged := True`. With PDF/A + Tagged the engine describes `pdfuaid` in the XMP extension schemas, inside the caller's `<pdfaExtension:schemas><rdf:Bag>` if `PdfAMetadaExtension` has one — keep that single list
- **E-invoices**: the engine writes the PDF/A-3 container (`CreateFileAttachmentFrom` + `PdfMetadataFacturX`) and never generates or validates invoice XML. Scope is B2B (ZUGFeRD/Factur-X profile EN 16931); invoices to German authorities are pure XML and out of scope. Third-party material only with a verified license, recorded in the demo's `THIRD_PARTY.md`
- **Links in tagged output**: no `Link` role, `OBJR` or `/StructParent` for annotations — `CreateHyperLink` in tagged output fails veraPDF `ua1` on four 7.18 rules (measured). `TGDIPages.DrawLink` draws link-styled text as a `Span` and drops the URL: conformant, not clickable (roadmap R-18, only on request)
- **Delphi** (R-19 done, R-21, R-23, R-20): layer 1 — `mormot.pdf.types`,
  `mormot.ui.pdf`, GDI backend, Uniscribe — builds on Delphi 7, Win32;
  `test_runner` green with 127 assertions (the layer 1 suites), and the tagged
  Unicode test file passes PAC 2024 and veraPDF `ua1` from both compilers. R-21 done on
  Windows and macOS: `{$I mormot.defines.inc}` in every unit; the Linux
  assertion count is to record. R-23:
  `layer1_demo`, the first demo that builds on Delphi 7 — built and compared
  on Windows, PAC/veraPDF and the other platforms open.
  R-20, priority 2: the TCanvas bridge — `TPdfVclCanvas` relies on
  `override`, but Delphi 7's `TCanvas` drawing methods are static, so a call
  through a `TCanvas` reference bypasses the bridge. Never put `mORMot2/src/ui`
  on a Delphi search path: it holds the original `mormot.ui.pdf`/`report`/`core`

Current verification status per platform, and the open items in detail:
`docs/ROADMAP.md`

## Dependencies

Build: FreePascal 3.0+, Lazarus 2.0+, mORMot2-Core

Runtime Windows: none (GDI is part of the OS)

Runtime Linux: `libfreetype.so.6`
```bash
sudo apt install libfreetype6       # Debian/Ubuntu
sudo dnf install freetype           # Fedora/RHEL
```

Runtime macOS: `libfreetype.6.dylib` (`brew install freetype`)

Optional on Linux/macOS: HarfBuzz 2.9+ with its subset library, for RTL shaping
and font subsetting (without it, the whole face is embedded)
```bash
sudo apt install libharfbuzz0b libharfbuzz-subset0   # Debian 12+/Ubuntu 22.04+
sudo dnf install harfbuzz                            # Fedora/RHEL
brew install harfbuzz                                # macOS
```
