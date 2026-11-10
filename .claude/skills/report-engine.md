# Report Engine — TGDIPages

Source: `src/pdf/mormot.pdf.report.pas`, preview and printing in `src/pdf/mormot.pdf.report.preview.pas`

`TGDIPages` is a high-level layout engine for multi-page documents. All drawing commands are recorded as a `TDrawCommand` array; actual rendering to canvas or PDF only happens when `RenderPageToCanvas()` is called.

**Strings:** all text, font and format names are `RawUtf8` — parameters, records, `TDrawCommand`, the format registry; file names are `TFileName`. Conversion happens only at the boundaries: `Utf8ToString` for LCL fonts, captions, the preview's `TextOut` and layer 1's `string` API (`Info.*`, `CreateOutline`, `GetPdfFonts`); the PDF bridge gets `TextOutUtf8`. Words are split with `CsvToRawUtf8DynArray` at spaces only, so a `"` in the text stays text — `TStringList.DelimitedText` would take it as a quote and drop it.

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
  ShowReportPreview(Report);   // mormot.pdf.report.preview
finally
  Report.Free;
end;
```

**Defaults of `TGDIPages.Create`:** A4 portrait, margins 2000 (20 mm) on
each side, `REPORT_FONT_SANS` at 10 pt, black text, `LineHeightFactor` 1.1,
`UseOutlines` false, `ExportPdfEmbeddedTTF` true, `ExportPdfStandardFonts`
true (Arial, Times New Roman and Courier New are written as the
unembedded Helvetica, Times and Courier unless it is set false before the
first `NewPage`; `ExportPdfTagged` sets it false), `ExportPdfTagged` false,
`ExportPdfLanguage` `'en'`, `ExportPdfFileFormat` `pdf13`,
`ExportPdfLevel` `pdfaNone`, `ExportPdfPageMode` `pmUseNone`.

`PaperSize` and `Orientation` take effect at the next `NewPage`; each page
keeps the size and margins it was created with (`TPageData`).

---

## Layout Methods

### Pages & Navigation

| Method/Property | Description |
|---|---|
| `NewPage` | Begin a new page - always, there is no check for content; `CurrentX`/`CurrentY` back to 0 |
| `ForceNewPage` | the same as `NewPage` (it sets Y to the top again) |
| `EndDoc` | Finalise document: closes an open list, then any further drawing raises; call it before export |
| `CurrentY` | Current Y position (read-only) |
| `CurrentX` | Current X position (read/write) |
| `PageWidth` | Content width (read-only) |
| `PageHeight` | Content height (read-only) |
| `PageCount` | Number of pages (read-only) |
| `CurrentPageIndex` | 1-based number of the current page, the same as `PageCount`; 0 before the first `NewPage` (read-only) |
| `MoveToNextLine(Offset)` | Advance Y by Offset (1/100 mm); ends the current inline line |
| `AddVerticalSpace(mm)` | Advance Y by mm millimetres (`mm * 100` units) |

### Font & Style

```pascal
Report.SetFont('Helvetica', 11);      // set font (active until next SetFont)
Report.FontStyle := [fsBold];         // fsBold, fsItalic, fsUnderline, fsStrikeOut
Report.TextColor := clNavy;           // text colour
Report.LineHeightFactor := 1.3;       // line spacing multiplier (default 1.1)
```

`LineHeightFactor` scales the per-line vertical advance: `FontSize * LineHeightFactor`, in PDF points. Default `1.1`. The advance does not depend on the face's own metrics, so it is the same on every platform — and a face whose ascender+descender exceeds 1.1 em needs a larger factor. Set `1.3` or higher for more open layouts.

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

**What SaveLayout/RestoreLayout saves:** `fFontName`, `fFontSize`, `fFontStyle`, `fTextColor` — nothing else. `fCurrentY` is NOT saved/restored. Stack-based (unlimited depth); `RestoreLayout` on an empty stack does nothing.

### Headers and Footers

```pascal
Report.SetHeader('Company Name   |   Report Title');  // {#} and {total} supported
Report.SetFooter('Created: ' + DateToStr(Now) + '   Page {#} of {total}');
```

- `{#}` = current page number (1-based); `{total}` = total page count. Both are also replaced in every recorded text and heading
- One header and one footer for the whole document: `SetHeader`/`SetFooter` store the text, and `RenderPageToCanvas` draws it on every page, so the last call before export wins, wherever it was made
- Drawn with the document font, style and `TextColor` as they are at render time — the state the recording left them in, not the state at the `SetHeader` call
- Rendered in the **margin area**, left-aligned at the left margin — vertically centred in `MarginTop` (header) and `MarginBottom` (footer)
- Does **not** advance `CurrentY`; the content area starts at Y=0 as normal
- Use `SetHeader`/`SetFooter` for per-page text; **do not** use manual `DrawText` commands for headers/footers — those commands are only recorded on the page where they are called and will not appear on continuation pages created by table pagination

---

## Text Methods

| Method | Description |
|---|---|
| `DrawText(X,Y,S)` | Text at position X,Y |
| `DrawText(S)` | Inline text at CurrentX,CurrentY; advances `CurrentX`, starts a new page first if the line does not fit |
| `DrawTextAt(X,Y,S)` | The same as `DrawText(X,Y,S)` |
| `DrawTextRight(X,Y,S)` | Right-aligned: the text ends at X; X=0 = right edge of the printable area |
| `DrawTextCenter(X,Y,S)` | Centred on X; X=0 = centred on the printable width |
| `DrawTextWrapped(X,MaxW,Y,S)` | With word-wrap at MaxW; breaks pages; `CurrentY` ends below the text |

### Semantic Elements

```pascal
Report.DrawHeading(1, 'Main Title');                    // H1 with PDF bookmark
Report.DrawHeading(2, 'Section');                       // H2
Report.DrawParagraph('Paragraph text...');              // flows, word-wraps
Report.DrawParagraph(X, MaxWidth, Y, 'Text');           // with explicit position
Report.DrawQuote('"Quote" — Author');                   // indented 10 mm, italic grey
Report.DrawQuote(X, MaxWidth, Y, 'Quote');              // with explicit position
Report.DrawListItem(800, Report.CurrentY, 'Item');      // with bullet, X=indent
Report.DrawListItem(800, Report.CurrentY, 'Item', '– '); // custom prefix
Report.DrawCaption('Image caption');                    // small text below image/table
Report.DrawCaption(X, MaxWidth, Y, 'Caption');          // with explicit position

// Inline elements (X advances automatically with the no-coordinate overload):
Report.CurrentX := 0;
Report.DrawText('Normal ');
Report.DrawStrong('bold');             // current font + fsBold
Report.DrawText(' and ');
Report.DrawEm('italic');               // current font + fsItalic
Report.DrawText(' text.');
Report.DrawCode('snippet');            // the Code format's font and colour
Report.DrawLink('Link text', 'http://...'); // blue, underlined; the target is not used
Report.MoveToNextLine(800);

// Overloads with coordinates:
Report.DrawStrong(X, Y, 'bold');
Report.DrawEm(X, Y, 'italic');
Report.DrawCode(X, Y, 'code snippet');
Report.DrawLink(X, Y, 'Link text', 'http://...');
```

- `DrawHeading` raises `EPdfReport` for a level outside 1..6 or an empty
  title. It starts a new page when the heading line does not fit, records
  the heading for the outline, wraps the title and advances by a third of
  the font size.
- `DrawListItem` draws at the Y passed and then advances `CurrentY` by one
  line of the LI font plus `SpaceAfter`: pass `CurrentY`. Consecutive items
  share one list (`L`, each item an `LI`); any other command, `NewPage` or
  `EndDoc` closes it.
- `DrawLink` writes no link annotation: a tagged export has no `Link` role
  yet, so the text is a `Span` and the URL is dropped (R-29).

---

## Format Registry

All elements have named formats that can be customised via `DefineFormat`.

```pascal
type TReportFormat = record
  FontName:    RawUtf8;     // face name
  FontSize:    Integer;     // points; 0 = proportional (Code: 90% of the current size)
  FontStyle:   TFontStyles;
  Color:       TColor;
  SpaceAfter:  Integer;     // space after element (1/100mm)
  SpaceBefore: Integer;     // space before element (1/100mm)
end;
```

Predefined names: `H1`–`H6`, `P`, `Strong`, `Em`, `Code`, `Link`, `Quote`,
`LI`, `TableHeader`, `TableCell`, `TableCellAlt`, `Caption`. `GetFormat`
of an unknown name returns `REPORT_FONT_SANS` 11 pt, black, no spacing.

Which formats are read:

| Format | Read by | Fields used |
|---|---|---|
| `H1`–`H6` | `DrawHeading` (recording and rendering) | font name, size, style, colour; not the spacing |
| `P`, `Quote`, `Caption` | `DrawParagraph`, `DrawQuote`, `DrawCaption` | font, size, style, colour, `SpaceAfter` |
| `LI` | `DrawListItem` | font, size, style, colour, `SpaceAfter` |
| `Code` | `DrawCode` | font name, size (0 = 90% of the current size), colour; the style stays the current one |
| `Strong`, `Em`, `Link`, `TableHeader`, `TableCell`, `TableCellAlt` | nothing: `DrawStrong`/`DrawEm` add a style to the current font, `DrawLink` draws blue and underlined, tables take `TTableLayout` | — |

`SpaceBefore` of `P`, `Quote`, `Caption` and `LI` does not move the text:
it is added to `CurrentY`, but the text is drawn at the Y passed (the
overloads without coordinates pass `CurrentY` before the space is added).
The wrapped elements then set `CurrentY` below the text, which drops it;
`DrawListItem` keeps it, so it lands below the item.
`DrawHeading` adds a third of the font size after the heading, and nothing
before. `PT_TO_100MM` yields 1/10 mm where 1/100 mm is meant, so that third
is 0.33 mm after an H1 of 28 pt. The fix of all of it is decided, not done:
ROADMAP R-29 item 4.

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

Default H1 size is 28pt; H2–H6 scale proportionally (75%, 57%, 46%, 39%, 36%: 21, 16, 13, 11, 10 pt).

---

## Measurement — PDF metrics, not the LCL

Layout is measured with the font engine that will later place the glyphs, not with an LCL `TCanvas` (`mormot.pdf.TPdfFontMeasurer`):

| Quantity | Source |
|---|---|
| Text width | `TPdfFontMeasurer.TextWidth` — base-14 AFM tables when `ExportPdfStandardFonts` is set and the font is Helvetica/Times/Courier or Arial/Times New Roman/Courier New, otherwise `IFontFace.GetCharAbcWidths` of a 1000-per-em face |
| Line height | `FontSize * LineHeightFactor`, in PDF points |
| Fallback | `fMeasureBitmap.Canvas` — only for a face the PDF engine has no metrics for |

Consequences for callers:

- `ExportPdfStandardFonts` / `ExportPdfEmbeddedTTF` decide **which font the layout is measured with**, so set them before drawing, not just before export.
- Line breaking accumulates widths as unrounded PDF points and rounds once, when emitting a line — do not reintroduce per-word `PixelsToMM`/`MMToPixels` round-trips.
- `RenderPageToCanvas` places text via `TPdfVclCanvas.TextOutUtf8` (single coordinates, the UTF-8 form of `TextOutFrac`) when the target is the PDF bridge, keeping sub-pixel positions; the preview uses the integer `TCanvas.TextOut`. The preview may therefore differ slightly from the PDF — by design.

---

## Tables

### Primary API — TTableLayout

```pascal
// built in a function, as every demo does: Delphi 7 and 2010 have no typed
// constants with dynamic array fields
function TableLayout: TTableLayout;
begin
  Finalize(result);
  FillChar(result, SizeOf(result), 0);   // every field 0/''/[], as in a typed constant
  SetLength(result.ColumnWidths, 3);     // 1/100mm per column
  result.ColumnWidths[0] := 2000;
  result.ColumnWidths[1] := 6000;
  result.ColumnWidths[2] := 2000;
  SetLength(result.ColumnAligns, 3);     // tcaLeft/Center/Right; missing ones are tcaLeft
  result.ColumnAligns[0] := tcaLeft;
  result.ColumnAligns[1] := tcaLeft;
  result.ColumnAligns[2] := tcaRight;
  result.HeaderFontStyle   := [fsBold];  // name '' and size 0: the current font
  result.HeaderBkColor     := $E0E0E0;
  result.BodyBkColor       := $FFFFFF;
  result.AlternateRowColor := $F5F5F5;   // 0 = no alternation
  { leaving all four Footer* fields at '' / 0 / [] / 0 makes the row drawn by
    DrawTableFooter look exactly like the header row }
  result.GridColor := clSilver;          // cell borders; 0 = clBlack
  result.FooterRowHeader := false;       // true: first footer cell is a row header (TH /Scope /Row)
end;

Report.BeginTable(TableLayout);
Report.DrawTableHeader(['Date', 'Description', 'Amount']);
Report.DrawTableRow(['2026-01-15', 'Consulting', '1,500.00']);
Report.DrawTableRow(['2026-01-16', 'License', '500.00']);
Report.DrawTableFooter(['', 'Total', '2,000.00']);   // optional closing row
Report.EndTable;
```

FPC 3.2 also takes the layout as a typed constant
(`ColumnWidths: [2000, 6000, 2000]`); older FPC may leave such dynamic array
fields at `Length = 0`, and then no cell is drawn, not even the header.

**Fonts of a row.** The `Header*`, `Body*` and `Footer*` font fields
inherit each alone (`ApplyRowFont`): an empty `FontName` takes the current
font name, a `FontSize` of 0 the current size, and the `FontStyle` field
always applies. With both inherited only the style changes and the current
metrics stay. A row is as high as its own font size (`DrawTableRow` works
it out before setting the font, so that a header repeated at a page break
still takes the page font). Cell text is always black.

**Row groups.** A tagged export wraps the rows in the three group
elements of ISO 32000-1 14.8.4.3.4: `Table > THead | TBody | TFoot > TR >
TH|TD`. The group follows from the row kind, so nothing has to be declared:
`DrawTableHeader` opens `THead`, the first `DrawTableRow` switches to `TBody`,
`DrawTableFooter` switches to `TFoot`, and `EndTable` closes both the open
group and the table. A repeated header on a continuation page is an artifact
and leaves the open `TBody` alone.

**`GridColor`** colours all cell borders (`dckDrawRect`), header, data and
footer rows alike; 0 is `clBlack`, so an unset field draws black borders.
The width is `LineWidth = 1`: pixels at 96 dpi, clamped to at least 1 when
rendered — the bridge takes integer pen widths, so 0.75 pt is the thinnest
border. The legacy `AddTableRow` always draws black.

**`DrawTableFooter(Cells)`** draws the closing row — a totals line, typically.
Its cells are `TD`, not `TH` — unless `TTableLayout.FooterRowHeader` is set:
then its first cell is a row header (`psrTHRow`, `/S /TH` with `/Scope /Row`),
so a screen reader announces the label with the amount. `EmitTextCmd` marks
the cell through `fEmitRowHeader` → `TDrawCommand.RowHeader`, which
`TextStructRole` reads. It breaks the page like `DrawTableRow` does, with
the header repeated, so the footer is never orphaned on a page of its own.

**Internal lifecycle of BeginTable(TTableLayout):**
- `BeginTable(Layout)` calls `SaveLayout` internally — balanced by `EndTable` calling `RestoreLayout`. Set the document body font via `SetFont` **before** `BeginTable` so the save captures it.
- `BeginTable` raises `EPdfReport` while a table is open; `DrawTableHeader`, `DrawTableRow`, `DrawTableFooter`, `AddTableRow` and `EndTable` raise without one.
- `DrawTableHeader`, `DrawTableRow` and `DrawTableFooter` each call `SaveLayout`/`RestoreLayout` internally for their cell drawing.
- `CELL_PADDING = 200` (2 mm). Row/cell height = `LineHeightMM + CELL_PADDING`.
- `LineHeightMM` is `FontSize * LineHeightFactor` converted to 1/100 mm — no canvas involved, identical on every platform.
- Column loop in every row method: `for i := 0 to Min(High(Cells), High(fTableColWidths))` — extra cells are dropped, missing ones leave their columns empty.
- `fTableColWidths`/`fTableColAligns` are populated from `Length(Layout.ColumnWidths)` / `Length(Layout.ColumnAligns)`: an empty `ColumnWidths` draws no cell at all.
- `AddCommand` raises `EPdfReport` ("call NewPage before drawing") if `fCurrCmds = nil` — i.e. if `NewPage` was not called before any draw method, or after `EndDoc`.

### Legacy API — ColWidths / ColAligns Arrays

```pascal
// For code that predates TTableLayout:
Report.BeginTable([2000, 6000, 2000], [tcaLeft, tcaLeft, tcaRight]);
Report.AddTableRow(['Date', 'Description', 'Amount'], {IsHeader=}true);
Report.AddTableRow(['2026-01-15', 'Consulting', '1,500.00']);
Report.EndTable;
```

`AddTableRow(Cells, IsHeader)`: `IsHeader=true` renders with gray background
(`$E0E0E0`, else white), in the current font. Prefer `BeginTable(Layout)` +
`DrawTableHeader` + `DrawTableRow` for new code:

- each `AddTableRow` is a `TR` in a tagged export: a header row
  (`IsHeader`, kind 1) in `THead` with `TH` cells, a data row (kind 0) in
  `TBody` with `TD` cells
- at a page break it starts a new page without repeating the header
- a header row after data rows opens a second `THead` after the `TBody`,
  as `DrawTableHeader` mid-table does: give the header first
- this `BeginTable` saves the layout and `EndTable` restores it, as with
  `BeginTable(Layout)`

**Automatic page break:** When a data row no longer fits, it moves to the next page and the column headers are automatically repeated at the top. A header row that does not fit moves the table to the next page first, and a footer row breaks the same way. Header content is saved internally when `DrawTableHeader` is called; `EndTable` clears the saved headers. The repetition is recorded as `dckBeginTR` with `Color = 2`; a tagged export renders it inside `BeginArtifact`/`EndArtifact` with no struct elements, so the struct tree holds the header once. Running page header/footer text is an artifact too. A tagged export with an empty `Title` takes the first H1 as the document title. A single row taller than the page is not split (R-10).

---

## Graphics Methods

```pascal
Report.DrawLine(X1, Y1, X2, Y2, Width, Color);   // line; Width in pixels at 96 dpi
Report.DrawFilledRect(X1, Y1, X2, Y2, Color);     // filled rectangle, no border
Report.Columns2(Gap, Text1, Text2);               // two wrapped columns from CurrentY
```

`Columns2` splits the printable width into two columns with `Gap` between
them and leaves `CurrentY` below the longer one.

---

## Export & Preview

`TGDIPages` is a non-visual `TComponent`: the unit needs no forms and
no printer. Preview and printing live in `mormot.pdf.report.preview` and use
only the public API (`PageCount`, `Pages[]`, margins, `Title`,
`RenderPageToCanvas`):

```pascal
// WYSIWYG preview (GUI, modal):
ShowReportPreview(Report);

// Print on the LCL's current printer (Printers.Printer, its settings; range
// clipped, 0-based, defaults print all pages; no dialog):
PrintReport(Report);
PrintReport(Report, 0, 2);

// Export PDF:
Report.ExportPdfStream(AStream): boolean;   // false on error (or no page)
Report.ExportPdfStream(AStream, true);      // raises instead, also for no page
Report.ExportPDF(FileName, false, false, Title, Company); // raises on error

// PDF export configuration:
Report.ExportPdfEmbeddedTTF    := True;      // embed TrueType fonts
Report.ExportPdfStandardFonts  := False;     // keep the TrueType faces (true: Type1 base-14)
Report.ExportPdfTagged         := True;      // before the first NewPage, else EPdfReport
Report.ExportPdfLanguage       := 'en';      // /Lang of a tagged export
Report.ExportPdfLevel          := pdfa3U;    // PDF/A level, pdfaNone (default) … pdfa3U
Report.ExportPdfFileFormat     := pdf17;     // PDF version header (default: pdf13), never below what the level and Tagged need
Report.ExportPdfAuthor         := 'Company'; // empty = Author
Report.ExportPdfSubject        := 'Report';  // empty = Subject
Report.ExportPdfCreator        := 'My App';  // /Creator; empty = executable name
Report.Title   := 'Document title';
Report.Author  := 'Author name';
Report.Subject := 'Subject';

// PDF/A-3 associated files and XMP extension (ZUGFeRD/Factur-X):
Report.AddExportPdfAttachment(Xml, 'factur-x.xml', 'Factur-X invoice data',
  'text/xml', afrAlternative);       // kept until ClearExportPdfAttachments
Report.ExportPdfMetadataExtension := PdfMetadataFacturX('EN 16931', 'factur-x.xml');
Report.ExportPdfPageMode := pmUseAttachments; // opens the attachments panel;
                                     // pmUseNone (default) writes no /PageMode
```

`ExportPdfTagged := True` also sets `ExportPdfEmbeddedTTF` true and
`ExportPdfStandardFonts` false: PDF/UA forbids the unembedded base-14
faces, and the flags decide the measurement, hence the error after the
first page.

**Errors:** the unit raises `EPdfReport = class(ESynException)` - the
trunk's `mormot.ui.report` has `EReport` for the same; a name of its own,
because both units exist until the 2.5 merge. Misuse raises it: drawing
before `NewPage` or after `EndDoc`, `DrawHeading` with a level outside
1..6 or an empty title, a table call without `BeginTable`, `BeginTable`
twice, `ExportPdfTagged` after the first page (`TestMisuseRaises`, one
`CheckRaised` each, exact class). Errors of the engine and of the file
pass through with their own class.

`ExportPdfStream` first closes a list left open, as `EndDoc` does: a tagged
export would otherwise leave its `L` element open and fail. It catches every
exception and returns false, unless
`aRaiseException` is true (the trunk's parameter); either way it resets
`fActivePdfDoc`, so a later `RenderPageToCanvas` (preview, printing) does
not reach the freed document. With no page it returns false, or raises
`EPdfReport`.

`ExportPDF` raises on every error: `EPdfReport` when there is no page and
when `Protect` or `Encrypt` is true - neither is implemented, and a
protection asked for must not silently give an open file (the trunk's
`ExportPdfEncryption*` properties are open work, see ROADMAP;
`TPdfDocumentVcl.Create` already takes a `TPdfEncryption`, PDF/A refuses
one, PDF/UA needs `/P` bit 10 - `Tagged` raises without
`epContentExtraction`, which RC4-40 always sets); otherwise the export's own
exception or that of writing the file (`EPdfInvalidOperation`,
`EFCreateError`, ...). `ATitle` replaces `Title`, `ACompany` becomes
`ExportPdfSubject`. The PDF is built in a `TMemoryStream` and the file is
opened with `fmCreate` only after a successful export, so a failed export
leaves the old file; a failed write deletes the partial one. Keep it
written in place, not as a temporary file renamed over the target:
`fmCreate` keeps the file's permissions and links on POSIX and refuses a
read-only file, and a rename on Windows does not overwrite.

`ExportPdfStream` owns its `TPdfDocumentVcl`, so these are the only way to
reach `CreateFileAttachmentFrom` and `PdfAMetadaExtension`. The extension is
assigned **before** `SaveToStreamDirectBegin` — PDF/A writes its XMP packet
there; the attachments are created after the outlines, before
`SaveToStreamDirectEnd`, which works in the direct streaming mode
(`TestExportPdfAttachment`).

**A report program uses `mormot.pdf.report` only.** It re-exports what the
`ExportPdf*` options take — `TPdfALevel`/`pdfa*`, `TPdfFileFormat`/`pdf1x`,
`TPdfAFRelationship`/`afr*`, `TPdfPageMode`/`pm*`, `PdfMetadataFacturX` — from
`mormot.pdf`, the first unit of its `uses`, so that the units after it win
for `TRect`/`TPoint` and its own `psA4` wins. Never add `mormot.pdf` beside it
in a program: its
`TPdfPaperSize` has a `psA4` as `TGdiPagePaperSize` does, and its `TRect`
differs from the LCL's, so the uses order decides which one a name means
(`Report.PaperSize := psA4` then fails to compile). A new option taking a
layer-1 type re-exports that type the same way.

### Font Selection for Export

```pascal
var SansFont, SerifFont, MonoFont: RawUtf8;
Report.ExportPdfEmbeddedTTF := True;
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
// Windows: Calibri, Cambria, Consolas
// macOS:   Trebuchet MS, Georgia, Andale Mono
// Linux:   Liberation Sans, Liberation Serif, Liberation Mono
// Android: Roboto, Noto Serif, Droid Sans Mono
// ExportPdfEmbeddedTTF = false: Helvetica, Times, Courier
```

---

## Rendering

```pascal
// Render one page to an arbitrary canvas (used internally by preview and PDF export):
Report.RenderPageToCanvas(
  ACanvas,      // target TCanvas (must be valid)
  PageIndex,    // 0-based page number; out of range draws nothing
  DestWidth,    // rendering area width in pixels (including margins)
  DestHeight,   // rendering area height in pixels (including margins)
  SourceDPI     // optional DPI (0 = ACanvas.Font.PixelsPerInch; use 96 for PDF export)
);
```

Coordinates scale by `DestWidth`/`DestHeight` over the full page size
(content plus the page's margins); `SourceDPI` only enters the font scale.

**Font scaling (zoom):** `RenderPageToCanvas` computes `FontScale = DestHeight / BaseHeight`
where `BaseHeight = MMToPixels(totalPageHeight, SourceDPI or ACanvas.Font.PixelsPerInch)`.
All text commands apply `Font.Size := Round(storedSize * FontScale)`. The preview
passes `DestHeight = fH * fZoom` with `fH` the page height at 96 dpi and no
`SourceDPI`, so on a 96 dpi canvas `FontScale = fZoom` — fonts scale
proportionally with zoom. For PDF export (`SourceDPI = PDF.ScreenLogPixels`),
`FontScale = 1.0` always. `PrintReport` renders each page into
`Printer.PageWidth` × `Printer.PageHeight`.

**Through the PDF bridge.** Delphi 7's `TCanvas` drawing methods are
static, so a call through the `TCanvas` parameter would bypass the bridge.
`RenderPageToCanvas` keeps a local `Bridge` (the parameter cast to
`TPdfVclCanvas`, else nil) and draws text, header/footer, rectangles and
lines through `CanvasTextOut`, `CanvasTextHeight`, `CanvasRectangle`,
`CanvasLine`. `StretchDraw` stays on `ACanvas`: the bridge reintroduces it
even under FPC, so it never reaches the PDF — routing it would change the
output (no recording method emits `dckDrawBitmap` anyway). The white page
background `FillRect` is skipped when `Bridge <> nil`: a PDF page is white
already, and through the `TCanvas` reference the call reached the LCL
widgetset with a DC that has no drawable (GTK2: `Gdk-CRITICAL` per page).

`dckFillRect` is drawn as `Rectangle()` with `Pen.Style := psClear`, never
`FillRect()`: `FillRect` does not trigger brush synchronisation in
`TPdfVclCanvas`.

---

## Global Helper Functions

```pascal
// Convert 1/100-mm to pixels at the given DPI:
function MMToPixels(Value100: Integer; DPI: Integer): Integer;

// Convert pixels to 1/100-mm at the given DPI:
function PixelsToMM(Pixels: Integer; DPI: Integer): Integer;

// Get platform-default font names - an alias of GetPdfFonts() in
// mormot.pdf, which layer 1 code uses without the report engine:
procedure GetReportFonts(Embedded: boolean;
  out SansFont, SerifFont, MonoFont: RawUtf8);
```

Constants: `REPORT_FONT_SANS`, `REPORT_FONT_SERIF`, `REPORT_FONT_MONO` — the
same as `PDF_FONT_TTF_*` of `mormot.pdf`.

---

## Internal Types (useful for extensions)

### TDrawCmdKind

```pascal
TDrawCmdKind = (
  dckDrawText,      // text at (X,Y); Align 0 left, 1 right, 2 centre
  dckDrawLine, dckDrawRect, dckFillRect,
  dckDrawBitmap,    // rendered (Figure when tagged), no recording method
  dckClip, dckRestoreClip, // neither recorded nor rendered
  dckBeginTable,
  dckTableRow,      // neither recorded nor rendered
  dckEndTable,
  dckHeading,       // rendered from the H format, no recording method:
                    // DrawHeading records dckDrawText with HeadingLevel
  dckBeginTR,       // begin table row - Color: the row kind, below
  dckEndTR,         // end table row
  dckBeginList, dckEndList,  // L
  dckBeginLI, dckEndLI);     // LI
```

`dckBeginTR.Color`: `0` data row (→ `TBody`, `psrTD` cells), `1` header row
(→ `THead`, `psrTH`), `2` the header repeated on a continuation page (an
artifact), `3` footer row (→ `TFoot`, `psrTD`, the first cell `psrTHRow`
with `FooterRowHeader`).

### TDrawCommand

Each recorded drawing operation:

```pascal
TDrawCommand = record
  Kind:         TDrawCmdKind;
  X, Y, X2, Y2: Integer;      // coordinates in 1/100mm
  FontName:     RawUtf8;
  FontSize:     Integer;
  FontStyle:    TFontStyles;
  Color:        TColor;
  BkColor:      TColor;        // never set
  Text:         RawUtf8;
  TextWidthMM:  Integer;       // measured once at recording
  BitmapIndex:  Integer;       // never set
  LineWidth:    Integer;       // pixels at 96 dpi
  Align:        Integer;
  FormatName:   RawUtf8;       // never set
  HeadingLevel: Integer;       // dckDrawText of a heading: 1..6, else 0
  HeadingTitle: RawUtf8;       // dckHeading only
  BlockId:      Integer;       // logical block: 0 = standalone, >0 = shared by
                               // all lines of one wrapped paragraph
                               // or by all runs of one inline line
  IsInline:     boolean;       // true = inline run continuing the current line
  InlineStyle:  TInlineStyle;  // isPlain, isStrong, isEm, isCode, isLink
  RowHeader:    boolean;       // dckDrawText: a cell heading its row (TH /Scope /Row)
end;
```

`NewCommand` returns an all-zero command (Delphi 7 has no `Default()`);
build every command from it.

**BlockId (Tagged PDF).** `RecordWrappedText` — and therefore every wrapping
entry point (`DrawTextWrapped`, `DrawParagraph`, `DrawQuote`, `DrawCaption`,
`DrawHeading`, `Columns2`) — stamps one fresh id onto all lines it emits.
During tagged export `RenderPageToCanvas` opens **one** struct element per
block and keeps its marked-content region open across the lines, so a
wrapped paragraph is a single `P`, not one `P` per line. Cell text, list
items and the coordinate overloads keep `BlockId = 0` (standalone). A block
interrupted by a page break is reopened on the next page via
`TPdfDocumentVcl.ResumeStructContent`, so it stays one element with one MCID
per page. Any command other than `dckDrawText` closes the open block.

**Inline runs (Tagged PDF).** The coordinate-less overloads (`DrawText`,
`DrawStrong`, `DrawEm`, `DrawCode`, `DrawLink`) advance `CurrentX` on the
current line. They all stamp one shared `BlockId` and `IsInline = true`, so the
tagged export emits **one** `P` (or `TD`/`LBody`/`Hx`) for the whole line: a
plain run adds a region to that element, a styled run becomes a nested `Span`.
The line ends — and the next one gets a fresh id — at
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
  MarginLeft, MarginRight, MarginTop, MarginBottom: Integer; // as at NewPage
end;
```

Access via `Report.Pages[PageIndex]` (0-based, read-only, no range check).

---

## Command Recording Flow

```
DrawHeading / DrawParagraph / DrawText
    ↓ EmitTextCmd / AddCommand
    ↓ TDrawCommand array (one list per page)

ShowReportPreview / PrintReport / ExportPdfStream
    ↓ RenderPageToCanvas(ACanvas, PageIndex, DestWidth, DestHeight)
    ↓ iterates TDrawCommand[]
    ↓ ACanvas.TextOut / ACanvas.Rectangle / ...
        ↓ (on PDF export: TPdfVclCanvas -> TPdfCanvas -> PDF stream)
```
