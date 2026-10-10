/// the CFF reader of the engine (PdfCffParse), on tables built here
// - each table is made by CffTable below, so its every byte is known: no
// font file is checked in
// - the system faces are only read: Hiragino Sans GB on macOS, Noto Sans
// CJK on Linux, a glyf face everywhere
unit test_pdf_cff;

interface

{$I mormot.defines.inc}

uses
  Classes,
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.text,
  mormot.core.unicode,
  mormot.core.test,
  mormot.lib.core,
  mormot.pdf,
  test_pdf_subset,      // DrawUtf8Text, PDF_DEFAULT_CHARSET
  pdf_inspect;          // InflatePdf

type
  /// PdfCffParse test cases
  TPdfCffTests = class(TSynTestCase)
  protected
    procedure CheckCids(const Info: TPdfCffInfo; const Cids: array of integer;
      const Msg: string);
  published
    procedure CidKeyedCharsets;
    procedure NameKeyed;
    procedure Malformed;
    procedure EveryPrefixRefused;
    procedure FlippedBytes;
    procedure FaceTables;
    procedure SystemFaces;
    procedure Type0Codes;
    procedure Type0CodesOfAFace;
    procedure Type0CidCodes;
    procedure SubsetKeepsCids;
    procedure Type0CidPaths;
    procedure FallbackMidRun;
    procedure Type0Routing;
    procedure WinAnsiFontNotWritten;
    procedure EmbeddedPrograms;
    procedure UnembeddedNameKeyed;
    procedure TextStateAcrossQ;
    procedure SystemFaceCids;
  end;

/// a bare 'CFF ' table of Glyphs glyphs
// - CidKeyed: its Top DICT begins with ROS RosReg RosOrd Supplement; the
// String INDEX holds 'Adobe' (SID 391) and 'Identity' (SID 392)
// - Charset: the bytes of the charset, '' for the predefined charset 0
// - Extra: DICT bytes put before the ROS when RosFirst is false, after it
// otherwise
// - OffSize: of the CharStrings INDEX, 0 for the smallest that fits
// - Name: of the Name INDEX; Ordering, Supplement: of the ROS
function CffTable(CidKeyed: boolean; Glyphs: integer;
  const Charset: RawByteString; RosReg: integer = 391; RosOrd: integer = 392;
  const Extra: RawByteString = ''; RosFirst: boolean = true;
  OffSize: integer = 0; const Name: RawByteString = 'Test';
  const Ordering: RawByteString = 'Identity';
  Supplement: integer = 0): RawByteString;

/// a charset of format 0 for the CIDs of glyphs 1, 2, ...
function CffCharset0(const Cids: array of integer): RawByteString;

/// a charset of format 1 or 2 from (first, nLeft) pairs
function CffCharsetRanges(Format: integer; const Ranges: array of integer): RawByteString;

const
  /// the name of the synthetic face of SwapInFakeFace
  FAKE_FACE = 'CffTestFace';

/// a synthetic CID-keyed CFF face: space, W, i are CIDs 140, 136, 135
function FakeRoutingFace: IFontFace;

/// put a provider into FontProvider which gives Face for FAKE_FACE
// - returns the provider before, to be put back; register the name with
// TPdfDocument.AddTrueTypeFont(FAKE_FACE)
function SwapInFakeFace(const Face: IFontFace): IFontProvider;


implementation

function Card16(v: integer): RawByteString;
begin
  result := AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

function Card32(v: cardinal): RawByteString;
begin
  result := AnsiChar(v shr 24) + AnsiChar((v shr 16) and 255) +
            AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

// a DICT integer of 5 bytes, so that the size of the DICT is known before
// the offsets it holds
function DictInt(v: integer): RawByteString;
begin
  result := #29 + AnsiChar(v shr 24) + AnsiChar((v shr 16) and 255) +
            AnsiChar((v shr 8) and 255) + AnsiChar(v and 255);
end;

// an INDEX - OffSize 0 for the smallest that fits
function IndexOf(const Items: array of RawByteString;
  OffSize: integer = 0): RawByteString;
var
  i, o, b: integer;
  data: RawByteString;

  procedure AddOffset(v: integer);
  var
    k: integer;
  begin
    for k := OffSize - 1 downto 0 do
      result := result + AnsiChar((v shr (k * 8)) and 255);
  end;

begin
  result := Card16(length(Items));
  if length(Items) = 0 then
    exit;
  data := '';
  for i := 0 to high(Items) do
    data := data + Items[i];
  if OffSize = 0 then
  begin
    OffSize := 1;
    b := length(data) + 1;
    while b > 255 do
    begin
      b := b shr 8;
      inc(OffSize);
    end;
  end;
  result := result + AnsiChar(OffSize);
  o := 1;
  for i := 0 to high(Items) do
  begin
    AddOffset(o);
    inc(o, length(Items[i]));
  end;
  AddOffset(o);
  result := result + data;
end;

function CffTable(CidKeyed: boolean; Glyphs: integer;
  const Charset: RawByteString; RosReg, RosOrd: integer;
  const Extra: RawByteString; RosFirst: boolean; OffSize: integer;
  const Name, Ordering: RawByteString; Supplement: integer): RawByteString;
var
  ros, dict, head, strings, glyph: RawByteString;
  charstrings: array of RawByteString;
  i, topsize, charsetpos: integer;
begin
  ros := '';
  if CidKeyed then
    ros := DictInt(RosReg) + DictInt(RosOrd) + DictInt(Supplement) + #12#30;
  if RosFirst then
    dict := ros + Extra
  else
    dict := Extra + ros;
  // charset and CharStrings: 5 + 1 bytes each
  topsize := length(dict) + 12;
  if Charset = '' then
    dec(topsize, 6);
  head := #1#0#4#1 + IndexOf([Name]);
  strings := IndexOf(['Adobe', Ordering]);
  // the Top DICT INDEX: 2 + 1 + 2 offsets + topsize
  charsetpos := length(head) + 5 + topsize + length(strings) + 2;
  if Charset <> '' then
    dict := dict + DictInt(charsetpos) + #15;
  dict := dict + DictInt(charsetpos + length(Charset)) + #17;
  SetLength(charstrings, Glyphs);
  glyph := #14; // endchar
  for i := 0 to Glyphs - 1 do
    charstrings[i] := glyph;
  result := head + IndexOf([dict]) + strings + #0#0 + Charset +
            IndexOf(charstrings, OffSize);
end;

function CffCharset0(const Cids: array of integer): RawByteString;
var
  i: integer;
begin
  result := #0;
  for i := 0 to high(Cids) do
    result := result + Card16(Cids[i]);
end;

function CffCharsetRanges(Format: integer; const Ranges: array of integer): RawByteString;
var
  i: integer;
begin
  result := AnsiChar(Format);
  i := 0;
  while i < high(Ranges) do
  begin
    result := result + Card16(Ranges[i]);
    if Format = 1 then
      result := result + AnsiChar(Ranges[i + 1])
    else
      result := result + Card16(Ranges[i + 1]);
    inc(i, 2);
  end;
end;

type
  // a face of the given sfnt tables and nothing else
  TFakeFace = class(TInterfacedObject, IFontFace)
  protected
    fTags: array of cardinal;
    fTables: array of RawByteString;
    fWhole: RawByteString;
  public
    procedure AddTable(const Tag: RawByteString; const Data: RawByteString);
    // the sfnt of the tables added, as GetFontData(0) and GetFaceFile give it
    procedure Seal(const Signature: RawByteString);
    function Handle: TFontHandle;
    function GetTextMetrics(out Metrics: TFontMetrics): boolean;
    function GetOutlineMetrics(out Metrics: TFontOutlineMetrics): boolean;
    function GetCharAbcWidths(FirstChar, LastChar: cardinal;
      out Widths: TFontCharAbcArray): boolean;
    function GetGlyphAdvance(Glyph: cardinal; out Advance: integer): boolean;
    function GetFontData(TableTag, Offset: cardinal; Buffer: pointer;
      BufferSize: cardinal): cardinal;
    function GetFaceFile(out Face: RawByteString): boolean;
  end;

procedure TFakeFace.AddTable(const Tag: RawByteString; const Data: RawByteString);
var
  n: integer;
begin
  n := length(fTags);
  SetLength(fTags, n + 1);
  SetLength(fTables, n + 1);
  fTags[n] := PCardinal(Tag)^; // little-endian, as GetFontData takes it
  fTables[n] := Data;
end;

function TFakeFace.Handle: TFontHandle;
begin
  result := nil;
end;

