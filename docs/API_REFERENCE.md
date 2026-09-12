# API Reference

## TPdfDocumentVcl — TCanvas Methods

Coordinates in pixels, origin top-left. Requires LCL.

### Text

| Method | Description |
|---|---|
| `C.TextOut(X, Y, S)` | Output text (Unicode supported) |
| `C.TextWidth(S)` | Measure text width in pixels |
| `C.TextHeight(S)` | Measure text height in pixels |

### Font Properties

| Property | Values |
|---|---|
| `C.Font.Name` | e.g. `'Helvetica'`, `'Times New Roman'`, `'Calibri'` |
| `C.Font.Size` | Point size (10, 12, 24, ...) |
| `C.Font.Style` | `[]`, `[fsBold]`, `[fsItalic]`, `[fsBold, fsItalic]`, `[fsUnderline]`, `[fsStrikeOut]` |
| `C.Font.Color` | `clBlack`, `clRed`, `$800000`, ... |

### Shapes

| Method | Description |
|---|---|
| `C.Rectangle(X1, Y1, X2, Y2)` | Rectangle with pen and brush |
| `C.Ellipse(X1, Y1, X2, Y2)` | Ellipse with pen and brush |
| `C.RoundRect(X1, Y1, X2, Y2, RX, RY)` | Rounded rectangle |
| `C.FillRect(Rect)` | Fill rectangle only (no border) |

### Lines & Polygons

| Method | Description |
|---|---|
| `C.MoveTo(X, Y)` | Set cursor position |
| `C.LineTo(X, Y)` | Line from cursor to (X,Y) |
| `C.Polyline(Points)` | Open polyline |
| `C.Polygon(Points)` | Closed, filled polygon |

### Bitmaps

| Method | Description |
|---|---|
| `C.Draw(X, Y, Graphic)` | Bitmap at original size |
| `C.StretchDraw(Rect, Graphic)` | Bitmap scaled to target rectangle |

### Pen & Brush

| Property | Values |
|---|---|
| `C.Pen.Color` | TColor value |
| `C.Pen.Width` | Line width in pixels (1, 2, 3, ...) |
| `C.Pen.Style` | `psSolid`, `psClear` |
| `C.Brush.Color` | TColor value |
| `C.Brush.Style` | `bsSolid`, `bsClear` |

---

## TPdfDocumentVcl — Tagged PDF and Transparency

Available on `TPdfDocumentVcl` (delegates to `TPdfCanvas`):

```pascal
// Tagged PDF accessibility marks — no-op when Tagged = false
Doc.BeginStructContent(psrH1);           // open a structure element
Doc.EndStructContent;                    // close it
Doc.BeginStructContent(psrFigure, 'Company logo');  // /Alt text for figures

// Transparency (PDF 1.4+)
Doc.SetFillAlpha(0.5);    // fill opacity 0..1
Doc.SetStrokeAlpha(0.8);  // stroke opacity 0..1
```

---

## TPdfDocument — Key Properties

| Property | Type | Description |
|---|---|---|
| `DefaultPaperSize` | `TPdfPaperSize` | psA4, psLetter, psA3, psA5, psA6, psB4, psB5 |
| `DefaultPageLandscape` | boolean | Landscape orientation |
| `EmbeddedTtf` | boolean | Embed TrueType fonts |
| `StandardFontsReplace` | boolean | Use Type1 fonts instead of TTF |
| `PdfA` | `TPdfALevel` | pdfNone, pdfA1A, pdfA1B, pdfA2A, pdfA2B, pdfA3A, pdfA3B |
| `FileFormat` | `TPdfFileFormat` | pdf13 (default) … pdf17; auto-raised by PdfA / Tagged |
| `Tagged` | boolean | Enable Tagged PDF (ISO 32000-1 §14); auto-raises `FileFormat` to pdf17 |
| `DefaultLanguage` | string | BCP-47 language tag for `/Lang` (default `'en'`) |
| `Info.Title` | string | PDF metadata |
| `Info.Author` | string | PDF metadata |
| `Info.Subject` | string | PDF metadata |
| `Info.Keywords` | string | PDF metadata |

---

## PDF Encryption

Requires compile-time flag `USE_PDFSECURITY` (enabled by default).

