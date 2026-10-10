# mORMot2 PDF Engine — Cross-Platform

Cross-platform PDF generation for Windows, Linux and macOS, based on the [mORMot2](https://github.com/synopse/mORMot2) PDF engine (`mormot.ui.pdf.pas`). The original implementation is Windows/GDI-only; this project abstracts all platform calls behind interfaces and provides a FreeType2 backend for Unix/macOS.

**Current release: [v0.10.0](CHANGELOG.md)** — PDF/A-3 and ZUGFeRD /
Factur-X e-invoices, Delphi 7 to Delphi 13; tagged PDF output verified by
veraPDF and PAC 2024 on all three platforms.

## Platforms

| Platform | Compiler | Backend | Status |
|---|---|---|---|
| Windows | FreePascal/Lazarus | GDI via interfaces | Production |
| Windows (Win32) | Delphi 7, Delphi 2010 | GDI via interfaces | Layer 1, the TCanvas bridge and the `TGDIPages` core; all tests green on both, the six console demos and the `--export` of the two GUI demos give the same PDF as FPC. The preview and the demo windows need FPC for now (roadmap R-20) |
| Windows (Win32, Win64) | Delphi 13 | GDI via interfaces | Layer 1, the TCanvas bridge and the `TGDIPages` core; all tests green (roadmap R-27) |
| Linux | FreePascal/Lazarus | FreeType2 | Production |
| Linux64, Android64 | Delphi 13 | FreeType2 | Layer 1 and the backends; all tests green. No TCanvas bridge and no `TGDIPages`: Delphi has no VCL there (roadmap R-27) |
| macOS | FreePascal/Lazarus | FreeType2 | Production |

## Architecture (3 layers)

```
TGDIPages           mormot.ui.report     Document layout, tables, H1-H6
TPdfDocumentVcl     mormot.ui.pdfcanvas  TCanvas-compatible wrapper
TPdfDocument        mormot.pdf           Direct PDF API, no TCanvas, no VCL/LCL
```

### Which unit to use

A program uses the units of the layer it works on, as listed here; what a
layer's API takes from below, that layer re-exports:

| Layer | `uses` | Re-exports |
|---|---|---|
| 3 — `TGDIPages` | `mormot.ui.report`; a GUI adds `mormot.ui.reportpreview` for preview and printing | what the `ExportPdf*` options take: `TPdfALevel` (`pdfaNone` … `pdfa3U`), `TPdfFileFormat` (`pdf13` … `pdf17`), `TPdfAFRelationship` (`afr*`), `PdfMetadataFacturX` |
| 2 — `TPdfDocumentVcl` | `mormot.ui.pdfcanvas`, `mormot.pdf` | `TPdfALevel`, `TPdfAFRelationship`, `PdfMetadataFacturX`; the rest of the document API comes from `mormot.pdf` |
| 1 — `TPdfDocument` | `mormot.pdf` | — |

The structure roles (`psrH1`, `psrP`, …) and `GetPdfFonts` come with
`mormot.pdf` (declared in `mormot.pdf.types`, re-exported).

**The platform units need no `uses` of yours.** `mormot.pdf` pulls in GDI
and Uniscribe on Windows, and FreeType2, the HarfBuzz shaper and the hb-subset
font subsetter on Linux and macOS. HarfBuzz is loaded at run time: where the
library is missing, text is drawn unshaped and fonts are embedded whole.

**Shaping** Arabic, Hebrew, Indic or Thai text is one switch on every
platform, `UseUniscribe := True` — the name comes from the original API; on
Linux and macOS it shapes with HarfBuzz. Latin text stays in the simple font
either way - except in a CFF face, which draws all its text as glyphs. `RightToLeftText := True` on the canvas sets the paragraph
direction; without it the direction comes from the script. Set the switch
without a conditional — see [rtl_demo](examples/rtl_demo/).

**Never put `mormot.pdf` beside `mormot.ui.report`.** The two use some of
the same names for different things — `psA4` is a `TPdfPaperSize` in one and
a `TGdiPagePaperSize` in the other, and `mormot.pdf`'s `TRect` is not the
LCL's — so the order of the `uses` clause decides which one a name means.
With `mormot.pdf` last, `Report.PaperSize := psA4` does not compile. What a
report needs from below is re-exported by `mormot.ui.report`; if something is
missing, it belongs there, not in your `uses` clause.

---

## Quick start

### Layer 1 — Direct PDF API (no TCanvas)

```pascal
uses mormot.pdf;

Doc := TPdfDocument.Create;
Doc.DefaultPaperSize := psA4;
Doc.StandardFontsReplace := True;
Doc.NewDoc;
Doc.AddPage;
Doc.Canvas.SetFont('Helvetica', 12, []);
Doc.Canvas.TextOut(72, 750, 'Hello from mORMot2 PDF!');
Doc.SaveToFile('hello.pdf');
Doc.Free;
```

Coordinates are in PDF points (72 DPI), Y = 0 at the lower-left corner.

### Layer 2 — TCanvas API

```pascal
uses mormot.pdf, mormot.ui.pdfcanvas;

Doc := TPdfDocumentVcl.Create;
Doc.EmbeddedTTF := False;
Doc.StandardFontsReplace := True;
Doc.AddPage;
C := Doc.VclCanvas;
C.Font.Name := 'Helvetica';  C.Font.Size := 24;
C.TextOut(40, 40, 'Cross-Platform PDF');
C.Pen.Color := clRed;  C.Brush.Color := clYellow;
C.Rectangle(40, 80, 200, 140);
Doc.SaveToFile('output.pdf');
```

Coordinates are in pixels (96 DPI), Y = 0 at the upper-left corner. Full method reference: [docs/API_REFERENCE.md](docs/API_REFERENCE.md)

### Layer 3 — Report engine

```pascal
uses mormot.ui.report;

Report := TGDIPages.Create(nil);
// Tagged PDF/UA: set before drawing — it selects the fonts the layout is
// measured with, and raises when a page already exists
Report.ExportPdfTagged := True;
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
Report.PaperSize        := psA4;
Report.MarginLeft       := 1500;   // 15 mm
Report.LineHeightFactor := 1.3;    // line spacing (default 1.1)
Report.NewPage;
Report.SetFont(SansFont, 11);
Report.DrawHeading(1, 'Report title');          // automatic PDF bookmark
Report.DrawParagraph('Text with line wrapping...');
Report.BeginTable(MyLayout);
Report.DrawTableHeader(['Column 1', 'Column 2']);
Report.DrawTableRow(['Value A', 'Value B']);      // automatic page break + header repetition
Report.EndTable;
Report.EndDoc;
Report.ExportPdfStream(Stream);   // file format is raised to pdf17 automatically
// or: ShowReportPreview(Report)   // mormot.ui.reportpreview
Report.Free;
```

Units: 1/100 mm. Learning path with all features: [docs/DEMOS.md](docs/DEMOS.md)

---

## Tagged PDF (PDF/UA)

`ExportPdfTagged := True` (report engine) or `Tagged := True` (low-level API)
writes the structure tree that screen readers and accessibility checkers need.
The tagged demos pass **PAC 2024**. PAC keeps one accepted hint on every
`Figure`, "possibly inappropriate use of figure"; it shows for vector paths
and images alike. In `zugferd_demo` it adds one more, "link in text does not
have a Link element", for the e-mail addresses drawn as plain text: a
clickable link would need a tagged link annotation, which the engine does not
write (see *Links in tagged output* below).

What the engine emits:

- structure elements `H1`–`H6`, `P`, `Span`, `Figure` with `/Alt`, lists
  (`L` / `LI` / `Lbl` / `LBody`) and tables
  (`Table` > `THead` | `TBody` | `TFoot` > `TR` > `TH` | `TD`)
- a PDF bookmark per heading, the document title in the XMP metadata, plus
  `/Lang` and `/DisplayDocTitle`
- running headers and footers, repeated table header rows and decorative
  graphics as artifacts, so they are not read out twice

Two rules:

- **Fonts are embedded.** PDF/UA does not allow the viewer's own base-14 faces,
  so tagging turns `EmbeddedTTF` on and `StandardFontsReplace` off. Ask for the
  font names *after* that, with `GetExportFonts` / `GetPdfFonts`.
- **Switch it on before the first page.** The font flags decide which metrics
  the layout is measured with; setting them later raises an exception.

```pascal
// Report engine
Report.ExportPdfTagged := True;    // first — it selects the fonts to measure with
Report.UseOutlines     := True;    // one bookmark per heading
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
Report.NewPage;
Report.DrawHeading(1, 'Report title');
// ... draw, then ExportPdfStream / ExportPDF

// TCanvas bridge (layer 2)
Doc.Tagged          := True;
Doc.DefaultLanguage := 'en';
GetPdfFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
Doc.AddPage;
Doc.BeginStructContent(psrH1);
Doc.VclCanvas.TextOut(40, 40, 'Title');
Doc.EndStructContent;
```

**Charts are not in scope.** The project has no chart engine and will not get
one, just as it generates no invoice XML. A chart comes as an image from a
chart library of your choice, drawn into a `Figure` with an alternate text
that says what the chart shows. A chart that carries data should also have
those values as a real table in the document: an alternate text cannot carry
a data series, a table can be read cell by cell.

## Font embedding and subsetting

Embedded fonts hold only the glyphs a document uses, unless something prevents
that. `EmbeddedWholeTtf := True` always embeds the complete face.

| | Linux / macOS | Windows |
|---|---|---|
| Subsetter | `libharfbuzz-subset` (optional, see dependencies) | `CreateFontPackage`, part of the OS |
| Latin text | subset | subset |
| CJK, shaped Arabic | subset | subset |
| Tagged output | subset | subset |
| `markdown_demo_<os>_<cpu>_<compiler>.pdf` | 46 KB | 230 KB |

Both subsetters keep the original glyph numbering — `libharfbuzz-subset` by
retaining glyph IDs, `CreateFontPackage` through a glyph keep list
(`TTFCFP_FLAGS_GLYPHLIST`) — so Identity-H and the `/ToUnicode` round-trip
survive, which is what makes CJK and shaped Arabic safe to subset.

The whole face is embedded instead without `libharfbuzz-subset`, for PDF/A-1
(which would need a `/CIDSet`) and for symbol fonts on Linux/macOS. Text
extraction and copy/paste are unaffected either way.

Both outline flavours are subset. A `glyf` face goes to `/FontFile2`; a
CFF face (the CJK system faces of macOS and Linux) draws all its text as a
`CIDFontType0` and goes to `/FontFile3`: a CID-keyed one as its bare CFF
(`/Subtype /CIDFontType0C`, PDF 1.3, also PDF/A-1), a name-keyed one as an
OpenType font file (PDF 1.6). On macOS `chinese_demo` went from 10 MB to
23 KB once CFF was subset (see R-15c in [docs/ROADMAP.md](docs/ROADMAP.md)).

## PDF/A and e-invoices (ZUGFeRD / Factur-X)

PDF/A-3 and PDF/UA-1 combine in one file: pass the level to the constructor,
switch `Tagged` on, and the engine writes one XMP packet with both
identifications and the extension schema PDF/A needs for `pdfuaid`.

| Level | Status |
|---|---|
| **PDF/A-3U** + PDF/UA-1 | verified on all three platforms — veraPDF `3u` and `ua1`, PAC 2024 |
| **PDF/A-3A** | verified with `Tagged := True` (veraPDF `3a`); the A level needs the structure tree |
| PDF/A-3B | verified, with and without tagging |
| PDF/A-1A/B, -2A/B | implemented, not verified. PDF/A-1 embeds whole faces (no `/CIDSet`) |

**Hybrid e-invoices.** A ZUGFeRD 2.x / Factur-X 1.x invoice is PDF/A-3 with
its CII XML embedded as an associated file. The engine provides the container
— `CreateFileAttachmentFrom` with an `/AFRelationship`, and
`PdfMetadataFacturX` for the `fx:` XMP properties — and stays neutral towards
the invoice itself: it neither generates nor validates the XML.
[zugferd_demo](examples/zugferd_demo/) builds a profile EN 16931 invoice that
Mustang validates, the form exchanged between businesses in Germany and
France. Invoices to German public authorities take pure XML (XRechnung), not
a PDF, and are not in scope.

```pascal
// TCanvas bridge (layer 2)
Doc := TPdfDocumentVcl.Create(true, 0, pdfa3U);   // not the PdfA property: it resets the document
Doc.Tagged := True;
// ... draw the invoice ...
Doc.CreateFileAttachmentFrom(Xml, 'factur-x.xml', 'Factur-X invoice data',
  'text/xml', Now, Now, nil, afrAlternative);
Doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931');

// Report engine (layer 3) - mormot.ui.report alone
Report.ExportPdfLevel := pdfa3U;
Report.ExportPdfTagged := True;
// ... draw the invoice ...
Report.AddExportPdfAttachment(Xml, 'factur-x.xml', 'Factur-X invoice data',
  'text/xml', afrAlternative);
Report.ExportPdfMetadataExtension := PdfMetadataFacturX('EN 16931');
Report.ExportPdfStream(Stream);
```

---

## The 8 demos (learning path)

| Demo | API | What it shows |
|---|---|---|
| [pdf_demo](examples/pdf_demo/) | `TPdfDocumentVcl` | Text, graphics, tagged PDF (H1/P/Figure, Table with THead/TBody/TR/TH/TD) |
| [report_demo](examples/report_demo/) | `TGDIPages` + GUI | Preview, tagged tables with row groups and a footer row, running headers/footers, `--export` batch mode |
| [markdown_demo](examples/markdown_demo/) | `TGDIPages` | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| [mormot_demo](examples/mormot_demo/) | `TGDIPages` + ORM | SQLite database, service layer, TTableLayout, tagged export, `--export` batch mode |
| [chinese_demo](examples/chinese_demo/) | `TPdfDocumentVcl` | CJK text, subset embedding |
| [rtl_demo](examples/rtl_demo/) | `TPdfDocumentVcl` | Arabic RTL, HarfBuzz / Uniscribe shaping |
| [zugferd_demo](examples/zugferd_demo/) | `TGDIPages` | PDF/A-3U + PDF/UA-1, ZUGFeRD / Factur-X invoice read from and embedded with its XML |
| [layer1_demo](examples/layer1_demo/) | `TPdfDocument` | The low-level API alone: tagged headings, text, a figure and a table with THead/TBody/TFoot, in PDF points; builds with FPC, Delphi 7 and Delphi 2010 |

Full guide: [docs/DEMOS.md](docs/DEMOS.md)

---

## Build

Requirements: FreePascal 3.2+ with Lazarus and the mORMot2 sources of the
**trunk** (the Lazarus package `mormot2`, with `static/` from
`mormot2static`), or Delphi 7 / Delphi 2010 for Win32, or Delphi 13 — see
below. The release mORMot2 2.4-stable lacks functions this project uses;
v0.10.0 is the last version that builds with it.

```bash
# Windows
"C:\lazarus\lazbuild.exe" examples/pdf_demo/pdf_demo_crossplat.lpi -B
"C:\lazarus\lazbuild.exe" examples/report_demo/report_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/markdown_demo/markdown_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/mormot_demo/mormot_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/chinese_demo/chinese_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/rtl_demo/rtl_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/zugferd_demo/zugferd_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/layer1_demo/layer1_demo.lpi -B

# Linux/macOS
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
lazbuild examples/markdown_demo/markdown_demo.lpi -B
lazbuild examples/chinese_demo/chinese_demo.lpi -B
lazbuild examples/rtl_demo/rtl_demo.lpi -B
lazbuild examples/report_demo/report_demo.lpi -B
lazbuild examples/mormot_demo/mormot_demo.lpi -B
lazbuild examples/zugferd_demo/zugferd_demo.lpi -B
lazbuild examples/layer1_demo/layer1_demo.lpi -B

# Test suite
lazbuild tests/test_runner.lpi -B && tests/bin/<cpu-os>/test_runner
# on Windows: tests\bin\x86_64-win64\test_runner.exe --noenter (it waits for Enter otherwise)
```

**Delphi 7** (Win32: layer 1, the TCanvas bridge, the `TGDIPages` core) builds from the command line. `MORMOT2` points to
the mORMot2 checkout, `DELPHI7` defaults to the standard install folder; output
goes to `bin\d7\<project>\`:

```bat
set MORMOT2=C:\path\to\mORMot2
tests\build_delphi7.bat tests\test_runner.lpr
bin\d7\test_runner\test_runner.exe --noenter
tests\build_delphi7.bat examples\layer1_demo\layer1_demo.dpr
bin\d7\layer1_demo\layer1_demo.exe
tests\build_delphi7.bat examples\markdown_demo\markdown_demo.lpr
bin\d7\markdown_demo\markdown_demo.exe
```

**Delphi 2010** (a Unicode Delphi) builds the same projects the same way with
`tests\build_delphi2010.bat`, output in `bin\d2010\<project>\`, and gives the
same PDFs as Delphi 7.

**Delphi 13** builds the test suites from the IDE: `tests\delphi13\test_runner.dproj`
for Win32, Win64 and Linux64 (through PAServer), with `MORMOT2` set as for
Delphi 7. Android64 has its own FMX host in `tests\delphi13\android\`, since
Android starts no console program: `build.cmd` packages the APK,
`run-emulator.cmd -Run` runs the suites on an emulator and returns the verdict
as exit code. The app needs an NDK build of `libfreetype.so`, see
[BUILD-FREETYPE.md](tests/delphi13/android/BUILD-FREETYPE.md).

Do not put `mORMot2\src\ui` on a Delphi search path: it holds the original
`mormot.ui.pdf`, `mormot.ui.report` and `mormot.ui.core` - the last two have
the names of this project's units, which the compiler would take instead.

The two GUI demos also export without their window, which is what the
automated checks use:

```bash
examples/report_demo/bin/<target>/report_demo --export report.pdf
```

The LCL measures the text, so on Linux/GTK2 this still needs a display —
on a headless machine run it under `xvfb-run`. The macOS Cocoa widgetset
exports without one.

## Runtime dependencies

**Windows:** none additional (GDI is part of the OS)

**Linux:**
```bash
sudo apt install libfreetype6                    # required — PDF font rendering
sudo apt install libharfbuzz0b                   # optional — shaping of Arabic, Hebrew, Indic ... (UseUniscribe)
sudo apt install libharfbuzz-subset0             # optional — font subsetting (HarfBuzz 2.9+)
sudo apt install fonts-liberation                # recommended — Liberation Sans/Serif/Mono, the faces of embedded and tagged output
sudo apt install fonts-noto-core                 # optional — Noto Naskh Arabic (rtl_demo)
sudo apt install fonts-droid-fallback            # optional — Droid Sans Fallback, CJK (chinese_demo)
```
Fonts are detected automatically from `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.fonts`.

Font subsetting needs HarfBuzz 2.9 or later. Debian 11, Ubuntu 22.04 LTS and
RHEL 8/9 ship older versions (1.7.5–2.7.4): there every face is embedded whole.

**macOS:**
```bash
brew install freetype
brew install harfbuzz          # optional — shaping (UseUniscribe) and font subsetting
```
Fonts from `/Library/Fonts`, `/System/Library/Fonts`, `~/Library/Fonts`.

**Android** (Delphi 13): Android ships no public FreeType — the app brings an
NDK build of `libfreetype.so` ([BUILD-FREETYPE.md](tests/delphi13/android/BUILD-FREETYPE.md));
a Linux ARM64 build does not load. Fonts from `/system/fonts` (Roboto, Noto
Serif, Droid Sans Mono). HarfBuzz is not packaged: no shaping, no subsetting.

---

## Open items

- **Symbol fonts on Linux/macOS:** not subset — the whole face is embedded, because hb-subset is not given the glyph IDs behind the `(3,0)` cmap. Windows subsets them (roadmap R-15b)
- **TTC collections:** only face index 0 is reachable (roadmap R-11)
- **EMF/MetaFile:** Windows-only (`TPdfDocumentGdi`), not portable
- **GDI+/Gradient fills:** available only via EMF on Windows
- **Table pagination:** no row wrap within a cell
- **Delphi:** Delphi 7 and Delphi 2010 (Win32) build layer 1, the TCanvas bridge and the `TGDIPages` core, all six console demos and the batch export of the two GUI demos, not yet the preview or the demo windows (roadmap R-20). Delphi 7's `TCanvas` drawing methods are static: draw through a `TPdfVclCanvas` reference (`Doc.VclCanvas` has that type), never through a plain `TCanvas`, or nothing reaches the PDF. Delphi 13 builds layer 1, the TCanvas bridge and the `TGDIPages` core on Win32 and Win64 (tested through `test_runner`, the demos not yet; both depend on the community, the maintainers have no Delphi 13); on Linux64 and Android64 only layer 1 and the backends — no VCL, so no TCanvas bridge, no `TGDIPages` and no `TBitmap` images (JPEG through `CreateJpegDirect`) (roadmap R-27)
- **Links in tagged output:** `CreateHyperLink` in a tagged document fails PDF/UA — there is no `Link` structure element for annotations. `TGDIPages.DrawLink` stays conformant by drawing styled text only; its URL is not clickable (roadmap R-18)

Details and the current verification status: [docs/ROADMAP.md](docs/ROADMAP.md)

---

## License

This project follows the licensing terms of mORMot2. See the [mORMot2 repository](https://github.com/synopse/mORMot2) for details.
