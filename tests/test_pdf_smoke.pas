/// PDF smoke tests: document basics and tagged output
// - migrated to TSynTestCase framework for mORMot2 compatibility
// - drawn through TPdfDocument/TPdfCanvas (layer 1), so the suite runs on
// Delphi too (R-19); the tests of the TCanvas bridge itself need
// PDF_HASVCLCANVAS (test_defines.inc), set for every compiler since R-20
unit test_pdf_smoke;

interface

{$I mormot.defines.inc}
{$I test_defines.inc}

uses
  Classes,
  SysUtils,
  mormot.core.base,
  {$ifdef PDF_HASVCLCANVAS}
  {$ifdef OSWINDOWS}
  mormot.lib.uniscribe, // GdiScreenLogPixels
  {$endif OSWINDOWS}
  Types,                // TSize
  Graphics,             // TCanvas.Font
  mormot.pdf.canvas,    // TPdfDocumentVcl, TPdfVclCanvas
  {$endif PDF_HASVCLCANVAS}
  mormot.core.os,       // FileFromString
  mormot.core.test,
  mormot.core.unicode,  // StringToUtf8
  mormot.lib.core,      // FontShaper
  mormot.pdf,        // TPdfDocument, TPdfCanvas
  test_pdf_cff,         // SwapInFakeFace
  test_pdf_crossplatform, // the test fonts
  test_pdf_subset;      // DrawUtf8Text

