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

begin
  RequireDerivedFormResource := True;
  Application.Title:='mORMot2 Report Demo';
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
