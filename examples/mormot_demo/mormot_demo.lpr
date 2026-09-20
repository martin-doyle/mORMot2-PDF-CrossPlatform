program mormot_demo;

{$I mormot.defines.inc}
uses
  {$I mormot.uses.inc}
  {$ifdef FPC}
  Interfaces,
  {$endif FPC}
  Forms,
  uMainForm;

{$R *.res}

var
  PdfFile: string;
begin
  {$ifdef FPC}
  RequireDerivedFormResource := True;
  Application.Scaled:=True;
  {$endif FPC}
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  // mormot_demo --export <file.pdf>: build and export, then quit
  if BatchExportFile(PdfFile) then
  begin
    MainForm.ExportToFile(PdfFile);
    WriteLn('PDF exported: ', PdfFile);
    exit;
  end;
  Application.Run;
end.

