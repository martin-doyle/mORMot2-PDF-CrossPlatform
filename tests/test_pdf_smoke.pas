/// PDF smoke tests: document basics and tagged output
// - migrated to TSynTestCase framework for mORMot2 compatibility
// - drawn through TPdfDocument/TPdfCanvas (layer 1), so the suite runs on
// Delphi too (R-19); the two tests of the TCanvas bridge itself are FPC-only
// until the bridge exists on Delphi (R-20)
unit test_pdf_smoke;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif FPC}

interface

uses
  Classes,
  SysUtils,
  mormot.core.base,
  {$ifdef FPC}
  Graphics,             // TCanvas.Font
  mormot.ui.pdfcanvas,  // TPdfDocumentVcl, TPdfVclCanvas
  {$endif FPC}
  mormot.core.test,
  mormot.core.unicode,  // StringToUtf8
  mormot.pdf.types,     // TPdfStructRole, GetPdfFonts
  mormot.ui.pdf,        // TPdfDocument, TPdfCanvas
  test_pdf_subset;      // DrawUtf8Text

type
  /// PDF smoke test cases
  TPdfSmokeTests = class(TSynTestCase)
  published
    procedure TestPdfCreation;
    procedure TestPdfMetadata;
    procedure TestPdfMultiplePages;
    procedure TestPdfDifferentSizes;
    {$ifdef FPC}
    procedure TestVclCanvasTextMetrics;
    {$endif FPC}
    procedure TestTaggedAltTextIsPdfString;
    procedure TestTaggedImpliesEmbeddedFonts;
    procedure TestTaggedAfterAddPageRaises;
    procedure TestTaggedStreamedMetadata;
    procedure TestTaggedPdfA;
    procedure TestTaggedDecorationIsArtifact;
    procedure TestTaggedArtifactMisuseRaises;
    {$ifdef FPC}
    procedure TestLineToWritesCompletePath;
    {$endif FPC}
    procedure TestTaggedTableRowGroups;
  end;

implementation

const
  /// the TCanvas bridge maps 96 DPI pixels to PDF points
  PX = 72 / 96;
  /// default page height (A4) - PDF points count from the bottom
  PAGE_H = 842;

{ select the platform sans font, as the tagged font mode embeds it }
procedure UseSansFont(PDF: TPdfDocument; ASize: single = 12);
var
  sans, serif, mono: string;
begin
  GetPdfFonts(true, sans, serif, mono);
  PDF.Canvas.SetFont(StringToUtf8(sans), ASize, []);
end;

{ a stroked rectangle given in bridge pixels (Y from the top), with the
  0.75 pt pen of a 1 px TCanvas pen }
procedure StrokeRectPx(PDF: TPdfDocument; X1, Y1, X2, Y2: integer);
begin
  PDF.Canvas.SetLineWidth(PX);
  PDF.Canvas.Rectangle(X1 * PX, PAGE_H - Y2 * PX, (X2 - X1) * PX, (Y2 - Y1) * PX);
  PDF.Canvas.Stroke;
end;

function StreamToRaw(Stream: TMemoryStream): RawByteString;
begin
  SetLength(result, Stream.Size);
  Stream.Position := 0;
  Stream.Read(pointer(result)^, Stream.Size);
end;

// count the ISO 32000-1 8.2 violations in an uncompressed PDF without text:
// a graphics state operator inside a path object, or an 'l' without a
// current point (ROADMAP B-12)
function PathOrderViolations(const s: RawByteString): integer;
const
  CONSTRUCT: array[0..6] of RawByteString = ('m', 're', 'l', 'c', 'v', 'y', 'h');
  PAINT: array[0..10] of RawByteString = ('S', 's', 'f', 'F', 'f*', 'B', 'B*',
    'b', 'b*', 'n', 'W n');
  STATE: array[0..12] of RawByteString = ('RG', 'rg', 'G', 'g', 'K', 'k', 'w',
    'J', 'j', 'M', 'd', 'gs', 'CS');
