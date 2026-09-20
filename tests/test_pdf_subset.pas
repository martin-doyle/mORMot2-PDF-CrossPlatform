/// Font subsetting unit tests (ROADMAP R-12)
// - tests IPdfFontSubsetter in isolation, on raw sfnt bytes
// - POSIX only: Windows subsets through CreateFontPackage, not this interface
// - every test skips when libharfbuzz-subset is not installed
unit test_pdf_subset;

{$ifdef FPC}
  {$mode delphi}
{$endif FPC}

interface

uses
  Classes,
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.test,
  mormot.pdf.types,
  {$ifndef MSWINDOWS}
  mormot.pdf.hbsubset,
  {$endif MSWINDOWS}
  mormot.ui.pdf,
  mormot.ui.pdfcanvas,
  mormot.ui.report;     // GetReportFonts

type
  /// IPdfFontSubsetter test cases
  TPdfSubsetTests = class(TSynTestCase)
  protected
    fFace: RawByteString;
    fFaceName: RawUtf8;
    // load the whole face of a common glyf-based font through the platform
    // backend; false (and a SKIP check) when no subsetter or no font exists
    function PrepareFace: boolean;
    function SubsetOf(const Unicodes, Glyphs: array of integer;
      out Sub: RawByteString): boolean;
  published
    procedure TestSubsetterRegistered;
    procedure TestSubsetRetainsGids;
    procedure TestSubsetKeepsCmapForUnicodes;
    procedure TestSubsetKeepsNotdef;
    procedure TestSubsetIsSmaller;
    procedure TestSubsetRejectsCff;
    procedure TestSubsetRejectsGarbage;
  end;

  /// font subsetting through TPdfDocument, on the saved PDF
  TPdfSubsetEngineTests = class(TSynTestCase)
  protected
    // render aText with aFont (regular, and bold if aBold) into an
    // uncompressed PDF; aWhole = EmbeddedWholeTtf
    // - aText holds UTF-8 bytes in a string, as TPdfVclCanvas.TextOut expects:
    // a RawUtf8 parameter would be converted to the system code page first
    function BuildPdf(const aFont: string; const aText: string;
      aWhole, aTagged, aBold: boolean;
      aPdfA: TPdfALevel = pdfaNone): RawByteString;
    function SansFont: string;
  published
    procedure TestSubsetEmbeddedIsSmaller;
    procedure TestSubsetSharedStreamAndTag;
    procedure TestSubsetUnionOfStyles;
    procedure TestSubsetTagIsDeterministic;
    procedure TestSubsetFallbackWithoutSubsetter;
    procedure TestTaggedSubsetKeepsToUnicode;
    procedure TestPdfA1StillWholeFace;
  end;

/// number of non-overlapping occurrences of Sub in s
function CountOf(const Sub, s: RawByteString): integer;
/// the bytes of the first /FontFile2 stream of an uncompressed PDF
function FirstFontFile(const Pdf: RawByteString): RawByteString;
/// the first '/ABCDEF+' subset tag of a PDF name, as 'ABCDEF+', or ''
function FirstSubsetTag(const Pdf: RawByteString): RawByteString;

// minimal sfnt readers, shared with the engine-level tests

/// offset and length of an sfnt table, false if absent
function SfntFindTable(const Face: RawByteString; const Tag: RawUtf8;
  out Offset, Len: cardinal): boolean;
/// maxp.numGlyphs of an sfnt face, -1 on error
function SfntNumGlyphs(const Face: RawByteString): integer;
/// byte length of a glyph in the glyf table (0 = empty glyph), -1 on error
function SfntGlyphLength(const Face: RawByteString; Glyph: integer): integer;
/// glyph ID for a BMP code point from the (3,1) format 4 cmap, 0 if unmapped
function SfntCmapLookup(const Face: RawByteString; CodePoint: cardinal): integer;

implementation

function BE16(const s: RawByteString; ofs: cardinal): cardinal;
begin
  result := (ord(s[ofs + 1]) shl 8) or ord(s[ofs + 2]);
