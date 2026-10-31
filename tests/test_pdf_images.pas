/// golden files of the image and metafile paths of the engine
// - raw pixels and JPEG through TPdfImagePixels, on every compiler
// - TBitmap in every pixel format, reuse, color key, both JPEG ways and
// TPdfDocumentGdi/RenderMetaFile, as they are before they leave the engine
// for an adapter: the baseline recorded on the commit before the move proves
// the move changed nothing
// - assertions do not depend on the platform; the metafile cases are Windows
// only and count as skips elsewhere
unit test_pdf_images;

interface

{$I mormot.defines.inc}
{$I test_defines.inc}

uses
  {$ifdef PDF_HASVCLCANVAS}
  {$ifdef OSWINDOWS}
  Windows,
  {$endif OSWINDOWS}
  Types,                // Point, Rect of the canvas, not the engine's
  Graphics,             // TBitmap, TPixelFormat
  {$ifdef FPC}
  intfgraphics,         // TLazIntfImage: what the LCL says the pixels are
  {$endif FPC}
  {$ifdef OSWINDOWS}
  {$ifdef FPC}
  mormot.ui.core,       // TMetaFile, TMetaFileCanvas for FPC
  {$endif FPC}
  mormot.ui.gdiplus,    // TJpegImage, as the engine uses it on Windows
  mormot.lib.uniscribe, // GdiScreenLogPixels
  {$endif OSWINDOWS}
  {$endif PDF_HASVCLCANVAS}
  Classes,
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.test,
  mormot.core.text,
  mormot.core.unicode,
  mormot.lib.core,      // FontProvider
  mormot.pdf,
  test_pdf_cff,         // the synthetic CFF face
  {$ifdef PDF_HASVCLCANVAS}
  mormot.pdf.canvas,
  {$endif PDF_HASVCLCANVAS}
  pdf_inspect,
  test_pdf_golden;

type
  /// raw pixels and JPEG data through TPdfImagePixels and TPdfImage
  TPdfImageRawTests = class(TPdfGoldenTestCase)
  published
    procedure PixelFormats;
    procedure PixelReuse;
    procedure PixelChecks;
    procedure JpegData;
    procedure FormFonts;
    procedure FormWithCanvasImage;
  end;

{$ifdef PDF_HASVCLCANVAS}

  /// images and metafiles through the engine, recorded as golden files
  TPdfImageGoldenTests = class(TPdfGoldenTestCase)
  protected
    function SaveDoc(Doc: TPdfDocument): RawByteString;
  published
    procedure BitmapFormats;
    procedure BitmapReuse;
    procedure BitmapKeys;
    procedure BitmapJpeg;
    /// a bitmap with a colour key stays lossless under ForceJPEGCompression
    procedure BitmapJpegKey;
    procedure BitmapBridge;
    procedure MetaFileCanvas;
    procedure MetaFileRender;
    procedure MetaFileForm;
    procedure MetaFileFormState;
    procedure MetaFileWorldTransform;
    /// EMR_ALPHABLEND draws its bitmap opaque: no colour key
    procedure MetaFileAlphaBlend;
    /// the polylines of EMR_POLYPOLYLINE/16 stay open
    procedure MetaFilePolyPolyline;
    /// EMR_RESTOREDC restores the state it names, however deep
    procedure MetaFileRestoreDC;
    /// EMR_RESTOREDC restores the clip of EMR_EXTSELECTCLIPRGN and of
    // EMR_SETMETARGN, q and Q balanced
    procedure MetaFileClipRestoreDC;
    /// the pen after the Q of a clipped text with an underline is set again
    procedure MetaFileUnderlineClipped;
    /// lines of a null pen outside a path paint nothing and leave no path
    // open, a line of a pen leaves no pending stroke
    procedure MetaFileNullPenLines;
    /// a line after a record that ended its path with n is drawn: the n
    // left the renderer as if inside a path
    procedure MetaFileLineAfterEndedPath;
    /// text in a path is painted by the painting record, in the brush or the
    // pen of it, or dropped with the path
    procedure MetaFileTextInPath;
    procedure MetaFileMarkedContentInPath;
    procedure MetaFileTransformAfterPath;
    /// a scaled rotation is drawn, without ArcSin/ArcCos of a value past 1
    procedure MetaFileScaledRotation;
    /// EMR_EXTTEXTOUTA reads bytes in the code page of the font
    procedure MetaFileAnsiText;
    /// EMR_EXTTEXTOUTA after a stock font reads bytes in the system code page
    procedure MetaFileAnsiStockFont;
    procedure MetaFileStockFontMetrics;
    /// a stock font reads its bytes in the code page of its own charset
    procedure MetaFileStockCodePages;
    /// EMR_STRETCHDIBITS under a flipped transform flips a copy of its header
    procedure MetaFileDIBitsKept;
    /// a printer resolution of 0 is asked again, not divided by
    procedure MetaFilePrinterRes;
    /// the boxes as GDI records them: one device pixel inside for the shapes,
    // exclusive for the fills, the corners of EMR_ROUNDRECT mapped
    procedure MetaFileBoxes;
    procedure MetaFileClipBoxes;
    procedure MetaFileWorldBoxes;
    procedure MetaFileBitmapBounds;
    procedure MetaFileWorldRotation;
    procedure MetaFileWorldReflection;
    /// brushes and extended pens read in the layout of the EMF records
    procedure MetaFileRecordLayout;
  end;

{$endif PDF_HASVCLCANVAS}


implementation

{$ifdef FPC}
  // ScanLine[] is the pixel access of TBitmap on the VCL and the LCL alike
  {$WARN 5044 off : Symbol "$1" is not portable }
{$endif FPC}

type
  // reads the text states GSave keeps
  TPdfCanvasPeek = class(TPdfCanvas);

function Box(L, B, W, H: single): TPdfBox;
begin
  result.Left := L;
  result.Top := B;
  result.Width := W;
  result.Height := H;
end;


function SaveToString(Doc: TPdfDocument): RawByteString;
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

// the data of the uncompressed image named Name in a normalized PDF
function ImageData(const Txt, Name: RawUtf8): RawUtf8;
var
  i, j: PtrInt;
