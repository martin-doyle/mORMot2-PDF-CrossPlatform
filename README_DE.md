# mORMot2 PDF Engine — Cross-Platform

Cross-platform PDF-Generierung für Windows, Linux und macOS, basierend auf der [mORMot2](https://github.com/synopse/mORMot2) PDF-Engine (`mormot.ui.pdf.pas`). Das Original ist Windows/GDI-only; dieses Projekt abstrahiert alle Plattformaufrufe hinter Interfaces und liefert ein FreeType2-Backend für Unix/macOS.

**Aktuelles Release: [v0.10.0](CHANGELOG.md)** — PDF/A-3 und
ZUGFeRD-/Factur-X-E-Rechnungen, Delphi 7 bis Delphi 13; Tagged-PDF-Ausgabe von
veraPDF und PAC 2024 auf allen drei Plattformen geprüft.

## Plattformen

| Plattform | Compiler | Backend | Status |
|---|---|---|---|
| Windows | FreePascal/Lazarus | GDI via Interfaces | Produktiv |
| Windows (Win32) | Delphi 7, Delphi 2010 | GDI via Interfaces | Ebene 1, die TCanvas-Brücke und der Kern von `TGDIPages`; Tests grün unter beiden, die sechs Konsolen-Demos und der `--export` der beiden GUI-Demos geben dasselbe PDF wie FPC. Vorschau und Demo-Fenster brauchen vorerst FPC (Roadmap R-20) |
| Windows (Win32, Win64) | Delphi 13 | GDI via Interfaces | Ebene 1, die TCanvas-Brücke und der Kern von `TGDIPages`; Tests grün (Roadmap R-27) |
| Linux | FreePascal/Lazarus | FreeType2 | Produktiv |
| Linux64, Android64 | Delphi 13 | FreeType2 | Ebene 1 und die Backends; Tests grün. Keine TCanvas-Brücke und kein `TGDIPages`: Delphi hat dort keine VCL (Roadmap R-27) |
| macOS | FreePascal/Lazarus | FreeType2 | Produktiv |

## Architektur (3 Ebenen)

```
TGDIPages           mormot.ui.report     Dokument-Layout, Tabellen, H1-H6
TPdfDocumentVcl     mormot.ui.pdfcanvas  TCanvas-kompatibler Wrapper
TPdfDocument        mormot.pdf           Direkte PDF-API, ohne TCanvas, ohne VCL/LCL
```

### Welche Unit wofür

Ein Programm bindet die Units der Ebene ein, auf der es arbeitet, wie hier
aufgeführt; was die API einer Ebene von unten braucht, exportiert diese Ebene
selbst weiter:

| Ebene | `uses` | Re-Exporte |
|---|---|---|
| 3 — `TGDIPages` | `mormot.ui.report`; eine GUI nimmt `mormot.ui.reportpreview` für Vorschau und Druck dazu | was die `ExportPdf*`-Optionen erwarten: `TPdfALevel` (`pdfaNone` … `pdfa3U`), `TPdfFileFormat` (`pdf13` … `pdf17`), `TPdfAFRelationship` (`afr*`), `PdfMetadataFacturX` |
| 2 — `TPdfDocumentVcl` | `mormot.ui.pdfcanvas`, `mormot.pdf` | `TPdfALevel`, `TPdfAFRelationship`, `PdfMetadataFacturX`; der Rest der Dokument-API kommt aus `mormot.pdf` |
| 1 — `TPdfDocument` | `mormot.pdf` | — |

Die Strukturrollen (`psrH1`, `psrP`, …) und `GetPdfFonts` kommen mit
`mormot.pdf` (deklariert in `mormot.pdf.types`, re-exportiert).

**Die Plattform-Units brauchen kein eigenes `uses`.** `mormot.pdf` bindet
unter Windows GDI und Uniscribe ein, unter Linux und macOS FreeType2, den
HarfBuzz-Shaper und den hb-subset-Subsetter. HarfBuzz wird zur Laufzeit
geladen: Fehlt die Bibliothek, wird Text ungeformt gezeichnet und Schriften
werden ganz eingebettet.

**Shaping** von arabischem, hebräischem, indischem oder thailändischem Text
ist auf jeder Plattform ein Schalter, `UseUniscribe := True` — der Name stammt
aus der Original-API; unter Linux und macOS formt HarfBuzz. Lateinischer Text
bleibt in beiden Fällen in der einfachen Schrift. `RightToLeftText := True`
auf dem Canvas setzt die Absatzrichtung; ohne ihn ergibt sich die Richtung aus
der Schrift. Den Schalter ohne Bedingung setzen — siehe
[rtl_demo](examples/rtl_demo/).

**`mormot.pdf` nie neben `mormot.ui.report` einbinden.** Beide verwenden
einige Namen für Verschiedenes — `psA4` ist in der einen ein `TPdfPaperSize`,
in der anderen ein `TGdiPagePaperSize`, und das `TRect` von `mormot.pdf`
ist nicht das der LCL —, also entscheidet die Reihenfolge der `uses`-Klausel,
welches ein Name meint. Mit `mormot.pdf` zuletzt kompiliert
`Report.PaperSize := psA4` nicht. Was ein Report von unten braucht, exportiert
`mormot.ui.report` weiter; fehlt etwas, gehört es dorthin, nicht in die eigene
`uses`-Klausel.

---

## Schnellstart

### Ebene 1 — Direkte PDF-API (ohne TCanvas)

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

Koordinaten in PDF-Points (72 DPI), Y=0 unten-links.

### Ebene 2 — TCanvas-API

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
// oder: ShowReportPreview(Report)   // mormot.ui.reportpreview
Report.Free;
```

Einheiten: 1/100mm. Lernpfad mit allen Features: [docs/DEMOS.md](docs/DEMOS.md)

---

## Tagged PDF (PDF/UA)

`ExportPdfTagged := True` (Report Engine) bzw. `Tagged := True` (Low-Level-API)
schreibt den Strukturbaum, den Screenreader und Barrierefreiheits-Prüfer
brauchen. Die getaggten Demos bestehen **PAC 2024**. PAC behält einen
akzeptierten Hinweis auf jeder `Figure`, „possibly inappropriate use of
figure“; er erscheint bei Vektorpfaden und Bildern gleichermaßen. In
`zugferd_demo` kommt einer dazu, „link in text does not have a Link element“,
für die E-Mail-Adressen, die als einfacher Text gezeichnet sind: Ein
anklickbarer Link bräuchte eine getaggte Link-Annotation, die die Engine nicht
schreibt (siehe *Links in getaggter Ausgabe* unten).

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
  über `GetExportFonts` / `GetPdfFonts` erfragen.
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

// TCanvas-Brücke (Ebene 2)
Doc.Tagged          := True;
Doc.DefaultLanguage := 'de';
GetPdfFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
Doc.AddPage;
Doc.BeginStructContent(psrH1);
Doc.VclCanvas.TextOut(40, 40, 'Titel');
Doc.EndStructContent;
```

**Diagramme gehören nicht zum Umfang.** Das Projekt hat keine Diagramm-Engine
und bekommt keine, so wie es auch keine Rechnungs-XML erzeugt. Ein Diagramm
kommt als Bild aus einer Diagramm-Bibliothek nach Wahl, gezeichnet in eine
`Figure` mit einem Alternativtext, der sagt, was das Diagramm zeigt. Ein
Diagramm, das Daten trägt, sollte diese Werte zusätzlich als echte Tabelle im
Dokument haben: Ein Alternativtext kann keine Datenreihe tragen, eine Tabelle
lässt sich Zelle für Zelle lesen.

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
| `markdown_demo_<os>_<cpu>_<compiler>.pdf` | 46 KB | 230 KB |

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
// TCanvas-Brücke (Ebene 2)
Doc := TPdfDocumentVcl.Create(true, 0, pdfa3U);   // nicht die Property PdfA: sie setzt das Dokument zurück
Doc.Tagged := True;
// ... Rechnung zeichnen ...
Doc.CreateFileAttachmentFrom(Xml, 'factur-x.xml', 'Factur-X invoice data',
  'text/xml', Now, Now, nil, afrAlternative);
Doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931');

// Report Engine (Ebene 3) - nur mormot.ui.report
Report.ExportPdfLevel := pdfa3U;
Report.ExportPdfTagged := True;
// ... Rechnung zeichnen ...
Report.AddExportPdfAttachment(Xml, 'factur-x.xml', 'Factur-X invoice data',
  'text/xml', afrAlternative);
Report.ExportPdfMetadataExtension := PdfMetadataFacturX('EN 16931');
Report.ExportPdfStream(Stream);
```

---

## Die 8 Demos (Lernpfad)

| Demo | API | Was wird gezeigt |
|---|---|---|
| [pdf_demo](examples/pdf_demo/) | `TPdfDocumentVcl` | Text, Grafik, Tagged PDF (H1/P/Figure, Tabelle mit THead/TBody/TR/TH/TD) |
| [report_demo](examples/report_demo/) | `TGDIPages` + GUI | Preview, getaggte Tabellen mit Zeilengruppen und Fußzeile, laufende Kopf-/Fußzeilen, `--export`-Stapelbetrieb |
| [markdown_demo](examples/markdown_demo/) | `TGDIPages` | H1-H6, TTableLayout, LineHeightFactor, ExportPdfTagged |
| [mormot_demo](examples/mormot_demo/) | `TGDIPages` + ORM | SQLite-Datenbank, Service-Layer, TTableLayout, getaggter Export, `--export`-Stapelbetrieb |
| [chinese_demo](examples/chinese_demo/) | `TPdfDocumentVcl` | CJK-Text, Subset-Embedding |
| [rtl_demo](examples/rtl_demo/) | `TPdfDocumentVcl` | Arabisch RTL, HarfBuzz / Uniscribe Shaping |
| [zugferd_demo](examples/zugferd_demo/) | `TGDIPages` | PDF/A-3U + PDF/UA-1, ZUGFeRD-/Factur-X-Rechnung, aus ihrer XML gelesen und mit ihr eingebettet |
| [layer1_demo](examples/layer1_demo/) | `TPdfDocument` | Die Low-Level-API allein: getaggte Überschriften, Text, eine Grafik und eine Tabelle mit THead/TBody/TFoot, in PDF-Points; baut mit FPC, Delphi 7 und Delphi 2010 |

Vollständige Anleitung: [docs/DEMOS.md](docs/DEMOS.md)

---

## Bauen

Voraussetzungen: FreePascal 3.2+ mit Lazarus und den mORMot2-Quellen (das
Lazarus-Paket `mormot2`), oder Delphi 7 / Delphi 2010 für Win32, oder
Delphi 13 — siehe unten.

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

# Testsuite
lazbuild tests/test_runner.lpi -B && tests/bin/<cpu-os>/test_runner
# unter Windows: tests\bin\x86_64-win64\test_runner.exe --noenter (sonst wartet es auf Enter)
```

**Delphi 7** (Win32: Ebene 1, die TCanvas-Brücke, der Kern von `TGDIPages`) baut von der Kommandozeile. `MORMOT2` zeigt auf
den mORMot2-Checkout, `DELPHI7` ist standardmäßig der übliche
Installationsordner; die Ausgabe landet in `bin\d7\<Projekt>\`:

```bat
set MORMOT2=C:\pfad\zu\mORMot2
tests\build_delphi7.bat tests\test_runner.lpr
bin\d7\test_runner\test_runner.exe --noenter
tests\build_delphi7.bat examples\layer1_demo\layer1_demo.dpr
bin\d7\layer1_demo\layer1_demo.exe
tests\build_delphi7.bat examples\markdown_demo\markdown_demo.lpr
bin\d7\markdown_demo\markdown_demo.exe
```

**Delphi 2010** (ein Unicode-Delphi) baut dieselben Projekte auf dieselbe Weise
mit `tests\build_delphi2010.bat`, Ausgabe in `bin\d2010\<Projekt>\`, und gibt
dieselben PDFs wie Delphi 7.

**Delphi 13** baut die Testsuiten aus der IDE: `tests\delphi13\test_runner.dproj`
für Win32, Win64 und Linux64 (über PAServer), `MORMOT2` gesetzt wie für
Delphi 7. Für Android64 gibt es einen eigenen FMX-Host in
`tests\delphi13\android\`, weil Android keine Konsolenprogramme startet:
`build.cmd` baut das APK, `run-emulator.cmd -Run` lässt die Suiten im Emulator
laufen und gibt das Ergebnis als Exit-Code zurück. Die App braucht ein mit dem
NDK gebautes `libfreetype.so`, siehe
[BUILD-FREETYPE.md](tests/delphi13/android/BUILD-FREETYPE.md).

`mORMot2\src\ui` gehört nicht in einen Delphi-Suchpfad: Dort liegt das
originale `mormot.ui.pdf`, das der Compiler sonst statt der Unit dieses
Projekts nimmt.

Die beiden GUI-Demos exportieren auch ohne Fenster — so laufen die
automatisierten Prüfungen:

```bash
examples/report_demo/bin/<target>/report_demo --export report.pdf
```

Die LCL misst den Text, daher wird unter Linux/GTK2 trotzdem ein
Display gebraucht — auf einer Maschine ohne Bildschirm `xvfb-run` davorsetzen.
Das Cocoa-Widgetset unter macOS exportiert auch ohne Display.

## Runtime-Abhängigkeiten

**Windows:** keine zusätzlichen (GDI ist Teil des OS)

**Linux:**
```bash
sudo apt install libfreetype6                    # Pflicht — PDF-Fontrendering
sudo apt install libharfbuzz0b                   # Optional — Shaping von Arabisch, Hebräisch, Indisch ... (UseUniscribe)
sudo apt install libharfbuzz-subset0             # Optional — Font-Subsetting (HarfBuzz 2.9+)
sudo apt install fonts-liberation                # Empfohlen — Liberation Sans/Serif/Mono, die Schriften der eingebetteten und getaggten Ausgabe
sudo apt install fonts-noto-core                 # Optional — Noto Naskh Arabic (rtl_demo)
sudo apt install fonts-droid-fallback            # Optional — Droid Sans Fallback, CJK (chinese_demo)
```
Fonts werden automatisch aus `/usr/share/fonts`, `/usr/local/share/fonts`, `~/.fonts` gefunden.

Font-Subsetting braucht HarfBuzz 2.9 oder neuer. Debian 11, Ubuntu 22.04 LTS
und RHEL 8/9 liefern ältere Versionen (1.7.5–2.7.4): dort wird jede Schrift
ganz eingebettet.

**macOS:**
```bash
brew install freetype
brew install harfbuzz          # Optional — Shaping (UseUniscribe) und Font-Subsetting
```
Fonts aus `/Library/Fonts`, `/System/Library/Fonts`, `~/Library/Fonts`.

**Android** (Delphi 13): Android bringt kein öffentliches FreeType mit — die App
liefert ein mit dem NDK gebautes `libfreetype.so` mit
([BUILD-FREETYPE.md](tests/delphi13/android/BUILD-FREETYPE.md)); ein Build für
Linux ARM64 lädt nicht. Fonts aus `/system/fonts` (Roboto, Noto Serif, Droid
Sans Mono). HarfBuzz ist nicht paketiert: kein Shaping, kein Subsetting.

---

## Offene Punkte

- **Symbolschriften unter Linux/macOS:** werden nicht gesubsettet — die ganze Schrift wird eingebettet, weil hb-subset die Glyphen-IDs hinter der `(3,0)`-Cmap nicht erhält. Windows subsettet sie (Roadmap R-15b)
- **TTC-Sammlungen:** nur Face-Index 0 ist erreichbar (Roadmap R-11)
- **EMF/MetaFile:** Windows-only (`TPdfDocumentGdi`), nicht portierbar
- **GDI+/Gradient Fills:** nur via EMF auf Windows verfügbar
- **Tabellen-Pagination:** kein Zeilenumbruch innerhalb einer Zelle
- **Delphi:** Delphi 7 und Delphi 2010 (Win32) bauen Ebene 1, die TCanvas-Brücke und den Kern von `TGDIPages`, alle sechs Konsolen-Demos und den Batch-Export der beiden GUI-Demos, noch nicht die Vorschau und die Demo-Fenster (Roadmap R-20). Die Zeichenmethoden von `TCanvas` sind unter Delphi 7 statisch: über eine `TPdfVclCanvas`-Referenz zeichnen (`Doc.VclCanvas` hat diesen Typ), nie über ein einfaches `TCanvas`, sonst kommt nichts im PDF an. Delphi 13 baut Ebene 1, die TCanvas-Brücke und den Kern von `TGDIPages` unter Win32 und Win64 (geprüft über `test_runner`, die Demos noch nicht; beides hängt an der Community, die Maintainer haben kein Delphi 13); unter Linux64 und Android64 nur Ebene 1 und die Backends — keine VCL, also keine TCanvas-Brücke, kein `TGDIPages` und keine `TBitmap`-Bilder (JPEG über `CreateJpegDirect`) (Roadmap R-27)
- **Links in getaggter Ausgabe:** `CreateHyperLink` in einem getaggten Dokument verletzt PDF/UA — es gibt kein `Link`-Strukturelement für Annotationen. `TGDIPages.DrawLink` bleibt konform, weil es nur formatierten Text zeichnet; seine URL ist nicht anklickbar (Roadmap R-18)

Details und aktueller Prüfstand: [docs/ROADMAP.md](docs/ROADMAP.md)

---

## Lizenz

Dieses Projekt folgt den Lizenzbedingungen von mORMot2. Siehe [mORMot2 Repository](https://github.com/synopse/mORMot2) für Details.
