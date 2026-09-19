# Learning Path — The 6 Demos

The six demos show the framework from bottom to top: from the direct PDF API up to database-driven report generation, and then into specialised scripts. Each of the first four demos builds on the previous one.

```
Demo 6 — rtl_demo         Arabic RTL text + HarfBuzz / Uniscribe shaping
Demo 5 — chinese_demo     CJK (Chinese) text with whole-TTF embedding
Demo 4 — mormot_demo      ORM + database
Demo 3 — markdown_demo    Semantic document layout
Demo 2 — report_demo      GUI preview + interactive export
Demo 1 — pdf_demo         Direct TCanvas graphics
```

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
  `EmbeddedTTF` on and `StandardFontsReplace` off. On Linux/macOS the faces
  are embedded as subsets through `libharfbuzz-subset`, which keeps glyph IDs
  and therefore the `/ToUnicode` round-trip (ROADMAP R-12: the demo PDF is
  about 19 KB). Windows has no such subsetter and embeds the whole face
  (a few hundred KB).
- Struct roles: `psrH1` for headings, `psrP` for body text, `psrFigure` for graphics, `psrTable / psrTR / psrTH / psrTD` for tables

**Core pattern:**

```pascal
uses mormot.pdf.types, mormot.ui.pdf, mormot.ui.pdfcanvas, mormot.ui.report;

var Doc: TPdfDocumentVcl; C: TCanvas;
begin
  Doc := TPdfDocumentVcl.Create;
  // Tagged PDF — must be set BEFORE AddPage and before the font names are
  // resolved. It auto-raises FileFormat to pdf17 (ISO 32000-1) and selects the
  // PDF/UA font mode: EmbeddedTTF on, StandardFontsReplace off.
  Doc.Tagged          := True;
  Doc.DefaultLanguage := 'en';
  // asked afterwards, so the names match the mode Tagged just selected
  GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
  Doc.Info.Title      := 'mORMot2 PDF Cross-Platform Demo';
  Doc.DefaultPaperSize := mormot.ui.pdf.psA4;

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

  Doc.SaveToFile('output_crossplat.pdf');
  Doc.Free;
end;
```

**Output:** `output_crossplat.pdf` (3 pages: fonts, vector graphics, table)

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
- Draw table rows manually (low-level variant)
- Define headers and footers
- Automatic page break
- GUI preview with `ShowPreviewForm`
- PDF export with metadata

**Core pattern:**

```pascal
uses mormot.ui.report;

var Report: TGDIPages; SansFont, SerifFont, MonoFont: string;
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

  Report.NewPage;

  // Header (every page)
  Report.SaveLayout;
    Report.SetFont(SansFont, 10);
    Report.FontStyle := [fsBold];
    Report.DrawText(0, 0, 'Sample Corp Inc.');
    Report.DrawTextRight(0, 0, 'Report 2026');
    Report.DrawLine(0, 800, Report.PageWidth, 800, 2, clNavy);
    Report.MoveToNextLine(1000);
  Report.RestoreLayout;

  // Content
  Report.SetFont(SansFont, 18);
  Report.FontStyle := [fsBold];
  Report.DrawTextCenter(0, Report.CurrentY, 'Order List Q1/2026');
  Report.MoveToNextLine(1200);

  Report.EndDoc;
  Report.ShowPreviewForm;   // or: Report.ExportPdfStream(Stream)
  Report.Free;
end;
```

**File structure:**
```
examples/report_demo/
  mormot_report_demo.lpi    Lazarus project
  uMainForm.pas             Main form with preview + export
```

**Build & run:**
```bash
"C:\lazarus\lazbuild.exe" examples/report_demo/mormot_report_demo.lpi -B
examples/report_demo/bin/x86_64-win64/report_demo_crossplat.exe
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
    MS.SaveToFile('markdown_demo.pdf');
end;
```

**Build & run:**
```bash
lazbuild examples/markdown_demo/markdown_demo.lpi -B
examples/markdown_demo/bin/x86_64-linux/markdown_demo
# -> produces markdown_demo.pdf
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

**Architecture:**

```
data.pas        TOrmEmployee, TOrmCustomer, TOrmCustomerOrder
server.pas      TDemoServer with GetInvoiceData() -> TDtoInvoiceRowDynArray
uMainForm.pas   BuildReport -> DrawInvoiceTable -> TTableLayout rendering
```

**Core pattern (data query + TTableLayout rendering):**

```pascal
// server.pas — data retrieval:
function TDemoServer.GetInvoiceData(out Items: TDtoInvoiceRowDynArray): integer;
begin
  Table := Self.Orm.ExecuteList([TOrmCustomerOrder, TOrmCustomer], SQL);
  // -> fills Items array with TDtoInvoiceRow records
