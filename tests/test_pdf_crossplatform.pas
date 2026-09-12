/// Cross-platform PDF engine unit tests
// - tests IPdfPlatformFont, IPdfSystemFonts, IPdfPlatformDC contracts
// - tests TPdfDocument basic PDF generation on all platforms
// - migrated to TSynTestCase framework for mORMot2 compatibility
unit test_pdf_crossplatform;

{$ifdef FPC}
  {$mode delphi}
{$endif FPC}

interface

uses
  SysUtils,
  Classes,
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.os,
  mormot.core.test,
  mormot.pdf.types,
  {$ifndef MSWINDOWS}
  mormot.pdf.harfbuzz,  // registers PdfTextShaper when libharfbuzz is present
  mormot.pdf.freetype,  // ExtractSfntFromTtc + FreeType face validation
  {$endif MSWINDOWS}
  mormot.ui.pdf;

type
  /// Cross-platform PDF test cases
  TPdfCrossPlatTests = class(TSynTestCase)
  published
    procedure TestPlatformRegistration;
    procedure TestDCProvider;
    procedure TestFontEnumeration;
    procedure TestFontMetrics;
    procedure TestTextShaperAdvances;
    {$ifndef MSWINDOWS}
    procedure TestTtcFaceExtraction;
    {$endif MSWINDOWS}
    procedure TestFontData;
    procedure TestPdfDocumentCreate;
    procedure TestPdfMultiPage;
  end;

implementation

procedure TPdfCrossPlatTests.TestPlatformRegistration;
begin
  Check(PdfPlatformRegistered, 'RegisterPdfPlatform must be called in initialization');
  Check(PdfPlatformFont <> nil, 'PdfPlatformFont is nil');
  Check(PdfSystemFonts  <> nil, 'PdfSystemFonts is nil');
  Check(PdfPlatformDCProvider <> nil, 'PdfPlatformDCProvider is nil');
end;

procedure TPdfCrossPlatTests.TestDCProvider;
var
  dc: TPdfPlatformDC;
  dpi: integer;
begin
  dc := PdfPlatformDCProvider.CreateDC;
  Check(dc <> nil, 'CreateDC returned nil');
  dpi := PdfPlatformDCProvider.GetScreenLogPixels(dc);
  Check(dpi > 0, 'GetScreenLogPixels must be > 0');
  Check(dpi <= 600, 'GetScreenLogPixels must be <= 600 (sanity)');
  PdfPlatformDCProvider.DeleteDC(dc);
end;

procedure TPdfCrossPlatTests.TestFontEnumeration;
var
  dc: TPdfPlatformDC;
  list: TRawUtf8DynArray;
begin
  dc := PdfPlatformDCProvider.CreateDC;
  try
    PdfSystemFonts.EnumTrueTypeFonts(dc, list);
    Check(Length(list) > 0, 'EnumTrueTypeFonts must return at least one font');
  finally
    PdfPlatformDCProvider.DeleteDC(dc);
  end;
end;

procedure TPdfCrossPlatTests.TestFontMetrics;
var
  dc: TPdfPlatformDC;
  lf: TPdfLogFont;
  font: TPdfPlatformFontHandle;
  prev: TPdfPlatformFontHandle;
  tm: TPdfTextMetrics;
  otm: TPdfOutlineMetrics;
  abc: TPdfCharABCArray;
