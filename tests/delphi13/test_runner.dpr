/// Delphi 13 IDE twin of ../test_runner.lpr - keep the uses clause and the
// test list in sync with it; the .lpr stays the source for FPC and the
// command line builds (build_delphi7.bat, build_delphi2010.bat)
program test_runner;

{$I mormot.defines.inc}
{$APPTYPE CONSOLE}
{$I test_defines.inc}

{$ifdef OSWINDOWS}
  {$apptype console}
{$endif OSWINDOWS}

// without PDF_HASVCLCANVAS (Delphi until R-20): layer 1 suites only
uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$ifdef FPC}
  Interfaces, // registers the LCL widgetset - Delphi has no counterpart
  {$endif FPC}
  SysUtils,
  {$ifdef PDF_HASVCLCANVAS}
  Graphics,
  {$endif PDF_HASVCLCANVAS}
  mormot.core.base,
  mormot.core.log,
  mormot.core.os,
  mormot.core.test,
  test_pdf_crossplatform,
  test_pdf_smoke,
  test_pdf_subset,
  test_pdf_pdfa,
  test_pdf_golden,
  test_pdf_images
  {$ifdef PDF_HASVCLCANVAS},
  test_report_crossplatform,
  test_report_golden,
  test_coordinates,
  test_report_coordinates
  {$endif PDF_HASVCLCANVAS};

type
  TIntegrationTests = class(TSynTestsLogged)
  published
    procedure TestPDF;
    {$ifdef PDF_HASVCLCANVAS}
    procedure TestReport;
    procedure TestStructuredReport;
    {$endif PDF_HASVCLCANVAS}
  end;

procedure TIntegrationTests.TestPDF;
begin
  AddCase([TPdfCrossPlatTests, TPdfSmokeTests, TPdfSubsetTests,
    TPdfSubsetEngineTests, TPdfATests, TPdfGoldenTests, TPdfImageRawTests]);
  {$ifdef PDF_HASVCLCANVAS}
  AddCase([TPdfImageGoldenTests]);
  {$endif PDF_HASVCLCANVAS}
end;

{$ifdef PDF_HASVCLCANVAS}
procedure TIntegrationTests.TestReport;
begin
  AddCase([TReportTests, TReportGoldenTests]);
end;

procedure TIntegrationTests.TestStructuredReport;
begin
  AddCase([TPageCoordinateTests, TCoordinateTests]);
end;
{$endif PDF_HASVCLCANVAS}

begin
  SetExecutableVersion(SYNOPSE_FRAMEWORK_VERSION);
  GoldenRecord := Executable.Command.Option('golden-record',
    'write the golden PDF baseline of this machine instead of comparing');
  TIntegrationTests.RunAsConsole('mORMot2 PDF and Report Tests',
    //LOG_VERBOSE +
    LOG_FILTER[lfExceptions] // + [sllErrors, sllWarning]
    ,[]); // WorkDir: next to the executable, where the test PDF goes
  {$ifdef FPC_X64MM}
  WriteHeapStatus(' ', 16, 8, {compileflags=}true);
  {$endif FPC_X64MM}
end.
