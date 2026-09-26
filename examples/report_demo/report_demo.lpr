/// Report Engine Demo — mORMot2 PDF Cross-Platform
// A Lazarus GUI around TGDIPages: WYSIWYG preview, print and tagged PDF export
// from the form in uMainForm.pas.
//
// Worth noting:
// - the report is built once and rendered twice, to the preview and to the PDF,
//   because TGDIPages records draw commands instead of painting directly
// - TTableLayout with DrawTableHeader/DrawTableRow/DrawTableFooter produces a
//   real Table > THead|TBody|TFoot structure; the totals line is the TFoot row
// - SetHeader/SetFooter repeat on continuation pages and are tagged as artifacts
// - report_demo --export <file.pdf> builds and exports without showing
//   the window; TGDIPages is an LCL control, so this still needs a display
program report_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // LCL
  Forms,
  uMainForm;

{$R *.res}

var
  PdfFile: string;
begin
  RequireDerivedFormResource := True;
  Application.Title:='mORMot2 Report Demo';
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  // report_demo --export <file.pdf>: build and export, then quit
  if BatchExportFile(PdfFile) then
  begin
    MainForm.ExportToFile(PdfFile);
    WriteLn('PDF exported: ', PdfFile);
    exit;
  end;
  Application.Run;
end.
