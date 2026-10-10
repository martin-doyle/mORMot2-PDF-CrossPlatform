unit uReport;

{ ============================================================
  mORMot2 - ORM Report Demo: the report itself
  Builds and exports the report from the DTO rows server.pas returns, without
  a form, so the batch export runs wherever TGDIPages does - Delphi 7
  included. uMainForm only fills TReportOptions from its controls.
  ============================================================ }

interface

{$I mormot.defines.inc}

uses
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.ui.report,   // TGDIPages (includes PDF export via ExportPdfStream)
  server;             // TDtoInvoiceRowDynArray

const
  /// the application title
  REPORT_CAPTION = 'mORMot2 Report Demo';

type
  /// what the form lets the user change
  TReportOptions = record
    Title, Company: RawUtf8;
    Header, Footer, Grid, Colors: boolean;
  end;

/// the values the form starts with, also used by the batch export
function DefaultReportOptions: TReportOptions;

/// builds the report from Items; the caller frees it
function BuildReport(const Options: TReportOptions;
  const Items: TDtoInvoiceRowDynArray): TGDIPages;

/// reads the rows from the demo database, builds the report and writes it
// to FileName
procedure ExportReport(const Options: TReportOptions; const FileName: TFileName);

/// true when the command line asks for a batch export (--export [<file>]);
// the caller then runs ExportReport instead of the GUI
function BatchExportFile(out FileName: TFileName): boolean;

implementation

uses
  mormot.core.datetime,
  mormot.core.text,
  mormot.core.os,
  mormot.core.unicode;

/// the date the report shows: today, or the day of SOURCE_DATE_EPOCH (UTC,
// ISO 8601) when set - pdfcheck sets it, so that two runs on other days
// give the same PDF (reproducible builds, as pdfTeX or Sphinx do)
function ReportDate: RawUtf8;
var
  epoch: RawUtf8;
  seconds: Int64;
begin
  epoch := StringToUtf8(GetEnvironmentVariable('SOURCE_DATE_EPOCH'));
  if (epoch <> '') and
     ToInt64(epoch, seconds) and
     (seconds >= 0) then
    result := DateToIso8601(UnixTimeToDateTime(seconds), true)
  else
    result := StringToUtf8(DateToStr(Now));
end;

const
  // the placeholder of an empty table, an em dash as UTF-8
  NO_VALUE: RawUtf8 = {$ifdef HASCODEPAGE} #$2014 {$else} #$E2#$80#$94 {$endif};

var
  SansFont: RawUtf8;
  SerifFont: RawUtf8;
  MonoFont: RawUtf8;

function DefaultReportOptions: TReportOptions;
begin
  Result.Title   := 'Order List Q1/2026';
  Result.Company := 'Sample Corp Inc.';
  Result.Header  := True;
  Result.Footer  := True;
  Result.Grid    := True;
  Result.Colors  := True;
end;

{ Table layout for the invoice list. Built at runtime instead of as a typed
  constant: Delphi 7 has no constants for dynamic array fields.
  Every field starts at zero, like the fields a typed constant leaves out:
  the Footer* fields are left alone below and must read as "like the header" }
function InvoiceTableLayout: TTableLayout;
begin
  Finalize(Result);
  FillChar(Result, SizeOf(Result), 0);
  // widths in 1/100 mm: # + OrderNo + Customer + Date + Amount = 18000
  // (A4 portrait minus the 2 x 15 mm margins)
  SetLength(Result.ColumnWidths, 5);
  Result.ColumnWidths[0] := 1000;
  Result.ColumnWidths[1] := 2500;
  Result.ColumnWidths[2] := 7000;
  Result.ColumnWidths[3] := 2200;
  Result.ColumnWidths[4] := 5300;
  SetLength(Result.ColumnAligns, 5);
  Result.ColumnAligns[0] := tcaRight;
  Result.ColumnAligns[1] := tcaLeft;
  Result.ColumnAligns[2] := tcaLeft;
  Result.ColumnAligns[3] := tcaRight;
  Result.ColumnAligns[4] := tcaRight;
  Result.HeaderFontName  := '';         // inherit current document font
  Result.HeaderFontSize  := 0;
  Result.HeaderFontStyle := [fsBold];
  { light grey behind black bold text: the dark accent colour used here
    before did not carry enough contrast (PAC), and report_demo uses the
    same scheme }
  Result.HeaderBkColor     := $00E0E0E0;
  Result.BodyFontName      := '';
  Result.BodyFontSize      := 0;
  Result.BodyFontStyle     := [];
  Result.BodyBkColor       := clWhite;
  Result.AlternateRowColor := $00F0F0F0; // light grey stripe on odd rows
