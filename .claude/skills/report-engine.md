# Report Engine — TGDIPages

Source: `src/core/mormot.ui.report.pas`

`TGDIPages` is a high-level layout engine for multi-page documents. All drawing commands are recorded as a `TDrawCommand` array; actual rendering to canvas or PDF only happens when `RenderPageToCanvas()` is called.

---

## Coordinate System

- Unit: **1/100 millimetre** (100 units = 1 mm)
- X=0: left page margin (content area)
- Y=0: top page margin (content area)
- `CurrentY` tracks the current write position
- `PageWidth`/`PageHeight`: content width/height in 1/100mm (excluding margins)

```
MarginTop
┌────────────────────────┐
│  Y=0                   │  PageHeight
│  CurrentY →            │
│                        │
└────────────────────────┘
MarginBottom
```

Millimetre conversion: `1500` = 15 mm. Example: `MarginLeft := 1500` sets a 15 mm left margin.

---

## Lifecycle

```pascal
Report := TGDIPages.Create(nil);
try
  // 1. Configuration
  Report.PaperSize  := psA4;
  Report.Orientation := poPortrait;
  Report.MarginLeft := 1500;  // 15mm
  Report.MarginRight := 1500;
  Report.MarginTop  := 2000;  // 20mm
  Report.MarginBottom := 2000;
  Report.UseOutlines := True;

  // 2. First page + content
  Report.NewPage;
  Report.SetFont('Helvetica', 11);
  Report.DrawHeading(1, 'Title');
  Report.DrawParagraph('Text...');

  // 3. Finalise document
  Report.EndDoc;

  // 4. Export / preview
  Report.ExportPdfStream(Stream);
  // or
  Report.ShowPreviewForm;
finally
  Report.Free;
end;
```

---

## Layout Methods

### Pages & Navigation

| Method/Property | Description |
|---|---|
| `NewPage` | Begin a new page |
| `ForceNewPage` | Force a new page (even when space remains) |
| `EndDoc` | Finalise document (must be called before export) |
| `CurrentY` | Current Y position (read-only) |
| `CurrentX` | Current X position (read/write) |
| `PageWidth` | Content width (read-only) |
| `PageHeight` | Content height (read-only) |
| `PageCount` | Number of pages (read-only) |
| `CurrentPageIndex` | Current page number (read-only) |
| `MoveToNextLine(Offset)` | Advance Y by Offset |
| `AddVerticalSpace(mm)` | Advance Y by mm millimetres |

### Font & Style

```pascal
Report.SetFont('Helvetica', 11);      // set font (active until next SetFont)
Report.FontStyle := [fsBold];         // fsBold, fsItalic, fsUnderline, fsStrikeOut
Report.TextColor := clNavy;           // text colour
Report.LineHeightFactor := 1.3;       // line spacing multiplier (default 1.1); R-8
```

`LineHeightFactor` scales the per-line vertical advance: `Round(FontTextHeight * LineHeightFactor)`. Default `1.1` (10% extra leading). Set to `1.3` or higher for more open layouts.

### Layout Stack

```pascal
Report.SaveLayout;    // save current font name/size/style + TextColor — NOT fCurrentY
try
  Report.SetFont('Arial', 8);
  Report.TextColor := clGray;
  Report.DrawText(0, 0, 'Footer text');
finally
  Report.RestoreLayout;  // restore saved font+color; fCurrentY is unchanged
end;
```

**What SaveLayout/RestoreLayout saves:** `fFontName`, `fFontSize`, `fFontStyle`, `fTextColor` — nothing else. `fCurrentY` is NOT saved/restored. Stack-based (unlimited depth).

### Headers and Footers

```pascal
// Call BEFORE NewPage so the text appears on all pages including page 1.
Report.SetHeader('Company Name   |   Report Title');  // {#} and {total} supported
Report.SetFooter('Created: ' + DateToStr(Now) + '   Page {#} of {total}');
```

- `{#}` = current page number (1-based); `{total}` = total page count
- Rendered in the **margin area** — vertically centred in `MarginTop` (header) and `MarginBottom` (footer)
- Does **not** advance `CurrentY`; the content area starts at Y=0 as normal
- Use `SetHeader`/`SetFooter` for per-page text; **do not** use manual `DrawText` commands for headers/footers — those commands are only recorded on the page where they are called and will not appear on continuation pages created by table pagination
- `SetHeader`/`SetFooter` must be called **before** `NewPage` to take effect on page 1

---

## Text Methods

| Method | Description |
|---|---|
| `DrawText(X,Y,S)` | Text at position X,Y |
| `DrawText(S)` | Text at CurrentX,CurrentY |
| `DrawTextAt(X,Y,S)` | Like DrawText(X,Y,S) — absolute position |
| `DrawTextRight(X,Y,S)` | Right-aligned; X=0 = page edge |
| `DrawTextCenter(X,Y,S)` | Centred; X=0 = page |
| `DrawTextWrapped(X,MaxW,Y,S)` | With word-wrap at MaxW |

