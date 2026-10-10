# Learning Path — The 8 Demos

The eight demos show the framework from bottom to top: from the direct PDF API up to database-driven report generation, and then into specialised scripts. Each of the first four demos builds on the previous one. Demo 8 goes one layer below Demo 1, to the API that also builds with Delphi 7.

```
Demo 8 — layer1_demo      TPdfDocument / TPdfCanvas alone, FPC and Delphi 7
Demo 7 — zugferd_demo     PDF/A-3U + PDF/UA-1 hybrid e-invoice (ZUGFeRD / Factur-X)
Demo 6 — rtl_demo         Arabic RTL text + HarfBuzz / Uniscribe shaping
Demo 5 — chinese_demo     CJK (Chinese) text with font subsetting
Demo 4 — mormot_demo      ORM + database
Demo 3 — markdown_demo    Semantic document layout
Demo 2 — report_demo      GUI preview + interactive export
Demo 1 — pdf_demo         Direct TCanvas graphics
```

**Output files.** Every demo writes `<demo>_<os>_<cpu>_<compiler>.pdf` next to
its executable, whatever the current folder: `<os>` is mORMot2's
`OS_NAME[OS_KIND]` in lower case — `windows`, `osx`, and on Linux the
distribution (`debian`, `ubuntu`, …); `<cpu>` is `CPU_ARCH_TEXT` (`x64`,
`x86`, `aarch64`, …) and `<compiler>` `COMPILER_VERSION` without its bitness,
e.g. `pdf_demo_windows_x64_free-pascal-3.2.2.pdf` or
`pdf_demo_windows_x86_delphi-7.pdf`. The files of all platforms and compilers
can so share one folder for checking. The GUI demos write it with `--export`
and no file name.

**One unit per layer.** Each demo uses the units of its layer only: Demos 2–4
and 7 `mormot.ui.report` (the GUI forms add `mormot.ui.reportpreview`), Demos
1, 5 and 6 `mormot.ui.pdfcanvas` with `mormot.pdf`, Demo 8 `mormot.pdf`. A
layer re-exports what its API takes from below, so a report never needs
`mormot.pdf` — and must not have it: both units declare `psA4`, and the
order of the `uses` clause would decide which one is meant. See the main
README, "Which unit to use".

---

## Demo 1 — pdf_demo_crossplat

**Entry level: Direct TCanvas API**

Shows how to produce a 3-page PDF from TCanvas commands using `TPdfDocumentVcl` — no report engine, no GUI.

**What you learn:**
- Create and configure `TPdfDocumentVcl`
- Set font, pen and brush
- Draw text, rectangles, lines and polygons
- Create multi-page PDFs (`AddPage` / get fresh `VclCanvas`)
- Measure text (`TextWidth` / `TextHeight`)
- Manual low-level table: header row, data rows with alternating colors
- Tagged PDF accessibility marks (`Doc.Tagged := True` auto-raises `FileFormat` to `pdf17`)
- Tagged output implies **embedded TrueType fonts**: PDF/UA does not allow the
  viewer's own non-embedded base-14 faces, so `Tagged := True` turns
  `EmbeddedTTF` on and `StandardFontsReplace` off. The faces are embedded as
  subsets on every platform — `libharfbuzz-subset` on Linux/macOS (ROADMAP
  R-12: the demo PDF is about 19 KB), `CreateFontPackage` with a glyph keep
  list on Windows (R-15: 115 KB). Both keep the glyph IDs, and therefore the
  `/ToUnicode` round-trip.
- Struct roles: `psrH1` for headings, `psrP` for body text, `psrFigure` for graphics, `psrTable / psrTR / psrTH / psrTD` for tables
- Table row groups: the header row sits in `psrTHead`, the data rows in
  `psrTBody` (ISO 32000-1 14.8.4.3.4). `TGDIPages` emits the groups on its
  own; with the low-level API the caller opens them, as this demo shows

**Core pattern:**

