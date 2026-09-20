unit uMainForm;

{$mode objfpc}{$H+}

{ ============================================================
  mORMot2 - TGDIPages Report Demo (Lazarus / FPC)
  Demonstrates typical usage of mormot.ui.report.pas:
    - Running page headers and footers (SetHeader/SetFooter)
    - Multi-column text
    - Tables via TTableLayout (auto page break, repeated header row)
    - Graphical elements (lines, rectangles)
    - Tagged PDF export (PDF/UA): headings, bookmarks, table structure
    - Print preview (Windows: native; Linux/macOS: PDF viewer)
    - Batch export without the GUI:  mormot_report_demo --export out.pdf
  ============================================================ }

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, Menus, ActnList,
  // mORMot2 UI
  mormot.ui.report;   // TGDIPages (includes PDF export via ExportPdfStream)

type
  TMainForm = class(TForm)
    // ToolBar
    ToolBar1: TToolBar;
    btnPreview: TToolButton;
    btnPrint:   TToolButton;
    btnPDF:     TToolButton;
    btnSep1:    TToolButton;
    btnClose:   TToolButton;
    // Status
    StatusBar1: TStatusBar;
    // Data panel
    pnlData: TPanel;
    lblTitle:   TLabel;
    edtTitle:   TEdit;
    lblCompany: TLabel;
    edtCompany: TEdit;
    grpOptions: TGroupBox;
    chkHeader:  TCheckBox;
    chkFooter:  TCheckBox;
    chkGrid:    TCheckBox;
    chkColors:  TCheckBox;
    // SaveDialog
    SaveDialog1: TSaveDialog;
    // Actions
    ActionList1:   TActionList;
    actPreview:    TAction;
    actPrint:      TAction;
    actExportPDF:  TAction;
    actClose:      TAction;

    procedure FormCreate(Sender: TObject);
    procedure actPreviewExecute(Sender: TObject);
    procedure actPrintExecute(Sender: TObject);
    procedure actExportPDFExecute(Sender: TObject);
    procedure actCloseExecute(Sender: TObject);

  private
    { Builds the report and returns a TGDIPages object.
      The caller is responsible for freeing it. }
    function BuildReport: TGDIPages;

    { Defines the H1/H2 formats used by DrawHeading }
    procedure DefineHeadingFormats(Report: TGDIPages);

    { Draws the main content area (table, paragraphs, etc.) }
    procedure DrawReportBody(Report: TGDIPages);

    { Helper: draws the sample data table }
    procedure DrawSampleTable(Report: TGDIPages);

    procedure Log(const Msg: string);
  public
    { Builds the report and writes it to AFileName - used by the GUI action
      and by the --export batch mode }
    procedure ExportToFile(const AFileName: string);
  end;

{ True when the command line asks for a batch export (--export <file>);
  the caller then runs ExportToFile instead of Application.Run }
function BatchExportFile(out AFileName: string): boolean;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  Printers,   // for TPrinter
  mormot.core.base,
  mormot.core.text,
  mormot.core.datetime,
  mormot.core.unicode;

{ ============================================================
  Constants / demo data
  ============================================================ }
const
  DEMO_ROWS = 20;


type
  TDemoRow = record
    Nr:       Integer;
    Article:  string;
    Quantity: Integer;
    Price:    Currency;
  end;
  TDemoRowArray = array of TDemoRow;

var
  SansFont: String;
  SerifFont: String;
  MonoFont: String;

{ Table layout for the order list. Built at runtime instead of as a typed
  constant: the [1000, ...] syntax for the dynamic array fields needs
  {$mode delphi}, and this unit is compiled in objfpc mode.
  Empty font names and size 0 inherit the document font set before BeginTable. }
function OrderTableLayout: TTableLayout;
begin
  // widths in 1/100 mm; 18000 = A4 portrait (21000) minus the 2 x 15 mm margins
  SetLength(Result.ColumnWidths, 4);
  Result.ColumnWidths[0] := 1200;   // #
  Result.ColumnWidths[1] := 10300;  // Article
  Result.ColumnWidths[2] := 2500;   // Qty
  Result.ColumnWidths[3] := 4000;   // Price
  SetLength(Result.ColumnAligns, 4);
  Result.ColumnAligns[0] := tcaRight;
  Result.ColumnAligns[1] := tcaLeft;
  Result.ColumnAligns[2] := tcaRight;
  Result.ColumnAligns[3] := tcaRight;
  Result.HeaderFontName    := '';
  Result.HeaderFontSize    := 0;
  Result.HeaderFontStyle   := [fsBold];
  Result.HeaderBkColor     := $00E0E0E0;
  Result.BodyFontName      := '';
  Result.BodyFontSize      := 0;
  Result.BodyFontStyle     := [];
  Result.BodyBkColor       := clWhite;
  Result.AlternateRowColor := $00F0F0F0;
