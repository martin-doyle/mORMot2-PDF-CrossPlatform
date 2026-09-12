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

begin
  {$ifdef FPC}
  RequireDerivedFormResource := True;
  Application.Scaled:=True;
  {$endif FPC}
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.