begin
  dc := PdfPlatformDCProvider.CreateDC;
  try
    FillChar(lf, SizeOf(lf), 0);
    lf.FaceName := 'Arial';
    lf.Height := -1000;
    lf.Weight := 400; // FW_NORMAL
    font := PdfPlatformFont.CreateFont(lf);
    if font = nil then
    begin
      // Arial not available — try DejaVu Sans (Linux) or system default
      lf.FaceName := 'DejaVu Sans';
      font := PdfPlatformFont.CreateFont(lf);
    end;
    if font = nil then
    begin
      Check(true, 'SKIP: no test font found on this system');
      exit;
    end;
    prev := PdfPlatformFont.SelectFont(dc, font);
    // Text metrics
    Check(PdfPlatformFont.GetTextMetrics(dc, tm), 'GetTextMetrics must succeed');
    Check(tm.tmAscent > 0, 'tmAscent must be > 0');
    Check(tm.tmDescent > 0, 'tmDescent must be > 0');
    Check(tm.tmHeight >= tm.tmAscent + tm.tmDescent - 10,
      'tmHeight should be >= ascent + descent (approx)');
    // Outline metrics
    Check(PdfPlatformFont.GetOutlineMetrics(dc, otm), 'GetOutlineMetrics must succeed');
    Check(otm.otmAscent > 0, 'otmAscent must be > 0');
    // ABC widths for ' '..'z'
    Check(PdfPlatformFont.GetCharABCWidths(dc, 32, 90, abc), 'GetCharABCWidths must succeed');
    Check(Length(abc) = 59, 'ABC widths: expected 59 entries (32..90)');
    // Space width should be > 0 for a normal font: the advance is the sum of
    // the three ABC members - abcB alone is the ink width, which is legitimately
    // 0 for a space since the glyph is blank
    Check(abc[0].abcA + integer(abc[0].abcB) + abc[0].abcC > 0,
      'Space advance width must be > 0');
    // Restore previous font
    if prev <> nil then
      PdfPlatformFont.SelectFont(dc, prev);
    PdfPlatformFont.DeleteFont(font);
  finally
    PdfPlatformDCProvider.DeleteDC(dc);
  end;
end;

