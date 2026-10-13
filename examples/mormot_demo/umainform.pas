unit uMainForm;

{ The report is built in uReport.pas from the rows server.pas returns; this
  form only collects the options from its controls. }

interface

{$I mormot.defines.inc}
uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, Menus, ActnList,
  // mORMot2 UI
  mormot.pdf.report,         // TGDIPages
  mormot.pdf.report.preview, // ShowReportPreview, PrintReport
  server,
  uReport;

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

  private
    { The report options as the controls show them }
    function Options: TReportOptions;

    { Reads the rows and builds the report; the caller frees it }
    function BuildReportFromDatabase: TGDIPages;

    procedure Log(const Msg: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  mormot.core.base,
  mormot.core.datetime,
  mormot.core.unicode;

{ ============================================================
  TMainForm
  ============================================================ }

procedure TMainForm.FormCreate(Sender: TObject);
var
  Defaults: TReportOptions;
begin
  Caption := REPORT_CAPTION;
  Defaults := DefaultReportOptions;
  edtTitle.Text     := Utf8ToString(Defaults.Title);
  edtCompany.Text   := Utf8ToString(Defaults.Company);
  chkHeader.Checked := Defaults.Header;
  chkFooter.Checked := Defaults.Footer;
  chkGrid.Checked   := Defaults.Grid;
  chkColors.Checked := Defaults.Colors;
  StatusBar1.SimpleText := 'Ready.';
end;

function TMainForm.Options: TReportOptions;
begin
  Result.Title   := StringToUtf8(edtTitle.Text);
  Result.Company := StringToUtf8(edtCompany.Text);
  Result.Header  := chkHeader.Checked;
  Result.Footer  := chkFooter.Checked;
  Result.Grid    := chkGrid.Checked;
  Result.Colors  := chkColors.Checked;
end;

function TMainForm.BuildReportFromDatabase: TGDIPages;
var
  Items: TDtoInvoiceRowDynArray;
begin
  ReadInvoiceData(Items);
  Result := BuildReport(Options, Items);
end;

procedure TMainForm.Log(const Msg: string);
begin
  StatusBar1.SimpleText := Msg;
  Application.ProcessMessages;
end;

{ ============================================================
  Actions
  ============================================================ }
procedure TMainForm.actPreviewExecute(Sender: TObject);
var
  Report: TGDIPages;
begin
  Log('Building preview...');
  Report := BuildReportFromDatabase;
  try
    // ShowReportPreview opens the preview window (mormot.pdf.report.preview)
    ShowReportPreview(Report);
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
  Report := BuildReportFromDatabase;
  try
    PrintReport(Report);
  finally
    Report.Free;
  end;
  Log('Print complete.');
end;

procedure TMainForm.actExportPDFExecute(Sender: TObject);
var
  PdfFile: string;
begin
  SaveDialog1.Filter      := 'PDF Document (*.pdf)|*.pdf';
  SaveDialog1.DefaultExt  := 'pdf';
  // DateToIso8601 (mORMot) returns 'YYYYMMDD' - preferred over FormatDateTime
  SaveDialog1.FileName    := 'report_' +
    Utf8ToString(DateToIso8601(Now, {Expanded=}false)) + '.pdf';

  if not SaveDialog1.Execute then Exit;

  PdfFile := SaveDialog1.FileName;
  Log('Exporting PDF: ' + PdfFile + '...');
  ExportReport(Options, PdfFile);
  Log('PDF saved: ' + PdfFile);
  ShowMessage('PDF successfully saved:'#13#10 + PdfFile);
end;

procedure TMainForm.actCloseExecute(Sender: TObject);
begin
  Close;
end;

end.