```pascal
uses mormot.pdf, mormot.ui.pdfcanvas;

var Doc: TPdfDocumentVcl; C: TPdfVclCanvas;
begin
  Doc := TPdfDocumentVcl.Create;
  // Tagged PDF — must be set BEFORE AddPage and before the font names are
  // resolved. It auto-raises FileFormat to pdf17 (ISO 32000-1) and selects the
  // PDF/UA font mode: EmbeddedTTF on, StandardFontsReplace off.
  Doc.Tagged          := True;
  Doc.DefaultLanguage := 'en';
  // asked afterwards, so the names match the mode Tagged just selected
  GetPdfFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
  Doc.Info.Title      := 'mORMot2 PDF Cross-Platform Demo';
  Doc.DefaultPaperSize := psA4;

  // --- Page 1: Fonts & Text ---
  Doc.AddPage;
  C := Doc.VclCanvas;

  Doc.BeginStructContent(psrH1);
  C.Font.Name  := 'Helvetica';
  C.Font.Size  := 24;
  C.Font.Style := [fsBold];
  C.Font.Color := $800000;
  C.TextOut(40, 40, 'mORMot2 PDF Cross-Platform Test');
  Doc.EndStructContent;
  // one bookmark per heading (PDF/UA); the document was created with
  // TPdfDocumentVcl.Create(true), i.e. with outlines on
  Doc.CreateOutline('mORMot2 PDF Cross-Platform Test', 1,
    Doc.DefaultPageHeight - 40 * 72 / 96);   // PDF points from the bottom

  Doc.BeginStructContent(psrP);
  C.Font.Style := [];
  C.Font.Size  := 12;
  C.Font.Color := clBlack;
  C.TextOut(40, 100, 'Helvetica 12pt: The quick brown fox...');
  // ... more TextOut calls ...
  Doc.EndStructContent;

  // --- Page 2: Vector graphics ---
  Doc.AddPage;
  C := Doc.VclCanvas;   // always get a fresh canvas after AddPage
  // one figure for the whole drawing, the text samples included (text in an
  // image): a reader gets the /Alt instead, so it describes the numbers too
  Doc.BeginStructContent(psrFigure,
    'Vector graphics: three filled rectangles, three lines of increasing ' +
    'width, and the numbers 1 to 10 in growing font sizes, each inside its ' +
    'measured bounding box');
  C.Brush.Color := $DCDCFF;
  C.Pen.Color   := $C80000;
  C.Rectangle(40, 40, 190, 120);
  C.MoveTo(40, 160); C.LineTo(550, 160);
  // ... the numbers 1..10 with their measured boxes ...
  Doc.EndStructContent;
  // PAC 2024 warns "Possibly inappropriate use of figure structure element"
  // here, with or without the text inside: accepted, see ROADMAP W-1

  // --- Page 3: Table with Tagged PDF structure ---
  Doc.AddPage;
  C := Doc.VclCanvas;
  Doc.BeginStructContent(psrTable);
    Doc.BeginStructContent(psrTR);
      Doc.BeginStructContent(psrTH); C.TextOut(45, 44, 'Article'); Doc.EndStructContent;
      // ... more TH cells ...
    Doc.EndStructContent; // TR
    for Row := 0 to 4 do begin
      Doc.BeginStructContent(psrTR);
        Doc.BeginStructContent(psrTD); C.TextOut(x, y, Data[Row,0]); Doc.EndStructContent;
        // ... more TD cells ...
      Doc.EndStructContent; // TR
    end;
  Doc.EndStructContent; // Table

  Doc.SaveToFile(PdfFileName); // pdf_demo_<os>_<cpu>_<compiler>.pdf next to the executable
  Doc.Free;
end;
```

**Output:** `pdf_demo_<os>_<cpu>_<compiler>.pdf` (3 pages: fonts, vector graphics, table)

**Build & run:**
```bash
# Linux/macOS:
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
examples/pdf_demo/bin/x86_64-linux/pdf_demo_crossplat

# Windows:
"C:\lazarus\lazbuild.exe" examples/pdf_demo/pdf_demo_crossplat.lpi -B
examples/pdf_demo/bin/x86_64-win64/pdf_demo_crossplat.exe
```

**Next step:** Demo 2 shows how `TGDIPages` handles automatic layout, page breaks and GUI preview.

---

## Demo 2 — report_demo

**Intermediate: Report engine with GUI preview**

Shows `TGDIPages` with a Lazarus GUI: WYSIWYG preview, print and PDF export via button click.

**What you learn:**
- Create and configure `TGDIPages`
- Set `SetFont`, `FontStyle`, `TextColor`
- Position text with `DrawText`, `DrawTextCenter`, `DrawTextRight`
- `DrawLine`, `DrawFilledRect` for graphics
- `Columns2` for two-column text
- `DrawHeading(1..2, ...)` for headings with PDF bookmarks — PDF/UA expects one
  bookmark per heading, and a plain `DrawTextCenter` would only be a paragraph
- `TTableLayout` + `BeginTable`/`DrawTableHeader`/`DrawTableRow`/`DrawTableFooter`,
  which builds a real `Table > THead|TBody|TFoot > TR > TH|TD` structure and
  repeats the header row on page breaks
- the totals line is the table's footer row: set apart visually, and held in
  `TFoot` instead of looking like one more data row
- Running header and footer via `SetHeader`/`SetFooter`: the engine repeats them
  on the continuation pages that table pagination creates, and marks them as
  artifacts in the tagged export
- Tagged PDF/UA export (`ExportPdfTagged`), verified with PAC 2024
- GUI preview with `ShowReportPreview` (`mormot.ui.reportpreview`)
- PDF export with metadata, from the GUI or in batch mode

**Core pattern:**