procedure TFakeFace.Seal(const Signature: RawByteString);
var
  i, n, off: integer;
  dir, data, t, tag: RawByteString;
begin
  n := length(fTags);
  dir := Signature + Card16(n) + Card16(0) + Card16(0) + Card16(0);
  off := 12 + 16 * n;
  data := '';
  for i := 0 to n - 1 do
  begin
    t := fTables[i];
    SetString(tag, PAnsiChar(@fTags[i]), 4);
    dir := dir + tag + Card32(0) + Card32(off + length(data)) +
      Card32(length(t));
    while length(t) and 3 <> 0 do
      t := t + #0;
    data := data + t;
  end;
  fWhole := dir + data;
end;

// metrics of an em of 1000 units, WinAnsi advances of 300 + 20 * (c mod 10)
function TFakeFace.GetTextMetrics(out Metrics: TFontMetrics): boolean;
begin
  FillChar(Metrics, SizeOf(Metrics), 0);
  Metrics.tmHeight := 1000;
  Metrics.tmAscent := 800;
  Metrics.tmDescent := 200;
  Metrics.tmAveCharWidth := 500;
  Metrics.tmMaxCharWidth := 510;
  Metrics.tmWeight := 400;
  Metrics.tmPitchAndFamily := 1; // TMPF_FIXED_PITCH set: proportional (GDI)
  result := true;
end;

function TFakeFace.GetOutlineMetrics(out Metrics: TFontOutlineMetrics): boolean;
begin
  FillChar(Metrics, SizeOf(Metrics), 0);
  Metrics.otmAscent := 800;
  Metrics.otmDescent := -200;
  Metrics.otmrcFontBox.Right := 1000;
  Metrics.otmrcFontBox.Top := 800;
  Metrics.otmrcFontBox.Bottom := -200;
  Metrics.otmEMSquare := 1000;
  result := true;
end;

function TFakeFace.GetCharAbcWidths(FirstChar, LastChar: cardinal;
  out Widths: TFontCharAbcArray): boolean;
var
  i: integer;
begin
  SetLength(Widths, LastChar - FirstChar + 1);
  for i := 0 to high(Widths) do
  begin
    Widths[i].abcA := 0;
    Widths[i].abcB := 300 + ((integer(FirstChar) + i) mod 10) * 20;
    Widths[i].abcC := 0;
  end;
  result := true;
end;

function TFakeFace.GetGlyphAdvance(Glyph: cardinal; out Advance: integer): boolean;
begin
  Advance := 100 + integer(Glyph) * 10; // as FakeHmtx
  result := true;
end;

function TFakeFace.GetFontData(TableTag, Offset: cardinal; Buffer: pointer;
  BufferSize: cardinal): cardinal;
var
  i: integer;
begin
  result := FONT_DATA_ERROR;
  if (TableTag = 0) and
     (fWhole <> '') then
  begin
    if Offset > cardinal(length(fWhole)) then
      exit;
    result := cardinal(length(fWhole)) - Offset;
    if Buffer <> nil then
    begin
      if result > BufferSize then
        result := BufferSize;
      MoveFast(PByteArray(fWhole)[Offset], Buffer^, result);
    end;
    exit;
  end;
  for i := 0 to high(fTags) do
    if fTags[i] = TableTag then
    begin
      if Offset > cardinal(length(fTables[i])) then
        exit;
      result := cardinal(length(fTables[i])) - Offset;
      if Buffer <> nil then
      begin
        if result > BufferSize then
          result := BufferSize;
        MoveFast(PByteArray(fTables[i])[Offset], Buffer^, result);
      end;
      exit;
    end;
end;

function TFakeFace.GetFaceFile(out Face: RawByteString): boolean;
begin
  Face := fWhole;
  result := Face <> '';
end;

type
  // CreateFace gives Face for Name, and asks the provider before it otherwise
  TFakeProvider = class(TInterfacedObject, IFontProvider)
  protected
    fPrevious: IFontProvider;
    fFace: IFontFace;
    fName: SynUnicode;
  public
    constructor Create(const Previous: IFontProvider; const Face: IFontFace;
      const Name: RawUtf8);
    function CreateFace(const Request: TFontRequest): IFontFace;
  end;

constructor TFakeProvider.Create(const Previous: IFontProvider;
  const Face: IFontFace; const Name: RawUtf8);
begin
  inherited Create;
  fPrevious := Previous;
  fFace := Face;
  fName := Utf8ToSynUnicode(Name);
end;

function TFakeProvider.CreateFace(const Request: TFontRequest): IFontFace;
begin
  if Request.FaceName = fName then
    result := fFace
  else
    result := fPrevious.CreateFace(Request);
end;

const
  FAKE_GLYPHS = 42;

