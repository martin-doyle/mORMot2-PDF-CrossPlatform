/// Reading a written PDF back for checks: shared by the tests and pdfcheck
// - text-level only, no object model: a test tool, not a PDF reader
unit pdf_inspect;

interface

{$I mormot.defines.inc}

uses
  mormot.core.base;

/// the file with every FlateDecode stream inflated in place
// - PDF 1.5+ object streams hide the catalog, fonts and file specifications;
// the /Length entries keep their compressed values
function InflatePdf(const s: RawUtf8): RawUtf8;

/// the form in which two PDFs are compared
// - parsed token by token: streams decoded (FlateDecode inflated, XRef streams
// as one text line per object, JPEG kept as it is), the /ID, '/ABCDEF+' subset tags, the
// /CreationDate and /ModDate values, XMP dates, stream lengths and file offsets
// replaced by placeholders
// - the structure is checked before anything is blanked: each /Length has to
// end at endstream, each offset has to point to its object; Error tells the
// first violation
function NormalizePdf(const Pdf: RawByteString; out Error: RawUtf8): RawUtf8; overload;

type
  /// where one object is in the normalized text: from the "n g" before
  // 'obj' to 'endobj', or one object of an object stream
  TPdfObjectSpan = record
    Num, Gen: integer;
    Start, Stop: integer; // 1-based, Stop excluded
  end;
  TPdfObjectSpans = array of TPdfObjectSpan;

/// NormalizePdf, with where each object is in the result
// - found by the same walk through the syntax, so that strings and stream
// data are never taken for an object; an object stream gives its objects
// one by one, not itself
function NormalizePdf(const Pdf: RawByteString; out Error: RawUtf8;
  out Objects: TPdfObjectSpans): RawUtf8; overload;

/// compare two normalized files: true when equal, otherwise Diff names each
// differing, added or removed object (up to ten), paired by number, with the
// byte of its first difference and the line of each side, and the text
// outside the objects - so that one expected difference hides no other
function ComparePdfText(const a, b: RawUtf8; const ObjA, ObjB: TPdfObjectSpans;
  out Diff: RawUtf8): boolean;

/// the roles of the structure tree with their counts, one 'Role count' per
// line, sorted by role; '' for an untagged file
function PdfStructRoles(const s: RawUtf8): RawUtf8;

/// the fonts as pdffonts lists them, one line per font dictionary, sorted:
// name, type, the font file key (or no), subset and /ToUnicode, e.g.
// 'ABCDEF+Calibri Type0/CIDFontType2 emb=FontFile2 sub=yes uni=yes'
// - a Type0 font is followed to its descendant and that one's descriptor
function PdfFonts(const s: RawUtf8): RawUtf8;

implementation

uses
  SysUtils,
  mormot.core.text,    // Int32ToUtf8, FormatUtf8
  mormot.core.unicode, // TrimU
  mormot.lib.z;

function InflatePdf(const s: RawUtf8): RawUtf8;
var
  p, q, body, e: integer;
  z: RawUtf8;
