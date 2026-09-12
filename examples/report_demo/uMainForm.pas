unit uMainForm;

{$mode objfpc}{$H+}

{ ============================================================
  mORMot2 - TGDIPages Report Demo (Lazarus / FPC)
  Demonstrates typical usage of mormot.ui.report.pas:
    - Page headers and footers
    - Multi-column text
    - Tables with ruled lines
    - Graphical elements (lines, rectangles)
    - PDF export
    - Print preview (Windows: native; Linux/macOS: PDF viewer)
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

    { Draws the page header on every page }
    procedure DrawPageHeader(Report: TGDIPages);

    { Draws the page footer on every page }
    procedure DrawPageFooter(Report: TGDIPages);

    { Draws the main content area (table, paragraphs, etc.) }
    procedure DrawReportBody(Report: TGDIPages);

    { Helper: draws a sample data table }
    procedure DrawSampleTable(Report: TGDIPages);

    procedure Log(const Msg: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  Printers,   // for TPrinter
  mormot.core.base,
  mormot.core.text,
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
    Result.ExportPdfEmbeddedTTF := False;
    Result.GetExportFonts(SansFont, SerifFont, MonoFont);
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

    // --- Begin first page ---
    Result.NewPage;

    // Set up header (printed on every page)
    if chkHeader.Checked then
      DrawPageHeader(Result);

    // Set up footer (printed on every page)
    if chkFooter.Checked then
      DrawPageFooter(Result);

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
  DrawPageHeader
  ============================================================ }
procedure TMainForm.DrawPageHeader(Report: TGDIPages);
begin
  // SaveLayout / RestoreLayout preserves the current state
  Report.SaveLayout;
  try
    // Font for header area
    Report.SetFont(SansFont, 10);
    Report.FontStyle := [fsBold];
    Report.TextColor := clNavy;

    // Left: company name
    Report.DrawText(0, 0, edtCompany.Text);

    // Right: title right-aligned
    Report.DrawTextRight(0, 0, edtTitle.Text);

    // Separator line below the header
    Report.DrawLine(0, 800, Report.PageWidth, 800, 2, clNavy);

    // Advance past the header (at least 10mm)
    Report.MoveToNextLine(1000);
  finally
    Report.RestoreLayout;
  end;
end;

{ ============================================================
  DrawPageFooter
  ============================================================ }
procedure TMainForm.DrawPageFooter(Report: TGDIPages);
begin
  Report.SaveLayout;
  try
    Report.SetFont(SansFont, 8);
    Report.FontStyle := [];
    Report.TextColor := clGray;

    // Separator line above the footer
    Report.DrawLine(0, Report.PageHeight - 300,
                    Report.PageWidth, Report.PageHeight - 300, 1, clGray);

    // Left: creation date — use mORMot NowToString for ISO date/time
    Report.DrawTextAt(0, Report.PageHeight - 250,
                      'Created: ' + DateToStr(Now));

    // Right: page number
    Report.DrawTextRight(0, Report.PageHeight - 250,
                         'Page ' + IntToStr(Report.CurrentPageIndex) +
                         ' of {total}');
  finally
    Report.RestoreLayout;
  end;
end;

{ ============================================================
  DrawReportBody
  ============================================================ }
procedure TMainForm.DrawReportBody(Report: TGDIPages);
begin
  // ---- Cover area ----
  // IMPORTANT: all Y positions are RELATIVE to Report.CurrentY (set by DrawPageHeader)
  // Do not use absolute positions like Y=500!
  Report.SaveLayout;

  // Large title — RELATIVE to CurrentY
  Report.SetFont(SansFont, 18);
  Report.FontStyle  := [fsBold];
  Report.TextColor  := clNavy;
  Report.DrawTextCenter(0, Report.CurrentY, edtTitle.Text);
  Report.MoveToNextLine(1200);

  // Subtitle
  Report.SetFont(SansFont, 12);
  Report.FontStyle := [];
  Report.TextColor := clBlack;
  Report.DrawTextCenter(0, Report.CurrentY,
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
  DrawSampleTable(Report);

  // ---- Summary ----
  Report.MoveToNextLine(1000);
  Report.SaveLayout;
  Report.SetFont(SansFont, 10);
  Report.FontStyle := [fsBold];
  Report.TextColor := clBlack;
  Report.DrawText(0, Report.CurrentY, 'Note:');
  Report.FontStyle := [];
  Report.DrawText(2000, Report.CurrentY,
    '  All prices are exclusive of applicable taxes.');
  Report.RestoreLayout;
end;

{ ============================================================
  DrawSampleTable – table with borders and alternating rows
  ============================================================ }
procedure TMainForm.DrawSampleTable(Report: TGDIPages);
const
  COL_NR      = 1000;
  COL_ARTICLE = 7000;
  COL_QTY     = 2000;
  COL_PRICE   = 2000;
  ROW_HEIGHT  = 650;
var
  Data: array of TDemoRow;
  i:    Integer;
  x, y: Integer;
  Total: Currency;
  RowColor: TColor;
begin
  Data := GetDemoData;
  Total := 0;

  // ---------- Table header ----------
  Report.SaveLayout;
  Report.SetFont(SansFont, 10);
  Report.FontStyle  := [fsBold];
  Report.TextColor  := clWhite;

  y := Report.CurrentY;
  x := 0;

  // Background rectangle for header
  if chkColors.Checked then
    Report.DrawFilledRect(x, y, Report.PageWidth, y + ROW_HEIGHT, $00AA5500)
  else
    Report.DrawFilledRect(x, y, Report.PageWidth, y + ROW_HEIGHT, clNavy);

  // Column titles
  Report.DrawTextAt(x + 50,           y + 80, '#');
  Report.DrawTextAt(x + COL_NR + 50,  y + 80, 'Article');
  Report.DrawTextRight(x + COL_NR + COL_ARTICLE,           y + 80, 'Qty');
  Report.DrawTextRight(x + COL_NR + COL_ARTICLE + COL_QTY, y + 80, 'Price');

  Report.MoveToNextLine(ROW_HEIGHT);
  Report.RestoreLayout;

  // ---------- Data rows ----------
  for i := 0 to High(Data) do
  begin
    // Check for page break
    if Report.CurrentY + ROW_HEIGHT > Report.PageHeight - 2500 then
    begin
      Report.NewPage;
      if chkHeader.Checked then DrawPageHeader(Report);
      if chkFooter.Checked then DrawPageFooter(Report);
    end;

    y := Report.CurrentY;
    x := 0;

    // Alternating row colour
    if chkGrid.Checked then
    begin
      if Odd(i) then
        RowColor := $00F0F0FF
      else
        RowColor := clWhite;
      Report.DrawFilledRect(x, y, Report.PageWidth, y + ROW_HEIGHT, RowColor);
    end;

    // Cell content
    Report.SaveLayout;
    Report.SetFont(SansFont, 9);
    Report.FontStyle := [];
    Report.TextColor := clBlack;

    Report.DrawTextAt(x + 50,           y + 70, IntToStr(Data[i].Nr));
    Report.DrawTextAt(x + COL_NR + 50,  y + 70, Data[i].Article);
    Report.DrawTextRight(
      x + COL_NR + COL_ARTICLE, y + 70,
      IntToStr(Data[i].Quantity));
    Report.DrawTextRight(
      x + COL_NR + COL_ARTICLE + COL_QTY, y + 70,
      FormatFloat('#,##0.00', Data[i].Price));

    Total := Total + Data[i].Quantity * Data[i].Price;

    Report.RestoreLayout;
    Report.MoveToNextLine(ROW_HEIGHT);

    // Horizontal separator line
    if chkGrid.Checked then
      Report.DrawLine(0, Report.CurrentY,
                      Report.PageWidth, Report.CurrentY, 1, clSilver);
  end;

  // ---------- Totals row ----------
  Report.MoveToNextLine(100);
  y := Report.CurrentY;

  Report.DrawLine(0, y, Report.PageWidth, y, 2, clBlack);
  Report.MoveToNextLine(50);
  y := Report.CurrentY;

  Report.SaveLayout;
  Report.SetFont(SansFont, 10);
  Report.FontStyle  := [fsBold];
  Report.TextColor  := clBlack;

  Report.DrawTextAt(0, y + 80, 'Total:');
  Report.DrawTextRight(
    COL_NR + COL_ARTICLE + COL_QTY, y + 80,
    FormatFloat('#,##0.00', Total));

  Report.MoveToNextLine(ROW_HEIGHT);
  Report.DrawLine(0, Report.CurrentY, Report.PageWidth, Report.CurrentY,
                  3, clBlack);
  Report.RestoreLayout;
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

procedure TMainForm.actExportPDFExecute(Sender: TObject);
var
  Report:  TGDIPages;
  PdfFile: string;
begin
  SaveDialog1.Filter      := 'PDF Document (*.pdf)|*.pdf';
  SaveDialog1.DefaultExt  := 'pdf';
  // DateToString8 (mORMot) returns 'YYYYMMDD' — preferred over FormatDateTime
  SaveDialog1.FileName    := 'report_' +
    Utf8ToString(DateToStr(Now)) + '.pdf';

  if not SaveDialog1.Execute then Exit;

  PdfFile := SaveDialog1.FileName;
  Log('Exporting PDF: ' + PdfFile + '...');

  Report := BuildReport;
  try
    // ExportPDF uses mormot.ui.pdf (cross-platform)
    Report.ExportPDF(PdfFile,
      False,  // no password protection
      False,  // no encryption
      edtTitle.Text,
      edtCompany.Text);
    Log('PDF saved: ' + PdfFile);
    ShowMessage('PDF successfully saved:'#13#10 + PdfFile);
  finally
    Report.Free;
  end;
end;

procedure TMainForm.actCloseExecute(Sender: TObject);
begin
  Close;
end;

end.
