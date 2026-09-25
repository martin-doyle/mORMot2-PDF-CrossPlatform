/// compile guard for the units R-19 brings to Delphi 7
// - build with tests\build_delphi7.bat tests\delphi7_core.dpr
// - uses only the core: no TCanvas bridge, no report engine, no FPImage
program delphi7_core;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  mormot.core.base,
  mormot.pdf.types,
  mormot.lib.uniscribe,
  mormot.pdf.gdi,
  mormot.ui.pdf;

begin
  writeln('delphi7_core: the R-19 units compile');
end.
