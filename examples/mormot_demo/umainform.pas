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

    { Defines the H1/H2 formats used by DrawHeading }
    procedure DefineHeadingFormats(Report: TGDIPages);

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

const
  // Column widths (1/100mm): # + OrderNo + Customer + Date + Amount = 18000 (A4 – 2×15mm)
  INVOICE_TABLE: TTableLayout = (
    ColumnWidths:      [1000, 2500, 7000, 2200, 5300];
    ColumnAligns:      [tcaRight, tcaLeft, tcaLeft, tcaRight, tcaRight];
    HeaderFontName:    '';         // inherit current document font
    HeaderFontSize:    0;
    HeaderFontStyle:   [fsBold];
    { light grey behind black bold text: the dark accent colour used here
      before did not carry enough contrast (PAC), and report_demo uses the
      same scheme }
    HeaderBkColor:     $00E0E0E0;
    BodyFontName:      '';
    BodyFontSize:      0;
    BodyFontStyle:     [];
    BodyBkColor:       clWhite;
    AlternateRowColor: $00F0F0F0; // light grey stripe on odd rows
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

  // ---- Invoice table ----
  Report.DrawHeading(2, 'Orders');
  DrawInvoiceTable(Report);

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
  DrawInvoiceTable – order table from ORM data (uses TTableLayout)
  ============================================================ }
procedure TMainForm.DrawInvoiceTable(Report: TGDIPages);
var
  Items: TDtoInvoiceRowDynArray;
  Layout: TTableLayout;
  Count, i: Integer;
  Total: Currency;
begin
  Count := TDemoServer(Client.Server).GetInvoiceData(Items);
  Total := 0;

  Layout := INVOICE_TABLE;
  if chkColors.Checked then
    Layout.HeaderBkColor := $00D8C0A8;  // light blue-grey (BGR)
  if not chkGrid.Checked then
    Layout.AlternateRowColor := 0;      // 0 = no alternating row colour

  // Set the body font before BeginTable so the layout inherits it (FontName = '').
  Report.SetFont(SansFont, 9);

  // TTableLayout handles column widths, alignment, header background, and alternating
  // row colours automatically. DrawTableRow triggers page breaks as needed.
  Report.BeginTable(Layout);
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

  { The totals line is part of the table, so it is a row - and DrawTableFooter
    puts it into the table's TFoot group, which tells it apart from the data
    rows for assistive technology and gives it the header's look (R-14).
    Drawn below the table with DrawTextAt + DrawTextRight it would be two
    separate P elements, because only the coordinate-less overloads share one
    line and one tag. }
  Report.DrawTableFooter(['', 'Total', '', '', FormatFloat('#,##0.00 EUR', Total)]);
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

{ ============================================================
  Batch mode:  mormot_demo --export <file.pdf>
  - builds and exports the same report as the GUI action, without showing
    the window, so the demo can be checked automatically
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
        AFileName := 'mormot_demo.pdf';
      result := true;
      exit;
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