### Semantic Elements

```pascal
Report.DrawHeading(1, 'Main Title');                    // H1 with PDF bookmark
Report.DrawHeading(2, 'Section');                       // H2
Report.DrawParagraph('Paragraph text...');              // flows, word-wraps
Report.DrawParagraph(X, MaxWidth, Y, 'Text');           // with explicit position
Report.DrawQuote('"Quote" — Author');                   // indented, italic
Report.DrawQuote(X, MaxWidth, Y, 'Quote');              // with explicit position
Report.DrawListItem(800, Y, 'Item');                    // with bullet, X=indent
Report.DrawListItem(800, Y, 'Item', '– ');              // custom prefix
Report.DrawCaption('Image caption');                    // small text below image/table
Report.DrawCaption(X, MaxWidth, Y, 'Caption');          // with explicit position

// Inline elements (X advances automatically with the no-coordinate overload):
Report.CurrentX := 0;
Report.DrawText('Normal ');
Report.DrawStrong('bold');             // bold inline text
Report.DrawText(' and ');
Report.DrawEm('italic');              // italic inline text
Report.DrawText(' text.');
Report.DrawCode('snippet');           // monospace inline text
Report.DrawLink('Link text', 'http://...'); // hyperlink text
Report.MoveToNextLine(800);

// Overloads with coordinates:
Report.DrawStrong(X, Y, 'bold');
Report.DrawEm(X, Y, 'italic');
Report.DrawCode(X, Y, 'code snippet');
Report.DrawLink(X, Y, 'Link text', 'http://...');
```

---

## Format Registry

All elements have named formats that can be customised via `DefineFormat`.

```pascal
type TReportFormat = record
  FontName:   string;       // '' = current document font
  FontSize:   Integer;      // 0 = proportional (e.g. 90% for Code)
  FontStyle:  TFontStyles;
  Color:      TColor;
  SpaceBefore: Integer;     // space before element (1/100mm)
  SpaceAfter:  Integer;     // space after element (1/100mm)
  HeaderBkColor:      TColor;  // table header background
  BodyBkColor:        TColor;  // table body background
  AlternateRowColor:  TColor;  // alternating row colour (0 = off)
end;
```

Predefined names: `H1`–`H6`, `P`, `Strong`, `Em`, `Code`, `Quote`, `LI`, `Caption`

```pascal
var Fmt: TReportFormat;
Fmt.FontName  := 'Times New Roman';
Fmt.FontSize  := 32;
Fmt.FontStyle := [fsBold];
Fmt.Color     := clNavy;
Fmt.SpaceBefore := 600;
Fmt.SpaceAfter  := 800;
Report.DefineFormat('H1', Fmt);

// Retrieve:
Fmt := Report.GetFormat('H1');
```

Default H1 size is 28pt; H2–H6 scale proportionally (75%, 57%, 46%, 39%, 36%).

---

## Tables

### Primary API — TTableLayout

```pascal
const TABLE_LAYOUT: TTableLayout = (
  ColumnWidths:      [2000, 6000, 2000];        // 1/100mm per column
  ColumnAligns:      [tcaLeft, tcaLeft, tcaRight]; // tcaLeft/Center/Right
  HeaderFontName:    '';       // '' = current document font
  HeaderFontSize:    0;        // 0 = current document font size
  HeaderFontStyle:   [fsBold];
  HeaderBkColor:     $E0E0E0;
  BodyFontName:      '';
  BodyFontSize:      0;
  BodyFontStyle:     [];
  BodyBkColor:       $FFFFFF;
  AlternateRowColor: $F5F5F5;  // 0 = no alternation
);

Report.BeginTable(TABLE_LAYOUT);
Report.DrawTableHeader(['Date', 'Description', 'Amount']);
Report.DrawTableRow(['2026-01-15', 'Consulting', '1,500.00']);
Report.DrawTableRow(['2026-01-16', 'License', '500.00']);
Report.EndTable;
```