```pascal
uses mormot.ui.report;

var Report: TGDIPages; SansFont, SerifFont, MonoFont: RawUtf8;
begin
  Report := TGDIPages.Create(nil);
  // ExportPdfTagged wraps all draw commands in struct elements, auto-raises
  // FileFormat to pdf17, and selects the PDF/UA font mode. Set it first: it
  // decides which font the layout below is measured with.
  Report.ExportPdfTagged := True;
  Report.GetExportFonts(SansFont, SerifFont, MonoFont);  // platform-correct fonts

  Report.PaperSize    := psA4;
  Report.MarginLeft   := 1500;  // 15mm
  Report.MarginTop    := 2000;  // 20mm

  Report.UseOutlines := True;   // PDF/UA: one bookmark per heading

  // Running header/footer - before the first NewPage, repeated by the engine
  Report.SetHeader('Sample Corp Inc.   |   Report 2026');
  Report.SetFooter('Page {#} of {total}');

  Report.NewPage;

  // Content: H1 writes a struct element and a bookmark
  Report.DrawHeading(1, 'Order List Q1/2026');

  Report.EndDoc;
  ShowReportPreview(Report);   // or: Report.ExportPdfStream(Stream)
  Report.Free;
end;
```

**File structure:**
```
examples/report_demo/
  report_demo.lpi    Lazarus project
  uReport.pas        the report: BuildReport, ExportReport, --export
  uMainForm.pas      Main form with preview + export, passes the options
```

**Build & run:**
```bash
"C:\lazarus\lazbuild.exe" examples/report_demo/report_demo.lpi -B
examples/report_demo/bin/x86_64-win64/report_demo.exe

# batch export, without the GUI - for automated checks (pdffonts, rendering):
examples/report_demo/bin/aarch64-linux/report_demo --export   # -> report_demo_<os>_<cpu>_<compiler>.pdf
```

On Linux the batch mode still needs a display, because the LCL measures the
text; on a headless machine run it under `xvfb-run`. The report is built in
`uReport.pas`, without a form, so Delphi 7 builds the batch export too (the
window follows with roadmap R-20):

```bat
tests\build_delphi7.bat examples\report_demo\report_demo.lpr
bin\d7\report_demo\report_demo.exe --export
```

**Next step:** Demo 3 introduces semantic document layout (H1-H6, inline formatting, `TTableLayout`).

---

## Demo 3 — markdown_demo

**Advanced: Semantic document layout**

Shows the full format system of `TGDIPages`: headings with PDF bookmarks, inline formatting, custom formats and type-safe tables — as a console app without GUI. Renders the same content twice with two different page configurations (margins, font family, font size) to demonstrate per-section layout changes within a single document.

**What you learn:**
- `DrawHeading(1..6, ...)` with automatic PDF bookmarks
- `DefineFormat` to override H1-H6, P, Code, Quote, LI, Caption
- `DrawParagraph`, `DrawQuote`, `DrawListItem`, `DrawCaption` as block elements
- Inline elements: `DrawStrong`, `DrawEm`, `DrawCode`, `DrawLink`
- `TTableLayout` as a type-safe table definition
- `BeginTable` / `DrawTableHeader` / `DrawTableRow` / `EndTable`
- Automatic table header repetition on page break (R-9): 20-row table triggers a visible page break
- `LineHeightFactor` for configurable line spacing — `1.1` (standard) vs. `1.4` (open) across two page configs
- `ExportPdfTagged` for automatic Tagged PDF accessibility marks; auto-raises `FileFormat` to `pdf17`
  and selects the PDF/UA font mode (embedded TrueType). It has to be set **before the first
  drawing command**, because the export font flags decide which metrics the layout is measured with.
- Different page configurations (margins, font, size, `LineHeightFactor`) within one document
- `ExportPdfStream` for stream-based PDF output

**Core pattern:**

```pascal
const TABLE: TTableLayout = (
  ColumnWidths:      [2500, 5000, 5000, 2500];
  ColumnAligns:      [tcaLeft, tcaLeft, tcaRight, tcaRight];
  HeaderFontName:    '';        // inherits current document font
  HeaderFontSize:    0;
  HeaderFontStyle:   [fsBold];
  HeaderBkColor:     $E0E0E0;
  BodyFontName:      '';
  BodyFontSize:      0;
  BodyFontStyle:     [];
  BodyBkColor:       $FFFFFF;
  AlternateRowColor: $F5F5F5;
);

var Fmt: TReportFormat;
begin
  // Override format
  // LineHeightFactor controls vertical spacing (default 1.1).
  // Set per page config before NewPage for a visible contrast between sections.
  Report.LineHeightFactor := 1.1;   // page 1: standard spacing

  Fmt.FontName  := SansFont;
  Fmt.FontSize  := 28;
  Fmt.FontStyle := [fsBold];
  Fmt.SpaceBefore := 600;  Fmt.SpaceAfter := 800;
  Report.DefineFormat('H1', Fmt);

  Report.NewPage;
  Report.SetFont(SansFont, 11);

  // Semantic content
  Report.DrawHeading(1, 'Main Title');           // -> PDF bookmark
  Report.DrawParagraph('Introductory text...');
  Report.DrawHeading(2, 'Section');
  Report.DrawQuote('"Quote" — Author');

  // Inline formatting
  Report.CurrentX := 0;
  Report.DrawText('Normal ');
  Report.DrawStrong('bold');
  Report.DrawText(' and ');
  Report.DrawEm('italic');
  Report.DrawText(' text.');
  Report.MoveToNextLine(800);

  // Table
  Report.BeginTable(TABLE);
  Report.DrawTableHeader(['Date', 'Description', 'Quantity', 'Price']);
  Report.DrawTableRow(['2026-03-15', 'Consulting', '10', '1,500.00']);
  Report.EndTable;

  Report.EndDoc;

  MS := TMemoryStream.Create;
  if Report.ExportPdfStream(MS) then
    MS.SaveToFile(PdfFileName); // markdown_demo_<os>_<cpu>_<compiler>.pdf
end;
```