begin
  result := '';
  i := PosEx('/Name/' + Name + '/', Txt);
  if i = 0 then
    i := PosEx('/Name/' + Name + '>>', Txt);
  if i = 0 then
    exit;
  i := PosEx('stream'#10, Txt, i);
  j := PosEx(#10'endstream', Txt, i);
  if (i > 0) and
     (j > i) then
    result := copy(Txt, i + 7, j - i - 7);
end;

const
  RAW_W = 4;
  RAW_H = 3;

// RAW_W x RAW_H pixels of Format, top row first, rows of Pad extra bytes;
// Data points at the buffer, which holds them all
function RawPixels(Format: TPdfImagePixelFormat; var Buf: RawByteString;
  Pad: integer = 0; BottomUp: boolean = false): TPdfImagePixels;
const
  BYTES: array[TPdfImagePixelFormat] of integer = (3, 3, 4, 1);
var
  x, y, row, n: integer;
  r, g, b: byte;
  p: PAnsiChar;
begin
  FillCharFast(result, SizeOf(result), 0);
  result.Width := RAW_W;
  result.Height := RAW_H;
  result.Format := Format;
  n := BYTES[Format];
  row := RAW_W * n + Pad;
  SetLength(Buf, row * RAW_H);
  FillCharFast(pointer(Buf)^, length(Buf), $AA); // the padding
  for y := 0 to RAW_H - 1 do
  begin
    p := pointer(Buf);
    if BottomUp then
      inc(p, (RAW_H - 1 - y) * row)
    else
      inc(p, y * row);
    for x := 0 to RAW_W - 1 do
    begin
      r := 10 + x * 60;
      g := 20 + y * 70;
      b := 200 - x * 30 - y * 10;
      case Format of
        ipfRgb24:
          begin
            p[0] := AnsiChar(r);
            p[1] := AnsiChar(g);
            p[2] := AnsiChar(b);
          end;
        ipfBgr24, ipfBgrx32:
          begin
            p[0] := AnsiChar(b);
            p[1] := AnsiChar(g);
            p[2] := AnsiChar(r);
            if Format = ipfBgrx32 then
              p[3] := #$EE; // skipped, not alpha
          end;
        ipfIndexed8:
          p[0] := AnsiChar(x + y * RAW_W);
      end;
      inc(p, n);
    end;
  end;
  result.Size := length(Buf);
  if BottomUp then
  begin
    result.Data := PAnsiChar(pointer(Buf)) + (RAW_H - 1) * row;
    result.Stride := -row;
  end
  else
  begin
    result.Data := pointer(Buf);
    result.Stride := row;
  end;
  if Format = ipfIndexed8 then
  begin
    SetLength(result.Palette, 768);
    for x := 0 to 767 do
      result.Palette[x + 1] := AnsiChar((x * 7) and 255);
  end;
end;


{ TPdfImageRawTests }

procedure TPdfImageRawTests.PixelFormats;
var
  doc: TPdfDocument;
  buf: array[0..5] of RawByteString;
  px: TPdfImagePixels;
  names: array[0..5] of PdfString;
  b: TPdfBox;
  i: integer;
  pdf: RawByteString;
  txt, err, rgb: RawUtf8;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    for i := 0 to 5 do
    begin
      case i of
        0: px := RawPixels(ipfRgb24, buf[i]);
        1: px := RawPixels(ipfBgr24, buf[i], 2); // padded rows
        2: px := RawPixels(ipfBgrx32, buf[i]);
        3: px := RawPixels(ipfIndexed8, buf[i], 1);
        4: px := RawPixels(ipfBgr24, buf[i], 2, true); // bottom-up, as 1
      else
        begin
          px := RawPixels(ipfRgb24, buf[i]);
          px.HasColorKey := true;
          px.ColorKey := $C8140A; // R 10, G 20, B 200
          inc(PByte(px.Data)^); // other pixels, not the same image
        end;
      end;
      b := Box(40 + i * 60, 700, RAW_W * 10, RAW_H * 10);
      names[i] := doc.CreateOrGetImage(px, @b);
    end;
    pdf := SaveToString(doc);
  finally
    doc.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  // the bottom-up rows are the rows of the padded BGR image: reused
  CheckEqual(names[4], names[1], 'the same rows in another layout: one image');
  CheckEqual(CountOccurrences('/Subtype/Image', txt), 5, 'five images');
  rgb := ImageData(txt, names[0]);
  CheckEqual(length(rgb), RAW_W * RAW_H * 3, 'RGB rows');
  CheckEqual(ImageData(txt, names[1]), rgb, 'BGR padded = RGB');
  CheckEqual(ImageData(txt, names[2]), rgb, 'BGRx = RGB, x skipped');
  CheckEqual(length(ImageData(txt, names[3])), RAW_W * RAW_H, 'one index per pixel');
  CheckEqual(CountOccurrences('<00070E 151C23 ', txt), 1, 'the palette');
  CheckEqual(CountOccurrences('/Mask[10 10 20 20 200 200]', txt), 1, 'the color key');
  CheckGolden('images_raw', pdf);
end;

procedure TPdfImageRawTests.PixelReuse;
var
  doc: TPdfDocument;
  buf, buf2: RawByteString;
  px, px2: TPdfImagePixels;
  n1, n2, n3, n4, n5, n6: PdfString;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  doc := TPdfDocument.Create;
  try
    doc.AddPage;
    px := RawPixels(ipfIndexed8, buf);
    px2 := RawPixels(ipfIndexed8, buf2);
    n1 := doc.CreateOrGetImage(px);
    n2 := doc.CreateOrGetImage(px2);
    px2.Palette[1] := #1;
    n3 := doc.CreateOrGetImage(px2);
    // the same bytes as another format, or with a color key: other images
    px := RawPixels(ipfRgb24, buf);
    n5 := doc.CreateOrGetImage(px);
    px.Format := ipfBgr24;
    n6 := doc.CreateOrGetImage(px);
    Check(n6 <> n5, 'the same bytes as BGR: another image');
    px.Format := ipfRgb24;
    px.HasColorKey := true;
    n6 := doc.CreateOrGetImage(px);
    Check(n6 <> n5, 'the same bytes with a color key: another image');
    // a color key for 32-bit rows, which the TBitmap adapter never sets
    px := RawPixels(ipfBgrx32, buf);
    px.HasColorKey := true;
    px.ColorKey := $C8140A; // R 10, G 20, B 200
    Check(doc.CreateOrGetImage(px) <> '', 'BGRx with a color key');
    doc.ForceNoBitmapReuse := true;
    n4 := doc.CreateOrGetImage(px);
    pdf := SaveToString(doc);
  finally
    doc.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(CountOccurrences('/Mask[10 10 20 20 200 200]', txt), 2, 'the key of BGRx, R G B');
  Check(n1 <> '', 'named');
  CheckEqual(n2, n1, 'the same pixels in another buffer: one image');
  Check(n3 <> n1, 'another palette: another image');
  Check(n4 <> n1, 'ForceNoBitmapReuse: always a new image');
end;

procedure TPdfImageRawTests.PixelChecks;
var
  doc: TPdfDocument;
  buf: RawByteString;
  px: TPdfImagePixels;
  i: integer;
  raised: boolean;
begin
  doc := TPdfDocument.Create;
  try
    doc.AddPage;
    for i := 0 to 10 do
    begin
      if i in [4, 5, 6] then
        px := RawPixels(ipfIndexed8, buf)
      else
        px := RawPixels(ipfRgb24, buf);
      case i of
        0: px.Width := 0;
        1: px.Stride := RAW_W * 3 - 1;
        2: dec(px.Size);
        3: px.Data := nil;
        4: px.Palette := '';
        5: SetLength(px.Palette, 767);
        6: px.HasColorKey := true;
        7: px.Palette := buf; // no palette with RGB
        8: px.Stride := High(PtrInt) div 2; // (Height - 1) * Stride overflows
        10: px.Height := 0;
      else
        px.Stride := Low(PtrInt);
      end;
      raised := false;
      try
        doc.CreateOrGetImage(px);
      except
        on EPdfInvalidValue do
          raised := true;
      end;
      Check(raised, FormatString('case % raises', [i]));
    end;
  finally
    doc.Free;
  end;
end;

procedure TPdfImageRawTests.JpegData;
var
  doc: TPdfDocument;
  img: TPdfImage;
  name1, name2: PdfString;
  b: TPdfBox;
  pdf: RawByteString;
  txt, err: RawUtf8;
  jpg: RawByteString;
  raised: boolean;
begin
  // not decoded by the engine: written as it is - SOI, text, EOI
  jpg := 'xxxxengine-opaquexx';
  jpg[1] := AnsiChar($FF);
  jpg[2] := AnsiChar($D8);
  jpg[3] := AnsiChar($FF);
  jpg[4] := AnsiChar($E0);
  jpg[18] := AnsiChar($FF);
  jpg[19] := AnsiChar($D9);
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    // in the xref from its constructor, or added by RegisterImage
    img := TPdfImage.CreateJpeg(doc, pointer(jpg), length(jpg), 8, 6, false);
    name1 := doc.RegisterImage(img);
    img := TPdfImage.CreateJpeg(doc, pointer(jpg), length(jpg), 8, 6, true);
    name2 := doc.RegisterImage(img);
    CheckEqual(doc.RegisterImage(img), name2, 'registered twice: its name');
    b := Box(40, 700, 80, 60);
    doc.DrawImage(name1, @b);
    b := Box(140, 700, 80, 60);
    doc.DrawImage(name2, @b);
    pdf := SaveToString(doc);
  finally
    doc.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  Check(name1 <> name2, 'two names');
  raised := false;
  try
    TPdfImage.CreateJpeg(nil, nil, 0, 8, 6, false); // raises before the xref
  except
    on EPdfInvalidValue do
      raised := true;
  end;
  Check(raised, 'no JPEG data raises');
  CheckEqual(CountOccurrences('/ColorSpace/DeviceRGB', txt), 2, 'RGB');
  CheckEqual(CountOccurrences(jpg, txt), 2, 'the data as it is');
  CheckGolden('images_jpegdata', pdf);
end;

type
  // a form XObject that lists one font, as TPdfForm does once rendered
  TFontListForm = class(TPdfFormXObject)
  public
    constructor Create(aDoc: TPdfDocument; aFont: TPdfFont);
  end;

constructor TFontListForm.Create(aDoc: TPdfDocument; aFont: TPdfFont);
var
  res: TPdfDictionary;
begin
  inherited Create(aDoc, true);
  res := TPdfDictionary.Create(nil);
  fFontList := TPdfDictionary.Create(nil);
  fFontList.AddItem(aFont.ShortCut, aFont.Data);
  res.AddItem('Font', fFontList);
  fAttributes.AddItem('Type', 'XObject');
  fAttributes.AddItem('Subtype', 'Form');
  fAttributes.AddItem('BBox', TPdfArray.Create(nil, [0, 0, 100, 100]));
  fAttributes.AddItem('Resources', res);
end;

// a page that draws a TPdfFormXObject lists the fonts of the form
procedure TPdfImageRawTests.FormFonts;
var
  doc: TPdfDocument;
  font: TPdfFont;
  key: PdfString;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    font := doc.Canvas.SetFont('Courier', 10, []);
    doc.AddXObject('FontForm', TFontListForm.Create(doc, font));
    doc.AddPage; // no font yet
    doc.Canvas.DrawXObject(40, 600, 100, 100, 'FontForm');
    key := font.ShortCut;
    pdf := SaveToString(doc);
  finally
    doc.Free; // the page and the form each own their reference to the font
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  // the first page, the form, and the second page once it drew the form
  CheckEqual(CountOccurrences('/Font<</' + key + ' ', txt), 3, 'listed by both pages');
end;

// TPdfFormWithCanvas: an image and a transparency drawn on its canvas need the
// XObject and ExtGState resources of the form
procedure TPdfImageRawTests.FormWithCanvasImage;
var
  doc: TPdfDocument;
  form: TPdfFormWithCanvas;
  buf: RawByteString;
  img: PdfString;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.CompressionMethod := cmNone;
    doc.AddPage;
    img := doc.CreateOrGetImage(RawPixels(ipfRgb24, buf));
    form := TPdfFormWithCanvas.Create(doc, 200, 100);
    form.Canvas.SetFillAlpha(0.5);
    form.Canvas.DrawXObject(10, 10, 40, 30, img);
    form.CloseCanvas;
    doc.AddXObject('FormC', form);
    doc.Canvas.DrawXObject(40, 600, 1, 1, 'FormC');
    pdf := SaveToString(doc);
  finally
    doc.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  Check(PosEx('/' + img + ' Do', txt) > 0, 'the image drawn in the form');
  CheckEqual(CountOccurrences('<</' + img + ' ', txt), 1, 'listed by the form');
  CheckEqual(CountOccurrences('/Fca50<<', txt), 1, 'the alpha of the form');
end;

{$ifdef PDF_HASVCLCANVAS}

const
  // every row a multiple of four bytes, even at one bit per pixel: the reuse
  // hash reads padded rows, a shorter LCL row would be read past its end
  IMG_W = 32;
  IMG_H = 4;

// the pixel bytes of each row, from Seed - set after the palette, which the
// VCL may apply by remapping the pixels already there
procedure FillBitmap(B: TBitmap; Seed: byte);
var
  x, y, n: integer;
  {$ifndef FPC}
  W: integer;
  {$endif FPC}
  p: PByteArray;
begin
  {$ifdef FPC}
  // the row as the widgetset holds it: pf24bit is 32-bit on GTK2 and Cocoa
  n := B.RawImage.Description.BytesPerLine;
  B.BeginUpdate(true);
  {$else}
  W := B.Width;
  case B.PixelFormat of
    pf1bit:
      n := W shr 3;
    pf4bit:
      n := W shr 1;
    pf8bit:
      n := W;
    pf24bit:
      n := W * 3;
  else
    n := W * 4;
  end;
  {$endif FPC}
  for y := 0 to B.Height - 1 do
  begin
    p := B.ScanLine[y];
    for x := 0 to n - 1 do
      p[x] := byte(Seed + x * 37 + y * 101);
  end;
  {$ifdef FPC}
  B.EndUpdate;
  {$endif FPC}
end;

function NewBitmap(Format: TPixelFormat; Seed: byte; W: integer = IMG_W): TBitmap;
begin
  result := TBitmap.Create;
  result.PixelFormat := Format;
  result.Width := W;
  result.Height := IMG_H;
  FillBitmap(result, Seed);
end;

{ TPdfImageGoldenTests }

function TPdfImageGoldenTests.SaveDoc(Doc: TPdfDocument): RawByteString;
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

// the rows of B as the image stream must hold them: R, G, B of each pixel -
// on the LCL as its own reader TLazIntfImage sees them, whatever the layout
// (GTK2 and Cocoa hold 32 bits per pixel, Cocoa A,R,G,B), on the VCL read
// from ScanLine[], Bytes bytes per pixel, B, G, R first
function ScanRgb(B: TBitmap; Bytes: integer): RawByteString;
var
  x, y: integer;
  {$ifdef FPC}
  img: TLazIntfImage;
  {$else}
  p: PByteArray;
  {$endif FPC}
  d: PAnsiChar;
begin
  {$ifdef FPC}
  SetLength(result, B.Width * B.Height * 3);
  d := pointer(result);
  img := TLazIntfImage.Create(B.RawImage, {DataOwner=}false);
  try
    for y := 0 to B.Height - 1 do
      for x := 0 to B.Width - 1 do
      begin
        d[0] := AnsiChar(img.Colors[x, y].red shr 8);
        d[1] := AnsiChar(img.Colors[x, y].green shr 8);
        d[2] := AnsiChar(img.Colors[x, y].blue shr 8);
        inc(d, 3);
      end;
  finally
    img.Free;
  end;
  exit;
  {$endif FPC}
  {$ifndef FPC}
  SetLength(result, B.Width * B.Height * 3);
  d := pointer(result);
  for y := 0 to B.Height - 1 do
  begin
    p := B.ScanLine[y];
    for x := 0 to B.Width - 1 do
    begin
      d[0] := AnsiChar(p[x * Bytes + 2]);
      d[1] := AnsiChar(p[x * Bytes + 1]);
      d[2] := AnsiChar(p[x * Bytes]);
      inc(d, 3);
    end;
  end;
  {$endif FPC}
end;

// true when S is not empty and holds the two byte values A and B only
function OnlyBytes(const S: RawByteString; A, B: byte): boolean;
var
  i: PtrInt;
begin
  result := S <> '';
  for i := 1 to length(S) do
    if not (ord(S[i]) in [A, B]) then
      result := false;
end;

function ScanIndexes(B: TBitmap): RawByteString;
var
  y: integer;
begin
  SetLength(result, B.Width * B.Height);
  for y := 0 to B.Height - 1 do
    MoveFast(B.ScanLine[y]^, PByteArray(result)[y * B.Width], B.Width);
end;

procedure TPdfImageGoldenTests.BitmapFormats;
var
  doc: TPdfDocument;
  bmp: array[0..5] of TBitmap;
  names: array[0..6] of PdfString;
  b, c: TPdfBox;
  pdf: RawByteString;
  txt, err: RawUtf8;
  i, raised: integer;
  rgb24, rgb32, idx8, empty: RawByteString;
  none: PdfString;
  e: TBitmap;
begin
  raised := 0;
  FillCharFast(bmp, SizeOf(bmp), 0);
  FillCharFast(names, SizeOf(names), 0);
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    bmp[0] := NewBitmap(pf24bit, 1);
    bmp[1] := NewBitmap(pf32bit, 2);
    bmp[2] := NewBitmap(pf8bit, 3);
    bmp[3] := NewBitmap(pf4bit, 4);
    bmp[4] := NewBitmap(pf1bit, 5);
    // a fixed transparent color: /Mask with the color as its range
    bmp[5] := NewBitmap(pf24bit, 6);
    bmp[5].TransparentColor := $0000FF;
    bmp[5].TransparentMode := tmFixed;
    for i := 0 to 5 do
    begin
      b := Box(40, 700 - i * 60, IMG_W * 4, IMG_H * 8);
      try
        names[i] := CreateOrGetBitmapImage(doc, bmp[i], @b);
      except
        on EPdfInvalidValue do
          inc(raised);
      end;
    end;
    // the same pixels again, drawn clipped: one image, two draws
    b := Box(300, 700, IMG_W * 4, IMG_H * 8);
    c := Box(310, 700, IMG_W * 2, IMG_H * 8);
    names[6] := CreateOrGetBitmapImage(doc, bmp[0], @b, @c);
    // an empty bitmap gives no image
    e := TBitmap.Create;
    try
      none := CreateOrGetBitmapImage(doc, e, @b);
    finally
      e.Free;
    end;
    // what the streams must hold: the ScanLine[] rows, top first, B G R
    // swapped - the bytes the golden file holds as well, checked without it
    rgb24 := ScanRgb(bmp[0], 3);
    rgb32 := ScanRgb(bmp[1], 4);
    idx8 := ScanIndexes(bmp[2]);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    for i := 0 to 5 do
      bmp[i].Free;
  end;
  empty := '';
  CheckEqual(none, empty, 'an empty bitmap: no image');
  Check(names[6] = names[0], 'same bitmap, same image');
  Check((names[0] <> names[1]) and (names[1] <> names[5]), 'one image per bitmap');
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  // the LCL: gray bitmaps, indexed with a gray ramp; the VCL: their palette
  CheckEqual(raised, 0, 'every format embedded');
  CheckEqual(CountOccurrences('/Subtype/Image', txt), 6, 'six images');
  CheckEqual(CountOccurrences('/Indexed', txt), 3, 'the 1, 4 and 8 bit formats indexed');
  CheckEqual(CountOccurrences('/Mask', txt), 1, 'the color key');
  Check(ImageData(txt, names[0]) = rgb24, 'pf24bit: the rows, RGB');
  Check(ImageData(txt, names[1]) = rgb32, 'pf32bit: the rows, RGB, x skipped');
  Check(ImageData(txt, names[2]) = idx8, 'pf8bit: the index bytes');
  {$ifdef FPC}
  CheckEqual(CountOccurrences('<000000 010101 020202 ', txt), 3, 'a gray ramp each');
  Check(OnlyBytes(ImageData(txt, names[4]), 0, 255), 'pf1bit: black or white');
  {$else}
  Check(true, 'SKIP: the VCL writes the palette of the bitmap');
  Check(true, 'SKIP: the VCL indexes pf1bit by its palette');
  {$endif FPC}
  CheckGolden('images_bitmap', pdf);
end;

{$ifndef FPC}
// a 256 entry palette: a gray ramp, or the same ramp reversed
function NewPalette(Reversed: boolean): HPALETTE;
var
  pal: TMaxLogPalette;
  i: integer;
  v: byte;
begin
  pal.palVersion := $300;
  pal.palNumEntries := 256;
  for i := 0 to 255 do
  begin
    v := i;
    if Reversed then
      v := 255 - i;
    pal.palPalEntry[i].peRed := v;
    pal.palPalEntry[i].peGreen := v;
    pal.palPalEntry[i].peBlue := v;
    pal.palPalEntry[i].peFlags := 0;
  end;
  result := CreatePalette(PLogPalette(@pal)^);
end;
{$endif FPC}

// what the reuse hash covers: the palette, and the padding of each row - the
// VCL only, as the LCL has no palette for an indexed bitmap and its rows of a
// width not a multiple of four need not be padded
procedure TPdfImageGoldenTests.BitmapReuse;
var
  {$ifndef FPC}
  doc: TPdfDocument;
  bmp: array[0..4] of TBitmap;
  names: array[0..4] of PdfString;
  {$endif FPC}
  i: integer;
begin
  {$ifdef FPC}
  for i := 1 to 5 do
    Check(true, 'SKIP: the LCL gives indexed bitmaps no palette');
  {$else}
  FillCharFast(bmp, SizeOf(bmp), 0);
  doc := TPdfDocument.Create;
  try
    doc.AddPage;
    // the same indices: with the same palette, then with the reversed one
    for i := 0 to 2 do
    begin
      bmp[i] := NewBitmap(pf8bit, 0);
      bmp[i].Palette := NewPalette(i = 2);
      FillBitmap(bmp[i], 11);
    end;
    Check(CompareMem(bmp[0].ScanLine[1], bmp[2].ScanLine[1], IMG_W),
      'the same indices under both palettes');
    // a width of 30 pixels: 90 bytes of a row, then 2 of padding
    bmp[3] := NewBitmap(pf24bit, 12, 30);
    bmp[4] := NewBitmap(pf24bit, 12, 30);
    PByteArray(bmp[4].ScanLine[0])[90] := $55;
    for i := 0 to 4 do
      names[i] := CreateOrGetBitmapImage(doc, bmp[i]);
  finally
    doc.Free;
    for i := 0 to 4 do
      bmp[i].Free;
  end;
  Check(names[1] = names[0], 'same indices, same palette: one image');
  Check(names[2] <> names[0], 'another palette: another image');
  Check(names[3] <> '', 'padded rows');
  Check(names[4] <> names[3], 'the padding is hashed');
  {$endif FPC}
end;

// BitmapHash reads each row as long as the framework holds it: a DIB row on the
// VCL, BytesPerLine on the LCL - a pf1bit row of 10 pixels is 2 bytes there,
// where the DIB formula reads 4, past the end of the last row
function RowHash(B: TBitmap): THash128Rec;
var
  y, row: integer;
begin
  FillZero(result.b);
  {$ifdef FPC}
  row := B.RawImage.Description.BytesPerLine;
  {$else}
  case B.PixelFormat of
    pf1bit:
      row := ((B.Width + 31) and not 31) shr 3;
  else
    row := ((B.Width * 8 + 31) and not 31) shr 3;
  end;
  {$endif FPC}
  for y := 0 to B.Height - 1 do
    result.c[y and 3] := crc32c(result.c[y and 3], B.ScanLine[y], row);
end;

// the reuse key: the same pixels with a color key are another image, unless
// the key writes no /Mask; a width whose rows the LCL does not pad to four
// bytes is hashed as the LCL holds it
procedure TPdfImageGoldenTests.BitmapKeys;
var
  doc: TPdfDocument;
  b1, b2, b3, b4: TBitmap;
  n1, n2, n3, n4, n5, n6, n7: PdfString;
  pf: TPixelFormat;
  h1, h2: THash128Rec;
begin
  b1 := NewBitmap(pf24bit, 21);
  b2 := NewBitmap(pf24bit, 21);
  b3 := NewBitmap(pf24bit, 22, 10);
  b4 := NewBitmap(pf32bit, 23);
  doc := TPdfDocument.Create;
  try
    doc.AddPage;
    n1 := CreateOrGetBitmapImage(doc, b1);
    b2.TransparentColor := $0000FF;
    b2.TransparentMode := tmFixed;
    n2 := CreateOrGetBitmapImage(doc, b2);
    n3 := CreateOrGetBitmapImage(doc, b3);
    n4 := CreateOrGetBitmapImage(doc, b3);
    b3.Free;
    b3 := NewBitmap(pf24bit, 22, 10);
    n5 := CreateOrGetBitmapImage(doc, b3);
    // pf32bit writes no /Mask: its color key is no reason for another image
    n6 := CreateOrGetBitmapImage(doc, b4);
    b4.TransparentColor := $0000FF;
    b4.TransparentMode := tmFixed;
    n7 := CreateOrGetBitmapImage(doc, b4);
  finally
    doc.Free;
    b1.Free;
    b2.Free;
    b3.Free;
    b4.Free;
  end;
  Check(n2 <> n1, 'the same pixels with a color key: another image');
  CheckEqual(n4, n3, 'a width of 10 pixels: the same bitmap, one image');
  CheckEqual(n5, n3, 'the same pixels in another bitmap: one image');
  CheckEqual(n7, n6, 'pf32bit: the color key changes nothing');
  // four rows of 10 pixels, 1 and 8 bits: the row length of the framework -
  // lanes 1 to 3 hold rows only (lane 0 the palette of the VCL first)
  for pf := pf1bit to pf8bit do
    if pf <> pf4bit then
    begin
      b1 := TBitmap.Create;
      try
        b1.PixelFormat := pf;
        b1.Width := 10;
        b1.Height := 4;
        h1 := BitmapHash(b1);
        h2 := RowHash(b1);
        Check((h1.c1 = h2.c1) and (h1.c2 = h2.c2) and (h1.c3 = h2.c3),
          'the rows of the framework, no more');
      finally
        b1.Free;
      end;
    end;
end;

// a "W 0 0 H X Y cm" operator in Text, the numbers compared as numbers: their
// digits differ between the 32-bit and the 64-bit compilers
function HasMatrix(const Text: RawUtf8; W, H, X, Y: double): boolean;
var
  p, e, b, i: PtrInt;
  v: array[0..5] of double;
  line: RawUtf8;
  P2: PUtf8Char;
begin
  result := true;
  p := PosEx(' cm', Text);
  while p > 0 do
  begin
    b := p;
    while (b > 1) and not (Text[b - 1] in [#10, #13]) do
      dec(b);
    line := copy(Text, b, p - b);
    P2 := pointer(line);
    for i := 0 to 5 do
      v[i] := GetExtended(pointer(GetNextItem(P2, ' ')));
    if (Abs(v[0] - W) < 0.01) and (v[1] = 0) and (v[2] = 0) and
       (Abs(v[3] - H) < 0.01) and (Abs(v[4] - X) < 0.01) and
       (Abs(v[5] - Y) < 0.01) then
      exit;
    e := p + 3;
    p := PosEx(' cm', Text, e);
  end;
  result := false;
end;

// TPdfVclCanvas.Draw and StretchDraw: placement, reuse, a graphic that is no
// TBitmap, and the graphics that draw nothing
procedure TPdfImageGoldenTests.BitmapBridge;
var
  doc: TPdfDocumentVcl;
  c: TPdfVclCanvas;
  bmp, empty: TBitmap;
  jpg: TJpegImage;
  r: TRect; // as the bridge declares it: mormot.pdf's on FPC
  ms: TMemoryStream;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  bmp := NewBitmap(pf24bit, 9);
  empty := TBitmap.Create;
  ms := TMemoryStream.Create;
  jpg := TJpegImage.Create;
  doc := TPdfDocumentVcl.Create;
  try
    // decoded from its bytes: other pixels than the bitmap's
    jpg.Assign(bmp);
    jpg.SaveToStream(ms);
    jpg.Free;
    jpg := TJpegImage.Create;
    ms.Position := 0;
    jpg.LoadFromStream(ms);
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.StandardFontsReplace := true;
    doc.ScreenLogPixels := 96; // 3/4 pt per pixel
    doc.AddPage;
    c := doc.VclCanvas;
    c.Draw(40, 40, bmp);
    c.Draw(200, 40, bmp); // the same bitmap: one image drawn twice
    r.Left := 40;
    r.Top := 120;
    r.Right := 40 + IMG_W * 4;
    r.Bottom := 120 + IMG_H * 8;
    c.StretchDraw(r, bmp);
    c.Draw(40, 200, nil);
    c.Draw(40, 200, empty);
    c.StretchDraw(r, nil);
    c.StretchDraw(r, empty);
    c.Draw(40, 260, jpg); // converted to a bitmap of its own
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    jpg.Free;
    ms.Free;
    empty.Free;
    bmp.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOccurrences('/Subtype/Image', txt), 2, 'the bitmap once, the JPEG once');
  CheckEqual(CountOccurrences(' Do', txt), 4, 'four drawn');
  // 3/4 pt per pixel, Y from the top of the 842 pt page
  Check(HasMatrix(txt, 24, 3, 30, 809), 'Draw: 32 x 4 px at 40, 40');
  Check(HasMatrix(txt, 24, 3, 150, 809), 'Draw: at 200, 40');
  Check(HasMatrix(txt, 96, 24, 30, 728), 'StretchDraw: 128 x 32 px at 40, 120');
  CheckGolden('images_bridge', pdf);
end;

procedure TPdfImageGoldenTests.BitmapJpeg;
var
  doc: TPdfDocument;
  bmp: TBitmap;
  jpg: TJpegImage;
  ms: TMemoryStream;
  img: TPdfImage;
  b: TPdfBox;
  pdf, encoded: RawByteString;
  txt, err: RawUtf8;
begin
  ms := TMemoryStream.Create;
  bmp := NewBitmap(pf24bit, 7);
  doc := TPdfDocument.Create;
  try
    // encoded once, then fed back: the passthrough and the direct way
    jpg := TJpegImage.Create;
    try
      jpg.Assign(bmp);
      jpg.SaveToStream(ms);
    finally
      jpg.Free;
    end;
    FastSetRawByteString(encoded, ms.Memory, ms.Size);
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    // CreateOrGetBitmapImage with ForceJPEGCompression: the bitmap recompressed,
    // with a quality other than TJpegImage's default of 80
    doc.ForceJPEGCompression := 37;
    b := Box(40, 700, IMG_W * 4, IMG_H * 8);
    CreateOrGetBitmapImage(doc, bmp, @b);
    // a TJpegImage without ForceJPEGCompression: its bytes as they are
    doc.ForceJPEGCompression := 0;
    ms.Position := 0;
    jpg := TJpegImage.Create;
    try
      jpg.LoadFromStream(ms);
      img := CreateGraphicImage(doc, jpg, false);
    finally
      jpg.Free;
    end;
    doc.RegisterXObject(img, 'JpgPass');
    doc.Canvas.DrawXObject(40, 600, IMG_W * 4, IMG_H * 8, 'JpgPass');
    // CreateJpegDirect: no graphics unit involved
    img := TPdfImage.CreateJpegDirect(doc, ms, false);
    doc.RegisterXObject(img, 'JpgDirect');
    doc.Canvas.DrawXObject(40, 500, IMG_W * 4, IMG_H * 8, 'JpgDirect');
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    bmp.Free;
    ms.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOccurrences('/DCTDecode', txt), 3, 'three JPEG images');
  Check(ImageData(txt, 'JpgDirect') = encoded, 'CreateJpegDirect: the bytes');
  {$ifdef OSWINDOWS}
  // GDI+: SaveInternalToStream writes the bytes it was loaded from
  Check(ImageData(txt, 'JpgPass') = encoded, 'passed through: the bytes');
  {$else}
  Check(true, 'SKIP: the LCL may encode a TJpegImage again');
  {$endif OSWINDOWS}
  CheckGolden('images_jpeg', pdf);
end;

procedure TPdfImageGoldenTests.BitmapJpegKey;
var
  doc: TPdfDocument;
  plain, keyed: TBitmap;
  b: TPdfBox;
  txt, err: RawUtf8;
begin
  { ForceJPEGCompression made a JPEG of a bitmap with a colour key too: the
    /Mask was lost, and the key colour altered (synopse/mORMot2#686) }
  plain := NewBitmap(pf24bit, 7);
  keyed := NewBitmap(pf24bit, 8);
  doc := TPdfDocument.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.StandardFontsReplace := true;
    doc.ForceJPEGCompression := 80;
    doc.AddPage;
    b := Box(40, 700, IMG_W * 4, IMG_H * 8);
    CreateOrGetBitmapImage(doc, plain, @b);
    keyed.TransparentColor := $0000FF;
    keyed.TransparentMode := tmFixed;
    b := Box(40, 600, IMG_W * 4, IMG_H * 8);
    CreateOrGetBitmapImage(doc, keyed, @b);
    txt := NormalizePdf(SaveDoc(doc), err);
  finally
    doc.Free;
    plain.Free;
    keyed.Free;
  end;
  CheckEqual(err, '');
  CheckEqual(CountOccurrences('/DCTDecode', txt), 1, 'the bitmap without a key');
  CheckEqual(CountOccurrences('/Mask', txt), 1, 'the colour key kept');
end;

{$ifdef OSWINDOWS}

// drawn the same into a TPdfDocumentGdi page and into a TMetaFile
procedure DrawSample(C: TCanvas);
var
  bmp: TBitmap;
begin
  C.Font.Name := 'Arial';
  C.Font.Size := 14;
  C.Font.Style := [fsBold];
  C.Font.Color := clNavy;
  C.TextOut(40, 30, 'Metafile text');
  C.Font.Style := [];
  C.Font.Size := 10;
  C.TextOut(40, 60, 'Second line, plain');
  C.Pen.Color := clRed;
  C.Pen.Width := 2;
  C.Brush.Color := clYellow;
  C.Rectangle(40, 90, 200, 160);
  C.Brush.Color := clAqua;
  C.Ellipse(220, 90, 380, 160);
  C.Pen.Width := 1;
  C.Pen.Color := clBlack;
  C.Polygon([Types.Point(40, 200), Types.Point(120, 180),
    Types.Point(200, 230)]);
  C.MoveTo(40, 250);
  C.LineTo(380, 250);
  bmp := NewBitmap(pf24bit, 9);
  try
    C.StretchDraw(Types.Rect(40, 270, 168, 302), bmp);
  finally
    bmp.Free;
  end;
end;

procedure TPdfImageGoldenTests.MetaFileCanvas;
var
  doc: TPdfDocumentGdi;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  doc := TPdfDocumentGdi.Create(true);
  try
    CheckEqual(doc.ScreenLogPixels, GdiScreenLogPixels, 'the screen');
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    DrawSample(doc.VclCanvas);
    GdiCommentOutline(doc.VclCanvas.Handle, 'First page', 0);
    GdiCommentBookmark(doc.VclCanvas.Handle, 'page1');
    doc.AddPage;
    DrawSample(doc.VclCanvas);
    GdiCommentLink(doc.VclCanvas.Handle, 'page1',
      {$ifdef FPC}mormot.pdf.{$else}Types.{$endif}Rect(40, 30, 200, 50), false);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOccurrences('/Type/Page/', txt) + CountOccurrences('/Type/Page>>', txt), 2,
    'two pages');
  Check(PosEx('/Outlines', txt) > 0, 'the outline comment');
  CheckEqual(CountOccurrences('/Subtype/Image', txt), 1, 'the same bitmap on both pages');
  CheckGolden('emf_canvas', pdf);
end;

procedure TPdfImageGoldenTests.MetaFileRender;
var
  doc: TPdfDocumentGdi;
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  mf := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    mf.Width := 400;
    mf.Height := 320;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      DrawSample(mc);
    finally
      mc.Free;
    end;
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    // RenderMetaFile into the page, twice - TPdfForm: MetaFileForm
    doc.AddPage;
    RenderMetaFile(doc.Canvas, mf, 1, 1, 20, 0);
    doc.AddPage;
    RenderMetaFile(doc.Canvas, mf, 0.5, 0.5, 40, 200);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    mf.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOccurrences('/Type/Page/', txt) + CountOccurrences('/Type/Page>>', txt), 2,
    'two pages');
  CheckEqual(CountOccurrences('/Subtype/Image', txt), 1, 'the bitmap, reused');
  CheckGolden('emf_render', pdf);
end;

// TPdfForm of a metafile: before the first page (no canvas state to come back
// to) and in the middle of one; the metafile's bitmap and fonts end in the
// form, its bookmark comment is left out
procedure TPdfImageGoldenTests.MetaFileForm;
var
  doc: TPdfDocumentGdi;
  mf, mfb: TMetaFile;
  mc: TMetaFileCanvas;
  pdf: RawByteString;
  txt, err: RawUtf8;
  w, h: integer;
begin
  mf := TMetaFile.Create;
  mfb := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    mf.Width := 400;
    mf.Height := 320;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      DrawSample(mc);
    finally
      mc.Free;
    end;
    mfb.Width := 200;
    mfb.Height := 100;
    mc := TMetaFileCanvas.Create(mfb, 0);
    try
      mc.Font.Name := 'Arial';
      mc.Font.Size := 12;
      mc.TextOut(10, 10, 'Form with a bookmark comment');
      GdiCommentBookmark(mc.Handle, 'inform');
    finally
      mc.Free;
    end;
    w := mf.Width;
    h := mf.Height;
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddXObject('Frm1', TPdfForm.Create(doc, mf));
    doc.AddPage; // used the freed page of the form before
    doc.Canvas.DrawXObject(40, 400, 1, 1, 'Frm1');
    doc.AddXObject('Frm2', TPdfForm.Create(doc, mfb));
    doc.Canvas.DrawXObject(40, 300, 0.5, 0.5, 'Frm2');
    doc.Canvas.SetFont('Helvetica', 10, []);
    doc.Canvas.TextOut(40, 250, 'After the form');
    doc.AddPage;
    doc.Canvas.DrawXObject(40, 300, 0.5, 0.5, 'Frm1');
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    mfb.Free;
    mf.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  CheckEqual(CountOccurrences('/Type/Page/', txt) + CountOccurrences('/Type/Page>>', txt), 2,
    'two pages');
  CheckEqual(CountOccurrences('/Subtype/Form', txt), 2, 'two forms');
  // the size TMetaFile reports, in pixels of the reference DC (its DPI)
  CheckEqual(CountOccurrences(FormatUtf8('/BBox[0 0 % %]', [w, h]), txt), 1,
    'the size of the metafile');
  CheckEqual(CountOccurrences('/Subtype/Image', txt), 1, 'the bitmap, in the form');
  Check(PosEx('(After the form)', txt) > 0, 'the page goes on after the form');
  Check(PosEx('inform', txt) = 0, 'no bookmark from a form');
  CheckGolden('emf_form', pdf);
end;

// the marked content of each stream - page or form - closed in that stream
function BalancedStreams(const Txt: RawUtf8): boolean;
var
  i, j: PtrInt;
  s: RawUtf8;
begin
  result := false;
  i := PosEx('stream'#10, Txt);
  while i > 0 do
  begin
    j := PosEx(#10'endstream', Txt, i);
    if j = 0 then
      exit;
    s := copy(Txt, i + 7, j - i - 7);
    if CountOccurrences(' BMC', s) + CountOccurrences(' BDC', s) <> CountOccurrences('EMC', s) then
      exit;
    i := PosEx('stream'#10, Txt, j + 10);
  end;
  result := true;
end;

// what the document canvas was doing before a form is built goes on after it:
// a path open on a tagged page, the right-to-left switch; and the optional
// content of a form keeps its /Properties
procedure TPdfImageGoldenTests.MetaFileFormState;
var
  doc: TPdfDocumentGdi;
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  grp: TPdfOptionalContentGroup;
  pdf: RawByteString;
  txt, err: RawUtf8;
  rtl: boolean;
  previous: IFontProvider;
  text: PdfString;
  saved, cur: TPdfTextStateSavedDynArray;
  depth, i: integer;
  kept: boolean;
begin
  mf := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    mf.Width := 100;
    mf.Height := 50;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      mc.MoveTo(5, 5);
      mc.LineTo(90, 40);
      mc.Font.Name := 'Arial';
      mc.TextOut(5, 20, 'Text sets the direction'); // RightToLeftText of the canvas
    finally
      mc.Free;
    end;
    doc.Tagged := true;
    doc.AddPage;
    doc.Canvas.MoveTo(10, 10);
    doc.Canvas.RightToLeftText := true;
    doc.AddXObject('FrmT', TPdfForm.Create(doc, mf));
    rtl := doc.Canvas.RightToLeftText;
    doc.Canvas.LineTo(100, 100);
    doc.Canvas.Stroke;
    doc.Canvas.RightToLeftText := false;
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    mf.Free;
  end;
  Check(rtl, 'the right-to-left switch of the page kept');
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  Check(BalancedStreams(txt), 'each stream closes its own marked content');
  mf := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    doc.UseOptionalContent := true;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    grp := doc.CreateOptionalContentGroup(nil, 'Layer', true);
    mf.Width := 100;
    mf.Height := 50;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      GdiCommentBeginMarkContent(mc.Handle, grp);
      mc.Rectangle(5, 5, 60, 30);
      GdiCommentEndMarkContent(mc.Handle);
    finally
      mc.Free;
    end;
    doc.AddXObject('FrmL', TPdfForm.Create(doc, mf));
    doc.Canvas.DrawXObject(40, 400, 1, 1, 'FrmL');
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    mf.Free;
  end;
  txt := NormalizePdf(pdf, err);
  CheckEqual(err, '');
  Check(PosEx('/OC /oc', txt) > 0, 'the layer drawn in the form');
  Check(PosEx('<</oc', txt) > 0, 'its /Properties kept with the form');
  // a form drawn between a q and its Q of the page keeps the text state the
  // q saved: the word spacing of the CFF text after the Q
  previous := SwapInFakeFace(FakeRoutingFace);
  mf := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    doc.AddTrueTypeFont(FAKE_FACE);
    doc.AddPage;
    mf.Width := 100;
    mf.Height := 50;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      mc.Rectangle(5, 5, 60, 30);
    finally
      mc.Free;
    end;
    doc.Canvas.SetFont(FAKE_FACE, 12, [], 1);
    doc.Canvas.SetWordSpace(6);
    doc.Canvas.GSave;
    saved := Copy(TPdfCanvasPeek(doc.Canvas).fTextStateSaved);
    depth := TPdfCanvasPeek(doc.Canvas).fGStateDepth;
    doc.AddXObject('FrmW', TPdfForm.Create(doc, mf));
    kept := length(TPdfCanvasPeek(doc.Canvas).fTextStateSaved) >= depth;
    cur := TPdfCanvasPeek(doc.Canvas).fTextStateSaved;
    for i := 0 to depth - 1 do
      if kept and
         ((cur[i].Font <> saved[i].Font) or
          (cur[i].FontSize <> saved[i].FontSize) or
          (cur[i].WordSpace <> saved[i].WordSpace)) then
        kept := false;
    doc.Canvas.GRestore;
    doc.Canvas.BeginText;
    doc.Canvas.MoveTextPoint(40, 700);
    text := 'Wi Wi';
    doc.Canvas.ShowText(text);
    doc.Canvas.EndText;
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    mf.Free;
    FontProvider := previous;
  end;
  Check(kept, 'the text states the q of the page saved, untouched by the form');
  Check(PosEx('[<00880087008C> -500 <00880087>] TJ', InflatePdf(pdf)) > 0,
    'the word spacing of the page after the form');
end;

const
  // the record types, by number: the windows unit of FPC lacks some names
  R_POLYPOLYLINE = 7;
  R_SAVEDC = 33;
  R_SELECTOBJECT = 37;
  R_RESTOREDC = 34;
  R_CREATEBRUSHINDIRECT = 39;
  R_STRETCHDIBITS = 81;
  R_EXTTEXTOUTA = 83;
  R_EXTTEXTOUTW = 84;
  R_POLYPOLYLINE16 = 90;
  R_EXTCREATEPEN = 95;
  R_POLYPOLYGON16 = 91;
  R_ALPHABLEND = 114;

type
  // sets the printer resolution a metafile is rendered with
  TPdfDocumentGdiAccess = class(TPdfDocumentGdi);

// AlphaBlend under its gdi32 name: the windows unit of FPC lacks it
function GdiAlphaBlend(Dest: HDC; X, Y, W, H: integer; Src: HDC;
  XS, YS, WS, HS: integer; Blend: DWord): BOOL; stdcall; external 'gdi32.dll';

// the bytes of a metafile, as GetEnhMetaFileBits gives them
function EmfBytes(Mf: TMetaFile): RawByteString;
var
  n: cardinal;
begin
  n := GetEnhMetaFileBits(Mf.Handle, 0, nil);
  SetLength(result, n);
  if n > 0 then
    GetEnhMetaFileBits(Mf.Handle, n, pointer(result));
end;

// the offsets of the records of type RecType in the bytes of a metafile
function EmfRecords(const Bytes: RawByteString; RecType: cardinal): TIntegerDynArray;
var
  o, n: PtrInt;
begin
  result := nil;
  o := 0;
  while o + 8 <= length(Bytes) do
  begin
    if PCardinal(@PByteArray(Bytes)[o])^ = RecType then
    begin
      n := length(result);
      SetLength(result, n + 1);
      result[n] := o;
    end;
    n := PCardinal(@PByteArray(Bytes)[o + 4])^;
    if n < 8 then
      break;
    inc(o, n);
  end;
end;

// the metafile rendered into one page, the PDF normalized and inflated
function RenderedEmf(Mf: TMetaFile; PxX: integer = 0; PxY: integer = 0;
  TextClipping: TPdfCanvasRenderMetaFileTextClipping = tcAlwaysClip;
  ScaleX: single = 1; ScaleY: single = 1): RawUtf8;
var
  doc: TPdfDocumentGdi;
  ms: TMemoryStream;
  pdf: RawByteString;
  err: RawUtf8;
begin
  ms := TMemoryStream.Create;
  doc := TPdfDocumentGdi.Create;
  try
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.ScreenLogPixels := 96; // the coordinates the checks expect, any screen
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    TPdfDocumentGdiAccess(doc).fPrinterPxPerInch.X := PxX;
    TPdfDocumentGdiAccess(doc).fPrinterPxPerInch.Y := PxY;
    doc.AddPage;
    RenderMetaFile(doc.Canvas, Mf, ScaleX, ScaleY, 0, 0,
      tpSetTextJustification, 99, 101, TextClipping);
    doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(pdf, ms.Memory, ms.Size);
  finally
    doc.Free;
    ms.Free;
  end;
  result := InflatePdf(NormalizePdf(pdf, err));
  if err <> '' then
    result := '';
end;

// the operands of the last Op (' rg', ' Tm') before Marker in the content
function OperandsBefore(const Txt, Marker, Op: RawUtf8): RawUtf8;
var
  p, i, j, k: PtrInt;
begin
  result := '';
  p := PosEx(Marker, Txt);
  i := 1;
  repeat
    j := PosEx(Op, Txt, i);
    if (j = 0) or
       (j > p) then
      break;
    i := j + length(Op);
    k := j;
    while (k > 1) and
          not (Txt[k - 1] in [#10, #13]) do
      dec(k);
    result := copy(Txt, k, j - k);
  until false;
end;

// binary data from numbers, as CLAUDE.md wants it (W1058 on Delphi 2010)
function BinaryOf(const B: array of byte): RawByteString;
begin
  FastSetRawByteString(result, @B[0], length(B));
end;

// text of a metafile under world transforms: a pure uniform scale is no
// rotation - the EMF TextOut took it for one and drew the text turned by 180
// degrees, its text matrix negated (the trunk's a86d7e6fc)
// the paths of the content that are painted, one item per path: its
// construction lines (m, l, c, re); a path ended by n (a clip) is dropped
function PaintedPaths(const Txt: RawUtf8): TRawUtf8DynArray;
var
  lines: TRawUtf8DynArray;
  path, op: RawUtf8;
  i, j, n: PtrInt;
begin
  result := nil;
  lines := nil;
  CsvToRawUtf8DynArray(pointer(Txt), lines, #10);
  path := '';
  for i := 0 to high(lines) do
  begin
    j := length(lines[i]);
    while (j > 0) and
          (lines[i][j] <> ' ') do
      dec(j);
    op := copy(lines[i], j + 1, maxInt);
    if (op = 'm') or (op = 'l') or (op = 'c') or (op = 're') then
      path := path + lines[i] + #10
    else if op = 'n' then
      path := ''
    else if (op = 'f') or (op = 'f*') or (op = 'S') or (op = 's') or
            (op = 'B') or (op = 'B*') or (op = 'b') or (op = 'b*') then
    begin
      if path <> '' then
      begin
        n := length(result);
        SetLength(result, n + 1);
        result[n] := path;
      end;
      path := '';
    end;
  end;
end;

// the box around the points of a path of PaintedPaths
function PathBox(const Path: RawUtf8): TPdfBox;
var
  lines, v: TRawUtf8DynArray;
  num: TDoubleDynArray;
  x1, y1, x2, y2: double;
  i, j, n: PtrInt;
  first: boolean;
begin
  lines := nil;
  CsvToRawUtf8DynArray(pointer(Path), lines, #10);
  first := true;
  x1 := 0;
  y1 := 0;
  x2 := 0;
  y2 := 0;
  for i := 0 to high(lines) do
  begin
    v := nil;
    CsvToRawUtf8DynArray(pointer(lines[i]), v, ' ');
    n := length(v) - 1; // the numbers, without the operator
    SetLength(num, n);
    for j := 0 to n - 1 do
      num[j] := GetExtended(pointer(v[j]));
    if v[n] = 're' then
    begin
      // x y w h: the second corner
      num[2] := num[0] + num[2];
      num[3] := num[1] + num[3];
    end;
    j := 0;
    while j + 1 < n do
    begin
      if first or (num[j] < x1) then
        x1 := num[j];
      if first or (num[j] > x2) then
        x2 := num[j];
      if first or (num[j + 1] < y1) then
        y1 := num[j + 1];
      if first or (num[j + 1] > y2) then
        y2 := num[j + 1];
      first := false;
      inc(j, 2);
    end;
  end;
  result := Box(x1, y1, x2 - x1, y2 - y1);
end;

procedure TPdfImageGoldenTests.MetaFileWorldTransform;

  // how many text matrices of the content turn the text by 180 degrees
  function NegatedMatrices(const Content: RawUtf8): integer;
  var
    i, j, n: PtrInt;
    line: RawUtf8;
    v: TRawUtf8DynArray;
  begin
    result := 0;
    i := PosEx(' Tm', Content);
    while i > 0 do
    begin
      j := i;
      while (j > 1) and
            not (Content[j - 1] in [#10, #13]) do
        dec(j);
      line := copy(Content, j, i - j);
      v := nil;
      CsvToRawUtf8DynArray(pointer(line), v, ' ');
      n := length(v);
      if (n >= 6) and
         (v[n - 6] <> '') and (v[n - 6][1] = '-') and
         (v[n - 3] <> '') and (v[n - 3][1] = '-') then
        inc(result);
      i := PosEx(' Tm', Content, i + 3);
    end;
  end;

var
  doc: TPdfDocumentGdi;
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  pdf: RawByteString;
  txt, err: RawUtf8;
begin
  mf := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    mf.Width := 400;
    mf.Height := 320;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      mc.Font.Name := 'Arial';
      mc.Font.Size := 20;
      SetGraphicsMode(mc.Handle, GM_ADVANCED);
      FillChar(xf, SizeOf(xf), 0);
      xf.eM11 := 0.5;
      xf.eM22 := 0.5;
      SetWorldTransform(mc.Handle, xf);
      mc.TextOut(40, 40, 'Half');
      xf.eM11 := 2;
      xf.eM22 := 2;
      SetWorldTransform(mc.Handle, xf);
      mc.TextOut(20, 40, 'Double');
      xf.eM11 := 0;
      xf.eM12 := 1;
      xf.eM21 := -1;
      xf.eM22 := 0;
      xf.eDx := 300;
      SetWorldTransform(mc.Handle, xf);
      mc.TextOut(40, 40, 'Turned');
      ModifyWorldTransform(mc.Handle, xf, MWT_IDENTITY);
      mc.TextOut(40, 260, 'Plain');
    finally
      mc.Free;
    end;
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    RenderMetaFile(doc.Canvas, mf, 1, 1, 0, 0);
    pdf := SaveDoc(doc);
  finally
    doc.Free;
    mf.Free;
  end;
  txt := InflatePdf(NormalizePdf(pdf, err));
  CheckEqual(err, '');
  Check(PosEx('(Half)', txt) > 0, 'the half-size text');
  Check(PosEx('(Double)', txt) > 0, 'the double-size text');
  Check(PosEx('(Turned)', txt) > 0, 'the rotated text');
  Check(PosEx('(Plain)', txt) > 0, 'the text after the identity');
  CheckEqual(NegatedMatrices(txt), 0, 'no text turned by 180 degrees');
  CheckGolden('emf_world', pdf);
end;

procedure TPdfImageGoldenTests.MetaFileAlphaBlend;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  mem: HDC;
  bmp, old: HBITMAP;
  bi: TBitmapInfo;
  bits: PCardinalArray;
  txt: RawUtf8;
  i: integer;
begin
  { the BLENDFUNCTION of the record was taken as the transparent colour: the
    usual AC_SRC_OVER with SourceConstantAlpha 255 is $00FF0000, blue }
  mf := TMetaFile.Create;
  try
    mf.Width := 100;
    mf.Height := 100;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      // a 32-bit DIB of blue pixels, whatever the depth of the screen
      FillChar(bi, SizeOf(bi), 0);
      bi.bmiHeader.biSize := SizeOf(bi.bmiHeader);
      bi.bmiHeader.biWidth := 8;
      bi.bmiHeader.biHeight := 8;
      bi.bmiHeader.biPlanes := 1;
      bi.bmiHeader.biBitCount := 32;
      mem := CreateCompatibleDC(0);
      bmp := CreateDIBSection(mem, bi, DIB_RGB_COLORS, pointer(bits), 0, 0);
      for i := 0 to 63 do
        bits[i] := $000000ff; // BGRX: blue
      old := SelectObject(mem, bmp);
      GdiAlphaBlend(mc.Handle, 10, 10, 64, 64, mem, 0, 0, 8, 8, $00FF0000);
      SelectObject(mem, old);
      DeleteObject(bmp);
      DeleteDC(mem);
    finally
      mc.Free;
    end;
    CheckEqual(length(EmfRecords(EmfBytes(mf), R_ALPHABLEND)), 1,
      'recorded as EMR_ALPHABLEND');
    txt := RenderedEmf(mf);
  finally
    mf.Free;
  end;
  CheckEqual(CountOccurrences('/Subtype/Image', txt), 1, 'the bitmap');
  CheckEqual(CountOccurrences('/Mask', txt), 0, 'no colour key');
end;

procedure TPdfImageGoldenTests.MetaFilePolyPolyline;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  pts: array[0..5] of TPoint;
  lines: array[0..1] of DWord;
  polys: array[0..1] of integer;
  bytes: RawByteString;
  txt: RawUtf8;
  i: integer;
begin
  { every polyline of EMR_POLYPOLYLINE/16 got a segment back to its first
    point; a polygon keeps it }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      lines[0] := 3;
      lines[1] := 3;
      polys[0] := 3;
      polys[1] := 3;
      for i := 0 to 5 do
      begin
        pts[i].X := 20 + i * 30;
        pts[i].Y := 20 + (i and 1) * 40;
      end;
      PolyPolyline(mc.Handle, pts[0], lines[0], 2); // 16-bit coordinates
      for i := 0 to 5 do
        inc(pts[i].Y, 100);
      PolyPolygon(mc.Handle, pts[0], polys[0], 2);
      for i := 0 to 5 do
        pts[i].X := 40000 + i * 30; // past 16 bits: the 32-bit record
      PolyPolyline(mc.Handle, pts[0], lines[0], 2);
    finally
      mc.Free;
    end;
    bytes := EmfBytes(mf);
    CheckEqual(length(EmfRecords(bytes, R_POLYPOLYLINE16)), 1, 'EMR_POLYPOLYLINE16');
    CheckEqual(length(EmfRecords(bytes, R_POLYPOLYLINE)), 1, 'EMR_POLYPOLYLINE');
    CheckEqual(length(EmfRecords(bytes, R_POLYPOLYGON16)), 1, 'EMR_POLYPOLYGON16');
    txt := RenderedEmf(mf);
  finally
    mf.Free;
  end;
  // two open polylines of two segments in each record, two closed triangles
  CheckEqual(CountOccurrences(' l'#10, txt), 2 * 2 + 2 * 2 + 2 * 3, 'line segments');
end;

procedure TPdfImageGoldenTests.MetaFileRestoreDC;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  bytes: RawByteString;
  recs: TIntegerDynArray;
  txt, rel: RawUtf8;
  i: integer;

  procedure Text(Y: integer; const Value: WideString);
  begin
    TextOutW(mc.Handle, 10, Y, pointer(Value), length(Value));
  end;

begin
  { EMR_RESTOREDC popped one state whatever its iRelative, and the saved
    states were an array of 32 guarded by Assert only }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      SetTextColor(mc.Handle, RGB(255, 0, 0));
      SaveDC(mc.Handle);
      SetTextColor(mc.Handle, RGB(0, 255, 0));
      SaveDC(mc.Handle);
      SetTextColor(mc.Handle, RGB(0, 0, 255));
      RestoreDC(mc.Handle, -2); // back to red
      Text(10, 'Red');
      for i := 1 to 40 do
      begin
        SetTextColor(mc.Handle, RGB(i * 6, 0, 0));
        if i = 37 then
          Text(40, 'Level');
        SaveDC(mc.Handle);
      end;
      RestoreDC(mc.Handle, -4); // the state saved after Level
      Text(70, 'Deep');
    finally
      mc.Free;
    end;
    bytes := EmfBytes(mf);
    CheckEqual(length(EmfRecords(bytes, R_SAVEDC)), 42, 'the saves');
    recs := EmfRecords(bytes, R_RESTOREDC); // the canvas adds one of its own
    rel := '';
    for i := 0 to high(recs) do
      rel := rel + Int32ToUtf8(PInteger(@PByteArray(bytes)[recs[i] + 8])^) + ' ';
    Check(PosEx('-2 -4 ', rel) = 1, 'the restores');
    txt := RenderedEmf(mf);
  finally
    mf.Free;
  end;
  CheckEqual(OperandsBefore(txt, '(Red)', ' rg'), '1 0 0', 'RestoreDC(-2)');
  Check(OperandsBefore(txt, '(Level)', ' rg') <> '', 'the colour of level 37');
  CheckEqual(OperandsBefore(txt, '(Deep)', ' rg'),
    OperandsBefore(txt, '(Level)', ' rg'), 'restored past 32 states');
end;

// the position of the last Op before Marker in the content, 0 if none
function PosBefore(const Txt, Marker, Op: RawUtf8): PtrInt;
var
  p, j: PtrInt;
begin
  result := 0;
  p := PosEx(Marker, Txt);
  j := PosEx(Op, Txt);
  while (j <> 0) and
        (j < p) do
  begin
    result := j;
    j := PosEx(Op, Txt, j + 1);
  end;
end;

// the number of q not closed by a Q before Marker in the content
function OpenBefore(const Txt, Marker: RawUtf8): integer;
var
  s: RawUtf8;
begin
  s := copy(Txt, 1, PosEx(Marker, Txt));
  result := CountOccurrences('q'#10, s) - CountOccurrences('Q'#10, s);
end;

// no q, Q or other graphics state operator within a path, no l, c or
// painting operator without a path
function ValidPaths(const Txt: RawUtf8): boolean;
var
  p: PUtf8Char;
  line, op: RawUtf8;
  i: PtrInt;
  inpath: boolean;
begin
  result := false;
  inpath := false;
  p := pointer(Txt);
  while p <> nil do
  begin
    line := GetNextLine(p, p);
    i := length(line);
    while (i > 0) and
          (line[i] <> ' ') do
      dec(i);
    op := copy(line, i + 1, length(line)); // case matters: M is the miter limit
    if (op = 'm') or
       (op = 're') then
      inpath := true
    else if (op = 'l') or
            (op = 'c') then
    begin
      if not inpath then
        exit;
    end
    else if (line = 'q') or
            (line = 'Q') or
            (op = 'w') or
            (op = 'd') or
            (op = 'J') or
            (op = 'j') or
            (op = 'M') or
            (op = 'RG') or
            (op = 'rg') or
            (op = 'gs') or
            (op = 'cm') or
            (op = 'BMC') or
            (op = 'BDC') or
            (op = 'EMC') then
    begin
      if inpath then
        exit;
    end
    else if (line = 'S') or
            (line = 'f') or
            (line = 'f*') or
            (line = 'B') or
            (line = 'B*') then
    begin
      if not inpath then
        exit;
      inpath := false;
    end
    else if line = 'n' then
      inpath := false;
  end;
  result := true;
end;

procedure TPdfImageGoldenTests.MetaFileClipRestoreDC;
var
  mf, mf2: TMetaFile;
  mc: TMetaFileCanvas;
  pen: HPEN;
  bmp: TBitmap;
  pts: array[0..2] of TPoint;
  doc: TPdfDocumentGdi;
  ms: TMemoryStream;
  pdf: RawByteString;
  txt, meta, two, tagged, more, fill, err: RawUtf8;
  i: PtrInt;

  procedure Text(Y: integer; const Value: WideString);
  begin
    TextOutW(mc.Handle, 10, Y, pointer(Value), length(Value));
  end;

  procedure Clip(L, T, R, B: integer);
  var
    rgn: HRGN;
  begin
    rgn := CreateRectRgn(L, T, R, B);
    SelectClipRgn(mc.Handle, rgn); // EMR_EXTSELECTCLIPRGN, RGN_COPY
    DeleteObject(rgn);
  end;

begin
  { EMR_RESTOREDC kept the clip of EMR_EXTSELECTCLIPRGN: the inner one stayed
    and its q was left open; the Q of a new clip kept the pen of before }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      SaveDC(mc.Handle);
      Clip(150, 150, 200, 200);
      Text(160, 'Saved');
      RestoreDC(mc.Handle, -1); // no clip: its q closed
      Clip(10, 10, 300, 300);
      Text(20, 'Outer');
      SaveDC(mc.Handle);
      Clip(50, 50, 100, 100);
      Text(60, 'Inner');
      RestoreDC(mc.Handle, -1); // the outer clip again
      Text(120, 'Back');
      pen := CreatePen(PS_DASH, 3, RGB(255, 0, 0));
      SelectObject(mc.Handle, pen);
      MoveToEx(mc.Handle, 20, 200, nil);
      LineTo(mc.Handle, 200, 200);
      Clip(20, 20, 350, 350); // Q q: the pen set again
      LineTo(mc.Handle, 200, 300);
      Text(310, 'Pen');
      SelectObject(mc.Handle, GetStockObject(BLACK_PEN));
      DeleteObject(pen);
    finally
      mc.Free;
    end;
    txt := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    mf.Free;
  end;
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      SaveDC(mc.Handle);
      Clip(10, 10, 100, 100);
      SetMetaRgn(mc.Handle); // the clip stays, part of the meta region
      Clip(0, 0, 300, 300);
      Text(20, 'Meta');
      RestoreDC(mc.Handle, -1); // before the meta region
      Text(150, 'Free');
      // a clip change within a path applies once the path is painted
      SaveDC(mc.Handle);
      Clip(10, 10, 300, 300);
      BeginPath(mc.Handle);
      MoveToEx(mc.Handle, 20, 200, nil);
      LineTo(mc.Handle, 200, 200);
      RestoreDC(mc.Handle, -1);
      EndPath(mc.Handle);
      StrokePath(mc.Handle);
      SaveDC(mc.Handle);
      Clip(10, 10, 300, 300);
      BeginPath(mc.Handle);
      MoveToEx(mc.Handle, 20, 210, nil);
      LineTo(mc.Handle, 200, 210);
      EndPath(mc.Handle);
      RestoreDC(mc.Handle, -1);
      StrokePath(mc.Handle);
      BeginPath(mc.Handle);
      MoveToEx(mc.Handle, 20, 220, nil);
      LineTo(mc.Handle, 200, 220);
      SaveDC(mc.Handle);
      Clip(10, 10, 300, 300);
      RestoreDC(mc.Handle, -1);
      LineTo(mc.Handle, 200, 230);
      EndPath(mc.Handle);
      StrokePath(mc.Handle);
      Text(250, 'Path');
      BeginPath(mc.Handle); // SelectClipPath consumes the path
      MoveToEx(mc.Handle, 20, 260, nil);
      LineTo(mc.Handle, 200, 260);
      MoveToEx(mc.Handle, 20, 265, nil);
      EndPath(mc.Handle);
      SelectClipPath(mc.Handle, RGN_COPY);
      LineTo(mc.Handle, 200, 265); // after the path: a line of its own
      Clip(0, 0, 350, 350);
      Text(270, 'After');
      BeginPath(mc.Handle); // painted under the clip of StrokePath, as GDI
      MoveToEx(mc.Handle, 20, 290, nil);
      LineTo(mc.Handle, 200, 290);
      Clip(0, 0, 30, 350);
      EndPath(mc.Handle);
      StrokePath(mc.Handle);
    finally
      mc.Free;
    end;
    meta := RenderedEmf(mf, 0, 0, tcNeverClip);
    // tagged: a recorded path takes its /Artifact BMC along
    ms := TMemoryStream.Create;
    doc := TPdfDocumentGdi.Create;
    try
      doc.Info.CreationDate := GOLDEN_DATE;
      doc.Tagged := true;
      doc.AddPage;
      RenderMetaFile(doc.Canvas, mf, 1, 1, 0, 0, tpSetTextJustification,
        99, 101, tcNeverClip);
      doc.SaveToStream(ms, GOLDEN_DATE);
      FastSetRawByteString(pdf, ms.Memory, ms.Size);
      tagged := InflatePdf(NormalizePdf(pdf, err));
    finally
      doc.Free;
      ms.Free;
    end;
  finally
    mf.Free;
  end;
  // what is drawn in a path bracket but is no geometry goes to the page
  mf := TMetaFile.Create;
  bmp := TBitmap.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    bmp.PixelFormat := pf24bit;
    bmp.Width := 4;
    bmp.Height := 4;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      BeginPath(mc.Handle);
      Text(20, 'InPath');
      mc.Draw(10, 40, bmp);
      MoveToEx(mc.Handle, 20, 80, nil);
      LineTo(mc.Handle, 200, 80);
      SelectObject(mc.Handle, GetStockObject(BLACK_PEN)); // a pen of the bracket
      LineTo(mc.Handle, 200, 120);
      EndPath(mc.Handle);
      StrokePath(mc.Handle);
      BeginPath(mc.Handle); // a shape adds to the path, painted once
      Rectangle(mc.Handle, 250, 250, 300, 300);
      EndPath(mc.Handle);
      SelectObject(mc.Handle, GetStockObject(NULL_PEN));
      MoveToEx(mc.Handle, 20, 350, nil);
      LineTo(mc.Handle, 200, 350); // of a null pen: ended, not in the fill
      FillPath(mc.Handle);
    finally
      mc.Free;
    end;
    more := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    bmp.Free;
    mf.Free;
  end;
  // the painting records as GDI paints: fill mode, closed figures
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      SetPolyFillMode(mc.Handle, ALTERNATE);
      SelectObject(mc.Handle, GetStockObject(NULL_PEN));
      SelectObject(mc.Handle, GetStockObject(NULL_BRUSH));
      pts[0].X := 20;
      pts[0].Y := 20;
      pts[1].X := 100;
      pts[1].Y := 20;
      pts[2].X := 60;
      pts[2].Y := 90;
      BeginPath(mc.Handle); // kept although neither pen nor brush shows it
      Polygon(mc.Handle, pts, 3);
      EndPath(mc.Handle);
      SelectObject(mc.Handle, GetStockObject(GRAY_BRUSH));
      FillPath(mc.Handle); // f* for ALTERNATE
      SelectObject(mc.Handle, GetStockObject(BLACK_PEN));
      BeginPath(mc.Handle); // an open triangle, closed by StrokeAndFillPath
      MoveToEx(mc.Handle, 20, 200, nil);
      LineTo(mc.Handle, 100, 200);
      LineTo(mc.Handle, 60, 290);
      Rectangle(mc.Handle, 150, 200, 200, 250); // a figure of its own
      EndPath(mc.Handle);
      StrokeAndFillPath(mc.Handle);
    finally
      mc.Free;
    end;
    fill := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    mf.Free;
  end;
  // a metafile ending in a path never painted, then another one
  mf := TMetaFile.Create;
  mf2 := TMetaFile.Create;
  ms := TMemoryStream.Create;
  doc := TPdfDocumentGdi.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      BeginPath(mc.Handle);
      MoveToEx(mc.Handle, 20, 20, nil);
      LineTo(mc.Handle, 200, 20);
      EndPath(mc.Handle);
    finally
      mc.Free;
    end;
    mf2.Width := 400;
    mf2.Height := 400;
    mc := TMetaFileCanvas.Create(mf2, 0);
    try
      MoveToEx(mc.Handle, 20, 40, nil);
      LineTo(mc.Handle, 200, 40);
    finally
      mc.Free;
    end;
    doc.Info.CreationDate := GOLDEN_DATE;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    RenderMetaFile(doc.Canvas, mf);
    RenderMetaFile(doc.Canvas, mf2);
    doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(pdf, ms.Memory, ms.Size);
    two := InflatePdf(NormalizePdf(pdf, err));
  finally
    doc.Free;
    ms.Free;
    mf2.Free;
    mf.Free;
  end;
  CheckEqual(CountOccurrences('q'#10, txt), CountOccurrences('Q'#10, txt),
    'q and Q balanced');
  Check(OperandsBefore(txt, '(Inner)', ' re') <>
    OperandsBefore(txt, '(Outer)', ' re'), 'the inner clip');
  CheckEqual(OperandsBefore(txt, '(Back)', ' re'),
    OperandsBefore(txt, '(Outer)', ' re'), 'the outer clip restored');
  Check(PosBefore(txt, '(Pen)', ' RG'#10) > PosBefore(txt, '(Pen)', #10'Q'#10),
    'the pen colour after Q');
  Check(PosBefore(txt, '(Pen)', ' w'#10) > PosBefore(txt, '(Pen)', #10'Q'#10),
    'the pen width after Q');
  Check(PosBefore(txt, '(Pen)', ' d'#10) > PosBefore(txt, '(Pen)', #10'Q'#10),
    'the pen dash after Q');
  CheckEqual(CountOccurrences('q'#10, meta), CountOccurrences('Q'#10, meta),
    'q and Q balanced with SetMetaRgn');
  CheckEqual(OpenBefore(meta, '(Meta)'), 3, 'the meta region kept');
  CheckEqual(OpenBefore(meta, '(Free)'), 1, 'the meta region restored');
  Check(ValidPaths(meta), 'valid paths');
  CheckEqual(CountOccurrences(' l'#10, meta), 6, 'every segment kept');
  Check((PosEx('0 842 22.5 -262.5 re', meta) > 0) and
        (PosEx('0 842 22.5 -262.5 re', meta) < PosEx('15 624.5 m', meta)),
    'the path under the clip of its painting');
  CheckEqual(CountOccurrences('BMC'#10, tagged) + CountOccurrences(' BDC'#10, tagged),
    CountOccurrences('EMC'#10, tagged), 'marked content balanced');
  Check(ValidPaths(tagged), 'valid tagged paths');
  Check(PosEx('(InPath)', more) > 0, 'text in a path');
  Check(PosEx(' Do'#10, more) > 0, 'a bitmap in a path');
  Check(ValidPaths(more), 'valid paths with text and bitmap');
  CheckEqual(CountOccurrences('S'#10, more), 1, 'the path stroked once');
  CheckEqual(CountOccurrences(#10'B'#10, more) + CountOccurrences(#10'f'#10, more) +
    CountOccurrences(#10'B*'#10, more) + CountOccurrences(#10'f*'#10, more), 1,
    'the shape painted once');
  Check(PosEx('75 827 l'#10, fill) > 0, 'a polygon of no pen nor brush kept');
  CheckEqual(CountOccurrences(#10'f*'#10, fill), 1, 'FillPath in ALTERNATE mode');
  i := PosEx(' re'#10, fill);
  while (i > 1) and
        (fill[i - 1] <> #10) do
    dec(i);
  Check((i > 2) and
        (copy(fill, i - 2, 2) = 'h'#10), 'StrokeAndFillPath closes the figure');
  Check(PosBefore(meta, '(After)', ' re'#10) > PosBefore(meta, '(After)', ' l'#10),
    'a clip after SelectClipPath');
  Check(PosEx(' l'#10'S'#10, two) > 0, 'a line after a path never painted');
end;

procedure TPdfImageGoldenTests.MetaFileUnderlineClipped;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  font: HFONT;
  pen: HPEN;
  r: Windows.TRect;
  s: WideString;
  txt: RawUtf8;
begin
  { the Q after a clipped text forgot only the fill colour, while its
    underline had set the pen and then the one of before again: a line of
    that pen kept the width of before the q }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      pen := CreatePen(PS_SOLID, 1, 0); // of a width: NeedPen caches it
      SelectObject(mc.Handle, pen);
      font := CreateFontW(-20, 0, 0, 0, FW_NORMAL, 0, 1, 0, DEFAULT_CHARSET,
        0, 0, 0, 0, 'Arial');
      SelectObject(mc.Handle, font);
      SetTextColor(mc.Handle, RGB(255, 0, 0));
      r.Left := 10;
      r.Top := 10;
      r.Right := 300;
      r.Bottom := 60;
      s := 'Under';
      ExtTextOutW(mc.Handle, 10, 10, ETO_CLIPPED, @r, pointer(s), length(s), nil);
      MoveToEx(mc.Handle, 20, 200, nil); // the pen of before the text
      LineTo(mc.Handle, 200, 200);
      s := 'End';
      TextOutW(mc.Handle, 10, 300, pointer(s), length(s));
      SelectObject(mc.Handle, GetStockObject(SYSTEM_FONT));
      SelectObject(mc.Handle, GetStockObject(BLACK_PEN));
      DeleteObject(font);
      DeleteObject(pen);
    finally
      mc.Free;
    end;
    txt := RenderedEmf(mf);
  finally
    mf.Free;
  end;
  Check(PosEx('(Under)', txt) > 0, 'the text');
  Check(PosBefore(txt, '(End)', ' w'#10) > PosBefore(txt, '(End)', #10'Q'#10),
    'the pen width after the Q of the text');
end;

procedure TPdfImageGoldenTests.MetaFileNullPenLines;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  pen: HPEN;
  txt, two: RawUtf8;
begin
  { GDI draws no line of a null pen: its m l and the ArcTo stayed open, the
    next shape stroked them in the colour of before, and the Arc was
    stroked at once; a line of a pen is stroked at once, yet the next shape
    wrote a lone S }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      SelectObject(mc.Handle, GetStockObject(NULL_PEN));
      MoveToEx(mc.Handle, 20, 20, nil);
      LineTo(mc.Handle, 200, 20);
      ArcTo(mc.Handle, 20, 40, 120, 140, 120, 90, 20, 90);
      Arc(mc.Handle, 150, 40, 250, 140, 250, 90, 150, 90);
      SelectObject(mc.Handle, GetStockObject(GRAY_BRUSH));
      Rectangle(mc.Handle, 250, 250, 300, 300);
    finally
      mc.Free;
    end;
    txt := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    mf.Free;
  end;
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      pen := CreatePen(PS_SOLID, 1, 0);
      SelectObject(mc.Handle, pen);
      MoveToEx(mc.Handle, 20, 20, nil);
      LineTo(mc.Handle, 200, 20);
      SelectObject(mc.Handle, GetStockObject(GRAY_BRUSH));
      Rectangle(mc.Handle, 250, 250, 300, 300);
      SelectObject(mc.Handle, GetStockObject(BLACK_PEN));
      DeleteObject(pen);
    finally
      mc.Free;
    end;
    two := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    mf.Free;
  end;
  CheckEqual(CountOccurrences(#10'S'#10, txt), 0, 'a null pen strokes nothing');
  Check(ValidPaths(txt), 'valid paths of a null pen');
  Check((PosBefore(txt, #10'f'#10, ' l'#10) > 0) and
        (PosBefore(txt, #10'f'#10, ' l'#10) < PosBefore(txt, #10'f'#10, #10'n'#10)),
    'the line ended before the shape');
  Check((PosBefore(txt, #10'f'#10, ' c'#10) > 0) and
        (PosBefore(txt, #10'f'#10, ' c'#10) < PosBefore(txt, #10'f'#10, #10'n'#10)),
    'the arcs ended before the shape');
  CheckEqual(CountOccurrences(#10'S'#10, two), 1, 'the line stroked once');
  Check(ValidPaths(two), 'no stroke left pending for the shape');
end;

// the content of a metafile of the lines of LineAfterEndedPath, case Kind
function LineAfterEndedPathEmf(Kind: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  pen: HPEN;
  rgn: HRGN;
  pts: array[0..3] of Windows.TPoint;
  counts: array[0..1] of DWORD;
begin
  pts[0].X := 20;
  pts[0].Y := 200;
  pts[1].X := 90;
  pts[1].Y := 250;
  pts[2].X := 150;
  pts[2].Y := 200;
  pts[3].X := 220;
  pts[3].Y := 250;
  counts[0] := 2;
  counts[1] := 2;
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      pen := CreatePen(PS_SOLID, 1, 0);
      SelectObject(mc.Handle, pen);
      case Kind of
        0, 1: // PolylineTo alone, of a pen or of a null pen
          begin
            if Kind = 1 then
              SelectObject(mc.Handle, GetStockObject(NULL_PEN));
            MoveToEx(mc.Handle, 20, 60, nil);
            PolylineTo(mc.Handle, PPoint(@pts)^, 2);
          end;
        2: // a polyline of a null pen ends with n
          begin
            SelectObject(mc.Handle, GetStockObject(NULL_PEN));
            Polyline(mc.Handle, PPoint(@pts)^, 2);
            SelectObject(mc.Handle, pen);
          end;
        3: // FillRgn
          begin
            rgn := CreateRectRgn(250, 250, 300, 300);
            FillRgn(mc.Handle, rgn, GetStockObject(GRAY_BRUSH));
            DeleteObject(rgn);
          end;
        4: // PolyPolyline
          PolyPolyline(mc.Handle, PPoint(@pts)^, PDWORD(@counts)^, 2);
        5: // PolylineTo within a path, painted by StrokePath
          begin
            BeginPath(mc.Handle);
            MoveToEx(mc.Handle, 20, 60, nil);
            PolylineTo(mc.Handle, PPoint(@pts)^, 2);
            EndPath(mc.Handle);
            StrokePath(mc.Handle);
          end;
      end;
      if Kind in [2..4] then
      begin
        MoveToEx(mc.Handle, 20, 100, nil); // the line after it, nothing else
        LineTo(mc.Handle, 300, 100);
      end;
      SelectObject(mc.Handle, GetStockObject(BLACK_PEN));
      DeleteObject(pen);
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    mf.Free;
  end;
end;

procedure TPdfImageGoldenTests.MetaFileLineAfterEndedPath;
const
  STROKES: array[0..5] of integer = (1, 0, 1, 1, 2, 1);
  LINES: array[0..5] of integer = (2, 2, 2, 1, 3, 2);
  WHAT: array[0..5] of RawUtf8 = ('PolylineTo', 'PolylineTo of a null pen',
    'a line after a null pen polyline', 'a line after FillRgn',
    'a line after PolyPolyline', 'PolylineTo in a path');
var
  k: integer;
  txt: RawUtf8;
begin
  { TPdfCanvas.NewPath set the flag that tells the renderer a GDI path is
    being recorded: after a record that ended its path with n, a line had
    no S, and without a MoveTo no m, and PolylineTo wrote its own n first
    and was never stroked }
  for k := 0 to high(STROKES) do
  begin
    txt := LineAfterEndedPathEmf(k);
    CheckEqual(CountOccurrences(#10'S'#10, txt), STROKES[k], WHAT[k]);
    CheckEqual(CountOccurrences(' l'#10, txt), LINES[k], WHAT[k]);
    Check(ValidPaths(txt), Utf8ToString(WHAT[k]));
    Check(PosBefore(txt, 'endstream', ' l'#10) <
      MaxPtrInt(PosBefore(txt, 'endstream', #10'S'#10),
        PosBefore(txt, 'endstream', #10'n'#10)), Utf8ToString(WHAT[k])); // no path left open
  end;
end;

// not in FPC's windows unit
function GdiAbortPath(DC: HDC): BOOL; stdcall;
  external 'gdi32.dll' name 'AbortPath';

function Between(P, After, Before: PtrInt): boolean;
begin
  result := (P > After) and
            (P < Before);
end;

// the operand Item of the line Index lines before the first Op line of Txt
function OperandAt(const Txt, Op: RawUtf8; Index, Item: integer): double;
var
  p, i: PtrInt;
  line: RawUtf8;
begin
  p := PosEx(Op, Txt);
  for i := 0 to Index do
  begin
    while (p > 1) and
          (Txt[p - 1] <> #10) do
      dec(p);
    dec(p); // the #10 before the line
  end;
  line := copy(Txt, p + 1, PosEx(#10, Txt, p + 1) - p - 1);
  result := GetExtended(pointer(GetCsvItem(pointer(line), Item, ' ')));
end;

// the content of a metafile of text in a path, case Kind of MetaFileTextInPath
function TextInPathEmf(Kind: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  lf: TLogFontW;
  fnt, fnt2: HFONT;
  brush: HBRUSH;
  r: Windows.TRect;
  dc: HDC;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight := -20;
  lf.lfUnderline := ord(Kind = 6);
  if Kind = 10 then
    lf.lfEscapement := 900;
  Utf8ToWideChar(@lf.lfFaceName, 'Arial');
  fnt := CreateFontIndirectW(lf);
  lf.lfUnderline := 0;
  Utf8ToWideChar(@lf.lfFaceName, 'Courier New');
  fnt2 := CreateFontIndirectW(lf);
  brush := CreateSolidBrush($0000FF); // red
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      dc := mc.Handle;
      SelectObject(dc, fnt);
      SelectObject(dc, GetStockObject(BLACK_PEN));
      if Kind = 5 then
        SelectObject(dc, GetStockObject(NULL_BRUSH))
      else
        SelectObject(dc, brush);
      SetTextColor(dc, $FF0000); // blue
      if Kind in [7, 10] then
      begin
        SetBkMode(dc, OPAQUE);
        SetTextAlign(dc, TA_BASELINE);
      end
      else
        SetBkMode(dc, TRANSPARENT);
      BeginPath(dc);
      if Kind = 9 then
      begin
        MoveToEx(dc, 100, 100, nil);
        LineTo(dc, 150, 100);
      end;
      if Kind = 4 then
      begin
        r.Left := 0;
        r.Top := 0;
        r.Right := 300;
        r.Bottom := 100;
        ExtTextOutW(dc, 20, 20, ETO_CLIPPED, @r, 'Path', 4, nil);
      end
      else
        TextOutW(dc, 20, 20, 'Path', 4);
      if Kind = 9 then
        LineTo(dc, 150, 150);
      EndPath(dc);
      if Kind = 8 then
      begin
        SelectObject(dc, fnt2); // drawn at once, before the path
        TextOutW(dc, 20, 200, 'Page', 4);
      end;
      case Kind of
        1, 6:
          StrokePath(dc);
        2:
          StrokeAndFillPath(dc);
        3:
          GdiAbortPath(dc);
      else
        FillPath(dc);
      end;
      SelectObject(dc, GetStockObject(SYSTEM_FONT));
      SelectObject(dc, GetStockObject(WHITE_BRUSH));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    mf.Free;
    DeleteObject(fnt);
    DeleteObject(fnt2);
    DeleteObject(brush);
  end;
end;

procedure TPdfImageGoldenTests.MetaFileTextInPath;
const
  MODES: array[0..10] of RawUtf8 = ('0 Tr', '1 Tr', '2 Tr', '', '', '', '1 Tr',
    '0 Tr', '0 Tr', '0 Tr', '0 Tr');
  TEXTS: array[0..10] of integer = (1, 1, 1, 0, 0, 0, 1, 1, 2, 1, 1);
  WHAT: array[0..10] of RawUtf8 = ('FillPath', 'StrokePath',
    'StrokeAndFillPath', 'AbortPath', 'ETO_CLIPPED', 'a null brush',
    'an underline', 'an opaque background', 'text after the path',
    'lines around the text', 'a turned opaque background');
var
  k: integer;
  txt: RawUtf8;
  tr, bt: PtrInt;
  base: double;
begin
  { GDI adds the outlines of text in a path to the path, painted or dropped
    with it, in the brush or the pen of the painting record: the renderer
    drew the text at once, in the text colour }
  for k := 0 to high(MODES) do
  begin
    txt := TextInPathEmf(k);
    CheckEqual(CountOccurrences(#10'BT'#10, txt), TEXTS[k], WHAT[k]);
    if MODES[k] <> '' then
      Check(PosEx(#10 + MODES[k] + #10, txt) > 0, Utf8ToString(WHAT[k]))
    else
      Check(PosEx(' Tr'#10, txt) = 0, Utf8ToString(WHAT[k]));
    Check(ValidPaths(txt), Utf8ToString(WHAT[k]));
    CheckEqual(OpenBefore(txt, 'endstream'), 0, WHAT[k]);
    // the text colour only for the text drawn at once
    Check((PosEx(#10'0 0 1 rg'#10, txt) > 0) = (k = 8), Utf8ToString(WHAT[k]));
    Check(PosEx(#10'0 Tz'#10, txt) = 0, Utf8ToString(WHAT[k])); // no text scaled to nothing
    case k of
      6:
        begin
          CheckEqual(CountOccurrences(#10'S'#10, txt), 1, 'no stroke of its own');
          CheckEqual(CountOccurrences(#10'h'#10, txt), 1, 'the underline closed');
        end;
      7:
        begin
          CheckEqual(CountOccurrences(#10'h'#10, txt), 1,
            'the background as a figure');
          // the cell around the baseline of TA_BASELINE, Y up in PDF
          base := OperandAt(txt, ' Td'#10, 0, 1);
          Check((OperandAt(txt, #10'h'#10, 2, 1) > base) and // its top
                (OperandAt(txt, #10'h'#10, 1, 1) < base),
            'the background around the baseline');
        end;
      8:
        begin
          tr := PosEx(' Tr'#10, txt);
          bt := PosEx(#10'BT'#10, txt, tr);
          Check((tr > 0) and
                (PosEx(' Tf'#10, txt, tr) > 0) and
                (PosEx(' Tf'#10, txt, tr) < bt),
            'the text of the path selects its own font');
          Check(Between(PosEx('Tc'#10, txt, tr), tr, bt) and
                Between(PosEx('Tw'#10, txt, tr), tr, bt) and
                Between(PosEx(' Tz'#10, txt, tr), tr, bt),
            'and its own spacing');
        end;
      9:
        CheckEqual(CountOccurrences(' m'#10, txt), 3,
          'the line after the text starts a figure');
      10: // turned by 90 degrees: its top and bottom apart in X, not in Y
        Check((abs(OperandAt(txt, #10'h'#10, 2, 1) -
                   OperandAt(txt, #10'h'#10, 1, 1)) < 0.01) and
              (abs(OperandAt(txt, #10'h'#10, 2, 0) -
                   OperandAt(txt, #10'h'#10, 1, 0)) > 5),
          'the background turned with the text');
    end;
  end;
end;

// the content of a metafile of a path and a layer, case Kind of
// MetaFileMarkedContentInPath
function MarkedPathEmf(Kind: integer): RawUtf8;
var
  doc: TPdfDocumentGdi;
  grp: TPdfOptionalContentGroup;
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  ms: TMemoryStream;
  dc: HDC;
  pdf: RawByteString;
  err: RawUtf8;
begin
  ms := TMemoryStream.Create;
  mf := TMetaFile.Create;
  doc := TPdfDocumentGdi.Create;
  try
    doc.UseOptionalContent := true;
    doc.ScreenLogPixels := 96;
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    doc.AddPage;
    grp := doc.CreateOptionalContentGroup(nil, 'Layer', true);
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      mc.Font.Name := 'Arial';
      mc.Font.Size := 14;
      dc := mc.Handle;
      SetBkMode(dc, TRANSPARENT);
      SelectObject(dc, GetStockObject(BLACK_PEN));
      SelectObject(dc, GetStockObject(GRAY_BRUSH));
      if Kind in [0, 3] then
        GdiCommentBeginMarkContent(dc, grp);
      BeginPath(dc);
      MoveToEx(dc, 100, 100, nil);
      LineTo(dc, 150, 100);
      if Kind in [1, 2] then
        GdiCommentBeginMarkContent(dc, grp);
      if Kind = 2 then
        LineTo(dc, 150, 150)
      else
        TextOutW(dc, 20, 20, 'Path', 4);
      if Kind in [1, 2] then
        GdiCommentEndMarkContent(dc);
      LineTo(dc, 100, 150);
      EndPath(dc);
      if Kind = 3 then
        GdiCommentEndMarkContent(dc);
      FillPath(dc);
      if Kind = 0 then
        GdiCommentEndMarkContent(dc);
    finally
      mc.Free;
    end;
    RenderMetaFile(doc.Canvas, mf, 1, 1, 0, 0, tpSetTextJustification,
      99, 101, tcNeverClip);
    doc.SaveToStream(ms, GOLDEN_DATE);
    FastSetRawByteString(pdf, ms.Memory, ms.Size);
  finally
    doc.Free;
    mf.Free;
    ms.Free;
  end;
  result := InflatePdf(NormalizePdf(pdf, err));
  if err <> '' then
    result := '';
end;

procedure TPdfImageGoldenTests.MetaFileMarkedContentInPath;
const
  WHAT: array[0..3] of RawUtf8 = ('a layer around the path',
    'a layer around the text of the path', 'a layer around a line of the path',
    'a layer closed before the painting');
var
  k: integer;
  txt: RawUtf8;
  bdc, emc, path, fill, bt: PtrInt;
begin
  { the path and its text are kept apart until the painting record: a layer
    comment within the path must stay on the page, never in a buffer, and
    the path is in the layer only when painted in it, as GDI paints it then }
  for k := 0 to high(WHAT) do
  begin
    txt := MarkedPathEmf(k);
    Check(BalancedStreams(txt), Utf8ToString(WHAT[k]));
    Check(ValidPaths(txt), Utf8ToString(WHAT[k]));
    bdc := PosEx(' BDC'#10, txt);
    emc := PosEx(#10'EMC'#10, txt);
    path := PosEx(' m'#10, txt); // the path, painted on its own
    fill := PosEx(#10'f*'#10, txt);
    bt := PosEx(#10'BT'#10, txt);
    if k = 0 then
      Check(Between(bdc, 0, path) and
            Between(fill, path, emc) and
            Between(bt, fill, emc), Utf8ToString(WHAT[k]))
    else
      Check((bdc > 0) and
            Between(emc, bdc, path) and
            (fill > path) and
            ((k = 2) or
             (bt > fill)), Utf8ToString(WHAT[k]));
  end;
end;

// the content of a metafile of a path and a world transform set between
// EndPath and FillPath: none, a translation (Kind 1) or a scale (Kind 2)
function TransformAfterPathEmf(Kind: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  dc: HDC;
begin
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      mc.Font.Name := 'Arial';
      mc.Font.Size := 14;
      dc := mc.Handle;
      SetBkMode(dc, TRANSPARENT);
      SetGraphicsMode(dc, GM_ADVANCED);
      BeginPath(dc);
      MoveToEx(dc, 100, 100, nil);
      LineTo(dc, 150, 100);
      LineTo(dc, 150, 150);
      TextOutW(dc, 20, 20, 'Path', 4);
      EndPath(dc);
      FillChar(xf, SizeOf(xf), 0);
      xf.eM11 := Kind;
      xf.eM22 := Kind;
      if Kind = 1 then
        xf.eDx := 100;
      if Kind <> 0 then
        SetWorldTransform(dc, xf);
      FillPath(dc);
      MoveToEx(dc, 10, 10, nil); // a line under the new transform
      LineTo(dc, 20, 20);
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf, 0, 0, tcNeverClip);
  finally
    mf.Free;
  end;
end;

procedure TPdfImageGoldenTests.MetaFileTransformAfterPath;
var
  k: integer;
  txt, path, line, path0, line0: RawUtf8;
  p, e: PtrInt;
begin
  { GDI keeps the points of a path in device units from its recording on:
    a world transform set before the painting record moves neither the
    path nor its text, only what is drawn after it }
  for k := 0 to 2 do
  begin
    txt := TransformAfterPathEmf(k);
    p := PosEx('stream'#10, txt); // any cm of the page too
    e := PosEx(#10'ET'#10, txt);
    path := copy(txt, p, e - p + 1);
    line := copy(txt, e, PosEx(#10'S'#10, txt, e) - e);
    if k = 0 then
    begin
      path0 := path;
      line0 := line;
      Check((p > 0) and
            (PosEx(' m'#10, path) > 0) and
            (PosEx(#10'f*'#10, path) > 0) and
            (PosEx(' Tj'#10, path) > 0), 'the path and its text');
    end
    else
    begin
      CheckEqual(path, path0, 'the path and its text where recorded');
      Check(line <> line0, 'the line after the painting transformed');
    end;
  end;
end;

procedure TPdfImageGoldenTests.MetaFileScaledRotation;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  txt, m: RawUtf8;
  raised: boolean;
begin
  { ScaleMatrix took ArcSin(eM12) and TextOut ArcCos(eM11): with a rotation
    scaled by 2 both get a value past 1 and raise (Delphi) or give NaN (FPC) }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      mc.Font.Name := 'Arial';
      mc.Font.Size := 10;
      SetGraphicsMode(mc.Handle, GM_ADVANCED);
      FillChar(xf, SizeOf(xf), 0);
      xf.eM12 := 2; // 90 degrees, twice the size
      xf.eM21 := -2;
      xf.eDx := 200;
      SetWorldTransform(mc.Handle, xf);
      mc.TextOut(10, 10, 'Ninety');
      xf.eM11 := -2; // 180 degrees, twice the size
      xf.eM12 := 0;
      xf.eM21 := 0;
      xf.eM22 := -2;
      xf.eDx := 300;
      xf.eDy := 300;
      SetWorldTransform(mc.Handle, xf);
      mc.TextOut(10, 10, 'Turned');
    finally
      mc.Free;
    end;
    raised := false;
    try
      txt := RenderedEmf(mf);
    except
      raised := true;
    end;
  finally
    mf.Free;
  end;
  Check(not raised, 'rendered');
  Check(PosEx('(Ninety)', txt) > 0, 'the text at 90 degrees');
  Check(PosEx('(Turned)', txt) > 0, 'the text at 180 degrees');
  // FPC's ArcCos(-2) is NaN: the text took the negated matrix, drawn upright
  m := OperandsBefore(txt, '(Turned)', ' Tm');
  Check((m <> '') and (m[1] = '-'), 'turned by 180 degrees: ' + Utf8ToString(m));
end;

procedure TPdfImageGoldenTests.MetaFileAnsiText;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  bytes: RawByteString;
  recs: TIntegerDynArray;
  w, a: RawUtf8;
  i: integer;

  // draw Codes at Y in an Arial of CharSet
  procedure Text(Y, CharSet: integer; const Codes: array of word);
  var
    lf: TLogFontW;
    f, old: HFONT;
    ws: WideString;
    c: integer;
  begin
    FillChar(lf, SizeOf(lf), 0);
    lf.lfHeight := -16;
    lf.lfCharSet := CharSet;
    Utf8ToWideChar(@lf.lfFaceName, 'Arial');
    f := CreateFontIndirectW(lf);
    old := SelectObject(mc.Handle, f);
    SetLength(ws, length(Codes));
    for c := 0 to high(Codes) do
      ws[c + 1] := WideChar(Codes[c]);
    TextOutW(mc.Handle, 10, Y, pointer(ws), length(ws));
    SelectObject(mc.Handle, old);
    DeleteObject(f);
  end;

  // the W record at o as an A record of Ansi, its UTF-16 zeroed past the bytes
  procedure ToAnsi(o: integer; const Ansi: RawByteString);
  var
    str: PtrInt;
  begin
    PCardinal(@PByteArray(bytes)[o])^ := R_EXTTEXTOUTA;
    // EMRTEXT.nChars at 44, offString at 48 of the record: room for 4 bytes
    PCardinal(@PByteArray(bytes)[o + 44])^ := length(Ansi);
    str := o + PInteger(@PByteArray(bytes)[o + 48])^;
    FillChar(PByteArray(bytes)[str], 4, 0);
    MoveFast(pointer(Ansi)^, PByteArray(bytes)[str], length(Ansi));
  end;

  // a dx of 100 per byte after the 4 bytes of the A record at o, which held
  // the UTF-16 and the dx of 3 WideChars: wider than the text, so it is used
  procedure WideDx(o: integer);
  var
    j, str: PtrInt;
  begin
    str := PInteger(@PByteArray(bytes)[o + 48])^;
    PInteger(@PByteArray(bytes)[o + 72])^ := str + 4; // EMRTEXT.offDx
    for j := 0 to 3 do
      PInteger(@PByteArray(bytes)[o + str + 4 + j * 4])^ := 100;
  end;

begin
  { EMR_EXTTEXTOUTA went through the Unicode path: its bytes were read as
    WideChars, twice as many as the record holds. Windows records ExtTextOutA
    as EMR_EXTTEXTOUTW, so the A records are made from W ones, in the ANSI
    code page, in the one of a Greek font and in Shift-JIS, three characters
    of four bytes. The W records lose their dx, which an A record has per
    byte: the Shift-JIS one gets a dx of 4 entries, which cannot fit its 3
    WideChars and is dropped - all draw by the measured text }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      Text(10, ANSI_CHARSET, [ord('A'), ord('b')]);
      Text(40, GREEK_CHARSET, [$03B1, $03B2]); // alpha beta
      Text(70, SHIFTJIS_CHARSET, [ord('A'), $3042, ord('B')]); // hiragana a
    finally
      mc.Free;
    end;
    bytes := EmfBytes(mf);
    recs := EmfRecords(bytes, R_EXTTEXTOUTW);
    if CheckEqual(length(recs), 3, 'three W records') then
    begin
      for i := 0 to 2 do
      begin
        CheckEqual(PCardinal(@PByteArray(bytes)[recs[i] + 44])^, 2 + i shr 1,
          'the characters');
        PCardinal(@PByteArray(bytes)[recs[i] + 72])^ := 0; // EMRTEXT.offDx
      end;
      mf.Handle := SetEnhMetaFileBits(length(bytes), pointer(bytes));
      w := RenderedEmf(mf);
      ToAnsi(recs[0], 'Ab');
      ToAnsi(recs[1], BinaryOf([$E1, $E2])); // code page 1253
      ToAnsi(recs[2], BinaryOf([ord('A'), $82, $A0, ord('B')])); // code page 932
      WideDx(recs[2]);
      mf.Handle := SetEnhMetaFileBits(length(bytes), pointer(bytes));
      a := RenderedEmf(mf);
    end;
  finally
    mf.Free;
  end;
  Check(w <> '', 'the W metafile rendered');
  CheckEqual(a, w, 'the A records draw as the W ones');
end;

// two boxes the same within the rounding of the content stream
function SameBox(const A, B: TPdfBox): boolean;
begin
  result := (Abs(A.Left - B.Left) < 0.02) and
            (Abs(A.Top - B.Top) < 0.02) and
            (Abs(A.Width - B.Width) < 0.02) and
            (Abs(A.Height - B.Height) < 0.02);
end;

// text in the stock font Stock after a large Arial, or (Reference) in a font
// created from the LOGFONT of that stock font; Mapped device pixels per
// logical unit, 1 for MM_TEXT
function StockFontEmf(Stock: integer; Reference: boolean;
  Mapped: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  lf: TLogFontW;
  f, g: HFONT;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight := -40;
  Utf8ToWideChar(@lf.lfFaceName, 'Arial');
  f := CreateFontIndirectW(lf);
  GetObjectW(GetStockObject(Stock), SizeOf(lf), @lf);
  g := CreateFontIndirectW(lf);
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      if Mapped > 1 then
      begin
        SetMapMode(mc.Handle, MM_ANISOTROPIC);
        SetWindowExtEx(mc.Handle, 100, 100, nil);
        SetViewportExtEx(mc.Handle, 100 * Mapped, 100 * Mapped, nil);
      end;
      SelectObject(mc.Handle, f);
      TextOutW(mc.Handle, 10, 10, 'Arial', 5);
      if Reference then
        SelectObject(mc.Handle, g)
      else
        SelectObject(mc.Handle, GetStockObject(Stock));
      TextOutW(mc.Handle, 10, 100, 'Stock', 5);
      SelectObject(mc.Handle, GetStockObject(SYSTEM_FONT));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf);
  finally
    mf.Free;
    DeleteObject(f);
    DeleteObject(g);
  end;
end;

// SYSTEM_FONT text on an opaque background at device pixel 320,320, aligned
// by Align, at Mapped device pixels per logical unit
function StockTextEmf(Mapped, Align: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  brush: HBRUSH;
  dc: HDC;
begin
  brush := CreateSolidBrush($0000FF);
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      dc := mc.Handle;
      if Mapped > 1 then
      begin
        SetMapMode(dc, MM_ANISOTROPIC);
        SetWindowExtEx(dc, 100, 100, nil);
        SetViewportExtEx(dc, 100 * Mapped, 100 * Mapped, nil);
      end;
      SelectObject(dc, GetStockObject(SYSTEM_FONT));
      SelectObject(dc, brush); // the background drawn in the brush's colour
      SetBkMode(dc, OPAQUE);
      SetBkColor(dc, $0000FF);
      SetTextAlign(dc, Align);
      TextOutW(dc, 320 div Mapped, 320 div Mapped, 'Stock', 5);
      SelectObject(dc, GetStockObject(WHITE_BRUSH));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf);
  finally
    mf.Free;
    DeleteObject(brush);
  end;
end;

// text in a metafile that selects no font: the DC's own, SYSTEM_FONT; at two
// device pixels per logical unit, set after the start (Mapped), and after a
// selection of SYSTEM_FONT (Selected)
function DefaultFontEmf(Mapped: boolean = false;
  Selected: boolean = false): RawUtf8;
var
  mf: TMetaFile;
  dc: HDC;
begin
  dc := CreateEnhMetaFileW(0, nil, nil, nil);
  if Selected then
    SelectObject(dc, GetStockObject(SYSTEM_FONT));
  if Mapped then
  begin
    SetMapMode(dc, MM_ANISOTROPIC);
    SetWindowExtEx(dc, 100, 100, nil);
    SetViewportExtEx(dc, 200, 200, nil);
  end;
  TextOutW(dc, 10, 100, 'Stock', 5);
  mf := TMetaFile.Create;
  try
    mf.Handle := CloseEnhMetaFile(dc);
    result := RenderedEmf(mf);
  finally
    mf.Free;
  end;
end;

// the lines of Txt from the last Tf before Marker to Marker
function LastTextState(const Txt, Marker: RawUtf8): RawUtf8;
var
  m, p, q: PtrInt;
begin
  result := '';
  m := PosEx(Marker, Txt);
  p := 0;
  q := PosEx(' Tf'#10, Txt);
  while (q > 0) and
        (q < m) do
  begin
    p := q;
    q := PosEx(' Tf'#10, Txt, q + 1);
  end;
  if p = 0 then
    exit;
  while (p > 1) and
        (Txt[p - 1] <> #10) do
    dec(p);
  result := copy(Txt, p, m - p);
end;

// the size of the last Tf before Marker, 0 if none
function LastFontSize(const Txt, Marker: RawUtf8): double;
var
  state: RawUtf8;
begin
  state := LastTextState(Txt, Marker);
  result := GetExtended(pointer(GetCsvItem(pointer(state), 1, ' ')));
end;

// the /BaseFont names of Txt, in their order
function BaseFonts(const Txt: RawUtf8): RawUtf8;
var
  p, e: PtrInt;
begin
  result := '';
  p := PosEx('/BaseFont/', Txt);
  while p > 0 do
  begin
    e := p + 10;
    while (e <= length(Txt)) and
          not (Txt[e] in ['/', '>', ' ', #10]) do
      inc(e);
    result := result + copy(Txt, p + 10, e - p - 10) + ' ';
    p := PosEx('/BaseFont/', Txt, e);
  end;
end;

procedure TPdfImageGoldenTests.MetaFileStockFontMetrics;
const
  STOCK: array[0..2] of integer = (SYSTEM_FONT, DEFAULT_GUI_FONT,
    ANSI_FIXED_FONT);
  SCALES: array[0..1] of integer = (2, 32);
  ALIGNS: array[0..1] of integer = (TA_TOP, TA_BASELINE);
var
  i, m, a: integer;
  txt, ref, mapped: RawUtf8;
  paths, mpaths: TRawUtf8DynArray;
  b1, b2: TPdfBox;
begin
  { a stock font selected after a font of the metafile kept that font's
    LOGFONT and metrics: its text was drawn in the size, face and ascent
    of the font before; as GDI, it now takes the stock font's own, in
    device pixels under any map mode (DEFAULT_GUI_FONT is recorded as a
    font of the metafile) - and text before any selection had size 0 }
  for i := 0 to high(STOCK) do
  begin
    txt := StockFontEmf(STOCK[i], false, 1);
    ref := StockFontEmf(STOCK[i], true, 1);
    Check(LastTextState(ref, '(Stock) Tj') <> '', 'the reference drawn');
    CheckEqual(LastTextState(txt, '(Stock) Tj'),
      LastTextState(ref, '(Stock) Tj'),
      'the stock font''s own size and position');
    CheckEqual(BaseFonts(txt), BaseFonts(ref), 'the stock font''s own face');
    for m := 0 to high(SCALES) do
    begin
      mapped := StockFontEmf(STOCK[i], false, SCALES[m]);
      if STOCK[i] = DEFAULT_GUI_FONT then
        Check(Abs(LastFontSize(mapped, '(Stock) Tj') -
                  SCALES[m] * LastFontSize(txt, '(Stock) Tj')) < 0.02,
          'a font of the metafile: of logical units')
      else
        Check(Abs(LastFontSize(mapped, '(Stock) Tj') -
                  LastFontSize(txt, '(Stock) Tj')) < 0.02,
          'of device pixels under a map mode');
    end;
  end;
  // its position and background under a map mode: the rounded lfHeight was
  // 0 at 32 pixels per unit
  for a := 0 to high(ALIGNS) do
  begin
    txt := StockTextEmf(1, ALIGNS[a]);
    paths := PaintedPaths(txt);
    for m := 0 to high(SCALES) do
    begin
      mapped := StockTextEmf(SCALES[m], ALIGNS[a]);
      Check((Abs(OperandAt(mapped, '(Stock) Tj', 1, 0) -
                 OperandAt(txt, '(Stock) Tj', 1, 0)) < 0.05) and
            (Abs(OperandAt(mapped, '(Stock) Tj', 1, 1) -
                 OperandAt(txt, '(Stock) Tj', 1, 1)) < 0.05),
        'the stock text where it is in device pixels');
      // its width follows the advances, which the metafile records in
      // whole logical units
      mpaths := PaintedPaths(mapped);
      if (length(paths) = 1) and
         (length(mpaths) = 1) then
      begin
        b1 := PathBox(paths[0]);
        b2 := PathBox(mpaths[0]);
        Check((Abs(b1.Left - b2.Left) < 0.02) and
              (Abs(b1.Top - b2.Top) < 0.02) and
              (Abs(b1.Height - b2.Height) < 0.02), 'its background too');
      end
      else
        Check(false, 'its background too');
    end;
  end;
  txt := DefaultFontEmf;
  Check(LastFontSize(txt, '(Stock) Tj') > 0, 'the default font drawn');
  Check(Abs(LastFontSize(txt, '(Stock) Tj') - LastFontSize(
    StockFontEmf(SYSTEM_FONT, false, 1), '(Stock) Tj')) < 0.01,
    'in the size of SYSTEM_FONT');
  // a map mode set after the font: still of device pixels, the default
  // font of the start as one selected
  Check(Abs(LastFontSize(DefaultFontEmf(true), '(Stock) Tj') -
    LastFontSize(txt, '(Stock) Tj')) < 0.01, 'the default font after a map mode');
  Check(Abs(LastFontSize(DefaultFontEmf(true, true), '(Stock) Tj') -
    LastFontSize(txt, '(Stock) Tj')) < 0.01, 'a stock font after a map mode');
end;

procedure TPdfImageGoldenTests.MetaFileAnsiStockFont;
const
  ANSI: array[0..1] of byte = ($E1, $E2);
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  lf: TLogFontW;
  f, old: HFONT;
  bytes: RawByteString;
  recs: TIntegerDynArray;
  w, a: RawUtf8;
  str: PtrInt;
  i, stock: integer;

  // the bytes as CodePage reads them, drawn as a W record after the stock
  // font - one character on a DBCS code page (932, 936, 950)
  procedure Text(Y: integer; StockFont, CodePage: cardinal);
  var
    ws: array[0..1] of WideChar;
    n: integer;
  begin
    SelectObject(mc.Handle, GetStockObject(StockFont));
    n := MultiByteToWideChar(CodePage, 0, @ANSI, 2, @ws, 2);
    TextOutW(mc.Handle, 10, Y, @ws, n);
  end;

begin
  { a stock font selected after a font of the metafile left the code page of
    that font: an EMR_EXTTEXTOUTA drawn then decoded its bytes in it, not in
    the code page of the stock font - the system one, the OEM one for
    OEM_FIXED_FONT }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      FillChar(lf, SizeOf(lf), 0);
      lf.lfHeight := -16;
      lf.lfCharSet := GREEK_CHARSET;
      Utf8ToWideChar(@lf.lfFaceName, 'Arial');
      f := CreateFontIndirectW(lf);
      old := SelectObject(mc.Handle, f);
      Text(10, SYSTEM_FONT, CP_ACP);
      SelectObject(mc.Handle, f);
      Text(40, OEM_FIXED_FONT, CP_OEMCP);
      SelectObject(mc.Handle, old);
      DeleteObject(f);
    finally
      mc.Free;
    end;
    bytes := EmfBytes(mf);
    recs := EmfRecords(bytes, R_SELECTOBJECT);
    stock := 0; // the VCL canvas may select a stock font of its own
    for i := 0 to high(recs) do
      case PCardinal(@PByteArray(bytes)[recs[i] + 8])^ of
        $80000000 + SYSTEM_FONT:
          stock := stock or 1;
        $80000000 + OEM_FIXED_FONT:
          stock := stock or 2;
      end;
    CheckEqual(stock, 3, 'both stock fonts selected');
    recs := EmfRecords(bytes, R_EXTTEXTOUTW);
    if CheckEqual(length(recs), 2, 'two W records') then
    begin
      for i := 0 to 1 do
        PCardinal(@PByteArray(bytes)[recs[i] + 72])^ := 0; // no dx: see AnsiText
      mf.Handle := SetEnhMetaFileBits(length(bytes), pointer(bytes));
      w := RenderedEmf(mf);
      // the W records as A records of the two bytes
      for i := 0 to 1 do
      begin
        PCardinal(@PByteArray(bytes)[recs[i]])^ := R_EXTTEXTOUTA;
        PCardinal(@PByteArray(bytes)[recs[i] + 44])^ := 2; // EMRTEXT.nChars
        str := recs[i] + PInteger(@PByteArray(bytes)[recs[i] + 48])^;
        FillChar(PByteArray(bytes)[str], 4, 0);
        MoveFast(ANSI, PByteArray(bytes)[str], 2);
      end;
      mf.Handle := SetEnhMetaFileBits(length(bytes), pointer(bytes));
      a := RenderedEmf(mf);
    end;
  finally
    mf.Free;
  end;
  Check(w <> '', 'the W metafile rendered');
  CheckEqual(a, w, 'decoded in the code page of the stock font');
end;

procedure TPdfImageGoldenTests.MetaFileStockCodePages;
begin
  { ANSI_FIXED_FONT and ANSI_VAR_FONT got CP_ACP, though their charset is
    ANSI_CHARSET, cp1252 (Martin on #88): the decoded text differs only where
    the system code page is not 1252, the code page everywhere }
  CheckEqual(StockFontCodePage(ANSI_VAR_FONT), 1252, 'ANSI_VAR_FONT');
  CheckEqual(StockFontCodePage(ANSI_FIXED_FONT), 1252, 'ANSI_FIXED_FONT');
  CheckEqual(StockFontCodePage(OEM_FIXED_FONT), CP_OEMCP, 'OEM_FIXED_FONT');
  CheckEqual(FontCharSetCodePage(DEFAULT_CHARSET), CP_ACP, 'DEFAULT_CHARSET');
  CheckEqual(FontCharSetCodePage(GREEK_CHARSET), 1253, 'GREEK_CHARSET');
  CheckEqual(StockFontCodePage(BLACK_BRUSH), CP_ACP, 'no font');
end;

procedure TPdfImageGoldenTests.MetaFileDIBitsKept;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  bmi: TBitmapInfo;
  pix: array[0..15] of cardinal;
  before: RawByteString;
  first, second: RawUtf8;
  i: integer;
begin
  { with eM22 < 0, EMR_STRETCHDIBITS negated biHeight inside the record,
    which EnumEnhMetaFile hands out read-only. Windows 11 gives each
    enumeration its own copy, so the old code passed this too: it guards the
    flip in a copy of the header, not a measured failure }
  mf := TMetaFile.Create;
  try
    mf.Width := 200;
    mf.Height := 200;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      SetGraphicsMode(mc.Handle, GM_ADVANCED);
      FillChar(xf, SizeOf(xf), 0);
      xf.eM11 := 1;
      xf.eM22 := -1;
      xf.eDy := 150;
      SetWorldTransform(mc.Handle, xf);
      FillChar(bmi, SizeOf(bmi), 0);
      bmi.bmiHeader.biSize := SizeOf(bmi.bmiHeader);
      bmi.bmiHeader.biWidth := 4;
      bmi.bmiHeader.biHeight := 4;
      bmi.bmiHeader.biPlanes := 1;
      bmi.bmiHeader.biBitCount := 32;
      for i := 0 to high(pix) do
        pix[i] := cardinal(i) * $00101010; // a top-bottom gradient
      StretchDIBits(mc.Handle, 10, 10, 64, 64, 0, 0, 4, 4, @pix, bmi,
        DIB_RGB_COLORS, SRCCOPY);
    finally
      mc.Free;
    end;
    before := EmfBytes(mf);
    CheckEqual(length(EmfRecords(before, R_STRETCHDIBITS)), 1,
      'recorded as EMR_STRETCHDIBITS');
    first := RenderedEmf(mf);
    second := RenderedEmf(mf);
    Check(EmfBytes(mf) = before, 'the metafile unchanged');
  finally
    mf.Free;
  end;
  CheckEqual(CountOccurrences('/Subtype/Image', first), 1, 'the bitmap');
  CheckEqual(second, first, 'drawn the same twice');
end;

procedure TPdfImageGoldenTests.MetaFilePrinterRes;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  auto, zero: RawUtf8;
  raised: boolean;
begin
  { MM_ISOTROPIC divides by the printer resolution: one of 0 - a printer DC
    that failed - was kept, as only its X was checked }
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      SetMapMode(mc.Handle, MM_ISOTROPIC);
      SetWindowExtEx(mc.Handle, 1000, 1000, nil);
      SetViewportExtEx(mc.Handle, 300, 300, nil);
      Windows.Rectangle(mc.Handle, 100, 100, 600, 400);
    finally
      mc.Free;
    end;
    auto := RenderedEmf(mf); // the resolution asked from the printer
    raised := false;
    try
      zero := RenderedEmf(mf, 300, 0);
    except
      raised := true;
    end;
  finally
    mf.Free;
  end;
  Check(not raised, 'rendered with a resolution of 0');
  Check(auto <> '', 'rendered');
  CheckEqual(zero, auto, 'asked again');
end;

procedure TPdfImageGoldenTests.MetaFileBoxes;

  // the painted paths of a polygon and of four shapes on its corners,
  // recorded at K logical units per pixel, VX and VY < 0 mirroring an axis
  function Shapes(K, VX, VY: integer): TRawUtf8DynArray;
  var
    mf: TMetaFile;
    mc: TMetaFileCanvas;
    r: Windows.TRect; // not the TRect of mormot.pdf
    pts: array[0..3] of Windows.TPoint;
    i: integer;
  begin
    mf := TMetaFile.Create;
    try
      mf.Width := 100;
      mf.Height := 100;
      mc := TMetaFileCanvas.Create(mf, 0);
      try
        if K > 1 then
        begin
          SetMapMode(mc.Handle, MM_ANISOTROPIC);
          SetWindowExtEx(mc.Handle, 100 * K, 100 * K, nil);
          SetViewportExtEx(mc.Handle, VX, VY, nil);
          SetViewportOrgEx(mc.Handle, 60 * ord(VX < 0), 60 * ord(VY < 0), nil);
        end;
        // the reference: GDI records the points of a polygon as they are
        for i := 0 to 3 do
        begin
          pts[i].X := (10 + 40 * ord(i in [1, 2])) * K;
          pts[i].Y := (10 + 40 * ord(i >= 2)) * K;
        end;
        Windows.Polygon(mc.Handle, pts, 4);
        Windows.Rectangle(mc.Handle, 10 * K, 10 * K, 50 * K, 50 * K);
        Windows.Ellipse(mc.Handle, 10 * K, 10 * K, 50 * K, 50 * K);
        Windows.RoundRect(mc.Handle, 10 * K, 10 * K, 50 * K, 50 * K,
          16 * K, 16 * K);
        r.Left := 10 * K;
        r.Top := 10 * K;
        r.Right := 50 * K;
        r.Bottom := 50 * K;
        Windows.FillRect(mc.Handle, r, GetStockObject(BLACK_BRUSH));
      finally
        mc.Free;
      end;
      result := PaintedPaths(RenderedEmf(mf));
    finally
      mf.Free;
    end;
  end;

  // each shape on the box of the polygon
  procedure SameBoxes(const Paths: TRawUtf8DynArray; const Msg: string);
  var
    ref, b: TPdfBox;
    i: integer;
  begin
    if CheckFailed(length(Paths) = 5, Msg) then
      exit;
    ref := PathBox(Paths[0]);
    for i := 1 to 4 do
    begin
      b := PathBox(Paths[i]);
      Check((Abs(b.Left - ref.Left) < 0.02) and
            (Abs(b.Top - ref.Top) < 0.02) and
            (Abs(b.Width - ref.Width) < 0.02) and
            (Abs(b.Height - ref.Height) < 0.02), Msg);
    end;
  end;

var
  px, mapped, mirrored: TRawUtf8DynArray;
  a, b: TPdfBox;
  i: integer;
begin
  { GDI records the right and bottom of Rectangle, Ellipse and RoundRect one
    device pixel inside (49 for 50, 490 for 500 at 10 units per pixel; 500,110
    for 100..500 with the axis mirrored) and a FillRect as an exclusive
    EMR_BITBLT: BoxI removed one logical unit more from all of them,
    RoundRectI none, and its corners were not mapped (synopse/mORMot2#686) }
  px := Shapes(1, 100, 100);
  mapped := Shapes(10, 100, 100);
  SameBoxes(px, 'on the polygon');
  SameBoxes(mapped, 'on the polygon at 10 units per pixel');
  mirrored := Shapes(10, -100, -100);
  SameBoxes(mirrored, 'on the polygon, mirrored');
  // mirrored at the origin 60: the polygon covers the same device pixels
  if (mirrored <> nil) and
     (px <> nil) then
  begin
    a := PathBox(mirrored[0]);
    b := PathBox(px[0]);
    Check((Abs(a.Left - b.Left) < 0.02) and (Abs(a.Top - b.Top) < 0.02) and
          (Abs(a.Width - b.Width) < 0.02) and (Abs(a.Height - b.Height) < 0.02),
      'mirrored: the same place');
  end
  else
    Check(false, 'mirrored: the same place');
  if length(mapped) = length(px) then
    for i := 0 to high(px) do
      CheckEqual(mapped[i], px[i], 'the same at 10 units per pixel');
end;

// a polygon on 10..50, then a clip and text or a shape, recorded at K
// logical units per pixel, VX < 0 mirroring X - Kind:
// 0 a region of device pixels 0..90 intersected with 10..50, then text
// 1 the rectangle 10..50 of an ETO_CLIPPED ExtTextOut
// 2 IntersectClipRect 10..50 alone, then a rectangle and text
// 3 the region alone, then text
// 4 10..70 intersected with 0..50, then a rectangle
// 5 IntersectClipRect 10..50 between SaveDC and RestoreDC, then text
// 6 10..20 intersected with 30..40, then a rectangle
function ClipBoxEmf(Kind, K, VX: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  r: Windows.TRect;
  pts: array[0..3] of Windows.TPoint;
  i: integer;
  dc: HDC;
  rgn: HRGN;
begin
  mf := TMetaFile.Create;
  try
    mf.Width := 100;
    mf.Height := 100;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      dc := mc.Handle;
      if K > 1 then
      begin
        SetMapMode(dc, MM_ANISOTROPIC);
        SetWindowExtEx(dc, 100 * K, 100 * K, nil);
        SetViewportExtEx(dc, VX, 100, nil);
        SetViewportOrgEx(dc, 60 * ord(VX < 0), 0, nil);
      end;
      for i := 0 to 3 do
      begin
        pts[i].X := (10 + 40 * ord(i in [1, 2])) * K;
        pts[i].Y := (10 + 40 * ord(i >= 2)) * K;
      end;
      Windows.Polygon(dc, pts, 4);
      if Kind in [0, 3] then
      begin
        rgn := CreateRectRgn(0, 0, 90, 90); // device pixels
        SelectClipRgn(dc, rgn);
        DeleteObject(rgn);
      end;
      if Kind = 5 then
        SaveDC(dc);
      case Kind of
        0, 2, 5:
          IntersectClipRect(dc, 10 * K, 10 * K, 50 * K, 50 * K);
        4:
          begin
            IntersectClipRect(dc, 10 * K, 10 * K, 70 * K, 70 * K);
            IntersectClipRect(dc, 0, 0, 50 * K, 50 * K);
          end;
        6:
          begin
            IntersectClipRect(dc, 10 * K, 10 * K, 20 * K, 20 * K);
            IntersectClipRect(dc, 30 * K, 30 * K, 40 * K, 40 * K);
          end;
      end;
      if Kind = 5 then
        RestoreDC(dc, -1);
      if Kind in [2, 4, 6] then
        Windows.Rectangle(dc, 0, 0, 90 * K, 90 * K);
      if Kind = 1 then
      begin
        r.Left := 10 * K;
        r.Top := 10 * K;
        r.Right := 50 * K;
        r.Bottom := 50 * K;
        ExtTextOutW(dc, 5 * K, 5 * K, ETO_CLIPPED, @r, 'Clipped', 7, nil);
      end
      else if Kind in [0, 2, 3, 5] then
        TextOutW(dc, 5 * K, 5 * K, 'Clipped', 7);
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf); // tcAlwaysClip
  finally
    mf.Free;
  end;
end;

// the last clip rectangle (re h W) before Before in Txt, normalized, and
// the position of its W; false if none
function LastClip(const Txt: RawUtf8; Before: PtrInt; out Box: TPdfBox;
  out At: PtrInt): boolean;
var
  p, l: PtrInt;
  line: RawUtf8;
  v: array[0..3] of double;
  i: integer;
begin
  result := false;
  p := PosEx(' re'#10'h'#10'W'#10, Txt);
  while (p > 0) and
        (p < Before) do
  begin
    l := p;
    while (l > 1) and
          (Txt[l - 1] <> #10) do
      dec(l);
    line := copy(Txt, l, p - l);
    for i := 0 to 3 do
      v[i] := GetExtended(pointer(GetCsvItem(pointer(line), i, ' ')));
    Box.Left := v[0];
    Box.Width := v[2];
    Box.Top := v[1];
    Box.Height := v[3];
    if Box.Width < 0 then
    begin
      Box.Left := Box.Left + Box.Width;
      Box.Width := -Box.Width;
    end;
    if Box.Height < 0 then
    begin
      Box.Top := Box.Top + Box.Height;
      Box.Height := -Box.Height;
    end;
    At := p + 6;
    result := true;
    p := PosEx(' re'#10'h'#10'W'#10, Txt, p + 1);
  end;
end;

// the clip at At still holds at Pos: no Q between them
function ClipHolds(const Txt: RawUtf8; At, Pos: PtrInt): boolean;
var
  q: PtrInt;
begin
  q := PosEx(#10'Q'#10, Txt, At);
  result := (Pos > At) and
            ((q = 0) or
             (q > Pos));
end;

procedure TPdfImageGoldenTests.MetaFileClipBoxes;
const
  SCALE: array[0..2] of integer = (1, 10, 10);
  VIEW: array[0..2] of integer = (100, 100, -100);
var
  kind, s: integer;
  txt: RawUtf8;
  paths: TRawUtf8DynArray;
  poly, clip: TPdfBox;
  bt, paint, at: PtrInt;
  msg: string;
begin
  { the clip of IntersectClipRect and of an ETO_CLIPPED ExtTextOut is the
    exclusive rectangle, on the box of a polygon of the same points:
    IntersectClipRect clipped nothing without a region and to an empty
    box after one, as did any text after a region, and BoxI took a
    logical unit off both rectangles; the region of device pixels was
    mapped as logical units, ten times too small at 10 units per pixel }
  for kind := 0 to 6 do
    for s := 0 to high(SCALE) do
    begin
      msg := Utf8ToString(FormatUtf8('kind % at % units per pixel, view %',
        [kind, SCALE[s], VIEW[s]]));
      txt := ClipBoxEmf(kind, SCALE[s], VIEW[s]);
      paths := PaintedPaths(txt);
      if CheckFailed(length(paths) > 0, msg) then
        continue;
      poly := PathBox(paths[0]);
      bt := PosEx(#10'BT'#10, txt);
      paint := PosEx(#10'B'#10, txt, PosEx(#10'B'#10, txt) + 1); // the rectangle
      case kind of
        0, 1, 2:
          Check(LastClip(txt, bt, clip, at) and
                SameBox(clip, poly) and
                ClipHolds(txt, at, bt), msg);
        3:
          Check(LastClip(txt, bt, clip, at) and
                SameBox(clip, PdfBox(0, 842 - 67.5, 67.5, 67.5)) and
                ClipHolds(txt, at, bt), msg);
        4:
          Check(LastClip(txt, paint, clip, at) and
                SameBox(clip, poly) and
                ClipHolds(txt, at, paint), msg);
        5: // the text drawn, no clip left at it
          Check((bt > 0) and
                (not LastClip(txt, bt, clip, at) or
                 not ClipHolds(txt, at, bt)), msg);
        6:
          Check(LastClip(txt, paint, clip, at) and
                (clip.Width * clip.Height = 0) and
                ClipHolds(txt, at, paint), msg);
      end;
      if kind = 2 then // the shape too
        Check(LastClip(txt, paint, clip, at) and
              SameBox(clip, poly) and
              ClipHolds(txt, at, paint), msg);
    end;
end;

// a polygon on 10..50 and four shapes on the same box under a world scale
// World (GM_ADVANCED), at K units per pixel, rendered at the scale Render
function WorldBoxEmf(World: single; K: integer; Render: single): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  r: Windows.TRect;
  pts: array[0..3] of Windows.TPoint;
  i: integer;
  dc: HDC;
begin
  mf := TMetaFile.Create;
  try
    mf.Width := 200;
    mf.Height := 200;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      dc := mc.Handle;
      if K > 1 then
      begin
        SetMapMode(dc, MM_ANISOTROPIC);
        SetWindowExtEx(dc, 100 * K, 100 * K, nil);
        SetViewportExtEx(dc, 100, 100, nil);
      end;
      SetGraphicsMode(dc, GM_ADVANCED);
      FillChar(xf, SizeOf(xf), 0);
      xf.eM11 := World;
      xf.eM22 := World;
      SetWorldTransform(dc, xf);
      for i := 0 to 3 do
      begin
        pts[i].X := (10 + 40 * ord(i in [1, 2])) * K;
        pts[i].Y := (10 + 40 * ord(i >= 2)) * K;
      end;
      Windows.Polygon(dc, pts, 4);
      Windows.Rectangle(dc, 10 * K, 10 * K, 50 * K, 50 * K);
      Windows.Ellipse(dc, 10 * K, 10 * K, 50 * K, 50 * K);
      Windows.RoundRect(dc, 10 * K, 10 * K, 50 * K, 50 * K, 16 * K, 16 * K);
      r.Left := 10 * K;
      r.Top := 10 * K;
      r.Right := 50 * K;
      r.Bottom := 50 * K;
      Windows.FillRect(dc, r, GetStockObject(BLACK_BRUSH));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf, 0, 0, tcAlwaysClip, Render, Render);
  finally
    mf.Free;
  end;
end;

procedure TPdfImageGoldenTests.MetaFileWorldBoxes;
const
  WORLD: array[0..4] of single = (1, 2, 0.5, 3, 1.5);
  RENDER: array[0..1] of single = (1, -1);
  PX = 0.75; // one device pixel at 96 dpi
var
  w, k, i, s: integer;
  paths: TRawUtf8DynArray;
  poly, incl, b: TPdfBox;
  msg: string;
begin
  { GM_ADVANCED records Rectangle, Ellipse and RoundRect as called and GDI
    paints them with the right and bottom edges: 81 device pixels for
    10..50 under a world scale of 2, 21 under 0.5 (measured on a memory
    DC). BoxInclI added one logical unit per device pixel of the map mode,
    not divided by the world factor: 82 and 20.5. FillRect stays exclusive.
    Rendered at a negative scale, the device's right and bottom are the
    left and top of the page }
  for s := 0 to high(RENDER) do
  for k := 1 to 2 do
    for w := 0 to high(WORLD) do
    begin
      msg := Utf8ToString(FormatUtf8('world % at % units per pixel, scale %',
        [WORLD[w], 1 + 9 * (k - 1), RENDER[s]]));
      paths := PaintedPaths(WorldBoxEmf(WORLD[w], 1 + 9 * (k - 1), RENDER[s]));
      if CheckFailed(length(paths) = 5, msg) then
        continue;
      poly := PathBox(paths[0]);
      // one device pixel more, right and bottom
      if RENDER[s] > 0 then
        incl := PdfBox(poly.Left, poly.Top - PX, poly.Width + PX,
          poly.Height + PX)
      else
        incl := PdfBox(poly.Left - PX, poly.Top, poly.Width + PX,
          poly.Height + PX);
      for i := 1 to 4 do
      begin
        b := PathBox(paths[i]);
        if i = 4 then
          Check(SameBox(b, poly), msg) // FillRect
        else
          Check(SameBox(b, incl), msg);
      end;
    end;
end;

// a bitmap on 10..50 at K logical units per pixel, alone in the metafile
function BitmapBoundsEmf(K: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  bmi: TBitmapInfo;
  pix: array[0..15] of cardinal;
  i: integer;
begin
  mf := TMetaFile.Create;
  try
    mf.Width := 100;
    mf.Height := 100;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      if K > 1 then
      begin
        SetMapMode(mc.Handle, MM_ANISOTROPIC);
        SetWindowExtEx(mc.Handle, 100 * K, 100 * K, nil);
        SetViewportExtEx(mc.Handle, 100, 100, nil);
      end;
      FillChar(bmi, SizeOf(bmi), 0);
      bmi.bmiHeader.biSize := SizeOf(bmi.bmiHeader);
      bmi.bmiHeader.biWidth := 4;
      bmi.bmiHeader.biHeight := 4;
      bmi.bmiHeader.biPlanes := 1;
      bmi.bmiHeader.biBitCount := 32;
      for i := 0 to high(pix) do
        pix[i] := cardinal(i) * $00101010;
      StretchDIBits(mc.Handle, 10 * K, 10 * K, 40 * K, 40 * K, 0, 0, 4, 4,
        @pix, bmi, DIB_RGB_COLORS, SRCCOPY);
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf);
  finally
    mf.Free;
  end;
end;

// text in Arial of 20 device pixels at K logical units per pixel, rendered
// with tcClipExplicit: clipped to the bounds of its record
function TextBoundsEmf(K: integer): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  lf: TLogFontW;
  f: HFONT;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight := -20 * K;
  Utf8ToWideChar(@lf.lfFaceName, 'Arial');
  f := CreateFontIndirectW(lf);
  mf := TMetaFile.Create;
  try
    mf.Width := 200;
    mf.Height := 100;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      if K > 1 then
      begin
        SetMapMode(mc.Handle, MM_ANISOTROPIC);
        SetWindowExtEx(mc.Handle, 100 * K, 100 * K, nil);
        SetViewportExtEx(mc.Handle, 100, 100, nil);
      end;
      SelectObject(mc.Handle, f);
      SetBkMode(mc.Handle, TRANSPARENT);
      TextOutW(mc.Handle, 10 * K, 10 * K, 'Bounds', 6);
      SelectObject(mc.Handle, GetStockObject(SYSTEM_FONT));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf, 0, 0, tcClipExplicit);
  finally
    mf.Free;
    DeleteObject(f);
  end;
end;

// the content stream of the page: the first stream of Txt
function FirstStream(const Txt: RawUtf8): RawUtf8;
var
  p: PtrInt;
begin
  p := PosEx('stream'#10, Txt);
  result := copy(Txt, p, PosEx('endstream', Txt, p) - p);
end;

procedure TPdfImageGoldenTests.MetaFileBitmapBounds;
var
  px, mapped: RawUtf8;
  clip, b: TPdfBox;
  at: PtrInt;
  k: integer;
begin
  { the bounds of EMR_HEADER clip a bitmap without a region: device pixels,
    the right and bottom ones included, which BoxI took as exclusive
    logical units less one - a bitmap at the edge lost two pixels }
  for k := 0 to 1 do
  begin
    px := FirstStream(BitmapBoundsEmf(1 + 9 * k));
    Check((PosEx(' Do'#10, px) > 0) and
          (Abs(OperandAt(px, #10'W'#10, 0, 2) - OperandAt(px, ' cm'#10, 0, 0)) < 0.02) and
          (Abs(OperandAt(px, #10'W'#10, 0, 3) - OperandAt(px, ' cm'#10, 0, 3)) < 0.02) and
          (Abs(OperandAt(px, #10'W'#10, 0, 0) - OperandAt(px, ' cm'#10, 0, 4)) < 0.02) and
          (Abs(OperandAt(px, #10'W'#10, 0, 1) - OperandAt(px, ' cm'#10, 0, 5)) < 0.02),
      'the bitmap within its clip');
  end;
  { the bounds of an ExtTextOut, tcClipExplicit, are device pixels too, but
    were mapped as logical units: ten times too small at 10 per pixel }
  px := TextBoundsEmf(1);
  mapped := TextBoundsEmf(10);
  Check(LastClip(px, PosEx(#10'BT'#10, px), clip, at) and
        (clip.Width > 20), 'the text clipped to its bounds');
  Check(LastClip(mapped, PosEx(#10'BT'#10, mapped), b, at) and
        SameBox(b, clip), 'the same bounds at 10 units per pixel');
end;

// a rectangle and text under the world transform M11, M12, M21, M22 moved
// to 300,100; Prior: after a scale by 2 and a move by 50
function WorldRotationEmf(M11, M12, M21, M22: single; Prior: boolean): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  lf: TLogFontW;
  f: HFONT;
  dc: HDC;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight := -20;
  Utf8ToWideChar(@lf.lfFaceName, 'Arial');
  f := CreateFontIndirectW(lf);
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      dc := mc.Handle;
      SetGraphicsMode(dc, GM_ADVANCED);
      SelectObject(dc, f);
      SetBkMode(dc, TRANSPARENT);
      FillChar(xf, SizeOf(xf), 0);
      if Prior then
      begin
        xf.eM11 := 2;
        xf.eM22 := 2;
        xf.eDx := 50;
        xf.eDy := 50;
        SetWorldTransform(dc, xf);
      end;
      xf.eM11 := M11;
      xf.eM12 := M12;
      xf.eM21 := M21;
      xf.eM22 := M22;
      xf.eDx := 300;
      xf.eDy := 100;
      SetWorldTransform(dc, xf);
      Windows.Rectangle(dc, 10, 10, 50, 50);
      TextOutW(dc, 40, 40, 'Turned', 6);
      SelectObject(dc, GetStockObject(SYSTEM_FONT));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf);
  finally
    mf.Free;
    DeleteObject(f);
  end;
end;

procedure TPdfImageGoldenTests.MetaFileWorldRotation;
const
  // a rotation by 90 and by 30 degrees, a shear
  M: array[0..2, 0..3] of single = ((0, 1, -1, 0),
    (0.866025, 0.5, -0.5, 0.866025), (1, 0, 0.5, 1));
var
  i: integer;
  fresh, prior: RawUtf8;
  a, b: TRawUtf8DynArray;
  msg: string;
begin
  { a rotation or a shear kept the scale and the move of the transform
    before it: what was drawn depended on it (the turned text of emf_world
    twice its size); without the factor and offset, the same drawing.
    The text matrix negated all four terms: right at 90 and 270 degrees
    only, a text at 30 degrees was drawn at 150 }
  for i := 0 to high(M) do
  begin
    msg := Utf8ToString(FormatUtf8('matrix %', [i]));
    fresh := WorldRotationEmf(M[i, 0], M[i, 1], M[i, 2], M[i, 3], false);
    prior := WorldRotationEmf(M[i, 0], M[i, 1], M[i, 2], M[i, 3], true);
    a := PaintedPaths(fresh);
    b := PaintedPaths(prior);
    Check((length(a) = 1) and
          (length(b) = 1) and
          SameBox(PathBox(a[0]), PathBox(b[0])), msg);
    CheckEqual(LastTextState(prior, '(Turned) Tj'),
      LastTextState(fresh, '(Turned) Tj'), msg);
    // the text matrix of a rotation: Y goes down in GDI, up in PDF
    if i < 2 then
      Check((Abs(OperandAt(fresh, ' Tm'#10, 0, 0) - M[i, 0]) < 0.01) and
            (Abs(OperandAt(fresh, ' Tm'#10, 0, 1) + M[i, 1]) < 0.01) and
            (Abs(OperandAt(fresh, ' Tm'#10, 0, 2) + M[i, 2]) < 0.01) and
            (Abs(OperandAt(fresh, ' Tm'#10, 0, 3) - M[i, 3]) < 0.01),
        msg + ': the text turned as GDI turns it');
  end;
end;

// a rectangle 10..50 with a pen 3 wide and text at 40,40 under the world
// scale M11, M22, moved back into the picture where negative, the viewport's
// origin at 20,10; Reference: the same rectangle and pen at the page's
// coordinates, no transform, and the text aligned where GDI's mirrored one is
function WorldReflectionEmf(M11, M22: single; Reference: boolean): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  lf: TLogFontW;
  f: HFONT;
  pen: HPEN;
  dc: HDC;
  dx, dy: single;
  x1, x2, y1, y2: integer;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight := -20;
  lf.lfUnderline := 1;
  Utf8ToWideChar(@lf.lfFaceName, 'Arial');
  f := CreateFontIndirectW(lf);
  dx := 100 * Abs(M11) * ord(M11 < 0);
  dy := 100 * Abs(M22) * ord(M22 < 0);
  if Reference then
    pen := CreatePen(PS_SOLID, round(3 * Abs(M11)), 0)
  else
    pen := CreatePen(PS_SOLID, 3, 0);
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      dc := mc.Handle;
      SetGraphicsMode(dc, GM_ADVANCED);
      SetViewportOrgEx(dc, 20, 10, nil);
      SelectObject(dc, f);
      SelectObject(dc, pen);
      SetBkMode(dc, TRANSPARENT);
      x1 := round(M11 * 10 + dx);
      x2 := round(M11 * 50 + dx);
      y1 := round(M22 * 10 + dy);
      y2 := round(M22 * 50 + dy);
      if Reference then
      begin
        Windows.Rectangle(dc, MinPtrInt(x1, x2), MinPtrInt(y1, y2),
          MaxPtrInt(x1, x2), MaxPtrInt(y1, y2));
        // mirrored on X, the text ends at the reference point; on Y, it
        // stands on it
        if (M11 < 0) <> (M22 < 0) then
        begin
          SetTextAlign(dc, TA_RIGHT * ord(M11 < 0) + TA_BOTTOM * ord(M22 < 0));
          TextOutW(dc, round(M11 * 40 + dx), round(M22 * 40 + dy), 'Mirror', 6);
        end;
      end
      else
      begin
        FillChar(xf, SizeOf(xf), 0);
        xf.eM11 := M11;
        xf.eM22 := M22;
        xf.eDx := dx;
        xf.eDy := dy;
        SetWorldTransform(dc, xf);
        Windows.Rectangle(dc, 10, 10, 50, 50);
        if (M11 < 0) and
           (M22 < 0) then
          SetTextAlign(dc, TA_BASELINE); // the glyphs' start: the point
        TextOutW(dc, 40, 40, 'Mirror', 6);
      end;
      SelectObject(dc, GetStockObject(SYSTEM_FONT));
      SelectObject(dc, GetStockObject(BLACK_PEN));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf);
  finally
    mf.Free;
    DeleteObject(f);
    DeleteObject(pen);
  end;
end;

// underlined text turned by 90 degrees (lfEscapement) under the world scale
// M11, M22, moved back into the picture; InPath: filled as a GDI path
function MirroredTurnedEmf(M11, M22: single; InPath: boolean): RawUtf8;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  xf: TXForm;
  lf: TLogFontW;
  f: HFONT;
  dc: HDC;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight := -20;
  lf.lfEscapement := 900;
  lf.lfUnderline := 1;
  Utf8ToWideChar(@lf.lfFaceName, 'Arial');
  f := CreateFontIndirectW(lf);
  mf := TMetaFile.Create;
  try
    mf.Width := 400;
    mf.Height := 400;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      dc := mc.Handle;
      SetGraphicsMode(dc, GM_ADVANCED);
      SelectObject(dc, f);
      SetBkMode(dc, TRANSPARENT);
      FillChar(xf, SizeOf(xf), 0);
      xf.eM11 := M11;
      xf.eM22 := M22;
      xf.eDx := 200 * ord(M11 < 0);
      xf.eDy := 200 * ord(M22 < 0);
      SetWorldTransform(dc, xf);
      if InPath then
        BeginPath(dc);
      TextOutW(dc, 60, 120, 'Turned', 6);
      if InPath then
      begin
        EndPath(dc);
        FillPath(dc);
      end;
      SelectObject(dc, GetStockObject(SYSTEM_FONT));
    finally
      mc.Free;
    end;
    result := RenderedEmf(mf);
  finally
    mf.Free;
    DeleteObject(f);
  end;
end;

// the lowest and highest projection of the l points of Path on the line of
// the glyphs (Tm of Txt): along it from where they start
procedure GlyphProjections(const Txt, Path: RawUtf8; out Lo, Hi: double);
var
  lines: TRawUtf8DynArray;
  i: PtrInt;
  a, b, e, f, n, x, y, d: double;
begin
  a := OperandAt(Txt, ' Tm'#10, 0, 0);
  b := OperandAt(Txt, ' Tm'#10, 0, 1);
  e := OperandAt(Txt, ' Tm'#10, 0, 4);
  f := OperandAt(Txt, ' Tm'#10, 0, 5);
  n := Sqrt(a * a + b * b);
  Lo := 1E9;
  Hi := -1E9;
  lines := nil;
  CsvToRawUtf8DynArray(pointer(Path), lines, #10);
  for i := 0 to high(lines) do
    if (length(lines[i]) > 2) and
       (copy(lines[i], length(lines[i]) - 1, 2) = ' l') then
    begin
      x := GetExtended(pointer(GetCsvItem(pointer(lines[i]), 0, ' ')));
      y := GetExtended(pointer(GetCsvItem(pointer(lines[i]), 1, ' ')));
      d := ((x - e) * a + (y - f) * b) / n;
      if d < Lo then
        Lo := d;
      if d > Hi then
        Hi := d;
    end;
end;

procedure TPdfImageGoldenTests.MetaFileWorldReflection;
const
  M: array[0..4, 0..1] of single = ((-1, 1), (1, -1), (-1, -1), (-2, -2),
    (-1, -2));
var
  i, k: integer;
  lo, hi: double;
  txt, ref: RawUtf8;
  a, b: TRawUtf8DynArray;
  msg: string;
begin
  { a reflection (a negative scale, no shear) was not applied at all: what
    was drawn under it stayed where it was. A scale with negative factors
    mirrors the shapes on the page, with a positive line width; a turn by
    180 degrees (both negative) turns the text too, at the scale's size.
    The world transform comes before the viewport's origin: it was applied
    after it; and the upright glyphs stand where GDI's mirrored ones are }
  for i := 0 to high(M) do
  begin
    msg := Utf8ToString(FormatUtf8('scale % %', [M[i, 0], M[i, 1]]));
    txt := WorldReflectionEmf(M[i, 0], M[i, 1], false);
    ref := WorldReflectionEmf(M[i, 0], M[i, 1], true);
    a := PaintedPaths(txt);
    b := PaintedPaths(ref);
    Check((length(a) >= 1) and
          (length(b) >= 1) and
          SameBox(PathBox(a[0]), PathBox(b[0])), msg);
    Check(Abs(OperandAt(txt, ' w'#10, 0, 0) - OperandAt(ref, ' w'#10, 0, 0)) < 0.01,
      msg + ': the line width');
    if (M[i, 0] < 0) and
       (M[i, 1] < 0) then
    begin
      // the device point of 40,40 under the scale, at 0.75 pt per pixel
      Check((OperandAt(txt, ' Tm'#10, 0, 0) < 0) and
            (OperandAt(txt, ' Tm'#10, 0, 3) < 0) and
            (Abs(OperandAt(txt, ' Tm'#10, 0, 4) -
              (M[i, 0] * 40 + 100 * Abs(M[i, 0]) + 20) * 0.75) < 0.05) and
            (Abs(OperandAt(txt, ' Tm'#10, 0, 5) - (842 -
              (M[i, 1] * 40 + 100 * Abs(M[i, 1]) + 10) * 0.75)) < 0.05),
        msg + ': the text turned by 180 degrees');
      Check(Abs(LastFontSize(txt, '(Mirror) Tj') * Abs(OperandAt(txt, ' Tm'#10, 0, 0)) -
        15 * Abs(M[i, 1])) < 0.05, msg + ': in the size of the scale');
      // its underline turned with it: to the left, above the baseline
      if length(a) = 2 then
      begin
        GlyphProjections(txt, a[1], lo, hi);
        Check((lo > -0.5) and
              (hi > 5) and
              (PathBox(a[1]).Top > OperandAt(txt, ' Tm'#10, 0, 5)),
          msg + ': its underline turned');
      end
      else
        Check(false, msg + ': its underline turned');
      // and under a font's angle, which turns the glyphs without the world
      for k := 0 to 1 do
      begin
        txt := MirroredTurnedEmf(M[i, 0], M[i, 1], k = 1);
        a := PaintedPaths(txt);
        if length(a) = 0 then
          Check(false, msg + ': the turned underline drawn')
        else
        begin
          GlyphProjections(txt, a[0], lo, hi);
          Check((lo > -0.5) and
                (hi > 5), msg + ': the underline along the font''s glyphs');
        end;
      end;
    end
    else
    begin
      Check((Abs(OperandAt(txt, ' Td'#10, 0, 0) - OperandAt(ref, ' Td'#10, 0, 0)) < 0.05) and
            (Abs(OperandAt(txt, ' Td'#10, 0, 1) - OperandAt(ref, ' Td'#10, 0, 1)) < 0.05),
        msg + ': the text where GDI mirrors it');
      Check((length(a) = 2) and
            (length(b) = 2) and
            SameBox(PathBox(a[1]), PathBox(b[1])), msg + ': its underline');
      // turned by the font: the underline, alone or a figure of a path,
      // goes the way the glyphs go from their start
      for k := 0 to 1 do
      begin
        txt := MirroredTurnedEmf(M[i, 0], M[i, 1], k = 1);
        a := PaintedPaths(txt);
        if length(a) = 0 then
          Check(false, msg + ': the turned underline drawn')
        else
        begin
          GlyphProjections(txt, a[0], lo, hi);
          Check((lo > -0.5) and
                (hi > 5), msg + ': the turned underline along the glyphs');
        end;
      end;
    end;
  end;
end;

procedure TPdfImageGoldenTests.MetaFileRecordLayout;
var
  mf: TMetaFile;
  mc: TMetaFileCanvas;
  lb: TLogBrush;
  bytes: RawByteString;
  txt: RawUtf8;
begin
  { the windows unit of FPC 3.2.2 declares EMR_CREATEBRUSHINDIRECT and
    EMR_EXTCREATEPEN with the native LOGBRUSH and EXTLOGPEN, whose ULONG_PTR
    hatch moves the fields on Win64: every brush and extended pen was black }
  mf := TMetaFile.Create;
  try
    mf.Width := 100;
    mf.Height := 100;
    mc := TMetaFileCanvas.Create(mf, 0);
    try
      DeleteObject(SelectObject(mc.Handle, CreateSolidBrush(RGB(255, 0, 0))));
      Windows.Rectangle(mc.Handle, 10, 10, 50, 50);
      lb.lbStyle := BS_SOLID;
      lb.lbColor := RGB(0, 0, 255);
      lb.lbHatch := 0;
      DeleteObject(SelectObject(mc.Handle,
        ExtCreatePen(PS_GEOMETRIC or PS_SOLID, 4, lb, 0, nil)));
      MoveToEx(mc.Handle, 10, 80, nil);
      LineTo(mc.Handle, 90, 80);
    finally
      mc.Free;
    end;
    bytes := EmfBytes(mf);
    Check(length(EmfRecords(bytes, R_CREATEBRUSHINDIRECT)) > 0,
      'recorded as EMR_CREATEBRUSHINDIRECT');
    CheckEqual(length(EmfRecords(bytes, R_EXTCREATEPEN)), 1,
      'recorded as EMR_EXTCREATEPEN');
    txt := RenderedEmf(mf);
  finally
    mf.Free;
  end;
  Check(PosEx(#10'1 0 0 rg'#10, txt) > 0, 'the brush colour');
  Check(PosEx(#10'0 0 1 RG'#10, txt) > 0, 'the extended pen colour');
end;

{$else}

procedure TPdfImageGoldenTests.MetaFileCanvas;
var
  i: integer;
begin
  for i := 1 to 6 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileRender;
var
  i: integer;
begin
  for i := 1 to 5 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileForm;
var
  i: integer;
begin
  for i := 1 to 9 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileFormState;
var
  i: integer;
begin
  for i := 1 to 8 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileWorldTransform;
var
  i: integer;
begin
  for i := 1 to 8 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileAlphaBlend;
var
  i: integer;
begin
  for i := 1 to 3 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFilePolyPolyline;
var
  i: integer;
begin
  for i := 1 to 4 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileRestoreDC;
var
  i: integer;
begin
  for i := 1 to 5 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileClipRestoreDC;
var
  i: integer;
begin
  for i := 1 to 24 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileUnderlineClipped;
var
  i: integer;
begin
  for i := 1 to 2 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileNullPenLines;
var
  i: integer;
begin
  for i := 1 to 6 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileLineAfterEndedPath;
var
  i: integer;
begin
  for i := 1 to 24 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileTextInPath;
var
  i: integer;
begin
  for i := 1 to 74 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileMarkedContentInPath;
var
  i: integer;
begin
  for i := 1 to 12 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileTransformAfterPath;
var
  i: integer;
begin
  for i := 1 to 5 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileScaledRotation;
var
  i: integer;
begin
  for i := 1 to 4 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileAnsiText;
var
  i: integer;
begin
  for i := 1 to 6 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileAnsiStockFont;
var
  i: integer;
begin
  for i := 1 to 4 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileStockFontMetrics;
var
  i: integer;
begin
  for i := 1 to 27 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileStockCodePages;
var
  i: integer;
begin
  for i := 1 to 6 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileDIBitsKept;
var
  i: integer;
begin
  for i := 1 to 4 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFilePrinterRes;
var
  i: integer;
begin
  for i := 1 to 3 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileBoxes;
var
  i: integer;
begin
  for i := 1 to 21 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileClipBoxes;
var
  i: integer;
begin
  for i := 1 to 45 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileWorldBoxes;
var
  i: integer;
begin
  for i := 1 to 100 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileBitmapBounds;
var
  i: integer;
begin
  for i := 1 to 4 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileWorldRotation;
var
  i: integer;
begin
  for i := 1 to 8 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileWorldReflection;
var
  i: integer;
begin
  for i := 1 to 33 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

procedure TPdfImageGoldenTests.MetaFileRecordLayout;
var
  i: integer;
begin
  for i := 1 to 4 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

{$endif OSWINDOWS}

{$endif PDF_HASVCLCANVAS}

end.
