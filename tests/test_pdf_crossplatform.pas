/// Cross-platform PDF engine unit tests
// - tests IFontFace, IFontProvider, IFontEnumerator contracts
// - tests TPdfDocument basic PDF generation on all platforms
// - migrated to TSynTestCase framework for mORMot2 compatibility
unit test_pdf_crossplatform;

interface

{$I mormot.defines.inc}

uses
  SysUtils,
  Classes,
  mormot.core.base,
  mormot.core.unicode,
  mormot.core.os,
  mormot.core.text,
  mormot.core.test,
  mormot.lib.core,
  {$ifndef OSWINDOWS}
  mormot.lib.freetype,  // FreeType face validation
  {$endif OSWINDOWS}
  mormot.pdf;        // registers the backend and FontShaper itself

type
  /// Cross-platform PDF test cases
  TPdfCrossPlatTests = class(TSynTestCase)
  published
    procedure TestPlatformRegistration;
    procedure TestScreenLogPixels;
    procedure TestFontEnumeration;
    procedure TestFontMetrics;
    procedure TestWinAnsiHighRangeWidths;
    procedure TestTextShaperAdvances;
    procedure TestTextShaperYOffsets;
    {$ifndef OSWINDOWS}
    procedure TestShapedGlyphWidthFromHmtx;
    {$endif OSWINDOWS}
    procedure TestUseUniscribeIsPortable;
    {$ifndef OSWINDOWS}
    procedure TestTtcFaceExtraction;
    {$endif OSWINDOWS}
    procedure TestFontData;
    procedure TestFacesKeepTheirState;
    procedure TestPdfDocumentCreate;
    procedure TestPdfMultiPage;
    procedure TestRegisteredFont;
    procedure TestRegisteredArabic;
    procedure TestTestFontFiles;
    procedure TestRegisteredSymbol;
  end;

/// the full name of a font of tests/fonts, '' if it is not found
// - searched upwards from the executable: tests/bin/<cpu-os>, bin/d7/<project>
// and the copies of the remote runs reach it
function TestFontFile(const Name: TFileName): TFileName;

const
  /// the families of tests/fonts (README.md there)
  TEST_SANS = 'mORMot Test Sans';
  TEST_ARABIC = 'mORMot Test Arabic';
  TEST_CJK = 'mORMot Test CJK';
  TEST_SYMBOL = 'mORMot Test Symbol';
  TEST_SYMBOL_LOW = 'mORMot Test Symbol Low';
  TEST_SYMBOL_F2 = 'mORMot Test Symbol F2';
  TEST_UNICODE_ONLY = 'mORMot Test Unicode Only';
  TEST_FORMAT12 = 'mORMot Test Format12';
  TEST_CJK_GLYF = 'mORMot Test CJK Glyf';
  TEST_TTC_A = 'mORMot Test TTC A';
  TEST_TTC_B = 'mORMot Test TTC B';
  /// DEFAULT_CHARSET: GDI takes another font for a registered one that lacks
  // the code page asked for (platform-backends skill)
  TEST_FONT_CHARSET = 1;

/// register every font of tests/fonts that is not registered yet
// - false if a file is missing or refused
// - call it before the document a test draws with them is created: the
// document reads the font list once; a test calling UnregisterFontData drops
// them all, the next call registers them again
function EnsureTestFonts: boolean;

/// a face of a test font at 1000 units per em, nil if it cannot be created
function TestFace(const Family: RawUtf8;
  CharSet: byte = TEST_FONT_CHARSET): IFontFace;

/// is Code one of the 4-digit codes of the hex strings of the first text
// object of an uncompressed PDF? A shaped run is one Tj when the shaper's
// advances equal /W and it gives no offsets, a TJ otherwise
// - the first 'BT' of the file: no stream may come before the page contents,
// e.g. the XMP of a tagged or PDF/A document
function PdfTextShows(const Pdf: RawByteString; const Code: RawUtf8): boolean;

const
  /// the system faces this OS is expected to have: the extras that run here
  // - with --require-fonts a missing one fails (SystemFaceExtra)
  {$ifdef OSWINDOWS}
  REQUIRED_SYSTEM_FACES: array[0..3] of RawUtf8 = (
    'Microsoft YaHei', 'Tahoma', 'MS Gothic', 'Nirmala UI');
  {$else}
  {$ifdef OSDARWIN}
  REQUIRED_SYSTEM_FACES: array[0..2] of RawUtf8 = (
    'Hiragino Sans GB', 'Geeza Pro', 'Helvetica');
  {$else}
  REQUIRED_SYSTEM_FACES: array[0..2] of RawUtf8 = (
    'Droid Sans Fallback', 'Noto Naskh Arabic', 'Noto Sans CJK JP');
  {$endif OSDARWIN}
  {$endif OSWINDOWS}

var
  /// test_runner --require-fonts: a missing face of REQUIRED_SYSTEM_FACES fails
  RequireSystemFaces: boolean;

/// is a system face installed, for a test that runs only where it is?
// - one assertion either way: it passes, or it is skipped - reported on the
// console for a face of REQUIRED_SYSTEM_FACES, a failure for one with
// --require-fonts
function SystemFaceExtra(Test: TSynTestCase; const Name: RawUtf8): boolean;

implementation

function SystemFaceExtra(Test: TSynTestCase; const Name: RawUtf8): boolean;
var
  fonts: TRawUtf8DynArray;
  required: boolean;
  i: PtrInt;