end;

// uMainForm.pas — rendering with TTableLayout:
const
  INVOICE_TABLE: TTableLayout = (
    ColumnWidths:      [1000, 2500, 7000, 2200, 5300];  // 1/100mm; sum = 18000 (A4-2×15mm)
    ColumnAligns:      [tcaRight, tcaLeft, tcaLeft, tcaRight, tcaRight];
    HeaderFontStyle:   [fsBold];
    HeaderBkColor:     $00AA5500;
    AlternateRowColor: $00F0F0FF;
    // FontName='' and FontSize=0 inherit the current document font
  );

procedure TMainForm.DrawInvoiceTable(Report: TGDIPages);
var Items: TDtoInvoiceRowDynArray; Count, i: integer; Total: Currency;
begin
  Count := TDemoServer(Client.Server).GetInvoiceData(Items);
  Report.SetFont(SansFont, 9);
  Report.BeginTable(INVOICE_TABLE);
  Report.DrawTableHeader(['#', 'Order No.', 'Customer', 'Date', 'Amount']);
  if Count = 0 then
    Report.DrawTableRow(['—', 'No orders available', '', '', ''])
  else
    for i := 0 to Count - 1 do
    begin
      Report.DrawTableRow([
        IntToStr(i + 1),
        Utf8ToString(Items[i].OrderNo),
        Utf8ToString(Items[i].Company),
        FormatDateTime('dd.mm.yyyy', Items[i].SaleDate),
        FormatFloat('#,##0.00', Items[i].ItemsTotal)
      ]);
      Total := Total + Items[i].ItemsTotal;
    end;
  Report.EndTable;
  // ... totals row drawn manually below EndTable ...
end;
```

**Database initialisation:**
The SQLite database is created automatically (`CreateMissingTables`). Demo data must be inserted separately — the app also starts with an empty database (shows a placeholder row).

**File structure:**
```
examples/mormot_demo/
  mormot_demo.lpi     Lazarus project
  uMainForm.pas       Main form
  data.pas            ORM models (TOrmEmployee, TOrmCustomer, TOrmCustomerOrder)
  server.pas          TDemoServer with GetInvoiceData()
```

**Build & run:**
```bash
"C:\lazarus\lazbuild.exe" examples/mormot_demo/mormot_demo.lpi -B
examples/mormot_demo/bin/x86_64-win64/mormot_demo.exe
```

---

## Demo 5 — chinese_demo

**Specialised: CJK (Chinese) text with whole-TTF embedding**

Shows how to render Chinese (CJK) text with `TPdfDocumentVcl`. CJK ideographs require the full CMAP of a CJK-capable font, full TTF embedding and no contextual shaping.

**What you learn:**
- CJK has no contextual shaping — `UseUniscribe := False` is sufficient on Windows
- `EmbeddedWholeTtf := True` embeds the complete TTF binary (required for full CJK CMAP coverage)
- Root cause of the historic CJK failure: `lfCharSet = ANSI_CHARSET` restricted CMAP to Latin only; the fix passes `Font.Charset` (DEFAULT_CHARSET) via `TPdfVclCanvas.SyncFont`
- Why CJK PDFs are large: Microsoft YaHei / WQY covers 28,000+ ideographs (~17 MB TTF); the whole font is embedded
- Font subsetting (`EmbeddedWholeTtf := False`) is safe for CJK on Linux/macOS (hb-subset, ROADMAP R-12: 2.3 MB → 11 KB); on Windows `CreateFontPackage` is safe only for Latin, so the demo keeps the whole face
- Platform-specific CJK fonts: Microsoft YaHei (Windows) / Hiragino Sans GB (macOS) / WQY MicroHei (Linux)

**Font requirements:**

| Platform | Font | How to install |
|---|---|---|
| Windows | Microsoft YaHei | pre-installed (Vista+) |
| macOS | Hiragino Sans GB | pre-installed |
| Linux | WQY MicroHei | `sudo apt install fonts-wqy-microhei` |

**Core pattern:**

```pascal
uses mormot.ui.pdf, mormot.ui.pdfcanvas, mormot.ui.report;

const CJK_FONT = 'Microsoft YaHei'; // Windows example

var Doc: TPdfDocumentVcl; C: TCanvas;
begin
  Doc := TPdfDocumentVcl.Create;
  Doc.EmbeddedTTF      := True;
  Doc.EmbeddedWholeTtf := True;   // full font stream — CJK CMAP coverage guaranteed
  {$ifdef MSWINDOWS}
  Doc.UseUniscribe     := False;  // CJK needs no contextual shaping
  {$endif}
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

  Doc.SaveToFile('output_chinese.pdf');
  Doc.Free;