end;

function BE32(const s: RawByteString; ofs: cardinal): cardinal;
begin
  result := (BE16(s, ofs) shl 16) or BE16(s, ofs + 2);
end;

function SfntFindTable(const Face: RawByteString; const Tag: RawUtf8;
  out Offset, Len: cardinal): boolean;
var
  i, n, rec: cardinal;
begin
  result := false;
  if length(Face) < 12 then
    exit;
  n := BE16(Face, 4);
  for i := 0 to n - 1 do
  begin
    rec := 12 + i * 16;
    if rec + 16 > cardinal(length(Face)) then
      exit;
    if copy(Face, rec + 1, 4) = Tag then
    begin
      Offset := BE32(Face, rec + 8);
      Len := BE32(Face, rec + 12);
      result := Offset + Len <= cardinal(length(Face));
      exit;
    end;
  end;
end;

function SfntNumGlyphs(const Face: RawByteString): integer;
var
  ofs, len: cardinal;
begin
  if SfntFindTable(Face, 'maxp', ofs, len) then
    result := BE16(Face, ofs + 4)
  else
    result := -1;
end;

function SfntGlyphLength(const Face: RawByteString; Glyph: integer): integer;
var
  hofs, hlen, lofs, llen: cardinal;
begin
  result := -1;
  if not SfntFindTable(Face, 'head', hofs, hlen) or
     not SfntFindTable(Face, 'loca', lofs, llen) then
    exit;
  if (Glyph < 0) or
     (Glyph >= SfntNumGlyphs(Face)) then
    exit;
  if BE16(Face, hofs + 50) = 0 then // indexToLocFormat: short offsets
    result := integer(BE16(Face, lofs + cardinal(Glyph + 1) * 2) -
                      BE16(Face, lofs + cardinal(Glyph) * 2)) * 2
  else
    result := integer(BE32(Face, lofs + cardinal(Glyph + 1) * 4) -
                      BE32(Face, lofs + cardinal(Glyph) * 4));
end;

function SfntCmapLookup(const Face: RawByteString; CodePoint: cardinal): integer;
var
  cofs, clen, n, i, sub, segX2, s, e, delta, range, p: cardinal;
begin
  result := 0;
  if not SfntFindTable(Face, 'cmap', cofs, clen) then
    exit;
  n := BE16(Face, cofs + 2);
  sub := 0;
  for i := 0 to n - 1 do
    if (BE16(Face, cofs + 4 + i * 8) = 3) and
       (BE16(Face, cofs + 6 + i * 8) = 1) then
    begin
      sub := cofs + BE32(Face, cofs + 8 + i * 8);
      break;
    end;
  if (sub = 0) or
     (BE16(Face, sub) <> 4) then
    exit;
  segX2 := BE16(Face, sub + 6);
  for i := 0 to segX2 shr 1 - 1 do
  begin
    e := BE16(Face, sub + 14 + i * 2);
    if e < CodePoint then
      continue;
    s := BE16(Face, sub + 16 + segX2 + i * 2);
    if s > CodePoint then
      exit;
    delta := BE16(Face, sub + 16 + segX2 * 2 + i * 2);
    p := sub + 16 + segX2 * 3 + i * 2; // address of idRangeOffset[i]
    range := BE16(Face, p);
    if range = 0 then
      result := (CodePoint + delta) and $ffff
    else
    begin
      result := BE16(Face, p + range + (CodePoint - s) * 2);
      if result <> 0 then
        result := (cardinal(result) + delta) and $ffff;
    end;
    exit;
  end;
end;


function CountOf(const Sub, s: RawByteString): integer;
var
  p: PtrInt;
begin
  result := 0;
  p := PosEx(Sub, s, 1);
  while p > 0 do
  begin
    inc(result);
    p := PosEx(Sub, s, p + length(Sub));
  end;
end;