**Internal lifecycle of BeginTable(TTableLayout):**
- `BeginTable(Layout)` calls `SaveLayout` internally — balanced by `EndTable` calling `RestoreLayout`. Set the document body font via `SetFont` **before** `BeginTable` so the save captures it.
- `DrawTableHeader` and `DrawTableRow` each call `SaveLayout`/`RestoreLayout` internally for their cell drawing.
- `CELL_PADDING = 200` (2 mm). Row/cell height = `LineHeightMM + CELL_PADDING`.
- `LineHeightMM` always calls `SetupMeasureFont` first (syncs `fMeasureBitmap.Canvas.Font` to `fFontName`/`fFontSize`/`fFontStyle`) — measurement is always current.
- Column loop in both `DrawTableHeader` and `DrawTableRow`: `for i := 0 to Min(High(Cells), High(fTableColWidths))`.
- `fTableColWidths`/`fTableColAligns` are populated from `Length(Layout.ColumnWidths)` / `Length(Layout.ColumnAligns)`. If `TTableLayout` typed constants have dynamic array fields that aren't properly initialized by the FPC version in use, `Length()` returns 0 and NO cells are drawn (not even the header). See note below.
- `AddCommand` raises an exception ("call NewPage before drawing") if `fCurrCmds = nil` — i.e. if `NewPage` was not called before any draw method, or after `EndDoc`.

**FPC typed constants with dynamic array fields:** `TTableLayout.ColumnWidths` and `ColumnAligns` are `array of Integer` / `array of TTableColumnAlign` (dynamic arrays). Initializing them via typed-constant syntax `(ColumnWidths: [1000, 2500, ...])` requires FPC ≥ 3.2. With FPC 3.0/3.1 the arrays may have `Length = 0`, making all table cells invisible. **Workaround for older FPC:** build the layout in a function or `initialization` block using `SetLength` + direct assignment instead of a typed constant.

### Legacy API — ColWidths / ColAligns Arrays

```pascal
// For code that predates TTableLayout:
Report.BeginTable([2000, 6000, 2000], [tcaLeft, tcaLeft, tcaRight]);
Report.AddTableRow(['Date', 'Description', 'Amount'], {IsHeader=}true);
Report.AddTableRow(['2026-01-15', 'Consulting', '1,500.00']);
Report.EndTable;
```

`AddTableRow(Cells, IsHeader)`: `IsHeader=true` renders with gray background.
Prefer `BeginTable(Layout)` + `DrawTableHeader` + `DrawTableRow` for new code.

**Automatic page break (R-9):** When a data row no longer fits, it moves to the next page and the column headers are automatically repeated at the top. Header content is saved internally when `DrawTableHeader` is called; `EndTable` clears the saved headers.

---

## Graphics Methods

```pascal
Report.DrawLine(X1, Y1, X2, Y2, Width, Color);   // line
Report.DrawFilledRect(X1, Y1, X2, Y2, Color);     // filled rectangle
Report.Columns2(Gap, Text1, Text2);               // two-column text
```

---

## Export & Preview

```pascal
// WYSIWYG preview (GUI):
Report.ShowPreviewForm;

// Print:
Report.PrintPages(0, Report.PageCount - 1);
Report.ShowPrintDialog;

// Open exported file in default PDF viewer:
Report.OpenPdfFile('output.pdf');   // calls xdg-open / open / ShellExecute

// Export PDF:
Report.ExportPdfStream(AStream): boolean;
Report.ExportPDF(FileName, UsePassword, Encrypt, Title, Author);

// PDF export configuration:
Report.ExportPdfEmbeddedTTF    := True;      // embed TrueType fonts
Report.ExportPdfStandardFonts  := False;     // use Type1 instead of TTF
Report.ExportPdfLevel          := pdfA1B;    // PDF/A conformance level
Report.ExportPdfFileFormat     := pdf17;     // PDF version header (default: pdf13)
Report.ExportPdfAuthor         := 'Company';
Report.ExportPdfSubject        := 'Report';
Report.Title   := 'Document title';
Report.Author  := 'Author name';
Report.Subject := 'Subject';
```

### Font Selection for Export

```pascal
var SansFont, SerifFont, MonoFont: string;
Report.ExportPdfEmbeddedTTF := True;
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
// Windows: Calibri, Cambria, Consolas
// macOS:   Trebuchet MS, Georgia, Andale Mono
// Linux:   Liberation Sans, Liberation Serif, Liberation Mono
```

---

## Rendering

```pascal
// Render one page to an arbitrary canvas (used internally by preview and PDF export):
Report.RenderPageToCanvas(
  ACanvas,      // target TCanvas (must be valid)
  PageIndex,    // 0-based page number (must be < PageCount)
  DestWidth,    // rendering area width in pixels (including margins)
  DestHeight,   // rendering area height in pixels (including margins)
  SourceDPI     // optional DPI (0 = Screen.PixelsPerInch; use 96 for PDF export)
);
```

**Font scaling (zoom):** `RenderPageToCanvas` computes `FontScale = DestHeight / BaseHeight`
where `BaseHeight = MMToPixels(totalPageHeight, SourceDPI or ACanvas.Font.PixelsPerInch)`.
All text commands apply `Font.Size := Round(storedSize * FontScale)`. In the preview,
`DestHeight = fPreviewH * fPreviewZoom`, so `FontScale = fPreviewZoom` — fonts scale
proportionally with zoom. For PDF export (`SourceDPI = PDF.ScreenLogPixels`),
`FontScale = 1.0` always.