end;
```

**Output:** `output_chinese.pdf` (1 page with Chinese headings, greetings, numerals, sentences)

**Build & run:**
```bash
lazbuild examples/chinese_demo/chinese_demo.lpi -B
examples/chinese_demo/bin/x86_64-linux/chinese_demo
# -> produces output_chinese.pdf (~10–17 MB due to whole-TTF embedding)
```

**Note:** The large file size is expected. YaHei / WQY covers 28,000+ CJK glyphs, and the whole font is embedded. On Linux/macOS `EmbeddedWholeTtf := False` reduces the output to a few KB (hb-subset); the demo keeps the whole face because Windows' `CreateFontPackage` is not reliable for CJK.

---

## Demo 6 — rtl_demo

**Specialised: Arabic RTL text with HarfBuzz / Uniscribe shaping**

Shows Arabic right-to-left text in two sections: an unshared isolated-letter baseline (verifying the CMAP DEFAULT_CHARSET fix), and a contextual-shaping section using Uniscribe (Windows) or HarfBuzz (Linux/macOS).

**What you learn:**
- `PdfC.RightToLeftText := True` signals RTL direction to the PDF canvas
- Section 1 (no shaper): isolated Arabic letters verify the CMAP fix and per-glyph advance widths
- Section 2 (shaper): contextual Arabic letter forms (connected ligatures) via Uniscribe or HarfBuzz
- Why HarfBuzz: FreeType alone cannot perform Arabic GSUB substitutions; `mormot.pdf.harfbuzz` must be registered
- `EmbeddedWholeTtf := True` required on Windows — `CreateFontPackage` drops the shaped GSUB glyphs. On Linux/macOS a subset is safe: hb-subset receives the shaped glyph IDs themselves (ROADMAP R-12)
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
  {$ifndef MSWINDOWS}
  mormot.pdf.freetype,    // FreeType2 backend (before harfbuzz)
  mormot.pdf.harfbuzz,    // registers PdfTextShaper at startup
  {$endif}
  mormot.ui.pdf, mormot.ui.pdfcanvas;

var Doc: TPdfDocumentVcl; C: TCanvas; PdfC: TPdfCanvas;
begin
  Doc := TPdfDocumentVcl.Create;
  Doc.EmbeddedTTF      := True;
  Doc.EmbeddedWholeTtf := True;   // shaped GSUB IDs must stay valid

  Doc.AddPage;
  C    := Doc.VclCanvas;
  PdfC := (C as TPdfVclCanvas).PdfCanvas;

  // --- Section 1: NoShaper path — isolated form, CMAP fix test ---
  PdfC.RightToLeftText := False;
  C.Font.Name := ARABIC_FONT;
  C.Font.Size := 48;
  C.TextOut(40, 52, ARABIC_BA);   // U+0628 BA — single isolated letter

  // Multiple isolated letters — advance width test
  C.Font.Size := 24;
  C.TextOut(40, 162, ARABIC_HELLO);   // مرحبا  (5 isolated chars)

  // --- Section 2: Shaper path — contextual forms + RTL bidi ---
  {$ifdef MSWINDOWS}
  Doc.UseUniscribe := True;
  {$endif}
  C.Font.Name  := ARABIC_FONT;
  C.Font.Size  := 36;
  PdfC.RightToLeftText := True;
  C.TextOut(500, 472, ARABIC_HELLO);   // مرحبا — connected contextual forms
  C.TextOut(500, 516, ARABIC_BOOK);    // كتاب
  C.TextOut(500, 560, ARABIC_SCHOOL);  // مدرسة
  C.TextOut(500, 604, ARABIC_HOUSE);   // بيت

  PdfC.RightToLeftText := False;       // restore for Latin labels
  Doc.SaveToFile('output_rtl.pdf');
  Doc.Free;
end;
```

**Output:** `output_rtl.pdf` (1 page, 4 sections: isolated-letter CMAP test, advance-width test, single shaped char, shaped words)

**Build & run:**
```bash
lazbuild examples/rtl_demo/rtl_demo.lpi -B
examples/rtl_demo/bin/x86_64-linux/rtl_demo
# -> produces output_rtl.pdf
```

**Note:** On Linux without `libharfbuzz`, Section 2 still runs but Arabic letters appear as isolated forms (no contextual shaping). Install `libharfbuzz0b` and `fonts-noto-core` for correct connected letter output.

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