function FirstFontFile(const Pdf: RawByteString): RawByteString;
var
  p, q, len: PtrInt;
begin
  result := '';
  p := Pos(RawByteString('/Length1 '), Pdf);
  if p = 0 then
    exit;
  inc(p, 9);
  len := 0;
  while Pdf[p] in ['0'..'9'] do
  begin
    len := len * 10 + ord(Pdf[p]) - 48;
    inc(p);
  end;
  q := PosEx(RawByteString(#10'stream'#10), Pdf, p);
  if q > 0 then
    result := copy(Pdf, q + 8, len);
end;


function FirstSubsetTag(const Pdf: RawByteString): RawByteString;
var
  p, i: PtrInt;
  ok: boolean;
begin
  result := '';
  p := PosEx('+', Pdf, 8);
  while p > 0 do
  begin
    ok := Pdf[p - 7] = '/';
    for i := p - 6 to p - 1 do
      ok := ok and (Pdf[i] in ['A'..'Z']);
    if ok then
    begin
      result := copy(Pdf, p - 6, 7);
      exit;
    end;
    p := PosEx('+', Pdf, p + 1);
  end;
end;


{ TPdfSubsetTests }

function TPdfSubsetTests.PrepareFace: boolean;
const
  FONTS: array[0..3] of RawUtf8 = (
    'Liberation Sans', 'Arial', 'DejaVu Sans', 'Verdana');
var
  dc: TPdfPlatformDC;
  lf: TPdfLogFont;
  font, prev: TPdfPlatformFontHandle;
  size: cardinal;
  f: PtrInt;
begin
  result := false;
  if PdfFontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IPdfFontSubsetter registered (libharfbuzz-subset absent)');
    exit;
  end;
  if fFace <> '' then
  begin
    result := true;
    exit;
  end;
  dc := PdfPlatformDCProvider.CreateDC;
  try
    for f := 0 to high(FONTS) do
    begin
      FillChar(lf, SizeOf(lf), 0);
      lf.FaceName := SynUnicode(FONTS[f]);
      lf.Height := -1000;
      lf.Weight := 400;
      font := PdfPlatformFont.CreateFont(lf);
      if font = nil then
        continue;
      prev := PdfPlatformFont.SelectFont(dc, font);
      size := PdfPlatformFont.GetFontData(dc, 0, 0, nil, 0);
      if size <> PdfPlatformFont.FontDataError then
      begin
        SetLength(fFace, size);
        if PdfPlatformFont.GetFontData(dc, 0, 0, pointer(fFace), size) <> size then
          fFace := '';
      end;
      PdfPlatformFont.SelectFont(dc, prev);
      PdfPlatformFont.DeleteFont(font);
      if (fFace <> '') and
         (copy(fFace, 1, 4) = #0#1#0#0) and
         (SfntCmapLookup(fFace, ord('A')) <> 0) then
      begin
        fFaceName := FONTS[f];
        break;
      end;
      fFace := '';
    end;
  finally
    PdfPlatformDCProvider.DeleteDC(dc);
  end;
  result := fFace <> '';
  if not result then
    Check(true, 'SKIP: no glyf-based test font found on this system');
end;

function TPdfSubsetTests.SubsetOf(const Unicodes, Glyphs: array of integer;
  out Sub: RawByteString): boolean;
var
  req: TPdfFontSubsetRequest;
  i: PtrInt;
begin
  SetLength(req.Unicodes, length(Unicodes));
  for i := 0 to high(Unicodes) do
    req.Unicodes[i] := Unicodes[i];
  SetLength(req.Glyphs, length(Glyphs));
  for i := 0 to high(Glyphs) do
    req.Glyphs[i] := Glyphs[i];
  result := PdfFontSubsetter.Subset(fFace, req, Sub);
end;

procedure TPdfSubsetTests.TestSubsetterRegistered;
begin
  {$ifdef MSWINDOWS}
  Check(PdfFontSubsetter = nil, 'Windows subsets via CreateFontPackage');
  {$else}
  if LoadHarfBuzzSubset then
    Check(PdfFontSubsetter <> nil, 'libharfbuzz-subset loaded but not registered')
  else
    Check(true, 'SKIP: libharfbuzz-subset not installed');
  {$endif MSWINDOWS}
end;

procedure TPdfSubsetTests.TestSubsetRetainsGids;
var
  sub: RawByteString;
  ga, gb: integer;
begin
  if not PrepareFace then
    exit;
  ga := SfntCmapLookup(fFace, ord('A'));
  gb := SfntCmapLookup(fFace, ord('B'));
  Check((ga > 0) and (gb > 0) and (ga <> gb), fFaceName + ': no A/B glyphs');
  Check(SubsetOf([ord('A')], [], sub), 'Subset failed');
  // retain-gids keeps every ID up to the highest one kept: glyphs after it are
  // cut off, so numGlyphs shrinks but never below the retained IDs
  Check(SfntNumGlyphs(sub) > ga, 'A beyond numGlyphs: glyph IDs renumbered');
  Check(SfntNumGlyphs(sub) <= SfntNumGlyphs(fFace), 'numGlyphs grew');
  CheckEqual(SfntCmapLookup(sub, ord('A')), ga, 'A moved to another glyph ID');
  Check(SfntGlyphLength(sub, ga) > 0, 'A lost its outline');
  Check(SfntGlyphLength(sub, gb) <= 0, 'B was not requested but kept');
end;

procedure TPdfSubsetTests.TestSubsetKeepsCmapForUnicodes;
var
  sub: RawByteString;
  ga, gb: integer;
begin
  if not PrepareFace then
    exit;
  ga := SfntCmapLookup(fFace, ord('A'));
  gb := SfntCmapLookup(fFace, ord('B'));
  // A by code point (WinAnsi instance), B by glyph ID only (CID instance) -
  // hb-subset may add a cmap entry for B too, which is harmless
  Check(SubsetOf([ord('A')], [gb], sub), 'Subset failed');
  CheckEqual(SfntCmapLookup(sub, ord('A')), ga, 'cmap entry for A dropped');
  Check(SfntGlyphLength(sub, gb) > 0, 'glyph of B dropped');
end;

procedure TPdfSubsetTests.TestSubsetKeepsNotdef;
var
  sub: RawByteString;
begin
  if not PrepareFace then
    exit;
  Check(SubsetOf([ord('A')], [], sub), 'Subset failed');
  Check(SfntGlyphLength(sub, 0) > 0, '.notdef lost its outline');
end;

procedure TPdfSubsetTests.TestSubsetIsSmaller;
var
  sub: RawByteString;
begin
  if not PrepareFace then
    exit;
  Check(SubsetOf([ord('H'), ord('e'), ord('l'), ord('o'), ord(' '),
    ord('W'), ord('r'), ord('d'), ord('!')], [], sub), 'Subset failed');
  Check(length(sub) * 10 < length(fFace), FormatUtf8('% subset is % of % bytes',
    [fFaceName, length(sub), length(fFace)]));
end;

procedure TPdfSubsetTests.TestSubsetRejectsCff;
var
  sub: RawByteString;
  req: TPdfFontSubsetRequest;
begin
  if PdfFontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IPdfFontSubsetter registered');
    exit;
  end;
  req := Default(TPdfFontSubsetRequest);
  Check(not PdfFontSubsetter.Subset('OTTO' + StringOfChar(#0, 60), req, sub),
    'a CFF face must not be subset into /FontFile2');
  CheckEqual(sub, '', 'no output expected');
end;

procedure TPdfSubsetTests.TestSubsetRejectsGarbage;
var
  sub, junk: RawByteString;
  req: TPdfFontSubsetRequest;
  i: PtrInt;
begin
  if PdfFontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IPdfFontSubsetter registered');
    exit;
  end;
  SetLength(junk, 4096);
  for i := 1 to length(junk) do
    junk[i] := AnsiChar(Random32 and 255);
  PCardinal(junk)^ := $00000100; // looks like a TrueType sfnt header
  req := Default(TPdfFontSubsetRequest);
  SetLength(req.Unicodes, 1);
  req.Unicodes[0] := ord('A');
  // must not crash; whatever comes back, it must not claim to hold glyph A
  if PdfFontSubsetter.Subset(junk, req, sub) then
    Check(SfntGlyphLength(sub, 1) <= 0, 'garbage produced a glyph')
  else
    CheckEqual(sub, '', 'failure must not return data');
end;


{ TPdfSubsetEngineTests }

function TPdfSubsetEngineTests.SansFont: string;
var
  serif, mono: string;
begin
  GetReportFonts(true, result, serif, mono);
end;

function TPdfSubsetEngineTests.BuildPdf(const aFont: string;
  const aText: string; aWhole, aTagged, aBold: boolean;
  aPdfA: TPdfALevel): RawByteString;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, aPdfA);
    try
      PDF.CompressionMethod := cmNone; // keep the font file readable
      if aTagged then
        PDF.Tagged := true
      else
      begin
        PDF.EmbeddedTTF := true;
        PDF.EmbeddedWholeTtf := aWhole;
      end;
      PDF.AddPage;
      if aTagged then
        PDF.BeginStructContent(psrP);
      PDF.VclCanvas.Font.Name := aFont;
      PDF.VclCanvas.Font.Size := 12;
      PDF.VclCanvas.TextOut(20, 20, aText);
      if aBold then
      begin
        PDF.VclCanvas.Font.Style := [fsBold];
        PDF.VclCanvas.TextOut(20, 60, aText + '!');
      end;
      if aTagged then
        PDF.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(result, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(result)^, Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure TPdfSubsetEngineTests.TestSubsetEmbeddedIsSmaller;
var
  whole, sub: RawByteString;
begin
  if PdfFontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IPdfFontSubsetter registered');
    exit;
  end;
  whole := BuildPdf(SansFont, 'Hello World', true, false, false);
  sub := BuildPdf(SansFont, 'Hello World', false, false, false);
  Check(length(sub) * 4 < length(whole), FormatUtf8('subset PDF % bytes, whole %',
    [length(sub), length(whole)]));
  Check(copy(FirstFontFile(sub), 1, 4) = #0#1#0#0, 'embedded subset is an sfnt');
end;

procedure TPdfSubsetEngineTests.TestSubsetSharedStreamAndTag;
var
  pdf, ttf, tag: RawByteString;
begin
  if PdfFontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IPdfFontSubsetter registered');
    exit;
  end;
  // Latin runs through the WinAnsi instance, Omega through the Type0 one
  pdf := BuildPdf(SansFont, 'Hello '#$CE#$A9, false, false, false);
  CheckEqual(CountOf('/Length1 ', pdf), 1, 'one font file for both instances');
  CheckEqual(CountOf('/FontFile2 ', pdf), 1, 'one shared /FontDescriptor');
  // TrueType + Type0 /BaseFont, CIDFontType2 /BaseFont, /FontName
  tag := FirstSubsetTag(pdf);
  Check(tag <> '', 'subset tag present');
  CheckEqual(CountOf('/' + tag, pdf), 4,
    'the same tag on all fonts and the descriptor');
  ttf := FirstFontFile(pdf);
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, ord('H'))) > 0, 'H kept');
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, $03A9)) > 0, 'Omega kept');
  CheckEqual(SfntCmapLookup(ttf, ord('Z')), 0, 'Z dropped from the cmap');
end;

procedure TPdfSubsetEngineTests.TestSubsetUnionOfStyles;
var
  pdf, ttf: RawByteString;
begin
  if PdfFontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IPdfFontSubsetter registered');
    exit;
  end;
  // Droid Sans Fallback has no bold face: Bold resolves to the same file, so
  // the Regular and Bold fonts share one face and must share one subset
  pdf := BuildPdf('Droid Sans Fallback', #$E4#$B8#$AD, false, false, true);
  if Pos(RawByteString('DroidSansFallback'), pdf) = 0 then
  begin
    Check(true, 'SKIP: Droid Sans Fallback not installed');
    exit;
  end;
  CheckEqual(CountOf('/Length1 ', pdf), 1, 'Regular and Bold share one file');
  ttf := FirstFontFile(pdf);
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, $4E2D)) > 0, 'CJK glyph kept');
  Check(SfntGlyphLength(ttf, SfntCmapLookup(ttf, ord('!'))) > 0,
    '! drawn only in Bold, yet kept in the shared subset');
