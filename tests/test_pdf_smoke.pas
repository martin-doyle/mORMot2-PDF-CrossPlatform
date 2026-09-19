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
  end;

implementation

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
      Check(PDF.EmbeddedWholeTtf, 'Tagged embeds the whole face, not a subset');
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
