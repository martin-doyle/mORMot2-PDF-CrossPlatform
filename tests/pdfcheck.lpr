/// Check tool of the mORMot Refactoring (docs/REFACTORING.md, Phase 0):
// runs the demos and compares their PDFs with a baseline.
// - pdfcheck run <fpc|d7|d2010> <outdir>   run the eight demos, copy their PDFs
// - pdfcheck compare <dirA> <dirB>         compare the PDFs, normalized
// - pdfcheck normalize <file.pdf> <out>    write one file normalized
// - pdfcheck struct <file.pdf>             the structure roles and their counts
// - pdfcheck fonts <file.pdf>              the fonts, as pdffonts lists them
// The exit code is 0 when everything ran and matched.
program pdfcheck;

{$I mormot.defines.inc}
{$APPTYPE CONSOLE}

uses
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.search,
  pdf_inspect;

type
  TDemo = record
    Dir, Exe: TFileName;
    Gui: boolean;
  end;

const
  DEMOS: array[0..7] of TDemo = (
    (Dir: 'pdf_demo';      Exe: 'pdf_demo_crossplat'; Gui: false),
    (Dir: 'report_demo';   Exe: 'report_demo';        Gui: true),
    (Dir: 'markdown_demo'; Exe: 'markdown_demo';      Gui: false),
    (Dir: 'mormot_demo';   Exe: 'mormot_demo';        Gui: true),
    (Dir: 'chinese_demo';  Exe: 'chinese_demo';       Gui: false),
    (Dir: 'rtl_demo';      Exe: 'rtl_demo';           Gui: false),
    (Dir: 'zugferd_demo';  Exe: 'zugferd_demo';       Gui: false),
    (Dir: 'layer1_demo';   Exe: 'layer1_demo';        Gui: false));

  /// the day report_demo and mormot_demo print, unless SOURCE_DATE_EPOCH is
  // set already: 2026-01-01, the same for the baseline and the change
  SOURCE_DATE = '1767225600';

var
  Problems: integer;

procedure Say(const Text: RawUtf8);
begin
  ConsoleWrite(Text);
end;

procedure Fail(const Text: RawUtf8);
begin
  ConsoleWrite(Text, ccLightRed);
  inc(Problems);
end;

function Utf8(const FileName: TFileName): RawUtf8;
begin
  result := StringToUtf8(FileName);
end;

// the repository root: this program is built to tests/bin/<cpu-os>/
function RootDir: TFileName;
begin
  result := ExpandFileName(Executable.ProgramFilePath + '..' + PathDelim + '..' +
    PathDelim + '..' + PathDelim);
end;

function DemoExe(const Compiler: RawUtf8; const Demo: TDemo): TFileName;
var
  cpuos: TFileName;
begin
  if Compiler = 'fpc' then
  begin
    // the same <cpu-os> as this program's own folder
    cpuos := ExtractFileName(ExcludeTrailingPathDelimiter(
      Executable.ProgramFilePath));
    result := RootDir + 'examples' + PathDelim + Demo.Dir + PathDelim + 'bin' +
      PathDelim + cpuos + PathDelim + Demo.Exe {$ifdef OSWINDOWS} + '.exe' {$endif};
  end
  else
    result := RootDir + 'bin' + PathDelim + Utf8ToString(Compiler) + PathDelim +
      Demo.Exe + PathDelim + Demo.Exe + '.exe';
end;

{$ifdef OSPOSIX}
// the environment of this process for RunCommand, SOURCE_DATE_EPOCH set to
// Epoch: RunCommand passes FPC's startup environment, which setenv() does not
// change, and an inherited entry would come first, even an empty one
function DemoEnvironment(const Epoch: RawUtf8): RawUtf8;
var
  i: integer;
  e: RawUtf8;
begin
  result := '';
  for i := 1 to GetEnvironmentVariableCount do
  begin
    e := StringToUtf8(GetEnvironmentString(i));
    if (e <> '') and
       not IdemPChar(pointer(e), 'SOURCE_DATE_EPOCH=') then
      result := result + e + #0;
  end;
  result := result + 'SOURCE_DATE_EPOCH=' + Epoch + #0;
end;
{$endif OSPOSIX}

// each demo runs in its own folder, where zugferd_demo and mormot_demo find
// their data whatever the compiler's output layout; a PDF written since the
// start is the demo's
procedure RunDemos(const Compiler: RawUtf8; const OutDir: TFileName);
var
  i, j, code, copied: integer;
  exe, cmd: TFileName;
  start: TUnixTime;
  pdfs: TFindFilesDynArray;
  output, epoch: RawUtf8;