// 'head' of an em of 1000 units
function FakeHead: RawByteString;
begin
  result := Card32($00010000) + Card32($00010000) + Card32(0) +
    Card32($5F0F3CF5) + Card16(0) + Card16(1000) + StringOfChar(#0, 16) +
    Card16(0) + Card16(65336) + Card16(1000) + Card16(800) +
    Card16(0) + Card16(3) + Card16(2) + Card16(0) + Card16(0);
end;

// 'hhea' with FAKE_GLYPHS advances
function FakeHhea: RawByteString;
begin
  result := Card32($00010000) + Card16(800) + Card16(65336) + Card16(0) +
    Card16(510) + StringOfChar(#0, 22) + Card16(FAKE_GLYPHS);
end;

// 'hmtx': glyph g advances 100 + 10 * g units
function FakeHmtx: RawByteString;
var
  g: integer;
begin
  result := '';
  for g := 0 to FAKE_GLYPHS - 1 do
    result := result + Card16(100 + g * 10) + Card16(0);
end;

function FakeMaxp: RawByteString;
begin
  result := Card32($00005000) + Card16(FAKE_GLYPHS);
end;

// a (3,1) 'cmap' of format 4: Chars[i] -> Glyphs[i], one segment each
function FakeCmap(const Chars, Glyphs: array of integer): RawByteString;
var
  i, n: integer;
  ends, starts, deltas, ranges: RawByteString;
begin
  n := length(Chars) + 1; // and the final $FFFF segment
  ends := '';
  starts := '';
  deltas := '';
  ranges := '';
  for i := 0 to high(Chars) do
  begin
    ends := ends + Card16(Chars[i]);
    starts := starts + Card16(Chars[i]);
    deltas := deltas + Card16((Glyphs[i] - Chars[i]) and $ffff);
    ranges := ranges + Card16(0);
  end;
  ends := ends + Card16($ffff);
  starts := starts + Card16($ffff);
  deltas := deltas + Card16(1);
  ranges := ranges + Card16(0);
  result := Card16(4) + Card16(16 + n * 8) + Card16(0) + Card16(n * 2) +
    Card16(0) + Card16(0) + Card16(0) + ends + Card16(0) + starts + deltas +
    ranges;
  result := Card16(0) + Card16(1) + Card16(3) + Card16(1) + Card32(12) + result;
end;

// a 'name' table of one PostScript name (ID 6), Windows Unicode
function FakeNameTable(const PostScript: RawByteString): RawByteString;
var
  i: integer;
  utf16: RawByteString;
begin
  utf16 := '';
  for i := 1 to length(PostScript) do
    utf16 := utf16 + #0 + PostScript[i];
  result := Card16(0) + Card16(1) + Card16(6 + 12) +
    Card16(3) + Card16(1) + Card16($409) + Card16(6) + Card16(length(utf16)) +
    Card16(0) + utf16;
end;

// a face of the tables above, mapping Chars to Glyphs, with Cff if not ''
// - Marker: the bytes of a table 'zzzz', to find the face in a PDF
// - PostScript: the name ID 6 of a 'name' table, none if ''
function FakeFace(const Chars, Glyphs: array of integer;
  const Cff: RawByteString; const Marker: RawByteString = '';
  const PostScript: RawByteString = ''): TFakeFace;
begin
  result := TFakeFace.Create;
  if Cff <> '' then
    result.AddTable('CFF ', Cff);
  if Marker <> '' then
    result.AddTable('zzzz', Marker);
  if PostScript <> '' then
    result.AddTable('name', FakeNameTable(PostScript));
  result.AddTable('cmap', FakeCmap(Chars, Glyphs));
  result.AddTable('head', FakeHead);
  result.AddTable('hhea', FakeHhea);
  result.AddTable('hmtx', FakeHmtx);
  result.AddTable('maxp', FakeMaxp);
  if Cff <> '' then
    result.Seal('OTTO')
  else
    result.Seal(#0#1#0#0);
end;

const
  // Greek, Cyrillic and Latin Extended, out of the glyph order of most faces
  MIXED_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$03C9#$03B1#$03B2' '#$0416#$0434' '#$0101#$0100#$0436#$03B3
    {$else}
    #$CF#$89#$CE#$B1#$CE#$B2' '#$D0#$96#$D0#$B4' '#$C4#$81#$C4#$80#$D0#$B6#$CE#$B3
    {$endif};

// the hex value of <XXXX> at s[i], -1 if there is none
function Hex4At(const s: RawUtf8; i: PtrInt): integer;
var
  k, v: integer;
begin
  result := -1;
  if (i < 1) or
     (i + 5 > length(s)) or
     (s[i] <> '<') or
     (s[i + 5] <> '>') then
    exit;
  v := 0;
  for k := i + 1 to i + 4 do
    case s[k] of
      '0'..'9':
        v := v * 16 + ord(s[k]) - ord('0');
      'A'..'F':
        v := v * 16 + ord(s[k]) - ord('A') + 10;
    else
      exit;
    end;
  result := v;
end;

function Parse(const Table: RawByteString; out Info: TPdfCffInfo): TPdfCffKind;
begin
  result := PdfCffParse(pointer(Table), length(Table), Info);
end;


{ TPdfCffTests }

procedure TPdfCffTests.CheckCids(const Info: TPdfCffInfo;
  const Cids: array of integer; const Msg: string);
var
  i: integer;
  ok: boolean;
begin
  ok := length(Info.Cid) = length(Cids);
  if ok then
    for i := 0 to high(Cids) do
      if Info.Cid[i] <> Cids[i] then
        ok := false;
  Check(ok, Msg);
end;

procedure TPdfCffTests.CidKeyedCharsets;
var
  info: TPdfCffInfo;
begin
  // format 0: glyphs 1, 2, 3 are CIDs 7, 2, 41
  CheckEqual(ord(Parse(CffTable(true, 4, CffCharset0([7, 2, 41])), info)),
    ord(pcCidKeyed), 'format 0');
  CheckEqual(info.GlyphCount, 4);
  CheckEqual(info.Registry, 'Adobe');
  CheckEqual(info.Ordering, 'Identity');
  CheckEqual(info.Supplement, 0);
  CheckCids(info, [0, 7, 2, 41], 'format 0 CIDs');
  // format 1: 10..11, then 5
  Check(Parse(CffTable(true, 4, CffCharsetRanges(1, [10, 1, 5, 0])), info) =
    pcCidKeyed, 'format 1');
  CheckCids(info, [0, 10, 11, 5], 'format 1 CIDs');
  // format 2: 100..102
  Check(Parse(CffTable(true, 4, CffCharsetRanges(2, [100, 2])), info) =
    pcCidKeyed, 'format 2');
  CheckCids(info, [0, 100, 101, 102], 'format 2 CIDs');
  // a last range beyond the glyphs ends with them
  Check(Parse(CffTable(true, 3, CffCharsetRanges(2, [1, 300])), info) =
    pcCidKeyed, 'long range');
  CheckCids(info, [0, 1, 2], 'long range CIDs');
  // the identity, written out
  Check(Parse(CffTable(true, 5, CffCharsetRanges(1, [1, 3])), info) =
    pcCidKeyed, 'identity');
  CheckCids(info, [0, 1, 2, 3, 4], 'identity CIDs');
  // 300 glyphs: CharStrings offsets of 2 bytes; then of 3 and 4 bytes
  Check(Parse(CffTable(true, 300, CffCharsetRanges(2, [1, 298])), info) =
    pcCidKeyed, '300 glyphs');
  CheckEqual(info.GlyphCount, 300);
  CheckEqual(info.Cid[299], 299);
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 41]), 391, 392, '', true,
    3), info) = pcCidKeyed, 'offSize 3');
  CheckCids(info, [0, 7, 2, 41], 'offSize 3 CIDs');
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 41]), 391, 392, '', true,
    4), info) = pcCidKeyed, 'offSize 4');
  CheckCids(info, [0, 7, 2, 41], 'offSize 4 CIDs');
  // reals and other operators after the ROS are skipped: FontMatrix
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 41]),
    391, 392, #30#$0a#$00#$1f#$8b#$8b#30#$0a#$00#$1f#$8b#$8b#12#7), info) =
    pcCidKeyed, 'FontMatrix');
  CheckCids(info, [0, 7, 2, 41], 'FontMatrix CIDs');
end;

procedure TPdfCffTests.NameKeyed;
var
  info: TPdfCffInfo;
