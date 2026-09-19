/// Unified test runner for all PDF and Report tests
program test_runner;

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$ifdef FPC}
  Interfaces,
  {$endif FPC}
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.core.log,
  mormot.core.os,
  mormot.core.test,
  test_pdf_crossplatform,
  test_pdf_smoke,
  test_pdf_subset,
  test_report_crossplatform,
  test_coordinates,
  test_report_coordinates;

type
  TIntegrationTests = class(TSynTestsLogged)
  published
    procedure TestPDF;
    procedure TestReport;
    procedure TestStructuredReport;
  end;

procedure TIntegrationTests.TestPDF;
begin
  AddCase([TPdfCrossPlatTests, TPdfSmokeTests, TPdfSubsetTests]);
end;

procedure TIntegrationTests.TestReport;
begin
  AddCase([TReportTests]);
end;

procedure TIntegrationTests.TestStructuredReport;
begin
  AddCase([TPageCoordinateTests, TCoordinateTests]);
end;

begin
  SetExecutableVersion(SYNOPSE_FRAMEWORK_VERSION);
  TIntegrationTests.RunAsConsole('mORMot2 PDF and Report Tests',
    //LOG_VERBOSE +
    LOG_FILTER[lfExceptions] // + [sllErrors, sllWarning]
    ,[], Executable.ProgramFilePath + 'data');
  {$ifdef FPC_X64MM}
  WriteHeapStatus(' ', 16, 8, {compileflags=}true);
  {$endif FPC_X64MM}
end.