end;

{ ============================================================
  DefineHeadingFormats - appearance of DrawHeading(1..2)
  ============================================================ }
procedure DefineHeadingFormats(Report: TGDIPages);
var
  Fmt: TReportFormat;
begin
  Fmt.FontName    := SansFont;
  Fmt.FontStyle   := [fsBold];
  Fmt.Color       := clNavy;
  Fmt.FontSize    := 18;
  Fmt.SpaceBefore := 0;
  Fmt.SpaceAfter  := 800;
  Report.DefineFormat('H1', Fmt);
  Fmt.FontSize    := 13;
  Fmt.SpaceBefore := 600;
  Fmt.SpaceAfter  := 400;
  Report.DefineFormat('H2', Fmt);
end;

{ ============================================================
  DrawInvoiceTable - order table from ORM data (uses TTableLayout)
  ============================================================ }
procedure DrawInvoiceTable(Report: TGDIPages; const Options: TReportOptions;
  const Items: TDtoInvoiceRowDynArray);
var
  Layout: TTableLayout;
  i: Integer;
  Total: Currency;
begin
  Total := 0;

  Layout := InvoiceTableLayout;
  if Options.Colors then
    Layout.HeaderBkColor := $00D8C0A8;  // light blue-grey (BGR)
  if not Options.Grid then
    Layout.AlternateRowColor := 0;      // 0 = no alternating row colour

  // Set the body font before BeginTable so the layout inherits it (FontName = '').
  Report.SetFont(SansFont, 9);

  // TTableLayout handles column widths, alignment, header background, and alternating
  // row colours automatically. DrawTableRow triggers page breaks as needed.
  Report.BeginTable(Layout);
  Report.DrawTableHeader(['#', 'Order No.', 'Customer', 'Date', 'Amount']);

  if Items = nil then
    Report.DrawTableRow([NO_VALUE, 'No orders available', '', '', ''])
  else
    for i := 0 to High(Items) do
    begin
      Report.DrawTableRow([
        Int32ToUtf8(i + 1),
        Items[i].OrderNo,
        Items[i].Company,
        StringToUtf8(FormatDateTime('dd.mm.yyyy', Items[i].SaleDate)),
        StringToUtf8(FormatFloat('#,##0.00', Items[i].ItemsTotal))
      ]);
      Total := Total + Items[i].ItemsTotal;
    end;

  { The totals line is part of the table, so it is a row - and DrawTableFooter
    puts it into the table's TFoot group, which tells it apart from the data
    rows for assistive technology and gives it the header's look (R-14).
    Drawn below the table with DrawTextAt + DrawTextRight it would be two
    separate P elements, because only the coordinate-less overloads share one
    line and one tag. }
  Report.DrawTableFooter(['', 'Total', '', '',
    StringToUtf8(FormatFloat('#,##0.00 EUR', Total))]);
  Report.EndTable;

  Report.MoveToNextLine(300);
  Report.DrawLine(0, Report.CurrentY, Report.PageWidth, Report.CurrentY,
                  2, clBlack);
  Report.MoveToNextLine(300);
end;

{ ============================================================
  DrawReportBody
  ============================================================ }
procedure DrawReportBody(Report: TGDIPages; const Options: TReportOptions;
  const Items: TDtoInvoiceRowDynArray);
begin
  // ---- Cover area ----
  Report.SaveLayout;

  { DrawHeading writes an H1 structure element and a PDF bookmark - PAC 2024
    reports a heading without a bookmark as a quality issue (ROADMAP B-14).
    A plain DrawTextCenter would only be a paragraph in the structure tree. }
  Report.DrawHeading(1, Options.Title);

  // Subtitle, left-aligned like the H1 above it
  Report.SetFont(SansFont, 12);
  Report.FontStyle := [];
  Report.TextColor := clBlack;
  Report.DrawText(0, Report.CurrentY,
    Options.Company + '  |  ' + ReportDate);
  Report.MoveToNextLine(800);

  // Decorative line
  if Options.Colors then
  begin
    Report.DrawLine(500, Report.CurrentY,
                    Report.PageWidth - 500, Report.CurrentY,
                    4, $00AA5500);
    Report.MoveToNextLine(600);
  end
  else
  begin
    Report.DrawLine(500, Report.CurrentY,
                    Report.PageWidth - 500, Report.CurrentY,
                    4, clBlack);
    Report.MoveToNextLine(600);
  end;

  // Introduction text (two-column)
  Report.SetFont(SansFont, 10);
  Report.FontStyle := [];
  Report.TextColor := clBlack;

  Report.Columns2(
    500,   // gap between columns
    'This list contains all orders for the first quarter of 2026. ' +
    'Please review the quantities and prices carefully before ' +
    'further processing.',
    'The data was exported automatically from the ERP system. ' +
    'For questions please contact the accounts department.');

  Report.MoveToNextLine(600);
  Report.RestoreLayout;

  // ---- Invoice table ----
  Report.DrawHeading(2, 'Orders');
  DrawInvoiceTable(Report, Options, Items);

  // ---- Summary ----
  { Inline runs: the coordinate-less overloads advance CurrentX on the same
    line and share one BlockId, so the tagged export emits ONE P with the bold
    label as a nested Span. The coordinate overloads DrawText(X, Y, ...) would
    make two standalone P elements out of these two halves (ROADMAP B-3). }
  Report.MoveToNextLine(1000);
  Report.SaveLayout;
  Report.SetFont(SansFont, 10);
  Report.TextColor := clBlack;
  Report.CurrentX := 0;
  Report.DrawStrong('Note:');
  Report.DrawText('  All prices are exclusive of applicable taxes.');
  Report.MoveToNextLine(600);
  Report.RestoreLayout;