end;

procedure TPdfSubsetEngineTests.TestSubsetTagIsDeterministic;
var
  a, b: RawByteString;
begin
  if PdfFontSubsetter = nil then
  begin
    Check(true, 'SKIP: no IPdfFontSubsetter registered');
    exit;
  end;
  a := BuildPdf(SansFont, 'Same input', false, false, false);
  b := BuildPdf(SansFont, 'Same input', false, false, false);
  Check(FirstSubsetTag(a) <> '', 'tag present');
  CheckEqual(FirstSubsetTag(a), FirstSubsetTag(b), 'same input, same tag');
  Check(FirstFontFile(a) = FirstFontFile(b), 'same input, same subset bytes');
end;

procedure TPdfSubsetEngineTests.TestSubsetFallbackWithoutSubsetter;
var
  saved: IPdfFontSubsetter;
  whole, sub: RawByteString;
begin
  saved := PdfFontSubsetter;
  PdfFontSubsetter := nil;
  try
    whole := BuildPdf(SansFont, 'Hello', true, false, false);
    sub := BuildPdf(SansFont, 'Hello', false, false, false);
  finally
    PdfFontSubsetter := saved;
  end;
  {$ifdef MSWINDOWS}
  Check(true, 'Windows subsets through CreateFontPackage, not through this');
  {$else}
  Check(FirstFontFile(sub) = FirstFontFile(whole),
    'without a subsetter the whole face is embedded, as before R-12');
  CheckEqual(FirstSubsetTag(sub), '', 'and no subset tag is written');
  {$endif MSWINDOWS}