begin
  // FontMatrix 0.001 0 0 0.001 0 0, its reals skipped
  Check(Parse(CffTable(false, 3, CffCharset0([5, 6]), 0, 0,
    #30#$0a#$00#$1f#$8b#$8b#30#$0a#$00#$1f#$8b#$8b#12#7), info) =
    pcNameKeyed, 'name-keyed');
  CheckEqual(info.GlyphCount, 3);
  Check(info.Cid = nil, 'no CIDs: the glyph index is the code');
  CheckEqual(info.Registry, '');
  // the charset of glyph names is not read
  Check(Parse(CffTable(false, 3, #9#9), info) = pcNameKeyed, 'any charset');
  Check(PdfCffParse(nil, 0, info) = pcNone, 'no table');
  Check(info.Kind = pcNone, 'Kind');
end;

procedure TPdfCffTests.Malformed;
var
  info: TPdfCffInfo;
  t: RawByteString;
begin
  Check(Parse(CffTable(true, 4, CffCharset0([7, 2, 7])), info) = pcInvalid,
    'duplicate CID');
  Check(info.Kind = pcInvalid, 'Kind');
  Check(info.Cid = nil, 'no CIDs of a refused table');
  Check(Parse(CffTable(true, 3, CffCharset0([0, 2])), info) = pcInvalid,
    'CID 0 beyond glyph 0');
  Check(Parse(CffTable(true, 3, CffCharsetRanges(1, [65535, 1])), info) =
    pcInvalid, 'range beyond 65535');
  Check(Parse(CffTable(true, 3, CffCharsetRanges(3, [1, 1])), info) =
    pcInvalid, 'charset format 3');
  // a CIDFont has no predefined charset: none given, 1 (Expert) given
  Check(Parse(CffTable(true, 5, ''), info) = pcInvalid, 'charset 0');
  Check(Parse(CffTable(true, 5, '', 391, 392, DictInt(1) + #15), info) =
    pcInvalid, 'charset 1');
  Check(Parse(CffTable(true, 3, CffCharset0([1, 2]), 300), info) = pcInvalid,
    'standard string SID');
  Check(Parse(CffTable(true, 3, CffCharset0([1, 2]), 391, 393), info) =
    pcInvalid, 'SID out of the String INDEX');
  // ROS after another operator: version SID 0
  Check(Parse(CffTable(true, 3, CffCharset0([1, 2]), 391, 392, #$8b#0, false),
    info) = pcInvalid, 'ROS not first');
  // an operand too many, a reserved byte
  Check(Parse(CffTable(false, 3, '', 0, 0, #$8b), info) = pcInvalid,
    'CharStrings with two operands');
  Check(Parse(CffTable(false, 3, '', 0, 0, #255#0), info) = pcInvalid,
    'reserved byte');
  // the header and the INDEX structure
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[1] := #2;
  Check(Parse(t, info) = pcInvalid, 'major version 2');
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[7] := #5; // the offSize of the Name INDEX
  Check(Parse(t, info) = pcInvalid, 'offSize 5');
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[8] := #2; // its first offset
  Check(Parse(t, info) = pcInvalid, 'first offset not 1');
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  t[9] := #$ff; // its last offset
  Check(Parse(t, info) = pcInvalid, 'offset beyond the table');
end;

procedure TPdfCffTests.EveryPrefixRefused;
var
  info: TPdfCffInfo;
  t, cut: RawByteString;
  l: integer;
  ok: boolean;
begin
  // the CharStrings INDEX ends each table: no prefix is a whole one
  t := CffTable(true, 4, CffCharset0([7, 2, 41]));
  Check(Parse(t, info) = pcCidKeyed);
  ok := true;
  for l := 1 to length(t) - 1 do
  begin
    cut := copy(t, 1, l);
    if Parse(cut, info) <> pcInvalid then
      ok := false;
  end;
  Check(ok, 'every prefix of a CID-keyed table');
  t := CffTable(false, 4, '');
  ok := true;
  for l := 1 to length(t) - 1 do
  begin
    cut := copy(t, 1, l);
    if Parse(cut, info) <> pcInvalid then
      ok := false;
  end;
  Check(ok, 'every prefix of a name-keyed table');
end;

procedure TPdfCffTests.FlippedBytes;
var
  info: TPdfCffInfo;
  t, f: RawByteString;
  i, v: integer;
  k: TPdfCffKind;
  ok: boolean;
begin
  // whatever a byte becomes, the reader returns a kind and nothing else:
  // a CID-keyed answer still has one CID per glyph
  t := CffTable(true, 4, CffCharsetRanges(1, [10, 1, 5, 0]));
  ok := true;
  for i := 1 to length(t) do
    for v := 0 to 255 do
    begin
      f := t;
      f[i] := AnsiChar(v);
      k := Parse(f, info);
      if (k = pcCidKeyed) and
         (length(info.Cid) <> info.GlyphCount) then
        ok := false;
    end;
  Check(ok, 'every byte of a table, every value');
end;

procedure TPdfCffTests.FaceTables;
var
  info: TPdfCffInfo;
  face: TFakeFace;
  intf: IFontFace;
begin
  Check(PdfFaceCffInfo(nil, info) = pcNone, 'no face');
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('glyf', #0#0);
  Check(PdfFaceCffInfo(intf, info) = pcNone, 'glyf face');
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('CFF ', CffTable(true, 4, CffCharset0([7, 2, 41])));
  Check(PdfFaceCffInfo(intf, info) = pcCidKeyed, 'CFF face');
  CheckCids(info, [0, 7, 2, 41], 'its CIDs, read raw');
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('CFF ', 'garbage');
  Check(PdfFaceCffInfo(intf, info) = pcInvalid, 'malformed CFF face');
  // CFF2 is no CFF a PDF 1.x font program allows, and no glyf face either
  face := TFakeFace.Create;
  intf := face;
  face.AddTable('CFF2', #2#0#5#0#0);
  Check(PdfFaceCffInfo(intf, info) = pcInvalid, 'CFF2 face');
end;

procedure TPdfCffTests.SystemFaces;
var
  lf: TFontRequest;
  info: TPdfCffInfo;
  i, diff: integer;
  identity: boolean;

  function Face(const Name: RawUtf8): IFontFace;
  begin
    FillChar(lf, SizeOf(lf), 0);
    lf.FaceName := SynUnicode(Name);
    lf.Height := -1000;
    lf.Weight := 400;
    result := FontProvider.CreateFace(lf);
  end;

begin
  // a glyf face has no 'CFF ' table
  if PdfFaceCffInfo(Face({$ifdef OSWINDOWS} 'Arial' {$else}
       {$ifdef OSDARWIN} 'Helvetica' {$else} 'DejaVu Sans' {$endif}
       {$endif}), info) = pcNone then
    Check(true)
  else
    Check(true, 'SKIP: the glyf face resolved to a CFF face');
  {$ifdef OSDARWIN}
  // the CJK face of the Mac tests: CID-keyed, 288 glyphs whose CID differs
  Check(PdfFaceCffInfo(Face('Hiragino Sans GB'), info) = pcCidKeyed,
    'Hiragino Sans GB');
  CheckEqual(info.Registry, 'Adobe');
  diff := 0;
  for i := 0 to high(info.Cid) do
    if info.Cid[i] <> i then
      inc(diff);
  CheckEqual(diff, 288, 'glyphs whose CID is not their index');
  {$else}
  {$ifdef OSLINUX}
  // Noto Sans CJK is Adobe-Identity-0: CID-keyed, every CID its index
  if PdfFaceCffInfo(Face('Noto Sans CJK JP'), info) = pcCidKeyed then
  begin
    CheckEqual(info.Registry, 'Adobe');
    CheckEqual(info.Ordering, 'Identity');
    identity := true;
    for i := 0 to high(info.Cid) do
      if info.Cid[i] <> i then
        identity := false;
    Check(identity, 'Noto Sans CJK: the identity');
  end
  else
    Check(true, 'SKIP: Noto Sans CJK JP not installed');
  {$else}
  Check(true, 'SKIP: no CFF system face known here');
  {$endif OSLINUX}
  {$endif OSDARWIN}
end;

procedure TPdfCffTests.Type0Codes;
var
  pdf: TPdfDocument;
  stream: TMemoryStream;
  sans, serif, mono: string;
  s: RawUtf8;
  i, j, e, code, last, runs, chars: PtrInt;
  sorted: boolean;
begin
  // /W and /ToUnicode of a Type0 font are keyed by the code, sorted, one
  // entry per code, under the codespace of every two-byte code
  stream := TMemoryStream.Create;
  try
    pdf := TPdfDocument.Create(false, 0, pdfaNone);
    try
      pdf.CompressionMethod := cmNone;
      pdf.EmbeddedTTF := true;
      pdf.AddPage;
      GetPdfFonts(true, sans, serif, mono);
      pdf.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(pdf, 40, 700, MIXED_TEXT);
      pdf.SaveToStream(stream);
    finally
      pdf.Free;
    end;
    SetLength(s, stream.Size);
    stream.Position := 0;
    stream.Read(pointer(s)^, stream.Size);
  finally
    stream.Free;
  end;
  s := InflatePdf(s);
  // /W [c [w ...] c [w ...]]: each run starts after the end of the one before
  i := PosEx('/W [', s);
  Check(i > 0, '/W');
  inc(i, 4);
  last := -1;
  runs := 0;
  sorted := true;
  while (i <= length(s)) and
        (s[i] in ['0'..'9']) do
  begin
    code := 0;
    while s[i] in ['0'..'9'] do
    begin
      code := code * 10 + ord(s[i]) - ord('0');
      inc(i);
    end;
    if code <= last then
      sorted := false;
    e := PosEx(']', s, i);
    if (s[i] <> '[') or
       (e = 0) then
      break;
    last := code;
    for j := i + 1 to e - 1 do
      if s[j] = ' ' then
        inc(last); // one width more in this run
    inc(runs);
    i := e + 1;
  end;
  Check(runs > 0, 'runs of /W');
  Check(sorted, '/W sorted by code, no code twice');
  // /ToUnicode
  Check(PosEx('begincodespacerange'#10'<0000> <FFFF>'#10, s) > 0, 'codespace');
  i := PosEx('beginbfchar'#10, s);
  Check(i > 0, 'bfchar');
  inc(i, 12);
  last := -1;
  chars := 0;
  sorted := true;
  while Hex4At(s, i) >= 0 do
  begin
    code := Hex4At(s, i);
    if code <= last then
      sorted := false;
    last := code;
    inc(chars);
    i := PosEx(#10, s, i) + 1;
    if copy(s, i, 9) = 'endbfchar' then
      i := PosEx('beginbfchar'#10, s, i) + 12;
  end;
  CheckEqual(chars, 9, 'one code per character out of WinAnsi');
  Check(sorted, '/ToUnicode sorted by code, no code twice');
end;

type
  // draws on the page of FakeFacePdf instead of Text in the fake face
  TFakeDraw = procedure(Pdf: TPdfDocument);

// draw Text in the fake face, return the inflated PDF
// - with a Subsetter, the face is embedded and subset by it
var
  // the PDF/A level of the documents of FakeFacePdf, and whether it embeds
  FakePdfA: TPdfALevel;
  FakeEmbedded: boolean;

function FakeFacePdf(const Face: IFontFace; const Text: RawUtf8;
  const Subsetter: IFontSubsetter = nil; Draw: TFakeDraw = nil): RawUtf8;
var
  pdf: TPdfDocument;
  stream: TMemoryStream;
  previous: IFontProvider;
  previoussub: IFontSubsetter;
begin
  previous := FontProvider;
  previoussub := FontSubsetter;
  FontProvider := TFakeProvider.Create(previous, Face, FAKE_FACE);
  if Subsetter <> nil then
    FontSubsetter := Subsetter; // before Create: it decides EmbeddedWholeTtf
  try
    stream := TMemoryStream.Create;
    try
      pdf := TPdfDocument.Create(false, 0, FakePdfA);
      try
        pdf.CompressionMethod := cmNone;
        pdf.EmbeddedTTF := (Subsetter <> nil) or FakeEmbedded;
        pdf.AddTrueTypeFont(FAKE_FACE);
        pdf.AddPage;
        if Assigned(Draw) then
          Draw(pdf)
        else
        begin
          pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
          DrawUtf8Text(pdf, 40, 700, Text);
        end;
        pdf.SaveToStream(stream);
      finally
        pdf.Free;
      end;
      SetLength(result, stream.Size);
      stream.Position := 0;
      stream.Read(pointer(result)^, stream.Size);
    finally
      stream.Free;
    end;
  finally
    FontProvider := previous;
    FontSubsetter := previoussub;
  end;
  result := InflatePdf(result);
end;

// a charset of format 0 giving glyph g of Count the CID Shift - g
function FakeCidCharset(Shift: integer = 141;
  Count: integer = FAKE_GLYPHS): RawByteString;
var
  g: integer;
  cids: array of integer;
begin
  SetLength(cids, Count - 1);
  for g := 1 to Count - 1 do
    cids[g - 1] := Shift - g;
  result := CffCharset0(cids);
end;

const
  // U+0100..U+0104: glyphs 7, 2, 3, 7, 41 - U+0103 an alias of U+0100
  ALIAS_CHARS: array[0..4] of integer = ($100, $101, $102, $103, $104);
  ALIAS_GLYPHS: array[0..4] of integer = (7, 2, 3, 7, 41);
  ALIAS_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0104#$0100#$0101#$0103#$0102
    {$else}
    #$C4#$84#$C4#$80#$C4#$81#$C4#$83#$C4#$82
    {$endif};

type
  // Subset gives Output, whatever it is asked
  TFakeSubsetter = class(TInterfacedObject, IFontSubsetter)
  protected
    fOutput: RawByteString;
  public
    Called: integer;
    constructor Create(const Output: RawByteString);
    function Subset(const Face: RawByteString; const Request: TFontSubsetRequest;
      Font: TFontHandle; out Output: RawByteString): boolean;
    function SupportsSymbolic: boolean;
  end;

constructor TFakeSubsetter.Create(const Output: RawByteString);
begin
  inherited Create;
  fOutput := Output;
end;

function TFakeSubsetter.Subset(const Face: RawByteString;
  const Request: TFontSubsetRequest; Font: TFontHandle;
  out Output: RawByteString): boolean;
begin
  inc(Called);
  Output := fOutput;
  result := true;
end;

function TFakeSubsetter.SupportsSymbolic: boolean;
begin
  result := true;
end;

procedure TPdfCffTests.Type0CodesOfAFace;
var
  s: RawUtf8;
begin
  // a face built here: the codes, their widths and their characters are
  // known whatever fonts are installed
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS, ''), ALIAS_TEXT);
  Check(PosEx('/W [2[120 130]7[170]41[510]]', s) > 0,
    'runs of /W: sorted, code 7 once, widths of hmtx');
  Check(PosEx('4 beginbfchar'#10'<0002> <0101>'#10'<0003> <0102>'#10 +
    '<0007> <0100>'#10'<0029> <0104>'#10'endbfchar', s) > 0,
    '/ToUnicode: sorted, the smaller character of code 7');
  Check(PosEx('<00290007000200070003>', s) > 0, 'the text in glyph codes');
end;

procedure TPdfCffTests.Type0CidCodes;
var
  s: RawUtf8;
begin
  // glyph g is CID 141 - g: the codes are 100 (glyph 41), 134 (7), 138 (3)
  // and 139 (2), /W and /ToUnicode sorted by them
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset)), ALIAS_TEXT);
  Check(PosEx('/W [100[510]134[170]138[130 120]]', s) > 0,
    '/W keyed by CID, the widths of the glyphs');
  Check(PosEx('4 beginbfchar'#10'<0064> <0104>'#10'<0086> <0100>'#10 +
    '<008A> <0102>'#10'<008B> <0101>'#10'endbfchar', s) > 0,
    '/ToUnicode keyed by CID');
  Check(PosEx('<00640086008B0086008A>', s) > 0, 'the text in CIDs');
  // a name-keyed face: the glyph index is the code
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(false, FAKE_GLYPHS, '')), ALIAS_TEXT);
  Check(PosEx('<00290007000200070003>', s) > 0, 'name-keyed: glyph codes');
end;

procedure TPdfCffTests.SubsetKeepsCids;
var
  s: RawUtf8;
  sub: TFakeSubsetter;
  keep: IFontSubsetter;
begin
  // a subset whose charset gives the glyphs the CIDs of the face is embedded
  sub := TFakeSubsetter.Create(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'SUBSET-SAME-CIDS')).fWhole);
  keep := sub;
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'THE-WHOLE-FACE')),
    ALIAS_TEXT, keep);
  CheckEqual(sub.Called, 1, 'subset asked');
  Check(PosEx('SUBSET-SAME-CIDS', s) > 0, 'the subset embedded');
  Check(PosEx('THE-WHOLE-FACE', s) = 0, 'not the face');
  // other CIDs: the content would draw other glyphs - the face is embedded
  sub := TFakeSubsetter.Create(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset(142), 391, 392, '', true, 0,
    'SUBSET-OTHER-CIDS')).fWhole);
  keep := sub;
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'THE-WHOLE-FACE')),
    ALIAS_TEXT, keep);
  CheckEqual(sub.Called, 1, 'subset asked');
  Check(PosEx('SUBSET-OTHER-CIDS', s) = 0, 'not the subset');
  Check(PosEx('THE-WHOLE-FACE', s) > 0, 'the face embedded');
  // a subset that is no CID-keyed CFF any more
  sub := TFakeSubsetter.Create(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(false, FAKE_GLYPHS, '', 391, 392, '', true, 0,
    'SUBSET-NAME-KEYED')).fWhole);
  keep := sub;
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'THE-WHOLE-FACE')),
    ALIAS_TEXT, keep);
  Check(PosEx('SUBSET-NAME-KEYED', s) = 0, 'not the name-keyed subset');
  Check(PosEx('THE-WHOLE-FACE', s) > 0, 'the face embedded instead');
  // the same CIDs, but glyph 41 left out: CID 100 would draw nothing
  sub := TFakeSubsetter.Create(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, 8, FakeCidCharset(141, 8), 391, 392, '', true, 0,
    'SUBSET-TOO-SHORT')).fWhole);
  keep := sub;
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'THE-WHOLE-FACE')),
    ALIAS_TEXT, keep);
  Check(PosEx('SUBSET-TOO-SHORT', s) = 0, 'not a subset without glyph 41');
  Check(PosEx('THE-WHOLE-FACE', s) > 0, 'the face embedded for it');
