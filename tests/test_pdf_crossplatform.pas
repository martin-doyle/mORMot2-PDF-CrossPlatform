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
  mormot.pdf.types,
  {$ifndef OSWINDOWS}
  mormot.lib.freetype,  // FreeType face validation
  {$endif OSWINDOWS}
  mormot.ui.pdf;        // registers the backend and FontShaper itself

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
  end;

implementation

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

procedure TPdfCrossPlatTests.TestScreenLogPixels;
var
  PDF: TPdfDocument;
begin
  // GDI's LOGPIXELSY on Windows (96 unless the process is DPI-aware), 96 on
  // POSIX: no font service any more, since Phase 1b
  PDF := TPdfDocument.Create;
  try
    Check(PDF.ScreenLogPixels > 0, 'ScreenLogPixels must be > 0');
    Check(PDF.ScreenLogPixels <= 600, 'ScreenLogPixels must be <= 600 (sanity)');
    {$ifndef OSWINDOWS}
    CheckEqual(PDF.ScreenLogPixels, 96, 'POSIX: 96');
    {$endif OSWINDOWS}
  finally
    PDF.Free;
  end;
end;

procedure TPdfCrossPlatTests.TestFontEnumeration;
var
  list: TRawUtf8DynArray;
begin
  FontEnumerator.EnumTrueTypeFonts(list);
  Check(Length(list) > 0, 'EnumTrueTypeFonts must return at least one font');
end;

procedure TPdfCrossPlatTests.TestFontMetrics;
var
  lf: TFontRequest;
  face: IFontFace;
  tm: TFontMetrics;
  otm: TFontOutlineMetrics;
  abc: TFontCharAbcArray;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.FaceName := 'Arial';
  lf.Height := -1000;
  lf.Weight := 400; // FW_NORMAL
  face := FontProvider.CreateFace(lf);
  if face = nil then
  begin
    // Arial not available - try DejaVu Sans (Linux) or system default
    lf.FaceName := 'DejaVu Sans';
    face := FontProvider.CreateFace(lf);
  end;
  if face = nil then
  begin
    Check(true, 'SKIP: no test font found on this system');
    exit;
  end;
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
  lf: TFontRequest;
  face: IFontFace;
  abc: TFontCharAbcArray;
  notdef, bullet, emdash, letter: integer;

  function Advance(aCode: cardinal): integer;
  begin
    with abc[aCode - 32] do
      result := abcA + integer(abcB) + abcC;
  end;

