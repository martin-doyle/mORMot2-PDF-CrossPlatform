# Examples -- mORMot2 PDF Cross-Platform

## Dateien

### pdf_demo_windows.dpr (Golden Master)
- **Compiler**: Delphi 7 (Windows-only)
- **Klasse**: `TPdfDocumentGDI` (Original-mORMot2-Pfad mit TMetaFile + TPdfEnum)
- **Ausgabe**: `output_golden_master.pdf` (130 KB, 3 Seiten)
- **Zweck**: Referenz-PDF, gegen das die Cross-Platform-Ausgabe verglichen wird
- **Aendern**: Nein -- diese Datei ist die unveraenderte Referenz

### pdf_demo_crossplat.lpr (Cross-Platform Demo)
- **Compiler**: FreePascal/Lazarus (Windows, Linux, macOS)
- **Klasse**: `TPdfDocumentVcl` (Recording Canvas ohne MetaFile)
- **Ausgabe**: `output_crossplat.pdf` (124 KB, 3 Seiten)
- **Zweck**: Beweist, dass der identische TCanvas-Code cross-platform funktioniert
- **Bedingte Kompilierung**: Nutzt `TPdfDocumentGDI` nur unter Delphi/Windows

### peekpdf.pas / peekpdf2.pas (Diagnose-Tools)
- Lesen ein PDF und geben die interne Objektstruktur auf der Konsole aus
- Nuetzlich zum Vergleich von Golden Master und Cross-Platform-Ausgabe
- `peekpdf2.pas` ist die erweiterte Version mit mehr Detail

## Demo-Inhalt (3 Seiten)

| Seite | Inhalt | Getestete Features |
|---|---|---|
| 1 | Fonts & Text | Helvetica, Times New Roman, Courier New; Groessen 9-24pt; Bold; Umlaute |
| 2 | Vektorgrafik | Gefuellte Rechtecke mit Rahmen, Linien (1/3/6px), Text + Bounding-Boxes |
| 3 | Tabelle | Header mit Farbe, 5 Datenzeilen, alternierende Zeilenfarben |

## Kompilierung

### Cross-Platform (FPC/Lazarus)
```bash
lazbuild pdf_demo_crossplat.lpi
# oder:
fpc -MObjFPC -dFPC pdf_demo_crossplat.lpr
```

### Windows Golden Master (Delphi 7)
```bash
dcc32 pdf_demo_windows.dpr
```

## Qualitaetskriterium
Das Cross-Platform-PDF muss visuell identisch mit dem Golden-Master-PDF sein.
Vergleich ueber: Dateigroesse, `peekpdf2` Strukturvergleich, visueller Abgleich.