end;

procedure TPdfSubsetEngineTests.TestTaggedSubsetKeepsToUnicode;
var
  tagged, whole: RawByteString;
begin
  tagged := BuildPdf(SansFont, 'Hello', false, true, false);
  whole := BuildPdf(SansFont, 'Hello', true, false, false);
  if not PdfCanSubsetRetainingGids then
  begin
    Check(FirstFontFile(tagged) = FirstFontFile(whole),
      'without a retain-GID subsetter Tagged embeds the whole face (P-6)');
    exit;
  end;
  // PDF/UA allows subsets, and retained glyph IDs keep the round-trip
  Check(FirstSubsetTag(tagged) <> '', 'tagged output is subset');
  Check(length(FirstFontFile(tagged)) * 10 < length(FirstFontFile(whole)),
    'and much smaller');
  Check(Pos(RawByteString('/ToUnicode'), tagged) > 0,
    'WinAnsi ToUnicode CMap still written (pdffonts: uni=yes)');
end;

procedure TPdfSubsetEngineTests.TestPdfA1StillWholeFace;
var
  pdfa1, whole: RawByteString;
begin
  // PDF/A-1 would need a /CIDSet for a subset, which is not written
  pdfa1 := BuildPdf(SansFont, 'Hello', false, false, false, pdfa1B);
  whole := BuildPdf(SansFont, 'Hello', true, false, false);
  Check(FirstFontFile(pdfa1) = FirstFontFile(whole),
    'PDF/A-1 embeds the whole face');
  // R-15 gave the Windows CreateFontPackage path the same guard, so this
  // now holds on every platform
  CheckEqual(FirstSubsetTag(pdfa1), '', 'no subset tag');
end;

end.
