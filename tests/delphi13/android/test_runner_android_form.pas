/// FMX host for the PDF test suites on Android, where no console exists
// - the same suites as ../../test_runner.lpr; output goes to the memo, to
// logcat (tag 'pdf-tests') and to LOG_NAME in the app's documents folder,
// where the test PDFs go as well
// - started with the boolean intent extra 'autorun' (run-emulator.cmd -Run),
// the suites run without a tap
unit test_runner_android_form;

interface

{$I mormot.defines.inc}
{$I test_defines.inc}

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  FMX.Controls,
  FMX.Forms,
  FMX.Memo,
  FMX.StdCtrls,
  FMX.Types,
  mormot.core.base;

const
  /// the run's full output, its last line 'RESULT: ...' - read by
  // run-emulator.ps1, which waits for that line
  LOG_NAME = 'test_runner_android.log';

type
  TTestForm = class(TForm)
  private
    fStatus: TLabel;
    fStart: TButton;
    fOutput: TMemo;
    fPending: string;
    fTimer: TTimer;
    fAutoRunChecked: boolean;
    procedure StartTests(Sender: TObject);
    procedure FlushOutput(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure AppendOutput(const Text: string);
    procedure TestsFinished(const Summary: string; Success: boolean);
  end;

var
  TestForm: TTestForm;

implementation

uses
  {$ifdef OSANDROID}
  Posix.Dlfcn,
  Androidapi.Log,
  Androidapi.Helpers,
  Androidapi.JNI.GraphicsContentViewText,
  Androidapi.JNI.JavaTypes,
  {$endif OSANDROID}
  mormot.core.log,
  mormot.pdf.types,
  mormot.lib.core,
  mormot.lib.freetype,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.test,
  test_pdf_crossplatform,
  test_pdf_smoke,
  test_pdf_subset,
  test_pdf_pdfa
  {$ifdef PDF_HASVCLCANVAS},
  test_report_crossplatform,
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

  TRunnerThread = class(TThread)
  private
    fForm: TTestForm;
    fLog: RawUtf8;
    procedure Output(const Value: RawUtf8);
  protected
    procedure Execute; override;
  public
    constructor Create(Form: TTestForm);
  end;

procedure TIntegrationTests.TestPDF;
begin
  AddCase([TPdfCrossPlatTests, TPdfSmokeTests, TPdfSubsetTests,
    TPdfSubsetEngineTests, TPdfATests]);
end;

{$ifdef PDF_HASVCLCANVAS}
procedure TIntegrationTests.TestReport;
begin
  AddCase([TReportTests]);
end;

procedure TIntegrationTests.TestStructuredReport;
begin
  AddCase([TPageCoordinateTests, TCoordinateTests]);
end;
{$endif PDF_HASVCLCANVAS}

/// the backend state the suites depend on: without FreeType no platform is
// registered, and most tests stop on a nil interface
function PlatformInfo: RawUtf8;
{$ifdef OSANDROID}
var
  h: NativeUInt;
{$endif OSANDROID}
begin
  result := FormatUtf8('FreeType loaded: %, platform registered: %' + CRLF,
    [BOOL_STR[LoadFreeType], BOOL_STR[FontPlatformRegistered]]);
  {$ifdef OSANDROID}
  if not FreeType.Loaded then
  begin
    h := dlopen('libfreetype.so', RTLD_NOW);
    if h = 0 then
      Append(result, ['dlopen(libfreetype.so): ', RawUtf8(dlerror), CRLF])
    else
      Append(result, ['dlopen(libfreetype.so) works - a symbol is missing', CRLF]);
  end;
  {$endif OSANDROID}
end;

function LogFileName: TFileName;
begin
  result := TPath.Combine(TPath.GetDocumentsPath, LOG_NAME);
end;


{ TRunnerThread }

constructor TRunnerThread.Create(Form: TTestForm);
begin
  inherited Create(true);
  fForm := Form;
  FreeOnTerminate := true;
end;

procedure TRunnerThread.Execute;
var
  tests: TSynTestsLogged;
  success: boolean;
  assertions, failed, i: integer;
  summary: RawUtf8;
begin
  success := false;
  tests := nil;
  Output(PlatformInfo);
  // as TSynTests.RunAsConsole does - mORMot logs every raised exception, and
  // an unconfigured family crashed in TSynLog.FillInfo on Android; the log
  // file goes next to LOG_NAME, the app folder being read-only
  RunFromSynTests := true;
  with TSynLogTestLog.Family do
  begin
    PerThreadLog := ptIdentifiedInOneFile;
    HighResolutionTimestamp := true;
    DestinationPath := TPath.GetDocumentsPath;
    Level := LOG_FILTER[lfExceptions]; // better be set last
  end;
  try
    try
      tests := TIntegrationTests.Create('mORMot2 PDF and Report Tests');
      // the app folder is read-only on Android: the test PDFs go here
      tests.WorkDir := TPath.GetDocumentsPath;
      tests.CustomOutput := Output;
      success := tests.Run;
      assertions := tests.Assertions;
      failed := tests.AssertionsFailed;
      // the console runner shows each exception through GetLastExceptionText,
      // which is empty here: list what AddFailed() kept instead
      if tests.FailedCount > 0 then
      begin
        Output(CRLF + 'Failures:' + CRLF);
        for i := 0 to tests.FailedCount - 1 do
          with tests.Failed[i] do
            Output(FormatUtf8('- %: %' + CRLF, [IdentTestName, Error]));
      end;
      summary := FormatUtf8('RESULT: % - % assertions, % failed, % failures',
        [BOOL_STR[success], assertions, failed, tests.FailedCount]);
    except
      on E: Exception do
        summary := FormatUtf8('RESULT: false - %: %', [E.ClassName, E.Message]);
    end;
  finally
    tests.Free;
  end;
  Output(CRLF + summary + CRLF);
  FileFromString(fLog, LogFileName);
  System.Classes.TThread.Synchronize(nil,
    procedure
    begin
      fForm.TestsFinished(Utf8ToString(summary), success);
    end);
end;

procedure TRunnerThread.Output(const Value: RawUtf8);
var
  form: TTestForm;
  text: string;
begin
  {$ifdef OSANDROID}
  __android_log_write(ANDROID_LOG_INFO, 'pdf-tests', pointer(Value));
  {$endif OSANDROID}
  Append(fLog, Value);
  form := fForm;
  text := Utf8ToString(Value);
  System.Classes.TThread.Queue(nil,
    procedure
    begin
      form.AppendOutput(text);
    end);
end;


{ TTestForm }

constructor TTestForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  // an app process has no TMPDIR, so mORMot's temporary files would go to
  // the missing /tmp: point spTemp to the app's cache folder
  SetSystemPath(spTemp, TPath.GetTempPath);
  Caption := 'mORMot2 PDF Tests';
  fStatus := TLabel.Create(self);
  fStatus.Parent := self;
  fStatus.Align := TAlignLayout.Top;
  fStatus.Height := 48;
  fStatus.Text := 'Ready';
  fStart := TButton.Create(self);
  fStart.Parent := self;
  fStart.Align := TAlignLayout.Top;
  fStart.Height := 56;
  fStart.Text := 'Run tests';
  fStart.OnClick := StartTests;
  fOutput := TMemo.Create(self);
  fOutput.Parent := self;
  fOutput.Align := TAlignLayout.Client;
  fOutput.ReadOnly := true;
  fOutput.WordWrap := false;
  fOutput.TextSettings.Font.Family := 'monospace';
  fOutput.TextSettings.Font.Size := 11;
  // the suites write line by line: collect and repaint a few times a second;
  // the first tick also looks for the autorun extra, once the form is shown
  fTimer := TTimer.Create(self);
  fTimer.Interval := 100;
  fTimer.OnTimer := FlushOutput;
end;

procedure TTestForm.StartTests(Sender: TObject);
begin
  fStart.Enabled := false;
  fStatus.Text := 'Tests running ...';
  fOutput.Text := '';
  fPending := '';
  DeleteFile(LogFileName); // the script waits for a new one
  TRunnerThread.Create(self).Start;
end;

procedure TTestForm.AppendOutput(const Text: string);
begin
  fPending := fPending + Text;
end;

procedure TTestForm.FlushOutput(Sender: TObject);
begin
  if not fAutoRunChecked then
  begin
    fAutoRunChecked := true;
    {$ifdef OSANDROID}
    if TAndroidHelper.Activity.getIntent.getBooleanExtra(
         StringToJString('autorun'), false) then
      StartTests(nil);
    {$endif OSANDROID}
  end;
  if fPending = '' then
    exit;
  fOutput.Text := fOutput.Text + fPending;
  fPending := '';
  fOutput.GoToTextEnd;
end;

procedure TTestForm.TestsFinished(const Summary: string; Success: boolean);
begin
  fStatus.Text := Summary;
  if Success then
    fStatus.FontColor := $FF008000 // TAlphaColors.Green
  else
    fStatus.FontColor := $FFFF0000; // TAlphaColors.Red
  fStatus.StyledSettings := fStatus.StyledSettings - [TStyledSetting.FontColor];
  AppendOutput('Log: ' + LogFileName + sLineBreak);
  FlushOutput(nil);
  fStart.Enabled := true;
end;

end.