end;

procedure TPdfCffTests.SystemFaceCids;
{$ifdef OSDARWIN}
const
  // U+9FA6: glyph 29064 of Hiragino Sans GB, CID 30284 ($764C)
  CHAR_9FA6: RawUtf8 = {$ifdef HASCODEPAGE} #$9FA6 {$else} #$E9#$BE#$A6 {$endif};
var
  pdf: TPdfDocument;
  stream: TMemoryStream;
  s: RawUtf8;
begin
  stream := TMemoryStream.Create;
  try
    pdf := TPdfDocument.Create(false, 0, pdfaNone);
    try
      pdf.CompressionMethod := cmNone;
      pdf.EmbeddedTTF := true;
      pdf.AddPage;
      pdf.Canvas.SetFont('Hiragino Sans GB', 12, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(pdf, 40, 700, CHAR_9FA6);
      pdf.SaveToStream(stream);
    finally
      pdf.Free;
    end;
    SetLength(s, stream.Size);
    stream.Position := 0;
    stream.Read(pointer(s)^, stream.Size);
  finally
    stream.Free;
  end;
  s := InflatePdf(s);
  Check(PosEx('<764C>', s) > 0, 'U+9FA6 drawn as CID 30284, not glyph 29064');
  Check(PosEx('<7188>', s) = 0, 'no glyph index');
  Check(PosEx('/W [30284[', s) > 0, '/W keyed by the CID');
  Check(PosEx('<764C> <9FA6>', s) > 0, '/ToUnicode keyed by the CID');
end;
{$else}
begin
  Check(true, 'SKIP: Hiragino Sans GB is a macOS face');
end;
{$endif OSDARWIN}

type
  // Shape gives one shaped run of the glyphs 41, 7, 2 - with the advances of
  // the face when Mode > 0, with offsets too when Mode > 1
  TFakeShaper = class(TInterfacedObject, IFontShaper)
  public
    Mode: integer;
    function Shape(Text: PWideChar; Len: integer; Font: TFontHandle;
      RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
  end;

function TFakeShaper.Shape(Text: PWideChar; Len: integer; Font: TFontHandle;
  RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
begin
  SetLength(Runs, 1);
  Runs[0].Kind := fskShaped;
  Runs[0].Outcome := fsoDone;
  Runs[0].TextStart := 0;
  Runs[0].TextLen := Len;
  SetLength(Runs[0].Glyphs, 3);
  Runs[0].Glyphs[0] := 41;
  Runs[0].Glyphs[1] := 7;
  Runs[0].Glyphs[2] := 2;
  if Mode > 0 then
  begin
    SetLength(Runs[0].Advances, 3);
    Runs[0].Advances[0] := 510; // as FakeHmtx: no correction needed
    Runs[0].Advances[1] := 170;
    Runs[0].Advances[2] := 120;
  end;
  if Mode > 1 then
  begin
    SetLength(Runs[0].Offsets, 3);
    Runs[0].Offsets[1] := 50;
  end;
  result := true;
end;

procedure DrawShaped(Pdf: TPdfDocument);
begin
  Pdf.UseUniscribe := true;
  Pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
  DrawUtf8Text(Pdf, 40, 700, ALIAS_TEXT);
end;

procedure DrawGlyphs(Pdf: TPdfDocument);
var
  g: array[0..2] of word;
begin
  Pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
  g[0] := 41;
  g[1] := 7;
  g[2] := 0;
  Pdf.Canvas.BeginText;
  Pdf.Canvas.MoveTextPoint(40, 700);
  Pdf.Canvas.ShowGlyph(@g[0], 3);
  Pdf.Canvas.EndText;
end;

const
  // U+0101: in every system sans face, not in WinAnsi
  ALIAS_A: RawUtf8 = {$ifdef HASCODEPAGE} #$0101 {$else} #$C4#$81 {$endif};
  // U+FDD0 is a noncharacter: no system face maps it, the fake face does
  CHAR_FDD0: RawUtf8 = {$ifdef HASCODEPAGE} #$FDD0 {$else} #$EF#$B7#$90 {$endif};
  // U+0200 is in no cmap of the fake face
  CHAR_0200: RawUtf8 = {$ifdef HASCODEPAGE} #$0200 {$else} #$C8#$80 {$endif};

procedure DrawFallback(Pdf: TPdfDocument);
var
  sans, serif, mono: string;
begin
  GetPdfFonts(true, sans, serif, mono);
  Pdf.FontFallBackName := FAKE_FACE;
  Pdf.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
  DrawUtf8Text(Pdf, 40, 700, CHAR_FDD0);
end;

procedure DrawMissing(Pdf: TPdfDocument);
begin
  Pdf.UseFontFallBack := false;
  Pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
  DrawUtf8Text(Pdf, 40, 700, CHAR_0200);
end;

procedure DrawFallbackMidRun(Pdf: TPdfDocument);
var
  sans, serif, mono: string;
begin
  GetPdfFonts(true, sans, serif, mono);
  Pdf.FontFallBackName := FAKE_FACE;
  Pdf.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
  // U+0101 in the system face, then U+FDD0 from the fallback, then U+0101
  DrawUtf8Text(Pdf, 40, 700, ALIAS_A + CHAR_FDD0 + ALIAS_A);
end;

procedure TPdfCffTests.Type0CidPaths;
var
  face: IFontFace;
  shaper: TFakeShaper;
  previous: IFontShaper;
  s: RawUtf8;
  m: integer;
begin
  // every writer of Type0 codes writes the CID: glyph g is CID 141 - g
  face := FakeFace([$100, $101, $102, $103, $104, $FDD0], [7, 2, 3, 7, 41, 41],
    CffTable(true, FAKE_GLYPHS, FakeCidCharset));
  // the three branches of a shaped run: font advances, advances, offsets
  previous := FontShaper;
  shaper := TFakeShaper.Create;
  FontShaper := shaper;
  try
    for m := 0 to 2 do
    begin
      shaper.Mode := m;
      s := FakeFacePdf(face, '', nil, DrawShaped);
      if m < 2 then
        Check(PosEx('<00640086008B> Tj', s) > 0, 'shaped run in CIDs')
      else
        Check(PosEx('[<0064> -50<0086> 50<008B>] TJ', s) > 0,
          'positioned glyphs in CIDs');
    end;
  finally
    FontShaper := previous;
  end;
  // explicit glyphs, glyph 0 among them
  s := FakeFacePdf(face, '', nil, DrawGlyphs);
  Check(PosEx('<006400860000> Tj', s) > 0, 'ShowGlyph in CIDs');
  // the fallback face draws the character its own way
  s := FakeFacePdf(face, '', nil, DrawFallback);
  Check(PosEx('<0064> Tj', s) > 0, 'the fallback face writes its CID');
  // a character the face has no glyph for: .notdef, CID 0
  s := FakeFacePdf(face, '', nil, DrawMissing);
  Check(PosEx('<0000> Tj', s) > 0, 'no glyph: CID 0');
end;

procedure TPdfCffTests.FallbackMidRun;
var
  s: RawUtf8;
  i, j: PtrInt;
begin
  // a run that switches to the fallback face and back: each font change
  // closes the hex string with Tj and opens a new one
  s := FakeFacePdf(FakeFace([$100, $101, $102, $103, $104, $FDD0],
    [7, 2, 3, 7, 41, 41], CffTable(true, FAKE_GLYPHS, FakeCidCharset)),
    '', nil, DrawFallbackMidRun);
  i := PosEx('BT'#10, s);
  j := PosEx('ET'#10, s, i);
  Check((i > 0) and
        (j > i), 'one text object');
  s := copy(s, i, j - i);
  Check(PosEx(#10'<0064> Tj', s) > 0, 'the fallback string opened');
  CheckEqual(CountOf('<', s), CountOf('> Tj', s), 'every string opened and shown');
end;

var
  // what the routing draws report back to Type0Routing
  RoutedWidth: single;
  RoutedText: PdfString;
  RoutedNextLine: boolean;
  RoutedWordSpace: single;
  RoutedRestore: boolean;

procedure DrawRouted(Pdf: TPdfDocument);
begin
  Pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
  RoutedWidth := Pdf.Canvas.TextWidth(RoutedText);
  if RoutedWordSpace <> 0 then
    Pdf.Canvas.SetWordSpace(RoutedWordSpace);
  if RoutedRestore then
  begin
    // q, no word spacing at 24 pt, Q: the spacing and size of before apply
    // again - q/Q are not allowed in a text object
    Pdf.Canvas.GSave;
    Pdf.Canvas.SetWordSpace(0);
    Pdf.Canvas.SetFont(FAKE_FACE, 24, [], PDF_DEFAULT_CHARSET);
    Pdf.Canvas.GRestore;
  end;
  Pdf.Canvas.BeginText;
  Pdf.Canvas.MoveTextPoint(40, 700);
  Pdf.Canvas.ShowText(RoutedText, RoutedNextLine);
  Pdf.Canvas.EndText;
end;

// after Unicode text the page font is the Unicode font of the face
procedure DrawUnicodeThenMeasure(Pdf: TPdfDocument);
begin
  Pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
  DrawUtf8Text(Pdf, 40, 700, ALIAS_TEXT);
  RoutedWidth := Pdf.Canvas.TextWidth(RoutedText);
end;

// the text object of an inflated PDF, and every font a Tf of the PDF selects
// has to be a Type0 font
function TextObjectOfType0(const Pdf: RawUtf8; out Text: RawUtf8): boolean;
var
  i, j, k, o, e: PtrInt;
  name, obj: RawUtf8;
begin
  result := false;
  i := PosEx('BT'#10, Pdf);
  j := PosEx('ET'#10, Pdf, i);
  if (i = 0) or
     (j = 0) then
    exit;
  Text := copy(Pdf, i, j - i);
  k := PosEx(' Tf'#10, Pdf);
  if k = 0 then
    exit;
  while k > 0 do
  begin
    o := k - 1;
    while (o > 1) and
          (Pdf[o] <> '/') do
      dec(o);
    name := copy(Pdf, o, k - o); // '/F1 12' of '/F1 12 Tf'
    name := copy(name, 1, PosEx(' ', name) - 1);
    o := PosEx('/Name' + name + '/', Pdf);
    if o = 0 then
      o := PosEx('/Name' + name + '>', Pdf);
    if o = 0 then
      exit;
    e := PosEx('endobj', Pdf, o);
    while (o > 1) and
          not ((Pdf[o] = 'o') and
               (copy(Pdf, o, 3) = 'obj')) do
      dec(o);
    obj := copy(Pdf, o, e - o);
    if PosEx('/Subtype/Type0', obj) = 0 then
      exit;
    k := PosEx(' Tf'#10, Pdf, k + 3);
  end;
  result := true;
end;

function FakeRoutingFace: IFontFace;
begin
  // space, W, i: glyphs 1, 5, 6 - CIDs 140, 136, 135 ($8C, $88, $87); their
  // WinAnsi widths 340, 440, 400, their /W widths 110, 150, 160
  result := FakeFace([$20, $57, $69, $100], [1, 5, 6, 7],
    CffTable(true, FAKE_GLYPHS, FakeCidCharset));
end;

function SwapInFakeFace(const Face: IFontFace): IFontProvider;
begin
  result := FontProvider;
  FontProvider := TFakeProvider.Create(result, Face, FAKE_FACE);
end;

procedure TPdfCffTests.Type0Routing;
var
  face: IFontFace;
  s, t: RawUtf8;
begin
  face := FakeRoutingFace;
  // ASCII text as a PdfString: the Type0 font, CIDs, no literal string
  RoutedText := 'Wi Wi';
  RoutedNextLine := false;
  RoutedWordSpace := 0;
  s := FakeFacePdf(face, '', nil, DrawRouted);
  Check(TextObjectOfType0(s, t), 'only the Type0 font selected');
  Check(PosEx('<00880087008C00880087> Tj', t) > 0, 'ASCII in CIDs');
  Check(PosEx('(', t) = 0, 'no literal string');
  // the advances of /W (hmtx: 100 + 10 * glyph), as the glyphs are drawn,
  // not the WinAnsi widths of the provider
  CheckSame(RoutedWidth, (150 + 160 + 110 + 150 + 160) * 12 / 1000, 1E-4,
    'TextWidth with the widths of /W');
  Check(PosEx('/W [135[160 150]140[110]]', s) > 0, 'those widths in /W');
  // the same text as UTF-16
  s := FakeFacePdf(face, 'Wi Wi');
  Check(TextObjectOfType0(s, t), 'only the Type0 font for UTF-16 text');
  Check(PosEx('<00880087008C00880087> Tj', t) > 0, 'UTF-16 in CIDs');
  // next line: the ' operator
  RoutedNextLine := true;
  s := FakeFacePdf(face, '', nil, DrawRouted);
  Check(TextObjectOfType0(s, t), 'Type0 font, next line');
  Check(PosEx('<00880087008C00880087> ''', t) > 0, 'next line and show');
  // word spacing: Tw does not reach two-byte codes, a TJ adjustment does
  RoutedNextLine := false;
  RoutedWordSpace := 6; // -1000 * 6 / 12
  s := FakeFacePdf(face, '', nil, DrawRouted);
  Check(TextObjectOfType0(s, t), 'Type0 font, word spacing');
  Check(PosEx('[<00880087008C> -500 <00880087>] TJ', t) > 0,
    'word spacing after the space');
  RoutedNextLine := true;
  s := FakeFacePdf(face, '', nil, DrawRouted);
  Check(TextObjectOfType0(s, t), 'Type0 font, word spacing, next line');
  Check(PosEx('T*'#10'[<00880087008C> -500 <00880087>] TJ', t) > 0,
    'next line before the array');
  // Q restores Tw: the adjustment follows it
  RoutedNextLine := false;
  RoutedWordSpace := 6;
  RoutedRestore := true;
  s := FakeFacePdf(face, '', nil, DrawRouted);
  RoutedRestore := false;
  Check(TextObjectOfType0(s, t), 'Type0 font, restored word spacing');
  Check(PosEx('[<00880087008C> -500 <00880087>] TJ', t) > 0,
    'the word spacing and the size restored by Q');
  Check(PosEx('/F1 24 Tf'#10'Q'#10, s) > 0, 'the size inside q/Q');
  RoutedWordSpace := 0;
  // a glyf face after Unicode text: the Unicode font measures WinAnsi text
  // with the widths of the WinAnsi font, not its default width
  RoutedWidth := 0;
  FakeFacePdf(FakeFace([$20, $57, $69, $100, $101, $102, $103, $104],
    [1, 5, 6, 7, 2, 3, 7, 41], ''), '', nil, DrawUnicodeThenMeasure);
  CheckSame(RoutedWidth, (440 + 400 + 340 + 440 + 400) * 12 / 1000, 1E-4,
    'TextWidth on the Unicode font');
end;

procedure TPdfCffTests.WinAnsiFontNotWritten;
var
  s: RawUtf8;
begin
  // the WinAnsi font of a CFF face is internal: the Type0 font and its
  // descendant are written, with the descriptor they share
  s := FakeFacePdf(FakeRoutingFace, 'Wi Wi');
  CheckEqual(CountOf('/Type/Font/', s), 2, 'Type0 and CIDFont only');
  Check(PosEx('/Subtype/Type0', s) > 0, 'the Type0 font');
  Check(PosEx('WinAnsiEncoding', s) = 0, 'no simple font');
  CheckEqual(CountOf('/Type/FontDescriptor', s), 1, 'the shared descriptor');
  // a glyf face keeps its WinAnsi font
  s := FakeFacePdf(FakeFace([$20, $57, $69, $100], [1, 5, 6, 7], ''), 'Wi Wi');
  Check(PosEx('WinAnsiEncoding', s) > 0, 'the simple font of a glyf face');
end;

// a name-keyed face first drawn on page 2, after SaveToStreamDirectBegin
// wrote PDF 1.3 and page 1 was flushed, and embedded once EmbeddedTTF is set
// before SaveToStreamDirectEnd: the inflated PDF
// - EmbedFirst: embedded before the face is created, as TPdfDocumentGdi
function StreamedLateEmbedding(const Version: RawUtf8 = '';
  EmbedFirst: boolean = false): RawUtf8;
var
  previous: IFontProvider;
  stream: TMemoryStream;
  pdf: TPdfDocument;
  sans, serif, mono: string;
begin
  result := '';
  previous := SwapInFakeFace(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(false, FAKE_GLYPHS, '')));
  try
    stream := TMemoryStream.Create;
    try
      pdf := TPdfDocument.Create(false, 0, pdfaNone);
      try
        pdf.EmbeddedTTF := false;
        pdf.AddTrueTypeFont(FAKE_FACE);
        pdf.CompressionMethod := cmNone;
        if Version <> '' then
          pdf.Root.Data.AddItem('Version', Version);
        pdf.SaveToStreamDirectBegin(stream);
        pdf.AddPage;
        GetPdfFonts(true, sans, serif, mono);
        pdf.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
        DrawUtf8Text(pdf, 40, 700, 'page 1');
        pdf.SaveToStreamDirectPageFlush;
        pdf.AddPage;
        if EmbedFirst then
          pdf.EmbeddedTTF := true;
        pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
        DrawUtf8Text(pdf, 40, 700, ALIAS_TEXT);
        pdf.EmbeddedTTF := true;
        pdf.SaveToStreamDirectEnd;
      finally
        pdf.Free;
      end;
      SetLength(result, stream.Size);
      stream.Position := 0;
      stream.Read(pointer(result)^, stream.Size);
    finally
      stream.Free;
    end;
  finally
    FontProvider := previous;
  end;
end;

procedure DrawThenUnembed(Pdf: TPdfDocument);
begin
  Pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
  DrawUtf8Text(Pdf, 40, 700, ALIAS_TEXT);
  Pdf.EmbeddedTTF := false;
end;

procedure TPdfCffTests.EmbeddedPrograms;
var
  s: RawUtf8;
  keep: IFontSubsetter;
  raised: boolean;
begin
  // a CID-keyed face: its bare 'CFF ' table as CIDFontType0C, its ROS
  keep := TFakeSubsetter.Create(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'CID-KEYED', 'Japan1', 6)).fWhole);
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'CID-KEYED', 'Japan1', 6)), ALIAS_TEXT, keep);
  Check(PosEx('/FontFile3', s) > 0, 'FontFile3');
  Check(PosEx('/Subtype/CIDFontType0C', s) > 0, 'the bare CFF program');
  Check(PosEx('stream'#13#10#1#0#4, s) + PosEx('stream'#10#1#0#4, s) > 0,
    'the stream is the CFF table');
  Check(PosEx('OTTO', s) = 0, 'no OpenType font file');
  Check(PosEx('/Subtype/CIDFontType0/', s) > 0, 'a CIDFontType0');
  Check(PosEx('/CIDToGIDMap', s) = 0, 'no CIDToGIDMap for CFF');
  Check(PosEx('/CIDSystemInfo<</Supplement 6/Ordering(Japan1)/Registry(Adobe)>>',
    s) > 0, 'the ROS of the face');
  Check(PosEx('%PDF-1.3', s) = 1, 'PDF 1.3 is enough');
  Check(PosEx('+CID-KEYED/', s) > 0, 'the name of the program, behind the tag');
  Check(PosEx(FAKE_FACE, s) = 0, 'not the family name');
  // a space in it is #20 in a PDF name; the PostScript name of the sfnt is
  // not the bare CFF's
  keep := TFakeSubsetter.Create(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'CID KEYED'), '', 'Other-PS').fWhole);
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
    CffTable(true, FAKE_GLYPHS, FakeCidCharset, 391, 392, '', true, 0,
    'CID KEYED'), '', 'Other-PS'), ALIAS_TEXT, keep);
  Check(PosEx('+CID#20KEYED/', s) > 0, 'the space escaped');
  Check(PosEx('Other-PS', s) = 0, 'the CIDFontName, not the PostScript name');
  // a name-keyed face: the OpenType font file, PDF 1.6
  FakeEmbedded := true;
  try
    s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
      CffTable(false, FAKE_GLYPHS, ''), '', 'Name#Keyed-PS'), ALIAS_TEXT);
  finally
    FakeEmbedded := false;
  end;
  Check(PosEx('/Subtype/OpenType', s) > 0, 'the OpenType font file');
  Check(PosEx('/Subtype/CIDFontType0/', s) > 0, 'a CIDFontType0 too');
  Check(PosEx('/CIDToGIDMap', s) = 0, 'no CIDToGIDMap');
  Check(PosEx('/Registry(Adobe)', s) > 0, 'Adobe-Identity');
  Check(PosEx('%PDF-1.6', s) = 1, 'PDF 1.6 for an OpenType font file');
  Check(PosEx('Name#23Keyed-PS/', s) > 0,
    'the PostScript name of the font file, its # escaped');
  Check(PosEx('Test/', s) = 0, 'not the name in its CFF');
  // which PDF/A-1 (PDF 1.4) cannot give
  FakePdfA := pdfa1B;
  raised := false;
  try
    try
      FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
        CffTable(false, FAKE_GLYPHS, '')), ALIAS_TEXT);
    except
      on EPdfInvalidOperation do
        raised := true;
    end;
  finally
    FakePdfA := pdfaNone;
  end;
  Check(raised, 'PDF/A-1 refuses a name-keyed CFF face');
  // first drawn after the header and a page flush: the catalog says 1.6
  s := InflatePdf(StreamedLateEmbedding);
  Check(PosEx('%PDF-1.3', s) = 1, 'the header written before the face');
  Check(PosEx('/Type/Catalog', s) > 0, 'a catalog');
  Check(PosEx('/Version/1.6', s) > 0, 'its /Version for the OpenType file');
  Check(PosEx('/Subtype/OpenType', s) > 0, 'the OpenType font file');
  Check(PosEx('/Subtype/Type1/', s) > 0,
    'embedded after its creation: its simple font a /Type1');
  // a higher /Version set before is kept
  s := InflatePdf(StreamedLateEmbedding('1.7'));
  Check((PosEx('/Version/1.7', s) > 0) and
        (PosEx('/Version/1.6', s) = 0), 'a higher /Version kept');
  // created embedded after the header: internal, its /Version from creation
  s := InflatePdf(StreamedLateEmbedding('', true));
  Check(PosEx('/Version/1.6', s) > 0, 'created after the header: /Version');
  Check(PosEx('/Subtype/Type1/', s) = 0, 'its WinAnsi font not written');
  // switched off after it drew through its Type0 font: refused
  raised := false;
  FakeEmbedded := true;
  try
    try
      FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS,
        CffTable(false, FAKE_GLYPHS, '')), ALIAS_TEXT, nil, DrawThenUnembed);
    except
      on EPdfInvalidOperation do
        raised := true;
    end;
  finally
    FakeEmbedded := false;
  end;
  Check(raised, 'embedding switched off after the text: refused');
  // a glyf face as before
  FakeEmbedded := true;
  try
    s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS, ''), ALIAS_TEXT);
  finally
    FakeEmbedded := false;
  end;
  Check(PosEx('/FontFile2', s) > 0, 'glyf: FontFile2');
  Check(PosEx('/Subtype/CIDFontType2/', s) > 0, 'glyf: CIDFontType2');
  Check(PosEx('/CIDToGIDMap/Identity', s) > 0, 'glyf: CIDToGIDMap');
