/// golden file tests: generated PDFs compared with a recorded baseline
// - the baseline is per machine, not versioned: embedded and subset faces come
// from the fonts installed, so the same document differs between systems
// - record it with "test_runner --golden-record" on the commit to compare
// against; without a baseline the cases are skipped
// - compared in the form pdf_inspect.NormalizePdf() gives: decoded, with what
// changes between runs blanked - the /ID, subset tags, dates, and the stream
// lengths and offsets that move with them - after checking that they are right
// - two assertions per case, recorded, skipped or compared: the count does not
// depend on a baseline
unit test_pdf_golden;

interface

{$I mormot.defines.inc}
{$I test_defines.inc}

uses
  Classes,
  SysUtils,
  {$ifdef PDF_HASVCLCANVAS}
  Types,                // TPoint, TRect on Delphi; mormot.pdf's win on FPC, as in the bridge
  Graphics,             // TCanvas.Font, colors
  mormot.pdf.canvas,    // TPdfDocumentVcl, TPdfVclCanvas
  {$endif PDF_HASVCLCANVAS}
  mormot.core.base,
  mormot.core.os,
  mormot.core.test,
  mormot.core.text,     // FormatUtf8, FormatString
  mormot.core.unicode,  // StringToUtf8
  mormot.pdf.types,     // TPdfStructRole, GetPdfFonts
  mormot.pdf,
  pdf_inspect,          // NormalizePdf, ComparePdfText
  test_pdf_subset;      // DrawUtf8Text

var
  /// set by the runner from --golden-record: write the baseline, compare nothing
  GoldenRecord: boolean;

const
  /// creation and modification date of every golden document
  // - the dates are blanked before comparing anyway; a fixed date keeps the
  // recorded files themselves reproducible where the API allows it
  GOLDEN_DATE = 46000.5;

type
  /// base class of the golden file test cases
  TPdfGoldenTestCase = class(TSynTestCase)
  protected
    /// record or compare Pdf as the golden file Name
    procedure CheckGolden(const Name: RawUtf8; const Pdf: RawByteString);
  end;

  /// golden files of documents drawn through TPdfDocument/TPdfCanvas (layer 1)
  TPdfGoldenTests = class(TPdfGoldenTestCase)
  protected
    function SaveDoc(Doc: TPdfDocument): RawByteString;
  published
    procedure CompareReportsEveryObject;
    procedure CompareSyntheticObjects;
    procedure Base14Untagged;
    procedure Base14Compressed;
    procedure TaggedEmbedded;
    procedure PdfA3UAttachment;
    procedure CjkSubset;
    procedure ArabicShaped;
    {$ifdef PDF_HASVCLCANVAS}
    procedure CanvasBridge;
    procedure CanvasBridgeShapes;
    procedure CanvasBridgePages;
    procedure CanvasBridgeTagged;
    {$endif PDF_HASVCLCANVAS}
  end;

/// the folder of this machine's baseline, below the executable
function GoldenFolder: TFileName;


implementation

function GoldenFolder: TFileName;
var
  key: RawUtf8;
begin
  key := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  key := LowerCase(ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' +
    CPU_ARCH_TEXT + '_' + StringReplaceAll(key, ' ', '-'));
  result := Executable.ProgramFilePath + 'golden' + PathDelim +
    Utf8ToString(key) + PathDelim;
end;

{ TPdfGoldenTestCase }

procedure TPdfGoldenTestCase.CheckGolden(const Name: RawUtf8;
  const Pdf: RawByteString);
var
  fn: TFileName;
  expected, actual, err, diff: RawUtf8;
  oe, oa: TPdfObjectSpans;
