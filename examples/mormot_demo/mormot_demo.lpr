/// mORMot ORM Report Demo — mORMot2 PDF Cross-Platform
// A Lazarus GUI report whose data comes from a live SQLite database through
// the mORMot ORM: data.pas holds the TOrm classes, server.pas the service that
// returns the rows, uMainForm.pas the TGDIPages rendering.
//
// Worth noting:
// - a service method returns a DTO array, so data retrieval and rendering stay
//   separate — the report never touches the ORM
// - the invoice table is a TTableLayout; DrawTableRow paginates and repeats
//   the header row on its own
// - tagged PDF/UA export, switched on before the first drawing command
// - mormot_demo --export <file.pdf> builds and exports without showing the
//   window; TGDIPages is an LCL control, so this still needs a display
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
    // a Windows GUI executable has no stdout: WriteLn raises I/O error 105
    if IsConsole then
      WriteLn('PDF exported: ', PdfFile);
    exit;
  end;
  Application.Run;
end.

