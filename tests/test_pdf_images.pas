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
  {$endif OSWINDOWS}
  {$endif PDF_HASVCLCANVAS}
  Classes,
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.test,
  mormot.core.text,
  mormot.core.unicode,
  mormot.pdf,
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
    procedure MetaFileCanvas;
    procedure MetaFileRender;
    procedure MetaFileForm;
    procedure MetaFileFormState;
  end;

{$endif PDF_HASVCLCANVAS}


implementation

function CountOf(const Sub, Text: RawUtf8): integer;
var
  i: PtrInt;
begin
  result := 0;
  i := PosEx(Sub, Text);
  while i > 0 do
  begin
    inc(result);
    i := PosEx(Sub, Text, i + length(Sub));
  end;
end;

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
  CheckEqual(CountOf('/Subtype/Image', txt), 5, 'five images');
  rgb := ImageData(txt, names[0]);
  CheckEqual(length(rgb), RAW_W * RAW_H * 3, 'RGB rows');
  CheckEqual(ImageData(txt, names[1]), rgb, 'BGR padded = RGB');
  CheckEqual(ImageData(txt, names[2]), rgb, 'BGRx = RGB, x skipped');
  CheckEqual(length(ImageData(txt, names[3])), RAW_W * RAW_H, 'one index per pixel');
  CheckEqual(CountOf('<00070E 151C23 ', txt), 1, 'the palette');
  CheckEqual(CountOf('/Mask[10 10 20 20 200 200]', txt), 1, 'the color key');
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
  CheckEqual(CountOf('/Mask[10 10 20 20 200 200]', txt), 2, 'the key of BGRx, R G B');
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
  CheckEqual(CountOf('/ColorSpace/DeviceRGB', txt), 2, 'RGB');
  CheckEqual(CountOf(jpg, txt), 2, 'the data as it is');
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
  CheckEqual(CountOf('/Font<</' + key + ' ', txt), 3, 'listed by both pages');
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
  CheckEqual(CountOf('<</' + img + ' ', txt), 1, 'listed by the form');
  CheckEqual(CountOf('/Fca50<<', txt), 1, 'the alpha of the form');
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
  x, y, n, W: integer;
  p: PByteArray;
begin
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
  {$ifdef FPC}
  B.BeginUpdate(true);
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
        with img.Colors[x, y] do
        begin
          d[0] := AnsiChar(red shr 8);
          d[1] := AnsiChar(green shr 8);
          d[2] := AnsiChar(blue shr 8);
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
  CheckEqual(CountOf('/Subtype/Image', txt), 6, 'six images');
  CheckEqual(CountOf('/Indexed', txt), 3, 'the 1, 4 and 8 bit formats indexed');
  CheckEqual(CountOf('/Mask', txt), 1, 'the color key');
  Check(ImageData(txt, names[0]) = rgb24, 'pf24bit: the rows, RGB');
  Check(ImageData(txt, names[1]) = rgb32, 'pf32bit: the rows, RGB, x skipped');
  Check(ImageData(txt, names[2]) = idx8, 'pf8bit: the index bytes');
  {$ifdef FPC}
  CheckEqual(CountOf('<000000 010101 020202 ', txt), 3, 'a gray ramp each');
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
  CheckEqual(CountOf('/DCTDecode', txt), 3, 'three JPEG images');
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
  CheckEqual(CountOf('/Type/Page/', txt) + CountOf('/Type/Page>>', txt), 2,
    'two pages');
  Check(PosEx('/Outlines', txt) > 0, 'the outline comment');
  CheckEqual(CountOf('/Subtype/Image', txt), 1, 'the same bitmap on both pages');
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
  CheckEqual(CountOf('/Type/Page/', txt) + CountOf('/Type/Page>>', txt), 2,
    'two pages');
  CheckEqual(CountOf('/Subtype/Image', txt), 1, 'the bitmap, reused');
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
  CheckEqual(CountOf('/Type/Page/', txt) + CountOf('/Type/Page>>', txt), 2,
    'two pages');
  CheckEqual(CountOf('/Subtype/Form', txt), 2, 'two forms');
  // the size TMetaFile reports, in pixels of the reference DC (its DPI)
  CheckEqual(CountOf(FormatUtf8('/BBox[0 0 % %]', [w, h]), txt), 1,
    'the size of the metafile');
  CheckEqual(CountOf('/Subtype/Image', txt), 1, 'the bitmap, in the form');
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
    if CountOf(' BMC', s) + CountOf(' BDC', s) <> CountOf('EMC', s) then
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
  for i := 1 to 6 do
    Check(true, 'SKIP: metafiles are Windows only');
end;

{$endif OSWINDOWS}

{$endif PDF_HASVCLCANVAS}

end.