end;

function GetDemoData: TDemoRowArray;
var
  i: Integer;
begin
  SetLength(Result, DEMO_ROWS);
  for i := 0 to DEMO_ROWS - 1 do
  begin
    Result[i].Nr       := i + 1;
    Result[i].Article  := FormatUtf8('Article-%', [i + 1]);
    Result[i].Quantity := (i + 1) * 3;
    Result[i].Price    := (i + 1) * 9.95;
  end;
end;

{ ============================================================
  TMainForm
  ============================================================ }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'mORMot2 Report Demo';
  edtTitle.Text   := 'Order List Q1/2026';
  edtCompany.Text := 'Sample Corp Inc.';
  StatusBar1.SimpleText := 'Ready.';
end;

procedure TMainForm.Log(const Msg: string);
begin
  StatusBar1.SimpleText := Msg;
  Application.ProcessMessages;
end;

{ ============================================================
  BuildReport – central build routine
  ============================================================ }
function TMainForm.BuildReport: TGDIPages;
begin
  Result := TGDIPages.Create(nil);
  try
    { Tagged export (PDF/UA): this also selects the font mode - embedded
      TrueType instead of the viewer's base-14 faces - so it has to be set
      BEFORE anything is drawn, because the export font flags decide which
      metrics the layout is measured with. On Linux/macOS the faces are
      embedded as subsets (ROADMAP R-12), on Windows as whole faces. }
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
    Result.Title   := edtTitle.Text;
    Result.Author  := 'mORMot2 Demo';
    Result.Subject := edtCompany.Text;

    { Running header/footer: the engine repeats them on every page, including
      the continuation pages that table pagination creates, and marks them as
      artifacts in the tagged export. Must be set before the first NewPage. }
    if chkHeader.Checked then
      Result.SetHeader(edtCompany.Text + '   |   ' + edtTitle.Text);
    if chkFooter.Checked then
      Result.SetFooter('Created: ' + DateToStr(Now) + '        Page {#} of {total}');

    // --- Begin first page ---
    Result.NewPage;

    // Report content
    DrawReportBody(Result);

    // Finalise last page
    Result.EndDoc;

  except
    Result.Free;
    raise;
  end;
end;

{ ============================================================
  DefineHeadingFormats – appearance of DrawHeading(1..2)
  ============================================================ }
procedure TMainForm.DefineHeadingFormats(Report: TGDIPages);
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
  DrawReportBody
  ============================================================ }
procedure TMainForm.DrawReportBody(Report: TGDIPages);
begin
  // ---- Cover area ----
  // IMPORTANT: all Y positions are RELATIVE to Report.CurrentY
  // Do not use absolute positions like Y=500!
  Report.SaveLayout;

  { DrawHeading writes an H1 structure element and a PDF bookmark - PAC 2024
    reports a heading without a bookmark as a quality issue (ROADMAP B-14).
    A plain DrawTextCenter would only be a paragraph in the structure tree. }
  Report.DrawHeading(1, edtTitle.Text);

  // Subtitle, left-aligned like the H1 above it
  Report.SetFont(SansFont, 12);
  Report.FontStyle := [];
  Report.TextColor := clBlack;
  Report.DrawText(0, Report.CurrentY,
    edtCompany.Text + '  |  ' + DateToStr(Now));
  Report.MoveToNextLine(800);

  // Decorative line
  if chkColors.Checked then
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

  // ---- Data table ----
  Report.DrawHeading(2, 'Order Items');
  DrawSampleTable(Report);

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
  DrawSampleTable – table via TTableLayout

  BeginTable/DrawTableHeader/DrawTableRow build a real Table > TR > TH|TD
  structure in the tagged PDF, break pages on their own and repeat the header
  row. Drawing the cells by hand (DrawTextAt per column) would look the same
  but leave a flat list of paragraphs for a screen reader.
  ============================================================ }
procedure TMainForm.DrawSampleTable(Report: TGDIPages);
var
  Data:   TDemoRowArray;
  Layout: TTableLayout;
  i:      Integer;
  Total:  Currency;
