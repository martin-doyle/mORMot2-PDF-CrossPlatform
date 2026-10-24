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
    /// a scaled rotation is drawn, without ArcSin/ArcCos of a value past 1
    procedure MetaFileScaledRotation;
    /// EMR_EXTTEXTOUTA reads bytes in the code page of the font
    procedure MetaFileAnsiText;
    /// EMR_STRETCHDIBITS under a flipped transform flips a copy of its header
    procedure MetaFileDIBitsKept;
    /// a printer resolution of 0 is asked again, not divided by
    procedure MetaFilePrinterRes;
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

// text of a metafile under world transforms: a pure uniform scale is no
// rotation - the EMF TextOut took it for one and drew the text turned by 180
// degrees, its text matrix negated (the trunk's a86d7e6fc)
const
  // the record types, by number: the windows unit of FPC lacks some names
  R_POLYPOLYLINE = 7;
  R_SAVEDC = 33;
  R_RESTOREDC = 34;
  R_STRETCHDIBITS = 81;
  R_EXTTEXTOUTA = 83;
  R_EXTTEXTOUTW = 84;
  R_POLYPOLYLINE16 = 90;
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
function RenderedEmf(Mf: TMetaFile; PxX: integer = 0; PxY: integer = 0): RawUtf8;
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
    doc.EmbeddedTTF := false;
    doc.StandardFontsReplace := true;
    TPdfDocumentGdiAccess(doc).fPrinterPxPerInch.X := PxX;
    TPdfDocumentGdiAccess(doc).fPrinterPxPerInch.Y := PxY;
    doc.AddPage;
    RenderMetaFile(doc.Canvas, Mf, 1, 1, 0, 0);
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
  p, i, j: PtrInt;
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
    result := '';
    while (j > 1) and
          not (Txt[j - 1] in [#10, #13]) do
    begin
      dec(j);
      result := Txt[j] + result;
    end;
  until false;
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
      ToAnsi(recs[1], AnsiChar($E1) + AnsiChar($E2)); // code page 1253
      ToAnsi(recs[2], 'A' + AnsiChar($82) + AnsiChar($A0) + 'B'); // code page 932
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

{$endif OSWINDOWS}

{$endif PDF_HASVCLCANVAS}

end.
