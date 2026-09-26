# mORMot2 PDF Engine — Cross-Platform

Cross-platform PDF-Generierung für Windows, Linux und macOS, basierend auf der [mORMot2](https://github.com/synopse/mORMot2) PDF-Engine (`mormot.ui.pdf.pas`). Das Original ist Windows/GDI-only; dieses Projekt abstrahiert alle Plattformaufrufe hinter Interfaces und liefert ein FreeType2-Backend für Unix/macOS.

**Aktuelles Release: [v0.9.0](CHANGELOG.md)** — Tagged-PDF-Ausgabe von veraPDF
(106/106) und PAC 2024 auf allen drei Plattformen geprüft.

## Plattformen

| Plattform | Compiler | Backend | Status |
|---|---|---|---|
| Windows | FreePascal/Lazarus | GDI via Interfaces | Produktiv |
| Windows (Win32) | Delphi 7 | GDI via Interfaces | Nur Ebene 1 — `TPdfDocument`/`TPdfCanvas`; Tests grün, getaggte Unicode-Ausgabe mit PAC geprüft. TCanvas-Brücke und `TGDIPages` brauchen vorerst FPC (Roadmap R-20) |
| Linux | FreePascal/Lazarus | FreeType2 | Produktiv |
| macOS | FreePascal/Lazarus | FreeType2 | Produktiv |

## Architektur (3 Ebenen)

```
TGDIPages           mormot.ui.report     Dokument-Layout, Tabellen, H1-H6
TPdfDocumentVcl     mormot.ui.pdfcanvas  TCanvas-kompatibler Wrapper
TPdfDocument        mormot.ui.pdf        Direkte PDF-API, ohne TCanvas (bindet die Unit Graphics von LCL/VCL ein)
```

---

## Schnellstart

### Ebene 1 — Direkte PDF-API (ohne TCanvas)

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

### Ebene 2 — TCanvas-API

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
// Tagged PDF/UA: vor dem Zeichnen setzen — wählt die Schriften, mit denen das
// Layout vermessen wird, und löst aus, wenn schon eine Seite existiert
Report.ExportPdfTagged := True;
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
Report.ExportPdfStream(Stream);   // FileFormat wird automatisch auf pdf17 angehoben
// oder: Report.ShowPreviewForm
Report.Free;
```

Einheiten: 1/100mm. Lernpfad mit allen Features: [docs/DEMOS.md](docs/DEMOS.md)

---

## Tagged PDF (PDF/UA)

`ExportPdfTagged := True` (Report Engine) bzw. `Tagged := True` (Low-Level-API)
schreibt den Strukturbaum, den Screenreader und Barrierefreiheits-Prüfer
brauchen. Beide getaggten Demos bestehen **PAC 2024**, mit einer akzeptierten
Warnung für eine dekorative Grafik in `pdf_demo`.

Was die Engine erzeugt:

- Strukturelemente `H1`–`H6`, `P`, `Span`, `Figure` mit `/Alt`, Listen
  (`L` / `LI` / `Lbl` / `LBody`) und Tabellen
  (`Table` > `THead` | `TBody` | `TFoot` > `TR` > `TH` | `TD`)
- ein PDF-Lesezeichen je Überschrift, den Dokumenttitel in den XMP-Metadaten,
  dazu `/Lang` und `/DisplayDocTitle`
- laufende Kopf- und Fußzeilen, wiederholte Tabellenköpfe und dekorative
  Grafik als Artefakte, damit sie nicht doppelt vorgelesen werden

Zwei Regeln:

- **Schriften werden eingebettet.** PDF/UA erlaubt die eingebauten
  Standardschriften des Betrachters nicht, deshalb schaltet das Tagging
  `EmbeddedTTF` ein und `StandardFontsReplace` aus. Die Schriftnamen *danach*
  über `GetExportFonts` / `GetReportFonts` erfragen.
- **Vor der ersten Seite einschalten.** Die Font-Flags entscheiden, mit welchen
  Metriken das Layout vermessen wird; später gesetzt lösen sie eine Ausnahme
  aus.

```pascal
// Report Engine
Report.ExportPdfTagged := True;    // zuerst — wählt die Schriften für die Messung
Report.UseOutlines     := True;    // ein Lesezeichen je Überschrift
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
Report.NewPage;
Report.DrawHeading(1, 'Report-Titel');
// ... zeichnen, dann ExportPdfStream / ExportPDF

// Low-Level-API
Doc.Tagged          := True;
Doc.DefaultLanguage := 'de';
GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
Doc.AddPage;
Doc.BeginStructContent(psrH1);
Doc.VclCanvas.TextOut(40, 40, 'Titel');
Doc.EndStructContent;
```

## Schrifteinbettung und Subsetting

Eingebettete Schriften enthalten nur die tatsächlich benutzten Glyphen, sofern
nichts dagegen spricht. `EmbeddedWholeTtf := True` bettet immer die
vollständige Schrift ein.

| | Linux / macOS | Windows |
|---|---|---|
| Subsetter | `libharfbuzz-subset` (optional, siehe Abhängigkeiten) | `CreateFontPackage`, Teil des Betriebssystems |
| Latin-Text | Subset | Subset |
| CJK, geformtes Arabisch | Subset | Subset |
| Getaggte Ausgabe | Subset | Subset |
| `markdown_demo_<os>.pdf` | 46 KB | 230 KB |

Beide Subsetter behalten die ursprüngliche Glyphennummerierung —
`libharfbuzz-subset` über Retain-GIDs, `CreateFontPackage` über eine
Glyphen-Keep-Liste (`TTFCFP_FLAGS_GLYPHLIST`). Deshalb bleiben Identity-H und
der `/ToUnicode`-Rückweg gültig, und deshalb sind CJK und geformtes Arabisch
sicher zu subsetten.

Stattdessen wird die ganze Schrift eingebettet, wenn `libharfbuzz-subset`
fehlt, bei PDF/A-1 (dort wäre ein `/CIDSet` nötig) und bei Symbolschriften
unter Linux/macOS. Textextraktion und Kopieren sind in beiden Fällen
unverändert.

Beide Umriss-Varianten werden gesubsettet. Eine `glyf`-Schrift landet in
`/FontFile2`, eine CFF-OpenType-Schrift in `/FontFile3` mit
`/Subtype /OpenType` als `CIDFontType0`. Das ist unter macOS relevant, dessen
CJK-Systemschriften CFF sind: `chinese_demo` schrumpfte dort von 10 MB auf
23 KB, nachdem dies korrekt behandelt wurde (siehe R-15c in
[docs/ROADMAP.md](docs/ROADMAP.md)).

## PDF/A und E-Rechnungen (ZUGFeRD / Factur-X)

PDF/A-3 und PDF/UA-1 lassen sich in einer Datei kombinieren: die Stufe dem
Konstruktor übergeben, `Tagged` einschalten — die Engine schreibt ein
XMP-Paket mit beiden Kennungen und dem Erweiterungsschema, das PDF/A für
`pdfuaid` verlangt.

| Stufe | Stand |
|---|---|
| **PDF/A-3U** + PDF/UA-1 | auf allen drei Plattformen geprüft — veraPDF `3u` und `ua1`, PAC 2024 |
| **PDF/A-3A** | geprüft mit `Tagged := True` (veraPDF `3a`); die Stufe A braucht den Strukturbaum |
| PDF/A-3B | geprüft, mit und ohne Tagging |
| PDF/A-1A/B, -2A/B | implementiert, nicht geprüft. PDF/A-1 bettet ganze Schriften ein (kein `/CIDSet`) |

**Hybride E-Rechnungen.** Eine ZUGFeRD-2.x-/Factur-X-1.x-Rechnung ist ein
PDF/A-3 mit eingebetteter CII-XML als verknüpfter Datei. Die Engine liefert
den Container — `CreateFileAttachmentFrom` mit `/AFRelationship` und
`PdfMetadataFacturX` für die `fx:`-XMP-Eigenschaften — und bleibt gegenüber
der Rechnung selbst neutral: Sie erzeugt und prüft keine XML.
[zugferd_demo](examples/zugferd_demo/) baut eine Rechnung im Profil EN 16931,
die Mustang als valide bestätigt — die Form für den Austausch zwischen
Unternehmen in Deutschland und Frankreich. Rechnungen an deutsche Behörden
erwarten reine XML (XRechnung), kein PDF, und gehören nicht zum Umfang.

```pascal
Doc := TPdfDocumentVcl.Create(true, 0, pdfa3U);   // nicht die Property PdfA: sie setzt das Dokument zurück
Doc.Tagged := True;
// ... Rechnung zeichnen ...
Doc.CreateFileAttachmentFrom(Xml, 'factur-x.xml', 'Factur-X invoice data',
  'text/xml', Now, Now, nil, afrAlternative);
Doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931');
```

---

## Die 7 Demos (Lernpfad)

| Demo | API | Was wird gezeigt |
|---|---|---|
| [pdf_demo](examples/pdf_demo/) | `TPdfDocumentVcl` | Text, Grafik, Tagged PDF (H1/P/Figure, Tabelle mit THead/TBody/TR/TH/TD) |
| [report_demo](examples/report_demo/) | `TGDIPages` + GUI | Preview, getaggte Tabellen mit Zeilengruppen und Fußzeile, laufende Kopf-/Fußzeilen, `--export`-Stapelbetrieb |
| [markdown_demo](examples/markdown_demo/) | `TGDIPages` | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| [mormot_demo](examples/mormot_demo/) | `TGDIPages` + ORM | SQLite-Datenbank, Service-Layer, TTableLayout, getaggter Export, `--export`-Stapelbetrieb |
| [chinese_demo](examples/chinese_demo/) | `TPdfDocumentVcl` | CJK-Text, Subset-Embedding |
| [rtl_demo](examples/rtl_demo/) | `TPdfDocumentVcl` | Arabisch RTL, HarfBuzz / Uniscribe Shaping |
| [zugferd_demo](examples/zugferd_demo/) | `TPdfDocumentVcl` | PDF/A-3U + PDF/UA-1, ZUGFeRD-/Factur-X-Rechnung mit eingebetteter XML |

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
"C:\lazarus\lazbuild.exe" examples/zugferd_demo/zugferd_demo.lpi -B

# Linux/macOS
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
lazbuild examples/markdown_demo/markdown_demo.lpi -B
lazbuild examples/chinese_demo/chinese_demo.lpi -B
lazbuild examples/rtl_demo/rtl_demo.lpi -B
lazbuild examples/report_demo/mormot_report_demo.lpi -B
lazbuild examples/mormot_demo/mormot_demo.lpi -B
lazbuild examples/zugferd_demo/zugferd_demo.lpi -B

# Testsuite
lazbuild tests/test_runner.lpi -B && tests/bin/test_runner
```

**Delphi 7** (Win32, Ebene 1) baut von der Kommandozeile. `MORMOT2` zeigt auf
den mORMot2-Checkout, `DELPHI7` ist standardmäßig der übliche
Installationsordner; die Ausgabe landet in `bin\d7\<Projekt>\`:

```bat
set MORMOT2=C:\pfad\zu\mORMot2
tests\build_delphi7.bat tests\test_runner.lpr
bin\d7\test_runner\test_runner.exe --noenter
```

`mORMot2\src\ui` gehört nicht in einen Delphi-Suchpfad: Dort liegt das
originale `mormot.ui.pdf`, das der Compiler sonst statt der Unit dieses
Projekts nimmt.

Die beiden GUI-Demos exportieren auch ohne Fenster — so laufen die
automatisierten Prüfungen:

```bash
examples/report_demo/bin/<target>/report_demo_crossplat --export report.pdf
```

`TGDIPages` ist ein LCL-Control, daher wird unter Linux/GTK2 trotzdem ein
Display gebraucht — auf einer Maschine ohne Bildschirm `xvfb-run` davorsetzen.
Das Cocoa-Widgetset unter macOS exportiert auch ohne Display.

## Runtime-Abhängigkeiten

**Windows:** keine zusätzlichen (GDI ist Teil des OS)

**Linux:**
```bash
sudo apt install libfreetype6                    # Pflicht — PDF-Fontrendering
sudo apt install libharfbuzz0b                   # Optional — arabisches RTL-Shaping (rtl_demo)
sudo apt install libharfbuzz-subset0             # Optional — Font-Subsetting (HarfBuzz 2.9+)
sudo apt install fonts-noto-core                 # Optional — Noto Naskh Arabic (rtl_demo)
sudo apt install fonts-wqy-microhei              # Optional — CJK-Font (chinese_demo)
```
Fonts werden automatisch aus `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.fonts` gefunden.

**macOS:**
```bash
brew install freetype
brew install harfbuzz          # Optional — arabisches RTL-Shaping und Font-Subsetting
```
Fonts aus `/Library/Fonts`, `/System/Library/Fonts`, `~/Library/Fonts`.

---

## Open Items

- **Symbolschriften unter Linux/macOS:** werden nicht gesubsettet — die ganze Schrift wird eingebettet, weil hb-subset die Glyphen-IDs hinter der `(3,0)`-Cmap nicht erhält. Windows subsettet sie (Roadmap R-15b)
- **TTC-Sammlungen:** nur Face-Index 0 ist erreichbar (Roadmap R-11)
- **EMF/MetaFile:** Windows-only (`TPdfDocumentGdi`), nicht portierbar
- **GDI+/Gradient Fills:** nur via EMF auf Windows verfügbar
- **Tabellen-Pagination:** kein Zeilenumbruch innerhalb einer Zelle
- **Delphi:** nur Ebene 1 unter Delphi 7 (Win32). Die TCanvas-Brücke überschreibt Methoden, die in der VCL von Delphi 7 nicht virtuell sind; sie kommt mit Roadmap R-20
- **Links in getaggter Ausgabe:** `CreateHyperLink` in einem getaggten Dokument verletzt PDF/UA — es gibt kein `Link`-Strukturelement für Annotationen. `TGDIPages.DrawLink` bleibt konform, weil es nur formatierten Text zeichnet; seine URL ist nicht anklickbar (Roadmap R-18)

Details und aktueller Prüfstand: [docs/ROADMAP.md](docs/ROADMAP.md)

---

## Lizenz

Dieses Projekt folgt den Lizenzbedingungen von mORMot2. Siehe [mORMot2 Repository](https://github.com/synopse/mORMot2) für Details.
