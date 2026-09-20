# mORMot2 PDF Cross-Platform — Agent Reference

Cross-platform PDF and report engine for Windows, Linux and macOS, based on mORMot2.
The original document (`reference/mormot.ui.pdf.pas`) was Windows/GDI-only; this project abstracts all platform calls behind interfaces.

---

## Skills — Mandatory First Step

**RULE: Read the relevant skill file(s) BEFORE doing anything else — before reading source files, before searching, before planning.**

Skills contain complete, distilled API and architectural knowledge. The main source files are very large (mormot.ui.pdf.pas is 12,500+ lines); reading them without necessity wastes context and time.

| Skill | When to use |
|---|---|
| `.claude/skills/pdf-engine.md` | TPdfDocument, TPdfDocumentVcl, TPdfCanvas — full API, enums, encryption, FPImage |
| `.claude/skills/report-engine.md` | TGDIPages — all methods, tables, command recording, global helpers |
| `.claude/skills/platform-backends.md` | IPdfPlatformFont/SystemFonts/DC — interfaces, backends, data types |
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
  chinese_demo/       Demo 5 — CJK text, whole-TTF embedding (console)
  rtl_demo/           Demo 6 — Arabic RTL, HarfBuzz/Uniscribe shaping (console)
tests/
  test_pdf_crossplatform.pas   7 tests: platform backend
  test_pdf_smoke.pas           4 tests: PDF basics
  test_report_crossplatform.pas 11+ tests: report engine
  test_pdf_subset.pas          14 tests: font subsetting (R-12)
reference/
  mormot.ui.pdf.pas   Original file (12,500 lines, reference only)
docs/
  DEMOS.md            Learning path: the 6 demos step by step
  API_REFERENCE.md    TCanvas methods, TReportFormat, TTableLayout
  ROADMAP.md          Planned and completed work, with results
  R12_PLAN.md         R-12 font subsetting on POSIX: plan and results
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
    |
GDI (Windows)  /  FreeType2 (Linux/macOS)
```

For all execution paths through this architecture: `.claude/skills/call-graph.md`
For interface and backend details: `.claude/skills/platform-backends.md`

## The 6 Demos

| Demo | API | Type | Highlights |
|---|---|---|---|
| pdf_demo | `TPdfDocumentVcl` | Console | TCanvas basics, Tagged PDF (H1/P/Figure/Table) |
| report_demo | `TGDIPages` | GUI | WYSIWYG preview, tagged PDF export, `TTableLayout`, `--export` batch mode |
| markdown_demo | `TGDIPages` | Console | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| mormot_demo | `TGDIPages` + ORM | GUI | SQLite via TRestClientDB, TTableLayout, tagged PDF, `--export` batch mode |
| chinese_demo | `TPdfDocumentVcl` | Console | CJK text, whole-TTF embedding |
| rtl_demo | `TPdfDocumentVcl` | Console | Arabic RTL, HarfBuzz/Uniscribe shaping |

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
fonts. On Linux/macOS the faces are subset by `libharfbuzz-subset` (glyph IDs
retained, so `/ToUnicode` stays valid); on Windows, where `CreateFontPackage`
would break the round-trip, the whole face is embedded. Both
have to be set **before the first page is drawn** — the font flags decide which
metrics the layout is measured with — and both raise `ESynException` if set later.

Full details including dual-instance model, CMAP loading, text rendering chains, and RTL/Arabic limitations: `.claude/skills/fonts.md`

### Platform Abstraction

New platform feature: use interface method, do not add `{$ifdef}` inside `mormot.ui.pdf.pas`.
Details on interfaces and registration: `.claude/skills/platform-backends.md`

## Coding Conventions (mORMot2 style)

- **Language: English only** — all code, comments, and identifiers must be in English
- **Prefer mORMot2 functions** over FPC/LCL alternatives (e.g. `FormatUtf8` over `Format`, `RawUtf8` over `string` for internal strings, `DateToString8` over `FormatDateTime` for file names)
- `RawUtf8` instead of `string` for internal strings
- No blank lines between `begin`/`end` blocks
- Interfaces with reference counting (`TInterfacedObject`)
- Error handling via `ESynException`
- No RTTI where avoidable

## Build Commands

```bash
# Windows:
"C:\lazarus\lazbuild.exe" examples/pdf_demo/pdf_demo_crossplat.lpi -B
"C:\lazarus\lazbuild.exe" examples/report_demo/mormot_report_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/markdown_demo/markdown_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/mormot_demo/mormot_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/chinese_demo/chinese_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/rtl_demo/rtl_demo.lpi -B
"C:\lazarus\lazbuild.exe" tests/test_runner.lpr -B

# Linux/macOS:
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
lazbuild examples/markdown_demo/markdown_demo.lpi -B
lazbuild examples/chinese_demo/chinese_demo.lpi -B
lazbuild examples/rtl_demo/rtl_demo.lpi -B
```

## Open Items

- **Font subsetting**: default (`EmbeddedWholeTtf = False`) on all platforms, two implementations. **Linux/macOS** (R-12): `IPdfFontSubsetter` from `mormot.pdf.hbsubset` (`libharfbuzz-subset`, retained glyph IDs) — safe for CJK, RTL and tagged output; 97–99.5% smaller PDFs. Without the library, and for PDF/A-1 (no `/CIDSet`), symbol fonts and CFF faces, the whole face is embedded. **Windows**: `CreateFontPackage`, safe for Latin only; set `EmbeddedWholeTtf := True` for RTL/Arabic and CJK — `Tagged` does that there. See `.claude/skills/fonts.md` §3, §9 and `docs/R12_PLAN.md`
- **RTL / Arabic text**: HarfBuzz delivers correct ligatures on Linux/macOS; Windows uses Uniscribe — see `.claude/skills/fonts.md` §10
- **Testing RTL**: Linux fonts (Noto Naskh Arabic) resolve shaped glyphs through the CMAP, so they never exercise the shaper's own advance path. Validate RTL work against a font without Arabic presentation forms — see `.claude/skills/fonts.md` §10
- **TTC collections**: only face index 0 is reachable; `TPdfFontMap` has no face index, so the other faces of a `.ttc` cannot be selected by name
- **EMF/MetaFile**: Windows-only (`TPdfDocumentGdi`), not portable
- **GDI+/gradient fills**: Windows-only via EMF
- **Table pagination**: no row break within a cell

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