end;

procedure DrawGlyfWordSpaced(Pdf: TPdfDocument);
begin
  Pdf.Canvas.SetFont(FAKE_FACE, 12, [], PDF_DEFAULT_CHARSET);
  Pdf.Canvas.SetWordSpace(6);
  DrawUtf8Text(Pdf, 40, 700, ALIAS_TEXT);
end;

procedure TPdfCffTests.UnembeddedNameKeyed;
var
  s: RawUtf8;
begin
  // the glyph indexes of an unembedded name-keyed face mean nothing to a
  // viewer: its Latin text stays in the simple font, which it substitutes
  s := FakeFacePdf(FakeFace([$20, $57, $69, $100], [1, 5, 6, 7],
    CffTable(false, FAKE_GLYPHS, '')), 'Wi Wi');
  Check(PosEx('(Wi Wi) Tj', s) > 0, 'Latin text as WinAnsi');
  Check(PosEx('WinAnsiEncoding', s) > 0, 'the simple font written');
  // an unembedded CID-keyed face: its CIDs of a known ROS mean something
  s := FakeFacePdf(FakeRoutingFace, 'Wi Wi');
  Check(PosEx('(Wi Wi)', s) = 0, 'CID-keyed: through the Type0 font');
  // a glyf face with a word spacing: its spaces are WinAnsi, no TJ array
  s := FakeFacePdf(FakeFace(ALIAS_CHARS, ALIAS_GLYPHS, ''), '', nil,
    DrawGlyfWordSpaced);
  Check(PosEx('] TJ', s) = 0, 'glyf: no TJ array for Tw');
  Check(PosEx('> Tj', s) > 0, 'glyf: the glyph string as before');
