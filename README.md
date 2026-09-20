# mORMot2 PDF Engine — Cross-Platform

Cross-platform PDF generation for Windows, Linux and macOS, based on the [mORMot2](https://github.com/synopse/mORMot2) PDF engine (`mormot.ui.pdf.pas`). The original implementation is Windows/GDI-only; this project abstracts all platform calls behind interfaces and provides a FreeType2 backend for Unix/macOS.

## Platforms

| Platform | Compiler | Backend | Status |
|---|---|---|---|
| Windows | Delphi 7+ | GDI (original) | Production |
| Windows | FreePascal/Lazarus | GDI via interfaces | Production |
| Linux | FreePascal/Lazarus | FreeType2 | Production |
| macOS | FreePascal/Lazarus | FreeType2 | Production — build verification outstanding |

## Architecture (3 layers)

```
TGDIPages           mormot.ui.report     Document layout, tables, H1-H6
TPdfDocumentVcl     mormot.ui.pdfcanvas  TCanvas-compatible wrapper
TPdfDocument        mormot.ui.pdf        Direct PDF API (no LCL required)
```

---

## Quick start

### Layer 1 — Direct PDF API (no LCL)

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

### Layer 2 — TCanvas API (with LCL)

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
| `markdown_demo.pdf` | 46 KB | 230 KB |

Both subsetters keep the original glyph numbering — `libharfbuzz-subset` by
retaining glyph IDs, `CreateFontPackage` through a glyph keep list
(`TTFCFP_FLAGS_GLYPHLIST`) — so Identity-H and the `/ToUnicode` round-trip
survive, which is what makes CJK and shaped Arabic safe to subset.

The whole face is embedded instead without `libharfbuzz-subset`, for PDF/A-1
(which would need a `/CIDSet`), for symbol fonts on Linux/macOS and for
CFF-flavoured OpenType. Text extraction and copy/paste are unaffected either
way.

---

## The 6 demos (learning path)

| Demo | API | What it shows |
|---|---|---|
| [pdf_demo](examples/pdf_demo/) | `TPdfDocumentVcl` | Text, graphics, tagged PDF (H1/P/Figure, Table with THead/TBody/TR/TH/TD) |
| [report_demo](examples/report_demo/) | `TGDIPages` + GUI | Preview, tagged tables with row groups and a footer row, running headers/footers, `--export` batch mode |
| [markdown_demo](examples/markdown_demo/) | `TGDIPages` | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| [mormot_demo](examples/mormot_demo/) | `TGDIPages` + ORM | SQLite database, service layer, TTableLayout, tagged export, `--export` batch mode |
| [chinese_demo](examples/chinese_demo/) | `TPdfDocumentVcl` | CJK text, subset embedding |
| [rtl_demo](examples/rtl_demo/) | `TPdfDocumentVcl` | Arabic RTL, HarfBuzz / Uniscribe shaping |

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

# Linux/macOS
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
lazbuild examples/markdown_demo/markdown_demo.lpi -B
lazbuild examples/chinese_demo/chinese_demo.lpi -B
lazbuild examples/rtl_demo/rtl_demo.lpi -B
lazbuild examples/report_demo/mormot_report_demo.lpi -B
lazbuild examples/mormot_demo/mormot_demo.lpi -B

# Test suite
lazbuild tests/test_runner.lpi -B && tests/bin/test_runner
```

The two GUI demos also export without their window, which is what the
automated checks use:

```bash
examples/report_demo/bin/<target>/report_demo_crossplat --export report.pdf
```

`TGDIPages` is an LCL control, so this still needs a display — on a headless
machine run it under `xvfb-run`.

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

Details and the current verification status: [docs/ROADMAP.md](docs/ROADMAP.md)

---

## License

This project follows the licensing terms of mORMot2. See the [mORMot2 repository](https://github.com/synopse/mORMot2) for details.