begin
  // the backend substitutes a missing face: the installed list decides
  fonts := nil;
  FontEnumerator.EnumTrueTypeFonts(fonts);
  result := FindRawUtf8(fonts, Name) >= 0;
  required := false;
  for i := 0 to high(REQUIRED_SYSTEM_FACES) do
    if REQUIRED_SYSTEM_FACES[i] = Name then
      required := true;
  if result then
    Test.Check(true)
  else if RequireSystemFaces and
          required then
    Test.Check(false, Utf8ToString(FormatUtf8(
      'the system face % is missing (--require-fonts)', [Name])))
  else
  begin
    // reported for a face of this OS's list; another OS's face is expected
    // to be missing, so it is skipped silently
    Test.Check(true, 'SKIP: a system face is not installed');
    if required then
      Test.AddConsole('extra skipped: % is not installed', [Name]);
  end;
end;

function TestFontFile(const Name: TFileName): TFileName;
var
  dir: TFileName;
  i: integer;
begin
  dir := Executable.ProgramFilePath;
  for i := 0 to 5 do
  begin
    result := dir + 'tests' + PathDelim + 'fonts' + PathDelim + Name;
    if FileExists(result) then
      exit;
    result := dir + 'fonts' + PathDelim + Name;
    if FileExists(result) then
      exit;
    dir := dir + '..' + PathDelim;
  end;
  result := '';
end;

function EnsureTestFonts: boolean;
const
  FILES: array[0..10] of TFileName = (
    'mORMotTestSans-Regular.ttf', 'mORMotTestArabic-Regular.ttf',
    'mORMotTestCJK-Regular.otf', 'mORMotTestSymbol-Regular.ttf',
    'mORMotTestSymbolLow-Regular.ttf', 'mORMotTestSymbolF2-Regular.ttf',
    'mORMotTestCJKGlyf-Regular.ttf', 'mORMotTestUnicodeOnly-Regular.ttf',
    'mORMotTestFormat12-Regular.ttf',
    'mORMotTestCollection.ttc', 'mORMotTestCollection.ttc');
  FACES: array[0..10] of integer = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
  FAMILIES: array[0..10] of RawUtf8 = (
    TEST_SANS, TEST_ARABIC, TEST_CJK, TEST_SYMBOL, TEST_SYMBOL_LOW,
    TEST_SYMBOL_F2, TEST_CJK_GLYF, TEST_UNICODE_ONLY, TEST_FORMAT12,
    TEST_TTC_A, TEST_TTC_B);
var
  req: TFontRequest;
  data: RawByteString;
  index: integer;
  i: PtrInt;
begin
  result := true;
  FillChar(req, SizeOf(req), 0);
  req.Weight := 400;
  for i := 0 to high(FILES) do
  begin
    req.FaceName := Utf8ToSynUnicode(FAMILIES[i]);
    if FindRegisteredFont(req, data, index) then
      continue; // GDI would install a second copy
    data := StringFromFile(TestFontFile(FILES[i]));
    if RegisterFontData(data, FACES[i]) <> FAMILIES[i] then
      result := false;
  end;
end;

function TestFace(const Family: RawUtf8; CharSet: byte): IFontFace;
var
  req: TFontRequest;
begin
  result := nil;
  if not EnsureTestFonts then
    exit;
  FillChar(req, SizeOf(req), 0);
  req.FaceName := Utf8ToSynUnicode(Family);
  req.Height := -1000;
  req.Weight := 400;
  req.CharSet := CharSet;
  result := FontProvider.CreateFace(req);
end;

function PdfTextShows(const Pdf: RawByteString; const Code: RawUtf8): boolean;
var
  b, e, last, k: PtrInt;
begin
  result := false;
  b := PosEx('BT', Pdf);
  last := PosEx('ET', Pdf, b);
  if (b = 0) or
     (last = 0) then
    exit;
  repeat
    b := PosEx('<', Pdf, b);
    if (b = 0) or
       (b > last) then
      exit;
    e := PosEx('>', Pdf, b);
    if (e = 0) or
       (e > last) then
      exit; // no hex string closed inside the text object
    k := b + 1;
    while k + 4 <= e do
    begin
      if CompareMem(@Pdf[k], pointer(Code), 4) then
      begin
        result := true;
        exit;
      end;
      inc(k, 4);
    end;
    b := e;
  until false;
end;

// the /W entry this PDF states for aGlyph, or -1 if it is not found.
// /W is written as "<cid>[<w1> <w2> ...]" runs, so a glyph's width is the
// n-th number of the run whose first cid is <= aGlyph
function PdfWidthOf(const aPdf: RawByteString; aGlyph: word): integer;
var
  p, e, runStart, cid, n: PtrInt;
  v: integer;
begin
  result := -1;
  p := PosEx('/W [', aPdf);
  if p = 0 then
    exit;
  inc(p, 4);
  e := PosEx(']/', aPdf, p); // the /W array ends before the next key
  if e = 0 then
    e := length(aPdf);
  while p < e do
  begin
    while (p < e) and
          (aPdf[p] = ' ') do
      inc(p);
    cid := 0;
    runStart := p;
    while (p < e) and
          (aPdf[p] >= '0') and
          (aPdf[p] <= '9') do
    begin
      cid := cid * 10 + ord(aPdf[p]) - 48;
      inc(p);
    end;
    if p = runStart then
      break; // not a number: end of the array
    if (p >= e) or
       (aPdf[p] <> '[') then
      continue;
    inc(p);
    n := cid;
    while (p < e) and
          (aPdf[p] <> ']') do
    begin
      while (p < e) and
            (aPdf[p] = ' ') do
        inc(p);
      v := 0;
      runStart := p;
      while (p < e) and
            (aPdf[p] >= '0') and
            (aPdf[p] <= '9') do
      begin
        v := v * 10 + ord(aPdf[p]) - 48;
        inc(p);
      end;
      if p = runStart then
        break;
      if n = aGlyph then
      begin
        result := v;
        exit;
      end;
      inc(n);
    end;
    if (p < e) and
       (aPdf[p] = ']') then
      inc(p);
  end;
end;