```pascal
uses mormot.ui.pdf;

var Enc: TPdfEncryption;
Enc := TPdfEncryption.New(
  elAES_128,              // elRC4_40 / elRC4_128 / elAES_128
  '',                     // user password ('' = no open-doc password)
  'owner-secret',         // owner password (must be non-empty)
  PDF_PERMISSION_NOMODIF  // permissions set
);
Doc := TPdfDocument.Create(false, 0, pdfaNone, Enc);
// — or via TPdfDocumentVcl:
Doc := TPdfDocumentVcl.Create(false, 0, pdfaNone, Enc);
```

| Level | PDF version | Algorithm |
|---|---|---|
| `elRC4_40` | 1.3+ | RC4-40 + MD5 |
| `elRC4_128` | 1.4+ | RC4-128 + MD5 |
| `elAES_128` | 1.6+ | AES-128-CBC + MD5; 16-byte random IV per object |

Predefined permission sets:

| Constant | Meaning |
|---|---|
| `PDF_PERMISSION_ALL` | All permissions granted |
| `PDF_PERMISSION_NOMODIF` | No modification, no annotation |
| `PDF_PERSMISSION_NOPRINT` | No printing |
| `PDF_PERMISSION_NOCOPY` | No content copy |
| `PDF_PERMISSION_NOCOPYNORPRINT` | No copy and no print |

---

## Tagged PDF (ISO 32000-1 §14 — Accessibility)

Structure roles defined in `mormot.pdf.types.pas`:

```pascal
TPdfStructRole = (
  psrDocument,                                    // root (implicit)
  psrH1, psrH2, psrH3, psrH4, psrH5, psrH6,    // headings
  psrP,                                           // paragraph
  psrSpan,                                        // inline span
  psrFigure,                                      // image / graphic
  psrTable, psrTR, psrTH, psrTD);                // table structure
```

Low-level usage via `TPdfCanvas` or `TPdfDocumentVcl`:

```pascal
Doc.Tagged := True;                // must be set before AddPage
Doc.DefaultLanguage := 'en-US';   // BCP-47

Doc.AddPage;

Doc.BeginStructContent(psrH1);
C.TextOut(40, 40, 'Main Title');
Doc.EndStructContent;

Doc.BeginStructContent(psrFigure, 'Chart: Q1 revenue');  // /Alt for screen readers
C.StretchDraw(Rect(...), Bitmap);
Doc.EndStructContent;

Doc.BeginStructContent(psrTable);
  Doc.BeginStructContent(psrTR);
    Doc.BeginStructContent(psrTH); C.TextOut(..., 'Date');   Doc.EndStructContent;
    Doc.BeginStructContent(psrTH); C.TextOut(..., 'Amount'); Doc.EndStructContent;
  Doc.EndStructContent;
  Doc.BeginStructContent(psrTR);
    Doc.BeginStructContent(psrTD); C.TextOut(..., '2026-01'); Doc.EndStructContent;
    Doc.BeginStructContent(psrTD); C.TextOut(..., '1,500');   Doc.EndStructContent;
  Doc.EndStructContent;
Doc.EndStructContent;
```

High-level via `TGDIPages` (automatic tagging):

```pascal
Report.ExportPdfTagged   := True;   // wraps all drawing commands automatically
Report.ExportPdfLanguage := 'en';
Report.ExportPdfStream(Stream);
```

`RenderPageToCanvas` wraps each command: headings → `psrH1..H6`, paragraphs → `psrP`, bitmaps → `psrFigure`, table structure → `psrTable / psrTR / psrTH / psrTD`.

---

## TGDIPages — Format System

### TReportFormat Record

```pascal
TReportFormat = record
  FontName:         string;    // '' = inherit current document font
  FontSize:         Integer;   // 0 = proportional to current font
  FontStyle:        TFontStyles;
  Color:            TColor;
  SpaceBefore:      Integer;   // space before element (1/100mm)
  SpaceAfter:       Integer;   // space after element (1/100mm)
  HeaderBkColor:    TColor;    // table header background
  BodyBkColor:      TColor;    // table body background
  AlternateRowColor: TColor;   // alternating row colour (0 = off)
end;
```

### Predefined Format Names