**Build & run:**
```bash
lazbuild examples/markdown_demo/markdown_demo.lpi -B
examples/markdown_demo/bin/x86_64-linux/markdown_demo
# -> produces markdown_demo_<os>_<cpu>_<compiler>.pdf
```

**Next step:** Demo 4 replaces the static sample data with real ORM data from a SQLite database.

---

## Demo 4 — mormot_demo

**Expert: ORM integration with live database**

Shows `TGDIPages` with `TTableLayout` (the same as Demo 3), but the data comes from a SQLite database via mORMot ORM. A service-layer architecture separates data retrieval from rendering.

**What you learn:**
- mORMot ORM models (`TOrm` classes) as data source for reports
- `TRestClientDB` + `TRestServerDB` for local SQLite database
- Service method (`GetInvoiceData`) to fetch data as DTO array
- `TTableLayout` with 5 columns: row#, order number, customer, date, amount
- Automatic page break and table header repetition via `DrawTableRow`
- Empty-table handling (placeholder row)
- `DrawHeading(1..2, ...)` for headings with PDF bookmarks
- Tagged PDF/UA export (`ExportPdfTagged`), set before the first draw command
- Batch export without the GUI: `mormot_demo --export [<file.pdf>]`, by default `mormot_demo_<os>_<cpu>_<compiler>.pdf`

**Architecture:**

```
data.pas        TOrmEmployee, TOrmCustomer, TOrmCustomerOrder
server.pas      TDemoServer with GetInvoiceData() -> TDtoInvoiceRowDynArray,
                ReadInvoiceData() opening the database
uReport.pas     BuildReport -> DrawInvoiceTable -> TTableLayout rendering
uMainForm.pas   the form, passes the options its controls show
```

**Core pattern (data query + TTableLayout rendering):**

```pascal
// server.pas — data retrieval:
function TDemoServer.GetInvoiceData(out Items: TDtoInvoiceRowDynArray): integer;
begin
  Table := Self.Orm.ExecuteList([TOrmCustomerOrder, TOrmCustomer], SQL);
  // -> fills Items array with TDtoInvoiceRow records
end;

// uReport.pas — rendering with TTableLayout; the rows come in as DTOs,
// InvoiceTableLayout fills a TTableLayout at runtime (Delphi 7 has no typed
// constants for dynamic array fields); FontName='' and FontSize=0 inherit
// the current document font
procedure DrawInvoiceTable(Report: TGDIPages; const Options: TReportOptions;
  const Items: TDtoInvoiceRowDynArray);
var i: integer; Total: Currency;
begin
  Report.SetFont(SansFont, 9);
  Report.BeginTable(InvoiceTableLayout);
  Report.DrawTableHeader(['#', 'Order No.', 'Customer', 'Date', 'Amount']);
  if Items = nil then
    Report.DrawTableRow([NO_VALUE, 'No orders available', '', '', ''])
  else
    for i := 0 to High(Items) do
    begin
      Report.DrawTableRow([
        Int32ToUtf8(i + 1),
        Items[i].OrderNo,             // RawUtf8, as TGDIPages takes it
        Items[i].Company,
        StringToUtf8(FormatDateTime('dd.mm.yyyy', Items[i].SaleDate)),
        StringToUtf8(FormatFloat('#,##0.00', Items[i].ItemsTotal))
      ]);
      Total := Total + Items[i].ItemsTotal;
    end;
  // the totals line: a TFoot row
  Report.DrawTableFooter(['', 'Total', '', '',
    StringToUtf8(FormatFloat('#,##0.00 EUR', Total))]);
  Report.EndTable;
end;
```

**Database initialisation:**
The SQLite database is created automatically (`CreateMissingTables`). Demo data must be inserted separately — the app also starts with an empty database (shows a placeholder row).

**File structure:**
```
examples/mormot_demo/
  mormot_demo.lpi     Lazarus project
  uReport.pas         the report: BuildReport, ExportReport, --export
  uMainForm.pas       Main form, passes the options
  data.pas            ORM models (TOrmEmployee, TOrmCustomer, TOrmCustomerOrder)
  server.pas          TDemoServer with GetInvoiceData(), ReadInvoiceData()
```

**Build & run:**
```bash
"C:\lazarus\lazbuild.exe" examples/mormot_demo/mormot_demo.lpi -B
examples/mormot_demo/bin/x86_64-win64/mormot_demo.exe
```

Delphi 7 builds the batch export, ORM and static SQLite included (the window
follows with roadmap R-20); run it from the demo folder, where it finds
`data/`:

```bat
tests\build_delphi7.bat examples\mormot_demo\mormot_demo.lpr
cd examples\mormot_demo
..\..\bin\d7\mormot_demo\mormot_demo.exe --export
```

---

## Demo 5 — chinese_demo

**Specialised: CJK (Chinese) text with font subsetting**

Shows how to render Chinese (CJK) text with `TPdfDocumentVcl`. CJK ideographs require the full CMAP of a CJK-capable font and no contextual shaping.

**What you learn:**
- CJK has no contextual shaping — `UseUniscribe` stays off, on every platform
- `EmbeddedWholeTtf := False` embeds only the glyphs actually drawn, on every platform: hb-subset on Linux/macOS (ROADMAP R-12), `CreateFontPackage` driven by a glyph keep list on Windows (R-15). Both keep the glyph numbering, so Identity-H and `/ToUnicode` stay valid
- Root cause of the historic CJK failure: `lfCharSet = ANSI_CHARSET` restricted CMAP to Latin only; the fix passes `Font.Charset` (DEFAULT_CHARSET) via `TPdfVclCanvas.SyncFont`
- What subsetting saves here: Microsoft YaHei covers 28,000+ ideographs (~17 MB TTF), so embedding the whole face costs about 24 MB where the subset costs 39 KB
- `EmbeddedWholeTtf := True` still embeds the complete TTF binary, should a consumer need the full CMAP
- Platform-specific CJK fonts: Microsoft YaHei (Windows) / Hiragino Sans GB (macOS) / Droid Sans Fallback (Linux)

**Font requirements:**

| Platform | Font | How to install |
|---|---|---|
| Windows | Microsoft YaHei | pre-installed (Vista+) |
| macOS | Hiragino Sans GB | pre-installed |
| Linux | Droid Sans Fallback | `sudo apt install fonts-droid-fallback` |

**Core pattern:**

```pascal
uses mormot.pdf, mormot.ui.pdfcanvas;

const CJK_FONT = 'Microsoft YaHei'; // Windows example

var Doc: TPdfDocumentVcl; C: TPdfVclCanvas;
begin
  Doc := TPdfDocumentVcl.Create;
  Doc.EmbeddedTTF      := True;
  Doc.EmbeddedWholeTtf := False;  // subset: only the glyphs actually drawn
  Doc.UseUniscribe     := False;  // CJK needs no contextual shaping
  Doc.Info.Title := 'Chinese PDF Demo';

  Doc.AddPage;
  C := Doc.VclCanvas;

  // Latin label with platform sans-serif font
  C.Font.Name  := SansFont;
  C.Font.Size  := 14;
  C.Font.Style := [fsBold];
  C.TextOut(40, 30, 'Chinese PDF Demo  —  Font: ' + CJK_FONT);

  // Chinese title: 中文演示 (Chinese Demo)
  C.Font.Name  := CJK_FONT;
  C.Font.Size  := 36;
  C.Font.Style := [fsBold];
  C.TextOut(40, 65, CJK_TITLE);

  // Chinese numerals 1–10: 一二三四五六七八九十
  C.Font.Size  := 22;
  C.Font.Style := [];
  C.TextOut(40, 175, CJK_NUMBERS);

  Doc.SaveToFile(PdfFileName); // chinese_demo_<os>_<cpu>_<compiler>.pdf
  Doc.Free;
end;
```

**Output:** `chinese_demo_<os>_<cpu>_<compiler>.pdf` (1 page with Chinese headings, greetings, numerals, sentences)

**Build & run:**
```bash
lazbuild examples/chinese_demo/chinese_demo.lpi -B
examples/chinese_demo/bin/x86_64-linux/chinese_demo
# -> produces chinese_demo_<os>_<cpu>_<compiler>.pdf (~40 KB: only the glyphs drawn are embedded)
```

**Note:** With `EmbeddedWholeTtf := True` the same document comes out at roughly 24 MB, because YaHei / WQY covers 28,000+ CJK glyphs. Subsetting is safe for CJK on every platform now that the Windows keep list is a glyph list (R-15) rather than a list of code points — measured on Windows: 23,924,686 B → 39,279 B with byte-identical `pdftotext` output.

---

## Demo 6 — rtl_demo

**Specialised: Arabic RTL text with HarfBuzz / Uniscribe shaping**

Shows Arabic right-to-left text in two sections: an unshared isolated-letter baseline (verifying the CMAP DEFAULT_CHARSET fix), and a contextual-shaping section using Uniscribe (Windows) or HarfBuzz (Linux/macOS).

