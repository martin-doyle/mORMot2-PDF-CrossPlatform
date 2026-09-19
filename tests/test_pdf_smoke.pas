/// Smoke test für PDF-Export-Funktionalität (ohne LCL-Abhängigkeiten)
// - migrated to TSynTestCase framework for mORMot2 compatibility
unit test_pdf_smoke;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  mormot.core.base,
  Graphics,             // TCanvas.Font
  mormot.core.test,
  mormot.pdf.types,     // TPdfStructRole
  mormot.ui.pdf,        // TPdfCompressionMethod
  mormot.ui.pdfcanvas;  // TPdfDocumentVcl, TPdfVclCanvas

type
  /// PDF smoke test cases
  TPdfSmokeTests = class(TSynTestCase)
  published
    procedure TestPdfCreation;
    procedure TestPdfMetadata;
    procedure TestPdfMultiplePages;
    procedure TestPdfDifferentSizes;
    procedure TestVclCanvasTextMetrics;
    procedure TestTaggedAltTextIsPdfString;
    procedure TestTaggedImpliesEmbeddedFonts;
    procedure TestTaggedAfterAddPageRaises;
    procedure TestTaggedStreamedMetadata;
    procedure TestTaggedDecorationIsArtifact;
    procedure TestTaggedArtifactMisuseRaises;
    procedure TestLineToWritesCompletePath;
  end;

implementation

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

function CountMoveTo(const s: RawByteString): integer;
var
  p: integer;
begin
  result := 0;
  p := Pos(RawByteString(' m'#10), s);
  while p > 0 do
  begin
    inc(result);
    p := Pos(RawByteString(' m'#10), s, p + 1);
  end;
end;

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

procedure TPdfSmokeTests.TestTaggedStreamedMetadata;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Tagged := true;
      PDF.Info.Title := 'R&D <Plan>';
      { streamed page by page, as TGDIPages.ExportPdfStream does: the metadata
        stream only comes to exist on the first AddPage, after the Begin call
        which used to fill it - PAC: "PDF/UA identifier missing" (B-8) }
      PDF.SaveToStreamDirectBegin(Stream);
      PDF.AddPage;
      PDF.BeginStructContent(psrP);
      PDF.VclCanvas.TextOut(20, 20, 'Hello');
      PDF.EndStructContent;
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

procedure TPdfSmokeTests.TestTaggedDecorationIsArtifact;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
  fig, emc, art, bb, code: integer;
  left: double;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Tagged := true;
      PDF.AddPage;
      { a cell border drawn between two struct regions (B-9) }
      PDF.VclCanvas.Rectangle(10, 10, 100, 30);
      PDF.BeginStructContent(psrTable);
      PDF.BeginStructContent(psrTR);
      PDF.BeginStructContent(psrTH);
      PDF.VclCanvas.TextOut(12, 12, 'Date');
      PDF.EndStructContent;
      PDF.EndStructContent;
      PDF.EndStructContent;
      { a drawing inside a Figure is real content, not decoration }
      PDF.BeginStructContent(psrFigure, 'Chart');
      PDF.VclCanvas.Rectangle(10, 50, 100, 100);
      PDF.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(Pos(RawByteString('/Artifact BMC'), s) > 0,
      'a path outside any struct region is an artifact');
    fig := Pos(RawByteString('/Figure <<'), s);
    emc := Pos(RawByteString('EMC'), s, fig);
    art := Pos(RawByteString('/Artifact'), s, fig);
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
    Val(string(copy(s, bb + 6, Pos(RawByteString(' '), s, bb) - bb - 6)),
      left, code);
    Check((bb > 0) and (code = 0) and (abs(left - 7.125) < 0.01),
      'the /BBox starts at the left edge of the drawing minus half the pen');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedArtifactMisuseRaises;
var
  PDF: TPdfDocumentVcl;
  Raised: boolean;
begin
  PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
  try
    PDF.Tagged := true;
    PDF.AddPage;
    Raised := false;
    try
      PDF.EndArtifact;
    except
      on EPdfInvalidOperation do
        Raised := true;
    end;
    Check(Raised, 'EndArtifact without BeginArtifact');
    PDF.BeginStructContent(psrP);
    Raised := false;
    try
      PDF.BeginArtifact;
    except
      on EPdfInvalidOperation do
        Raised := true;
    end;
    Check(Raised, 'an artifact cannot open inside a struct region');
    PDF.EndStructContent;
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestTaggedImpliesEmbeddedFonts;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone; // so the objects stay readable
      { PDF/UA needs embedded fonts with a Unicode round-trip, so Tagged picks
        the font mode itself - the caller must not have to (ROADMAP Step 6) }
      PDF.Tagged := true;
      Check(PDF.EmbeddedTTF, 'Tagged turns embedding on');
      Check(not PDF.StandardFontsReplace, 'Tagged drops the base-14 Type1 mode');
      // a retain-GID subset keeps the round-trip (R-12): only without a
      // PdfFontSubsetter - i.e. on Windows - does Tagged force the whole face
      Check(PDF.EmbeddedWholeTtf = (PdfFontSubsetter = nil),
        'Tagged subsets only through PdfFontSubsetter');
      PDF.AddPage;
      PDF.BeginStructContent(psrP);
      PDF.VclCanvas.Font.Size := 12;
      PDF.VclCanvas.TextOut(20, 20, 'Hello');
      PDF.EndStructContent;
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
  PDF: TPdfDocumentVcl;
  Raised: boolean;
begin
  PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
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
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone; // so the content stream stays readable
      PDF.Tagged := true;
      PDF.DefaultLanguage := 'en';
      PDF.AddPage;
      PDF.BeginStructContent(psrFigure, ALT);
      PDF.VclCanvas.Rectangle(10, 10, 100, 100);
      PDF.EndStructContent;
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

procedure TPdfSmokeTests.TestPdfCreation;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  Size: Integer;
  Header: AnsiString;
begin
  Stream := TMemoryStream.Create;
  try
    // Create PDF with default options (no PDF/A)
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);  // Use Outlines=false, CodePage=0, pdfaNone
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
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
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
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  i: Integer;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
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
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
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

end.