procedure TPdfCrossPlatTests.TestTextShaperAdvances;
const
  // 'marhaba' = U+0645 U+0631 U+062D U+0628 U+0627, all spacing glyphs: none of
  // them may shape to a zero advance
  MARHABA: array[0..4] of WideChar = (
    #$0645, #$0631, #$062D, #$0628, #$0627);
  // fonts with Arabic contextual forms, in platform preference order
  ARABIC_FONTS: array[0..3] of RawUtf8 = (
    'Noto Naskh Arabic', 'Geeza Pro', 'Tahoma', 'DejaVu Sans');
var
  dc: TPdfPlatformDC;
  lf: TPdfLogFont;
  font, prev: TPdfPlatformFontHandle;
  glyphs: TWordDynArray;
  advances, offsets, clusters: TIntegerDynArray;
  i, f: integer;
begin
  if PdfTextShaper = nil then
  begin
    Check(true, 'SKIP: no IPdfTextShaper registered (libharfbuzz absent)');
    exit;
  end;
  dc := PdfPlatformDCProvider.CreateDC;
  try
    font := nil;
    for f := 0 to high(ARABIC_FONTS) do
    begin
      FillChar(lf, SizeOf(lf), 0);
      lf.FaceName := ARABIC_FONTS[f];
      lf.Height := -1000;
      lf.Weight := 400;
      font := PdfPlatformFont.CreateFont(lf);
      if font <> nil then
        break;
    end;
    if font = nil then
    begin
      Check(true, 'SKIP: no Arabic-capable font found on this system');
      exit;
    end;
    prev := PdfPlatformFont.SelectFont(dc, font);
    Check(PdfTextShaper.ShapeText(@MARHABA[0], length(MARHABA), font, true,
      glyphs, advances, offsets, clusters), 'ShapeText must succeed');
    Check(length(glyphs) > 0, 'ShapeText must return glyphs');
    Check(length(advances) = length(glyphs), 'one advance per glyph');
    for i := 0 to high(advances) do
    begin
      // a zero advance stacks every glyph on the same spot: this is exactly the
      // regression that made rtl_demo unreadable when the shaped glyphs were
      // missing from the font CMAP and their width came from the shaper
      Check(advances[i] > 0, 'shaped advance must be > 0');
      // and it must be a plausible 1000/em width, not a raw or mis-scaled value
      Check(advances[i] < 4000, 'shaped advance must be in 1000/em units');
    end;
    if prev <> nil then
      PdfPlatformFont.SelectFont(dc, prev);
    PdfPlatformFont.DeleteFont(font);
  finally
    PdfPlatformDCProvider.DeleteDC(dc);
  end;
end;

{$ifndef MSWINDOWS}
function FindAnyTtc(const ADir: string): TFileName;
var
  sr: TSearchRec;
begin
  result := '';
  if not DirectoryExists(ADir) then
    exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        continue;
      if sr.Attr and faDirectory <> 0 then
        result := FindAnyTtc(IncludeTrailingPathDelimiter(ADir) + sr.Name)
      else if LowerCase(ExtractFileExt(sr.Name)) = '.ttc' then
        result := IncludeTrailingPathDelimiter(ADir) + sr.Name;
      if result <> '' then
        exit;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

procedure TPdfCrossPlatTests.TestTtcFaceExtraction;
const
  DIRS: array[0..3] of string = (
    '/System/Library/Fonts', '/Library/Fonts', '/usr/share/fonts', '');
var
  ttcName, tmp: TFileName;
  ttc, sfnt: RawByteString;
  i, numTables: integer;
  face: FT_Face;
begin
  ttcName := '';
  for i := 0 to high(DIRS) do
  begin
    if DIRS[i] = '' then
      ttcName := FindAnyTtc(GetEnvironmentVariable('HOME') + '/.fonts')
    else
      ttcName := FindAnyTtc(DIRS[i]);
    if ttcName <> '' then
      break;
  end;
  if ttcName = '' then
  begin
    Check(true, 'SKIP: no .ttc collection installed on this system');
    exit;
  end;
  ttc := StringFromFile(ttcName);
  Check(length(ttc) > 16, 'the .ttc must be readable');
  Check(PCardinal(ttc)^ = $66637474, 'the test file must really be a ttcf');
  sfnt := ExtractSfntFromTtc(ttc, 0);
  Check(sfnt <> '', 'ExtractSfntFromTtc must succeed on a collection');
  // a raw 'ttcf' container is not a valid /FontFile2: this is the regression
  Check(PCardinal(sfnt)^ <> $66637474, 'the result must not be a collection');
  Check((PCardinal(sfnt)^ = $00000100) or  // 00 01 00 00, the usual TrueType
        (PCardinal(sfnt)^ = $65757274) or  // 'true'
        (PCardinal(sfnt)^ = $4F54544F),    // 'OTTO'
    'the result must start with a valid sfnt version');
  numTables := swap(PWord(@PByteArray(sfnt)[4])^);
  Check(numTables > 0, 'the extracted face must declare tables');
  Check(length(sfnt) >= 12 + numTables * 16, 'directory must fit in the result');
  Check(length(sfnt) <= length(ttc), 'one face cannot exceed the whole collection');
  // strongest check: FreeType must accept the bytes as a standalone font
  Check(ExtractSfntFromTtc(sfnt, 0) = '', 'the result is no longer a collection');
  if LoadFreeType then
  begin
    tmp := GetTempDir + 'claude_ttc_extract.ttf';
    Check(FileFromString(sfnt, tmp), 'temp file written');
    face := nil;
    Check(FreeType.NewFace(FreeType.FTLibrary, PAnsiChar(AnsiString(tmp)), 0, face) = 0,
      'FreeType must load the extracted face');
    if face <> nil then
    begin
      Check(PFT_FaceRec(face)^.units_per_EM > 0, 'the loaded face must have a UPM');
      Check(PFT_FaceRec(face)^.num_glyphs > 0, 'the loaded face must have glyphs');
      FreeType.DoneFace(face);
    end;
    DeleteFile(tmp);
  end;
end;
{$endif MSWINDOWS}

procedure TPdfCrossPlatTests.TestFontData;
var
  dc: TPdfPlatformDC;
  lf: TPdfLogFont;
  font: TPdfPlatformFontHandle;
  prev: TPdfPlatformFontHandle;
  buf: array[0..3] of byte;
  len: cardinal;
  tag: cardinal;
begin
  dc := PdfPlatformDCProvider.CreateDC;
  try
    FillChar(lf, SizeOf(lf), 0);
    lf.FaceName := 'Arial';
    lf.Height := -1000;
    lf.Weight := 400;
    font := PdfPlatformFont.CreateFont(lf);
    if font = nil then
      lf.FaceName := 'DejaVu Sans';
    font := PdfPlatformFont.CreateFont(lf);
    if font = nil then
    begin
      Check(true, 'SKIP: no test font found');
      exit;
    end;
    prev := PdfPlatformFont.SelectFont(dc, font);
    // Read the 'head' table — every TrueType font has it
    // tag is 4 bytes: 'h','e','a','d' in big-endian = $68656164
    tag := (Ord('h') shl 24) or (Ord('e') shl 16) or
           (Ord('a') shl  8) or  Ord('d');
    // First call: get size
    len := PdfPlatformFont.GetFontData(dc, tag, 0, nil, 0);
    if len <> PdfPlatformFont.FontDataError then
    begin
      Check(len >= 4, 'head table must be at least 4 bytes');
      // Second call: read first 4 bytes
      len := PdfPlatformFont.GetFontData(dc, tag, 0, @buf[0], 4);
      if len <> PdfPlatformFont.FontDataError then
        Check(len = 4, 'GetFontData(head,4 bytes) must return 4');
    end
    else
      Check(true, 'SKIP: GetFontData not available on this platform');
    if prev <> nil then
      PdfPlatformFont.SelectFont(dc, prev);
    PdfPlatformFont.DeleteFont(font);
  finally
    PdfPlatformDCProvider.DeleteDC(dc);
  end;
end;

procedure TPdfCrossPlatTests.TestPdfDocumentCreate;
var
  doc: TPdfDocument;
  ms: TMemoryStream;
  s: RawByteString;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.Title := 'Cross-Platform Test';
    doc.AddPage;
    doc.Canvas.SetFont('Helvetica', 12, []);
    doc.Canvas.TextOut(40, 700, 'Hello from cross-platform mORMot2 PDF!');
    ms := TMemoryStream.Create;
    try
      doc.SaveToStream(ms);
      Check(ms.Size > 100, 'PDF stream must be > 100 bytes');
      // Verify PDF header
      ms.Position := 0;
      SetLength(s, 5);
      ms.Read(pointer(s)^, 5);
      Check(copy(string(s), 1, 4) = '%PDF', 'PDF must start with %PDF');
    finally
      ms.Free;
    end;
  finally
    doc.Free;
  end;
end;

procedure TPdfCrossPlatTests.TestPdfMultiPage;
var
  doc: TPdfDocument;
  ms: TMemoryStream;
  i: integer;
  fonts: array[0..2] of string;
begin
  doc := TPdfDocument.Create;
  try
    doc.EmbeddedTTF := true;
    fonts[0] := 'Helvetica';
    fonts[1] := 'Courier';
    fonts[2] := 'Times';
    for i := 0 to 2 do
    begin
      doc.AddPage;
      doc.Canvas.SetFont(fonts[i], 12, []);
      doc.Canvas.TextOut(40, 700, PdfString('Page ' + IntToStr(i + 1) + ': ' + fonts[i]));
    end;
    ms := TMemoryStream.Create;
    try
      doc.SaveToStream(ms);
      Check(ms.Size > 500, 'Multi-page PDF must be > 500 bytes');
    finally
      ms.Free;
    end;
  finally
    doc.Free;
  end;
end;

end.