Important: `RenderPageToCanvas` uses `ACanvas.Rectangle()` instead of `FillRect()`, because `FillRect` does not trigger brush synchronisation in `TPdfVclCanvas`.

---

## Global Helper Functions

```pascal
// Convert 1/100-mm to pixels at the given DPI:
function MMToPixels(Value100: Integer; DPI: Integer): Integer;

// Convert pixels to 1/100-mm at the given DPI:
function PixelsToMM(Pixels: Integer; DPI: Integer): Integer;

// Get platform-default font names:
procedure GetReportFonts(Embedded: boolean;
  out SansFont, SerifFont, MonoFont: string);
```

---

## Internal Types (useful for extensions)

### TDrawCmdKind

```pascal
TDrawCmdKind = (
  dckDrawText, dckDrawLine, dckDrawRect, dckFillRect,
  dckDrawBitmap, dckClip, dckRestoreClip,
  dckBeginTable, dckTableRow, dckEndTable, dckHeading,
  dckBeginTR,   // begin table row — Color<>0 = header row (R-5/R-6)
  dckEndTR);    // end table row
```

`dckBeginTR.Color = 1` → header row (→ `psrTH` cells); `Color = 0` → data row (→ `psrTD` cells).

### TDrawCommand

Each recorded drawing operation:

```pascal
TDrawCommand = record
  Kind:         TDrawCmdKind;
  X, Y, X2, Y2: Integer;      // coordinates in 1/100mm
  FontName:     string;
  FontSize:     Integer;
  FontStyle:    TFontStyles;
  Color:        TColor;
  BkColor:      TColor;
  Text:         string;
  TextWidthMM:  Integer;
  BitmapIndex:  Integer;
  LineWidth:    Integer;
  Align:        Integer;
  FormatName:   string;        // name in format registry (H1, P, etc.)
  HeadingLevel: Integer;
  HeadingTitle: string;
  BlockId:      Integer;       // logical block: 0 = standalone, >0 = shared by
                               // all lines of one wrapped paragraph (B-2)
                               // or by all runs of one inline line (B-3)
  IsInline:     boolean;       // true = inline run continuing the current line
  InlineStyle:  TInlineStyle;  // isPlain, isStrong, isEm, isCode, isLink
end;
```

**BlockId (Tagged PDF).** `RecordWrappedText` — and therefore every wrapping
entry point (`DrawTextWrapped`, `DrawParagraph`, `DrawQuote`, `Columns2`,
`DrawListItem`) — stamps one fresh id onto all lines it emits. During tagged
export `RenderPageToCanvas` opens **one** struct element per block and keeps its
marked-content region open across the lines, so a wrapped paragraph is a single
`P`, not one `P` per line. Cell text and inline runs keep `BlockId = 0`
(standalone). A block interrupted by a page break is reopened on the next page
via `TPdfDocumentVcl.ResumeStructContent`, so it stays one element with one MCID
per page.

**Inline runs (Tagged PDF).** The coordinate-less overloads (`DrawText`,
`DrawStrong`, `DrawEm`, `DrawCode`, `DrawLink`) advance `CurrentX` on the
current line. They all stamp one shared `BlockId` and `IsInline = true`, so the
tagged export emits **one** `P` (or `TD`/`LBody`/`Hx`) for the whole line: a
plain run adds a region to that element, a styled run becomes a nested `Span`
(`ROADMAP B-3`). The line ends — and the next one gets a fresh id — at
`MoveToNextLine`, at `NewPage`, and at any wrapping entry point
(`RecordWrappedText`). The coordinate overloads (`DrawStrong(X, Y, …)`) stay
standalone blocks.

New features: record the command first, implement rendering in `RenderPageToCanvas()`.

### TPageData

```pascal
TPageData = record
  Commands:    TDrawCommandList;  // all commands on this page
  PageWidth:   Integer;           // content width in 1/100mm
  PageHeight:  Integer;           // content height in 1/100mm
  MarginLeft, MarginRight, MarginTop, MarginBottom: Integer;
end;
```

Access via `Report.Pages[PageIndex]` (0-based, read-only).

---

## Command Recording Flow

```
DrawHeading / DrawParagraph / DrawText
    ↓ EmitTextCmd / AddCommand
    ↓ TDrawCommand array (one list per page)

ShowPreviewForm / ExportPdfStream
    ↓ RenderPageToCanvas(ACanvas, PageIndex, DestWidth, DestHeight)
    ↓ iterates TDrawCommand[]
    ↓ ACanvas.TextOut / ACanvas.Rectangle / ...
        ↓ (on PDF export: TPdfVclCanvas -> TPdfCanvas -> PDF stream)
```