var
  lines: TStringList;
  i, sp: integer;
  line, op: RawByteString;
  inPath: boolean;

  function IsOp(const ops: array of RawByteString): boolean;
  var
    k: integer;
  begin
    result := true;
    for k := 0 to high(ops) do
      if op = ops[k] then
        exit;
    result := false;
  end;

begin
  result := 0;
  inPath := false;
  lines := TStringList.Create;
  try
    lines.Text := string(s);
    for i := 0 to lines.Count - 1 do
    begin
      line := RawByteString(Trim(lines[i]));
      sp := length(line);
      while (sp > 0) and (line[sp] <> ' ') do
        dec(sp);
      op := copy(line, sp + 1, maxInt);
      if IsOp(CONSTRUCT) then
      begin
        if (op = 'l') and not inPath then
          inc(result); // no current point: the previous path was painted
        if op <> 'h' then
          inPath := true;
      end
      else if IsOp(PAINT) then
        inPath := false
      else if inPath and IsOp(STATE) then
        inc(result);
    end;
  finally
    lines.Free;
  end;
end;

function CountOf(const Sub, s: RawByteString): integer;
var
  p: integer;
begin
  result := 0;
  p := Pos(Sub, s);
  while p > 0 do
  begin
    inc(result);
    p := PosEx(Sub, s, p + 1);
  end;
end;

function CountMoveTo(const s: RawByteString): integer;
var
  p: integer;