// a text of one script comes back as one shaped run, from HarfBuzz as from
// Uniscribe: give its arrays to the checks
function ShapeSingleRun(Text: PWideChar; Len: integer; Font: TFontHandle;
  out Glyphs: TWordDynArray; out Advances, Offsets,
  Clusters: TIntegerDynArray): boolean;
var
  runs: TFontShapedRuns;
begin
  result := FontShaper.Shape(Text, Len, Font, true, runs) and
            (length(runs) = 1) and
            (runs[0].Kind = fskShaped);
  if not result then
    exit;
  Glyphs := runs[0].Glyphs;
  Advances := runs[0].Advances;
  Offsets := runs[0].Offsets;
  Clusters := runs[0].Clusters;
end;

procedure TPdfCrossPlatTests.TestPlatformRegistration;
begin
  Check(FontPlatformRegistered, 'RegisterFontPlatform must be called in initialization');
  Check(FontProvider <> nil, 'FontProvider is nil');
  Check(FontEnumerator  <> nil, 'FontEnumerator is nil');
end;

type
  // reads the factors the canvas took from ScreenLogPixels
  TPdfCanvasPeek = class(TPdfCanvas);

procedure TPdfCrossPlatTests.TestScreenLogPixels;
var
  PDF: TPdfDocument;
  raised: boolean;
begin
  // 96 on every platform: the screen's is set by the canvas adapters
  PDF := TPdfDocument.Create;
  try
    CheckEqual(PDF.ScreenLogPixels, 96, '96 by default');
    PDF.ScreenLogPixels := 144;
    CheckEqual(PDF.ScreenLogPixels, 144, 'set');
    CheckSame(TPdfCanvasPeek(PDF.Canvas).fFactor, 0.5, 1e-6, 'fFactor');
    CheckSame(TPdfCanvasPeek(PDF.Canvas).fFactorX, 0.5, 1e-6, 'fFactorX');
    CheckSame(TPdfCanvasPeek(PDF.Canvas).fFactorY, 0.5, 1e-6, 'fFactorY');
    raised := false;
    try
      PDF.ScreenLogPixels := 0;
    except
      on EPdfInvalidValue do
        raised := true;
    end;
    Check(raised, 'no resolution of 0');
    CheckEqual(PDF.ScreenLogPixels, 144, 'kept');
  finally
    PDF.Free;
  end;
end;

procedure TPdfCrossPlatTests.TestFontEnumeration;
var
  list: TRawUtf8DynArray;
begin
  Check(EnsureTestFonts, 'the test fonts registered');
  FontEnumerator.EnumTrueTypeFonts(list);
  Check(Length(list) > 0, 'EnumTrueTypeFonts must return at least one font');
  Check(FindRawUtf8(list, TEST_SANS) >= 0, 'a registered family is listed');
end;

procedure TPdfCrossPlatTests.TestFontMetrics;
var
  face: IFontFace;
  tm: TFontMetrics;
  otm: TFontOutlineMetrics;
  abc: TFontCharAbcArray;
begin
  face := TestFace(TEST_SANS);
  if not Check(face <> nil, TEST_SANS) then
    exit;
  // Text metrics
  Check(face.GetTextMetrics(tm), 'GetTextMetrics must succeed');
  Check(tm.tmAscent > 0, 'tmAscent must be > 0');
  Check(tm.tmDescent > 0, 'tmDescent must be > 0');
  Check(tm.tmHeight >= tm.tmAscent + tm.tmDescent - 10,
    'tmHeight should be >= ascent + descent (approx)');
  // Outline metrics
  Check(face.GetOutlineMetrics(otm), 'GetOutlineMetrics must succeed');
  Check(otm.otmAscent > 0, 'otmAscent must be > 0');
  // ABC widths for ' '..'z'
  Check(face.GetCharAbcWidths(32, 90, abc), 'GetCharAbcWidths must succeed');
  Check(Length(abc) = 59, 'ABC widths: expected 59 entries (32..90)');
  // Space width should be > 0 for a normal font: the advance is the sum of
  // the three ABC members - abcB alone is the ink width, which is legitimately
  // 0 for a space since the glyph is blank
  Check(abc[0].abcA + integer(abc[0].abcB) + abc[0].abcC > 0,
    'Space advance width must be > 0');
end;

procedure TPdfCrossPlatTests.TestWinAnsiHighRangeWidths;
var
  face: IFontFace;
  abc: TFontCharAbcArray;
  notdef, bullet, emdash, letter: integer;

  function Advance(aCode: cardinal): integer;
  begin
    result := abc[aCode - 32].abcA + integer(abc[aCode - 32].abcB) +
      abc[aCode - 32].abcC;
  end;

begin
  // U-1b: GetCharAbcWidths takes WinAnsi byte values, because that is what the
  // Windows GetCharABCWidthsA counterpart takes. Codes 128..159 map to code
  // points well above U+00FF - the bullet #$95 is U+2022, the em dash #$97 is
  // U+2014 - so a backend that hands the byte to a Unicode lookup unchanged
  // lands on an unassigned C1 control, misses the CMAP and returns .notdef.
  // That wrote a wrong /Widths entry and broke ISO 14289-1 7.21.5 on POSIX.
  face := TestFace(TEST_SANS);
  if not Check(face <> nil, TEST_SANS) then
    exit;
  Check(face.GetCharAbcWidths(32, 255, abc),
    'GetCharAbcWidths must succeed');
  Check(Length(abc) = 224, 'ABC widths: expected 224 entries (32..255)');
  bullet := Advance($95);
  emdash := Advance($97);
  letter := Advance(ord('M'));
  Check(bullet > 0, 'bullet #$95 must have a positive advance');
  Check(emdash > 0, 'em dash #$97 must have a positive advance');
  // the bullet is narrow in any text face, the em dash wide - but not
  // always wider than M: Roboto, the Android sans, draws it at 1599 of
  // 2048 units against 1788 for M. Two .notdef boxes cannot order this way
  Check(emdash > bullet, 'em dash must be wider than the bullet');
  Check(bullet < letter, 'bullet must be narrower than M');
  // .notdef is what the defect returned, so the two must not silently be it.
  // Code #$81 is unassigned in WinAnsi and maps to no glyph, so its advance
  // is the .notdef advance on any backend.
  //
  // Comparing bullet <> .notdef directly would be wrong: nothing stops a
  // font from giving .notdef the same advance as a real glyph, and the face
  // the Linux CI picks does exactly that - it failed this check while the
  // lookup was perfectly correct. Compare the two *unmapped* codes with each
  // other instead: #$81 and #$8D are both unassigned in WinAnsi and map to
  // C1 controls no CMAP carries, so they must agree; and the bullet and em
  // dash must not both collapse onto that value. Both hold whatever widths
  // the face happens to use.
  // Note that assertion #5 above already catches the original defect on any
  // font without assuming anything: with the bug, bullet and em dash both
  // returned the .notdef advance, and one number cannot be wider than itself.
  notdef := Advance($81);
  if notdef > 0 then
  begin
    Check(Advance($8D) = notdef,
      'two unassigned WinAnsi codes must share the .notdef advance');
    Check((bullet <> notdef) or
          (emdash <> notdef),
      'bullet and em dash must not both fall back to .notdef');
  end;
