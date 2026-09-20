program mormot_report_demo;

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
  // mormot_report_demo --export <file.pdf>: build and export, then quit
  if BatchExportFile(PdfFile) then
  begin
    MainForm.ExportToFile(PdfFile);
    WriteLn('PDF exported: ', PdfFile);
    exit;
  end;
  Application.Run;
end.