| Name | Usage | Default size | Default spacing |
|---|---|---|---|
| `H1` | Main heading | 28pt, bold | 600 before, 800 after |
| `H2` | Section heading | 75% of H1 | 400 before, 600 after |
| `H3` | Sub-heading | 57% of H1 | 300 before, 400 after |
| `H4` | Detail heading | 46% of H1 | 200 before, 200 after |
| `H5` | Minor heading | 39% of H1 | 100 before, 200 after |
| `H6` | Smallest heading | 36% of H1 | 100 before, 100 after |
| `P` | Paragraph | body font | 0 before, 300 after |
| `Strong` | Bold inline | body font, bold | 0 before/after |
| `Em` | Italic inline | body font, italic | 0 before/after |
| `Code` | Monospace inline | 90% mono font, dark red | 0 before/after |
| `Quote` | Block quote | body font, italic, grey | 200 before, 300 after |
| `LI` | List item | body font | 0 before, 100 after |
| `Caption` | Image caption | 80% body font | 200 before, 0 after |

---

## TGDIPages — Additional Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `LineHeightFactor` | `single` | `1.1` | Line-height multiplier applied to `FontTextHeight`; raise to e.g. `1.3` for more open layouts |
| `ExportPdfTagged` | boolean | `false` | Wrap all drawing commands in Tagged PDF struct elements on export |
| `ExportPdfLanguage` | string | `'en'` | BCP-47 language tag written to `/Lang` when `ExportPdfTagged = true` |

---

## TTableLayout Record

```pascal
TTableLayout = record
  ColumnWidths:      array of Integer;           // 1/100mm per column
  ColumnAligns:      array of TTableColumnAlign;  // tcaLeft, tcaCenter, tcaRight
  HeaderFontName:    string;   // '' = current document font
  HeaderFontSize:    Integer;  // 0 = current font size
  HeaderFontStyle:   TFontStyles;
  HeaderBkColor:     TColor;
  BodyFontName:      string;
  BodyFontSize:      Integer;
  BodyFontStyle:     TFontStyles;
  BodyBkColor:       TColor;
  AlternateRowColor: TColor;   // 0 = no alternation
end;
```

Empty `FontName` and `FontSize = 0` inherit the current document font. The table automatically picks up the font set by `Report.SetFont()`.

**Automatic header repetition (R-9):** `DrawTableHeader` saves the column headers. When `DrawTableRow` triggers a page break, the headers are automatically re-drawn at the top of the continuation page. `EndTable` clears the saved headers.

---

## Spacing Units

All spacing and position values in `TGDIPages` use **1/100 millimetre**:

| Value | Equals |
|---|---|
| 100 | 1 mm |
| 500 | 5 mm |
| 1000 | 10 mm = 1 cm |
| 1500 | 15 mm |
| 2000 | 20 mm = 2 cm |
| 2540 | 25.4 mm = 1 inch |

---

## Font Selection Helper

### GetReportFonts (free procedure)

```pascal
procedure GetReportFonts(Embedded: boolean;
  out SansFont, SerifFont, MonoFont: string);
```

`Embedded = True` → platform-specific TTF fonts:

| Platform | SansFont | SerifFont | MonoFont |
|---|---|---|---|
| Windows | Calibri | Cambria | Consolas |
| macOS | Trebuchet MS | Georgia | Andale Mono |
| Linux | Liberation Sans | Liberation Serif | Liberation Mono |

`Embedded = False` → PDF standard fonts (all platforms): Helvetica, Times, Courier

### TGDIPages.GetExportFonts (wrapper)

```pascal
procedure TGDIPages.GetExportFonts(out SansFont, SerifFont, MonoFont: string);
```

Reads `ExportPdfEmbeddedTTF` internally and delegates to `GetReportFonts`. No parameter needed.

---

## Standard Font Constants

Defined in `mormot.pdf.types.pas`:

```pascal
PDF_FONT_STD_SANS  = 'Helvetica';
PDF_FONT_STD_SERIF = 'Times';
PDF_FONT_STD_MONO  = 'Courier';
```

Platform-specific TTF constants in `mormot.ui.report.pas`:

```pascal
REPORT_FONT_SANS  = 'Calibri';        // Windows
                  = 'Trebuchet MS';   // macOS
                  = 'Liberation Sans'; // Linux

REPORT_FONT_SERIF = 'Cambria';        // Windows
                  = 'Georgia';        // macOS
                  = 'Liberation Serif'; // Linux

REPORT_FONT_MONO  = 'Consolas';       // Windows
                  = 'Andale Mono';    // macOS
                  = 'Liberation Mono'; // Linux
```