type
  /// PDF smoke test cases
  TPdfSmokeTests = class(TSynTestCase)
  published
    procedure TestPdfCreation;
    procedure TestPdfMetadata;
    procedure TestPdfMultiplePages;
    procedure TestPdfDifferentSizes;
    {$ifdef PDF_HASVCLCANVAS}
    procedure TestVclCanvasTextMetrics;
    procedure TestVclCanvasUtf8Text;
    procedure TestVclCanvasUnknownFace;
    procedure TestVclCanvasThroughTCanvas;
    procedure TestVclCanvasScreenLogPixels;
    /// a line after text on a new page writes the pen width
    procedure TestVclCanvasPenAfterText;
    {$ifndef NO_USE_PDFSECURITY}
    procedure TestVclCanvasEncryption;
    {$endif NO_USE_PDFSECURITY}
    {$endif PDF_HASVCLCANVAS}
    procedure TestTaggedAltTextIsPdfString;
    procedure TestTaggedImpliesEmbeddedFonts;
    procedure TestTaggedAfterAddPageRaises;
    procedure TestTaggedStreamedMetadata;
    procedure TestTaggedPdfA;
    procedure TestTaggedDecorationIsArtifact;
    procedure TestTaggedArtifactMisuseRaises;
    {$ifdef PDF_HASVCLCANVAS}
    procedure TestLineToWritesCompletePath;
    {$endif PDF_HASVCLCANVAS}
    procedure TestTaggedTableRowGroups;
    procedure TestTaggedUnicode;
    procedure TestShapingSwitch;
    procedure TestShapedAfterFallback;
    procedure TestPlainFallback;
    /// fallback text in a form XObject drawn before the first page
    procedure TestFormFallback;
    /// a face whose only cmap is (0,3) draws its WinAnsi text as glyphs
    procedure TestUnicodeOnlyCmap;
    /// a face whose only cmap is (3,10) format 12 is read, and drawn by glyph
    procedure TestFormat12Cmap;
    procedure TestShapedFallback;
    procedure TestShapedRunOutcomeUnset;
    procedure TestZeroRealIsWritten;
    /// a backspace in a string is written as \b, the escape PDF defines
    procedure TestEscapeBackspace;
    {$ifndef NO_USE_PDFSECURITY}
    /// an encrypted text string holds its BOM and UTF-16BE, all encrypted
    procedure TestEncryptedUnicodeString;
    /// AddUnicodeHex writes the hex of a content stream: never encrypted
    procedure TestUnicodeHexNotEncrypted;
    {$endif NO_USE_PDFSECURITY}
    /// a WinAnsi ToUnicode CMap holds at most 100 entries per bfchar block
    procedure TestWinAnsiToUnicodeBlocks;
    /// an outline entry refused before the first page leaves the document sound
    procedure TestOutlineBeforePage;
    /// AddTrueTypeFont keeps the fallback font it sorts past
    procedure TestAddFontKeepsFallback;
    /// AddTrueTypeFont keeps the fonts created before it usable
    procedure TestAddFontKeepsCreatedFonts;
    /// AddTrueTypeFont keeps the face a raster font was resolved to
    procedure TestAddFontKeepsRasterFont;
    /// a raster font asked for as fixed-width is resolved as such
    procedure TestRasterFontFixedWidth;
    /// a raster font follows a change of the fallback font
    procedure TestRasterFontFollowsFallback;
    /// a face without an English PostScript name keeps its family name
    procedure TestPostScriptNameFallback;
    /// switching PDF/A off renews the document, its metadata stream included
    procedure TestNewDocDropsMetadata;
    {$ifndef NO_USE_PDFSECURITY}
    /// an encrypted document renewed by NewDoc saves with its /Encrypt
    procedure TestNewDocKeepsEncryption;
    /// a document renewed by NewDoc encrypts with its own RC4 object keys
    procedure TestNewDocRenewsObjectKeys;
    {$endif NO_USE_PDFSECURITY}
    /// NewDoc ends a direct save left open
    procedure TestNewDocEndsDirectSave;
    /// NewDoc closes an artifact left open on the freed page
    procedure TestNewDocClosesArtifact;
    /// the catalog getters read what the setters wrote
    procedure TestCatalogGetters;
    /// a JPEG's colour space follows its components; a non-JPEG is refused
    procedure TestJpegColorSpace;
    /// a glyph that advances by 0 measures 0
    procedure TestZeroAdvanceMeasured;
  private
    procedure CheckNoSimpleCmap(const aFamily, aCmap: RawUtf8);
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
  PDF.Canvas.SetFont(StringToUtf8(sans), ASize, [], PDF_DEFAULT_CHARSET);
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
      line := RawByteString(SysUtils.Trim(lines[i]));
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
    p := PosEx(RawByteString(' m'#10), s, p + 1);
  end;
end;

{$ifdef PDF_HASVCLCANVAS}
// a face no backend resolves: the bridge measures through its own DC - a
// provider without the face, as a name alone may be substituted
procedure TPdfSmokeTests.TestVclCanvasUnknownFace;
var
  PDF: TPdfDocumentVcl;
  previous: IFontProvider;
  e: TSize;
begin
  previous := SwapInFakeFace(nil);
  PDF := nil;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    PDF.EmbeddedTTF := true;
    PDF.AddPage;
    PDF.VclCanvas.Font.Name := FAKE_FACE;
    PDF.VclCanvas.Font.Size := 12;
    e := PDF.VclCanvas.TextExtent('Hello');
    Check(e.cx > 0, 'a width');
    Check(e.cy > 0, 'a height');
    CheckEqual(PDF.VclCanvas.TextWidth('Hello'), e.cx, 'TextWidth');
    CheckEqual(PDF.VclCanvas.TextHeight('Hello'), e.cy, 'TextHeight');
  finally
    PDF.Free;
    FontProvider := previous;
  end;
end;

// the bridge stands for the screen: its resolution on Windows, 96 elsewhere
procedure TPdfSmokeTests.TestVclCanvasScreenLogPixels;
var
  PDF: TPdfDocumentVcl;
begin
  PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
  try
    {$ifdef OSWINDOWS}
    CheckEqual(PDF.ScreenLogPixels, GdiScreenLogPixels, 'the screen');
    {$else}
    CheckEqual(PDF.ScreenLogPixels, 96, '96');
    {$endif OSWINDOWS}
  finally
    PDF.Free;
  end;
end;

// FPC's TCanvas has virtual drawing methods, which the bridge overrides;
// Delphi's are static or reintroduced: a TCanvas reference writes nothing
procedure TPdfSmokeTests.TestVclCanvasThroughTCanvas;
var
  PDF: TPdfDocumentVcl;
  c: TCanvas;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.StandardFontsReplace := true;
      PDF.AddPage;
      c := PDF.VclCanvas;
      PDF.VclCanvas.Font.Name := 'Helvetica';
      c.TextOut(40, 40, 'Through TCanvas');
      c.Rectangle(40, 80, 140, 120);
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    {$ifdef FPC}
    Check(PosEx('(Through TCanvas) Tj', s) > 0, 'the text');
    CheckEqual(CountOccurrences(' re'#10, s), 1, 'the rectangle');
    {$else}
    Check(PosEx('Through TCanvas', s) = 0, 'no text: the measuring DC got it');
    CheckEqual(CountOccurrences(' re'#10, s), 0, 'no rectangle');
    {$endif FPC}
  finally
    Stream.Free;
  end;
end;
{$endif PDF_HASVCLCANVAS}

{$ifdef PDF_HASVCLCANVAS}
{$ifndef NO_USE_PDFSECURITY}
// TPdfDocumentVcl.Create has the AEncryption of TPdfDocument.Create: the bridge
// sees USE_PDFSECURITY through mormot.pdf.defines.inc
procedure TPdfSmokeTests.TestVclCanvasEncryption;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone,
      TPdfEncryption.New(elRC4_128, '', 'owner', PDF_PERMISSION_ALL));
    try
      PDF.CompressionMethod := cmNone;
      PDF.StandardFontsReplace := true;
      PDF.AddPage;
      PDF.VclCanvas.Font.Name := 'Helvetica';
      PDF.VclCanvas.TextOut(40, 40, 'Plain words');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(PosEx('/Encrypt', s) > 0, 'an /Encrypt dictionary');
    Check(PosEx('Plain words', s) = 0, 'the text is encrypted');
  finally
    Stream.Free;
  end;
end;
{$endif NO_USE_PDFSECURITY}
{$endif PDF_HASVCLCANVAS}

{$ifdef PDF_HASVCLCANVAS} // SyncPen of the TCanvas bridge (R-20)
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
{$endif PDF_HASVCLCANVAS}

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
    CheckEqual(CountOccurrences('/MarkInfo', s), 1, 'one MarkInfo in the catalog');
    CheckEqual(CountOccurrences('/Type/StructTreeRoot', s) +
      CountOccurrences('/Type /StructTreeRoot', s), 1, 'one StructTreeRoot');
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
      // through FontSubsetter on POSIX (R-12), through CreateFontPackage
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

{$ifdef PDF_HASVCLCANVAS} // measuring through TPdfVclCanvas (R-20)
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

procedure TPdfSmokeTests.TestVclCanvasUtf8Text;
const
  // 'Größe' as UTF-8 bytes, and its Helvetica AFM advance widths
  GROESSE: RawUtf8 = {$ifdef HASCODEPAGE}
    'Gr'#$00F6#$00DF'e' {$else}
    'Gr'#$C3#$B6#$C3#$9F'e' {$endif};
  W_GROESSE = 778 + 333 + 556 + 611 + 556;
  W_L       = 222; // 'l'
var
  s: string;
  sTextOut, sUtf8: RawByteString;

  function NewCanvas(PDF: TPdfDocumentVcl): TPdfVclCanvas;
  begin
    PDF.CompressionMethod := cmNone;
    PDF.EmbeddedTTF := false;
    PDF.StandardFontsReplace := true;
    PDF.AddPage;
    result := PDF.VclCanvas as TPdfVclCanvas;
    result.Font.Name := 'Helvetica';
    result.Font.Size := 10;
  end;

  // the text object of the page, from BT to ET
  function DrawnText(Utf8: boolean): RawByteString;
  var
    PDF: TPdfDocumentVcl;
    Stream: TMemoryStream;
    i, j: integer;
  begin
    Stream := TMemoryStream.Create;
    try
      PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
      try
        if Utf8 then
          NewCanvas(PDF).TextOutUtf8(10, 10, GROESSE)
        else
          NewCanvas(PDF).TextOutFrac(10, 10, s);
        PDF.SaveToStream(Stream);
      finally
        PDF.Free;
      end;
      result := StreamToRaw(Stream);
    finally
      Stream.Free;
    end;
    i := Pos(RawByteString('BT'), result);
    j := PosEx(RawByteString('ET'), result, i);
    if (i = 0) or (j = 0) then
      result := ''
    else
      result := copy(result, i, j - i + 2);
  end;

var
  PDF: TPdfDocumentVcl;
  C: TPdfVclCanvas;
begin
  { s is built from code points, not from GROESSE: the string path and the
    RawUtf8 path must meet from independent sources }
  s := SynUnicodeToString('Gr' + WideChar($F6) + WideChar($DF) + 'e');
  PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
  try
    C := NewCanvas(PDF);
    CheckSame(C.TextWidthUtf8(GROESSE) / C.TextWidthUtf8('l'),
      W_GROESSE / W_L, 1e-3, 'UTF-8 decoded for measuring');
    CheckSame(C.TextWidthFrac(s), C.TextWidthUtf8(GROESSE), 1e-3,
      'string and RawUtf8 measure alike');
  finally
    PDF.Free;
  end;
  sTextOut := DrawnText(false);
  sUtf8 := DrawnText(true);
  Check(Pos(RawByteString('Tj'), sUtf8) > 0, 'TextOutUtf8 shows text');
  Check(sUtf8 = sTextOut, 'TextOutUtf8 draws as TextOutFrac');
end;
{$endif PDF_HASVCLCANVAS}

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
      PDF.Info.Creator := 'mormot.pdf';

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
      // A4: 210mm x 297mm = 595 x 842 points
      PDF.DefaultPageWidth  := 595;
      PDF.DefaultPageHeight := 842;
      PDF.AddPage;
      // US Letter: 216mm x 279mm = 612 x 792 points
      PDF.DefaultPageWidth  := 612;
      PDF.DefaultPageHeight := 792;
      PDF.AddPage;
      // A3: 297mm x 420mm = 842 x 1191 points
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
    Y: integer; const S: RawUtf8);
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

const
  // the test fonts: a CID-keyed CFF face, an Arabic face without
  // presentation forms - the same faces on every platform
  CJK_FONT    = TEST_CJK;
  ARABIC_FONT = TEST_ARABIC;
  /// 字体嵌入测试 - "font embedding test"
  CJK_TEXT = {$ifdef HASCODEPAGE}
    #$5B57#$4F53#$5D4C#$5165#$6D4B#$8BD5 {$else}
    #$E5#$AD#$97#$E4#$BD#$93#$E5#$B5#$8C#$E5#$85#$A5#$E6#$B5#$8B#$E8#$AF#$95 {$endif};
  /// مرحبا - "hello", joining letters: needs the shaper
  ARABIC_TEXT = {$ifdef HASCODEPAGE}
    #$0645#$0631#$062D#$0628#$0627 {$else}
    #$D9#$85#$D8#$B1#$D8#$AD#$D8#$A8#$D8#$A7 {$endif};

{ the file PAC 2024 and veraPDF are run on (R-19 step 4), named after the
  build, e.g. tagged_unicode_windows_x86_delphi-7.pdf: the files of every
  platform and compiler can then be checked from one folder.
  COMPILER_VERSION ends with ' 32 bit' or ' 64 bit', which CPU_ARCH_TEXT
  already says }
function UnicodePdfName: TFileName;
var
  compiler: RawUtf8;
begin
  compiler := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  result := Utf8ToString(LowerCase('tagged_unicode_' +
    ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' + CPU_ARCH_TEXT + '_' +
    StringReplaceAll(compiler, ' ', '-') + '.pdf'));
end;

{ font dictionaries of ASubtype (e.g. '/Subtype/TrueType') lacking AKey
  - the dictionary is taken from the '<<' before the subtype to the first
    '>>' after it, which holds for the font dictionaries this engine writes }
function FontsWithout(const s, ASubtype, AKey: RawByteString): integer;
var
  p, b, e: PtrInt;
begin
  result := 0;
  p := PosEx(ASubtype, s);
  while p > 0 do
  begin
    b := p;
    while (b > 1) and
          not ((s[b] = '<') and (s[b - 1] = '<')) do
      dec(b);
    e := PosEx(RawByteString('>>'), s, p);
    if PosEx(AKey, copy(s, b, e - b)) = 0 then
      inc(result);
    p := PosEx(ASubtype, s, p + 1);
  end;
end;

{ streams whose data starts with ASignature (e.g. 'OTTO') and whose
  dictionary - from the '<<' before 'stream' - lacks AKey }
function StreamsWithout(const s, ASignature, AKey: RawByteString): integer;
var
  p, b: PtrInt;
begin
  result := 0;
  p := PosEx('stream'#10 + ASignature, s);
  while p > 0 do
  begin
    b := p;
    while (b > 1) and
          not ((s[b] = '<') and (s[b - 1] = '<')) do
      dec(b);
    if PosEx(AKey, copy(s, b, p - b)) = 0 then
      inc(result);
    p := PosEx('stream'#10 + ASignature, s, p + 1);
  end;
end;

procedure TPdfSmokeTests.TestTaggedUnicode;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { tagged Latin, CJK and shaped Arabic through layer 1 alone - the output
    Delphi and FPC have to agree on (R-19); the file is kept in WorkDir,
    next to the executable }
  Check(EnsureTestFonts, 'the test fonts registered');
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone; // so the objects stay readable
      PDF.Tagged := true;
      PDF.DefaultLanguage := 'en';
      PDF.Info.Title := 'Tagged Unicode through TPdfCanvas';
      PDF.AddPage;
      PDF.Canvas.BeginStructContent(psrH1);
      UseSansFont(PDF, 18);
      DrawUtf8Text(PDF, 40, 780, 'Tagged Unicode through TPdfCanvas');
      PDF.Canvas.EndStructContent;
      PDF.Canvas.BeginStructContent(psrP);
      UseSansFont(PDF, 12);
      DrawUtf8Text(PDF, 40, 740, 'Latin, CJK and Arabic on one page.');
      PDF.Canvas.EndStructContent;
      PDF.Canvas.BeginStructContent(psrP);
      PDF.Canvas.SetFont(CJK_FONT, 18, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(PDF, 40, 700, CJK_TEXT);
      PDF.Canvas.EndStructContent;
      PDF.Canvas.BeginStructContent(psrP);
      // as rtl_demo: UseUniscribe shapes, RightToLeftText is the direction
      PDF.UseUniscribe := true;
      PDF.Canvas.RightToLeftText := true;
      PDF.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(PDF, 40, 650, ARABIC_TEXT);
      PDF.Canvas.RightToLeftText := false;
      PDF.UseUniscribe := false;
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    FileFromString(s, WorkDir + UnicodePdfName);
    CheckEqual(CountOccurrences('/S/H1', s), 1, 'one H1');
    CheckEqual(CountOccurrences('/S/P', s), 3, 'three P');
    Check(CountOccurrences('/FontFile', s) >= 3, 'Latin, CJK and Arabic faces embedded');
    Check(Pos(RawByteString('5B57'), s) > 0, 'ToUnicode maps the CJK text (U+5B57)');
    { joined Arabic letters are presentation forms (U+FExx) or, in a face
      without them as the test font, PUA slots (U+Exxx); unshaped text maps
      to U+06xx only (R-13). POSIX shapes only when libharfbuzz loaded }
    if {$ifdef OSWINDOWS} true {$else} FontShaper <> nil {$endif} then
      Check((Pos(RawByteString('> <FE'), s) > 0) or
            (Pos(RawByteString('> <E'), s) > 0), 'the Arabic text is shaped');
    { the WinAnsi peers of the CJK and Arabic faces show no character, and
      were written without /FirstChar, /LastChar and /Widths - PAC 2024
      stopped on them ("'FirstChar' not defined in TrueType font") }
    CheckEqual(FontsWithout(s, '/Subtype/TrueType', '/FirstChar'), 0,
      'every simple TrueType font has FirstChar, LastChar and Widths');
    { PDF/UA-1 7.21.3.2 wants the map written even though Identity is the
      default - it was, for PDF/A only: PAC 2024 "An invalid CIDToGIDMap
      entry in a Type 2 CID font" }
    CheckEqual(FontsWithout(s, '/Subtype/CIDFontType2', '/CIDToGIDMap/Identity'), 0,
      'every CIDFontType2 has CIDToGIDMap Identity');
    { a .ttc face is embedded alone, an OpenType font file with its subtype
      (fonts.md 3); the defect behind this depended on the heap, so it may
      not show }
    CheckEqual(CountOccurrences('stream'#10'ttcf', s), 0,
      'no whole .ttc collection embedded');
    CheckEqual(StreamsWithout(s, 'OTTO', '/Subtype/OpenType'), 0,
      'every OpenType font file has Subtype OpenType');
  finally
    Stream.Free;
  end;
end;

{ one line in aFont, uncompressed, with the two shaping switches as given }
function ShapedPdf(const aFont, aText: RawUtf8; aShape, aRtl: boolean): RawByteString;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  EnsureTestFonts; // before the document reads its font list
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.EmbeddedTTF := true;
      PDF.AddPage;
      PDF.UseUniscribe := aShape;
      PDF.Canvas.RightToLeftText := aRtl;
      PDF.Canvas.SetFont(aFont, 24, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(PDF, 40, 650, aText);
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    result := StreamToRaw(Stream);
  finally
    Stream.Free;
  end;
end;

{ joined Arabic letters are presentation forms (U+FExx) or PUA slots (U+Exxx)
  in /ToUnicode; unshaped text maps to U+06xx only }
function IsShaped(const s: RawByteString): boolean;
begin
  result := (Pos(RawByteString('> <FE'), s) > 0) or
            (Pos(RawByteString('> <E'), s) > 0);
end;

procedure TPdfSmokeTests.TestShapingSwitch;
var
  sans, serif, mono: string;
begin
  { UseUniscribe is the one shaping switch on every platform, RightToLeftText
    only the direction: HarfBuzz used to run on RightToLeftText alone and to
    force LTR otherwise, which shaped Arabic in the wrong order }
  {$ifndef OSWINDOWS} // Uniscribe is part of Windows
  if FontShaper = nil then
  begin
    Check(true, 'SKIP: no text shaper (libharfbuzz absent)');
    exit;
  end;
  {$endif OSWINDOWS}
  Check(IsShaped(ShapedPdf(ARABIC_FONT, ARABIC_TEXT, true, false)),
    'UseUniscribe alone shapes, the direction taken from the script');
  Check(not IsShaped(ShapedPdf(ARABIC_FONT, ARABIC_TEXT, false, true)),
    'RightToLeftText alone does not shape');
  // Uniscribe leaves a run without a complex script in the simple font, and
  // HarfBuzz has to do the same, or every Latin line changes font
  GetPdfFonts(true, sans, serif, mono);
  CheckEqual(CountOccurrences('/Type0', ShapedPdf(StringToUtf8(sans), 'Hello, World', true, false)), 0,
    'Latin text with UseUniscribe stays in the simple font');
end;

// Arabic and ' Ab' in the Arabic test font, Test Sans the fallback font
const
  /// U+200C ZERO WIDTH NON-JOINER
  ZWNJ: RawUtf8 = {$ifdef HASCODEPAGE} #$200C {$else} #$E2#$80#$8C {$endif};

function PlainFallbackPdf(aFallBack, aPdfString: boolean;
  aPdfA: TPdfALevel = pdfaNone): RawByteString;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, aPdfA);
    try
      PDF.CompressionMethod := cmNone;
      PDF.EmbeddedTTF := true;
      PDF.FontFallBackName := TEST_SANS;
      PDF.UseFontFallBack := aFallBack;
      PDF.AddPage;
      PDF.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
      if aPdfString then
        PDF.Canvas.TextOut(40, 650, 'Ab')
      else
        DrawUtf8Text(PDF, 40, 650, ARABIC_TEXT + ' Ab');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    result := StreamToRaw(Stream);
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestPlainFallback;
var
  s: RawByteString;
  raised: boolean;
  PDF: TPdfDocument;
  arabic, sans, space: single;
  tm: PdfString;
  tmw: array[0..1] of WideChar;
begin
  { a WinAnsi character the main face lacks went out in its simple font as
    .notdef: it is drawn by glyph now, where it falls back - read from the
    face's own cmap, no Unicode font added for a face that has them all }
  Check(EnsureTestFonts, 'the test fonts registered');
  s := PlainFallbackPdf(true, false);
  Check(Pos(RawByteString('mORMotTestSans'), s) > 0, 'the fallback font drew Ab');
  Check(Pos(RawByteString('Ab) Tj'), s) = 0, 'not in the simple Arabic font');
  s := PlainFallbackPdf(true, true);
  Check(Pos(RawByteString('mORMotTestSans'), s) > 0, 'TextOut of a PdfString too');
  Check(Pos(RawByteString('(Ab) Tj'), s) = 0, 'TextOut: not in the simple font');
  // no fallback: the simple font draws it, as before
  s := PlainFallbackPdf(false, false);
  Check(Pos(RawByteString('mORMotTestSans'), s) = 0, 'fallback off: no Test Sans');
  Check(Pos(RawByteString('Ab) Tj'), s) > 0, 'fallback off: the simple font');
  // PDF/A forbids .notdef (ISO 19005-2 6.2.11.8): no way out raises
  raised := false;
  try
    PlainFallbackPdf(false, false, pdfa3U);
  except
    on E: EPdfInvalidOperation do
      raised := Pos('U+0041', E.Message) > 0; // ours, not another rule's
  end;
  Check(raised, 'PDF/A without a fallback raises');
  // a format control no font has draws nothing - no PDF/A error (Test Sans
  // has no ZWNJ; both shapers drop it too)
  raised := false;
  try
    PDF := TPdfDocument.Create(false, 0, pdfa3U);
    try
      PDF.FontFallBackName := TEST_SANS;
      PDF.AddPage;
      PDF.Canvas.SetFont(TEST_SANS, 24, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(PDF, 40, 650, 'a' + ZWNJ + 'b');
    finally
      PDF.Free;
    end;
  except
    on EPdfInvalidOperation do
      raised := true;
  end;
  Check(not raised, 'a ZWNJ no font has is no PDF/A error');
  // measured where it is drawn, by both APIs
  PDF := TPdfDocument.Create;
  try
    PDF.FontFallBackName := TEST_SANS;
    PDF.AddPage;
    PDF.Canvas.SetFont(TEST_SANS, 24, [], PDF_DEFAULT_CHARSET);
    sans := PDF.Canvas.UnicodeTextWidth('Ab');
    space := PDF.Canvas.UnicodeTextWidth(' '); // the /DW of Test Sans
    PDF.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
    arabic := PDF.Canvas.UnicodeTextWidth('Ab');
    Check((sans > 0) and
          (abs(arabic - sans) < 0.01), 'measured with the fallback font');
    arabic := PDF.Canvas.TextWidth('Ab');
    Check(abs(arabic - sans) < 0.01, 'TextWidth of a PdfString too');
    // TRADE MARK SIGN, WinAnsi $99, which neither font has: drawn as glyph 0
    // of the fallback font, which advances its /DW - measured so by both
    // APIs; TextWidth gave 0 (Martin, #53), UnicodeTextWidth 600 (Fable)
    tm := AnsiChar($99);
    tmw[0] := WideChar($2122);
    tmw[1] := #0;
    sans := PDF.Canvas.UnicodeTextWidth(@tmw);
    arabic := PDF.Canvas.TextWidth(tm);
    Check((space > 0) and
          (abs(sans - space) < 0.01) and
          (abs(arabic - space) < 0.01), 'a character no font has: the /DW');
  finally
    PDF.Free;
  end;
end;

// a shaped line of the Arabic test font with Test Sans as its fallback font
function ShapedFallbackPdf(const aText: RawUtf8; aRtl: boolean;
  aFallBack: boolean = true; aPdfA: TPdfALevel = pdfaNone): RawByteString;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, aPdfA);
    try
      PDF.CompressionMethod := cmNone;
      PDF.EmbeddedTTF := true;
      PDF.FontFallBackName := TEST_SANS;
      PDF.UseFontFallBack := aFallBack;
      PDF.UseUniscribe := true;
      PDF.AddPage;
      PDF.Canvas.RightToLeftText := aRtl;
      PDF.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(PDF, 40, 650, aText);
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    result := StreamToRaw(Stream);
  finally
    Stream.Free;
  end;
end;

// where the Type0 font of Test Sans is selected in the first text object,
// relative to its first glyph string: -1 before it, 1 after it, 0 not at all
function SansSelected(const s: RawByteString): integer;
var
  p, e, b, t, h: PtrInt;
  name: RawByteString;
begin
  result := 0;
  p := PosEx('mORMotTestSans/Subtype/Type0/Encoding/Identity-H/Name/', s);
  if p = 0 then
    exit;
  inc(p, length('mORMotTestSans/Subtype/Type0/Encoding/Identity-H/Name/'));
  e := p;
  while (e <= length(s)) and
        (s[e] <> '/') do
    inc(e);
  // no '+': FPC 3.2.2 i386 drops a RawByteString operand of a concatenation
  SetLength(name, e - p + 2);
  name[1] := '/';
  Move(s[p], name[2], e - p);
  name[e - p + 2] := ' ';
  b := PosEx('BT', s);
  t := PosEx(name, s, b);
  h := PosEx('<', s, b);
  if (t = 0) or
     (h = 0) then
    exit;
  if t < h then
    result := -1
  else
    result := 1;
end;

procedure TPdfSmokeTests.TestFormFallback;
var
  PDF: TPdfDocument;
  form: TPdfFormWithCanvas;
  W: SynUnicode;
  s: RawByteString;
  ok: boolean;
  Stream: TMemoryStream;
  i: PtrInt;
  xobj: RawByteString;
begin
  { the fallback font was chosen through the document's page canvas, which
    has no page before the first AddPage: the form's own canvas draws it }
  Check(EnsureTestFonts, 'the test fonts registered');
  ok := true;
  s := '';
  PDF := TPdfDocument.Create;
  try
    PDF.CompressionMethod := cmNone;
    PDF.EmbeddedTTF := true;
    PDF.FontFallBackName := TEST_SANS;
    PDF.UseFontFallBack := true;
    try
      form := TPdfFormWithCanvas.Create(PDF, 200, 100);
      form.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
      W := 'Ab';
      form.Canvas.TextOutW(10, 50, pointer(W));
      form.CloseCanvas;
      PDF.AddXObject('FormF', form);
      PDF.AddPage;
      PDF.Canvas.DrawXObject(40, 600, 1, 1, 'FormF');
      Stream := TMemoryStream.Create;
      try
        PDF.SaveToStream(Stream);
        s := StreamToRaw(Stream);
      finally
        Stream.Free;
      end;
    except
      ok := false;
    end;
  finally
    PDF.Free;
  end;
  Check(ok, 'a form drawn before the first page');
  Check(Pos(RawByteString('mORMotTestSans'), s) > 0, 'the fallback font drew Ab');
  // drawn in the form, with the fallback font in the form's own resources
  i := Pos(RawByteString('/Subtype/Form'), s);
  xobj := Copy(s, i, PosEx('endstream', s, i + 1) - i);
  Check((i > 0) and
        (PosEx('> Tj', xobj) > 0), 'the glyphs in the form stream');
  CheckEqual(CountOccurrences(' 24 Tf', xobj), 2,
    'its font and the fallback font selected there');
  // the page object, up to its endobj, lists no font
  i := Pos(RawByteString('/Type/Page/'), s);
  Check((i > 0) and
        (PosEx('/Font<<>>', Copy(s, i, PosEx('endobj', s, i) - i)) > 0),
    'no font on the page');
end;

// Text in a test face without a (3,1) or (3,0) cmap, by both text APIs
function NoSimpleCmapPdf(const aFamily: RawUtf8; aEmbedded: boolean;
  aPdfA: TPdfALevel = pdfaNone; aWordSpace: single = 0): RawByteString;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, aPdfA);
    try
      PDF.CompressionMethod := cmNone;
      PDF.EmbeddedTTF := aEmbedded;
      PDF.AddPage;
      PDF.Canvas.SetFont(aFamily, 24, [], TEST_FONT_CHARSET);
      PDF.Canvas.SetWordSpace(aWordSpace);
      PDF.Canvas.TextOut(40, 650, 'Ab c');
      DrawUtf8Text(PDF, 40, 600, 'Ab c');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    result := StreamToRaw(Stream);
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestUnicodeOnlyCmap;
begin
  CheckNoSimpleCmap(TEST_UNICODE_ONLY, '(0,3)');
end;

procedure TPdfSmokeTests.TestFormat12Cmap;
begin
  CheckNoSimpleCmap(TEST_FORMAT12, '(3,10) format 12');
end;

// a face whose cmap is no (3,1) or (3,0) one: its WinAnsi text goes by
// glyph, as a simple TrueType font reaches its glyphs through those only
procedure TPdfSmokeTests.CheckNoSimpleCmap(const aFamily, aCmap: RawUtf8);
var
  face: IFontFace;
  cmap: RawByteString;
  n: cardinal;
  i, plat, enc: integer;
  loaded: boolean;
  s: RawByteString;
  raised: boolean;
  PDF: TPdfDocument;
begin
  Check(EnsureTestFonts, 'the test fonts registered');
  // GDI loads no face without a Microsoft cmap: it gives another font, one
  // with (3,1), whose text stays in the simple font
  face := TestFace(aFamily, TEST_FONT_CHARSET);
  loaded := false;
  if Check(face <> nil, 'the face') then
  begin
    n := face.GetFontData(PCardinal(PAnsiChar('cmap'))^, 0, nil, 0);
    if (n <> FONT_DATA_ERROR) and
       (n >= 12) then
    begin
      SetLength(cmap, n);
      face.GetFontData(PCardinal(PAnsiChar('cmap'))^, 0, pointer(cmap), n);
      loaded := true;
      for i := 0 to (ord(cmap[3]) shl 8 + ord(cmap[4])) - 1 do
        if 4 + i * 8 + 4 <= integer(n) then
        begin
          plat := ord(cmap[5 + i * 8]) shl 8 + ord(cmap[6 + i * 8]);
          enc := ord(cmap[7 + i * 8]) shl 8 + ord(cmap[8 + i * 8]);
          if (plat = 1) or
             ((plat = 3) and (enc <= 1)) then
            loaded := false; // a (1,x), (3,0) or (3,1): not the test face
        end;
    end;
  end;
  s := NoSimpleCmapPdf(aFamily, true);
  {$ifdef OSWINDOWS}
  if not loaded then
  begin
    Check(true, 'SKIP: GDI replaced the face by one with a Microsoft cmap');
    Check(PosEx('(Ab c) Tj', s) > 0, 'the replacement in the simple font');
    exit;
  end;
  {$else}
  Check(loaded, 'the test face, ' + aCmap + ' only');
  {$endif OSWINDOWS}
  Check(PosEx('(Ab c) Tj', s) = 0, 'not in the simple font');
  Check(PosEx('/Subtype/TrueType', s) = 0, 'no simple font written');
  Check(PosEx('/Subtype/Type0', s) > 0, 'the Type0 font');
  // the glyf flavour: CIDFontType2 by glyph index, no CFF program or version
  Check(PosEx('/Subtype/CIDFontType2', s) > 0, 'a CIDFontType2');
  Check(PosEx('/CIDToGIDMap/Identity', s) > 0, 'its codes the glyph indexes');
  Check((PosEx('/FontFile2', s) > 0) and
        (PosEx('/FontFile3', s) = 0), 'the glyf program in /FontFile2');
  Check(Copy(s, 1, 8) = '%PDF-1.3', 'no version raised');
  // A b space c of the face, not .notdef
  CheckEqual(CountOccurrences('<0022004300010044> Tj', s), 2,
    'both APIs by glyph');
  Check(PosEx('/ToUnicode', s) > 0, 'the text extractable');
  // measured with the advances of the face: 639 + 615 + 260 + 480 units
  PDF := TPdfDocument.Create;
  try
    PDF.EmbeddedTTF := true; // the Type0 path: the widths of the cmap read
    PDF.AddPage;
    PDF.Canvas.SetFont(aFamily, 24, [], TEST_FONT_CHARSET);
    CheckSame(PDF.Canvas.UnicodeTextWidth('Ab c'), 1994 * 24 / 1000, 0.01,
      'the widths of the face');
  finally
    PDF.Free;
  end;
  // word spacing on 2-byte codes: a TJ adjustment after the space
  s := NoSimpleCmapPdf(aFamily, true, pdfaNone, 5);
  CheckEqual(CountOccurrences('] TJ', s), 2, 'word spacing in a TJ array');
  // not embedded: glyph indexes would mean nothing - the simple font
  s := NoSimpleCmapPdf(aFamily, false);
  CheckEqual(CountOccurrences('(Ab c) Tj', s), 2, 'not embedded: simple font');
  // PDF/A embeds: no simple font left for a rule to fail
  raised := false;
  try
    s := NoSimpleCmapPdf(aFamily, false, pdfa3U);
  except
    raised := true;
  end;
  Check(not raised, 'PDF/A-3U saves');
  Check(PosEx('/Subtype/TrueType', s) = 0, 'PDF/A: no simple font');
end;

procedure TPdfSmokeTests.TestShapedFallback;
var
  arabicFirst, latinFirst: RawUtf8;
  s: RawByteString;
  rtl: boolean;
  raised: boolean;
begin
  { a part of a shaped line the main font lacks glyphs for - the Latin of a
    line in the Arabic test font - is shaped again in the fallback face and
    drawn from it (IFontRunShaper), the Arabic still joined: Uniscribe gave
    .notdef for it, HarfBuzz one run of the whole line }
  {$ifndef OSWINDOWS}
  if FontShaper = nil then
  begin
    Check(true, 'SKIP: no text shaper (libharfbuzz absent)');
    exit;
  end;
  {$endif OSWINDOWS}
  Check(EnsureTestFonts, 'the test fonts registered');
  arabicFirst := ARABIC_TEXT + ' Ab';
  latinFirst := 'Ab ' + ARABIC_TEXT;
  for rtl := false to true do
  begin
    s := ShapedFallbackPdf(arabicFirst, rtl);
    Check(IsShaped(s), 'Arabic first: the Arabic joined');
    Check(not PdfTextShows(s, '0000'), 'Arabic first: no .notdef');
    // the visual order: the Arabic run left of 'Ab' on a left-to-right line,
    // right of it on a right-to-left one
    if rtl then
      CheckEqual(SansSelected(s), -1, 'Arabic first, RTL: Ab drawn first')
    else
      CheckEqual(SansSelected(s), 1, 'Arabic first, LTR: Ab drawn after');
    s := ShapedFallbackPdf(latinFirst, rtl);
    Check(IsShaped(s), 'Latin first: the Arabic joined');
    Check(not PdfTextShows(s, '0000'), 'Latin first: no .notdef');
    if rtl then
      CheckEqual(SansSelected(s), 1, 'Latin first, RTL: Ab drawn after')
    else
      CheckEqual(SansSelected(s), -1, 'Latin first, LTR: Ab drawn first');
  end;
  // no fallback: the part keeps the main font, as before
  s := ShapedFallbackPdf(arabicFirst, false, false);
  CheckEqual(SansSelected(s), 0, 'fallback off: no Test Sans');
  // PDF/A forbids .notdef: no way out raises
  raised := false;
  try
    ShapedFallbackPdf(arabicFirst, false, false, pdfa3U);
  except
    on E: EPdfInvalidOperation do
      raised := Pos('PDF/A', E.Message) > 0;
  end;
  Check(raised, 'PDF/A without a fallback raises');
end;

procedure TPdfSmokeTests.TestShapedAfterFallback;
const
  /// देव then عربي: Devanagari, which the main font lacks, then Arabic
  MIXED_TEXT = {$ifdef HASCODEPAGE}
    #$0926#$0947#$0935#$0639#$0631#$0628#$064A {$else}
    #$E0#$A4#$A6#$E0#$A5#$87#$E0#$A4#$B5#$D8#$B9#$D8#$B1#$D8#$A8#$D9#$8A {$endif};
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { Uniscribe draws an item it cannot shape in the main font unshaped, and its
    characters then come from the fallback font; the shaped item after it drew
    the main font's glyph IDs in the fallback font, which was still active -
    a measured face: it runs where Nirmala UI is the fallback taken, on
    Windows, and adds nothing elsewhere. Since the fallback step the
    Devanagari item is shaped again in the fallback face (TestShapedFallback
    covers that on every platform) }
  Check(EnsureTestFonts, 'the test fonts registered');
  {$ifdef OSWINDOWS}
  if not SystemFaceExtra(self, 'Nirmala UI') then
    exit;
  {$endif OSWINDOWS}
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.EmbeddedTTF := true;
      PDF.FontFallBackName := 'Nirmala UI';
      PDF.AddPage;
      PDF.UseUniscribe := true;
      PDF.Canvas.SetFont(ARABIC_FONT, 24, [], PDF_DEFAULT_CHARSET);
      DrawUtf8Text(PDF, 40, 650, MIXED_TEXT);
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
  finally
    Stream.Free;
  end;
  if Pos(RawByteString('NirmalaUI'), s) = 0 then
    exit; // no Nirmala UI, or no fallback taken
  Check(IsShaped(s), 'the Arabic item is shaped');
  CheckEqual(CountOccurrences('> Tj'#10'<', s), 0,
    'the shaped item switches back to the main font after the fallback');
end;

type
  // a shaper giving one shaped run of glyph $0024 with the outcome asked for
  TFixedRunShaper = class(TInterfacedObject, IFontShaper)
  public
    Outcome: TFontShapeOutcome;
    // leaves Kind at its zero value, fskPlain
    KindUnset: boolean;
    // adds a second, plain run of no code unit - which the contract excludes
    EmptyRun: boolean;
    function Shape(Text: PWideChar; Len: integer; Font: TFontHandle;
      RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
  end;

function TFixedRunShaper.Shape(Text: PWideChar; Len: integer; Font: TFontHandle;
  RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
begin
  SetLength(Runs, 1);
  if not KindUnset then
    Runs[0].Kind := fskShaped;
  Runs[0].Outcome := Outcome;
  Runs[0].TextStart := 0;
  Runs[0].TextLen := Len;
  SetLength(Runs[0].Glyphs, 1);
  Runs[0].Glyphs[0] := $24;
  SetLength(Runs[0].Advances, 1);
  Runs[0].Advances[0] := 500;
  SetLength(Runs[0].Offsets, 1);
  if EmptyRun then
  begin
    SetLength(Runs, 2);
    Runs[1].Kind := fskPlain;
    Runs[1].Outcome := fsoDone;
    Runs[1].TextStart := Len;
    Runs[1].TextLen := 0;
  end;
  result := true;
end;

procedure TPdfSmokeTests.TestShapedRunOutcomeUnset;
var
  saved: IFontShaper;
  fixed: TFixedRunShaper;
  plain: RawByteString;

  // the text object of the page: the one line ShapedPdf() draws
  function TextObject(const aPdf: RawByteString): RawByteString;
  var
    b: integer;
  begin
    b := Pos(RawByteString('BT'#10), aPdf);
    result := Copy(aPdf, b, PosEx('ET'#10, aPdf, b) - b);
  end;

  function Drawn(aOutcome: TFontShapeOutcome): RawByteString;
  begin
    fixed.Outcome := aOutcome;
    result := TextObject(ShapedPdf(ARABIC_FONT, ARABIC_TEXT, true, false));
  end;

begin
  { fsoUnknown is the zero value of TFontShapeOutcome, fskPlain that of
    TFontShapeKind: a run whose shaper never set either is drawn unshaped,
    whatever the other says }
  saved := FontShaper;
  fixed := TFixedRunShaper.Create;
  FontShaper := fixed;
  try
    plain := TextObject(ShapedPdf(ARABIC_FONT, ARABIC_TEXT, false, false));
    Check(plain <> '', 'the unshaped line is drawn');
    // shaped: the run's one glyph, in Tj or TJ
    Check(Pos(RawByteString('<0024>'), Drawn(fsoDone)) > 0,
      'a run with fsoDone is drawn as shaped');
    Check(Drawn(fsoUnknown) = plain,
      'a run left at fsoUnknown is drawn as without shaping');
    // and the same for Kind: fskPlain wins over fsoDone
    fixed.KindUnset := true;
    Check(Drawn(fsoDone) = plain,
      'a run left at fskPlain is drawn as without shaping');
    fixed.KindUnset := false;
    // a run of no code unit breaks the contract: the whole text goes the
    // simple path (it used to write a #0 through a nil buffer)
    fixed.EmptyRun := true;
    Check(Drawn(fsoDone) = plain, 'an empty run leaves the text unshaped');
  finally
    FontShaper := saved;
  end;
end;

procedure TPdfSmokeTests.TestZeroRealIsWritten;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { a TPdfReal of 0 came out empty under FPC, whose Grisu conversion writes
    '0' where Str() writes '0.00': the outline zoom and alpha 0 lost their
    operand, e.g. /XYZ 0 700 ] (found by layer1_demo, R-23) }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create({AUseOutlines=}true);
    try
      PDF.CompressionMethod := cmNone;
      PDF.AddPage;
      PDF.CreateOutline('Top', 1, 700);
      PDF.Canvas.SetFillAlpha(0);
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(Pos(RawByteString('/XYZ 0 700 0]'), s) > 0, 'outline zoom 0 written');
    Check(Pos(RawByteString('/ca 0'), s) > 0, 'fill alpha 0 written');
  finally
    Stream.Free;
  end;
end;

function Nibble(c: AnsiChar): integer;
begin
  case c of
    '0'..'9':
      result := ord(c) - ord('0');
    'A'..'F':
      result := ord(c) - ord('A') + 10;
    'a'..'f':
      result := ord(c) - ord('a') + 10;
  else
    result := 0;
  end;
end;

{ the literal or hex string after Key in s, as bytes: (..) unescaped, <..>
  decoded - '' if not found }
function PdfStringAfter(const s, Key: RawByteString): RawByteString;
var
  p, n, v: integer;
begin
  result := '';
  p := PosEx(Key, s);
  if p = 0 then
    exit;
  inc(p, length(Key));
  while (p <= length(s)) and
        (s[p] = ' ') do
    inc(p);
  if p > length(s) then
    exit;
  if s[p] = '<' then
  begin
    inc(p);
    while (p + 1 <= length(s)) and
          (s[p] <> '>') do
    begin
      result := result + AnsiChar(Nibble(s[p]) shl 4 + Nibble(s[p + 1]));
      inc(p, 2);
    end;
    exit;
  end;
  if s[p] <> '(' then
    exit;
  inc(p);
  while (p <= length(s)) and
        (s[p] <> ')') do
  begin
    if s[p] = '\' then
    begin
      inc(p);
      case s[p] of
        'n':
          result := result + #10;
        'r':
          result := result + #13;
        't':
          result := result + #9;
        'b':
          result := result + #8;
        'f':
          result := result + #12;
        '0'..'7':
          begin
            v := 0;
            n := 0;
            while (n < 3) and
                  (s[p] in ['0'..'7']) do
            begin
              v := v * 8 + ord(s[p]) - ord('0');
              inc(p);
              inc(n);
            end;
            result := result + AnsiChar(v);
            continue;
          end;
      else
        result := result + s[p]; // \( \) \\
      end;
    end
    else
      result := result + s[p];
    inc(p);
  end;
end;

procedure TPdfSmokeTests.TestEscapeBackspace;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { ISO 32000-1 7.3.4.2 defines \b; a reader takes \B as a plain B }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Info.Data.AddItemText('Subject', 'a'#8'b');
      PDF.AddPage;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(PosEx('(a\bb)', s) > 0, 'a backspace written as \b');
    CheckEqual(PdfStringAfter(s, '/Subject'), 'a'#8'b', 'and read back');
  finally
    Stream.Free;
  end;
end;

{$ifndef NO_USE_PDFSECURITY}

procedure TPdfSmokeTests.TestEncryptedUnicodeString;
const
  // omega alpha beta: no WinAnsi character, so a <FEFF...> text string
  GREEK: RawUtf8 = {$ifdef HASCODEPAGE} #$03C9#$03B1#$03B2
    {$else} #$CF#$89#$CE#$B1#$CE#$B2 {$endif};
  PLAIN: array[0..7] of byte = ($FE, $FF, $03, $C9, $03, $B1, $03, $B2);
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s, title, author: RawByteString;
  i: integer;
  ok: boolean;
begin
  { RC4 restarts its key stream for each string of an object: the plain
    ASCII Author of the same Info dictionary gives the key stream, which
    must decrypt the Title to its BOM and big-endian UTF-16 }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone,
      TPdfEncryption.New(elRC4_128, '', 'owner', PDF_PERMISSION_ALL));
    try
      PDF.CompressionMethod := cmNone;
      PDF.Info.Data.AddItemTextUtf8('Title', GREEK);
      PDF.Info.Data.AddItemText('Author', 'AAAAAAAA');
      PDF.AddPage;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    title := PdfStringAfter(s, '/Title');
    author := PdfStringAfter(s, '/Author');
    CheckEqual(length(title), 8, 'BOM and three characters, encrypted');
    CheckEqual(length(author), 8, 'the author, encrypted');
    ok := (length(title) = 8) and
          (length(author) = 8);
    if ok then
      for i := 1 to 8 do
        if ord(title[i]) xor ord(author[i]) xor ord('A') <> PLAIN[i - 1] then
          ok := false;
    Check(ok, 'the title decrypts to FEFF and UTF-16BE');
  finally
    Stream.Free;
  end;
end;

type
  // the object number an encryption key is computed from
  TPdfDocumentObjectNumber = class(TPdfDocument);

procedure TPdfSmokeTests.TestUnicodeHexNotEncrypted;
const
  AB: array[0..1] of WideChar = ('A', 'B');
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  W: TPdfWrite;
begin
  { a content stream is encrypted as a whole: a string in it, such as an
    /Alt text, must not be encrypted a second time }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone,
      TPdfEncryption.New(elRC4_128, '', 'owner', PDF_PERMISSION_ALL));
    try
      // object 0 is never written, and its RC4 key never computed
      TPdfDocumentObjectNumber(PDF).fCurrentObjectNumber := 5;
      W := TPdfWrite.Create(PDF, Stream);
      try
        W.AddUnicodeHex(@AB, 2);
        W.Save;
      finally
        W.Free;
      end;
    finally
      PDF.Free;
    end;
    CheckEqual(StreamToRaw(Stream), '00410042', 'plain big-endian hex');
  finally
    Stream.Free;
  end;
end;

{$endif NO_USE_PDFSECURITY}

procedure TPdfSmokeTests.TestWinAnsiToUnicodeBlocks;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s, ansi: RawByteString;
  p, q, n, most: integer;
begin
  { a CMap bfchar block holds at most 100 entries (Adobe CMap specification
    5014, 7.4); a tagged WinAnsi font of more characters wrote one block }
  Check(EnsureTestFonts, 'the test fonts registered');
  ansi := '';
  for n := 33 to 126 do
    ansi := ansi + AnsiChar(n);
  for n := 161 to 255 do
    ansi := ansi + AnsiChar(n);
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Tagged := true;
      PDF.AddPage;
      PDF.Canvas.BeginStructContent(psrP);
      PDF.Canvas.SetFont(TEST_SANS, 8, [], TEST_FONT_CHARSET);
      DrawUtf8Text(PDF, 20, 700, WinAnsiToUtf8(ansi));
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    most := 0;
    p := PosEx(' beginbfchar', s);
    while p > 0 do
    begin
      q := p - 1;
      while (q > 0) and
            (s[q] in ['0'..'9']) do
        dec(q);
      n := GetInteger(pointer(copy(s, q + 1, p - q - 1)));
      if n > most then
        most := n;
      p := PosEx(' beginbfchar', s, p + 1);
    end;
    Check(most > 0, 'a ToUnicode CMap written');
    Check(most <= 100, 'at most 100 entries per bfchar block');
    Check(PosEx('<FF> <00FF>', s) > 0, 'the last WinAnsi character mapped');
  finally
    Stream.Free;
  end;
end;

{ the /Count entry of the /Type/Outlines dictionary of s, '' if none }
function OutlinesDictionary(const s: RawByteString): RawByteString;
var
  p, b, e, c: integer;
begin
  result := '';
  p := PosEx('/Type/Outlines', s);
  if p = 0 then
    exit;
  b := p;
  while (b > 1) and
        (copy(s, b, 2) <> '<<') do
    dec(b);
  e := PosEx('>>', s, p);
  c := PosEx('/Count ', s, b);
  if (c = 0) or
     (c > e) then
    exit;
  e := c + 7;
  while (e <= length(s)) and
        (s[e] in ['0'..'9']) do
    inc(e);
  result := copy(s, c, e - c);
end;

procedure TPdfSmokeTests.TestOutlineBeforePage;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
  raised: boolean;
begin
  { the refused entry was already in the object list: freed by the failed
    constructor and again by the document, and counted by its parent }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create({AUseOutlines=}true);
    try
      PDF.CompressionMethod := cmNone;
      raised := false;
      try
        PDF.CreateOutline('Early', 1, 700);
      except
        on EPdfInvalidOperation do
          raised := true;
      end;
      Check(raised, 'an outline position before the first page is refused');
      PDF.AddPage;
      PDF.CreateOutline('Top', 1, 700);
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    CheckEqual(OutlinesDictionary(s), '/Count 1',
      'the outlines count one entry, not the refused one');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestAddFontKeepsFallback;
var
  PDF: TPdfDocument;
begin
  { AddTrueTypeFont sorts the font list: the fallback index and the name
    cache pointed at the font that moved into their place }
  Check(EnsureTestFonts, 'the test fonts registered');
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.FontFallBackName := TEST_SANS;
    CheckEqual(StringToUtf8(PDF.FontFallBackName), TEST_SANS, 'set');
    Check(PDF.AddTrueTypeFont('!sorts first'), 'a new name added');
    CheckEqual(StringToUtf8(PDF.FontFallBackName), TEST_SANS, 'kept');
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestAddFontKeepsCreatedFonts;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { a font created before AddTrueTypeFont kept the index the sort moved: the
    next SetFont of its face did not find it and created a second one }
  Check(EnsureTestFonts, 'the test fonts registered');
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.AddPage;
      PDF.Canvas.SetFont(TEST_SANS, 12, [], TEST_FONT_CHARSET);
      PDF.Canvas.TextOut(40, 700, 'Before');
      PDF.AddTrueTypeFont('!sorts first');
      PDF.Canvas.SetFont(TEST_SANS, 12, [], TEST_FONT_CHARSET);
      PDF.Canvas.TextOut(40, 680, 'After');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    CheckEqual(CountOccurrences('/BaseFont/mORMotTestSans', s), 1,
      'one font object for the face');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestAddFontKeepsRasterFont;
const
  UNKNOWN = 'No Such mORMot Font';
var
  PDF: TPdfDocument;
  form: TPdfFormWithCanvas;
begin
  { the index an unknown (raster) font name was resolved to is cached: after
    the sort of AddTrueTypeFont it named the face before it - through the
    canvas of a form as well }
  Check(EnsureTestFonts, 'the test fonts registered');
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.FontFallBackName := TEST_SANS;
    form := TPdfFormWithCanvas.Create(PDF, 200, 100);
    PDF.AddXObject('FormR', form); // owned by the document from here
    form.Canvas.SetFont(UNKNOWN, 12, [], TEST_FONT_CHARSET); // resolved, cached
    PDF.AddPage;
    PDF.Canvas.SetFont(UNKNOWN, 12, [], TEST_FONT_CHARSET);
    Check(PDF.AddTrueTypeFont('!sorts first'), 'a new name added');
    // a style not created yet: made from the cached index
    Check(PDF.Canvas.SetFont(UNKNOWN, 12, [pfsBold], TEST_FONT_CHARSET) =
          PDF.Canvas.SetFont(TEST_SANS, 12, [pfsBold], TEST_FONT_CHARSET),
      'the raster font is still the fallback face');
    Check(form.Canvas.SetFont(UNKNOWN, 12, [pfsItalic], TEST_FONT_CHARSET) =
          PDF.Canvas.SetFont(TEST_SANS, 12, [pfsItalic], TEST_FONT_CHARSET),
      'on the canvas of a form too');
    form.CloseCanvas;
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestRasterFontFixedWidth;
const
  UNKNOWN = 'No Such mORMot Font';
var
  PDF: TPdfDocument;
begin
  { the cache of a resolved raster font name ignored AIsFixedWidth: a name
    resolved to the proportional fallback stayed it when asked for as fixed
    width, which takes Courier New - where Courier New is missing, both are
    the fallback }
  Check(EnsureTestFonts, 'the test fonts registered');
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.FontFallBackName := TEST_SANS;
    PDF.AddPage;
    PDF.Canvas.SetFont(UNKNOWN, 12, [], TEST_FONT_CHARSET); // resolved, cached
    Check(PDF.Canvas.SetFont(UNKNOWN, 12, [], TEST_FONT_CHARSET, -1, true) =
          PDF.Canvas.SetFont('Courier New', 12, [], TEST_FONT_CHARSET),
      'fixed width: Courier New');
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestRasterFontFollowsFallback;
const
  UNKNOWN = 'No Such mORMot Font';
var
  PDF: TPdfDocument;
begin
  { the cache of a resolved raster font name kept the fallback font it was
    resolved to after FontFallBackName named another one }
  Check(EnsureTestFonts, 'the test fonts registered');
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.FontFallBackName := TEST_SANS;
    PDF.AddPage;
    PDF.Canvas.SetFont(UNKNOWN, 12, [], TEST_FONT_CHARSET); // resolved, cached
    PDF.FontFallBackName := TEST_ARABIC;
    Check(PDF.Canvas.SetFont(UNKNOWN, 12, [], TEST_FONT_CHARSET) =
          PDF.Canvas.SetFont(TEST_ARABIC, 12, [], TEST_FONT_CHARSET),
      'the new fallback font');
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestPostScriptNameFallback;
const
  // a family name beyond ASCII, so TtfFontPostcriptName reads the name table
  FAKE_NAME: RawUtf8 = {$ifdef HASCODEPAGE} 'Fak'#$00E9' Face'
    {$else} 'Fak'#$C3#$A9' Face' {$endif};
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  previous: IFontProvider;
  s: RawByteString;
begin
  { a face without an English (3,1) PostScript name gave an empty /BaseFont }
  Stream := TMemoryStream.Create;
  previous := SwapInNamelessFace(FAKE_NAME);
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.AddTrueTypeFont(FAKE_NAME);
      PDF.AddPage;
      PDF.Canvas.SetFont(FAKE_NAME, 12, [], PDF_DEFAULT_CHARSET);
      PDF.Canvas.TextOut(40, 700, 'Wi');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(PosEx('/BaseFont/Fak', s) > 0, 'the family name as /BaseFont');
  finally
    FontProvider := previous;
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestNewDocDropsMetadata;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { NewDoc frees every object: the metadata stream of PDF/A stayed in
    fMetaData, so the tagged setup took it as written and saved a freed one }
  Check(EnsureTestFonts, 'the test fonts registered');
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfa3U);
    try
      PDF.CompressionMethod := cmNone;
      PDF.PdfA := pdfaNone; // NewDoc
      PDF.Tagged := true;
      PDF.AddPage;
      PDF.Canvas.BeginStructContent(psrP);
      PDF.Canvas.SetFont(TEST_SANS, 12, [], TEST_FONT_CHARSET);
      DrawUtf8Text(PDF, 40, 700, 'Renewed');
      PDF.Canvas.EndStructContent;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(PosEx('/Metadata', s) > 0, 'a metadata stream');
    Check(PosEx('pdfuaid:part', s) > 0, 'written by the tagged setup');
    Check(PosEx('pdfaid:part', s) = 0, 'no PDF/A packet left');
  finally
    Stream.Free;
  end;
end;

{$ifndef NO_USE_PDFSECURITY}

procedure TPdfSmokeTests.TestNewDocKeepsEncryption;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
begin
  { NewDoc freed the /Encrypt dictionary with the old trailer but kept the
    reference: attaching the encryption again wrote into the freed object }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone,
      TPdfEncryption.New(elRC4_40, '', 'owner', PDF_PERMISSION_ALL));
    try
      PDF.CompressionMethod := cmNone;
      PDF.AddPage;
      PDF.NewDoc;
      PDF.AddPage;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    Check(PosEx('/Encrypt', StreamToRaw(Stream)) > 0, 'still encrypted');
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestNewDocRenewsObjectKeys;
var
  PDF: TPdfDocument;
  Stream: TMemoryStream;
  first, second: RawByteString;
begin
  { RC4 caches the key of the last object it encrypted: the Info dictionary
    is the last of one save and the first of the next, under the same object
    number, so the document renewed by NewDoc kept the key of the old file ID }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone,
      TPdfEncryption.New(elRC4_128, '', 'owner', PDF_PERMISSION_ALL));
    try
      PDF.CompressionMethod := cmNone;
      PDF.Info.Data.AddItemText('Author', 'AAAAAAAA');
      PDF.AddPage;
      PDF.SaveToStream(Stream);
      first := PdfStringAfter(StreamToRaw(Stream), '/Author');
      PDF.NewDoc; // a new file ID, so a new key
      PDF.Info.Data.AddItemText('Author', 'AAAAAAAA');
      PDF.AddPage;
      Stream.Clear;
      PDF.SaveToStream(Stream);
      second := PdfStringAfter(StreamToRaw(Stream), '/Author');
    finally
      PDF.Free;
    end;
    CheckEqual(length(second), 8, 'the author, encrypted');
    Check(second <> first, 'encrypted with the key of the new document');
  finally
    Stream.Free;
  end;
end;

{$endif NO_USE_PDFSECURITY}

procedure TPdfSmokeTests.TestNewDocEndsDirectSave;
var
  PDF: TPdfDocument;
  left, Stream: TMemoryStream;
begin
  { the writer of a SaveToStreamDirectBegin never ended stayed after NewDoc:
    the next save raised "called twice" }
  left := TMemoryStream.Create;
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.AddPage;
      PDF.SaveToStreamDirectBegin(left);
      PDF.NewDoc;
      PDF.AddPage;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    Check(PosEx('%%EOF', StreamToRaw(Stream)) > 0, 'saved after NewDoc');
  finally
    Stream.Free;
    left.Free;
  end;
end;

procedure TPdfSmokeTests.TestNewDocClosesArtifact;
var
  PDF: TPdfDocument;
begin
  { an artifact open on the page NewDoc freed made the next BeginArtifact
    raise: the canvas still took it as open }
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.Tagged := true;
    PDF.AddPage;
    PDF.Canvas.BeginArtifact;
    PDF.NewDoc;
    PDF.Tagged := true;
    PDF.AddPage;
    PDF.Canvas.BeginArtifact;
    PDF.Canvas.EndArtifact;
    Check(true, 'an artifact opened and closed after NewDoc');
  finally
    PDF.Free;
  end;
end;

procedure TPdfSmokeTests.TestCatalogGetters;
var
  PDF: TPdfDocument;
begin
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    Check(PDF.Root.HasData, 'the catalog has its dictionary');
    PDF.Root.NonFullScreenPageMode := pmUseOutlines;
    Check(PDF.Root.NonFullScreenPageMode = pmUseOutlines,
      'NonFullScreenPageMode read where it is written');
  finally
    PDF.Free;
  end;
end;

{ the header of a JPEG of Components (1 gray, 3 RGB, 4 CMYK), long enough
  for GetJpegSize - the scan data does not matter to the writer; built from
  numbers, as binary data must be }
function FakeJpeg(Components: integer): RawByteString;
const
  // SOI, APP0 of 90 bytes (its 88 data bytes follow as zeros)
  HEAD: array[0..5] of byte = ($ff, $d8, $ff, $e0, $00, $5a);
  // SOF0 of 17 bytes: 8 bits, 16 x 32, then the component count
  SOF: array[0..8] of byte = ($ff, $c0, $00, $11, $08, $00, $10, $00, $20);
var
  p: PByteArray;
  i, n: integer;
begin
  n := length(HEAD) + 88 + length(SOF) + 1 + Components * 3 + 2 + 8;
  SetLength(result, n);
  FillCharFast(pointer(result)^, n, 0);
  p := pointer(result);
  MoveFast(HEAD, p[0], length(HEAD));
  i := length(HEAD) + 88;
  MoveFast(SOF, p[i], length(SOF));
  inc(i, length(SOF));
  p[i] := Components;
  inc(i);
  FillCharFast(p[i], Components * 3, 1);
  inc(i, Components * 3);
  p[i] := $ff; // EOI
  p[i + 1] := $d9;
end;

function JpegPdf(Components: integer; Direct: boolean): RawByteString;
var
  PDF: TPdfDocument;
  Stream, jpg: TMemoryStream;
  img: TPdfImage;
  data: RawByteString;
begin
  data := FakeJpeg(Components);
  Stream := TMemoryStream.Create;
  jpg := TMemoryStream.Create;
  try
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.AddPage;
      if Direct then
      begin
        jpg.WriteBuffer(pointer(data)^, length(data));
        img := TPdfImage.CreateJpegDirect(PDF, jpg, true);
      end
      else
        img := TPdfImage.CreateJpeg(PDF, pointer(data), length(data), 32, 16, true);
      PDF.AddXObject('img', img);
      PDF.Canvas.DrawXObject(0, 0, 32, 16, 'img');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    result := StreamToRaw(Stream);
  finally
    jpg.Free;
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestJpegColorSpace;
var
  PDF: TPdfDocument;
  jpg: TMemoryStream;
  data: RawByteString;
  raised: boolean;
begin
  Check(PosEx('/ColorSpace/DeviceGray', JpegPdf(1, false)) > 0,
    'CreateJpeg: a gray JPEG is DeviceGray');
  Check(PosEx('/ColorSpace/DeviceRGB', JpegPdf(3, false)) > 0,
    'CreateJpeg: an RGB JPEG is DeviceRGB');
  Check(PosEx('/ColorSpace/DeviceGray', JpegPdf(1, true)) > 0,
    'CreateJpegDirect: gray');
  { not a JPEG, or one of four components: CreateJpegDirect left an image
    without data or colour space; both raise now }
  data := 'not a JPEG at all';
  jpg := TMemoryStream.Create;
  try
    jpg.WriteBuffer(pointer(data)^, length(data));
    PDF := TPdfDocument.Create(false, 0, pdfaNone);
    try
      raised := false;
      try
        TPdfImage.CreateJpegDirect(PDF, jpg, true).Free;
      except
        on EPdfInvalidValue do
          raised := true;
      end;
      Check(raised, 'CreateJpegDirect refuses what is no JPEG');
      data := FakeJpeg(4);
      jpg.Clear;
      jpg.WriteBuffer(pointer(data)^, length(data));
      raised := false;
      try
        TPdfImage.CreateJpegDirect(PDF, jpg, true).Free;
      except
        on EPdfInvalidValue do
          raised := true;
      end;
      Check(raised, 'CreateJpegDirect refuses a CMYK JPEG');
      raised := false;
      try
        TPdfImage.CreateJpeg(PDF, pointer(data), length(data), 32, 16, true).Free;
      except
        on EPdfInvalidValue do
          raised := true;
      end;
      Check(raised, 'CreateJpeg refuses a CMYK JPEG');
    finally
      PDF.Free;
    end;
  finally
    jpg.Free;
  end;
end;

procedure TPdfSmokeTests.TestZeroAdvanceMeasured;
const
  FATHA: array[0..1] of WideChar = (WideChar($064E), #0);
var
  PDF: TPdfDocument;
begin
  { a combining mark advances by 0 (hmtx of the test font); it was taken
    for a character the face lacks and measured by /DW or the fallback }
  Check(EnsureTestFonts, 'the test fonts registered');
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.EmbeddedTtf := true;
    PDF.AddPage;
    PDF.Canvas.SetFont(TEST_ARABIC, 12, [], TEST_FONT_CHARSET);
    CheckSame(PDF.Canvas.UnicodeTextWidth(@FATHA), 0, 1E-6, 'fatha measures 0');
  finally
    PDF.Free;
  end;
  // a face without the mark: measured in the fallback font, also at 0
  PDF := TPdfDocument.Create(false, 0, pdfaNone);
  try
    PDF.EmbeddedTtf := true;
    PDF.UseFontFallBack := true;
    PDF.FontFallBackName := TEST_ARABIC;
    PDF.AddPage;
    PDF.Canvas.SetFont(TEST_SANS, 12, [], TEST_FONT_CHARSET);
    CheckSame(PDF.Canvas.UnicodeTextWidth(@FATHA), 0, 1E-6,
      'fatha measures 0 in the fallback font');
  finally
    PDF.Free;
  end;
end;

{$ifdef PDF_HASVCLCANVAS}
procedure TPdfSmokeTests.TestVclCanvasPenAfterText;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { SyncFont marked the whole state valid: a line drawn with the default pen
    after text on a new page wrote no line width, so it was 1 pt, not 0.75 }
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.CompressionMethod := cmNone;
      PDF.StandardFontsReplace := true;
      PDF.ScreenLogPixels := 96; // a 1 px pen is 0.75 pt, whatever the screen
      PDF.AddPage;
      PDF.VclCanvas.Font.Name := 'Helvetica';
      PDF.VclCanvas.TextOut(40, 40, 'Text first');
      PDF.VclCanvas.MoveTo(40, 100);
      PDF.VclCanvas.LineTo(200, 100);
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    s := StreamToRaw(Stream);
    Check(PosEx('0.75 w', s) > 0, 'the 1 px pen written as 0.75 pt');
  finally
    Stream.Free;
  end;
end;
{$endif PDF_HASVCLCANVAS}

end.
