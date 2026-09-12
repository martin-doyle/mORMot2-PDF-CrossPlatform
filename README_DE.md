# mORMot2 PDF Engine — Cross-Platform

Cross-platform PDF-Generierung für Windows, Linux und macOS, basierend auf der [mORMot2](https://github.com/synopse/mORMot2) PDF-Engine (`mormot.ui.pdf.pas`). Das Original ist Windows/GDI-only; dieses Projekt abstrahiert alle Plattformaufrufe hinter Interfaces und liefert ein FreeType2-Backend für Unix/macOS.

## Plattformen

| Plattform | Compiler | Backend | Status |
|---|---|---|---|
| Windows | Delphi 7+ | GDI (Original) | Produktiv |
| Windows | FreePascal/Lazarus | GDI via Interfaces | Produktiv |
| Linux | FreePascal/Lazarus | FreeType2 | Produktiv |
| macOS | FreePascal/Lazarus | FreeType2 | Produktiv |

## Architektur (3 Ebenen)

```
TGDIPages           mormot.ui.report     Dokument-Layout, Tabellen, H1-H6
TPdfDocumentVcl     mormot.ui.pdfcanvas  TCanvas-kompatibler Wrapper
TPdfDocument        mormot.ui.pdf        Direkte PDF-API (kein LCL nötig)
```

---

## Schnellstart

### Ebene 1 — Direkte PDF-API (kein LCL)

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

Koordinaten in PDF-Points (72 DPI), Y=0 unten-links.

### Ebene 2 — TCanvas-API (mit LCL)

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

Koordinaten in Pixel (96 DPI), Y=0 oben-links. Vollständige Methoden-Referenz: [docs/API_REFERENCE.md](docs/API_REFERENCE.md)

### Ebene 3 — Report Engine

```pascal
uses mormot.ui.report;

Report := TGDIPages.Create(nil);
Report.ExportPdfEmbeddedTTF := False;
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
Report.PaperSize        := psA4;
Report.MarginLeft       := 1500;   // 15 mm
Report.LineHeightFactor := 1.3;    // Zeilenabstand (Standard 1.1)
Report.NewPage;
Report.SetFont(SansFont, 11);
Report.DrawHeading(1, 'Report-Titel');          // automatisches PDF-Lesezeichen
Report.DrawParagraph('Text mit Zeilenumbruch...');
Report.BeginTable(MyLayout);
Report.DrawTableHeader(['Spalte 1', 'Spalte 2']);
Report.DrawTableRow(['Wert A', 'Wert B']);      // automatischer Seitenumbruch + Header-Wiederholung
Report.EndTable;
Report.EndDoc;
// Tagged PDF + Stream-Export (FileFormat wird automatisch auf pdf17 angehoben)
Report.ExportPdfTagged := True;
Report.ExportPdfStream(Stream);
// oder: Report.ShowPreviewForm
Report.Free;
```

Einheiten: 1/100mm. Lernpfad mit allen Features: [docs/DEMOS.md](docs/DEMOS.md)

---

## Die 6 Demos (Lernpfad)

| Demo | API | Was wird gezeigt |
|---|---|---|
| [pdf_demo](examples/pdf_demo/) | `TPdfDocumentVcl` | Text, Grafik, Tagged PDF (H1/P/Figure/Table/TR/TH/TD) |
| [report_demo](examples/report_demo/) | `TGDIPages` + GUI | Preview, Tabellen, Kopf-/Fußzeilen |
| [markdown_demo](examples/markdown_demo/) | `TGDIPages` | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| [mormot_demo](examples/mormot_demo/) | `TGDIPages` + ORM | SQLite-Datenbank, Service-Layer, TTableLayout |
| [chinese_demo](examples/chinese_demo/) | `TPdfDocumentVcl` | CJK-Text, vollständiges TTF-Embedding |
| [rtl_demo](examples/rtl_demo/) | `TPdfDocumentVcl` | Arabisch RTL, HarfBuzz / Uniscribe Shaping |

Vollständige Anleitung: [docs/DEMOS.md](docs/DEMOS.md)

---

## Bauen

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

## Runtime-Abhängigkeiten

**Windows:** keine zusätzlichen (GDI ist Teil des OS)

**Linux:**
```bash
sudo apt install libfreetype6                    # Pflicht — PDF-Fontrendering
sudo apt install libharfbuzz0b                   # Optional — arabisches RTL-Shaping (rtl_demo)
sudo apt install fonts-noto-core                 # Optional — Noto Naskh Arabic (rtl_demo)
sudo apt install fonts-wqy-microhei              # Optional — CJK-Font (chinese_demo)
```
Fonts werden automatisch aus `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.fonts` gefunden.

**macOS:**
```bash
brew install freetype
brew install harfbuzz          # Optional — arabisches RTL-Shaping (rtl_demo)
```
Fonts aus `/Library/Fonts`, `/System/Library/Fonts`, `~/Library/Fonts`.

---

## Open Items

- **Font-Subsetting:** opt-in via `EmbeddedWholeTtf := False`; für CJK und RTL/Arabisch nicht zuverlässig — vollständiges TTF empfohlen
- **EMF/MetaFile:** Windows-only (`TPdfDocumentGdi`), nicht portierbar
- **GDI+/Gradient Fills:** nur via EMF auf Windows verfügbar
- **Tabellen-Pagination:** kein Zeilenumbruch innerhalb einer Zelle

---

## Lizenz

Dieses Projekt folgt den Lizenzbedingungen von mORMot2. Siehe [mORMot2 Repository](https://github.com/synopse/mORMot2) für Details.