begin
  Data := GetDemoData;
  Total := 0;

  Layout := OrderTableLayout;
  if chkColors.Checked then
    Layout.HeaderBkColor := $00D8C0A8;  // light blue-grey (BGR)
  if not chkGrid.Checked then
    Layout.AlternateRowColor := 0;      // 0 = no alternating row colour

  // the table inherits this font: set it BEFORE BeginTable, which saves the layout
  Report.SetFont(SansFont, 9);
  Report.FontStyle := [];
  Report.TextColor := clBlack;

  Report.BeginTable(Layout);
  Report.DrawTableHeader(['#', 'Article', 'Qty', 'Price']);
  for i := 0 to High(Data) do
  begin
    Report.DrawTableRow([
      IntToStr(Data[i].Nr),
      Data[i].Article,
      IntToStr(Data[i].Quantity),
      FormatFloat('#,##0.00', Data[i].Price)]);
    Total := Total + Data[i].Quantity * Data[i].Price;
  end;
  { The totals line is part of the table, so it is a row - and DrawTableFooter
    puts it into the table's TFoot group, which tells it apart from the data
    rows for assistive technology and gives it the header's look (R-14).
    Drawn below the table with DrawText + DrawTextRight it would be two
    separate P elements, because only the coordinate-less overloads share one
    line and one tag. }
  Report.DrawTableFooter(['', 'Total', '', FormatFloat('#,##0.00', Total)]);
  Report.EndTable;

  Report.MoveToNextLine(300);
  Report.DrawLine(0, Report.CurrentY, Report.PageWidth, Report.CurrentY,
                  2, clBlack);
  Report.MoveToNextLine(300);
end;

{ ============================================================
  Actions
  ============================================================ }
procedure TMainForm.actPreviewExecute(Sender: TObject);
var
  Report: TGDIPages;
begin
  Log('Building preview...');
  Report := BuildReport;
  try
    // ShowPreviewForm opens the built-in preview window
    Report.ShowPreviewForm;
  finally
    Report.Free;
  end;
  Log('Preview closed.');
end;

procedure TMainForm.actPrintExecute(Sender: TObject);
var
  Report: TGDIPages;
begin
  if MessageDlg('Print report?', mtConfirmation,
                [mbYes, mbNo], 0) <> mrYes then Exit;
  Log('Printing...');
  Report := BuildReport;
  try
    Report.PrintPages(0, Report.PageCount - 1);
  finally
    Report.Free;
  end;
  Log('Print complete.');
end;

procedure TMainForm.ExportToFile(const AFileName: string);
var
  Report: TGDIPages;
begin
  Report := BuildReport;
  try
    // ExportPDF uses mormot.ui.pdf (cross-platform)
    Report.ExportPDF(AFileName,
      False,  // no password protection
      False,  // no encryption
      edtTitle.Text,
      edtCompany.Text);
  finally
    Report.Free;
  end;
end;

procedure TMainForm.actExportPDFExecute(Sender: TObject);
var
  PdfFile: string;
begin
  SaveDialog1.Filter      := 'PDF Document (*.pdf)|*.pdf';
  SaveDialog1.DefaultExt  := 'pdf';
  // DateToIso8601 (mORMot) returns 'YYYYMMDD' — preferred over FormatDateTime
  SaveDialog1.FileName    := 'report_' +
    Utf8ToString(DateToIso8601(Now, {Expanded=}false)) + '.pdf';

  if not SaveDialog1.Execute then Exit;

  PdfFile := SaveDialog1.FileName;
  Log('Exporting PDF: ' + PdfFile + '...');
  ExportToFile(PdfFile);
  Log('PDF saved: ' + PdfFile);
  ShowMessage('PDF successfully saved:'#13#10 + PdfFile);
end;

procedure TMainForm.actCloseExecute(Sender: TObject);
begin
  Close;
end;

{ ============================================================
  Batch mode:  mormot_report_demo --export <file.pdf>
  - builds and exports the same report as the GUI action, without showing
    the window, so the demo can be checked automatically (PDF size, pdffonts,
    rendering) like the console demos
  ============================================================ }
function BatchExportFile(out AFileName: string): boolean;
var
  i: Integer;
begin
  result := false;
  AFileName := '';
  for i := 1 to ParamCount do
    if ParamStr(i) = '--export' then
    begin
      if i < ParamCount then
        AFileName := ParamStr(i + 1)
      else
        AFileName := 'report_demo.pdf';
      result := true;
      exit;
    end;
end;

end.
