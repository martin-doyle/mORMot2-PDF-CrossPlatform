/// Cross-platform PDF engine unit tests
// - tests IPdfPlatformFont, IPdfSystemFonts, IPdfPlatformDC contracts
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
    procedure TestWinAnsiHighRangeWidths;
    procedure TestTextShaperAdvances;
    {$ifndef MSWINDOWS}
    procedure TestShapedGlyphWidthFromHmtx;
    {$endif MSWINDOWS}
    procedure TestUseUniscribeIsPortable;
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

procedure TPdfCrossPlatTests.TestWinAnsiHighRangeWidths;
var
  dc: TPdfPlatformDC;
  lf: TPdfLogFont;
  font: TPdfPlatformFontHandle;
  prev: TPdfPlatformFontHandle;
  abc: TPdfCharABCArray;
  notdef, bullet, emdash, letter: integer;

  function Advance(aCode: cardinal): integer;
  begin
    with abc[aCode - 32] do
      result := abcA + integer(abcB) + abcC;
  end;

begin
  // U-1b: GetCharABCWidths takes WinAnsi byte values, because that is what the
  // Windows GetCharABCWidthsA counterpart takes. Codes 128..159 map to code
  // points well above U+00FF - the bullet #$95 is U+2022, the em dash #$97 is
  // U+2014 - so a backend that hands the byte to a Unicode lookup unchanged
  // lands on an unassigned C1 control, misses the CMAP and returns .notdef.
  // That wrote a wrong /Widths entry and broke ISO 14289-1 7.21.5 on POSIX.
  dc := PdfPlatformDCProvider.CreateDC;
  try
    FillChar(lf, SizeOf(lf), 0);
    lf.FaceName := 'Arial';
    lf.Height := -1000;
    lf.Weight := 400; // FW_NORMAL
    font := PdfPlatformFont.CreateFont(lf);
    if font = nil then
    begin
      lf.FaceName := 'DejaVu Sans';
      font := PdfPlatformFont.CreateFont(lf);
    end;
    if font = nil then
    begin
      Check(true, 'SKIP: no test font found on this system');
      exit;
    end;
    prev := PdfPlatformFont.SelectFont(dc, font);
    Check(PdfPlatformFont.GetCharABCWidths(dc, 32, 255, abc),
      'GetCharABCWidths must succeed');
    Check(Length(abc) = 224, 'ABC widths: expected 224 entries (32..255)');
    bullet := Advance($95);
    emdash := Advance($97);
    letter := Advance(ord('M'));
    Check(bullet > 0, 'bullet #$95 must have a positive advance');
    Check(emdash > 0, 'em dash #$97 must have a positive advance');
    // an em dash is one em wide by definition, so it is the widest of the
    // three in any text face - a .notdef box would not order this way
    Check(emdash > letter, 'em dash must be wider than M');
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
    // returned the .notdef advance, and one number cannot be both wider and
    // narrower than M.
    notdef := Advance($81);
    if notdef > 0 then
    begin
      Check(Advance($8D) = notdef,
        'two unassigned WinAnsi codes must share the .notdef advance');
      Check((bullet <> notdef) or
            (emdash <> notdef),
        'bullet and em dash must not both fall back to .notdef');
    end;
    if prev <> nil then
      PdfPlatformFont.SelectFont(dc, prev);
    PdfPlatformFont.DeleteFont(font);
  finally
    PdfPlatformDCProvider.DeleteDC(dc);
  end;
end;

{$ifndef MSWINDOWS}
procedure TPdfCrossPlatTests.TestShapedGlyphWidthFromHmtx;
const
  // 'marhaba': with a font that attaches cursively (Geeza Pro) one glyph of
  // this word carries a GPOS x_offset, which is what U-2 was about
  MARHABA: array[0..4] of WideChar = (
    #$0645, #$0631, #$062D, #$0628, #$0627);
  ARABIC_FONTS: array[0..3] of RawUtf8 = (
    'Geeza Pro', 'Noto Naskh Arabic', 'Tahoma', 'DejaVu Sans');
var
  dc: TPdfPlatformDC;
  lf: TPdfLogFont;
  font, prev: TPdfPlatformFontHandle;
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
    n := PdfPlatformFont.GetFontData(dc, PCardinal(pointer(aTag))^, 0, nil, 0);
    if (n = PdfPlatformFont.FontDataError) or
       (n < 4) then
      exit;
    SetLength(aWords, n shr 1);
    result := PdfPlatformFont.GetFontData(dc, PCardinal(pointer(aTag))^, 0,
      pointer(aWords), n) <> PdfPlatformFont.FontDataError;
  end;

begin
  // U-2: the /W width of a shaped glyph must be the font's own 'hmtx' advance,
  // not the shaper's. HarfBuzz returns the *positioned* advance, so a glyph
  // carrying a GPOS cursive adjustment comes back shortened by exactly the
  // amount it is offset. Writing that value as the glyph width made the font
  // dictionary disagree with the embedded font program (ISO 14289-1 7.21.5)
  // while the page still looked right, because the shortened advance and the
  // offset cancelled each other out on screen.
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
    try
      Check(PdfTextShaper.ShapeText(@MARHABA[0], length(MARHABA), font, true,
        glyphs, advances, offsets, clusters), 'ShapeText must succeed');
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
    finally
      if prev <> nil then
        PdfPlatformFont.SelectFont(dc, prev);
      PdfPlatformFont.DeleteFont(font);
    end;
  finally
    PdfPlatformDCProvider.DeleteDC(dc);
  end;
end;
{$endif MSWINDOWS}

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