begin
  fn := GoldenFolder + Utf8ToString(Name) + '.pdf';
  // the first assertion: the new file itself - a broken one would also make
  // a baseline every later run fails against
  actual := NormalizePdf(Pdf, err, oa);
  if CheckFailed(err = '', FormatString('%: %', [Name, err])) then
    exit;
  // the second: recorded, skipped or compared - a difference by Check(false),
  // not TestFailed(), so that it counts as an assertion like the others
  if GoldenRecord then
  begin
    EnsureDirectoryExists(GoldenFolder);
    Check(FileFromString(Pdf, fn), 'golden file written');
    AddConsole('recorded %', [fn]);
  end
  else if not FileExists(fn) then
    Check(true, 'SKIP: no golden baseline - run test_runner --golden-record')
  else
  begin
    expected := NormalizePdf(StringFromFile(fn), err, oe);
    if err <> '' then
      Check(false, FormatString('% golden file: %', [Name, err]))
    else if ComparePdfText(expected, actual, oe, oa, diff) then
      Check(true)
    else
    begin
      // keep the new output beside the baseline for a viewer or a diff tool
      FileFromString(Pdf, GoldenFolder + Utf8ToString(Name) + '.actual.pdf');
      Check(false, FormatString('% differs from the golden file (a: golden, ' +
        'b: new)'#10'%', [Name, diff]));
    end;
  end;
end;


{ TPdfGoldenTests }

const
  CJK_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$4F60#$597D#$FF0C#$4E16#$754C#$FF01 {$else}
    #$E4#$BD#$A0#$E5#$A5#$BD#$EF#$BC#$8C#$E4#$B8#$96#$E7#$95#$8C#$EF#$BC#$81 {$endif};
  ARABIC_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0645#$0631#$062D#$0628#$0627' '#$0643#$062A#$0627#$0628 {$else}
    #$D9#$85#$D8#$B1#$D8#$AD#$D8#$A8#$D8#$A7' '#$D9#$83#$D8#$AA#$D8#$A7#$D8#$A8 {$endif};
  UMLAUTS: RawUtf8 = 'Umlauts: ' + {$ifdef HASCODEPAGE}
    #$00E4#$00F6#$00FC#$00C4#$00D6#$00DC#$00DF' '#$20AC {$else}
    #$C3#$A4#$C3#$B6#$C3#$BC#$C3#$84#$C3#$96#$C3#$9C#$C3#$9F' '#$E2#$82#$AC {$endif};
  {$ifdef OSWINDOWS}
  CJK_FONT = 'Microsoft YaHei';
  ARABIC_FONT = 'Tahoma';
  {$else}
  {$ifdef OSDARWIN}
  CJK_FONT = 'Hiragino Sans GB';
  ARABIC_FONT = 'Geeza Pro';
  {$else}
  CJK_FONT = 'Droid Sans Fallback';
  ARABIC_FONT = 'Noto Naskh Arabic';
  {$endif OSDARWIN}
  {$endif OSWINDOWS}
  INVOICE_XML = '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:' +
    'standard:CrossIndustryInvoice:100"/>'#10;

function TPdfGoldenTests.SaveDoc(Doc: TPdfDocument): RawByteString;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    Doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(result, ms.Memory, ms.Size);
  finally
    ms.Free;
  end;
end;

// a tagged document: its structure elements go to an object stream
function CompareDoc(const Alt1, Alt2, Text: RawUtf8; Pages: integer): RawByteString;
var
  doc: TPdfDocument;
  ms: TMemoryStream;
  sans, serif, mono: string;
  p: integer;
begin
  doc := TPdfDocument.Create;
  ms := TMemoryStream.Create;
  try
    doc.CompressionMethod := cmNone;
    doc.Tagged := true;
    GetPdfFonts(doc.EmbeddedTTF, sans, serif, mono);
    for p := 1 to Pages do
    begin
      doc.AddPage;
      doc.Canvas.BeginStructContent(psrFigure, Alt1);
      doc.Canvas.Rectangle(56, 600, 120, 80);
      doc.Canvas.Stroke;
      doc.Canvas.EndStructContent;
      doc.Canvas.BeginStructContent(psrFigure, Alt2);
      doc.Canvas.Ellipse(200, 600, 120, 80);
      doc.Canvas.Stroke;
      doc.Canvas.EndStructContent;
      doc.Canvas.BeginStructContent(psrP);
      doc.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(doc, 56, 500, Text);
      doc.Canvas.EndStructContent;
    end;
    doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(result, ms.Memory, ms.Size);
  finally
    ms.Free;
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.CompareReportsEveryObject;
var
  a, b, err, diff: RawUtf8;
  oa, ob: TPdfObjectSpans;

  function Differs(const PdfB: RawByteString): boolean;
  begin
    b := NormalizePdf(PdfB, err, ob);
    CheckEqual(err, '', 'b normalized');
    result := not ComparePdfText(a, b, oa, ob, diff);
  end;

begin
  { pdfcheck and CheckGolden name every differing object, paired by number:
    an expected difference (a date) must not hide another one further on -
    also inside one object stream, and text that looks like an object
    header is no object }
  a := NormalizePdf(CompareDoc('one', 'two', 'x 99 0 obj y', 1), err, oa);
  CheckEqual(err, '', 'normalized');
  Check(length(oa) > 5, 'objects found');
  Check(not Differs(CompareDoc('one', 'two', 'x 99 0 obj y', 1)), 'equal');
  CheckEqual(diff, '', 'no difference to tell');
  Check(Differs(CompareDoc('ONE', 'TWO', 'x 99 0 obj y', 1)),
    'two structure elements differ');
  Check(PosEx('object', diff, PosEx('object', diff) + 1) > 0,
    'both named: ' + Utf8ToString(diff));
  Check(PosEx('added', diff) + PosEx('removed', diff) = 0, 'none added');
  Check(Differs(CompareDoc('one', 'two', 'x 99 0 obj z', 1)), 'text differs');
  Check(PosEx('object 99 0', diff) = 0, 'no object 99 in a string');
  Check(Differs(CompareDoc('one', 'two', 'x 99 0 obj y', 2)), 'a page more');
  Check(PosEx('added', diff) > 0, 'the objects of the new page added');
end;

// a minimal PDF of the objects (number, body), in this order, with a valid
// xref table: what NormalizePdf checks
function MiniPdf(const Nums: array of integer;
  const Bodies: array of RawUtf8): RawUtf8;
var
  i, n, x: integer;
  offs: array of integer;
  num: RawUtf8;
begin
  result := '%PDF-1.4'#10;
  n := 0;
  for i := 0 to high(Nums) do
    if Nums[i] > n then
      n := Nums[i];
  SetLength(offs, n + 1);
  for i := 0 to high(Nums) do
  begin
    offs[Nums[i]] := length(result);
    result := result + Int32ToUtf8(Nums[i]) + ' 0 obj'#10 + Bodies[i] +
      #10'endobj'#10;
  end;
  x := length(result);
  result := result + 'xref'#10'0 ' + Int32ToUtf8(n + 1) + #10 +
    '0000000000 65535 f '#10;
  for i := 1 to n do
  begin
    num := Int32ToUtf8(offs[i]);
    while length(num) < 10 do
      num := '0' + num;
    result := result + num + ' 00000 n '#10;
  end;
  result := result + 'trailer'#10'<</Size ' + Int32ToUtf8(n + 1) + '>>'#10 +
    'startxref'#10 + Int32ToUtf8(x) + #10'%%EOF'#10;
end;

// an uncompressed object stream of the members 10, 11..., offsets from
// /First; Prefix goes before the first member, which no offset covers
function ObjStm(const Members: array of RawUtf8; const Prefix: RawUtf8): RawUtf8;
var
  i, o: integer;
  head, data: RawUtf8;
begin
  head := '';
  data := Prefix;
  o := length(Prefix);
  for i := 0 to high(Members) do
  begin
    head := head + Int32ToUtf8(10 + i) + ' ' + Int32ToUtf8(o) + ' ';
    data := data + Members[i];
    inc(o, length(Members[i]));
  end;
  result := '<</Type/ObjStm/N ' + Int32ToUtf8(length(Members)) + '/First ' +
    Int32ToUtf8(length(head)) + '/Length ' + Int32ToUtf8(length(head + data)) +
    '>>stream'#10 + head + data + #10'endstream';
end;

procedure TPdfGoldenTests.CompareSyntheticObjects;
var
  a, b, err, diff: RawUtf8;
  oa, ob: TPdfObjectSpans;

  function Compare(const PdfA, PdfB: RawUtf8): boolean;
  begin
    a := NormalizePdf(PdfA, err, oa);
    CheckEqual(err, '', 'a normalized');
    b := NormalizePdf(PdfB, err, ob);
    CheckEqual(err, '', 'b normalized');
    result := ComparePdfText(a, b, oa, ob, diff);
  end;

  // an object stream of N members as Body gives them
  function RawObjStm(N, First: integer; const Body: RawUtf8): RawUtf8;
  begin
    result := '<</Type/ObjStm/N ' + Int32ToUtf8(N) + '/First ' +
      Int32ToUtf8(First) + '/Length ' + Int32ToUtf8(length(Body)) +
      '>>stream'#10 + Body + #10'endstream';
  end;

begin
  // a string that looks like an object header is no object
  Check(not Compare(MiniPdf([1], ['(x'#10'99 0 obj'#10'y)']),
                    MiniPdf([1], ['(x'#10'99 0 obj'#10'z)'])), 'string');
  Check(PosEx('object 1 0', diff) > 0, 'the object named');
  Check(PosEx('object 99', diff) = 0, 'no object 99');
  // two members of one object stream, each named
  Check(not Compare(MiniPdf([1], [ObjStm(['(a) ', '(b) '], '')]),
                    MiniPdf([1], [ObjStm(['(A) ', '(B) '], '')])), 'object stream');
  Check((PosEx('object 10 0', diff) > 0) and (PosEx('object 11 0', diff) > 0),
    'both members named');
  // a member that grows moves the offsets after it, and /First with their
  // digits: only the member is named
  Check(not Compare(MiniPdf([1], [ObjStm(['(a) ', '(b) '], '')]),
    MiniPdf([1], [ObjStm(['(aaaaaaaaa) ', '(b) '], '')])), 'a member grown');
  Check(PosEx('object 10 0', diff) > 0, 'the grown member named');
  Check(PosEx('object 11 0', diff) = 0, 'not the member after it');
  Check(PosEx('outside the objects', diff) = 0, 'not the offsets, not /First');
  // a /First that is no member boundary: the stream as it is, and /First
  Check(not Compare(MiniPdf([1], [RawObjStm(1, 5, '10 0 (a) ')]),
    MiniPdf([1], [RawObjStm(1, 6, '10 0 (a) ')])), 'a /First off the members');
  // the same bytes cut into other members, the offsets blanked
  Check(not Compare(MiniPdf([1], [RawObjStm(2, 10, '10 0 11 4 (a) (b) ')]),
    MiniPdf([1], [RawObjStm(2, 10, '10 0 11 0 (a) (b) ')])), 'other bounds');
  Check(PosEx('object 10 0', diff) > 0, 'the member of other bounds named');
  // bytes before the first member are no member: the stream is compared
  // as one piece, and they are not lost
  Check(not Compare(MiniPdf([1], [ObjStm(['(z)'], '(A) ')]),
                    MiniPdf([1], [ObjStm(['(z)'], '(B) ')])), 'bytes before');
  // the same objects in another order
  Check(not Compare(MiniPdf([1, 2], ['(x)', '(y)']),
                    MiniPdf([2, 1], ['(y)', '(x)'])), 'reordered');
  Check(diff <> '', 'the order named');
  // an object defined twice (incremental update): the second one compared
  Check(not Compare(MiniPdf([1, 1], ['(x)', '(y)']),
                    MiniPdf([1, 1], ['(x)', '(z)'])), 'redefined');
  Check(diff <> '', 'the second definition named');
  // JPEG data is kept as it is - in an image, nowhere else
  NormalizePdf(MiniPdf([1], ['<</Subtype/Image/Filter/DCTDecode/Length 3>>' +
    #10'stream'#10'abc'#10'endstream']), err);
  CheckEqual(err, '', 'a JPEG image');
  NormalizePdf(MiniPdf([1], ['<</Type/XRef/Filter/DCTDecode/Length 3>>' +
    #10'stream'#10'abc'#10'endstream']), err);
  Check(err <> '', 'no JPEG xref stream');
  NormalizePdf(MiniPdf([1], ['<</Type/XRef/Subtype/Image/Filter/DCTDecode' +
    '/Length 3>>'#10'stream'#10'abc'#10'endstream']), err);
  Check(err <> '', 'no JPEG xref stream that claims to be an image');
  // empty on either side
  Check(not ComparePdfText('', 'x', nil, nil, diff), 'empty a');
  Check(not ComparePdfText('x', '', nil, nil, diff), 'empty b');
end;

procedure TPdfGoldenTests.Base14Untagged;
var
  doc: TPdfDocument;
  c: TPdfCanvas;
  i: integer;
begin
  doc := TPdfDocument.Create({AUseOutlines=}true);
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.Info.Title := 'Golden base-14';
    doc.CompressionMethod := cmNone;
    doc.StandardFontsReplace := true;
    doc.EmbeddedTTF := false;
    doc.DefaultPaperSize := psA4;
    doc.AddPage;
    c := doc.Canvas;
    c.SetFont('Helvetica', 20, [pfsBold], PDF_DEFAULT_CHARSET);
    c.TextOut(56, 780, 'Base-14 fonts, no embedding');
    doc.CreateOutline('Base-14 fonts', 1, 800);
    c.SetFont('Times New Roman', 12, [pfsItalic], PDF_DEFAULT_CHARSET);
    c.TextOut(56, 750, 'Times italic: The quick brown fox jumps over the lazy dog.');
    c.SetFont('Courier New', 11, [], PDF_DEFAULT_CHARSET);
    c.TextOut(56, 732, 'Courier: function Foo: integer;');
    c.SetRGBStrokeColor($5A2D14);
    c.SetRGBFillColor($E8C8B4);
    c.SetLineWidth(1.5);
    c.Rectangle(56, 600, 120, 80);
    c.FillStroke;
    c.Ellipse(200, 600, 120, 80);
    c.Stroke;
    c.MoveTo(340, 600);
    c.CurveToC(380, 700, 420, 580, 460, 680);
    c.Stroke;
    for i := 0 to 2 do
    begin
      c.SetLineWidth(0.5 + i);
      c.MoveTo(56, 560 - i * 20);
      c.LineTo(539, 560 - i * 20);
      c.Stroke;
    end;
    doc.AddPage;
    doc.Canvas.SetFont('Helvetica', 12, [], PDF_DEFAULT_CHARSET);
    doc.Canvas.TextOut(56, 780, 'Second page');
    doc.CreateOutline('Second page', 1, 800);
    CheckGolden('base14_untagged', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.Base14Compressed;
var
  doc: TPdfDocument;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmFlateDecode;
    doc.StandardFontsReplace := true;
    doc.EmbeddedTTF := false;
    doc.AddPage;
    doc.Canvas.SetFont('Helvetica', 12, [], PDF_DEFAULT_CHARSET);
    doc.Canvas.TextOut(56, 780, 'Deflated content stream');
    doc.Canvas.Rectangle(56, 700, 200, 50);
    doc.Canvas.Stroke;
    CheckGolden('base14_flate', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.TaggedEmbedded;
var
  doc: TPdfDocument;
  c: TPdfCanvas;
  sans, serif, mono: string;
  i: integer;
begin
  doc := TPdfDocument.Create({AUseOutlines=}true);
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.Tagged := true;
    doc.DefaultLanguage := 'en';
    doc.Info.Title := 'Golden tagged';
    GetPdfFonts(doc.EmbeddedTTF, sans, serif, mono);
    doc.AddPage;
    c := doc.Canvas;
    c.BeginStructContent(psrH1);
    c.SetFont(StringToUtf8(sans), 20, [pfsBold], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 780, 'Tagged document');
    c.EndStructContent;
    doc.CreateOutline('Tagged document', 1, 800);
    c.BeginStructContent(psrP);
    c.SetFont(StringToUtf8(serif), 12, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 750, 'A paragraph in the serif face.');
    c.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 732, UMLAUTS);
    c.SetFont(StringToUtf8(mono), 11, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 714, 'function Foo: integer;');
    c.EndStructContent;
    c.BeginStructContent(psrFigure, 'A rectangle and an ellipse');
    c.Rectangle(56, 600, 120, 80);
    c.Stroke;
    c.Ellipse(200, 600, 120, 80);
    c.Stroke;
    c.EndStructContent;
    c.BeginStructContent(psrTable);
    c.BeginStructContent(psrTHead);
    c.BeginStructContent(psrTR);
    c.SetFont(StringToUtf8(sans), 11, [pfsBold], PDF_DEFAULT_CHARSET);
    for i := 0 to 1 do
    begin
      c.BeginStructContent(psrTH);
      DrawUtf8Text(doc, 56 + i * 150, 560, FormatUtf8('Head %', [i]));
      c.EndStructContent;
    end;
    c.EndStructContent; // TR
    c.EndStructContent; // THead
    c.BeginStructContent(psrTBody);
    c.SetFont(StringToUtf8(sans), 11, [], PDF_DEFAULT_CHARSET);
    for i := 1 to 3 do
    begin
      c.BeginStructContent(psrTR);
      c.BeginStructContent(psrTD);
      DrawUtf8Text(doc, 56, 560 - i * 18, FormatUtf8('Row %', [i]));
      c.EndStructContent;
      c.BeginStructContent(psrTD);
      DrawUtf8Text(doc, 206, 560 - i * 18, FormatUtf8('%', [i * 10]));
      c.EndStructContent;
      c.EndStructContent; // TR
    end;
    c.EndStructContent; // TBody
    c.BeginStructContent(psrTFoot);
    c.BeginStructContent(psrTR);
    c.BeginStructContent(psrTD);
    DrawUtf8Text(doc, 56, 470, 'Total');
    c.EndStructContent;
    c.BeginStructContent(psrTD);
    DrawUtf8Text(doc, 206, 470, '60');
    c.EndStructContent;
    c.EndStructContent; // TR
    c.EndStructContent; // TFoot
    c.EndStructContent; // Table
    c.BeginArtifact;
    c.SetFont(StringToUtf8(sans), 9, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 40, 'page 1');
    c.EndArtifact;
    CheckGolden('tagged_embedded', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.PdfA3UAttachment;
var
  doc: TPdfDocument;
  sans, serif, mono: string;
begin
  doc := TPdfDocument.Create(false, 0, pdfa3U);
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.Tagged := true;
    doc.DefaultLanguage := 'en';
    doc.Info.Title := 'Golden PDF/A-3U';
    GetPdfFonts(true, sans, serif, mono);
    doc.AddPage;
    doc.Canvas.BeginStructContent(psrP);
    doc.Canvas.SetFont(StringToUtf8(sans), 12, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 780, 'Invoice with its XML attached');
    doc.Canvas.EndStructContent;
    doc.CreateFileAttachmentFrom(INVOICE_XML, 'factur-x.xml',
      'Factur-X invoice data', 'text/xml', GOLDEN_DATE, GOLDEN_DATE, nil,
      afrAlternative);
    doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931');
    CheckGolden('pdfa3u_attachment', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.CjkSubset;
var
  doc: TPdfDocument;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.EmbeddedTTF := true;
    doc.AddPage;
    doc.Canvas.SetFont(CJK_FONT, 24, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 760, CJK_TEXT);
    CheckGolden('cjk_subset', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

procedure TPdfGoldenTests.ArabicShaped;
var
  doc: TPdfDocument;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.EmbeddedTTF := true;
    doc.AddPage;
    doc.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
    DrawUtf8Text(doc, 56, 760, ARABIC_TEXT); // isolated forms, no shaper
    doc.UseUniscribe := true;
    doc.Canvas.RightToLeftText := true;
    DrawUtf8Text(doc, 56, 700, ARABIC_TEXT); // shaped, right to left
    CheckGolden('arabic_shaped', SaveDoc(doc));
  finally
    doc.Free;
  end;
end;

{$ifdef PDF_HASVCLCANVAS}
procedure TPdfGoldenTests.CanvasBridge;
var
  doc: TPdfDocumentVcl;
  c: TPdfVclCanvas;
  ms: TMemoryStream;
  pdf: RawByteString;
begin
  ms := TMemoryStream.Create;
  doc := TPdfDocumentVcl.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.ScreenLogPixels := 96;
    doc.AddPage;
    c := doc.VclCanvas;
    c.Font.Name := 'Helvetica';
    c.Font.Size := 18;
    c.Font.Style := [fsBold];
    c.TextOut(40, 40, 'TCanvas bridge');
    c.Font.Size := 11;
    c.Font.Style := [];
    c.Font.Color := clNavy;
    c.TextOut(40, 80, 'Pixels at 96 DPI, Y from the top edge.');
    c.Pen.Color := clRed;
    c.Pen.Width := 2;
    c.Brush.Color := clYellow;
    c.Rectangle(40, 120, 200, 200);
    c.Brush.Color := clAqua;
    c.Ellipse(220, 120, 380, 200);
    c.Pen.Color := clBlack;
    c.Pen.Width := 1;
    c.MoveTo(40, 240);
    c.LineTo(500, 240);
    c.Brush.Color := clSilver;
    c.RoundRect(40, 260, 200, 320, 20, 20);
    doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(pdf, ms.Memory, ms.Size);
    CheckGolden('canvas_bridge', pdf);
  finally
    doc.Free;
    ms.Free;
  end;
end;

// a bridge document as the golden cases draw it: standard fonts, uncompressed
function NewBridgeDoc: TPdfDocumentVcl;
begin
  result := TPdfDocumentVcl.Create;
  result.Info.CreationDate := GOLDEN_DATE;
  result.CompressionMethod := cmNone;
  result.EmbeddedTTF := false;
  result.StandardFontsReplace := true;
  result.ScreenLogPixels := 96; // not the screen's: the baseline is fixed
end;

function BridgePoint(X, Y: integer): TPoint;
begin
  result.X := X;
  result.Y := Y;
end;

// the TCanvas calls the first case leaves out, and the state they share
procedure TPdfGoldenTests.CanvasBridgeShapes;
var
  doc: TPdfDocumentVcl;
  c: TPdfVclCanvas;
  r: TRect; // as the bridge declares it: mormot.pdf's on FPC
  pts: array[0..3] of TPoint;
  pdf: RawByteString;
begin
  doc := NewBridgeDoc;
  try
    doc.AddPage;
    c := doc.VclCanvas;
    pts[0] := BridgePoint(40, 60);
    pts[1] := BridgePoint(120, 20);
    pts[2] := BridgePoint(200, 60);
    pts[3] := BridgePoint(280, 20);
    c.Pen.Color := clGreen;
    c.Polyline(pts);
    c.Polyline(Slice(pts, 1)); // one point: nothing drawn
    // a polygon with brush and pen, without brush, without pen
    pts[0] := BridgePoint(40, 100);
    pts[1] := BridgePoint(100, 160);
    pts[2] := BridgePoint(40, 160);
    c.Brush.Color := clYellow;
    c.Polygon(Slice(pts, 3));
    c.Brush.Style := bsClear;
    pts[0].X := 140;
    pts[1].X := 200;
    pts[2].X := 140;
    c.Polygon(Slice(pts, 3));
    c.Brush.Style := bsSolid;
    c.Pen.Style := psClear;
    pts[0].X := 240;
    pts[1].X := 300;
    pts[2].X := 240;
    c.Polygon(Slice(pts, 3));
    c.Polygon(Slice(pts, 1)); // one point: nothing drawn
    c.Pen.Style := psSolid;
    // FillRect: brush only, the pen restored after it
    r.Left := 40;
    r.Top := 200;
    r.Right := 140;
    r.Bottom := 240;
    c.Brush.Color := clSilver;
    c.FillRect(r);
    c.Rectangle(160, 200, 260, 240);
    // fractions of a pixel
    c.RectangleFrac(40.5, 260.25, 140.75, 300.5);
    c.Font.Name := 'Helvetica';
    c.Font.Size := -12; // a negative size is the height as well
    c.Font.Color := clMaroon;
    c.TextOutFrac(40.5, 320.5, 'Fractional text');
    // a shape between two texts of one font: the text color is set again
    c.Brush.Color := clBlue;
    c.Ellipse(40, 350, 100, 380);
    c.TextOutFrac(120, 350, 'After the shape');
    // the tagging calls write nothing in an untagged document
    doc.BeginStructContent(psrP);
    c.TextOut(40, 400, 'Untagged');
    doc.EndStructContent;
    pdf := SaveDoc(doc);
  finally
    doc.Free;
  end;
  Check(PosEx('/StructTreeRoot', pdf) = 0, 'no structure tree');
  Check(PosEx('BDC', pdf) = 0, 'no marked content');
  CheckGolden('canvas_bridge_shapes', pdf);
end;

// two pages of different heights, at a DPI set before the first page
procedure TPdfGoldenTests.CanvasBridgePages;
var
  doc: TPdfDocumentVcl;
  c: TPdfVclCanvas;
  pdf: RawByteString;
begin
  doc := NewBridgeDoc;
  try
    // the bridge takes its scale at the first page: 144 px are 72 pt
    doc.ScreenLogPixels := 144;
    doc.AddPage;
    c := doc.VclCanvas;
    c.Font.Name := 'Helvetica';
    c.Font.Size := 12;
    c.TextOut(144, 144, 'Page one');
    c.Brush.Color := clYellow;
    c.Pen.Color := clRed;
    c.Pen.Width := 3;
    c.Rectangle(144, 288, 288, 432);
    doc.DefaultPageHeight := 600;
    doc.AddPage;
    // the same font and pen again: the new page sets them
    c.TextOut(144, 144, 'Page two');
    c.Rectangle(144, 288, 288, 432);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
  end;
  Check(PosEx(' 72 72 re', pdf) > 0, 'a 144 px square is 72 pt');
  CheckEqual(CountOccurrences(' Tf', pdf), 2, 'the font set on each page');
  CheckGolden('canvas_bridge_pages', pdf);
end;

// the tagging calls and the alpha setters of TPdfDocumentVcl
procedure TPdfGoldenTests.CanvasBridgeTagged;
var
  doc: TPdfDocumentVcl;
  c: TPdfVclCanvas;
  sans, serif, mono: string;
  para: integer;
  pdf: RawByteString;
begin
  doc := TPdfDocumentVcl.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.Tagged := true;
    doc.DefaultLanguage := 'en';
    doc.Info.Title := 'Golden bridge tagged';
    doc.ScreenLogPixels := 96;
    GetPdfFonts(doc.EmbeddedTTF, sans, serif, mono);
    doc.AddPage;
    c := doc.VclCanvas;
    c.Font.Name := sans;
    c.Font.Size := 16;
    doc.BeginStructContent(psrH1);
    c.TextOut(40, 40, 'Bridge tagged');
    doc.EndStructContent;
    // an inline paragraph: plain runs as regions, a styled one as a Span
    c.Font.Size := 11;
    doc.BeginStructGroup(psrP);
    doc.ContinueStructContent;
    c.TextOut(40, 80, 'Plain,');
    doc.SuspendStructContent;
    doc.BeginStructContent(psrSpan);
    c.TextOut(90, 80, 'styled,');
    doc.EndStructContent;
    doc.ContinueStructContent;
    c.TextOut(150, 80, 'plain again.');
    doc.EndStructContent;
    doc.BeginStructContent(psrFigure, 'A filled square');
    doc.SetFillAlpha(0.5);
    doc.SetStrokeAlpha(0.25);
    c.Brush.Color := clAqua;
    c.Rectangle(40, 120, 120, 200);
    doc.SetFillAlpha(1);
    doc.SetStrokeAlpha(1);
    doc.EndStructContent;
    // a paragraph continued on the next page as the same element
    doc.BeginStructContent(psrP);
    para := doc.LastStructContent;
    c.TextOut(40, 240, 'A paragraph that goes on');
    doc.EndStructContent;
    doc.BeginArtifact;
    c.Pen.Color := clGray;
    c.MoveTo(40, 1000);
    c.LineTo(500, 1000);
    doc.EndArtifact;
    doc.AddPage;
    c.Font.Name := sans;
    c.Font.Size := 11;
    doc.ResumeStructContent(para);
    c.TextOut(40, 40, 'on the second page.');
    doc.EndStructContent;
    pdf := SaveDoc(doc);
  finally
    doc.Free;
  end;
  Check(para >= 0, 'LastStructContent');
  CheckEqual(PdfStructRoles(pdf), 'Document 1'#10'Figure 1'#10'H1 1'#10 +
    'P 2'#10'Span 1'#10, 'the roles');
  Check(PosEx('/ca 0.5', pdf) > 0, 'fill alpha');
  Check(PosEx('/CA 0.25', pdf) > 0, 'stroke alpha');
  CheckGolden('canvas_bridge_tagged', pdf);
end;
{$endif PDF_HASVCLCANVAS}

end.