begin
  result := '';
  p := 1;
  q := PosEx('stream', s, 1);
  while q > 0 do
  begin
    if (q > 3) and (copy(s, q - 3, 3) = 'end') then
    begin
      q := PosEx('stream', s, q + 6);
      continue;
    end;
    body := q + 6;
    if (body <= length(s)) and (s[body] = #13) then
      inc(body);
    if (body <= length(s)) and (s[body] = #10) then
      inc(body);
    e := PosEx('endstream', s, body);
    if e = 0 then
      break;
    result := result + copy(s, p, body - p);
    z := '';
    // only a stream dictionary carries a /Filter, so the text since the
    // previous stream names this stream's filter
    if PosEx('/FlateDecode', copy(s, p, q - p)) > 0 then
      try
        z := UncompressZipString(@s[body], e - body, nil, true);
      except
        z := '';
      end;
    if z = '' then
      z := copy(s, body, e - body);
    result := result + z;
    p := e;
    q := PosEx('stream', s, e + 9);
  end;
  result := result + copy(s, p, maxInt);
end;

function IsDigit(c: AnsiChar): boolean;
begin
  result := (c >= '0') and (c <= '9');
end;

function IsUpper(c: AnsiChar): boolean;
begin
  result := (c >= 'A') and (c <= 'Z');
end;

function Matches(const s: RawUtf8; i: integer; const sub: RawUtf8): boolean;
begin
  result := (i + length(sub) - 1 <= length(s)) and
            (copy(s, i, length(sub)) = sub);
end;

// /ABCDEF+ before a subset font name
function IsSubsetPrefix(const s: RawUtf8; i: integer): boolean;
var
  k: integer;
begin
  result := false;
  if (i + 7 > length(s)) or (s[i] <> '/') or (s[i + 7] <> '+') then
    exit;
  for k := i + 1 to i + 6 do
    if not IsUpper(s[k]) then
      exit;
  result := true;
end;

// the line of s that holds position i, at most 120 characters, the bytes
// outside ASCII shown as dots
function LineAt(const s: RawUtf8; i: integer; out LineNo: integer): RawUtf8;
var
  b, e, k: integer;
begin
  LineNo := 1;
  result := '';
  if s = '' then
    exit;
  if i < 1 then
    i := 1;
  for k := 1 to i - 1 do
    if s[k] = #10 then
      inc(LineNo);
  b := i;
  while (b > 1) and (s[b - 1] <> #10) do
    dec(b);
  e := i;
  while (e <= length(s)) and (s[e] <> #10) do
    inc(e);
  if e - b > 120 then
  begin
    b := MaxPtrInt(b, i - 60);
    e := b + 120;
  end;
  result := copy(s, b, e - b);
  for k := 1 to length(result) do
    if (result[k] < ' ') or (result[k] > #126) then
      result[k] := '.';
end;

// the "N 0 obj" header before offset i of s, or ''
function ObjectAt(const s: RawUtf8; i: integer): RawUtf8;
var
  k, b: integer;
begin
  result := '';
  k := i;
  if k > length(s) then
    k := length(s);
  while k > 4 do
  begin
    if (s[k] = 'j') and (s[k - 1] = 'b') and (s[k - 2] = 'o') and
       (s[k - 3] = ' ') then
    begin
      b := k - 3;
      while (b > 1) and (s[b - 1] in ['0'..'9', ' ']) do
        dec(b);
      result := TrimU(copy(s, b, k - b + 1));
      exit;
    end;
    dec(k);
  end;
end;

// the first difference of a[PosA..EndA) and b[PosB..EndB), as three lines
function DiffAt(const a, b: RawUtf8; PosA, EndA, PosB, EndB: integer;
  const What: RawUtf8): RawUtf8;
var
  i, la, lb: integer;
  ta, tb: RawUtf8;
begin
  i := 0;
  while (PosA + i < EndA) and
        (PosB + i < EndB) and
        (a[PosA + i] = b[PosB + i]) do
    inc(i);
  ta := LineAt(a, MinPtrInt(PosA + i, length(a)), la);
  tb := LineAt(b, MinPtrInt(PosB + i, length(b)), lb);
  result := '  ' + What + ', byte ' + Int32ToUtf8(PosA + i) + #10 +
    '  a, line ' + Int32ToUtf8(la) + ': ' + ta + #10 +
    '  b, line ' + Int32ToUtf8(lb) + ': ' + tb;
end;

// the Nth (0-based) definition of object Num Gen: an incremental update
// defines an object again
function FindSpan(const Spans: TPdfObjectSpans; Num, Gen, Nth: integer): integer;
begin
  for result := 0 to high(Spans) do
    if (Spans[result].Num = Num) and
       (Spans[result].Gen = Gen) then
      if Nth = 0 then
        exit
      else
        dec(Nth);
  result := -1;
end;

// which definition of its object Spans[Index] is, 0 for the first
function SpanNth(const Spans: TPdfObjectSpans; Index: integer): integer;
var
  k: integer;
begin
  result := 0;
  for k := 0 to Index - 1 do
    if (Spans[k].Num = Spans[Index].Num) and
       (Spans[k].Gen = Spans[Index].Gen) then
      inc(result);
end;

// the text outside the objects: header, xref, trailer
function OutsideSpans(const s: RawUtf8; const Spans: TPdfObjectSpans): RawUtf8;
var
  k, i, n: integer;
  inside: TBooleanDynArray;
begin
  SetLength(inside, length(s) + 1);
  for k := 0 to high(Spans) do
    for i := Spans[k].Start to Spans[k].Stop - 1 do
      inside[i] := true;
  SetLength(result, length(s));
  n := 0;
  for i := 1 to length(s) do
    if not inside[i] then
    begin
      inc(n);
      result[n] := s[i];
    end;
  SetLength(result, n);
end;

function ComparePdfText(const a, b: RawUtf8; const ObjA, ObjB: TPdfObjectSpans;
  out Diff: RawUtf8): boolean;
const
  MAX_REPORTED = 10;
var
  k, m, count: integer;
  oa, ob: RawUtf8;

  procedure Report(const Text: RawUtf8);
  begin
    inc(count);
    if count > MAX_REPORTED then
      exit;
    if Diff <> '' then
      Diff := Diff + #10;
    Diff := Diff + Text;
  end;

  function Name(const Span: TPdfObjectSpan): RawUtf8;
  begin
    result := 'object ' + Int32ToUtf8(Span.Num) + ' ' + Int32ToUtf8(Span.Gen);
  end;

begin
  Diff := '';
  result := a = b;
  if result then
    exit;
  count := 0;
  // removed and added first: a new object usually renumbers the others
  for k := 0 to high(ObjA) do
    if FindSpan(ObjB, ObjA[k].Num, ObjA[k].Gen, SpanNth(ObjA, k)) < 0 then
      Report('  ' + Name(ObjA[k]) + ' removed');
  for m := 0 to high(ObjB) do
    if FindSpan(ObjA, ObjB[m].Num, ObjB[m].Gen, SpanNth(ObjB, m)) < 0 then
      Report('  ' + Name(ObjB[m]) + ' added');
  for k := 0 to high(ObjA) do
  begin
    m := FindSpan(ObjB, ObjA[k].Num, ObjA[k].Gen, SpanNth(ObjA, k));
    if (m >= 0) and
       ((ObjA[k].Stop - ObjA[k].Start <> ObjB[m].Stop - ObjB[m].Start) or
        not CompareMem(@a[ObjA[k].Start], @b[ObjB[m].Start],
          ObjA[k].Stop - ObjA[k].Start)) then
      Report(DiffAt(a, b, ObjA[k].Start, ObjA[k].Stop, ObjB[m].Start,
        ObjB[m].Stop, Name(ObjA[k])));
  end;
  oa := OutsideSpans(a, ObjA);
  ob := OutsideSpans(b, ObjB);
  if oa <> ob then
    Report(DiffAt(oa, ob, 1, length(oa) + 1, 1, length(ob) + 1,
      'outside the objects'));
  // the same objects and the same text around them, in another order
  if count = 0 then
    Report(DiffAt(a, b, 1, length(a) + 1, 1, length(b) + 1,
      'the order of the objects'));
  if count > MAX_REPORTED then
    Diff := Diff + #10'  ... ' + Int32ToUtf8(count - MAX_REPORTED) + ' more';
end;


{ ---------- normalizing ---------- }

type
  // walks the PDF syntax token by token, so strings, comments and stream data
  // are never mistaken for structure; checks what it blanks before blanking it
  TPdfNormalizer = class
  protected
    fPdf: RawByteString;
    fOut: TRawByteStringStream;
    fError: RawUtf8;
    // file offsets of the xref tables and XRef stream objects parsed so far
    fXRefOffsets: TInt64DynArray;
    // where the objects are in fOut (Start/Stop 1-based), and those of the
    // object stream Stream() last normalized, relative to its result
    fSpans, fStreamSpans: TPdfObjectSpans;
    procedure AddSpan(var Spans: TPdfObjectSpans; Num, Gen: integer;
      Start, Stop: Int64);
    procedure Fail(const Fmt: RawUtf8; const Args: array of const);
    procedure Emit(const s: RawByteString; b, e: PtrInt); overload;
    procedure Emit(const s: RawByteString); overload;
    function ObjectAtOffset(Offset, Num, Gen: Int64): boolean;
    procedure Syntax(const s: RawByteString; TopLevel: boolean);
    function Stream(const Dict, Data: RawByteString; ObjNum: Int64): RawByteString;
    function XRefStream(const Dict, Data: RawByteString): RawByteString;
    procedure XRefTable(const s: RawByteString; var i: PtrInt);
  public
    function Normalize(const Pdf: RawByteString; out Error: RawUtf8): RawByteString;
  end;

const
  PDF_WHITE = [#0, #9, #10, #12, #13, ' '];
  PDF_DELIM = ['(', ')', '<', '>', '[', ']', '{', '}', '/', '%'];
  // longer digit runs are no offset or length of ours: refused, not wrapped
  MAX_DIGITS = 15;

function IsDigits(const s: RawByteString; b, n: PtrInt): boolean;
begin
  result := false;
  if (b < 1) or (n > length(s) - b + 1) then
    exit;
  while n > 0 do
  begin
    if not (s[b] in ['0'..'9']) then
      exit;
    inc(b);
    dec(n);
  end;
  result := true;
end;

// the unsigned integer at s[i], i moved after it; -1 if none or too long
function ReadInt(const s: RawByteString; var i: PtrInt): Int64;
var
  n: integer;
begin
  result := -1;
  if (i > length(s)) or not (s[i] in ['0'..'9']) then
    exit;
  result := 0;
  n := 0;
  while (i <= length(s)) and (s[i] in ['0'..'9']) do
  begin
    inc(n);
    if n > MAX_DIGITS then
    begin
      result := -1;
      exit;
    end;
    result := result * 10 + ord(s[i]) - 48;
    inc(i);
  end;
end;

// the whole of Value as an unsigned integer, or -1
function ReadIntValue(const Value: RawByteString): Int64;
var
  i: PtrInt;
begin
  i := 1;
  result := ReadInt(Value, i);
  if i <= length(Value) then
    result := -1;
end;

procedure SkipWhite(const s: RawByteString; var i: PtrInt);
begin
  while (i <= length(s)) and (s[i] in PDF_WHITE) do
    inc(i);
end;

// i after the string, hex string, array or dictionary starting at s[i];
// false if it is not closed
function SkipValue(const s: RawByteString; var i: PtrInt): boolean;
var
  depth: integer;
begin
  result := false;
  case s[i] of
    '(':
      begin
        depth := 0;
        repeat
          if i > length(s) then
            exit;
          case s[i] of
            '\':
              inc(i);
            '(':
              inc(depth);
            ')':
              dec(depth);
          end;
          inc(i);
        until depth = 0;
      end;
    '<':
      if (i < length(s)) and (s[i + 1] = '<') then
      begin
        inc(i, 2);
        depth := 1;
        while depth > 0 do
        begin
          if i > length(s) then
            exit;
          if s[i] in ['(', '['] then
          begin
            if not SkipValue(s, i) then
              exit;
            continue;
          end;
          if (s[i] = '<') and (i < length(s)) and (s[i + 1] = '<') then
          begin
            inc(depth);
            inc(i);
          end
          else if (s[i] = '>') and (i < length(s)) and (s[i + 1] = '>') then
          begin
            dec(depth);
            inc(i);
          end
          else if s[i] = '<' then
          begin
            if not SkipValue(s, i) then
              exit;
            continue;
          end;
          inc(i);
        end;
      end
      else
      begin
        while (i <= length(s)) and (s[i] <> '>') do
          inc(i);
        if i > length(s) then
          exit;
        inc(i);
      end;
    '[':
      begin
        inc(i);
        repeat
          SkipWhite(s, i);
          if i > length(s) then
            exit;
          if s[i] = ']' then
            break;
          if s[i] in ['(', '<', '['] then
          begin
            if not SkipValue(s, i) then
              exit;
          end
          else
            inc(i);
        until false;
        inc(i);
      end;
  else
    inc(i);
  end;
  result := true;
end;

// the position of the value of Key in the outermost dictionary of Dict
// - nested dictionaries, arrays and strings are skipped, so a key inside them
// is not taken; the value is Dict[b..e-1], maybe with trailing white space
function DictValuePos(const Dict, Key: RawByteString; out b, e: PtrInt): boolean;
var
  i, j: PtrInt;
  name: RawByteString;
begin
  result := false;
  i := PosEx('<<', Dict);
  if i = 0 then
    exit;
  inc(i, 2);
  repeat
    SkipWhite(Dict, i);
    if (i > length(Dict)) or (Dict[i] = '>') then
      exit;
    if Dict[i] <> '/' then
      exit; // not a key: malformed, the caller sees no value
    j := i + 1;
    while (j <= length(Dict)) and not (Dict[j] in PDF_WHITE + PDF_DELIM) do
      inc(j);
    name := copy(Dict, i, j - i);
    i := j;
    SkipWhite(Dict, i);
    if i > length(Dict) then
      exit;
    b := i;
    if Dict[i] in ['(', '<', '['] then
    begin
      if not SkipValue(Dict, i) then
        exit;
    end
    else if Dict[i] = '/' then
    begin
      inc(i);
      while (i <= length(Dict)) and not (Dict[i] in PDF_WHITE + PDF_DELIM) do
        inc(i);
    end
    else
    begin
      // a number, possibly 'n g R', or a keyword
      while (i <= length(Dict)) and not (Dict[i] in PDF_DELIM) do
        inc(i);
    end;
    if name = Key then
    begin
      e := i;
      result := true;
      exit;
    end;
  until false;
end;

// the raw text of the value of Key in the outermost dictionary of Dict, or ''
function DictValue(const Dict, Key: RawByteString): RawByteString;
var
  b, e: PtrInt;
begin
  if DictValuePos(Dict, Key, b, e) then
    result := TrimU(copy(Dict, b, e - b))
  else
    result := '';
end;

// the integers of an array value like '[1 3 1]'; nil if it holds anything else
function IntArray(const Value: RawByteString): TInt64DynArray;
var
  i: PtrInt;
  v: Int64;
  n: integer;
begin
  result := nil;
  if (Value = '') or (Value[1] <> '[') then
    exit;
  i := 2;
  n := 0;
  repeat
    SkipWhite(Value, i);
    if i > length(Value) then
    begin
      result := nil;
      exit;
    end;
    if Value[i] = ']' then
      exit;
    v := ReadInt(Value, i);
    if v < 0 then
    begin
      result := nil;
      exit;
    end;
    SetLength(result, n + 1);
    result[n] := v;
    inc(n);
  until false;
end;

procedure TPdfNormalizer.AddSpan(var Spans: TPdfObjectSpans; Num, Gen: integer;
  Start, Stop: Int64);
var
  n: PtrInt;
begin
  n := length(Spans);
  SetLength(Spans, n + 1);
  Spans[n].Num := Num;
  Spans[n].Gen := Gen;
  Spans[n].Start := Start;
  Spans[n].Stop := Stop;
end;

procedure TPdfNormalizer.Fail(const Fmt: RawUtf8; const Args: array of const);
begin
  if fError = '' then // the first error is the one that explains the others
    fError := FormatUtf8(Fmt, Args);
end;

procedure TPdfNormalizer.Emit(const s: RawByteString; b, e: PtrInt);
begin
  if e > b then
    fOut.WriteBuffer(PAnsiChar(pointer(s))[b - 1], e - b);
end;

procedure TPdfNormalizer.Emit(const s: RawByteString);
begin
  if s <> '' then
    fOut.WriteBuffer(pointer(s)^, length(s));
end;

// true if "Num Gen obj" starts at the 0-based file offset Offset
function TPdfNormalizer.ObjectAtOffset(Offset, Num, Gen: Int64): boolean;
var
  head: RawUtf8;
begin
  head := FormatUtf8('% % obj', [Num, Gen]);
  result := (Offset >= 0) and
            (Offset <= length(fPdf) - length(head)) and
            CompareMem(@fPdf[Offset + 1], pointer(head), length(head));
end;

procedure ZeroDigits(var s: RawByteString; b, n: PtrInt);
begin
  while n > 0 do
  begin
    if s[b] in ['0'..'9'] then
      s[b] := '0';
    inc(b);
    dec(n);
  end;
end;

// the dates the engine writes into an XMP packet, 'YYYY-MM-DDTHH:MM:SS';
// any other date in it is the caller's and stays
function BlankXmpDates(const Xmp: RawByteString): RawByteString;
const
  TAGS: array[0..2] of RawUtf8 = (
    '<xmp:CreateDate>', '<xmp:ModifyDate>', '<xmp:MetadataDate>');
var
  t: integer;
  i: PtrInt;
begin
  result := Xmp;
  SetLength(result, length(result)); // a copy of our own to write to
  for t := 0 to high(TAGS) do
  begin
    i := PosEx(TAGS[t], result);
    while i > 0 do
    begin
      inc(i, length(TAGS[t]));
      if (i + 18 <= length(result)) and
         (result[i + 4] = '-') and (result[i + 7] = '-') and
         (result[i + 10] = 'T') and (result[i + 13] = ':') and
         (result[i + 16] = ':') and IsDigits(result, i, 4) and
         IsDigits(result, i + 5, 2) and IsDigits(result, i + 8, 2) and
         IsDigits(result, i + 11, 2) and IsDigits(result, i + 14, 2) and
         IsDigits(result, i + 17, 2) then
        ZeroDigits(result, i, 19);
      i := PosEx(TAGS[t], result, i);
    end;
  end;
end;

// an XRef stream as text, one "type field2 field3" line per object; the
// offsets of objects in use are checked, then written as 0, as their width
// in /W changes with the file size
function TPdfNormalizer.XRefStream(const Dict, Data: RawByteString): RawByteString;
var
  w, index: TInt64DynArray;
  row, rows, seg, size: Int64;
  num, k, n: integer;
  f: array[0..2] of Int64;
  P: PByte;
begin
  result := '';
  w := IntArray(DictValue(Dict, '/W'));
  index := IntArray(DictValue(Dict, '/Index'));
  size := ReadIntValue(DictValue(Dict, '/Size'));
  if index = nil then
  begin
    SetLength(index, 2);
    index[0] := 0;
    index[1] := size;
  end;
  if (length(w) <> 3) or (w[0] > 8) or (w[1] > 8) or (w[2] > 8) or
     (w[0] + w[1] + w[2] = 0) or odd(length(index)) or
     (size < 0) or (size > MaxInt) then
  begin
    Fail('XRef stream: unusable /W, /Index or /Size', []);
    exit;
  end;
  row := w[0] + w[1] + w[2];
  rows := 0;
  seg := 0;
  while seg < length(index) do
  begin
    if index[seg] + index[seg + 1] > size then
    begin
      Fail('XRef stream: /Index beyond /Size %', [size]);
      exit;
    end;
    inc(rows, index[seg + 1]);
    inc(seg, 2);
  end;
  if rows * row <> length(Data) then
  begin
    Fail('XRef stream: % bytes for % rows of %', [length(Data), rows, row]);
    exit;
  end;
  P := pointer(Data);
  seg := 0;
  while seg < length(index) do
  begin
    for num := index[seg] to index[seg] + index[seg + 1] - 1 do // <= size
    begin
      for k := 0 to 2 do
      begin
        f[k] := 0;
        if (k = 0) and (w[0] = 0) then
          f[0] := 1; // the type defaults to 1 when its field is absent
        for n := 1 to w[k] do
        begin
          f[k] := f[k] shl 8 + P^;
          inc(P);
        end;
      end;
      if f[0] = 1 then
      begin
        if not ObjectAtOffset(f[1], num, f[2]) then
          Fail('XRef stream: object % % is not at offset %', [num, f[2], f[1]]);
        f[1] := 0;
      end;
      result := result + FormatUtf8('% % %'#10, [f[0], f[1], f[2]]);
    end;
    inc(seg, 2);
  end;
end;

// a classic "xref" table from s[i], i after the keyword; offsets checked,
// then written as 0
procedure TPdfNormalizer.XRefTable(const s: RawByteString; var i: PtrInt);
var
  first, count, k, off: Int64;
begin
  repeat
    SkipWhite(s, i);
    if (i > length(s)) or not (s[i] in ['0'..'9']) then
      exit; // 'trailer' follows
    first := ReadInt(s, i);
    SkipWhite(s, i);
    count := ReadInt(s, i);
    if (first < 0) or (count < 0) then
    begin
      Fail('xref table: bad subsection header', []);
      exit;
    end;
    Emit(FormatUtf8(#10'% %'#10, [first, count]));
    k := 0;
    while k < count do
    begin
      SkipWhite(s, i);
      if not (IsDigits(s, i, 10) and IsDigits(s, i + 11, 5) and
              (s[i + 10] = ' ') and (s[i + 16] = ' ') and
              (s[i + 17] in ['n', 'f'])) then
      begin
        Fail('xref table: bad entry for object %', [first + k]);
        exit;
      end;
      if s[i + 17] = 'n' then
      begin
        off := GetInt64(@s[i]);
        if not ObjectAtOffset(off, first + k, GetCardinal(@s[i + 11])) then
          Fail('xref table: object % is not at offset %', [first + k, off]);
        Emit('0000000000');
      end
      else
        Emit(s, i, i + 10);
      Emit(s, i + 10, i + 18);
      Emit(#10);
      inc(i, 18);
      inc(k);
    end;
  until false;
end;

// the content of one stream, decoded and with what varies blanked
function TPdfNormalizer.Stream(const Dict, Data: RawByteString;
  ObjNum: Int64): RawByteString;
var
  sub: TPdfNormalizer;
  filter, typ: RawByteString;
  err: RawUtf8;
  n, first, start: Int64;
  k: PtrInt;
  m, e: integer;
  nums, offs: TInt64DynArray;
begin
  result := Data;
  fStreamSpans := nil;
  filter := DictValue(Dict, '/Filter');
  if ((filter = '/FlateDecode') or (filter = '[/FlateDecode]')) and
     (Data = '') then
    Fail('object %: empty FlateDecode stream', [ObjNum])
  else if (filter = '/FlateDecode') or (filter = '[/FlateDecode]') then
    try
      // an error raises: an empty result is an empty stream
      result := UncompressZipString(pointer(Data), length(Data), nil, true);
    except
      Fail('object %: FlateDecode stream does not inflate', [ObjNum]);
      result := Data;
      exit;
    end
  else if (filter = '/DCTDecode') or
          (filter = '[/DCTDecode]') then
  begin
    // JPEG data: compared byte by byte as it is, nothing in it varies - an
    // image only, so that no xref or object stream escapes its checks
    typ := DictValue(Dict, '/Type');
    if (DictValue(Dict, '/Subtype') <> '/Image') or
       ((typ <> '') and
        (typ <> '/XObject')) then
      Fail('object %: /DCTDecode on a stream that is no image', [ObjNum]);
    exit;
  end
  else if filter <> '' then
  begin
    Fail('object %: unexpected /Filter %', [ObjNum, filter]);
    exit;
  end;
  typ := DictValue(Dict, '/Type');
  if typ = '/XRef' then
    result := XRefStream(Dict, result)
  else if typ = '/ObjStm' then
  begin
    // the objects inside are dictionaries like the ones at top level: each
    // normalized on its own, so that its place in the result is known
    sub := TPdfNormalizer.Create;
    try
      sub.fPdf := fPdf;
      sub.fOut := TRawByteStringStream.Create;
      try
        n := ReadIntValue(DictValue(Dict, '/N'));
        first := ReadIntValue(DictValue(Dict, '/First'));
        SetLength(nums, 0);
        SetLength(offs, 0);
        // each pair takes four characters at least: "1 0 "
        if (n > 0) and
           (first > 0) and
           (first <= length(result)) and
           (n <= first div 4) then
        begin
          // the header: n pairs "number offset"
          k := 1;
          SetLength(nums, n);
          SetLength(offs, n);
          for m := 0 to n - 1 do
          begin
            SkipWhite(result, k);
            nums[m] := ReadInt(result, k);
            SkipWhite(result, k);
            offs[m] := ReadInt(result, k);
            // the members follow each other from /First on, so that no
            // byte is left out of the normalized text
            if (nums[m] < 0) or
               (offs[m] < 0) or
               (k > first + 1) or
               (first + offs[m] > length(result)) or
               ((m = 0) and (offs[m] <> 0)) or
               ((m > 0) and (offs[m] < offs[m - 1])) then
            begin
              SetLength(nums, 0); // not as expected: normalized as one
              break;
            end;
          end;
        end;
        if nums = nil then
          sub.Syntax(result, {TopLevel=}false)
        else
        begin
          sub.Syntax(copy(result, 1, first), false);
          for m := 0 to n - 1 do
          begin
            if m < n - 1 then
              e := first + offs[m + 1]
            else
              e := length(result);
            start := sub.fOut.Position;
            sub.Syntax(copy(result, first + offs[m] + 1, e - first - offs[m]),
              false);
            AddSpan(fStreamSpans, nums[m], 0, start + 1, sub.fOut.Position + 1);
          end;
        end;
        result := sub.fOut.DataString;
        err := sub.fError;
      finally
        sub.fOut.Free;
      end;
    finally
      sub.Free;
    end;
    if err <> '' then
      Fail('object stream %: %', [ObjNum, err]);
  end
  else if typ = '/Metadata' then
    result := BlankXmpDates(result);
end;

procedure TPdfNormalizer.Syntax(const s: RawByteString; TopLevel: boolean);
var
  i, j, b, objStart, dataEnd, after: PtrInt;
  len, num1, num2, objNum, objGen, off, objOut, num1Pos, num2Pos, objPos: Int64;
  num1Out, num2Out, spanStart, dataOut: Int64;
  inStm: boolean;
  k: integer;
  found: boolean;
  tok, lastKey, dict, data, head: RawByteString;
  inId: boolean;
begin
  i := 1;
  lastKey := '';
  inId := false;
  num1 := -1;
  num2 := -1;
  objNum := -1;
  objGen := 0;
  objStart := 1;
  objOut := 0;
  num1Pos := 0;
  num2Pos := 0;
  objPos := 0;
  num1Out := 0;
  num2Out := 0;
  spanStart := 0;
  inStm := false;
  while (i <= length(s)) and (fError = '') do
    case s[i] of
      '%':
        begin // a comment, to the end of the line
          j := i;
          while (j <= length(s)) and not (s[j] in [#10, #13]) do
            inc(j);
          Emit(s, i, j);
          i := j;
        end;
      '(':
        begin
          j := i;
          if not SkipValue(s, j) then
          begin
            Fail('object %: literal string not closed', [objNum]);
            exit;
          end;
          tok := copy(s, i, j - i);
          // a date: (D:YYYYMMDDHHMMSS...)
          if ((lastKey = '/CreationDate') or (lastKey = '/ModDate')) and
             (length(tok) >= 18) and (tok[2] = 'D') and (tok[3] = ':') and
             IsDigits(tok, 4, 14) then
            ZeroDigits(tok, 4, 14);
          Emit(tok);
          lastKey := '';
          i := j;
        end;
      '<':
        if (i < length(s)) and (s[i + 1] = '<') then
        begin
          Emit('<<');
          inc(i, 2);
        end
        else
        begin // a hex string
          j := i;
          if not SkipValue(s, j) then
          begin
            Fail('object %: hex string not closed', [objNum]);
            exit;
          end;
          tok := copy(s, i, j - i);
          if inId then // the file identifier, random per document
            for b := 2 to length(tok) - 1 do
              if not (tok[b] in PDF_WHITE) then
                tok[b] := '0';
          Emit(tok);
          i := j;
        end;
      '[':
        begin
          inId := lastKey = '/ID';
          Emit('[');
          inc(i);
        end;
      ']':
        begin
          inId := false;
          Emit(']');
          inc(i);
        end;
      '/':
        begin // a name
          j := i + 1;
          while (j <= length(s)) and
                not (s[j] in PDF_WHITE + PDF_DELIM) do
            inc(j);
          tok := copy(s, i, j - i);
          // '/ABCDEF+Name': the subset tag, six random capitals
          if (length(tok) > 8) and (tok[8] = '+') then
          begin
            b := 2;
            while (b <= 7) and (tok[b] in ['A'..'Z']) do
              inc(b);
            if b = 8 then
              FillCharFast(tok[2], 6, ord('A'));
          end;
          Emit(tok);
          lastKey := tok;
          i := j;
        end;
      '0'..'9', '+', '-', '.':
        begin
          j := i;
          while (j <= length(s)) and (s[j] in ['0'..'9', '+', '-', '.']) do
            inc(j);
          tok := copy(s, i, j - i);
          num1 := num2;
          num1Pos := num2Pos;
          num1Out := num2Out;
          num2Out := fOut.Position;
          num2 := ReadIntValue(tok);
          num2Pos := i - 1; // 0-based offset of the number
          if (lastKey = '/Length') and TopLevel then
            tok := '0'; // varies with the deflated dates: checked at 'stream'
          Emit(tok);
          lastKey := '';
          i := j;
        end;
      'a'..'z', 'A'..'Z':
        begin // a keyword
          j := i;
          while (j <= length(s)) and (s[j] in ['a'..'z', 'A'..'Z']) do
            inc(j);
          if (j <= length(s)) and not (s[j] in PDF_WHITE + PDF_DELIM) then
          begin
            Fail('object %: keyword % not delimited', [objNum, copy(s, i, j - i)]);
            exit;
          end;
          tok := copy(s, i, j - i);
          i := j;
          lastKey := '';
          if not TopLevel then
            Emit(tok)
          else if tok = 'obj' then
          begin
            objNum := num1;
            objGen := num2;
            objPos := num1Pos;
            objStart := i;
            objOut := fOut.Position;
            spanStart := num1Out; // from the object number on
            inStm := false;
            Emit(tok);
          end
          else if tok = 'endobj' then
          begin
            Emit(tok);
            // an object stream gave its objects already
            if not inStm then
              AddSpan(fSpans, objNum, objGen, spanStart + 1, fOut.Position + 1);
          end
          else if tok = 'stream' then
          begin
            // the stream dictionary is the text since 'obj'
            dict := copy(s, objStart, i - 6 - objStart);
            tok := DictValue(dict, '/Length');
            b := 1;
            len := ReadInt(tok, b);
            if (len < 0) or (b <= length(tok)) then
            begin
              Fail('object % %: /Length % is not a direct integer',
                [objNum, objGen, tok]);
              exit;
            end;
            if (i <= length(s)) and (s[i] = #13) then
              inc(i);
            if (i > length(s)) or (s[i] <> #10) then
            begin
              Fail('object % %: no end of line after stream', [objNum, objGen]);
              exit;
            end;
            inc(i);
            if len > length(s) - i + 1 then
            begin
              Fail('object % %: /Length % beyond the end of the file',
                [objNum, objGen, len]);
              exit;
            end;
            dataEnd := i + len;
            b := dataEnd;
            if (b <= length(s)) and (s[b] = #13) then
              inc(b);
            if (b <= length(s)) and (s[b] = #10) then
              inc(b);
            if (b > length(s) - 8) or
               not CompareMem(@s[b], PAnsiChar('endstream'), 9) then
            begin
              Fail('object % %: /Length % does not end at endstream',
                [objNum, objGen, len]);
              exit;
            end;
            after := b + 9; // after endstream
            data := Stream(dict, copy(s, i, len), objNum);
            if DictValue(dict, '/Type') = '/XRef' then
            begin
              AddInt64(fXRefOffsets, objPos);
              // /W follows the file size: written in its canonical form, as
              // the rows are written as text
              head := copy(fOut.DataString, objOut + 1, maxInt);
              fOut.Size := objOut;
              fOut.Position := objOut;
              // the pieces are emitted, not concatenated: FPC 3.2.2 i386 lost
              // a RawByteString of code page CP_RAWBYTESTRING in a concatenation
              if DictValuePos(head, '/W', b, j) then
              begin
                Emit(head, 1, b);
                Emit('[*]');
                Emit(head, j, length(head) + 1);
              end
              else
                Emit(head);
            end;
            Emit('stream'#10);
            dataOut := fOut.Position;
            Emit(data);
            Emit(#10'endstream');
            inStm := fStreamSpans <> nil;
            for k := 0 to high(fStreamSpans) do
              with fStreamSpans[k] do
                AddSpan(fSpans, Num, Gen, dataOut + Start, dataOut + Stop);
            fStreamSpans := nil;
            i := after;
          end
          else if tok = 'xref' then
          begin
            AddInt64(fXRefOffsets, i - 5); // 0-based offset of the keyword
            Emit(tok);
            XRefTable(s, i);
          end
          else if tok = 'startxref' then
          begin
            SkipWhite(s, i);
            off := ReadInt(s, i);
            found := false;
            for k := 0 to high(fXRefOffsets) do
              if fXRefOffsets[k] = off then
                found := true;
            if not found then
              Fail('startxref % points to neither xref nor an XRef stream', [off]);
            Emit(tok);
            Emit(#10'0');
          end
          else
            Emit(tok);
        end;
    else
      begin
        Emit(s, i, i + 1);
        inc(i);
      end;
    end;
end;

function TPdfNormalizer.Normalize(const Pdf: RawByteString;
  out Error: RawUtf8): RawByteString;
begin
  fPdf := Pdf;
  fError := '';
  fOut := TRawByteStringStream.Create;
  try
    Syntax(Pdf, {TopLevel=}true);
    result := fOut.DataString;
  finally
    FreeAndNil(fOut);
  end;
  Error := fError;
end;

function NormalizePdf(const Pdf: RawByteString; out Error: RawUtf8): RawUtf8;
var
  spans: TPdfObjectSpans;
begin
  result := NormalizePdf(Pdf, Error, spans);
end;

function NormalizePdf(const Pdf: RawByteString; out Error: RawUtf8;
  out Objects: TPdfObjectSpans): RawUtf8;
var
  n: TPdfNormalizer;
  t: RawByteString;
begin
  n := TPdfNormalizer.Create;
  try
    t := n.Normalize(Pdf, Error);
    Objects := n.fSpans;
  finally
    n.Free;
  end;
  // as RawUtf8, like the rest of this unit: a RawByteString of code page
  // CP_RAWBYTESTRING may be converted when assigned or concatenated
  FastSetString(result, pointer(t), length(t));
end;

function PdfStructRoles(const s: RawUtf8): RawUtf8;
var
  t, role: RawUtf8;
  names: TRawUtf8DynArray;
  counts: TIntegerDynArray;
  p, d, e, r, k, j, tmp: integer;
  found: boolean;
begin
  result := '';
  t := InflatePdf(s);
  names := nil;
  counts := nil;
  p := PosEx('/StructElem', t, 1);
  while p > 0 do
  begin
    // the role is the /S of the dictionary that names itself a StructElem
    d := p;
    while (d > 1) and not Matches(t, d, '<<') do
      dec(d);
    e := PosEx('/StructElem', t, p + 11);
    if e = 0 then
      e := length(t) + 1;
    r := PosEx('/S/', t, d);
    if (r > 0) and (r < e) then
    begin
      inc(r, 3);
      k := r;
      while (k <= length(t)) and not (t[k] in
            ['/', '<', '>', '[', ']', '(', ')', ' ', #10, #13]) do
        inc(k);
      role := copy(t, r, k - r);
      found := false;
      for j := 0 to high(names) do
        if names[j] = role then
        begin
          inc(counts[j]);
          found := true;
          break;
        end;
      if not found then
      begin
        SetLength(names, length(names) + 1);
        SetLength(counts, length(counts) + 1);
        names[high(names)] := role;
        counts[high(counts)] := 1;
      end;
    end;
    p := PosEx('/StructElem', t, p + 11);
  end;
  // a handful of roles: an insertion sort is enough
  for k := 1 to high(names) do
  begin
    j := k;
    while (j > 0) and (names[j - 1] > names[j]) do
    begin
      role := names[j];
      names[j] := names[j - 1];
      names[j - 1] := role;
      tmp := counts[j];
      counts[j] := counts[j - 1];
      counts[j - 1] := tmp;
      dec(j);
    end;
  end;
  for k := 0 to high(names) do
    result := result + names[k] + ' ' + Int32ToUtf8(counts[k]) + #10;
end;


{ ---------- objects and fonts ---------- }

function IsDelim(c: AnsiChar): boolean;
begin
  result := c in [#0, #9, #10, #12, #13, ' ', '/', '<', '>', '[', ']', '(', ')',
    '{', '}', '%'];
end;

// every object's text by its number: the top-level "n g obj" ones and those
// packed in object streams
function PdfObjects(const t: RawUtf8): TRawUtf8DynArray;

  procedure Store(num: integer; const body: RawUtf8);
  begin
    if num < 0 then
      exit;
    if num >= length(result) then
      SetLength(result, num + 64);
    result[num] := body;
  end;

var
  i, j, k, e, num, n, first, b: integer;
  body, data: RawUtf8;
  nums, offs: TIntegerDynArray;
  c: PUtf8Char;
begin
  result := nil;
  i := PosEx(' obj', t, 1);
  while i > 0 do
  begin
    // "num gen obj": the generation, a space, the number
    j := i - 1;
    while (j > 0) and IsDigit(t[j]) do
      dec(j);
    if (j < i - 1) and (j > 1) and (t[j] = ' ') and IsDigit(t[j - 1]) and
       ((i + 4 > length(t)) or IsDelim(t[i + 4])) then
    begin
      k := j - 1;
      while (k > 0) and IsDigit(t[k]) do
        dec(k);
      num := GetInteger(pointer(copy(t, k + 1, j - k - 1)));
      e := PosEx('endobj', t, i + 4);
      if e = 0 then
        e := length(t) + 1;
      body := copy(t, i + 4, e - i - 4);
      Store(num, body);
      i := e;
    end;
    i := PosEx(' obj', t, i + 4);
  end;
  // the objects of each object stream: N pairs "num offset", then the data
  for i := 0 to high(result) do
    if PosEx('/Type/ObjStm', result[i]) > 0 then
    begin
      body := result[i];
      j := PosEx('/N ', body);
      k := PosEx('/First ', body);
      b := PosEx('stream', body);
      if (j = 0) or (k = 0) or (b = 0) then
        continue;
      n := GetInteger(@body[j + 3]);
      first := GetInteger(@body[k + 7]);
      inc(b, 6);
      if (b <= length(body)) and (body[b] = #13) then
        inc(b);
      if (b <= length(body)) and (body[b] = #10) then
        inc(b);
      e := PosEx('endstream', body, b);
      if e = 0 then
        continue;
      data := copy(body, b, e - b);
      SetLength(nums, n);
      SetLength(offs, n);
      c := pointer(data);
      for k := 0 to n - 1 do
      begin
        nums[k] := GetNextItemCardinal(c, ' ');
        offs[k] := GetNextItemCardinal(c, ' ');
      end;
      for k := 0 to n - 1 do
        if k < n - 1 then
          Store(nums[k], copy(data, first + offs[k] + 1, offs[k + 1] - offs[k]))
        else
          Store(nums[k], copy(data, first + offs[k] + 1, maxInt));
    end;
end;

// the object a "n g R" (or "[n g R]") points to
function Deref(const objs: TRawUtf8DynArray; const ref: RawUtf8): RawUtf8;
var
  c: PUtf8Char;
  num: integer;
begin
  result := '';
  c := pointer(ref);
  if c = nil then
    exit;
  if c^ = '[' then
    inc(c);
  while c^ = ' ' do
    inc(c);
  num := GetCardinal(c);
  if (num > 0) and (num < length(objs)) then
    result := objs[num];
end;

function PdfFonts(const s: RawUtf8): RawUtf8;
var
  objs, lines: TRawUtf8DynArray;
  i, k, n: integer;
  font, sub, desc, ftype, name, emb, tmp: RawUtf8;
begin
  result := '';
  objs := PdfObjects(InflatePdf(s));
  lines := nil;
  n := 0;
  for i := 0 to high(objs) do
  begin
    font := objs[i];
    if DictValue(font, '/Type') <> '/Font' then
      continue;
    ftype := copy(DictValue(font, '/Subtype'), 2, maxInt);
    // the descendant of a Type0 is listed with it, not on its own
    if (ftype = '') or (ftype = 'CIDFontType0') or (ftype = 'CIDFontType2') then
      continue;
    name := copy(DictValue(font, '/BaseFont'), 2, maxInt);
    desc := font;
    if ftype = 'Type0' then
    begin
      sub := Deref(objs, DictValue(font, '/DescendantFonts'));
      ftype := ftype + '/' + copy(DictValue(sub, '/Subtype'), 2, maxInt);
      desc := sub;
    end;
    desc := Deref(objs, DictValue(desc, '/FontDescriptor'));
    if DictValue(desc, '/FontFile2') <> '' then
      emb := 'FontFile2'
    else if DictValue(desc, '/FontFile3') <> '' then
      emb := 'FontFile3'
    else if DictValue(desc, '/FontFile') <> '' then
      emb := 'FontFile'
    else
      emb := 'no';
    tmp := name + ' ' + ftype + ' emb=' + emb + ' sub=';
    if IsSubsetPrefix('/' + name, 1) then
      tmp := tmp + 'yes'
    else
      tmp := tmp + 'no';
    if DictValue(font, '/ToUnicode') <> '' then
      tmp := tmp + ' uni=yes'
    else
      tmp := tmp + ' uni=no';
    SetLength(lines, n + 1);
    lines[n] := tmp;
    inc(n);
  end;
  // a handful of fonts: an insertion sort is enough
  for i := 1 to n - 1 do
  begin
    k := i;
    while (k > 0) and (lines[k - 1] > lines[k]) do
    begin
      tmp := lines[k];
      lines[k] := lines[k - 1];
      lines[k - 1] := tmp;
      dec(k);
    end;
  end;
  for i := 0 to n - 1 do
    result := result + lines[i] + #10;
end;

end.