begin
  if (Compiler <> 'fpc') and (Compiler <> 'd7') and (Compiler <> 'd2010') then
  begin
    Fail('unknown compiler ' + Compiler + ': fpc, d7 or d2010');
    exit;
  end;
  EnsureDirectoryExists(OutDir);
  // the demos print the date of SOURCE_DATE_EPOCH: the same PDF on any day
  epoch := StringToUtf8(GetEnvironmentVariable('SOURCE_DATE_EPOCH'));
  if epoch = '' then
    epoch := SOURCE_DATE;
  {$ifdef OSWINDOWS}
  SetSystemEnv('SOURCE_DATE_EPOCH', epoch); // inherited by RunRedirect
  {$endif OSWINDOWS}
  for i := 0 to high(DEMOS) do
  begin
    exe := DemoExe(Compiler, DEMOS[i]);
    if not FileExists(exe) then
    begin
      Fail(Utf8(DEMOS[i].Dir) + ': not built - ' + Utf8(exe));
      continue;
    end;
    cmd := '"' + exe + '"';
    if DEMOS[i].Gui then
      cmd := cmd + ' --export';
    start := UnixTimeUtc - 1;
    code := -1;
    {$ifdef OSPOSIX}
    // POSIX RunRedirect takes fpread() = 0 at EOF for more output and never
    // returns: the demo writes to our console instead
    ChDir(RootDir + 'examples' + PathDelim + DEMOS[i].Dir);
    output := '';
    code := RunCommand(cmd, true, DemoEnvironment(epoch));
    {$else}
    output := RunRedirect(cmd, @code, nil, INFINITE, true, '',
      RootDir + 'examples' + PathDelim + DEMOS[i].Dir);
    {$endif OSPOSIX}
    if code <> 0 then
    begin
      Fail(Utf8(DEMOS[i].Dir) + ': exit code ' + Int32ToUtf8(code));
      Say(output);
      continue;
    end;
    copied := 0;
    pdfs := FindFiles(ExtractFilePath(exe), '*.pdf');
    for j := 0 to high(pdfs) do
      if FileAgeToUnixTimeUtc(pdfs[j].Name) >= start then
        if CopyFile(pdfs[j].Name, OutDir + ExtractFileName(pdfs[j].Name),
             false) then
        begin
          Say(Utf8(DEMOS[i].Dir) + ': ' + Utf8(ExtractFileName(pdfs[j].Name)));
          inc(copied);
        end;
    if copied = 0 then
      Fail(Utf8(DEMOS[i].Dir) + ': wrote no PDF');
  end;
end;

procedure CompareDirs(const DirA, DirB: TFileName);
var
  a, b: TFindFilesDynArray;
  i, j: integer;
  found: boolean;
  na, nb, erra, errb, diff: RawUtf8;
  oa, ob: TPdfObjectSpans;
begin
  a := FindFiles(DirA, '*.pdf', '', [ffoExcludesDir, ffoSortByName]);
  b := FindFiles(DirB, '*.pdf', '', [ffoExcludesDir, ffoSortByName]);
  if a = nil then
    Fail('no PDF in ' + Utf8(DirA));
  for i := 0 to high(a) do
    if not FileExists(DirB + a[i].Name) then
      Fail('MISSING ' + Utf8(a[i].Name))
    else
    begin
      na := NormalizePdf(StringFromFile(DirA + a[i].Name), erra, oa);
      nb := NormalizePdf(StringFromFile(DirB + a[i].Name), errb, ob);
      if erra <> '' then
        Fail('BROKEN  ' + Utf8(DirA + a[i].Name) + ': ' + erra)
      else if errb <> '' then
        Fail('BROKEN  ' + Utf8(DirB + a[i].Name) + ': ' + errb)
      else if ComparePdfText(na, nb, oa, ob, diff) then
        Say('OK      ' + Utf8(a[i].Name))
      else
      begin
        Fail('DIFF    ' + Utf8(a[i].Name));
        Say(diff);
      end;
    end;
  for j := 0 to high(b) do
  begin
    found := false;
    for i := 0 to high(a) do
      if a[i].Name = b[j].Name then
      begin
        found := true;
        break;
      end;
    if not found then
      Fail('EXTRA   ' + Utf8(b[j].Name));
  end;
  Say(Int32ToUtf8(length(a)) + ' compared, ' + Int32ToUtf8(Problems) +
    ' problem(s)');
end;

// written even when broken: the text up to the error helps to find it
procedure NormalizeFile(const Source, Dest: TFileName);
var
  err: RawUtf8;
begin
  FileFromString(NormalizePdf(StringFromFile(Source), err), Dest);
  if err <> '' then
    Fail('BROKEN  ' + Utf8(Source) + ': ' + err);
end;

procedure Usage;
begin
  Say('usage:');
  Say('  pdfcheck run <fpc|d7|d2010> <outdir>');
  Say('  pdfcheck compare <dirA> <dirB>');
  Say('  pdfcheck normalize <file.pdf> <out>');
  Say('  pdfcheck struct <file.pdf>');
  Say('  pdfcheck fonts <file.pdf>');
  Problems := 1;
end;

var
  cmd: RawUtf8;
begin
  Problems := 0;
  cmd := StringToUtf8(ParamStr(1));
  if (cmd = 'run') and (ParamCount = 3) then
    RunDemos(StringToUtf8(ParamStr(2)),
      IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(3))))
  else if (cmd = 'compare') and (ParamCount = 3) then
    CompareDirs(IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(2))),
      IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(3))))
  else if (cmd = 'normalize') and (ParamCount = 3) then
    NormalizeFile(ParamStr(2), ParamStr(3))
  else if (cmd = 'struct') and (ParamCount = 2) then
    ConsoleWrite(PdfStructRoles(StringFromFile(ParamStr(2))), ccLightGray, true)
  else if (cmd = 'fonts') and (ParamCount = 2) then
    ConsoleWrite(PdfFonts(StringFromFile(ParamStr(2))), ccLightGray, true)
  else
    Usage;
  if Problems > 0 then
    ExitCode := 1;
end.