end;

procedure TPdfCffTests.TextStateAcrossQ;
var
  pdf: TPdfDocument;
  stream: TMemoryStream;
  s, ab, text: RawUtf8;
  sans, serif, mono: string;
  ok: boolean;
begin
  // Q restores Tc, Tz and TL: a value set again after it is written again
  stream := TMemoryStream.Create;
  try
    pdf := TPdfDocument.Create(false, 0, pdfaNone);
    try
      pdf.CompressionMethod := cmNone;
      pdf.AddPage;
      GetPdfFonts(true, sans, serif, mono);
      pdf.Canvas.SetCharSpace(1);
      pdf.Canvas.SetHorizontalScaling(90);
      pdf.Canvas.SetLeading(14);
      pdf.Canvas.GSave;
      pdf.Canvas.SetCharSpace(2);
      pdf.Canvas.SetHorizontalScaling(80);
      pdf.Canvas.SetLeading(20);
      // a font selected inside q/Q only: Q puts none back
      pdf.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
      pdf.Canvas.GRestore;
      // text in its own q/Q first: the Tf written there is gone after it
      pdf.Canvas.GSave;
      pdf.Canvas.BeginText;
      text := 'A';
      pdf.Canvas.ShowText(PdfString(text));
      pdf.Canvas.EndText;
      pdf.Canvas.GRestore;
      pdf.Canvas.BeginText;
      text := 'B';
      pdf.Canvas.ShowText(PdfString(text));
      pdf.Canvas.EndText;
      pdf.Canvas.SetCharSpace(2);
      pdf.Canvas.SetHorizontalScaling(80);
      pdf.Canvas.SetLeading(20);
      ok := true;
      try
        pdf.Canvas.BeginText;
        text := 'x';
        pdf.Canvas.ShowText(PdfString(text));
        pdf.Canvas.EndText;
      except
        ok := false;
      end;
      Check(ok, 'text after Q without a font of its own');
      pdf.SaveToStream(stream);
    finally
      pdf.Free;
    end;
    SetLength(s, stream.Size);
    stream.Position := 0;
    stream.Read(pointer(s)^, stream.Size);
  finally
    stream.Free;
  end;
  ab := copy(s, PosEx('(A)', s), maxInt);
  ab := copy(ab, PosEx('Q'#10, ab), maxInt);
  s := copy(s, PosEx('Q'#10, s), maxInt);
  Check(PosEx(' Tf'#10, s) > 0,
    'the font selected again before the text after Q');
  Check(PosEx('2 Tc', s) > 0, 'Tc after Q');
  Check(PosEx('80 Tz', s) > 0, 'Tz after Q');
  Check(PosEx('20 TL', s) > 0, 'TL after Q');
  Check((PosEx(' Tf', ab) > 0) and
        (PosEx(' Tf', ab) < PosEx('(B)', ab)), 'the font selected again before B');
end;

end.