begin
  // U-1b: GetCharAbcWidths takes WinAnsi byte values, because that is what the
  // Windows GetCharABCWidthsA counterpart takes. Codes 128..159 map to code
  // points well above U+00FF - the bullet #$95 is U+2022, the em dash #$97 is
  // U+2014 - so a backend that hands the byte to a Unicode lookup unchanged
  // lands on an unassigned C1 control, misses the CMAP and returns .notdef.
  // That wrote a wrong /Widths entry and broke ISO 14289-1 7.21.5 on POSIX.
  FillChar(lf, SizeOf(lf), 0);
  lf.FaceName := 'Arial';
  lf.Height := -1000;
  lf.Weight := 400; // FW_NORMAL
  face := FontProvider.CreateFace(lf);
  if face = nil then
  begin
    lf.FaceName := 'DejaVu Sans';
    face := FontProvider.CreateFace(lf);
  end;
  if face = nil then
  begin
    Check(true, 'SKIP: no test font found on this system');
    exit;
  end;
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
  // 'marhaba': with a font that attaches cursively (Geeza Pro) one glyph of
  // this word carries a GPOS x_offset, which is what U-2 was about
  MARHABA: array[0..4] of WideChar = (
    #$0645, #$0631, #$062D, #$0628, #$0627);
  ARABIC_FONTS: array[0..3] of RawUtf8 = (
    'Geeza Pro', 'Noto Naskh Arabic', 'Tahoma', 'DejaVu Sans');
var
  lf: TFontRequest;
  face: IFontFace;
  glyphs: TWordDynArray;
  advances, offsets, clusters: TIntegerDynArray;
  tbl: TWordDynArray;
  doc: TPdfDocument;
  ms: TMemoryStream;
  pdf: RawByteString;
  i, f, g, shifted, upm, nlhm, hmtxWords, hmtxAdv, wEntry: integer;

  function Swap16(w: word): word;
  begin
    result := (w shr 8) or (w shl 8);
  end;

  // the /W entry this PDF states for aGlyph, or -1 if it is not found.
  // /W is written as "<cid>[<w1> <w2> ...]" runs, so a glyph's width is the
  // n-th number of the run whose first cid is <= aGlyph
  function WFor(const aPdf: RawByteString; aGlyph: word): integer;
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
  face := nil;
  for f := 0 to high(ARABIC_FONTS) do
  begin
    FillChar(lf, SizeOf(lf), 0);
    lf.FaceName := Utf8ToSynUnicode(ARABIC_FONTS[f]);
    lf.Height := -1000;
    lf.Weight := 400;
    face := FontProvider.CreateFace(lf);
    if face <> nil then
      break;
  end;
  if face = nil then
  begin
    Check(true, 'SKIP: no Arabic-capable font found on this system');
    exit;
  end;
  Check(ShapeSingleRun(@MARHABA[0], length(MARHABA), face.Handle,
    glyphs, advances, offsets, clusters), 'Shape must succeed');
  shifted := 0;
  for i := 0 to high(glyphs) do
    if offsets[i] <> 0 then
      inc(shifted);
  if shifted = 0 then
  begin
    // this face shapes the word without cursive attachment and so cannot
    // exercise the defect - Noto Naskh Arabic behaves this way, which is
    // why U-2 was invisible on Linux
    Check(true, 'SKIP: font applies no GPOS x_offset to this word');
    exit;
  end;
  // read the face's own metrics: 'head' for unitsPerEm (offset 18 bytes),
  // 'hhea' for numOfLongHorMetrics (offset 34), 'hmtx' for the advances
  if not ReadTable('head', tbl) then
  begin
    Check(true, 'SKIP: cannot read the head table');
    exit;
  end;
  upm := Swap16(tbl[9]);
  Check(upm > 0, 'unitsPerEm must be > 0');
  if not ReadTable('hhea', tbl) then
  begin
    Check(true, 'SKIP: cannot read the hhea table');
    exit;
  end;
  nlhm := Swap16(tbl[17]);
  Check(nlhm > 0, 'numOfLongHorMetrics must be > 0');
  if not ReadTable('hmtx', tbl) then
  begin
    Check(true, 'SKIP: cannot read the hmtx table');
    exit;
  end;
  hmtxWords := length(tbl);
  // build a PDF with this very text, and read back what /W states for the
  // shifted glyphs. That is the assertion that bites: the engine used to
  // write advances[i] there, and it has to write the hmtx advance.
  doc := TPdfDocument.Create;
  try
    doc.EmbeddedTTF := true;
    doc.AddPage;
    doc.Canvas.SetFont(ARABIC_FONTS[f], 24, []);
    doc.Canvas.RightToLeftText := true;
    doc.Canvas.TextOutW(40, 700, @MARHABA[0]);
    ms := TMemoryStream.Create;
    try
      doc.SaveToStream(ms);
      SetLength(pdf, ms.Size);
      ms.Position := 0;
      ms.Read(pointer(pdf)^, ms.Size);
    finally
      ms.Free;
    end;
  finally
    doc.Free;
  end;
  Check(length(pdf) > 100, 'the test PDF must have been written');
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
      // and this is the regression itself: /W must state the hmtx value.
      // WFor(g) finds "<glyph>[<width>]" in the /W array of the CID font.
      wEntry := WFor(pdf, glyphs[i]);
      if wEntry < 0 then
        Check(true, 'SKIP: /W entry not found (deflated object stream)')
      else
      begin
        Check(Abs(wEntry - hmtxAdv) <= 1,
          'the /W entry must be the hmtx advance');
        Check(Abs(wEntry - advances[i]) > 2,
          'the /W entry must not be the shaper advance');
      end;
    end;
end;
{$endif OSWINDOWS}

procedure TPdfCrossPlatTests.TestUseUniscribeIsPortable;
var
  doc: TPdfDocument;
begin
  // ROADMAP R-16: UseUniscribe used to be declared inside {$ifdef
  // USE_UNISCRIBE}. That symbol is defined in mormot.ui.pdf and does not reach
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
  // fonts with Arabic contextual forms, in platform preference order
  ARABIC_FONTS: array[0..3] of RawUtf8 = (
    'Noto Naskh Arabic', 'Geeza Pro', 'Tahoma', 'DejaVu Sans');
var
  lf: TFontRequest;
  face: IFontFace;
  glyphs: TWordDynArray;
  advances, offsets, clusters: TIntegerDynArray;
  i, f: integer;
begin
  if FontShaper = nil then
  begin
    Check(true, 'SKIP: no IFontShaper registered (libharfbuzz absent)');
    exit;
  end;
  face := nil;
  for f := 0 to high(ARABIC_FONTS) do
  begin
    FillChar(lf, SizeOf(lf), 0);
    lf.FaceName := Utf8ToSynUnicode(ARABIC_FONTS[f]);
    lf.Height := -1000;
    lf.Weight := 400;
    face := FontProvider.CreateFace(lf);
    if face <> nil then
      break;
  end;
  if face = nil then
  begin
    Check(true, 'SKIP: no Arabic-capable font found on this system');
    exit;
  end;
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
  // known to place these marks with a vertical GPOS offset (Linux, macOS)
  MARK_FONTS: array[0..1] of RawUtf8 = (
    'Noto Naskh Arabic', 'Geeza Pro');
var
  lf: TFontRequest;
  face: IFontFace;
  runs: TFontShapedRuns;
  fonts: TRawUtf8DynArray;
  i, f, moved: integer;
begin
  { the contract carries vertical offsets as HarfBuzz gives them, so that it
    is complete before it goes into the trunk; the PDF writer does not draw
    them yet }
  if FontShaper = nil then
  begin
    Check(true, 'SKIP: no IFontShaper registered (libharfbuzz absent)');
    exit;
  end;
  // CreateFont substitutes a missing face: take one which is installed
  fonts := nil;
  FontEnumerator.EnumTrueTypeFonts(fonts);
  f := 0;
  while (f <= high(MARK_FONTS)) and
        (FindRawUtf8(fonts, MARK_FONTS[f]) < 0) do
    inc(f);
  if f > high(MARK_FONTS) then
  begin
    Check(true, 'SKIP: neither Noto Naskh Arabic nor Geeza Pro installed');
    exit;
  end;
  FillChar(lf, SizeOf(lf), 0);
  lf.FaceName := Utf8ToSynUnicode(MARK_FONTS[f]);
  lf.Height := -1000;
  lf.Weight := 400;
  face := FontProvider.CreateFace(lf);
  if face = nil then
  begin
    Check(true, 'SKIP: ' + Utf8ToString(MARK_FONTS[f]) + ' could not be created');
    exit;
  end;
  runs := nil;
  Check(FontShaper.Shape(@BISMI[0], length(BISMI), face.Handle, true, runs) and
    (length(runs) = 1), 'one run');
  if length(runs) = 1 then
    with runs[0] do
    begin
      Check((Kind = fskShaped) and (Outcome = fsoDone), 'shaped, done');
      CheckEqual(TextLen, length(BISMI), 'the run covers the whole text');
      CheckEqual(length(YOffsets), length(Glyphs), 'one y offset per glyph');
      moved := 0;
      for i := 0 to high(YOffsets) do
        if YOffsets[i] <> 0 then
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
    tmp := GetSystemPath(spTemp) + 'claude_ttc_extract.ttf';
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
{$endif OSWINDOWS}

procedure TPdfCrossPlatTests.TestFontData;
var
  lf: TFontRequest;
  face: IFontFace;
  buf: array[0..3] of byte;
  len: cardinal;
  tag: cardinal;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.FaceName := 'Arial';
  lf.Height := -1000;
  lf.Weight := 400;
  face := FontProvider.CreateFace(lf);
  if face = nil then
  begin
    lf.FaceName := 'DejaVu Sans';
    face := FontProvider.CreateFace(lf);
  end;
  if face = nil then
  begin
    Check(true, 'SKIP: no test font found');
    exit;
  end;
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

// the face of the first installed family of Names, or nil
function FirstFace(const Names: array of RawUtf8): IFontFace;
var
  lf: TFontRequest;
  fonts: TRawUtf8DynArray;
  i: PtrInt;
begin
  result := nil;
  fonts := nil;
  FontEnumerator.EnumTrueTypeFonts(fonts);
  for i := 0 to high(Names) do
    if FindRawUtf8(fonts, Names[i]) >= 0 then
    begin
      FillChar(lf, SizeOf(lf), 0);
      lf.FaceName := Utf8ToSynUnicode(Names[i]);
      lf.Height := -1000;
      lf.Weight := 400;
      result := FontProvider.CreateFace(lf);
      exit;
    end;
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
    caller having selected the right one }
  a := FirstFace(['Arial', 'Liberation Sans', 'DejaVu Sans', 'Helvetica']);
  b := FirstFace(['Courier New', 'Liberation Mono', 'DejaVu Sans Mono', 'Courier']);
  if (a = nil) or
     (b = nil) then
  begin
    Check(true, 'SKIP: no sans and mono pair installed');
    exit;
  end;
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
    pdf.Canvas.SetFont('Arial', 12, []);
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

end.