**What you learn:**
- `PdfC.RightToLeftText := True` signals RTL direction to the PDF canvas
- Section 1 (no shaper): isolated Arabic letters verify the CMAP fix and per-glyph advance widths
- Section 2 (shaper): contextual Arabic letter forms (connected ligatures) via Uniscribe or HarfBuzz
- Why HarfBuzz: FreeType alone cannot perform Arabic GSUB substitutions. `mormot.pdf` brings `mormot.lib.harfbuzz` itself, like the FreeType2 backend; it shapes when `libharfbuzz` loads
- `EmbeddedWholeTtf := False` is safe on every platform: both subsetters receive the shaped glyph IDs themselves — hb-subset on Linux/macOS (ROADMAP R-12), `CreateFontPackage` with a glyph keep list on Windows (R-15)
- **Set `UseUniscribe := True` without a conditional.** `USE_UNISCRIBE` is defined in `mormot.pdf.defines.inc` for `mormot.pdf` and does not reach your unit, so `{$ifdef USE_UNISCRIBE}` around the assignment compiles to nothing and the shaper never runs. That was ROADMAP R-16, and it is why the property is declared on every platform — on Linux and macOS the same switch shapes with HarfBuzz. `RightToLeftText` only sets the direction
- Platform-specific Arabic fonts: Tahoma (Windows) / Geeza Pro (macOS) / Noto Naskh Arabic (Linux)

**Font and library requirements:**

| Platform | Font | Shaper | How to install |
|---|---|---|---|
| Windows | Tahoma | Uniscribe (OS) | pre-installed |
| macOS | Geeza Pro | HarfBuzz | `brew install harfbuzz` |
| Linux | Noto Naskh Arabic | HarfBuzz | `sudo apt install fonts-noto-core libharfbuzz0b` |

**Core pattern:**

```pascal
uses
  mormot.pdf, mormot.ui.pdfcanvas;  // mormot.pdf brings backend and shaper

var Doc: TPdfDocumentVcl; C: TPdfVclCanvas; PdfC: TPdfCanvas;
begin
  Doc := TPdfDocumentVcl.Create;
  Doc.EmbeddedTTF      := True;
  Doc.EmbeddedWholeTtf := False;  // both subsetters keep the shaped glyph IDs
  Doc.UseUniscribe     := False;  // section 1 stays unshaped

  Doc.AddPage;
  C    := Doc.VclCanvas;
  PdfC := C.PdfCanvas;

  // --- Section 1: NoShaper path — isolated form, CMAP fix test ---
  PdfC.RightToLeftText := False;
  C.Font.Name := ARABIC_FONT;
  C.Font.Size := 48;
  C.TextOut(40, 52, ARABIC_BA);   // U+0628 BA — single isolated letter

  // Multiple isolated letters — advance width test
  C.Font.Size := 24;
  C.TextOut(40, 162, ARABIC_HELLO);   // مرحبا  (5 isolated chars)

  // --- Section 2: Shaper path — contextual forms + RTL bidi ---
  Doc.UseUniscribe := True;         // Uniscribe or HarfBuzz - no {$ifdef}
  C.Font.Name  := ARABIC_FONT;
  C.Font.Size  := 36;
  PdfC.RightToLeftText := True;     // the direction
  C.TextOut(500, 472, ARABIC_HELLO);   // مرحبا — connected contextual forms
  C.TextOut(500, 516, ARABIC_BOOK);    // كتاب
  C.TextOut(500, 560, ARABIC_SCHOOL);  // مدرسة
  C.TextOut(500, 604, ARABIC_HOUSE);   // بيت

  PdfC.RightToLeftText := False;       // restore for Latin labels
  Doc.SaveToFile(PdfFileName); // rtl_demo_<os>_<cpu>_<compiler>.pdf
  Doc.Free;
end;
```

**Output:** `rtl_demo_<os>_<cpu>_<compiler>.pdf` (1 page, 4 sections: isolated-letter CMAP test, advance-width test, single shaped char, shaped words)

**Build & run:**
```bash
lazbuild examples/rtl_demo/rtl_demo.lpi -B
examples/rtl_demo/bin/x86_64-linux/rtl_demo
# -> produces rtl_demo_<os>_<cpu>_<compiler>.pdf
```

**Note:** On Linux without `libharfbuzz`, Section 2 still runs but Arabic letters appear as isolated forms (no contextual shaping). Install `libharfbuzz0b` and `fonts-noto-core` for correct connected letter output.

---

## Demo 7 — zugferd_demo

**Specialised: PDF/A-3U and PDF/UA-1 in one file, as a hybrid e-invoice**

Reads the invoice data from `factur-x.xml`, draws the invoice with
`TGDIPages` and embeds the same file as an associated file — a ZUGFeRD 2.x /
Factur-X 1.x invoice of the profile **EN 16931**, the form exchanged between
businesses in Germany and France. The same file conforms to PDF/A-3U
(archiving, every text maps to Unicode) and to PDF/UA-1 (accessibility).

**What you learn:**
- A report as PDF/A: `ExportPdfLevel := pdfa3U` and `ExportPdfTagged := True`
  before the first `NewPage`, like every font option — they decide which
  metrics the layout is measured with
- Tagged PDF and PDF/A combine: the engine writes one XMP packet with both
  identifications, and describes the `pdfuaid` schema PDF/A does not
  predefine
- `AddExportPdfAttachment(..., afrAlternative)` embeds a file with its
  `/AFRelationship`; from PDF/A-2 up the catalog lists it in `/AF`
- `ExportPdfMetadataExtension := PdfMetadataFacturX('EN 16931', ...)` writes
  the `fx:` XMP properties a ZUGFeRD reader looks for, with their PDF/A
  extension schema