begin
  result := 0;
  p := Pos(RawByteString(' m'#10), s);
  while p > 0 do
  begin
    inc(result);
    p := PosEx(RawByteString(' m'#10), s, p + 1);
  end;
end;

{$ifdef FPC} // SyncPen of the TCanvas bridge (R-20)
procedure TPdfSmokeTests.TestLineToWritesCompletePath;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
  tagged: boolean;
begin
  for tagged := false to true do
  begin
    Stream := TMemoryStream.Create;
    try
      PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
      try
        PDF.CompressionMethod := cmNone;
        PDF.Tagged := tagged;
        PDF.AddPage;
        { the pdf_demo pattern: pen set, then MoveTo + LineTo - SyncPen used
          to write RG/w between the m and the l (PAC: "Operator 'RG' not
          allowed in this current state") }
        PDF.VclCanvas.Pen.Color := clNavy;
        PDF.VclCanvas.Pen.Width := 2;
        PDF.VclCanvas.MoveTo(10, 10);
        PDF.VclCanvas.LineTo(200, 10);
        { a connected line whose pen changes half way: each segment needs
          its own m, the old code wrote a bare l after the first S }
        PDF.VclCanvas.MoveTo(10, 50);
        PDF.VclCanvas.LineTo(200, 50);
        PDF.VclCanvas.Pen.Width := 4;
        PDF.VclCanvas.LineTo(200, 150);
        { with psClear nothing is drawn, and no path is left open }
        PDF.VclCanvas.Pen.Style := psClear;
        PDF.VclCanvas.MoveTo(10, 200);
        PDF.VclCanvas.LineTo(200, 200);
        PDF.SaveToStream(Stream);
      finally
        PDF.Free;
      end;
      s := StreamToRaw(Stream);
      CheckEqual(0, PathOrderViolations(s),
        'no state operator inside a path, no l without a current point');
      CheckEqual(3, CountMoveTo(s),
        'one m per drawn segment, none for the psClear line');
    finally
      Stream.Free;
    end;
  end;
end;
{$endif FPC}

procedure TPdfSmokeTests.TestTaggedStreamedMetadata;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Tagged := true;
      PDF.Info.Title := 'R&D <Plan>';
      { streamed page by page, as TGDIPages.ExportPdfStream does: the metadata
        stream only comes to exist on the first AddPage, after the Begin call
        which used to fill it - PAC: "PDF/UA identifier missing" (B-8) }
      PDF.SaveToStreamDirectBegin(Stream);
      PDF.AddPage;
      PDF.Canvas.BeginStructContent(psrP);
      UseSansFont(PDF);
      DrawUtf8Text(PDF, 20 * PX, PAGE_H - 20 * PX, 'Hello');
      PDF.Canvas.EndStructContent;
      PDF.SaveToStreamDirectPageFlush;
      PDF.SaveToStreamDirectEnd;
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(Pos(RawByteString('<pdfuaid:part>1</pdfuaid:part>'), s) > 0,
      'XMP carries the PDF/UA identifier');
    Check(Pos(RawByteString('<rdf:li xml:lang="x-default">R&amp;D &lt;Plan&gt;</rdf:li>'), s) > 0,
      'XMP carries the title as escaped dc:title (B-10)');
    Check(Pos(RawByteString('/DisplayDocTitle true'), s) > 0,
      'viewer shows the title, not the file name (B-7)');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedPdfA;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    { PDF/A used to set up its own direct StructTreeRoot and MarkInfo in
      NewDoc: the Tagged setup then skipped /Lang and DisplayDocTitle, and
      SerializeStructTree referenced the direct object from a second
      dictionary, so Free released it twice (R-17) }
    PDF := TPdfDocument.Create(false, 0, pdfa3B);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Tagged := true;
      PDF.DefaultLanguage := 'en';
      PDF.Info.Title := 'Tagged PDF/A';
      PDF.AddPage;
      PDF.Canvas.BeginStructContent(psrP);
      UseSansFont(PDF);
      DrawUtf8Text(PDF, 20 * PX, PAGE_H - 20 * PX, 'Hello');
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    CheckEqual(CountOf('/MarkInfo', s), 1, 'one MarkInfo in the catalog');
    CheckEqual(CountOf('/Type/StructTreeRoot', s) +
      CountOf('/Type /StructTreeRoot', s), 1, 'one StructTreeRoot');
    Check(Pos(RawByteString('/Lang'), s) > 0,
      'catalog carries the document language (PDF/UA-1 7.2)');
    Check(Pos(RawByteString('/DisplayDocTitle true'), s) > 0,
      'viewer shows the title (PDF/UA-1 7.1)');
    Check(Pos(RawByteString('<pdfaid:part>3</pdfaid:part>'), s) > 0,
      'XMP carries the PDF/A identifier');
    Check(Pos(RawByteString('<pdfuaid:part>1</pdfuaid:part>'), s) > 0,
      'XMP carries the PDF/UA identifier');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedDecorationIsArtifact;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
  fig, emc, art, bb, code: integer;
  left: double;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Tagged := true;
      PDF.AddPage;
      { a cell border drawn between two struct regions (B-9) }
      StrokeRectPx(PDF, 10, 10, 100, 30);
      PDF.Canvas.BeginStructContent(psrTable);
      PDF.Canvas.BeginStructContent(psrTR);
      PDF.Canvas.BeginStructContent(psrTH);
      UseSansFont(PDF);
      DrawUtf8Text(PDF, 12 * PX, PAGE_H - 12 * PX, 'Date');
      PDF.Canvas.EndStructContent;
      PDF.Canvas.EndStructContent;
      PDF.Canvas.EndStructContent;
      { a drawing inside a Figure is real content, not decoration }
      PDF.Canvas.BeginStructContent(psrFigure, 'Chart');
      StrokeRectPx(PDF, 10, 50, 100, 100);
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(Pos(RawByteString('/Artifact BMC'), s) > 0,
      'a path outside any struct region is an artifact');
    fig := Pos(RawByteString('/Figure <<'), s);
    emc := PosEx(RawByteString('EMC'), s, fig);
    art := PosEx(RawByteString('/Artifact'), s, fig);
    Check((fig > 0) and (emc > fig) and
      ((art = 0) or (art > emc)),
      'a path inside a Figure region stays real content');
    Check(Pos(RawByteString('/A <</O/Table/Scope/Column>>'), s) > 0,
      'a TH names the column it heads (B-11)');
    { Rectangle(10, 50, 100, 100) px = 7.5..75 pt wide, widened by half the
      0.75 pt pen: PAC wants the bounding box of a one-page Figure (B-13) }
    Check(Pos(RawByteString('/O/Layout/BBox['), s) > 0,
      'the Figure carries its /BBox layout attribute');
    bb := Pos(RawByteString('/BBox['), s);
    Val(string(copy(s, bb + 6, PosEx(RawByteString(' '), s, bb) - bb - 6)),
      left, code);
    Check((bb > 0) and (code = 0) and (abs(left - 7.125) < 0.01),
      'the /BBox starts at the left edge of the drawing minus half the pen');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedArtifactMisuseRaises;
var
  PDF: TPdfDocument;
  Raised: boolean;
begin
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.Tagged := true;
    PDF.AddPage;
    Raised := false;
    try
      PDF.Canvas.EndArtifact;
    except
      on EPdfInvalidOperation do
        Raised := true;
    end;
    Check(Raised, 'EndArtifact without BeginArtifact');
    PDF.Canvas.BeginStructContent(psrP);
    Raised := false;
    try
      PDF.Canvas.BeginArtifact;
    except
      on EPdfInvalidOperation do
        Raised := true;
    end;
    Check(Raised, 'an artifact cannot open inside a struct region');
    PDF.Canvas.EndStructContent;
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedImpliesEmbeddedFonts;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone; // so the objects stay readable
      { PDF/UA needs embedded fonts with a Unicode round-trip, so Tagged picks
        the font mode itself - the caller must not have to (ROADMAP P-6) }
      PDF.Tagged := true;
      Check(PDF.EmbeddedTTF, 'Tagged turns embedding on');
      Check(not PDF.StandardFontsReplace, 'Tagged drops the base-14 Type1 mode');
      // a retain-GID subset keeps the round-trip, so Tagged may subset:
      // through PdfFontSubsetter on POSIX (R-12), through CreateFontPackage
      // with a glyph keep list on Windows (R-15) - only a platform offering
      // neither falls back to the whole face
      Check(PDF.EmbeddedWholeTtf = not PdfCanSubsetRetainingGids,
        'Tagged embeds the whole face only without a retain-GID subsetter');
      PDF.AddPage;
      PDF.Canvas.BeginStructContent(psrP);
      UseSansFont(PDF, 12);
      DrawUtf8Text(PDF, 20 * PX, PAGE_H - 20 * PX, 'Hello');
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(s, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(s)^, Stream.Size);
    Check(Pos(RawByteString('/FontFile2'), s) > 0,
      'the face is embedded (pdffonts: emb=yes)');
    { the Latin text above runs through the WinAnsi instance, whose ToUnicode
      CMap used to be written for PDF/A only - without it pdffonts says uni=no }
    Check(Pos(RawByteString('/ToUnicode'), s) > 0,
      'WinAnsi ToUnicode CMap (pdffonts: uni=yes)');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedAfterAddPageRaises;
var
  PDF: TPdfDocument;
  Raised: boolean;
begin
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.AddPage;
    Raised := false;
    try
      { too late: the page was measured with the other font mode }
      PDF.Tagged := true;
    except
      on E: Exception do
        Raised := true;
    end;
    Check(Raised, 'Tagged after AddPage is refused');
    Check(not PDF.Tagged, 'and leaves the document untagged');
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedAltTextIsPdfString;
const
  // the characters a PDF string literal has to escape
  ALT = 'Chart (2026): 50% \ up';
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone; // so the content stream stays readable
      PDF.Tagged := true;
      PDF.DefaultLanguage := 'en';
      PDF.AddPage;
      PDF.Canvas.BeginStructContent(psrFigure, ALT);
      StrokeRectPx(PDF, 10, 10, 100, 100);
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(s, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(s)^, Stream.Size);
    { /Alt holds a PDF string: without its parenthesis and escaping the
      marked-content dictionary does not parse - PAC stops with "unexpected
      token", Acrobat reports a damaged page (ROADMAP B-6) }
    Check(Pos(RawByteString('/Alt (Chart \(2026\): 50% \\ up)'), s) > 0,
      'escaped /Alt string in the content stream');
    Check(Pos(RawByteString('/Alt ' + ALT), s) = 0, 'no bare /Alt text');
  finally
    Stream.Free;
  end;
end;

{$ifdef FPC} // measuring through TPdfVclCanvas (R-20)
procedure TPdfSmokeTests.TestVclCanvasTextMetrics;
const
  // Adobe AFM advance widths of Helvetica, in 1000-per-em units
  W_HELLO = 722 + 556 + 222 + 222 + 556; // 'Hello'
  W_L     = 222;                         // 'l'
var
  PDF: TPdfDocumentVcl;
  C: TPdfVclCanvas;
  w10, w20, wl, h10, h20: single;
begin
  PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
  try
    PDF.EmbeddedTTF := false;
    PDF.StandardFontsReplace := true;
    PDF.AddPage;
    C := PDF.VclCanvas as TPdfVclCanvas;
    C.Font.Name  := 'Helvetica';
    C.Font.Style := [];
    C.Font.Size  := 10;
    w10 := C.TextWidthFrac('Hello');
    wl  := C.TextWidthFrac('l');
    h10 := C.TextHeightFrac('Hello');
    { widths are exact, not quantised to whole screen pixels }
    CheckSame(C.TextWidthFrac('HelloHello'), 2 * w10, 1e-3, 'fractional width');
    { the integer TCanvas API now rounds that exact value }
    Check(C.TextWidth('Hello') = round(w10), 'integer TextWidth');
    Check(C.TextHeight('Hello') = round(h10), 'integer TextHeight');
    C.Font.Size := 20;
    w20 := C.TextWidthFrac('Hello');
    h20 := C.TextHeightFrac('Hello');
    { the text is measured with the base-14 AFM tables the PDF viewer will draw
      with, not with the widgetset's own resolution of 'Helvetica' (ROADMAP
      B-4) - the ratio cancels the pixels-per-point factor, so it holds on any
      screen DPI and on every platform }
    CheckSame(w10 / wl, W_HELLO / W_L, 1e-3, 'AFM width ratio');
    CheckSame(w20, 2 * w10, 1e-3, 'width scales with the font size');
    CheckSame(h20, 2 * h10, 1e-3, 'height scales with the font size');
  finally
    PDF.Free;
  end;
end;
{$endif FPC}

procedure TPdfSmokeTests.TestPdfCreation;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  Size: Integer;
  Header: AnsiString;
begin
  Stream := TMemoryStream.Create;
  try
    // Create PDF with default options (no PDF/A)
    PDF := TPdfDocument.Create(false, 0, pdfaNone);  // Use Outlines=false, CodePage=0, pdfaNone
    try
      // Set metadata
      PDF.Info.Title := 'Test Document';
      PDF.Info.Author := 'mORMot2 Test Suite';
      PDF.Info.Subject := 'PDF Export Smoke Test';
      PDF.Info.Creator := 'mormot.ui.pdfcanvas';

      // Create empty PDF (minimum valid structure)
      PDF.DefaultPageWidth  := 595;   // A4 width in points (210 mm)
      PDF.DefaultPageHeight := 842;   // A4 height in points (297 mm)
      PDF.AddPage;

      // Export to stream
      PDF.SaveToStream(Stream);

      // Verify stream has content
      Size := Stream.Size;
      Check(Size > 100, Format('PDF size too small: %d bytes (expected > 100)', [Size]));

      // Verify PDF header
      Stream.Position := 0;
      SetLength(Header, 4);
      Stream.Read(pointer(Header)^, 4);
      Check(copy(string(Header), 1, 1) = '%', 'Invalid PDF header (should start with %)');
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestPdfMetadata;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      // Verify we can set metadata without errors
      PDF.Info.Title := 'Metadata Test';
      PDF.Info.Author := 'Test Author';
      PDF.Info.Subject := 'Test Subject';
      PDF.Info.Keywords := 'test, pdf, export';
      PDF.Info.Creator := 'mORMot2';
      PDF.DefaultPageWidth  := 595;
      PDF.DefaultPageHeight := 842;
      PDF.AddPage;
      PDF.SaveToStream(Stream);
      Check(Stream.Size > 100, 'PDF with metadata too small');
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestPdfMultiplePages;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  i: Integer;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.Info.Title := 'Multi-Page Test';
      PDF.DefaultPageWidth  := 595;
      PDF.DefaultPageHeight := 842;
      // Create multiple pages
      for i := 1 to 5 do
        PDF.AddPage;
      PDF.SaveToStream(Stream);
      Check(Stream.Size > 500, Format('Multi-page PDF too small: %d bytes', [Stream.Size]));
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestPdfDifferentSizes;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.Info.Title := 'Different Sizes';
      // A4: 210mm × 297mm = 595 × 842 points
      PDF.DefaultPageWidth  := 595;
      PDF.DefaultPageHeight := 842;
      PDF.AddPage;
      // US Letter: 216mm × 279mm = 612 × 792 points
      PDF.DefaultPageWidth  := 612;
      PDF.DefaultPageHeight := 792;
      PDF.AddPage;
      // A3: 297mm × 420mm = 842 × 1191 points
      PDF.DefaultPageWidth  := 842;
      PDF.DefaultPageHeight := 1191;
      PDF.AddPage;
      PDF.SaveToStream(Stream);
      Check(Stream.Size > 300, 'Variable-size PDF too small');
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;


{ read the integer starting at Pdf[p], advancing p past it }
function ReadInt(const Pdf: RawByteString; var p: PtrInt): integer;
begin
  result := 0;
  while (p <= length(Pdf)) and
        (Pdf[p] = ' ') do
    inc(p);
  while (p <= length(Pdf)) and
        (Pdf[p] in ['0'..'9']) do
  begin
    result := result * 10 + ord(Pdf[p]) - 48;
    inc(p);
  end;
end;

{ text of object number ANum in an uncompressed PDF, '' if absent
  - pdf15+ keeps most dictionaries in an /ObjStm object stream, where the
    objects are concatenated behind an index of (number, offset) pairs
    instead of carrying their own "N 0 obj" header }
function ObjectText(const Pdf: RawByteString; ANum: integer): RawByteString;
var
  p, e, q, data, first, n, i, num, ofs, nextofs: PtrInt;
begin
  result := '';
  p := Pos(RawByteString(IntToStr(ANum) + ' 0 obj'), Pdf);
  if p > 0 then
  begin
    e := PosEx(RawByteString('endobj'), Pdf, p);
    if e > p then
      result := copy(Pdf, p, e - p);
    exit;
  end;
  q := Pos(RawByteString('/Type/ObjStm'), Pdf);
  while q > 0 do
  begin
    p := PosEx(RawByteString('/N '), Pdf, q) + 3;
    n := ReadInt(Pdf, p);
    p := PosEx(RawByteString('/First '), Pdf, q) + 7;
    first := ReadInt(Pdf, p);
    data := PosEx(RawByteString('stream'), Pdf, q) + 7; // 'stream' + #10
    p := data;
    for i := 1 to n do
    begin
      num := ReadInt(Pdf, p);
      ofs := ReadInt(Pdf, p);
      if num <> ANum then
        continue;
      if i < n then
      begin
        e := p;
        ReadInt(Pdf, e);          // number of the next object
        nextofs := ReadInt(Pdf, e);
      end
      else
        nextofs := PosEx(RawByteString('endstream'), Pdf, data) - 1 -
                   (data + first);
      result := copy(Pdf, data + first + ofs, nextofs - ofs);
      exit;
    end;
    q := PosEx(RawByteString('/Type/ObjStm'), Pdf, q + 12);
  end;
end;

{ text of the object whose /S role is ARole, '' if absent }
function ObjectTextOfRole(const Pdf, ARole: RawByteString): RawByteString;
var
  p, n, b, last, e: PtrInt;
begin
  result := '';
  p := Pos(RawByteString('/S/') + ARole, Pdf);
  if p = 0 then
    exit;
  { inside an object stream there is no object header to walk back to: the
    element ends at the next '>>' that closes its dictionary }
  e := PosEx(RawByteString('endobj'), Pdf, p);
  n := PosEx(RawByteString('>>'), Pdf, p);
  if (n > 0) and
     ((e = 0) or (n < e)) then
  begin
    b := p;
    while (b > 1) and
          (Pdf[b] <> '<') do
      dec(b);
    result := copy(Pdf, b, n + 2 - b);
    exit;
  end;
  last := 0;
  b := 1;
  repeat // the object header closest before the role name
    n := PosEx(RawByteString(' 0 obj'), Pdf, b);
    if (n = 0) or
       (n > p) then
      break;
    last := n;
    b := n + 6;
  until false;
  if last = 0 then
    exit;
  while (last > 1) and
        (Pdf[last - 1] in ['0'..'9']) do
    dec(last); // back to the start of the object number
  e := PosEx(RawByteString('endobj'), Pdf, p);
  if e > last then
    result := copy(Pdf, last, e - last);
end;

{ the /S role names of the objects listed in the /K array of AObj, in order }
function KidRoles(const Pdf, AObj: RawByteString): RawUtf8;
var
  p, n: PtrInt;
  kids, kid: RawByteString;
begin
  result := '';
  p := Pos(RawByteString('/K['), AObj);
  if p = 0 then
    exit;
  kids := copy(AObj, p + 3, PosEx(RawByteString(']'), AObj, p) - p - 3);
  p := 1;
  while p <= length(kids) do
    if kids[p] in ['0'..'9'] then
    begin
      n := 0;
      while (p <= length(kids)) and
            (kids[p] in ['0'..'9']) do
      begin
        n := n * 10 + ord(kids[p]) - 48;
        inc(p);
      end;
      kid := ObjectText(Pdf, n);
      p := PosEx(RawByteString('R'), kids, p) + 1; // skip the generation + R
      if Pos(RawByteString('/S/'), kid) > 0 then
      begin
        kid := copy(kid, Pos(RawByteString('/S/'), kid) + 3, 20);
        n := 1;
        while (n <= length(kid)) and
              (kid[n] in ['A'..'Z', 'a'..'z', '0'..'9']) do
          inc(n);
        result := result + copy(kid, 1, n - 1) + ' ';
      end;
    end
    else
      inc(p);
end;

procedure TPdfSmokeTests.TestTaggedTableRowGroups;

  procedure Cell(PDF: TPdfDocument; ARole: TPdfStructRole;
    Y: integer; const S: string);
  begin
    PDF.Canvas.BeginStructContent(psrTR);
    PDF.Canvas.BeginStructContent(ARole);
    DrawUtf8Text(PDF, 20 * PX, PAGE_H - Y * PX, S);
    PDF.Canvas.EndStructContent;
    PDF.Canvas.EndStructContent;
  end;

var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
  tbl: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone; // so the struct tree stays readable
      PDF.Tagged := true;
      PDF.AddPage;
      UseSansFont(PDF, 12);
      { Table > THead|TBody|TFoot > TR > TH|TD, ISO 32000-1 14.8.4.3.4 }
      PDF.Canvas.BeginStructContent(psrTable);
      PDF.Canvas.BeginStructContent(psrTHead);
      Cell(PDF, psrTH, 20, 'Item');
      PDF.Canvas.EndStructContent;
      PDF.Canvas.BeginStructContent(psrTBody);
      Cell(PDF, psrTD, 40, 'Row 1');
      Cell(PDF, psrTD, 60, 'Row 2');
      PDF.Canvas.EndStructContent;
      PDF.Canvas.BeginStructContent(psrTFoot);
      Cell(PDF, psrTD, 80, 'Total');
      PDF.Canvas.EndStructContent;
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(s, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(s)^, Stream.Size);
    Check(Pos(RawByteString('/S/THead'), s) > 0, 'THead written');
    Check(Pos(RawByteString('/S/TBody'), s) > 0, 'TBody written');
    Check(Pos(RawByteString('/S/TFoot'), s) > 0, 'TFoot written');
    { the three groups are the kids of Table, in reading order - a row group
      is a container, so it must own no marked-content region of its own }
    tbl := ObjectTextOfRole(s, 'Table');
    Check(tbl <> '', 'the Table element is in the struct tree');
    CheckEqual(KidRoles(s, tbl), 'THead TBody TFoot ', 'row groups of the table');
  finally
    Stream.Free;
  end;
end;

end.
