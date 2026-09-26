# mORMot2 PDF Engine — Cross-Platform

Cross-platform PDF generation for Windows, Linux and macOS, based on the [mORMot2](https://github.com/synopse/mORMot2) PDF engine (`mormot.ui.pdf.pas`). The original implementation is Windows/GDI-only; this project abstracts all platform calls behind interfaces and provides a FreeType2 backend for Unix/macOS.

**Current release: [v0.9.0](CHANGELOG.md)** — tagged PDF output verified by
veraPDF (106/106) and PAC 2024 on all three platforms.

## Platforms

| Platform | Compiler | Backend | Status |
|---|---|---|---|
| Windows | FreePascal/Lazarus | GDI via interfaces | Production |
| Windows (Win32) | Delphi 7 | GDI via interfaces | Layer 1 only — `TPdfDocument`/`TPdfCanvas`; tests green, tagged Unicode output PAC-verified. The TCanvas bridge and `TGDIPages` need FPC for now (roadmap R-20) |
| Linux | FreePascal/Lazarus | FreeType2 | Production |
| macOS | FreePascal/Lazarus | FreeType2 | Production |

## Architecture (3 layers)

```
TGDIPages           mormot.ui.report     Document layout, tables, H1-H6
TPdfDocumentVcl     mormot.ui.pdfcanvas  TCanvas-compatible wrapper
TPdfDocument        mormot.ui.pdf        Direct PDF API, no TCanvas (links the LCL/VCL Graphics unit)
```

---

## Quick start

### Layer 1 — Direct PDF API (no TCanvas)

```pascal
uses mormot.ui.pdf;

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
uses mormot.ui.pdf, mormot.ui.pdfcanvas;

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
// or: Report.ShowPreviewForm
Report.Free;
```

Units: 1/100 mm. Learning path with all features: [docs/DEMOS.md](docs/DEMOS.md)

---

## Tagged PDF (PDF/UA)

`ExportPdfTagged := True` (report engine) or `Tagged := True` (low-level API)
writes the structure tree that screen readers and accessibility checkers need.
Both tagged demos pass **PAC 2024**, with one accepted warning for a decorative
figure in `pdf_demo`.

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
  font names *after* that, with `GetExportFonts` / `GetReportFonts`.
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

// Low-level API
Doc.Tagged          := True;
Doc.DefaultLanguage := 'en';
GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
Doc.AddPage;
Doc.BeginStructContent(psrH1);
Doc.VclCanvas.TextOut(40, 40, 'Title');
Doc.EndStructContent;
```

## Font embedding and subsetting

Embedded fonts hold only the glyphs a document uses, unless something prevents
that. `EmbeddedWholeTtf := True` always embeds the complete face.

| | Linux / macOS | Windows |
|---|---|---|
| Subsetter | `libharfbuzz-subset` (optional, see dependencies) | `CreateFontPackage`, part of the OS |
| Latin text | subset | subset |
| CJK, shaped Arabic | subset | subset |
| Tagged output | subset | subset |
| `markdown_demo_<os>.pdf` | 46 KB | 230 KB |

Both subsetters keep the original glyph numbering — `libharfbuzz-subset` by
retaining glyph IDs, `CreateFontPackage` through a glyph keep list
(`TTFCFP_FLAGS_GLYPHLIST`) — so Identity-H and the `/ToUnicode` round-trip
survive, which is what makes CJK and shaped Arabic safe to subset.

The whole face is embedded instead without `libharfbuzz-subset`, for PDF/A-1
(which would need a `/CIDSet`) and for symbol fonts on Linux/macOS. Text
extraction and copy/paste are unaffected either way.

Both outline flavours are subset. A `glyf` face goes to `/FontFile2`; a
CFF-flavoured OpenType face goes to `/FontFile3` with `/Subtype /OpenType`, as
a `CIDFontType0`. That matters on macOS, whose CJK system faces are CFF —
`chinese_demo` there went from 10 MB to 23 KB once this was handled correctly
(see R-15c in [docs/ROADMAP.md](docs/ROADMAP.md)).

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
Doc := TPdfDocumentVcl.Create(true, 0, pdfa3U);   // not the PdfA property: it resets the document
Doc.Tagged := True;
// ... draw the invoice ...
Doc.CreateFileAttachmentFrom(Xml, 'factur-x.xml', 'Factur-X invoice data',
  'text/xml', Now, Now, nil, afrAlternative);
Doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931');
```

---

## The 7 demos (learning path)

| Demo | API | What it shows |
|---|---|---|
| [pdf_demo](examples/pdf_demo/) | `TPdfDocumentVcl` | Text, graphics, tagged PDF (H1/P/Figure, Table with THead/TBody/TR/TH/TD) |
| [report_demo](examples/report_demo/) | `TGDIPages` + GUI | Preview, tagged tables with row groups and a footer row, running headers/footers, `--export` batch mode |
| [markdown_demo](examples/markdown_demo/) | `TGDIPages` | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| [mormot_demo](examples/mormot_demo/) | `TGDIPages` + ORM | SQLite database, service layer, TTableLayout, tagged export, `--export` batch mode |
| [chinese_demo](examples/chinese_demo/) | `TPdfDocumentVcl` | CJK text, subset embedding |
| [rtl_demo](examples/rtl_demo/) | `TPdfDocumentVcl` | Arabic RTL, HarfBuzz / Uniscribe shaping |
| [zugferd_demo](examples/zugferd_demo/) | `TPdfDocumentVcl` | PDF/A-3U + PDF/UA-1, ZUGFeRD / Factur-X invoice with embedded XML |

Full guide: [docs/DEMOS.md](docs/DEMOS.md)

---

## Build

```bash
# Windows
"C:\lazarus\lazbuild.exe" examples/pdf_demo/pdf_demo_crossplat.lpi -B
"C:\lazarus\lazbuild.exe" examples/report_demo/mormot_report_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/markdown_demo/markdown_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/mormot_demo/mormot_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/chinese_demo/chinese_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/rtl_demo/rtl_demo.lpi -B
"C:\lazarus\lazbuild.exe" examples/zugferd_demo/zugferd_demo.lpi -B

# Linux/macOS
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
lazbuild examples/markdown_demo/markdown_demo.lpi -B
lazbuild examples/chinese_demo/chinese_demo.lpi -B
lazbuild examples/rtl_demo/rtl_demo.lpi -B
lazbuild examples/report_demo/mormot_report_demo.lpi -B
lazbuild examples/mormot_demo/mormot_demo.lpi -B
lazbuild examples/zugferd_demo/zugferd_demo.lpi -B

# Test suite
lazbuild tests/test_runner.lpi -B && tests/bin/test_runner
```

**Delphi 7** (Win32, layer 1) builds from the command line. `MORMOT2` points to
the mORMot2 checkout, `DELPHI7` defaults to the standard install folder; output
goes to `bin\d7\<project>\`:

```bat
set MORMOT2=C:\path\to\mORMot2
tests\build_delphi7.bat tests\test_runner.lpr
bin\d7\test_runner\test_runner.exe --noenter
```

Do not put `mORMot2\src\ui` on a Delphi search path: it holds the original
`mormot.ui.pdf`, which the compiler would take instead of this project's.

The two GUI demos also export without their window, which is what the
automated checks use:

```bash
examples/report_demo/bin/<target>/report_demo_crossplat --export report.pdf
```

`TGDIPages` is an LCL control, so on Linux/GTK2 this still needs a display —
on a headless machine run it under `xvfb-run`. The macOS Cocoa widgetset
exports without one.

## Runtime dependencies

**Windows:** none additional (GDI is part of the OS)

**Linux:**
```bash
sudo apt install libfreetype6                    # required — PDF font rendering
sudo apt install libharfbuzz0b                   # optional — Arabic RTL shaping (rtl_demo)
sudo apt install libharfbuzz-subset0             # optional — font subsetting (HarfBuzz 2.9+)
sudo apt install fonts-noto-core                 # optional — Noto Naskh Arabic (rtl_demo)
sudo apt install fonts-wqy-microhei              # optional — CJK font (chinese_demo)
```
Fonts are detected automatically from `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.fonts`.

**macOS:**
```bash
brew install freetype
brew install harfbuzz          # optional — Arabic RTL shaping and font subsetting
```
Fonts from `/Library/Fonts`, `/System/Library/Fonts`, `~/Library/Fonts`.

---

## Open items

- **Symbol fonts on Linux/macOS:** not subset — the whole face is embedded, because hb-subset is not given the glyph IDs behind the `(3,0)` cmap. Windows subsets them (roadmap R-15b)
- **TTC collections:** only face index 0 is reachable (roadmap R-11)
- **EMF/MetaFile:** Windows-only (`TPdfDocumentGdi`), not portable
- **GDI+/Gradient fills:** available only via EMF on Windows
- **Table pagination:** no row wrap within a cell
- **Delphi:** layer 1 only, on Delphi 7 (Win32). The TCanvas bridge overrides methods that Delphi 7's VCL does not declare virtual; it comes with roadmap R-20
- **Links in tagged output:** `CreateHyperLink` in a tagged document fails PDF/UA — there is no `Link` structure element for annotations. `TGDIPages.DrawLink` stays conformant by drawing styled text only; its URL is not clickable (roadmap R-18)

Details and the current verification status: [docs/ROADMAP.md](docs/ROADMAP.md)

---

## License

This project follows the licensing terms of mORMot2. See the [mORMot2 repository](https://github.com/synopse/mORMot2) for details.
