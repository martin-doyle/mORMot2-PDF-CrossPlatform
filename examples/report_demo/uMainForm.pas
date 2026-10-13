unit uMainForm;

{ ============================================================
  mORMot2 - TGDIPages Report Demo (Lazarus / FPC)
  Demonstrates typical usage of mormot.pdf.report.pas:
    - Running page headers and footers (SetHeader/SetFooter)
    - Multi-column text
    - Tables via TTableLayout (auto page break, repeated header row)
    - Graphical elements (lines, rectangles)
    - Tagged PDF export (PDF/UA): headings, bookmarks, table structure
    - Print preview (Windows: native; Linux/macOS: PDF viewer)
    - Batch export without the GUI:  report_demo --export out.pdf
  The report itself is built in uReport.pas; this form only collects the
  options from its controls.
  ============================================================ }

interface

{$I mormot.defines.inc}

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  StdCtrls, ExtCtrls, ComCtrls, Menus, ActnList,
  // mORMot2 UI
  mormot.pdf.report,         // TGDIPages
  mormot.pdf.report.preview, // ShowReportPreview, PrintReport
  uReport;

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
    { The report options as the controls show them }
    function Options: TReportOptions;

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
  Caption := REPORT_CREATOR;
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
  Report := BuildReport(Options);
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
  Report := BuildReport(Options);
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
