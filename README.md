# mORMot2 PDF Engine — Cross-Platform

Cross-platform PDF generation for Windows, Linux and macOS, based on the [mORMot2](https://github.com/synopse/mORMot2) PDF engine (`mormot.ui.pdf.pas`). The original implementation is Windows/GDI-only; this project abstracts all platform calls behind interfaces and provides a FreeType2 backend for Unix/macOS.

## Platforms

| Platform | Compiler | Backend | Status |
|---|---|---|---|
| Windows | Delphi 7+ | GDI (original) | Production |
| Windows | FreePascal/Lazarus | GDI via interfaces | Production |
| Linux | FreePascal/Lazarus | FreeType2 | Production |
| macOS | FreePascal/Lazarus | FreeType2 | Production |

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
Report.ExportPdfEmbeddedTTF := False;
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
// Tagged PDF + stream export (file format is automatically raised to pdf17)
Report.ExportPdfTagged := True;
Report.ExportPdfStream(Stream);
// or: Report.ShowPreviewForm
Report.Free;
```

Units: 1/100 mm. Learning path with all features: [docs/DEMOS.md](docs/DEMOS.md)

---

## The 6 demos (learning path)

| Demo | API | What it shows |
|---|---|---|
| [pdf_demo](examples/pdf_demo/) | `TPdfDocumentVcl` | Text, graphics, tagged PDF (H1/P/Figure/Table/TR/TH/TD) |
| [report_demo](examples/report_demo/) | `TGDIPages` + GUI | Preview, tables, headers/footers |
| [markdown_demo](examples/markdown_demo/) | `TGDIPages` | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| [mormot_demo](examples/mormot_demo/) | `TGDIPages` + ORM | SQLite database, service layer, TTableLayout |
| [chinese_demo](examples/chinese_demo/) | `TPdfDocumentVcl` | CJK text, full TTF embedding |
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
```

## Runtime dependencies

**Windows:** none additional (GDI is part of the OS)

**Linux:**
```bash
sudo apt install libfreetype6                    # required — PDF font rendering
sudo apt install libharfbuzz0b                   # optional — Arabic RTL shaping (rtl_demo)
sudo apt install fonts-noto-core                 # optional — Noto Naskh Arabic (rtl_demo)
sudo apt install fonts-wqy-microhei              # optional — CJK font (chinese_demo)
```
Fonts are detected automatically from `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.fonts`.

**macOS:**
```bash
brew install freetype
brew install harfbuzz          # optional — Arabic RTL shaping (rtl_demo)
```
Fonts from `/Library/Fonts`, `/System/Library/Fonts`, `~/Library/Fonts`.

---

## Open items

- **Font subsetting:** opt-in via `EmbeddedWholeTtf := False`; not reliable for CJK and RTL/Arabic — full TTF is recommended
- **EMF/MetaFile:** Windows-only (`TPdfDocumentGdi`), not portable
- **GDI+/Gradient fills:** available only via EMF on Windows
- **Table pagination:** no row wrap within a cell

---

## License

This project follows the licensing terms of mORMot2. See the [mORMot2 repository](https://github.com/synopse/mORMot2) for details.