end;

{$ifndef OSWINDOWS}
procedure TPdfCrossPlatTests.TestShapedGlyphWidthFromHmtx;
const
  // 'marhaba', terminated for TextOutW: the test font attaches meem and beh
  // cursively (a GPOS x_offset of -40), as Geeza Pro does one of its glyphs
  MARHABA: array[0..5] of WideChar = (
    #$0645, #$0631, #$062D, #$0628, #$0627, #0);

  procedure Run(const aFont: RawUtf8; aRequired: boolean);
  var
    face: IFontFace;
    glyphs: TWordDynArray;
    advances, offsets, clusters: TIntegerDynArray;
    tbl: TWordDynArray;
    doc: TPdfDocument;
    ms: TMemoryStream;
    pdf: RawByteString;
    i, g, shifted, upm, nlhm, hmtxWords, hmtxAdv: integer;

    function Swap16(w: word): word;
    begin
      result := (w shr 8) or (w shl 8);
    end;

    function ReadTable(const aTag: RawUtf8; out aWords: TWordDynArray): boolean;
    var
      n: cardinal;
    begin
      result := false;
      n := face.GetFontData(PCardinal(pointer(aTag))^, 0, nil, 0);
      if (n = FONT_DATA_ERROR) or
         (n < 4) then
        exit;
      SetLength(aWords, n shr 1);
      result := face.GetFontData(PCardinal(pointer(aTag))^, 0,
        pointer(aWords), n) <> FONT_DATA_ERROR;
    end;

  begin
    if not aRequired and
       not SystemFaceExtra(self, aFont) then
      exit; // an extra runs where its face is installed
    face := TestFace(aFont);
    if not Check(face <> nil, Utf8ToString(aFont)) then
      exit;
    Check(ShapeSingleRun(@MARHABA[0], 5, face.Handle, glyphs, advances,
      offsets, clusters), 'Shape must succeed');
    shifted := 0;
    for i := 0 to high(glyphs) do
      if offsets[i] <> 0 then
        inc(shifted);
    // a face without a cursive attachment of this word cannot exercise the
    // defect - Noto Naskh Arabic is one, which is why U-2 was invisible on
    // Linux; the test font has one on purpose
    if not aRequired and
       (shifted = 0) then
      exit;
    Check(shifted > 0, 'a GPOS x_offset on this word');
    // the face's own metrics: 'head' for unitsPerEm (offset 18 bytes),
    // 'hhea' for numOfLongHorMetrics (offset 34), 'hmtx' for the advances
    if not Check(ReadTable('head', tbl), 'the head table') then
      exit;
    upm := Swap16(tbl[9]);
    Check(upm > 0, 'unitsPerEm must be > 0');
    if not Check(ReadTable('hhea', tbl), 'the hhea table') then
      exit;
    nlhm := Swap16(tbl[17]);
    Check(nlhm > 0, 'numOfLongHorMetrics must be > 0');
    if not Check(ReadTable('hmtx', tbl), 'the hmtx table') then
      exit;
    hmtxWords := length(tbl);
    // a PDF with this very text, and what its /W states for the shifted
    // glyphs: the engine used to write advances[i] there, it has to write
    // the hmtx advance
    doc := TPdfDocument.Create;
    ms := TMemoryStream.Create;
    try
      doc.EmbeddedTTF := true;
      doc.CompressionMethod := cmNone;
      doc.UseUniscribe := true;
      doc.AddPage;
      doc.Canvas.SetFont(aFont, 24, []);
      doc.Canvas.RightToLeftText := true;
      doc.Canvas.TextOutW(40, 700, @MARHABA[0]);
      doc.SaveToStream(ms);
      FastSetRawByteString(pdf, ms.Memory, ms.Size);
    finally
      ms.Free;
      doc.Free;
    end;
    for i := 0 to high(glyphs) do
      if offsets[i] <> 0 then
      begin
        g := glyphs[i];
        if g >= nlhm then
          g := nlhm - 1;
        if g * 2 >= hmtxWords then
          continue;
        hmtxAdv := (int64(Swap16(tbl[g * 2])) * 1000) div upm;
        Check(hmtxAdv > 0, 'hmtx advance must be > 0');
        // the two really are different for a cursively attached glyph, which
        // is the precondition that makes the rest of this test meaningful
        Check(hmtxAdv <> advances[i],
          'a cursively shifted glyph must not have shaper advance = hmtx advance');
        Check(Abs((hmtxAdv - advances[i]) - Abs(offsets[i])) <= 2,
          'the advance difference must match the GPOS offset');
        // the regression itself: /W states the hmtx value
        Check(Abs(PdfWidthOf(pdf, glyphs[i]) - hmtxAdv) <= 1,
          'the /W entry must be the hmtx advance');
        Check(Abs(PdfWidthOf(pdf, glyphs[i]) - advances[i]) > 2,
          'the /W entry must not be the shaper advance');
      end;
  end;

begin
  // U-2: the /W width of a shaped glyph must be the font's own 'hmtx' advance,
  // not the shaper's. HarfBuzz returns the *positioned* advance, so a glyph
  // carrying a GPOS cursive adjustment comes back shortened by exactly the
  // amount it is offset. Writing that value as the glyph width made the font
  // dictionary disagree with the embedded font program (ISO 14289-1 7.21.5)
  // while the page still looked right, because the shortened advance and the
  // offset cancelled each other out on screen.
  if FontShaper = nil then
  begin
    Check(true, 'SKIP: no IFontShaper registered (libharfbuzz absent)');
    exit;
  end;
  Run(TEST_ARABIC, true);
  // the face U-2 was found with, where installed
  Run('Geeza Pro', false);
end;
{$endif OSWINDOWS}

procedure TPdfCrossPlatTests.TestUseUniscribeIsPortable;
var
  doc: TPdfDocument;
begin
  // ROADMAP R-16: UseUniscribe used to be declared inside {$ifdef
  // USE_UNISCRIBE}. That symbol is defined in mormot.pdf and does not reach
  // the units that use it, so callers wrote {$ifdef USE_UNISCRIBE} around the
  // assignment, it compiled to nothing, and the shaper silently never ran -
  // rtl_demo produced unshaped Arabic on Windows for exactly that reason.
  // This test carries no conditional on purpose: if the property is ever made
  // conditional again, this unit stops compiling, which is the point.
  doc := TPdfDocument.Create;
  try
    Check(not doc.UseUniscribe, 'off by default, for faster content');
    doc.UseUniscribe := true;
    Check(doc.UseUniscribe, 'the setter must stick on every platform');
    doc.UseUniscribe := false;
    Check(not doc.UseUniscribe, 'and be clearable again');
  finally
    doc.Free;
  end;
end;

procedure TPdfCrossPlatTests.TestTextShaperAdvances;
const
  // 'marhaba' = U+0645 U+0631 U+062D U+0628 U+0627, all spacing glyphs: none of
  // them may shape to a zero advance
  MARHABA: array[0..4] of WideChar = (
    #$0645, #$0631, #$062D, #$0628, #$0627);
var
  face: IFontFace;
  glyphs: TWordDynArray;
  advances, offsets, clusters: TIntegerDynArray;
  i: integer;
begin
  if FontShaper = nil then
  begin
    Check(true, 'SKIP: no IFontShaper registered (libharfbuzz absent)');
    exit;
  end;
  // no presentation forms in its cmap: the joined forms come from GSUB only
  face := TestFace(TEST_ARABIC);
  if not Check(face <> nil, TEST_ARABIC) then
    exit;
  Check(ShapeSingleRun(@MARHABA[0], length(MARHABA), face.Handle,
      glyphs, advances, offsets, clusters), 'Shape must succeed');
  Check(length(glyphs) > 0, 'Shape must return glyphs');
  // Uniscribe gives no advances: those of the font apply
  Check((advances = nil) or
        (length(advances) = length(glyphs)), 'one advance per glyph');
  for i := 0 to high(advances) do
  begin
    // a zero advance stacks every glyph on the same spot: this is exactly the
    // regression that made rtl_demo unreadable when the shaped glyphs were
    // missing from the font CMAP and their width came from the shaper
    Check(advances[i] > 0, 'shaped advance must be > 0');
    // and it must be a plausible 1000/em width, not a raw or mis-scaled value
    Check(advances[i] < 4000, 'shaped advance must be in 1000/em units');
  end;
end;

procedure TPdfCrossPlatTests.TestTextShaperYOffsets;
const
  // 'bismi' = U+0628 U+0650 U+0633 U+0652 U+0645 U+0650: two kasras below,
  // a sukun above - marks the font's GPOS places vertically
  BISMI: array[0..5] of WideChar = (
    #$0628, #$0650, #$0633, #$0652, #$0645, #$0650);
var
  face: IFontFace;
  runs: TFontShapedRuns;
  i, moved: integer;
begin
  { the contract carries vertical offsets as HarfBuzz gives them, so that it
    is complete before it goes into the trunk; the PDF writer does not draw
    them yet }
  if FontShaper = nil then
  begin
    Check(true, 'SKIP: no IFontShaper registered (libharfbuzz absent)');
    exit;
  end;
  // the test font places these marks with its 'mark' lookups: HarfBuzz
  // 14.6.0 gives -126 and -191
  face := TestFace(TEST_ARABIC);
  if not Check(face <> nil, TEST_ARABIC) then
    exit;
  runs := nil;
  Check(FontShaper.Shape(@BISMI[0], length(BISMI), face.Handle, true, runs) and
    (length(runs) = 1), 'one run');
  if length(runs) = 1 then
  begin
    Check((runs[0].Kind = fskShaped) and
          (runs[0].Outcome = fsoDone), 'shaped, done');
    CheckEqual(runs[0].TextLen, length(BISMI), 'the run covers the whole text');
    if runs[0].Advances = nil then
    begin
      // a shaper of glyphs only (Uniscribe): the font places them
      Check(runs[0].YOffsets = nil, 'no positions, no y offsets');
      exit;
    end;
    CheckEqual(length(runs[0].YOffsets), length(runs[0].Glyphs),
      'one y offset per glyph');
    moved := 0;
    for i := 0 to high(runs[0].YOffsets) do
      if runs[0].YOffsets[i] <> 0 then
        inc(moved);
    Check(moved > 0, 'a mark is placed vertically');
  end;
end;

{$ifndef OSWINDOWS}
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
  ttcName: TFileName;
  ttc: RawByteString;
  i: integer;

  procedure CheckFace(const ttc: RawByteString; index, glyphs: integer);
  var
    sfnt: RawByteString;
    numTables: integer;
    face: FT_Face;
  begin
    Check(length(ttc) > 16, 'the .ttc must be readable');
    Check(PCardinal(ttc)^ = $66637474, 'the test file must really be a ttcf');
    sfnt := ExtractSfntFromTtc(ttc, index);
    if not Check(sfnt <> '', 'ExtractSfntFromTtc must succeed on a collection') then
      exit;
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
    Check(ExtractSfntFromTtc(sfnt, 0) = '', 'the result is no longer a collection');
    // strongest check: FreeType must accept the bytes as a standalone font
    if not LoadFreeType then
      exit;
    face := nil;
    Check(FreeType.NewMemoryFace(FreeType.FTLibrary, pointer(sfnt), length(sfnt),
      0, face) = 0, 'FreeType must load the extracted face');
    if face <> nil then
    begin
      Check(PFT_FaceRec(face)^.units_per_EM > 0, 'the loaded face must have a UPM');
      Check(PFT_FaceRec(face)^.num_glyphs > 0, 'the loaded face must have glyphs');
      if glyphs > 0 then
        CheckEqual(PFT_FaceRec(face)^.num_glyphs, glyphs, 'the face asked for');
      FreeType.DoneFace(face);
    end;
  end;

begin
  // both faces of the test collection
  ttcName := TestFontFile('mORMotTestCollection.ttc');
  if Check(ttcName <> '', 'tests/fonts/mORMotTestCollection.ttc found') then
  begin
    // 233 and 226 glyphs (tests/fonts/README.md): face 1 lacks 'A'-'G'
    ttc := StringFromFile(ttcName);
    CheckFace(ttc, 0, 233);
    CheckFace(ttc, 1, 226);
  end;
  // and face 0 of an installed collection, where there is one
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
  if ttcName <> '' then
    CheckFace(StringFromFile(ttcName), 0, 0);
end;
{$endif OSWINDOWS}

procedure TPdfCrossPlatTests.TestFontData;
var
  face: IFontFace;
  buf: array[0..3] of byte;
  len: cardinal;
  tag: cardinal;
begin
  face := TestFace(TEST_SANS);
  if not Check(face <> nil, TEST_SANS) then
    exit;
  // Read the 'head' table - every TrueType font has it
  // the tag is the four characters read as a little-endian cardinal, as
  // Windows GetFontData takes it: 'head' = $64616568 (the test used the
  // big-endian value before Phase 1b, failed and took it as a skip)
  tag := Ord('h') or (Ord('e') shl 8) or
         (Ord('a') shl 16) or (cardinal(Ord('d')) shl 24);
  // First call: get size
  len := face.GetFontData(tag, 0, nil, 0);
  Check(len <> FONT_DATA_ERROR, 'GetFontData(head) must succeed');
  Check(len >= 54, 'head table must be at least 54 bytes');
  // Second call: read the first 4 bytes, the version 1.0
  len := face.GetFontData(tag, 0, @buf[0], 4);
  Check(len = 4, 'GetFontData(head,4 bytes) must return 4');
  Check((buf[0] = 0) and (buf[1] = 1) and (buf[2] = 0) and (buf[3] = 0),
    'head version 1.0');
end;

procedure TPdfCrossPlatTests.TestFacesKeepTheirState;
const
  OMEGA: RawUtf8 = {$ifdef HASCODEPAGE} #$03A9 {$else} #$CE#$A9 {$endif};
var
  a, b: IFontFace;
  wa1, wa2, wb: TFontCharAbcArray;
  ha1, ha2, hb: cardinal;
  i: PtrInt;
  same: boolean;
  pdf: TPdfDocument;
  ms: TMemoryStream;
  w: SynUnicode;
begin
  { Phase 1b: each face reads its own font - with one document DC, a read
    got whatever font was selected last, and TPdfTtf.Create relied on its
    caller having selected the right one - two faces of other files }
  a := TestFace(TEST_SANS);
  b := TestFace(TEST_CJK);
  if not Check((a <> nil) and
               (b <> nil), 'the two test faces') then
    exit;
  Check(a.GetCharAbcWidths(32, 126, wa1), 'widths of a');
  ha1 := a.GetFontData(0, 0, nil, 0);
  Check(b.GetCharAbcWidths(32, 126, wb), 'widths of b');
  hb := b.GetFontData(0, 0, nil, 0);
  Check(a.GetCharAbcWidths(32, 126, wa2), 'widths of a again');
  ha2 := a.GetFontData(0, 0, nil, 0);
  same := length(wa1) = length(wa2);
  for i := 0 to high(wa1) do
    same := same and
            (wa1[i].abcA = wa2[i].abcA) and
            (wa1[i].abcB = wa2[i].abcB) and
            (wa1[i].abcC = wa2[i].abcC);
  Check(same, 'a reads the same widths after b was read');
  CheckEqual(ha1, ha2, 'and the same font file size');
  Check(ha1 <> hb, 'b is another font file');
  // 'i' and 'M' share their advance in a mono face only
  Check(wa1[ord('i') - 32].abcB <> wa1[ord('M') - 32].abcB, 'a is proportional');
  // a font with a Unicode instance shares the face with its WinAnsi
  // instance: both go with the document, in any order, without a double free
  pdf := TPdfDocument.Create;
  ms := TMemoryStream.Create;
  try
    pdf.EmbeddedTTF := true;
    pdf.AddPage;
    pdf.Canvas.SetFont(TEST_SANS, 12, []);
    w := Utf8ToSynUnicode('Hello ' + OMEGA);
    pdf.Canvas.TextOutW(20, 800, pointer(w));
    pdf.SaveToStream(ms);
    Check(ms.Size > 1000, 'saved with both instances');
  finally
    ms.Free;
    pdf.Free;
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
  fonts: array[0..2] of RawUtf8;
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
      doc.Canvas.TextOut(40, 700, PdfString(FormatUtf8('Page %: %', [i + 1, fonts[i]])));
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

procedure TPdfCrossPlatTests.TestRegisteredFont;
const
  FAMILY = 'mORMot Test Sans';
var
  data, face, pdf, broken: RawByteString;
  list: TRawUtf8DynArray;
  req: TFontRequest;
  f: IFontFace;
  m: TFontMetrics;
  i, index: integer;
  found: boolean;
  doc: TPdfDocument;
  ms: TMemoryStream;
begin
  UnregisterFontData; // the copy EnsureTestFonts registered
  data := StringFromFile(TestFontFile('mORMotTestSans-Regular.ttf'));
  Check(data <> '', 'tests/fonts/mORMotTestSans-Regular.ttf found');
  if data = '' then
    exit;
  CheckEqual(RegisterFontData('not a font'), '', 'no font, no family');
  CheckEqual(RegisterFontData(data, 1), '', 'no collection, no face 1');
  // truncated or broken data: refused, read within its bounds
  CheckEqual(RegisterFontData(copy(data, 1, 12)), '', 'the header only');
  CheckEqual(RegisterFontData(copy(data, 1, 300)), '', 'the table directory only');
  broken := data;
  broken[5] := AnsiChar($ff); // numTables far beyond the data
  broken[6] := AnsiChar($ff);
  CheckEqual(RegisterFontData(broken), '', 'a table count past the end');
  try
    CheckEqual(RegisterFontData(data), FAMILY, 'the family of the name table');
    // the enumerators list it: a document reads that list once
    FontEnumerator.EnumTrueTypeFonts(list);
    found := false;
    for i := 0 to high(list) do
      if list[i] = FAMILY then
        found := true;
    Check(found, 'enumerated');
    // the provider creates the face from the registered bytes
    FillChar(req, SizeOf(req), 0);
    req.FaceName := FAMILY;
    req.Height := -1000;
    req.Weight := 400;
    f := FontProvider.CreateFace(req);
    Check(f <> nil, 'face created');
    if f = nil then
      exit;
    Check(f.GetFaceFile(face), 'GetFaceFile');
    Check(face = data, 'the face is the registered font, not a substitute');
    Check(f.GetTextMetrics(m) and (m.tmAscent > 0), 'metrics');
    f := nil;
    req.Weight := 700;
    Check(FindRegisteredFont(req, face, index), 'bold asks for the regular face');
    // a document draws and embeds it
    doc := TPdfDocument.Create;
    ms := TMemoryStream.Create;
    try
      doc.EmbeddedTTF := true;
      doc.CompressionMethod := cmNone;
      doc.AddPage;
      doc.Canvas.SetFont(FAMILY, 12, []);
      doc.Canvas.TextOut(40, 700, 'Registered font');
      doc.SaveToStream(ms);
      FastSetRawByteString(pdf, ms.Memory, ms.Size);
      Check(PosEx('/FontName/', pdf) > 0, 'a font descriptor');
      Check(PosEx('mORMotTestSans', pdf) > 0, 'named after the registered face');
      Check(PosEx('/FontFile2', pdf) > 0, 'embedded');
    finally
      ms.Free;
      doc.Free;
    end;
  finally
    UnregisterFontData;
  end;
  req.Weight := 400;
  Check(not FindRegisteredFont(req, face, index), 'forgotten');
end;

procedure TPdfCrossPlatTests.TestRegisteredArabic;
const
  FAMILY = 'mORMot Test Arabic';
  // 'marhaba', terminated for TextOutW
  MARHABA: array[0..5] of WideChar = (
    #$0645, #$0631, #$062D, #$0628, #$0627, #0);
  // the glyphs of the word in the test font, read with fontTools: the joined
  // forms GSUB gives, their hmtx advances (unitsPerEm is 1000) and their
  // codes, and the codes of the isolated forms of the cmap
  JOINED: array[0..4] of word = (316, 404, 163, 48, 23);
  JOINED_ADVANCE: array[0..4] of integer = (525, 396, 589, 343, 291);
  JOINED_HEX: array[0..4] of RawUtf8 = ('013C', '0194', '00A3', '0030', '0017');
  NOMINAL_HEX: array[0..4] of RawUtf8 = ('013A', '0193', '00A1', '002D', '0016');
var
  data, face, pdf: RawByteString;
  req: TFontRequest;
  f: IFontFace;
  glyphs: TWordDynArray;
  advances, offsets, clusters: TIntegerDynArray;
  i, j: PtrInt;
  found: boolean;
  doc: TPdfDocument;
  ms: TMemoryStream;
begin
  { the font has no presentation forms in its cmap, as fonts.md asks for RTL
    work: only a shaper reaches the joined forms, and their widths come from
    nowhere but the font's hmtx }
  data := StringFromFile(TestFontFile('mORMotTestArabic-Regular.ttf'));
  Check(data <> '', 'tests/fonts/mORMotTestArabic-Regular.ttf found');
  if data = '' then
    exit;
  try
    CheckEqual(RegisterFontData(data), FAMILY, 'the family of the name table');
    FillChar(req, SizeOf(req), 0);
    req.FaceName := FAMILY;
    req.Height := -1000;
    req.Weight := 400;
    req.CharSet := TEST_FONT_CHARSET;
    f := FontProvider.CreateFace(req);
    Check(f <> nil, 'face created');
    if f = nil then
      exit;
    Check(f.GetFaceFile(face) and (face = data), 'the registered font');
    if FontShaper = nil then
    begin
      Check(true, 'SKIP: no IFontShaper registered (libharfbuzz absent)');
      exit;
    end;
    Check(ShapeSingleRun(@MARHABA[0], 5, f.Handle, glyphs, advances, offsets,
      clusters), 'shaped');
    CheckEqual(length(glyphs), 5, 'one glyph per letter');
    for i := 0 to high(JOINED) do
    begin
      found := false;
      for j := 0 to high(glyphs) do
        if glyphs[j] = JOINED[i] then
          found := true;
      Check(found, 'the joined form from GSUB');
    end;
    f := nil;
    // the document draws the joined forms with their own widths
    doc := TPdfDocument.Create;
    ms := TMemoryStream.Create;
    try
      doc.EmbeddedTTF := true;
      doc.CompressionMethod := cmNone;
      doc.UseUniscribe := true;
      doc.AddPage;
      doc.Canvas.RightToLeftText := true;
      doc.Canvas.SetFont(FAMILY, 24, [], TEST_FONT_CHARSET);
      doc.Canvas.TextOutW(40, 700, @MARHABA[0]);
      doc.SaveToStream(ms);
      FastSetRawByteString(pdf, ms.Memory, ms.Size);
    finally
      ms.Free;
      doc.Free;
    end;
    for i := 0 to high(JOINED) do
    begin
      Check(PdfTextShows(pdf, JOINED_HEX[i]), 'the joined form drawn');
      Check(not PdfTextShows(pdf, NOMINAL_HEX[i]), 'not the isolated form');
      CheckEqual(PdfWidthOf(pdf, JOINED[i]), JOINED_ADVANCE[i],
        'the /W of a joined form is its hmtx advance');
    end;
  finally
    UnregisterFontData;
  end;
end;

procedure TPdfCrossPlatTests.TestTestFontFiles;
const
  FILES: array[0..10] of TFileName = (
    'mORMotTestSans-Regular.ttf', 'mORMotTestArabic-Regular.ttf',
    'mORMotTestCJK-Regular.otf', 'mORMotTestSymbol-Regular.ttf',
    'mORMotTestSymbolLow-Regular.ttf', 'mORMotTestSymbolF2-Regular.ttf',
    'mORMotTestCJKGlyf-Regular.ttf', 'mORMotTestUnicodeOnly-Regular.ttf',
    'mORMotTestFormat12-Regular.ttf',
    'mORMotTestCollection.ttc', 'mORMotTestCollection.ttc');
  FACES: array[0..10] of integer = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1);
  FAMILIES: array[0..10] of RawUtf8 = (
    'mORMot Test Sans', 'mORMot Test Arabic', 'mORMot Test CJK',
    'mORMot Test Symbol', 'mORMot Test Symbol Low', 'mORMot Test Symbol F2',
    'mORMot Test CJK Glyf', 'mORMot Test Unicode Only', 'mORMot Test Format12',
    'mORMot Test TTC A', 'mORMot Test TTC B');
var
  data: RawByteString;
  i: PtrInt;
begin
  // every file of tests/fonts registers under its family: the name table
  // the tests rely on, the face of a collection, the symbol encoding
  try
    for i := 0 to high(FILES) do
    begin
      data := StringFromFile(TestFontFile(FILES[i]));
      Check(data <> '', FILES[i]);
      CheckEqual(RegisterFontData(data, FACES[i]), FAMILIES[i]);
    end;
    CheckEqual(RegisterFontData(data, 2), '', 'a collection of two faces');
  finally
    UnregisterFontData;
  end;
end;

procedure TPdfCrossPlatTests.TestRegisteredSymbol;
const
  // the advances of the test fonts' glyphs of ' ', 'A', 'a' (fontTools); as
  // glyph indexes 32, 65, 97 the codes would give 434, 281 and 350
  SAMPLE: array[0..2] of AnsiChar = (' ', 'A', 'a');
  ADVANCE: array[0..2] of integer = (260, 639, 561);
  // the cmap at U+F020-F07E, as Wingdings has it, at U+F220-F27E, and at
  // U+0020-007E - where GDI finds nothing: it gives the .notdef advance
  // (measured)
  FILES: array[0..2] of TFileName = (
    'mORMotTestSymbol-Regular.ttf', 'mORMotTestSymbolF2-Regular.ttf',
    'mORMotTestSymbolLow-Regular.ttf');
  FAMILIES: array[0..2] of RawUtf8 = (
    'mORMot Test Symbol', 'mORMot Test Symbol F2', 'mORMot Test Symbol Low');
var
  data: RawByteString;
  req: TFontRequest;
  f: IFontFace;
  abc: TFontCharAbcArray;
  i, n: PtrInt;
begin
  // a symbol font maps the bytes in its (3,0) cmap; FreeType selects no
  // charmap for such a face by itself
  FillChar(req, SizeOf(req), 0);
  req.Height := -1000;
  req.Weight := 400;
  req.CharSet := 2; // SYMBOL_CHARSET
  try
    for n := 0 to {$ifdef OSWINDOWS} 1 {$else} high(FILES) {$endif} do
    begin
      data := StringFromFile(TestFontFile(FILES[n]));
      Check(data <> '', FILES[n]);
      CheckEqual(RegisterFontData(data), FAMILIES[n]);
      req.FaceName := Utf8ToSynUnicode(FAMILIES[n]);
      f := FontProvider.CreateFace(req);
      if not Check(f <> nil, 'face created') then
        continue;
      for i := 0 to high(SAMPLE) do
        if Check(f.GetCharAbcWidths(ord(SAMPLE[i]), ord(SAMPLE[i]), abc) and
                 (length(abc) = 1), 'GetCharAbcWidths') then
          CheckEqual(abc[0].abcA + integer(abc[0].abcB) + abc[0].abcC,
            ADVANCE[i], Utf8ToString(FAMILIES[n]) + ': the glyph the cmap maps the byte to');
      f := nil;
    end;
  finally
    UnregisterFontData;
  end;
end;

end.