end;

{ ============================================================
  BuildReport - central build routine
  ============================================================ }
function BuildReport(const Options: TReportOptions;
  const Items: TDtoInvoiceRowDynArray): TGDIPages;
begin
  Result := TGDIPages.Create(nil);
  try
    { Tagged export (PDF/UA): this also selects the font mode - embedded
      TrueType instead of the viewer's base-14 faces - so it has to be set
      BEFORE anything is drawn, because the export font flags decide which
      metrics the layout is measured with. The faces are embedded as subsets
      on every platform (ROADMAP R-12, R-15). }
    Result.ExportPdfTagged   := True;
    Result.ExportPdfLanguage := 'en';
    Result.UseOutlines       := True;  // PDF/UA: one bookmark per heading
    // asked afterwards, so the names match the mode just selected
    Result.GetExportFonts(SansFont, SerifFont, MonoFont);
    DefineHeadingFormats(Result);
    // --- Page format ---
    Result.PaperSize  := psA4;
    Result.Orientation := poPortrait;

    // Margins in mm x 100 (mORMot works internally in 1/100 mm)
    Result.MarginLeft   := 1500;  // 15 mm
    Result.MarginRight  := 1500;
    Result.MarginTop    := 2000;  // 20 mm
    Result.MarginBottom := 2000;

    // --- Metadata (for PDF export) ---
    Result.Title   := Options.Title;
    Result.Author  := 'mORMot2 Demo';
    Result.Subject := Options.Company;

    // SetHeader/SetFooter are rendered by the engine on every page
    if Options.Header then
      Result.SetHeader(Options.Company + '   |   ' + Options.Title);
    if Options.Footer then
      Result.SetFooter('Created: ' + ReportDate +
        '   Page {#} of {total}');

    // --- Begin first page ---
    Result.NewPage;

    // Report content
    DrawReportBody(Result, Options, Items);

    // Finalise last page
    Result.EndDoc;

  except
    Result.Free;
    raise;
  end;
end;

procedure ExportReport(const Options: TReportOptions; const FileName: TFileName);
var
  Items: TDtoInvoiceRowDynArray;
  Report: TGDIPages;
begin
  ReadInvoiceData(Items);
  Report := BuildReport(Options, Items);
  try
    // ExportPDF uses mormot.ui.pdf (cross-platform)
    Report.ExportPDF(FileName,
      False,  // no password protection
      False,  // no encryption
      Options.Title,
      Options.Company);
  finally
    Report.Free;
  end;
end;

{ ============================================================
  Batch mode:  mormot_demo --export [<file.pdf>]
  - builds and exports the same report as the GUI action, without showing
    the window, so the demo can be checked automatically
  ============================================================ }
function BatchExportFile(out FileName: TFileName): boolean;
var
  i: Integer;
  compiler: RawUtf8;
begin
  result := false;
  FileName := '';
  for i := 1 to ParamCount do
    if ParamStr(i) = '--export' then
    begin
      if i < ParamCount then
        FileName := ParamStr(i + 1)
      else
      begin
        // <demo>_<os>_<cpu>_<compiler>.pdf next to the executable, as the
        // console demos write it
        compiler := StringReplaceAll(COMPILER_VERSION,
          [' 32 bit', '', ' 64 bit', '']);
        FileName := Executable.ProgramFilePath + Utf8ToString(LowerCase('mormot_demo_' +
          ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' + CPU_ARCH_TEXT + '_' +
          StringReplaceAll(compiler, ' ', '-') + '.pdf'));
      end;
      result := true;
      exit;
    end;
end;

end.
