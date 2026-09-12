unit uMainForm;

interface

{$I mormot.defines.inc}
uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, Menus, ActnList,
  mormot.core.os,
  mormot.orm.core,
  mormot.rest.sqlite3,
  // mORMot2 UI
  mormot.ui.report, // TGDIPages (includes PDF export via ExportPdfStream)
  data,
  server;

type

  { TMainForm }

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
    procedure FormDestroy(Sender: TObject);

  private
    Client: TRestClientDB;
    Model: TOrmModel;
    { Builds the report and returns a TGDIPages object.
      The caller is responsible for freeing it. }
    function BuildReport: TGDIPages;

    { Draws the main content area (table, paragraphs, etc.) }
    procedure DrawReportBody(Report: TGDIPages);

    { Draws the invoice table from ORM data }
    procedure DrawInvoiceTable(Report: TGDIPages);

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

const
  // Column widths (1/100mm): # + OrderNo + Customer + Date + Amount = 18000 (A4 – 2×15mm)
  INVOICE_TABLE: TTableLayout = (
    ColumnWidths:      [1000, 2500, 7000, 2200, 5300];
    ColumnAligns:      [tcaRight, tcaLeft, tcaLeft, tcaRight, tcaRight];
    HeaderFontName:    '';         // inherit current document font
    HeaderFontSize:    0;
    HeaderFontStyle:   [fsBold];
    HeaderBkColor:     $00AA5500; // matches the decorative accent colour
    BodyFontName:      '';
    BodyFontSize:      0;
    BodyFontStyle:     [];
    BodyBkColor:       clWhite;
    AlternateRowColor: $00F0F0FF; // light blue stripe on odd rows
  );

var
  SansFont: String;
  SerifFont: String;
  MonoFont: String;

{ ============================================================
  TMainForm
  ============================================================ }

procedure TMainForm.FormCreate(Sender: TObject);
var
  db: TFileName;
begin
  Caption := 'mORMot2 Report Demo';
  edtTitle.Text   := 'Order List Q1/2026';
  edtCompany.Text := 'Sample Corp Inc.';
  StatusBar1.SimpleText := 'Ready.';
  db := Executable.ProgramFilePath + '../../data/' + Executable.ProgramName + '.db';
  Model := CreateModel;
  Client := TRestClientDB.Create(Model, nil, db, TDemoServer, false, '');
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

    // SetHeader/SetFooter are rendered by the engine on every page
    if chkHeader.Checked then
      Result.SetHeader(edtCompany.Text + '   |   ' + edtTitle.Text);
    if chkFooter.Checked then
      Result.SetFooter('Created: ' + DateToStr(Now) + '   Page {#} of {total}');

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
  DrawReportBody
  ============================================================ }
procedure TMainForm.DrawReportBody(Report: TGDIPages);
begin
  // ---- Cover area ----
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

  // ---- Invoice table ----
  DrawInvoiceTable(Report);

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
  DrawInvoiceTable – order table from ORM data (uses TTableLayout)
  ============================================================ }
procedure TMainForm.DrawInvoiceTable(Report: TGDIPages);
var
  Items: TDtoInvoiceRowDynArray;
  Count, i: Integer;
  y: Integer;
  Total: Currency;
begin
  Count := TDemoServer(Client.Server).GetInvoiceData(Items);
  Total := 0;

  // Set the body font before BeginTable so the layout inherits it (FontName = '').
  Report.SetFont(SansFont, 9);

  // TTableLayout handles column widths, alignment, header background, and alternating
  // row colours automatically. DrawTableRow triggers page breaks as needed.
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

  // ---------- Totals row ----------
  Report.MoveToNextLine(100);
  y := Report.CurrentY;

  Report.DrawLine(0, y, Report.PageWidth, y, 2, clBlack);
  Report.MoveToNextLine(50);
  y := Report.CurrentY;

  Report.SaveLayout;
  Report.SetFont(SansFont, 10);
  Report.FontStyle := [fsBold];
  Report.TextColor := clBlack;

  Report.DrawTextAt(0, y + 80, 'Total:');
  // Right-align at page right margin (X=0 means right margin in DrawTextRight)
  Report.DrawTextRight(0, y + 80, FormatFloat('#,##0.00 EUR', Total));

  Report.MoveToNextLine(650);
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
    FormatDateTime('yyyymmdd', Now) + '.pdf';

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

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  Client.Free;
  Model.Free;
end;

end.
