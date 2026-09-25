/// Unified test runner for all PDF and Report tests
program test_runner;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$else}
  {$APPTYPE CONSOLE}
{$endif FPC}

// Delphi (R-19): layer 1 only - the TCanvas bridge and the report engine
// are FPC-only until R-20, and so are their suites
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
  test_pdf_pdfa
  {$ifdef FPC},
  test_report_crossplatform,
  test_coordinates,
  test_report_coordinates
  {$endif FPC};

type
  TIntegrationTests = class(TSynTestsLogged)
  published
    procedure TestPDF;
    {$ifdef FPC}
    procedure TestReport;
    procedure TestStructuredReport;
    {$endif FPC}
  end;

procedure TIntegrationTests.TestPDF;
begin
  AddCase([TPdfCrossPlatTests, TPdfSmokeTests, TPdfSubsetTests,
    TPdfSubsetEngineTests, TPdfATests]);
end;

{$ifdef FPC}
procedure TIntegrationTests.TestReport;
begin
  AddCase([TReportTests]);
end;

procedure TIntegrationTests.TestStructuredReport;
begin
  AddCase([TPageCoordinateTests, TCoordinateTests]);
end;
{$endif FPC}

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