- `ExportPdfPageMode := pmUseAttachments` opens the viewer on the
  attachments panel; `TTableLayout.FooterRowHeader` makes the label of each
  totals row a row header (`TH` with `/Scope /Row`) for screen readers
- **Data in, page out:** the page is drawn from a record `TInvoice`, which a
  small demo reader fills from the XML the PDF embeds — so page and data
  cannot differ, and the record shows where your own data would go in
- **Non-ASCII text without code-point constants:** the labels are ASCII, the
  umlauts come from the UTF-8 file as `RawUtf8`, so one source builds with
  FPC, Delphi 7 and Delphi 2010
- Stages A and U: `pdfa3U` needs no more than a `/ToUnicode` for every font,
  which the engine writes; `pdfa3A` additionally needs the structure tree, so
  it requires the tagged export
- What the engine does **not** do: generate or validate invoice XML. That is
  the caller's, and here it is a sample file. The demo's reader is no
  parser either: fixed paths and prefixes, no entities, no validation

**Scope.** Invoices to German public authorities take pure XML (XRechnung),
not a PDF, so they are not what this demo — or this project — produces.

**The invoice data** is the sample `Gesamtbeispiel` of XRechnung for Delphi,
contributed by Landrix under the licence of this project: two VAT rates, a
billing period, a due date and two bank accounts, each drawn on the page.

**Core pattern:**

```pascal
uses
  mormot.ui.report;   // re-exports pdfa3U, afrAlternative, PdfMetadataFacturX

var Report: TGDIPages; Xml: RawUtf8; Invoice: TInvoice;
begin
  Xml := StringFromFile('factur-x.xml');
  Invoice := ReadInvoice(Xml);           // the demo's reader
  Report := TGDIPages.Create(nil);
  Report.ExportPdfLevel := pdfa3U;       // all before the first NewPage
  Report.ExportPdfTagged := True;        // PDF/UA-1 as well
  Report.ExportPdfLanguage := 'de';
  Report.UseOutlines := True;
  Report.Title := 'Rechnung ' + Invoice.Number;
  Report.NewPage;
  Report.DrawHeading(1, 'Rechnung ' + Invoice.Number);
  Report.DrawParagraph('Rechnungsdatum: ' + GermanDate(Invoice.IssueDate));
  // ... one TTableLayout table: header, the items, the totals as footer rows
  Report.EndDoc;
  Report.AddExportPdfAttachment(Xml, 'factur-x.xml', 'Factur-X invoice data',
    'text/xml', afrAlternative);
  Report.ExportPdfMetadataExtension := PdfMetadataFacturX('EN 16931', 'factur-x.xml');
  Report.ExportPdfStream(Stream);        // zugferd_demo_<os>_<cpu>_<compiler>.pdf
  Report.Free;
end;
```

**Switches:** `--no-attachment` leaves the XML and the `fx:` metadata out of
the PDF (the page is still read from it), `--untagged` the structure tree — to
tell the sources of a checker failure apart.

**Output:** `zugferd_demo_<os>_<cpu>_<compiler>.pdf` (1 page). The earlier
layer-2 version passed veraPDF (`3u`, `ua1`), Mustang-CLI and PAC 2024 on
Windows, Linux and macOS, with one accepted quality hint, e-mail addresses
without a link element (ROADMAP W-2); this version is being checked the same
way (ROADMAP R-26).

**Build & run** — `factur-x.xml` is looked up in the current folder, then two
levels above the executable (the demo folder); the PDF goes next to the executable:
```bash
lazbuild examples/zugferd_demo/zugferd_demo.lpi -B
examples/zugferd_demo/bin/<target>/zugferd_demo
# -> produces zugferd_demo_<os>_<cpu>_<compiler>.pdf
```

---

## Demo 8 — layer1_demo

**The low-level API alone, for FPC and Delphi 7**

Draws two tagged pages with `TPdfDocument` and `TPdfCanvas`, without the
TCanvas bridge and without `TGDIPages`: text and a figure, then a table. It
builds with Delphi 7 (Win32), and so do the other five console demos and the
batch export of the two GUI demos; their windows and the preview are FPC-only
until roadmap R-20 is done.

**What you learn:**
- PDF points, with Y counted from the bottom edge: a text line at Y = 780 is
  near the top of an A4 page (842 pt), and its Y is the baseline
- Text in the same encoding on both compilers: UTF-8 in, `Utf8ToSynUnicode`,
  `TextOutW`. Non-ASCII characters are UTF-8 bytes in a `RawUtf8` constant,
  never literal characters in the source
- `GetPdfFonts` of `mormot.pdf` gives the platform's faces without the
  report engine; ask for them after `Tagged := True`
- With this API you build the structure yourself: `BeginStructContent` for
  `H1`/`H2`/`P`, a `Figure` with alternate text, and `CreateOutline` for
  every heading
- The path operations in one figure: `Rectangle`, `RoundRect`, `Ellipse`, a
  Bézier curve with `CurveToC`, line widths; `Fill`, `Stroke`, `FillStroke`.
  Deliberately not a chart: charts are out of scope — an image from a chart
  library in a `Figure`, and its values as a table (README, "Tagged PDF")
- A table by hand: `Table` › `THead`/`TBody`/`TFoot` › `TR` › `TH`/`TD`,
  numbers right-aligned with `UnicodeTextWidth`. What `TGDIPages` does for you
  (roadmap R-14), step by step
- Artifacts: a path outside any element becomes one by itself — so the
  table's fills and rules are drawn before the table; text such as a running
  footer needs `BeginArtifact`/`EndArtifact`

**Core pattern:**

```pascal
uses
  mormot.core.base, mormot.core.unicode,
  mormot.pdf;   // roles, GetPdfFonts; brings the platform backend itself

procedure DrawText(C: TPdfCanvas; X, Y: single; const Text: RawUtf8);
var W: SynUnicode;
begin
  W := Utf8ToSynUnicode(Text);
  C.TextOutW(X, Y, pointer(W));
end;

var Doc: TPdfDocument; Sans, Serif, Mono: string;
begin
  Doc := TPdfDocument.Create(true);       // with outlines
  Doc.Tagged := True;
  Doc.Info.Title := 'mORMot2 PDF Layer 1 Demo';
  GetPdfFonts(Doc.EmbeddedTTF, Sans, Serif, Mono);
  Doc.AddPage;
  Doc.Canvas.BeginStructContent(psrH1);
  Doc.Canvas.SetFont(StringToUtf8(Sans), 22, [pfsBold], 1); // 1 = DEFAULT_CHARSET
  DrawText(Doc.Canvas, 56, 780, 'TPdfDocument and TPdfCanvas');
  Doc.Canvas.EndStructContent;
  Doc.CreateOutline('TPdfDocument and TPdfCanvas', 1, 780 + 22);
  Doc.Canvas.BeginStructContent(psrFigure, 'Four shapes in a row ...');
  Doc.Canvas.Rectangle(56, 420, 100, 70); // x, y (bottom), width, height
  Doc.Canvas.FillStroke;
  Doc.Canvas.Ellipse(306, 420, 100, 70);  // the bounding rectangle
  Doc.Canvas.FillStroke;
  Doc.Canvas.EndStructContent;
  // a table: fills and rules first (artifacts), then the elements
  Doc.AddPage;
  Doc.Canvas.Rectangle(56, 680, 483, 20);  // header fill
  Doc.Canvas.Fill;
  Doc.Canvas.BeginStructContent(psrTable);
  Doc.Canvas.BeginStructContent(psrTHead);
  Doc.Canvas.BeginStructContent(psrTR);
  Doc.Canvas.BeginStructContent(psrTH);
  DrawText(Doc.Canvas, 62, 686, 'Article');
  Doc.Canvas.EndStructContent;             // TH, then the other three
  Doc.Canvas.EndStructContent;             // TR
  Doc.Canvas.EndStructContent;             // THead
  // TBody with one TR of four TD per row, TFoot with the totals row
  Doc.Canvas.EndStructContent;             // Table
  Doc.SaveToFile(PdfFileName); // layer1_demo_<os>_<cpu>_<compiler>.pdf
  Doc.Free;
end;
```

**Output:** `layer1_demo_<os>_<cpu>_<compiler>.pdf` (2 pages), e.g.
`layer1_demo_windows_x64_free-pascal-3.2.2.pdf` and
`layer1_demo_windows_x86_delphi-7.pdf`. The FPC/Win64 and the Delphi 7/Win32
files give the same `pdftotext` output, fonts and structure tree.

**Build & run:**
```bash
lazbuild examples/layer1_demo/layer1_demo.lpi -B
examples/layer1_demo/bin/<target>/layer1_demo
# Delphi 7, MORMOT2 set to the mORMot2 checkout:
tests\build_delphi7.bat examples\layer1_demo\layer1_demo.dpr
bin\d7\layer1_demo\layer1_demo.exe
```

---

## Summary: API Layers

| Demo | Class | Coordinates | Dependency |
|---|---|---|---|
| 1 pdf_demo | `TPdfDocumentVcl` | pixels, Y=0 top | mORMot2 + LCL |
| 2 report_demo | `TGDIPages` | 1/100mm, Y=0 top | mORMot2 + LCL |
| 3 markdown_demo | `TGDIPages` | 1/100mm, Y=0 top | mORMot2 + LCL |
| 4 mormot_demo | `TGDIPages` + ORM | 1/100mm, Y=0 top | mORMot2 + LCL + SQLite |
| 5 chinese_demo | `TPdfDocumentVcl` | pixels, Y=0 top | mORMot2 + LCL + CJK font |
| 6 rtl_demo | `TPdfDocumentVcl` | pixels, Y=0 top | mORMot2 + LCL + Arabic font + HarfBuzz (Linux/macOS) |
| 7 zugferd_demo | `TGDIPages` | 1/100mm, Y=0 top | mORMot2 + LCL |
| 8 layer1_demo | `TPdfDocument` | PDF points, Y=0 bottom | mORMot2 + LCL (FPC) or VCL (Delphi 7) |
