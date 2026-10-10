/// Cross-Platform PDF Engine: VCL/LCL Canvas Adapter
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.pdf.canvas;

{
  *****************************************************************************

    VCL/LCL Adapter of the PDF Engine
    - TBitmap/TGraphic images: CreateOrGetBitmapImage, CreateGraphicImage
    - TPdfDocumentGdi for GDI/TCanvas rendering support (Windows)
    - the paper size and resolution of the current printer (Windows)
    - needs the VCL or the LCL: not for Delphi on Linux or Android

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

{$I mormot.pdf.defines.inc} // the same switches as mormot.pdf

uses
  {$ifdef OSWINDOWS}
  windows,
  winspool,
  {$endif OSWINDOWS}
  {$ifdef USE_UNISCRIBE}
  mormot.lib.uniscribe,
  {$endif USE_UNISCRIBE}
  mormot.lib.core,
  {$ifdef FPC}
  lcltype,
  lclproc,
  lclintf,
  {$ifdef USE_METAFILE}
  mormot.ui.core, // for TMetaFile definition
  {$endif USE_METAFILE}
  {$endif FPC}
  {$ifdef NEEDVCLPREFIX}
  vcl.graphics,
  {$else}
  graphics,
  {$endif NEEDVCLPREFIX}
  sysutils,
  types,
  classes,
  math,
  {$ifdef USE_SYNGDIPLUS}
  mormot.ui.gdiplus,
  {$else}
  {$ifdef OSWINDOWS}
  jpeg,
  {$endif OSWINDOWS}
  {$endif USE_SYNGDIPLUS}
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.core.text,
  mormot.core.buffers,
  mormot.pdf.types,
  mormot.pdf;


{$ifdef USE_GRAPHICS_UNIT}

/// create an image from a VCL/LCL bitmap, or reuse the same bitmap added before
// - returns the internal XObject name of the resulting TPdfImage
// - if you specify a PPdfBox to draw the image at the given position/size
// - if the same bitmap content is sent more than once, the TPdfImage will
// be reused (it will therefore spare resulting pdf file space) - if the
// Doc.ForceNoBitmapReuse is false
// - if Doc.ForceJPEGCompression is set, the picture will be stored as a JPEG
// - you can specify a clipping rectangle region as ClipRc parameter
// - an empty bitmap (no width or no height) gives no image: returns ''
// - replaces TPdfDocument.CreateOrGetImage(TBitmap); raw pixels go through
// TPdfDocument.CreateOrGetImage(TPdfImagePixels)
function CreateOrGetBitmapImage(Doc: TPdfDocument; B: TBitmap;
  DrawAt: PPdfBox = nil; ClipRc: PPdfBox = nil): PdfString;

/// create the image of a VCL/LCL TGraphic instance
// - handle TBitmap and SynGdiPlus picture types, i.e. TJpegImage
// (stored as jpeg), and TGifImage/TPngImage (stored as bitmap)
// - use TPdfForm to handle TMetafile in vectorial format
// - an optional DontAddToFXref is available, if you don't want to add
// this object to the main XRef list of the PDF file
// - raises EPdfInvalidValue for an empty graphic (no width or no height)
// - replaces the TPdfImage.Create(TGraphic) constructor
function CreateGraphicImage(Doc: TPdfDocument; Graphic: TGraphic;
  DontAddToFXref: boolean): TPdfImage;

{$endif USE_GRAPHICS_UNIT}


{$ifdef OSWINDOWS}
/// retrieve the paper size used by the current selected printer
function CurrentPrinterPaperSize: TPdfPaperSize;

/// retrieve the current printer resolution
function CurrentPrinterRes: TPoint;
{$endif OSWINDOWS}


{************ TPdfDocumentGdi for GDI/TCanvas rendering support }


{$ifdef USE_METAFILE}


/// append a EMR_GDICOMMENT message for handling PDF bookmarks
// - will create a PDF destination at the current position (i.e. the last Y
// parameter of a Move), with some text supplied as bookmark name
procedure GdiCommentBookmark(MetaHandle: HDC; const aBookmarkName: RawUtf8);

/// append a EMR_GDICOMMENT message for handling PDF outline
// - used to add an outline at the current position (i.e. the last Y parameter of
// a Move): the text is the associated title, UTF-8 encoded and the outline tree
// is created from the specified numerical level (0=root)
procedure GdiCommentOutline(MetaHandle: HDC;
  const aTitle: RawUtf8; aLevel: integer);

/// append a EMR_GDICOMMENT message for creating a Link into a specified bookmark
procedure GdiCommentLink(MetaHandle: HDC; const aBookmarkName: RawUtf8;
  const aRect: TRect; NoBorder: boolean);

/// append a EMR_GDICOMMENT message for adding jpeg direct
procedure GdiCommentJpegDirect(MetaHandle: HDC; const aFileName: RawUtf8;
  const aRect: TRect);

/// append a EMR_GDICOMMENT message mapping BeginMarkedContent
// - associate optionally a CreateOptionalContentGroup() instance from the
// current PDF document
procedure GdiCommentBeginMarkContent(MetaHandle: HDC;
  Group: TPdfOptionalContentGroup = nil);

/// append a EMR_GDICOMMENT message mapping EndMarkedContent
procedure GdiCommentEndMarkContent(MetaHandle: HDC);

type
  /// a PDF page, with its corresponding Meta File and Canvas
  TPdfPageGdi = class(TPdfPage)
  private
    // don't use these fVCL* properties directly, but via TPdfDocumentGdi.VclCanvas
    fVclMetaFileCompressed: RawByteString;
    fVclCanvasSize: TSize;
    // it is in fact a TMetaFileCanvas instance from fVclCurrentMetaFile
    fVclCurrentCanvas: TCanvas;
    fVclCurrentMetaFile: TMetaFile;
    // allow to create the meta file and its canvas only if necessary, and
    // compress the page content using SynLZ to reduce memory usage
    procedure CreateVclCanvas;
    procedure SetVclCurrentMetaFile;
    procedure FlushVclCanvas;
  public
    /// release associated memory
    destructor Destroy; override;
  end;

  /// class handling PDF document creation using GDI commands
  // - this class allows using a VCL/LCL standard Canvas class
  // - handles also PDF creation directly from TMetaFile content
  TPdfDocumentGdi = class(TPdfDocument)
  private
    fUseMetaFileTextPositioning: TPdfCanvasRenderMetaFileTextPositioning;
    fUseMetaFileTextClipping: TPdfCanvasRenderMetaFileTextClipping;
    fKerningHScaleTop: single;
    fKerningHScaleBottom: single;
    // not inline: they reach the canvas through TPdfCanvasAccess, which is
    // local to the implementation (Delphi E2441)
    function GetVclCanvas: TCanvas;
    function GetVclCanvasSize: TSize;
  public
    /// create the PDF document instance, with a VCL/LCL Canvas property
    // - see TPdfDocument.Create connstructor for the arguments expectations
    constructor Create(AUseOutlines: boolean = false; ACodePage: integer = 0;
      APdfA: TPdfALevel = pdfaNone
      {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption = nil {$endif});
    /// add a Page to the current PDF document
    function AddPage: TPdfPage; override;
    /// save the PDF file content into a specified Stream
    // - this overridden method draw first the all VclCanvas content into the PDF
    procedure SaveToStream(AStream: TStream; ForceModDate: TDateTime = 0); override;
    /// save the current page content to the PDF file
    // - this overridden method flush the content from the VclCanvas into the PDF
    // - it will reduce the used memory as much as possible, by-passing page
    // content compression
    // - typical use may be:
    // ! with TPdfDocumentGdi.Create do
    // !   try
    // !     Stream := TFileStreamEx.Create(FileName, fmCreate);
    // !     try
    // !       SaveToStreamDirectBegin(Stream);
    // !       for i := 1 to 9 do
    // !       begin
    // !         AddPage;
    // !         with VclCanvas do
    // !         begin
    // !           Font.Name := 'Times new roman';
    // !           Font.Size := 150;
    // !           Font.Style := [fsBold, fsItalic];
    // !           Font.Color := clNavy;
    // !           TextOut(100, 100, 'Page ' + IntToStr(i));
    // !         end;
    // !         SaveToStreamDirectPageFlush; // direct writing
    // !       end;
    // !       SaveToStreamDirectEnd;
    // !     finally
    // !       Stream.Free;
    // !     end;
    // !   finally
    // !     Free;
    // !   end;
    procedure SaveToStreamDirectPageFlush(
      FlushCurrentPageNow: boolean = false); override;
    /// the VCL/LCL Canvas of the current page
    property VclCanvas: TCanvas
      read GetVclCanvas;
    /// the VCL/LCL Canvas size of the current page
    // - useful to calculate coordinates for the current page
    // - filled with (0,0) before first call to VclCanvas property
    property VclCanvasSize: TSize
      read GetVclCanvasSize;
    /// defines how TMetaFile text positioning is rendered
    // - default is tpSetTextJustification
    // - tpSetTextJustification if content used SetTextJustification() API calls
    // - tpExactTextCharacterPositining for exact font kerning, but resulting
    // in bigger pdf size
    // - tpKerningFromAveragePosition will compute average pdf Horizontal Scaling
    // in association with KerningHScaleBottom/KerningHScaleTop properties
    // - replace deprecated property UseSetTextJustification
    property UseMetaFileTextPositioning: TPdfCanvasRenderMetaFileTextPositioning
      read fUseMetaFileTextPositioning write fUseMetaFileTextPositioning;
    /// defines how TMetaFile text clipping should be applied
    // - tcNeverClip has been reported to work better e.g. when app is running
    // on Wine (wsWine in WindowsSpecs)
    property UseMetaFileTextClipping: TPdfCanvasRenderMetaFileTextClipping
      read fUseMetaFileTextClipping write fUseMetaFileTextClipping;
    /// the % limit below which Font Kerning is transformed into PDF Horizontal
    // Scaling commands (when text positioning is tpKerningFromAveragePosition)
    // - set to 99.0 by default
    property KerningHScaleBottom: single
      read fKerningHScaleBottom write fKerningHScaleBottom;
    /// the % limit over which Font Kerning is transformed into PDF Horizontal
    // Scaling commands (when text positioning is tpKerningFromAveragePosition)
    // - set to 101.0 by default
    property KerningHScaleTop: single
      read fKerningHScaleTop write fKerningHScaleTop;
  end;

  /// handle any form XObject
  // - A form XObject (see Section 4.9, of PDF reference 1.3) is a self-contained
  // description of an arbitrary sequence of graphics objects, defined as a
  // PDF content stream
  TPdfForm = class(TPdfFormXObject)
  public
    /// create a form XObject from a supplied TMetaFile
    constructor Create(aDoc: TPdfDocumentGdi; aMetaFile: TMetafile); reintroduce;
  end;


/// draw a metafile content into the PDF page
procedure RenderMetaFile(C: TPdfCanvas; MF: TMetaFile; ScaleX: single = 1.0;
  ScaleY: single = 0.0; XOff: single = 0.0; YOff: single = 0.0;
  TextPositioning: TPdfCanvasRenderMetaFileTextPositioning = tpSetTextJustification;
  KerningHScaleBottom: single = 99.0; KerningHScaleTop: single = 101.0;
  TextClipping: TPdfCanvasRenderMetaFileTextClipping = tcAlwaysClip);

{$endif USE_METAFILE}


implementation

type
  // reach the protected state of the engine classes, as TORHook does in
  // mormot.core.json: no field, no override - only a cast of an instance
  TPdfCanvasAccess = class(TPdfCanvas);
  TPdfDocumentAccess = class(TPdfDocument);
  TPdfObjectAccess = class(TPdfObject);
  TPdfFontTrueTypeAccess = class(TPdfFontTrueType);

{$ifdef FPC}
{$ifdef USE_METAFILE}
type
  TEMRExtTextOut = TEMREXTTEXTOUTW;
  PEMRExtTextOut = ^TEMRExtTextOut;
  PEMRExtCreateFontIndirect = PEMRExtCreateFontIndirectW;
{$endif USE_METAFILE}
{$endif FPC}

{$ifdef OSWINDOWS}

function PrinterDriverExists: boolean;
var
  flags, count, dummy: dword;
  level: Byte;
begin
  // avoid using fPrinter.printers.count as this will raise an
  // exception if no printer driver is installed...
  count := 0;
  flags := PRINTER_ENUM_CONNECTIONS or PRINTER_ENUM_LOCAL;
  level := 4;
  {$ifdef FPC}
  EnumPrinters(flags, nil, level, nil, 0, @count, @dummy);
  {$else}
  EnumPrinters(flags, nil, level, nil, 0, count, dummy);
  {$endif FPC}
  result := (count > 0);
end;

function ParseFetchedPrinterStr(Str: PChar): PChar;
var
  P: PChar;
begin
  result := Str;
  if Str = nil then
    exit;
  P := Str;
  while P^ = ' ' do
    inc(P);
  result := P;
  while (P^ <> #0) and
        (P^ <> ',') do
    inc(P);
  if P^ = ',' then
    P^ := #0;
end;

function CurrentPrinterPaperSize: TPdfPaperSize;
var
  h: THandle;
  pt: TPoint;
  logical, physical: TSize;
  tmp: integer;
  name: array[0..1023] of char;
  PC: PChar;
begin
  result := psUserDefined;
  if not PrinterDriverExists then
    exit;
  GetProfileString('windows', 'device', nil, name, SizeOf(name) - 1);
  PC := ParseFetchedPrinterStr(name);
  if (PC = nil) or
     (PC^ = #0) then
    exit;
  try
    h := CreateDC(nil, PC, nil, nil);
    try
      pt.x := GetDeviceCaps(h, LOGPIXELSX);
      pt.y := GetDeviceCaps(h, LOGPIXELSY);
      physical.cx := GetDeviceCaps(h, PHYSICALWIDTH);
      physical.cy := GetDeviceCaps(h, PHYSICALHEIGHT);
      logical.cx := mulDiv(physical.cx, 254, pt.x * 10);
      logical.cy := mulDiv(physical.cy, 254, pt.y * 10);
    finally
      DeleteDC(h);
    end;
  except
    on Exception do // raised e.g. if no Printer is existing
      exit;
  end;
  with logical do
  begin
    if cx < cy then
    begin // handle landscape or portrait at once
      tmp := cx;
      cx := cy;
      cy := tmp;
    end;
    case cy of
      148:
        result := psA5;
      210:
        result := psA4; // A4 (297 x 210mm)
      216:
        if cx = 279 then
          result := psLetter
        else if cx = 356 then
          result := psLegal;
      297:
        if cx = 420 then
          result := psA3;
    end;
  end;
end;

function CurrentPrinterRes: TPoint;
var
  name: array[0..1023] of Char;
  PC: PChar;
  h: THandle;
begin
  result.X := 300;
  result.Y := 300; // default standard printer resolution
  if not PrinterDriverExists then
    exit;
  GetProfileString('windows', 'device', nil, name, SizeOf(name) - 1);
  PC := ParseFetchedPrinterStr(name);
  if (PC = nil) or
     (PC^ = #0) then
    exit;
  try
    h := CreateDC(nil, PC, nil, nil);
    try
      result.x := GetDeviceCaps(h, LOGPIXELSX);
      result.y := GetDeviceCaps(h, LOGPIXELSY);
    finally
      DeleteDC(h);
    end;
  except
    on Exception do // raised e.g. if no Printer is existing
      exit;
  end;
end;

function CombineTransform(xform1, xform2: XFORM): XFORM;
begin
  result.eM11 := xform1.eM11 * xform2.eM11 + xform1.eM12 * xform2.eM21;
  result.eM12 := xform1.eM11 * xform2.eM12 + xform1.eM12 * xform2.eM22;
  result.eM21 := xform1.eM21 * xform2.eM11 + xform1.eM22 * xform2.eM21;
  result.eM22 := xform1.eM21 * xform2.eM12 + xform1.eM22 * xform2.eM22;
  result.eDx := xform1.eDx * xform2.eM11 + xform1.eDy * xform2.eM21 + xform2.eDx;
  result.eDy := xform1.eDx * xform2.eM12 + xform1.eDy * xform2.eM22 + xform2.eDy;
end;

procedure InitTransformation(x: PXForm;
  var fIntFactorX, fIntFactorY, fIntOffsetX, fIntOffsetY: single);
begin
  if Assigned(x) then
  begin
    fIntFactorX := x^.eM11;
    fIntFactorY := x^.eM22;
    fIntOffsetX := x^.eDx;
    fIntOffsetY := x^.eDy;
  end
  else
  begin
    fIntFactorX := 1;
    fIntFactorY := 1;
    fIntOffsetX := 0;
    fIntOffsetY := 0;
  end;
end;

function DefaultIdentityMatrix: XFORM;
begin
  result.eM11 := 1;
  result.eM12 := 0;
  result.eM21 := 0;
  result.eM22 := 1;
  result.eDx := 0;
  result.eDy := 0;
end;

{$endif OSWINDOWS}

function ScaleRect(r: TRect; fScaleX, fScaleY: single): TRect;
begin
  result.Left   := Trunc(r.Left * fScaleX);
  result.Top    := Trunc(r.Top * fScaleY);
  result.Right  := Trunc(r.Right * fScaleX);
  result.Bottom := Trunc(r.Bottom * fScaleY);
end;

procedure NormalizeRect(var Rect: TRect); overload;
var
  tmp: integer;
begin // PDF can't draw twisted rects -> normalize such values
  if Rect.Right < Rect.Left then
  begin
    tmp := Rect.Left;
    Rect.Left := Rect.Right;
    Rect.Right := tmp;
  end;
  if Rect.Bottom < Rect.Top then
  begin
    tmp := Rect.Top;
    Rect.Top := Rect.Bottom;
    Rect.Bottom := tmp;
  end;
end;


{$ifdef OSWINDOWS}
function PrepareTransformation(
  fIntFactorX, fIntFactorY, fIntOffsetX, fIntOffsetY: single): XForm;
begin
  result.eM11 := fIntFactorX;
  result.eM12 := 0;
  result.eM21 := 0;
  result.eM22 := fIntFactorY;
  result.eDx := fIntOffsetX;
  result.eDy := fIntOffsetY;
end;
{$endif OSWINDOWS}

const
  MWT_IDENTITY      = 1;
  MWT_LEFTMULTIPLY  = 2;
  MWT_RIGHTMULTIPLY = 3;
  MWT_SET           = 4;
  {$ifdef USE_METAFILE}
  cPI: single = 3.141592654;
  cPIdiv180: single = 0.017453292;
  c180divPI: single = 57.29577951;
  {$endif USE_METAFILE}

function RGBA(r, g, b, a: cardinal): cardinal;
  {$ifdef HASINLINE} inline;{$endif}
begin
  result := ((r shr 8) or ((g shr 8) shl 8) or ((b shr 8) shl 16) or ((a shr 8) shl 24));
end;

{$ifdef USE_GRAPHICS_UNIT}
// the reuse key of a bitmap: four CRC32C lanes over its rows as a DIB pads
// them, after its palette entries
function BitmapHash(B: TBitmap): THash128Rec;
var
  y, w, h, row: integer;
  palcount: cardinal;
  pal: array of TPaletteEntry;
const
  PERROW: array[TPixelFormat] of byte = (0, 1, 4, 8, 15, 16, 24, 32, 0);
begin
  FillZero(result.b);
  w := B.Width;
  h := B.Height;
  row := PERROW[B.PixelFormat];
  if row = 0 then
  begin
    B.PixelFormat := pf24bit; // convert any device or custom bitmap
    row := 24;
  end;
  if B.Palette <> 0 then
  begin
    palcount := 0;
    if (GetObject(B.Palette, SizeOf(palcount), @palcount) <> 0) and
       (palcount > 0) then
    begin
      SetLength(pal, palcount);
      if GetPaletteEntries(B.Palette, 0, palcount, pal[0]) = palcount then
        result.c0 := crc32c(result.c0, pointer(pal), palcount * SizeOf(pal[0]));
    end;
  end;
  row := (((w * row) + 31) and (not 31)) shr 3; // inlined BytesPerScanLine
  for y := 0 to h - 1 do
    result.c[y and 3] := crc32c(result.c[y and 3], B.{%H-}ScanLine[y], row);
end;

function CreateOrGetBitmapImage(Doc: TPdfDocument; B: TBitmap;
  DrawAt, ClipRc: PPdfBox): PdfString;
var
  jpg: TJpegImage;
  img: TPdfImage;
  hash: THash128Rec; // no DefaultHasher128() because AesNiHash128() makes GPF
begin
  result := '';
  // an empty bitmap gives no image: ScanLine[0] would raise
  if (Doc = nil) or
     (B = nil) or
     (B.Width <= 0) or
     (B.Height <= 0) then
    exit;
  FillZero(hash.b);
  if not Doc.ForceNoBitmapReuse then
  begin
    hash := BitmapHash(B);
    result := Doc.GetXObjectImageName(hash, B.Width, B.Height); // search for matching image
  end;
  if result = '' then
  begin
     // create new if no existing TPdfImage match
    if Doc.ForceJPEGCompression = 0 then
      img := CreateGraphicImage(Doc, B, true)
    else
    begin
      jpg := TJpegImage.Create;
      try
        jpg.Assign(B);
        img := CreateGraphicImage(Doc, jpg, false);
      finally
        jpg.Free;
      end;
    end;
    img.Hash := hash;
    result := Doc.RegisterImage(img);
  end;
  Doc.DrawImage(result, DrawAt, ClipRc);
end;
{$endif USE_GRAPHICS_UNIT}

{$ifdef USE_GRAPHICS_UNIT}
function CreateGraphicImage(Doc: TPdfDocument; Graphic: TGraphic;
  DontAddToFXref: boolean): TPdfImage;
var
  bmp: TBitmap;
  ms: TMemoryStream;
  px: TPdfImagePixels;
  entry: array of TPaletteEntry;
  i: integer;
  p: PAnsiChar;

  procedure NeedBitmap(PF: TPixelFormat);
  begin
    bmp := TBitmap.Create; // create a temp bitmap (pixelformat may change)
    bmp.PixelFormat := PF;
    bmp.Width := Graphic.Width;
    bmp.Height := Graphic.Height;
    bmp.Canvas.Draw(0, 0, Graphic);
  end;

begin
  if (Graphic.Width <= 0) or
     (Graphic.Height <= 0) then
    EPdfInvalidValue.RaiseUtf8('CreateGraphicImage: empty % (% x %)',
      [Graphic.ClassName, Graphic.Width, Graphic.Height]);
  if Graphic.InheritsFrom(TJpegImage) then
  begin
    ms := TMemoryStream.Create;
    try
      with TJpegImage(Graphic) do
      begin
        if Doc.ForceJPEGCompression <> 0 then
          CompressionQuality := Doc.ForceJPEGCompression;
        {$ifdef USE_SYNGDIPLUS}
        if Doc.ForceJPEGCompression = 0 then // recompression only if necessary
          SaveInternalToStream(ms)
        else
        {$endif USE_SYNGDIPLUS}
          SaveToStream(ms); // with CompressionQuality recompress
      end;
      result := TPdfImage.CreateJpeg(Doc, ms.Memory, ms.Size, Graphic.Width,
        Graphic.Height, DontAddToFXref);
    finally
      ms.Free;
    end;
    exit;
  end;
  if Graphic.InheritsFrom(TBitmap) then
    bmp := TBitmap(Graphic)
  else
    NeedBitmap(pf24bit);
  try
    FillCharFast(px, SizeOf(px), 0);
    case bmp.PixelFormat of
      pf1bit,
      pf4bit,
      pf8bit:
        begin
          if bmp.PixelFormat <> pf8bit then
            NeedBitmap(pf8bit);
          SetLength(entry, 256);
          if GetPaletteEntries(bmp.Palette, 0, 256, entry[0]) <> 256 then
            raise EPdfInvalidValue.Create('TPdfImage');
          SetLength(px.Palette, 768);
          p := pointer(px.Palette);
          for i := 0 to 255 do
          begin
            p[0] := AnsiChar(entry[i].peRed);
            p[1] := AnsiChar(entry[i].peGreen);
            p[2] := AnsiChar(entry[i].peBlue);
            inc(p, 3);
          end;
          px.Format := ipfIndexed8;
        end;
    else
      begin
        if not (bmp.PixelFormat in [pf24bit, pf32bit]) then
          NeedBitmap(pf24bit);
        if bmp.PixelFormat = pf24bit then
        begin
          px.Format := ipfBgr24;
          // [ min1 max1 ... minn maxn ]
          px.HasColorKey := bmp.TransparentMode = tmFixed;
          if px.HasColorKey then
            px.ColorKey := bmp.TransparentColor;
        end
        else
          px.Format := ipfBgrx32;
      end;
    end;
    // the rows as ScanLine[] gives them: a DIB is bottom-up
    px.Width := bmp.Width;
    px.Height := bmp.Height;
    px.Data := bmp.{%H-}ScanLine[0];
    case px.Format of
      ipfIndexed8:
        px.Stride := px.Width;
      ipfBgr24:
        px.Stride := px.Width * 3;
    else
      px.Stride := px.Width * 4;
    end;
    px.Size := px.Stride;
    if px.Height > 1 then
    begin
      px.Stride := PAnsiChar(bmp.{%H-}ScanLine[1]) - PAnsiChar(px.Data);
      px.Size := PtrInt(px.Height - 1) * Abs(px.Stride) + px.Size;
    end;
    result := TPdfImage.CreatePixels(Doc, px, DontAddToFXref);
  finally
    if bmp <> Graphic then
      bmp.Free;
  end;
end;
{$endif USE_GRAPHICS_UNIT}

{************ TPdfDocumentGdi for GDI/TCanvas rendering support }

{$ifdef USE_METAFILE}

procedure SetGdiComment(h: HDC; pgc: TPdfGdiComment; data: pointer; len: PtrInt;
  const last: RawByteString = '');
var
  tmp: TSynTempAdder;
begin
  tmp.Init;
  tmp.AddDirect(AnsiChar(pgc));
  tmp.Add(data, len);
  tmp.Add(last);
  {$ifdef FPC}
  Windows.GdiComment(h, tmp.Size, PByte(tmp.Buffer)^);
  {$else}
  Windows.GdiComment(h, tmp.Size, tmp.Buffer);
  {$endif FPC}
  tmp.Store.Done;
end;

procedure GdiCommentBookmark(MetaHandle: HDC; const aBookmarkName: RawUtf8);
begin
  // high(TPdfGdiComment)<$47 so it will never begin with GDICOMMENT_IDENTIFIER
  SetGdiComment(MetaHandle, pgcBookmark, nil, 0, aBookMarkName);
end;

procedure GdiCommentOutline(MetaHandle: HDC; const aTitle: RawUtf8; aLevel: integer);
begin
  SetGdiComment(MetaHandle, pgcOutline, @aLevel, 4, aTitle);
end;

procedure GdiCommentLink(MetaHandle: HDC; const aBookmarkName: RawUtf8;
  const aRect: TRect; NoBorder: boolean);
const
  pgc: array[boolean] of TPdfGdiComment = (pgcLink, pgcLinkNoBorder);
begin
  SetGdiComment(MetaHandle, pgc[NoBorder], @aRect, SizeOf(aRect), aBookmarkName);
end;

procedure GdiCommentJpegDirect(MetaHandle: HDC; const aFileName: RawUtf8;
  const aRect: TRect);
begin
  SetGdiComment(MetaHandle, pgcJpegDirect, @aRect, SizeOf(aRect), aFileName);
end;

procedure GdiCommentBeginMarkContent(MetaHandle: HDC;
  Group: TPdfOptionalContentGroup);
begin
  SetGdiComment(MetaHandle, pgcBeginMarkContent, @Group, SizeOf(Group));
end;

procedure GdiCommentEndMarkContent(MetaHandle: HDC);
begin
  SetGdiComment(MetaHandle, pgcEndMarkContent, nil, 0);
end;


{ TPdfDocumentGdi }

function TPdfDocumentGdi.AddPage: TPdfPage;
begin
  if (fCanvas <> nil) and
     (TPdfCanvasAccess(fCanvas).fPage <> nil) then
    TPdfPageGdi(TPdfCanvasAccess(fCanvas).fPage).FlushVclCanvas;
  result := inherited AddPage;
  // as expected in SaveToStream() below
  TPdfObjectAccess(TPdfObject(TPdfCanvasAccess(fCanvas).fContents)).fSaveAtTheEnd := true;
end;

constructor TPdfDocumentGdi.Create(AUseOutlines: boolean; ACodePage: integer;
  APdfA: TPdfALevel
  {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption{$endif});
begin
  inherited;
  fTPdfPageClass := TPdfPageGdi;
  fUseMetaFileTextPositioning := tpSetTextJustification;
  fKerningHScaleBottom := 99.0;
  fKerningHScaleTop := 101.0;
end;

function TPdfDocumentGdi.GetVclCanvas: TCanvas;
begin
  with TPdfPageGdi(TPdfCanvasAccess(fCanvas).fPage) do
  begin
    if fVclCurrentCanvas = nil then
      CreateVclCanvas;
    result := fVclCurrentCanvas;
  end;
end;

function TPdfDocumentGdi.GetVclCanvasSize: TSize;
begin
  if (fCanvas <> nil) and
     (TPdfCanvasAccess(fCanvas).fPage <> nil) then
    with TPdfPageGdi(TPdfCanvasAccess(fCanvas).fPage) do
    begin
      if fVclCurrentCanvas = nil then
        CreateVclCanvas;
      result := fVclCanvasSize;
    end
  else
    Int64(result) := 0;
end;

procedure TPdfDocumentGdi.SaveToStream(AStream: TStream; ForceModDate: TDateTime);
var
  i: PtrInt;
  P: TPdfPageGdi;
begin
  // write the file header
  SaveToStreamDirectBegin(AStream, ForceModDate);
  // then draw the pages VCL/LCL Canvas content on the fly (miminal memory use)
  for i := 0 to fRawPages.Count - 1 do
  begin
    P := fRawPages.List[i];
    P.FlushVclCanvas;
    if P.fVclMetaFileCompressed <> '' then
    begin
      P.SetVclCurrentMetaFile;
      try
        fCanvas.SetPage(P);
        RenderMetaFile(fCanvas, P.fVclCurrentMetaFile, 1, 1, 0, 0,
          fUseMetaFileTextPositioning, KerningHScaleBottom, KerningHScaleTop,
          fUseMetaFileTextClipping);
      finally
        FreeAndNil(P.fVclCurrentMetaFile);
      end;
      inherited SaveToStreamDirectPageFlush;
    end;
  end;
  // finish to write PDF content to destination stream
  SaveToStreamDirectEnd;
end;

procedure TPdfDocumentGdi.SaveToStreamDirectPageFlush(FlushCurrentPageNow: boolean);
var
  P: TPdfPageGdi;
begin
  if fRawPages.Count > 0 then
  begin
    P := fRawPages.List[fRawPages.Count - 1];
    if (P = TPdfCanvasAccess(fCanvas).fPage) and
       (P.fVclMetaFileCompressed = '') and
       (P.fVclCurrentMetaFile <> nil) and
       (P.fVclCurrentCanvas <> nil) then
    begin
      FreeAndNil(P.fVclCurrentCanvas); // manual P.SetVclCurrentMetaFile
      try
        // force flush NOW
        TPdfObjectAccess(TPdfObject(TPdfCanvasAccess(fCanvas).fContents)).fSaveAtTheEnd := false;
        RenderMetaFile(fCanvas, P.fVclCurrentMetaFile, 1, 1, 0, 0,
          fUseMetaFileTextPositioning, KerningHScaleBottom, KerningHScaleTop,
          fUseMetaFileTextClipping);
      finally
        FreeAndNil(P.fVclCurrentMetaFile);
      end;
    end;
  end;
  inherited SaveToStreamDirectPageFlush;
end;


{ TPdfPageGdi }

procedure TPdfPageGdi.SetVclCurrentMetaFile;
var
  tmp: RawByteString;
  str: TStream;
begin
  assert(fVclCurrentMetaFile = nil);
  fVclCurrentMetaFile := TMetaFile.Create;
  fVclCanvasSize.cx := MulDiv(PageWidth, fDoc.ScreenLogPixels, 72);
  fVclCanvasSize.cy := MulDiv(PageHeight, fDoc.ScreenLogPixels, 72);
  fVclCurrentMetaFile.Width := fVclCanvasSize.cx;
  fVclCurrentMetaFile.Height := fVclCanvasSize.cy;
  if fVclMetaFileCompressed <> '' then
  begin
    SetLength(tmp, SynLZdecompressdestlen(pointer(fVclMetaFileCompressed)));
    SynLZdecompress1(pointer(fVclMetaFileCompressed),
      length(fVclMetaFileCompressed), pointer(tmp));
    str := TRawByteStringStream.Create(tmp);
    try
      fVclCurrentMetaFile.LoadFromStream(str);
    finally
      str.Free;
    end;
  end;
end;

procedure TPdfPageGdi.CreateVclCanvas;
begin
  SetVclCurrentMetaFile;
  fVclCurrentCanvas := TMetaFileCanvas.Create(fVclCurrentMetaFile,
    TPdfDocumentAccess(fDoc).EmfDC);
end;

procedure TPdfPageGdi.FlushVclCanvas;
var
  str: TRawByteStringStream;
  len: integer;
begin
  if (self = nil) or
     (fVclCurrentCanvas = nil) then
    exit;
  FreeAndNil(fVclCurrentCanvas);
  assert(fVclCurrentMetaFile <> nil);
  str := TRawByteStringStream.Create;
  try
    fVclCurrentMetaFile.SaveToStream(str);
    len := Length(str.DataString);
    SetLength(fVclMetaFileCompressed, SynLZcompressdestlen(len));
    SetLength(fVclMetaFileCompressed, SynLZcompress1(
      pointer(str.DataString), len, pointer(fVclMetaFileCompressed)));
  finally
    str.Free;
  end;
  FreeAndNil(fVclCurrentMetaFile);
end;

destructor TPdfPageGdi.Destroy;
begin
  FreeAndNil(fVclCurrentCanvas);
  FreeAndNil(fVclCurrentMetaFile);
  inherited;
end;


{ TPdfForm }

constructor TPdfForm.Create(aDoc: TPdfDocumentGdi; aMetaFile: TMetafile);
var
  P: TPdfPageGdi;
  res: TPdfDictionary;
  w, h: integer;
  old: TPdfPage;
begin
  inherited Create(aDoc, true);
  w := aMetaFile.Width;
  h := aMetaFile.Height;
  P := TPdfPageGdi.Create(nil);
  try
    res := TPdfDictionary.Create(aDoc.fXRef);
    fFontList := TPdfDictionary.Create(nil);
    res.AddItem('Font', fFontList);
    res.AddItem('ProcSet',
      TPdfArray.CreateNames(nil, ['PDF', 'Text', 'ImageC']));
    with TPdfCanvasAccess(TPdfDocumentAccess(TPdfDocument(aDoc)).fCanvas) do
    begin
      old := fPage;
      fPage := P;
      try
        fPageFontList := fFontList;
        fContents := self;
        fPage.PageHeight := h; // SetPageHeight, protected
        fFactor := 1;
        RenderMetaFile(TPdfDocumentAccess(TPdfDocument(aDoc)).fCanvas, aMetaFile);
      finally
        if old <> nil then
          SetPage(old);
      end;
    end;
    fAttributes.AddItem('Type', 'XObject');
    fAttributes.AddItem('Subtype', 'Form');
    fAttributes.AddItem('BBox', TPdfArray.Create(nil, [0, 0, w, h]));
    fAttributes.AddItem('Matrix', TPdfRawText.Create('[1 0 0 1 0 0]'));
    fAttributes.AddItem('Resources', res);
  finally
    P.Free;
  end;
end;

type
  TFontSpec = packed record
    angle: SmallInt; // -360..+360
    ascent, descent, cell: SmallInt;
  end;

  TPdfEnumStatePen = record
    Null: boolean;
    Color, style: integer;
    Width: single;
  end;

  /// a state of the EMF enumeration engine, for the PDF canvas
  // - used also for the SaveDC/RestoreDC stack
  TPdfEnumState = record
    Position: TPoint;
    Moved: boolean;
    WinSize, ViewSize: TSize;
    WinOrg, ViewOrg: TPoint;
    //transformation and clipping
    WorldTransform: XFORM; //current
    MetaRgn: TPdfBox;      //clipping
    ClipRgn: TPdfBox;      //clipping
    ClipRgnNull: boolean;  //clipping
    MappingMode: integer;
    PolyFillMode: integer;
    StretchBltMode: integer;
    ArcDirection: integer;
    // current selected pen
    Pen: TPdfEnumStatePen;
    // current selected brush
    Brush: record
      Null: boolean;
      Color: integer;
      Style: integer;
    end;
    // current selected font
    Font: record
      Color: integer;
      Align: integer;
      BkMode, BkColor: integer;
      Spec: TFontSpec;
      LogFont: TLogFontW; // better be the last entry in TPdfEnumState record
    end;
  end;

  /// internal state machine used during EMF drawing
  // - contain the EMF enumeration engine state parameters
  TPdfEnum = class
  private
    fStrokeColor: integer;
    fFillColor: integer;
    fPenStyle: integer;
    fPenWidth: single;
    fInLined: boolean;
    fInitTransformMatrix: XFORM;
    fInitMetaRgn: TPdfBox;
    procedure SetFillColor(Value: integer);
    procedure SetStrokeColor(Value: integer);
  protected
    Canvas: TPdfCanvasAccess;
    // the pen/font/brush objects table, indexed like the THandleTable
    Obj: array of record
      case kind: integer of
        OBJ_PEN:
          (PenColor: integer;
           PenStyle: integer;
           PenWidth: single);
        OBJ_FONT:
          (FontSpec: TFontSpec;
           LogFont: TLogFontW);
        OBJ_BRUSH:
          (BrushColor: integer;
           BrushNull: boolean;
           BrushStyle: integer);
    end;
    // SaveDC/RestoreDC stack
    nDC: integer;
    DC: array[0..31] of TPdfEnumState;
  public
    constructor Create(ACanvas: TPdfCanvas);
    procedure SaveDC;
    procedure RestoreDC;
    procedure NeedPen;
    procedure NeedBrushAndPen;
    procedure FlushPenBrush;
    procedure SelectObjectFromIndex(iObject: integer);
    procedure TextOut(var r: TEMRExtTextOut);
    procedure ScaleMatrix(Custom: PXForm; iMode: integer);
    procedure HandleComment(Kind: TPdfGdiComment; P: PAnsiChar; Len: integer);
    procedure CreateFont(ALogFont: PEMRExtCreateFontIndirect);
    // if Canvas.Doc.JPEGCompression<>0, draw not as a bitmap but jpeg encoded
    procedure DrawBitmap(xs, ys, ws, hs, xd, yd, wd, hd, usage: integer;
      Bmi: PBitmapInfo; bits: pointer; clipRect: PRect; xSrcTransform: PXForm;
      dwRop: DWord; transparent: TPdfColorRGB = $FFFFFFFF);
    procedure FillRectangle(const Rect: TRect; ResetNewPath: boolean);
    // the current value set to SetRGBFillColor (rg)
    property FillColor: integer
      read fFillColor write SetFillColor;
    // the current value set to SetRGBStrokeColor (RG)
    property StrokeColor: integer
      read fStrokeColor write SetStrokeColor;
    // WorldTransform
    property InitTransformMatrix: XFORM
      read fInitTransformMatrix write fInitTransformMatrix;
    // MetaRgn - clipping
    procedure InitMetaRgn(const ClientRect: TRect);
    procedure SetMetaRgn;
    // intersect - clipping
    function IntersectClipRect(
      const ClpRect: TPdfBox; const CurrRect: TPdfBox): TPdfBox;
    procedure ExtSelectClipRgn(data: PEMRExtSelectClipRgn);
    // get current clipping area
    function GetClipRect: TPdfBox;
    procedure GradientFill(Data: PEMGradientFill);
    procedure PolyPoly(Data: PEMRPolyPolygon; iType: integer);
  end;

const
  STOCKBRUSHCOLOR: array[WHITE_BRUSH..BLACK_BRUSH] of integer = (
    clWhite, $AAAAAA, $808080, $666666, clBlack);
  STOCKPENCOLOR: array[WHITE_PEN..BLACK_PEN] of integer = (
    clWhite, clBlack);

function CenterPoint(const Rect: TRect): TPoint;
  {$ifdef HASINLINE} inline;{$endif}
begin
  result.X := (Rect.Right + Rect.Left) div 2;
  result.Y := (Rect.Bottom + Rect.Top) div 2;
end;

/// EMF enumeration callback function, called from GDI
// - draw most content on PDF canvas (do not render 100% GDI content yet)
function EnumEMFFunc(DC: HDC; var Table: THandleTable; R: PEnhMetaRecord;
  NumObjects: DWord; E: TPdfEnum): LongBool; stdcall;
var
  i: PtrInt;
  InitTransX: XForm;
  polytypes: PByteArray;
begin
  result := true;
  with E.DC[E.nDC] do
    case R^.iType of
      EMR_HEADER:
        begin
          SetLength(E.obj, PEnhMetaHeader(R)^.nHandles);
          WinOrg.X := 0;
          WinOrg.Y := 0;
          ViewOrg.X := 0;
          ViewOrg.Y := 0;
          MappingMode := GetMapMode(DC);
          PolyFillMode := GetPolyFillMode(DC);
          StretchBltMode := GetStretchBltMode(DC);
          ArcDirection := AD_COUNTERCLOCKWISE;
          InitTransX := DefaultIdentityMatrix;
          E.InitTransformMatrix := InitTransX;
          E.ScaleMatrix(@InitTransX, MWT_SET); // keep init
          E.InitMetaRgn(TRect(PEnhMetaHeader(R)^.rclBounds));
        end;
      EMR_SETWINDOWEXTEX:
        WinSize := PEMRSetWindowExtEx(R)^.szlExtent;
      EMR_SETWINDOWORGEX:
        WinOrg := PEMRSetWindowOrgEx(R)^.ptlOrigin;
      EMR_SETVIEWPORTEXTEX:
        ViewSize := PEMRSetViewPortExtEx(R)^.szlExtent;
      EMR_SETVIEWPORTORGEX:
        ViewOrg := PEMRSetViewPortOrgEx(R)^.ptlOrigin;
      EMR_SETBKMODE:
        Font.BkMode := PEMRSetBkMode(R)^.iMode;
      EMR_SETBKCOLOR:
        if PEMRSetBkColor(R)^.crColor = cardinal(clNone) then
          Font.BkColor := 0
        else
          Font.BkColor := PEMRSetBkColor(R)^.crColor;
      EMR_SETTEXTCOLOR:
        if PEMRSetTextColor(R)^.crColor = cardinal(clNone) then
          Font.Color := 0
        else
          Font.Color := PEMRSetTextColor(R)^.crColor;
      EMR_SETTEXTALIGN:
        Font.Align := PEMRSetTextAlign(R)^.iMode;
      EMR_EXTTEXTOUTA,
      EMR_EXTTEXTOUTW:
        E.TextOut(PEMRExtTextOut(R)^);
      EMR_SAVEDC:
        E.SaveDC;
      EMR_RESTOREDC:
        E.RestoreDC;
      EMR_SETWORLDTRANSFORM:
        E.ScaleMatrix(@PEMRSetWorldTransform(R)^.xform, MWT_SET);
      EMR_CREATEPEN:
        with PEMRCreatePen(R)^ do
          if ihPen - 1 < cardinal(length(E.Obj)) then
            with E.obj[ihPen - 1] do
            begin
              kind := OBJ_PEN;
              PenColor := lopn.lopnColor;
              PenWidth := lopn.lopnWidth.X;
              PenStyle := lopn.lopnStyle;
            end;
      EMR_CREATEBRUSHINDIRECT:
        with PEMRCreateBrushIndirect(R)^ do
          if ihBrush - 1 < cardinal(length(E.Obj)) then
            with E.obj[ihBrush - 1] do
            begin
              kind := OBJ_BRUSH;
              BrushColor := lb.lbColor;
              BrushNull := (lb.lbStyle = BS_NULL);
              BrushStyle := lb.lbStyle;
            end;
      EMR_EXTCREATEFONTINDIRECTW:
        E.CreateFont(PEMRExtCreateFontIndirect(R));
      EMR_DELETEOBJECT:
        with PEMRDeleteObject(R)^ do
          if ihObject - 1 < cardinal(length(E.Obj)) then // avoid GPF
            E.obj[ihObject - 1].kind := 0;
      EMR_SELECTOBJECT:
        E.SelectObjectFromIndex(PEMRSelectObject(R)^.ihObject);
      EMR_MOVETOEX:
        begin
          position := PEMRMoveToEx(R)^.ptl; // temp var to ignore unused moves
          if E.Canvas.fNewPath then
          begin
            E.Canvas.MoveToI(position.X, position.Y);
            Moved := true;
          end
          else
            Moved := false;
        end;
      EMR_LINETO:
        begin
          E.NeedPen;
          if not E.Canvas.fNewPath and
             not Moved then
            E.Canvas.MoveToI(position.X, position.Y);
          E.Canvas.LineToI(PEMRLineTo(R)^.ptl.X, PEMRLineTo(R)^.ptl.Y);
          position := PEMRLineTo(R)^.ptl;
          Moved := false;
          E.fInLined := true;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
        end;
      EMR_RECTANGLE,
      EMR_ELLIPSE:
        begin
          E.NeedBrushAndPen;
          with E.Canvas.BoxI(TRect(PEMRRectangle(R)^.rclBox), true) do
            case R^.iType of
              EMR_RECTANGLE:
                E.Canvas.Rectangle(Left, Top, Width, Height);
              EMR_ELLIPSE:
                E.Canvas.Ellipse(Left, Top, Width, Height);
            end;
          E.FlushPenBrush;
        end;
      EMR_ROUNDRECT:
        begin
          NormalizeRect(PRect(@PEMRRoundRect(R)^.rclBox)^);
          E.NeedBrushAndPen;
          with PEMRRoundRect(R)^ do
            E.Canvas.RoundRectI(rclBox.left, rclBox.top, rclBox.right,
              rclBox.bottom, szlCorner.cx, szlCorner.cy);
          E.FlushPenBrush;
        end;
      EMR_ARC:
        begin
          NormalizeRect(PRect(@PEMRARC(R)^.rclBox)^);
          E.NeedPen;
          with PEMRARC(R)^, CenterPoint(TRect(rclBox)) do
            E.Canvas.ArcI(X, Y, rclBox.Right - rclBox.Left,
              rclBox.Bottom - rclBox.Top, ptlStart.x, ptlStart.y,
              ptlEnd.x, ptlEnd.y, E.dc[E.nDC].ArcDirection = AD_CLOCKWISE,
              acArc, position);
          E.Canvas.Stroke;
        end;
      EMR_ARCTO:
        begin
          NormalizeRect(PRect(@PEMRARCTO(R)^.rclBox)^);
          E.NeedPen;
          if not E.Canvas.fNewPath and
             not Moved then
            E.Canvas.MoveToI(position.X, position.Y);
          with PEMRARC(R)^, CenterPoint(TRect(rclBox)) do
          begin
            // E.Canvas.LineTo(ptlStart.x, ptlStart.y);
            E.Canvas.ArcI(X, Y, rclBox.Right - rclBox.Left,
              rclBox.Bottom - rclBox.Top, ptlStart.x, ptlStart.y,
              ptlEnd.x, ptlEnd.y, E.dc[E.nDC].ArcDirection = AD_CLOCKWISE,
              acArcTo, position);
            Moved := false;
            E.fInLined := true;
            if not E.Canvas.fNewPath then
              if not pen.null then
                E.Canvas.Stroke;
          end;
        end;
      EMR_PIE:
        begin
          NormalizeRect(PRect(@PEMRPie(R)^.rclBox)^);
          E.NeedBrushAndPen;
          with PEMRPie(R)^, CenterPoint(TRect(rclBox)) do
            E.Canvas.ArcI(X, Y, rclBox.Right - rclBox.Left,
              rclBox.Bottom - rclBox.Top, ptlStart.x, ptlStart.y,
              ptlEnd.x, ptlEnd.y, E.dc[E.nDC].ArcDirection = AD_CLOCKWISE,
              acPie, position);
          if pen.null then
            E.Canvas.Fill
          else
            E.Canvas.FillStroke;
        end;
      EMR_CHORD:
        begin
          NormalizeRect(PRect(@PEMRChord(R)^.rclBox)^);
          E.NeedBrushAndPen;
          with PEMRChord(R)^, CenterPoint(TRect(rclBox)) do
            E.Canvas.ArcI(X, Y, rclBox.Right - rclBox.Left,
              rclBox.Bottom - rclBox.Top, ptlStart.x, ptlStart.y,
              ptlEnd.x, ptlEnd.y, E.dc[E.nDC].ArcDirection = AD_CLOCKWISE,
              acChoord, position);
          if pen.null then
            E.Canvas.Fill
          else
            E.Canvas.FillStroke;
        end;
      EMR_FILLRGN:
        begin
          E.SelectObjectFromIndex(PEMRFillRgn(R)^.ihBrush);
          E.NeedBrushAndPen;
          E.FillRectangle(
            TRect(PRgnDataHeader(@PEMRFillRgn(R)^.RgnData[0])^.rcBound), false);
        end;
      EMR_POLYGON,
      EMR_POLYLINE,
      EMR_POLYGON16,
      EMR_POLYLINE16:
        if not brush.null or
           not pen.null then
        begin
          if R^.iType in [EMR_POLYGON, EMR_POLYGON16] then
            E.NeedBrushAndPen
          else
            E.NeedPen;
          if R^.iType in [EMR_POLYGON, EMR_POLYLINE] then
          begin
            E.Canvas.MoveToI(PEMRPolyLine(R)^.aptl[0].x, PEMRPolyLine(R)^.aptl[0].Y);
            for i := 1 to PEMRPolyLine(R)^.cptl - 1 do
              E.Canvas.LineToI(PEMRPolyLine(R)^.aptl[i].x, PEMRPolyLine(R)^.aptl[i].Y);
            if PEMRPolyLine(R)^.cptl > 0 then
              position := PEMRPolyLine(R)^.aptl[PEMRPolyLine(R)^.cptl - 1]
            else
              position := PEMRPolyLine(R)^.aptl[0];
          end
          else
          begin
            E.Canvas.MoveToI(PEMRPolyLine16(R)^.apts[0].x, PEMRPolyLine16(R)^.apts[0].Y);
            if PEMRPolyLine16(R)^.cpts > 0 then
            begin
              for i := 1 to PEMRPolyLine16(R)^.cpts - 1 do
                E.Canvas.LineToI(
                  PEMRPolyLine16(R)^.apts[i].x, PEMRPolyLine16(R)^.apts[i].Y);
              with PEMRPolyLine16(R)^.apts[PEMRPolyLine16(R)^.cpts - 1] do
              begin
                position.X := x;
                position.Y := Y;
              end;
            end
            else
            begin
              position.X := PEMRPolyLine16(R)^.apts[0].x;
              position.Y := PEMRPolyLine16(R)^.apts[0].Y;
            end;
          end;
          Moved := false;
          if R^.iType in [EMR_POLYGON, EMR_POLYGON16] then
          begin
            E.Canvas.Closepath;
            E.FlushPenBrush;
          end
          else if not pen.null then
            E.Canvas.Stroke
          else // for lines
            E.Canvas.NewPath;
        end;
      EMR_POLYPOLYGON,
      EMR_POLYPOLYGON16,
      EMR_POLYPOLYLINE,
      EMR_POLYPOLYLINE16:
        E.PolyPoly(PEMRPolyPolygon(R), R^.iType);
      EMR_POLYBEZIER:
        begin
          if not pen.null then
            E.NeedPen;
          E.Canvas.MoveToI(
            PEMRPolyBezier(R)^.aptl[0].x, PEMRPolyBezier(R)^.aptl[0].Y);
          for i := 0 to (PEMRPolyBezier(R)^.cptl div 3) - 1 do
            E.Canvas.CurveToCI(
              PEMRPolyBezier(R)^.aptl[i * 3 + 1].X,
              PEMRPolyBezier(R)^.aptl[i * 3 + 1].Y,
              PEMRPolyBezier(R)^.aptl[i * 3 + 2].X,
              PEMRPolyBezier(R)^.aptl[i * 3 + 2].Y,
              PEMRPolyBezier(R)^.aptl[i * 3 + 3].X,
              PEMRPolyBezier(R)^.aptl[i * 3 + 3].Y);
          if PEMRPolyBezier(R)^.cptl > 0 then
            position := PEMRPolyBezier(R)^.aptl[PEMRPolyBezier(R)^.cptl - 1]
          else
            position := PEMRPolyBezier(R)^.aptl[0];
          Moved := false;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
            else
              E.Canvas.NewPath;
        end;
      EMR_POLYBEZIER16:
        begin
          if not pen.null then
            E.NeedPen;
          E.Canvas.MoveToI(
            PEMRPolyBezier16(R)^.apts[0].x, PEMRPolyBezier16(R)^.apts[0].Y);
          if PEMRPolyBezier16(R)^.cpts > 0 then
          begin
            for i := 0 to (PEMRPolyBezier16(R)^.cpts div 3) - 1 do
              E.Canvas.CurveToCI(
                PEMRPolyBezier16(R)^.apts[i * 3 + 1].X,
                PEMRPolyBezier16(R)^.apts[i * 3 + 1].Y,
                PEMRPolyBezier16(R)^.apts[i * 3 + 2].X,
                PEMRPolyBezier16(R)^.apts[i * 3 + 2].Y,
                PEMRPolyBezier16(R)^.apts[i * 3 + 3].X,
                PEMRPolyBezier16(R)^.apts[i * 3 + 3].Y);
            with PEMRPolyBezier16(R)^.apts[PEMRPolyBezier16(R)^.cpts - 1] do
            begin
              position.X := x;
              position.Y := Y;
            end;
          end
          else
          begin
            position.X := PEMRPolyBezier16(R)^.apts[0].x;
            position.Y := PEMRPolyBezier16(R)^.apts[0].Y;
          end;
          Moved := false;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
            else
              E.Canvas.NewPath;
        end;
      EMR_POLYBEZIERTO:
        begin
          if not pen.null then
            E.NeedPen;
          if not E.Canvas.fNewPath then
            if not Moved then
              E.Canvas.MoveToI(position.X, position.Y);
          if PEMRPolyBezierTo(R)^.cptl > 0 then
          begin
            for i := 0 to (PEMRPolyBezierTo(R)^.cptl div 3) - 1 do
              E.Canvas.CurveToCI(
                PEMRPolyBezierTo(R)^.aptl[i * 3].X,
                PEMRPolyBezierTo(R)^.aptl[i * 3].Y,
                PEMRPolyBezierTo(R)^.aptl[i * 3 + 1].X,
                PEMRPolyBezierTo(R)^.aptl[i * 3 + 1].Y,
                PEMRPolyBezierTo(R)^.aptl[i * 3 + 2].X,
                PEMRPolyBezierTo(R)^.aptl[i * 3 + 2].Y);
            position := PEMRPolyBezierTo(R)^.aptl[PEMRPolyBezierTo(R)^.cptl - 1];
          end;
          Moved := false;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
            else
              E.Canvas.NewPath;
        end;
      EMR_POLYBEZIERTO16:
        begin
          if not pen.null then
            E.NeedPen;
          if not E.Canvas.fNewPath then
            if not Moved then
              E.Canvas.MoveToI(position.X, position.Y);
          if PEMRPolyBezierTo16(R)^.cpts > 0 then
          begin
            for i := 0 to (PEMRPolyBezierTo16(R)^.cpts div 3) - 1 do
              E.Canvas.CurveToCI(
                PEMRPolyBezierTo16(R)^.apts[i * 3].X,
                PEMRPolyBezierTo16(R)^.apts[i * 3].Y,
                PEMRPolyBezierTo16(R)^.apts[i * 3 + 1].X,
                PEMRPolyBezierTo16(R)^.apts[i * 3 + 1].Y,
                PEMRPolyBezierTo16(R)^.apts[i * 3 + 2].X,
                PEMRPolyBezierTo16(R)^.apts[i * 3 + 2].Y);
            with PEMRPolyBezierTo16(R)^.apts[PEMRPolyBezierTo16(R)^.cpts - 1] do
            begin
              position.X := x;
              position.Y := Y;
            end;
          end;
          Moved := false;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
            else
              E.Canvas.NewPath;
        end;
      EMR_POLYLINETO,
      EMR_POLYLINETO16:
        begin
          if not pen.null then
            E.NeedPen;
          if not E.Canvas.fNewPath then
          begin
            E.Canvas.NewPath;
            if not Moved then
              E.Canvas.MoveToI(position.X, position.Y);
          end;
          if R^.iType = EMR_POLYLINETO then
          begin
            if PEMRPolyLineTo(R)^.cptl > 0 then
            begin
              for i := 0 to PEMRPolyLineTo(R)^.cptl - 1 do
                with PEMRPolyLineTo(R)^.aptl[i] do
                  E.Canvas.LineToI(X, Y);
              position := PEMRPolyLineTo(R)^.aptl[PEMRPolyLineTo(R)^.cptl - 1];
            end;
          end
          else
          // EMR_POLYLINETO16
          if PEMRPolyLineTo16(R)^.cpts > 0 then
          begin
            for i := 0 to PEMRPolyLineTo16(R)^.cpts - 1 do
              with PEMRPolyLineTo16(R)^.apts[i] do
                E.Canvas.LineToI(X, Y);
            with PEMRPolyLineTo16(R)^.apts[PEMRPolyLineTo16(R)^.cpts - 1] do
            begin
              position.X := x;
              position.Y := Y;
            end;
          end;
          Moved := false;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
            else
              E.Canvas.NewPath;
        end;
      EMR_POLYDRAW:
        if PEMRPolyDraw(R)^.cptl > 0 then
        begin
          if not pen.null then
            E.NeedPen;
          polytypes := @PEMRPolyDraw(R)^.aptl[PEMRPolyDraw(R)^.cptl];
          i := 0;
          while i < integer(PEMRPolyDraw(R)^.cptl) do
          begin
            case polytypes^[i] and not PT_CLOSEFIGURE of
              PT_LINETO:
                begin
                  with PEMRPolyDraw(R)^.aptl[i] do
                    E.Canvas.LineToI(X, Y);
                  if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                  begin
                    E.Canvas.LineToI(position.X, position.Y);
                    position := PEMRPolyDraw(R)^.aptl[i];
                  end;
                end;
              PT_BEZIERTO:
                begin
                  E.Canvas.CurveToCI(
                    PEMRPolyDraw(R)^.aptl[i].X,
                    PEMRPolyDraw(R)^.aptl[i].Y,
                    PEMRPolyDraw(R)^.aptl[i + 1].X,
                    PEMRPolyDraw(R)^.aptl[i + 1].Y,
                    PEMRPolyDraw(R)^.aptl[i + 2].X,
                    PEMRPolyDraw(R)^.aptl[i + 2].Y);
                  inc(i, 2); // eventual inc(i) below
                  if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                  begin
                    E.Canvas.LineToI(position.X, position.Y);
                    position := PEMRPolyDraw(R)^.aptl[i];
                  end;
                end;
              PT_MOVETO:
                begin
                  with PEMRPolyDraw(R)^.aptl[i] do
                    E.Canvas.MoveToI(X, Y);
                  position := PEMRPolyDraw(R)^.aptl[i];
                end;
            else
              break; // invalid type
            end;
            inc(i);
          end;
          position := PEMRPolyDraw(R)^.aptl[PEMRPolyDraw(R)^.cptl - 1];
          Moved := false;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
            else
              E.Canvas.NewPath;
        end;
      EMR_POLYDRAW16:
        if PEMRPolyDraw16(R)^.cpts > 0 then
        begin
          if not pen.null then
            E.NeedPen;
          polytypes := @PEMRPolyDraw16(R)^.apts[PEMRPolyDraw16(R)^.cpts];
          i := 0;
          while i < integer(PEMRPolyDraw16(R)^.cpts) do
          begin
            case polytypes^[i] and not PT_CLOSEFIGURE of
              PT_LINETO:
                begin
                  with PEMRPolyDraw16(R)^.apts[i] do
                    E.Canvas.LineToI(X, Y);
                  if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                  begin
                    E.Canvas.LineToI(position.X, position.Y);
                    with PEMRPolyDraw16(R)^.apts[i] do
                    begin
                      position.X := x;
                      position.Y := Y;
                    end;
                  end;
                end;
              PT_BEZIERTO:
                begin
                  E.Canvas.CurveToCI(
                    PEMRPolyDraw16(R)^.apts[i].X,
                    PEMRPolyDraw16(R)^.apts[i].Y,
                    PEMRPolyDraw16(R)^.apts[i + 1].X,
                    PEMRPolyDraw16(R)^.apts[i + 1].Y,
                    PEMRPolyDraw16(R)^.apts[i + 2].X,
                    PEMRPolyDraw16(R)^.apts[i + 2].Y);
                  inc(i, 2); // eventual inc(i) below
                  if polytypes^[i] and PT_CLOSEFIGURE <> 0 then
                  begin
                    E.Canvas.LineToI(position.X, position.Y);
                    with PEMRPolyDraw16(R)^.apts[i] do
                    begin
                      position.X := X;
                      position.Y := Y;
                    end;
                  end;
                end;
              PT_MOVETO:
                begin
                  with PEMRPolyDraw16(R)^.apts[i] do
                  begin
                    E.Canvas.MoveToI(X, Y);
                    position.X := X;
                    position.Y := Y;
                  end;
                end;
            else
              break; // invalid type
            end;
            inc(i);
          end;
          with PEMRPolyDraw16(R)^.apts[PEMRPolyDraw16(R)^.cpts - 1] do
          begin
            position.X := X;
            position.Y := Y;
          end;
          Moved := false;
          if not E.Canvas.fNewPath then
            if not pen.null then
              E.Canvas.Stroke
            else
              E.Canvas.NewPath;
        end;
      EMR_BITBLT:
        begin
          with PEMRBitBlt(R)^ do // only handle RGB bitmaps (no palette)
            if (offBmiSrc <> 0) and
               (offBitsSrc <> 0) then
              E.DrawBitmap(xSrc, ySrc, cxDest, cyDest, xDest, yDest,
                cxDest, cyDest, iUsageSrc, pointer(PtrUInt(R) + offBmiSrc),
                pointer(PtrUInt(R) + offBitsSrc), @rclBounds, @xformSrc, dwRop)
            else
              case dwRop of // we only handle PATCOPY = fillrect
                PATCOPY:
                  E.FillRectangle(Rect(xDest, yDest,
                    xDest + cxDest, yDest + cyDest), true);
              end;
        end;
      EMR_STRETCHBLT:
        begin
          with PEMRStretchBlt(R)^ do // only handle RGB bitmaps (no palette)
            if (offBmiSrc <> 0) and
               (offBitsSrc <> 0) then
              E.DrawBitmap(xSrc, ySrc, cxSrc, cySrc, xDest, yDest, cxDest,
                cyDest, iUsageSrc, pointer(PtrUInt(R) + offBmiSrc),
                pointer(PtrUInt(R) + offBitsSrc), @rclBounds, @xformSrc, dwRop)
            else
              case dwRop of // we only handle PATCOPY = fillrect
                PATCOPY:
                  E.FillRectangle(Rect(
                    xDest, yDest, xDest + cxDest, yDest + cyDest), true);
              end;
        end;
      EMR_STRETCHDIBITS:
        with PEMRStretchDIBits(R)^ do // only handle RGB bitmaps (no palette)
          if (offBmiSrc <> 0) and
             (offBitsSrc <> 0) then
          begin
            if WorldTransform.eM22 < 0 then
              with PBitmapInfo(PtrUInt(R) + offBmiSrc)^ do
                bmiHeader.biHeight := -bmiHeader.biHeight;
            E.DrawBitmap(xSrc, ySrc, cxSrc, cySrc, xDest, yDest, cxDest, cyDest,
              iUsageSrc, pointer(PtrUInt(R) + offBmiSrc),
              pointer(PtrUInt(R) + offBitsSrc), @rclBounds, nil, dwRop);
          end;
      EMR_TRANSPARENTBLT:
        with PEMRTransparentBLT(R)^ do // only handle RGB bitmaps (no palette)
          if (offBmiSrc <> 0) and
             (offBitsSrc <> 0) then
            E.DrawBitmap(xSrc, ySrc, cxSrc, cySrc, xDest, yDest, cxDest, cyDest,
              iUsageSrc, pointer(PtrUInt(R) + offBmiSrc),
              pointer(PtrUInt(R) + offBitsSrc), @rclBounds, @xformSrc, SRCCOPY,
              dwRop); // dwRop stores the transparent color
      EMR_ALPHABLEND:
        with PEMRAlphaBlend(R)^ do // only handle RGB bitmaps (no palette nor transparency)
          if (offBmiSrc <> 0) and
             (offBitsSrc <> 0) then
            E.DrawBitmap (xSrc, ySrc, cxSrc, cySrc, xDest, yDest, cxDest, cyDest,
              iUsageSrc, pointer(PtrUInt(R) + offBmiSrc), pointer(
               PtrUInt(R) + offBitsSrc), @rclBounds, @xformSrc, SRCCOPY, dwRop)
          else
            case dwRop of // we only handle PATCOPY = fillrect
              PATCOPY:
                E.FillRectangle(Rect(xDest, yDest,
                  xDest + cxDest, yDest + cyDest), true);
            end;
      EMR_GDICOMMENT:
        with PEMRGDIComment(R)^ do
          if cbData >= 1  then
            E.HandleComment(
              TPdfGdiComment(Data[0]), PAnsiChar(@Data) + 1, cbData - 1);
      EMR_MODIFYWORLDTRANSFORM:
        with PEMRModifyWorldTransform(R)^ do
          E.ScaleMatrix(@xform, iMode);
      EMR_EXTCREATEPEN: // approx. - fast solution
        with PEMRExtCreatePen(R)^ do
          if ihPen - 1 < cardinal(length(E.Obj)) then
            with E.obj[ihPen - 1] do
            begin
              kind := OBJ_PEN;
              PenColor := elp.elpColor;
              PenWidth := elp.elpWidth;
              PenStyle := elp.elpPenStyle and (PS_STYLE_MASK or PS_ENDCAP_MASK);
            end;
      EMR_SETMITERLIMIT:
        if PEMRSetMiterLimit(R)^.eMiterLimit > 0.1 then
          E.Canvas.SetMiterLimit(PEMRSetMiterLimit(R)^.eMiterLimit);
      EMR_SETMETARGN:
        E.SetMetaRgn;
      EMR_EXTSELECTCLIPRGN:
        E.ExtSelectClipRgn(PEMRExtSelectClipRgn(R));
      EMR_INTERSECTCLIPRECT:
        ClipRgn := E.IntersectClipRect(E.Canvas.BoxI(
          TRect(PEMRIntersectClipRect(R)^.rclClip), true), ClipRgn);
      EMR_SETMAPMODE:
        MappingMode := PEMRSetMapMode(R)^.iMode;
      EMR_BEGINPATH:
        begin
          E.Canvas.NewPath;
          if not Moved then
          begin
            E.Canvas.MoveToI(position.X, position.Y);
            Moved := true;
          end;
        end;
      EMR_ENDPATH:
        E.Canvas.fNewPath := false;
      EMR_ABORTPATH:
        begin
          E.Canvas.NewPath;
          E.Canvas.fNewPath := false;
        end;
      EMR_CLOSEFIGURE:
        E.Canvas.ClosePath;
      EMR_FILLPATH:
        begin
          if not brush.Null then
          begin
            E.FillColor := brush.color;
            E.Canvas.Fill;
          end;
          E.Canvas.NewPath;
          E.Canvas.fNewPath := false;
        end;
      EMR_STROKEPATH:
        begin
          if not pen.null then
          begin
            E.NeedPen;
            E.Canvas.Stroke;
          end;
          E.Canvas.NewPath;
          E.Canvas.fNewPath := false;
        end;
      EMR_STROKEANDFILLPATH:
        begin
          if not brush.Null then
          begin
            E.NeedPen;
            E.FillColor := brush.color;
            if not pen.null then
              if PolyFillMode = ALTERNATE then
                E.Canvas.EofillStroke
              else
                E.Canvas.FillStroke
            else if PolyFillMode = ALTERNATE then
              E.Canvas.EoFill
            else
              E.Canvas.Fill
          end
          else if not pen.null then
          begin
            E.NeedPen;
            E.Canvas.Stroke;
          end;
          E.Canvas.NewPath;
          E.Canvas.fNewPath := false;
        end;
      EMR_SETPOLYFILLMODE:
        PolyFillMode := PEMRSetPolyFillMode(R)^.iMode;
      EMR_GRADIENTFILL:
        E.GradientFill(PEMGradientFill(R));
      EMR_SETSTRETCHBLTMODE:
        StretchBltMode := PEMRSetStretchBltMode(R)^.iMode;
      EMR_SETARCDIRECTION:
        ArcDirection := PEMRSetArcDirection(R)^.iArcDirection;
      EMR_SETPIXELV:
        begin
          // prepare pixel size and color
          if pen.width <> 1 then
          begin
            E.fPenWidth := E.Canvas.fWorldFactorX * E.Canvas.fDevScaleX;
            E.Canvas.SetLineWidth(E.fPenWidth * E.Canvas.fFactorX);
          end;
          if PEMRSetPixelV(R)^.crColor <> cardinal(pen.color) then
            E.Canvas.SetRGBStrokeColor(PEMRSetPixelV(R)^.crColor);
          // draw point
          position := TPoint(Point(PEMRSetPixelV(R)^.ptlPixel.X, PEMRSetPixelV(R)
            ^.ptlPixel.Y));
          E.Canvas.PointI(position.X, position.Y);
          E.Canvas.Stroke;
          Moved := false;
          // rollback pixel size and color
          if pen.width <> 1 then
          begin
            E.fPenWidth := pen.width * E.Canvas.fWorldFactorX * E.Canvas.fDevScaleX;
            E.Canvas.SetLineWidth(E.fPenWidth * E.Canvas.fFactorX);
          end;
          if PEMRSetPixelV(R)^.crColor <> cardinal(pen.color) then
            E.Canvas.SetRGBStrokeColor(pen.color);
        end;
     // TBD
      EMR_SMALLTEXTOUT,
      EMR_SETROP2,
      EMR_ALPHADIBBLEND,
      EMR_SETBRUSHORGEX,
      EMR_SETICMMODE,
      EMR_SELECTPALETTE,
      EMR_CREATEPALETTE,
      EMR_SETPALETTEENTRIES,
      EMR_RESIZEPALETTE,
      EMR_REALIZEPALETTE,
      EMR_EOF:
        ; //do nothing
    else
      R^.iType := R^.iType; // for debug purpose (breakpoint)
    end;
  case R^.iType of
    EMR_RESTOREDC,
    EMR_SETWINDOWEXTEX,
    EMR_SETWINDOWORGEX,
    EMR_SETVIEWPORTEXTEX,
    EMR_SETVIEWPORTORGEX,
    EMR_SETMAPMODE:
      E.ScaleMatrix(nil, MWT_SET); //recalc new transformation
  end;
end;

procedure RenderMetaFile(C: TPdfCanvas; MF: TMetaFile; ScaleX, ScaleY,
  XOff, YOff: single; TextPositioning: TPdfCanvasRenderMetaFileTextPositioning;
  KerningHScaleBottom, KerningHScaleTop: single;
  TextClipping: TPdfCanvasRenderMetaFileTextClipping);
var
  A: TPdfCanvasAccess;
  E: TPdfEnum;
  R: TRect;
begin
  R.Left := 0;
  R.Top := 0;
  R.Right := MF.Width;
  R.Bottom := MF.Height;
  if ScaleY = 0 then
    ScaleY := ScaleX; // if ScaleY is ommited -> assume symmetric coordinates
  A := TPdfCanvasAccess(C);
  E := TPdfEnum.Create(C);
  try
    A.fOffsetXDef := XOff;
    A.fOffsetYDef := YOff;
    A.fDevScaleX := ScaleX * A.fFactor;
    A.fDevScaleY := ScaleY * A.fFactor;
    A.fEmfBounds := R; // keep device rect
    A.fUseMetaFileTextPositioning := TextPositioning;
    A.fUseMetaFileTextClipping := TextClipping;
    A.fKerningHScaleBottom := KerningHScaleBottom;
    A.fKerningHScaleTop := KerningHScaleTop;
    with TPdfDocumentAccess(A.fDoc) do
    begin
      if fPrinterPxPerInch.X = 0 then
        fPrinterPxPerInch := CurrentPrinterRes; // caching for major speedup
      A.fPrinterPxPerInch := fPrinterPxPerInch;
    end;
    with E.DC[0] do
    begin
      Int64(WinSize) := PInt64(@R.Right)^;
      ViewSize := WinSize;
    end;
    C.GSave;
    try
      {$ifdef FPC}
      EnumEnhMetaFile(TPdfDocumentAccess(A.fDoc).EmfDC, MF.Handle, @EnumEMFFunc, E, Windows.RECT(R));
      {$else}
      EnumEnhMetaFile(TPdfDocumentAccess(A.fDoc).EmfDC, MF.Handle, @EnumEMFFunc, E, TRect(R));
      {$endif FPC}
    finally
      C.GRestore;
    end;
  finally
    E.Free;
  end;
end;



{ TPdfEnum }

constructor TPdfEnum.Create(ACanvas: TPdfCanvas);
begin
  Canvas := TPdfCanvasAccess(ACanvas);
  // set invalid colors or style -> force paint
  fFillColor := -1;
  fStrokeColor := -1;
  fPenStyle := -1;
  fPenWidth := -1;
  DC[0].brush.null := true;
  fInitTransformMatrix := DefaultIdentityMatrix;
  DC[0].WorldTransform := fInitTransformMatrix;
  fInitMetaRgn := PdfBox(0, 0, 0, 0);
  DC[0].ClipRgnNull := true;
  DC[0].MappingMode := MM_TEXT;
  DC[0].PolyFillMode := ALTERNATE;
  DC[0].StretchBltMode := STRETCH_DELETESCANS;
end;

procedure TPdfEnum.CreateFont(aLogFont: PEMRExtCreateFontIndirect);
var
  hf: HFONT;
  tm: TTextMetric;
  old: HGDIOBJ;
  dest: HDC;
begin
  dest := TPdfDocumentAccess(Canvas.fDoc).EmfDC;
  hf := CreateFontIndirectW(aLogFont.elfw.elfLogFont);
  old := SelectObject(dest, hf);
  GetTextMetrics(dest, tm);
  SelectObject(dest, old);
  DeleteObject(hf);
  if aLogFont^.ihFont - 1 < cardinal(length(Obj)) then
    with Obj[aLogFont^.ihFont - 1] do
    begin
      kind := OBJ_FONT;
      MoveFast(aLogFont^.elfw.elfLogFont, LogFont, SizeOf(LogFont));
      LogFont.lfPitchAndFamily := tm.tmPitchAndFamily;
      if LogFont.lfOrientation <> 0 then
        FontSpec.angle := LogFont.lfOrientation div 10 // -360..+360
      else
        FontSpec.angle := LogFont.lfEscapement div 10;
      FontSpec.ascent := tm.tmAscent;
      FontSpec.descent := tm.tmDescent;
      FontSpec.cell := tm.tmHeight - tm.tmInternalLeading;
    end;
end;

procedure TPdfEnum.DrawBitmap(xs, ys, ws, hs, xd, yd, wd, hd, usage: integer;
  Bmi: PBitmapInfo; bits: pointer; clipRect: PRect; xSrcTransform: PXForm;
  dwRop: DWord; transparent: TPdfColorRGB);
var
  bmp: TBitmap;
  R: TRect;
  box, clp: TPdfBox;
  fx, fy, ox, oy: single;
begin
  bmp := TBitmap.Create;
  try
    InitTransformation(xSrcTransform, fx, fy, ox, oy);
    // create a TBitmap with (0,0,ws,hs) bounds from DIB bits and info
    if Bmi^.bmiHeader.biBitCount = 1 then
      bmp.Monochrome := true
    else
      bmp.PixelFormat := pf24bit;
    bmp.Width := ws;
    bmp.Height := hs;
    StretchDIBits(bmp.Canvas.Handle, 0, 0, ws, hs, Trunc(xs + ox),
      Trunc(ys + oy), Trunc(ws * fx), Trunc(hs * fy),
      bits, Bmi^, usage, dwRop);
    if transparent <> $FFFFFFFF then
    begin
      if integer(transparent) < 0 then
        transparent := GetSysColor(transparent and $ff);
      bmp.TransparentColor := transparent;
    end;
    // draw the bitmap on the PDF canvas
    with Canvas do
    begin
      R := TRect(Rect(xd, yd, wd + xd, hd + yd));
      NormalizeRect(R);
      inc(R.Bottom);
      inc(R.Right);
      box := BoxI(R, true);
      clp := GetClipRect;
      if (clp.Width > 0) and
         (clp.Height > 0) then
        CreateOrGetBitmapImage(Doc, bmp, @box, @clp) // use cliping
      else
        CreateOrGetBitmapImage(Doc, bmp, @box, nil);
      // CreateOrGetBitmapImage() will reuse any matching TPdfImage
      // don't send bmi and bits parameters here, because of StretchDIBits above
    end;
  finally
    bmp.Free;
  end;
end;

// simulate gradient (not finished)
procedure TPdfEnum.GradientFill(data: PEMGradientFill);
type
  PTriVertex = ^TTriVertex;
  TTriVertex = packed record // circumvent some bug in older Delphi
    x: integer;
    Y: integer;
    Red: word; // COLOR16 wrongly defined in Delphi 6/7 e.g.
    Green: word;
    Blue: word;
    alpha: word;
  end;
  PTriVertexArray = ^TTriVertexArray;
  TTriVertexArray = array[word] of TTriVertex;
  PGradientTriArray = ^TGradientTriArray;
  TGradientTriArray = array[word] of TGradientTriangle;
  PGradientRectArray = ^TGradientRectArray;
  TGradientRectArray = array[word] of TGradientRect;
var
  i: integer;
  vertex: PTriVertexArray;
  tri: PGradientTriArray;
  r: PGradientRectArray;
  pt1, pt2: PTriVertex;
//    Direction: TGradientDirection;
begin
  if data^.nVer > 0 then
  begin
    vertex := @data.Ver;
    case data^.ulMode of
      GRADIENT_FILL_RECT_H,
      GRADIENT_FILL_RECT_V:
        begin
          Canvas.NewPath;
          r := @vertex[data^.nVer];
{         Direction := gdHorizontal;
          if data^.ulMode = GRADIENT_FILL_RECT_V then
            Direction := gdVertical; }
          for i := 1 to data^.nTri do
            with r[i - 1] do
            begin
              pt1 := @vertex[UpperLeft];
              pt2 := @vertex[LowerRight];
              Canvas.MoveToI(pt1.X, pt1.Y);
              Canvas.LineToI(pt1.X, pt2.Y);
              Canvas.LineToI(pt2.X, pt2.Y);
              Canvas.LineToI(pt2.X, pt1.Y);
              Canvas.Closepath;
              Canvas.Fill;
            end;
        end;
      GRADIENT_FILL_TRIANGLE:
        begin
          Canvas.NewPath;
          tri := @vertex[data^.nVer];
          for i := 1 to data^.nTri do
            with tri[i - 1] do
            begin
              with vertex[Vertex1] do
              begin
                FillColor := RGBA(Red, Green, Blue, 0); // ignore Alpha
                Canvas.MoveToI(X, Y);
              end;
              with vertex[Vertex2] do
                Canvas.LineToI(X, Y);
              with vertex[Vertex3] do
                Canvas.LineToI(X, Y);
              with vertex[Vertex1] do
                Canvas.LineToI(X, Y);
              // DC[nDC].Moved := Point(pt1.X, pt1.Y);
              Canvas.Closepath;
              Canvas.Fill;
            end;
        end;
    end;
  end;
end;

procedure TPdfEnum.PolyPoly(data: PEMRPolyPolygon; iType: integer);
var
  i, j, o, f: DWord;
  a: PPointArray;
  a16: PSmallPointArray;
  data16: PEMRPolyPolygon16 absolute data;
begin
  NeedBrushAndPen;
  if not Canvas.fNewPath then
    Canvas.NewPath;
  case iType of
    EMR_POLYPOLYGON,
    EMR_POLYPOLYLINE:
      begin
        o := 0;
        a := {%H-}pointer(PtrUInt(data) +
             SizeOf(TEMRPolyPolyline) - SizeOf(TPoint) +
             (data^.nPolys - 1) * SizeOf(DWord));
        for i := 1 to data^.nPolys do
        begin
          f := o;
          Canvas.MoveToI(a[o].x, a[o].Y);
          inc(o);
          for j := 2 to data^.aPolyCounts[i - 1] do
          begin
            Canvas.LineToI(a[o].x, a[o].Y);
            DC[nDC].position := Point(a[o].x,
              a[o].Y);
            inc(o);
          end;
          Canvas.LineToI(a[f].x, a[f].Y);
          DC[nDC].Moved := false;
        end;
      end;
    EMR_POLYPOLYGON16,
    EMR_POLYPOLYLINE16:
      begin
        o := 0;
        a16 := {%H-}pointer(PtrUInt(data16) +
               SizeOf(TEMRPolyPolyline16) - SizeOf(TSmallPoint) +
               (data16^.nPolys - 1) * SizeOf(DWord));
        for i := 1 to data16^.nPolys do
        begin
          f := o;
          Canvas.MoveToI(a16[o].x, a16[o].Y);
          inc(o);
          for j := 2 to data16^.aPolyCounts[i - 1] do
          begin
            Canvas.LineToI(a16[o].x, a16[o].Y);
            DC[nDC].position := Point(a16[o].x,
              a16[o].Y);
            inc(o);
          end;
          Canvas.LineToI(a16[f].x, a16[f].Y);
          DC[nDC].Moved := false;
        end;
      end;
  end;
  if iType in [EMR_POLYPOLYLINE, EMR_POLYPOLYLINE16] then
  begin // stroke
    if not DC[nDC].pen.null then
      Canvas.Stroke
    else
      Canvas.NewPath;
  end
  else
  begin
    // fill
    if not DC[nDC].brush.null then
    begin
      if not DC[nDC].pen.null then
        if DC[nDC].PolyFillMode = ALTERNATE then
          Canvas.EofillStroke
        else
          Canvas.FillStroke
      else if DC[nDC].PolyFillMode = ALTERNATE then
        Canvas.EoFill
      else
        Canvas.Fill
    end
    else if not DC[nDC].pen.null then
      Canvas.Stroke
    else
      Canvas.NewPath;
  end;
end;

procedure TPdfEnum.FillRectangle(const Rect: TRect; ResetNewPath: boolean);
begin
  if DC[nDC].brush.null then
    exit;
  Canvas.NewPath;
  FillColor := DC[nDC].brush.color;
  with Canvas.BoxI(Rect, true) do
    Canvas.Rectangle(Left, Top, Width, Height);
  Canvas.Fill;
  if ResetNewPath then
    Canvas.fNewPath := false;
end;

procedure TPdfEnum.FlushPenBrush;
begin
  with DC[nDC] do
  begin
    if brush.null then
    begin
      if not pen.null then
        Canvas.Stroke
      else
        Canvas.NewPath;
    end
    else if pen.null then
      Canvas.Fill
    else
      Canvas.FillStroke;
  end;
end;

procedure TPdfEnum.SelectObjectFromIndex(iObject: integer);
begin
  with DC[nDC] do
  begin
    if iObject < 0 then
    begin // stock object?
      iObject := iObject and $7fffffff;
      case iObject of
        NULL_BRUSH:
          brush.null := true;
        WHITE_BRUSH..BLACK_BRUSH:
          begin
            brush.color := STOCKBRUSHCOLOR[iObject];
            brush.null := false;
          end;
        NULL_PEN:
          begin
            if fInLined and
               ((pen.style <> PS_NULL) or not pen.null) then
            begin
              fInLined := false;
              if not pen.null then
                Canvas.Stroke;
            end;
            pen.style := PS_NULL;
            pen.null := true;
          end;
        WHITE_PEN,
        BLACK_PEN:
          begin
            if fInLined and
               ((pen.color <> STOCKPENCOLOR[iObject]) or not pen.null) then
            begin
              fInLined := false;
              if not pen.null then
                Canvas.Stroke;
            end;
            pen.color := STOCKPENCOLOR[iObject];
            pen.null := false;
          end;
      end;
    end
    else if cardinal(iObject - 1) < cardinal(length(Obj)) then // avoid GPF
      with Obj[iObject - 1] do
        case Kind of // ignore any invalid reference
          OBJ_PEN:
            begin
              if fInLined and
                 ((pen.color <> PenColor) or
                  (pen.width <> PenWidth) or
                  (pen.style <> PenStyle)) then
              begin
                fInLined := false;
                if not pen.null then
                  Canvas.Stroke;
              end;
              pen.null := (PenWidth < 0) or
                          (PenStyle = PS_NULL); // !! 0 means as thick as possible
              pen.color := PenColor;
              pen.width := PenWidth;
              pen.style := PenStyle;
            end;
          OBJ_BRUSH:
            begin
              brush.null := BrushNull;
              brush.color := BrushColor;
              brush.style := BrushStyle;
            end;
          OBJ_FONT:
            begin
              Font.spec := FontSpec;
              MoveFast(LogFont, Font.LogFont, SizeOf(LogFont));
            end;
        end;
  end;
end;

procedure TPdfEnum.HandleComment(Kind: TPdfGdiComment; P: PAnsiChar; Len: integer);
var
  Text: RawUtf8;
  Img: TPdfImage;
  ImgName: PdfString;
  ImgRect: TPdfRect;
begin
  try
    case Kind of
      pgcOutline: // pgcOutline, @aLevel, 4, aTitle
        if Len > 4 then
        begin
          FastSetString(Text, P + 4, Len - 4);
          Canvas.Doc.CreateOutline(Utf8ToString(Trim(Text)), PInteger(P)^,
            Canvas.I2Y(DC[nDC].position.Y));
        end;
      pgcBookmark: // pgcBookmark, nil, 0, aBookMarkName
        begin
          FastSetString(Text, P, Len);
          Canvas.Doc.CreateBookMark(Canvas.I2Y(DC[nDC].position.Y), Text);
        end;
      pgcLink,
      pgcLinkNoBorder: // pgc[NoBorder], @aRect, SizeOf(aRect), aBookmarkName
        if Len > Sizeof(TRect) then
        begin
          FastSetString(Text, P + SizeOf(TRect), Len - SizeOf(TRect));
          Canvas.Doc.CreateLink(
            Canvas.RectI(PRect(P)^, true), Text, abSolid, ord(Kind = pgcLink));
        end;
      pgcJpegDirect: // pgcJpegDirect, @aRect, SizeOf(aRect), aFileName
        if Len > Sizeof(TRect) then
        begin
          FastSetString(Text, P + SizeOf(TRect), Len - SizeOf(TRect));
          ImgName := 'SynImgJpg' + PdfString(crc32cUtf8ToHex(Text));
          if Canvas.Doc.GetXObject(ImgName) = nil then
          begin
            Img := TPdfImage.CreateJpegDirect(Canvas.Doc, Utf8ToString(Text));
            Canvas.Doc.RegisterXObject(Img, ImgName);
          end;
          ImgRect := Canvas.RectI(PRect(P)^, true);
          Canvas.DrawXObject(ImgRect.Left, ImgRect.Top,
            ImgRect.Right - ImgRect.Left, ImgRect.Bottom - ImgRect.Top, ImgName);
        end;
      pgcBeginMarkContent: // pgcBeginMarkContent, @Group, SizeOf(Group)
        if Len = SizeOf(pointer) then
          Canvas.BeginMarkedContent(PPointer(P)^);
      pgcEndMarkContent: // pgcEndMarkContent, nil, 0
        Canvas.EndMarkedContent;
    end;
  except
    on Exception do
      ; // ignore any error (continue EMF enumeration)
  end;
end;

procedure TPdfEnum.NeedBrushAndPen;
begin
  if fInlined then
  begin
    fInlined := false;
    Canvas.Stroke;
  end;
  NeedPen;
  with DC[nDC] do
    if not brush.null then
      FillColor := brush.color;
end;

procedure TPdfEnum.NeedPen;
begin
  with DC[nDC] do
    if not pen.null then
    begin
      StrokeColor := pen.color;
      if pen.style <> fPenStyle then
      begin
        case pen.style and PS_STYLE_MASK of
          PS_DASH:
            Canvas.SetDash([4, 4]);
          PS_DOT:
            Canvas.SetDash([1, 1]);
          PS_DASHDOT:
            Canvas.SetDash([4, 1, 1, 1]);
          PS_DASHDOTDOT:
            Canvas.SetDash([4, 1, 1, 1, 1, 1]);
        else
          Canvas.SetDash([]);
        end;
        case Pen.style and PS_ENDCAP_MASK of
          PS_ENDCAP_ROUND:
            Canvas.SetLineCap(lcRound_End);
          PS_ENDCAP_SQUARE:
            Canvas.SetLineCap(lcProjectingSquareEnd);
          PS_ENDCAP_FLAT:
            Canvas.SetLineCap(lcButt_End);
        end;
        fPenStyle := pen.style;
      end;
      if pen.width * Canvas.fWorldFactorX * Canvas.fDevScaleX <> fPenWidth then
      begin
        if pen.width = 0 then
          fPenWidth := Canvas.fWorldFactorX * Canvas.fDevScaleX
        else
          fPenWidth := pen.width * Canvas.fWorldFactorX * Canvas.fDevScaleX;
        Canvas.SetLineWidth(fPenWidth * Canvas.fFactorX);
      end;
    end
    else
    begin
      // pen.null need reset values
      fStrokeColor := -1;
      fPenWidth := -1;
      fPenStyle := -1;
    end;
end;

procedure TPdfEnum.RestoreDC;
begin
  Assert(nDC > 0);
  dec(nDC);
end;

procedure TPdfEnum.SaveDC;
begin
  Assert(nDC < high(DC));
  DC[nDC + 1] := DC[nDC];
  inc(nDC);
end;

procedure TPdfEnum.ScaleMatrix(Custom: PXForm; iMode: integer);
var
  xf: XForm;
  xdim, ydim: single;
  mx, my: integer;
begin
  if fInlined then
  begin
    fInlined := false;
    if not DC[nDC].pen.null then
      Canvas.Stroke;
  end;
  with DC[nDC], Canvas do
  begin
    fViewSize := ViewSize;
    fViewOrg := ViewOrg;
    fWinSize := WinSize;
    fWinOrg := WinOrg;
    case MappingMode of
      MM_TEXT:
        begin
          fViewSize.cx := 1;
          fViewSize.cy := 1;
          fWinSize.cx := 1;
          fWinSize.cy := 1;
        end;
      MM_LOMETRIC:
        begin
          fViewSize.cx := fPrinterPxPerInch.X;
          fViewSize.cy := -fPrinterPxPerInch.Y;
          fWinSize.cx := WinSize.cx * 10;
          fWinSize.cy := WinSize.cy * 10;
        end;
      MM_HIMETRIC:
        begin
          fViewSize.cx := fPrinterPxPerInch.X;
          fViewSize.cy := -fPrinterPxPerInch.Y;
          fWinSize.cx := WinSize.cx * 100;
          fWinSize.cy := WinSize.cy * 100;
        end;
      MM_LOENGLISH:
        begin
          fViewSize.cx := fPrinterPxPerInch.X;
          fViewSize.cy := -fPrinterPxPerInch.Y;
          fWinSize.cx := MulDiv(1000, WinSize.cx, 254);
          fWinSize.cy := MulDiv(1000, WinSize.cy, 254);
        end;
      MM_HIENGLISH:
        begin
          fViewSize.cx := fPrinterPxPerInch.X;
          fViewSize.cy := -fPrinterPxPerInch.Y;
          fWinSize.cx := MulDiv(10000, WinSize.cx, 254);
          fWinSize.cy := MulDiv(10000, WinSize.cy, 254);
        end;
      MM_TWIPS:
        begin
          fViewSize.cx := fPrinterPxPerInch.X;
          fViewSize.cy := -fPrinterPxPerInch.Y;
          fWinSize.cx := MulDiv(14400, WinSize.cx, 254);
          fWinSize.cy := MulDiv(14400, WinSize.cy, 254);
        end;
      MM_ISOTROPIC:
        begin
          fViewSize.cx := fPrinterPxPerInch.X;
          fViewSize.cy := -fPrinterPxPerInch.Y;
          fWinSize.cx := WinSize.cx * 10;
          fWinSize.cy := WinSize.cy * 10;
          xdim := Abs(fViewSize.cx * WinSize.cx / (fPrinterPxPerInch.X * fWinSize.cx));
          ydim := Abs(fViewSize.cy * WinSize.cy / (fPrinterPxPerInch.Y * fWinSize.cy));
          if xdim > ydim then
          begin
            if fViewSize.cx >= 0 then
              mx := 1
            else
              mx := -1;
            fViewSize.cx := Trunc(fViewSize.cx * ydim / xdim + 0.5);
            if fViewSize.cx = 0 then
              fViewSize.cx := mx;
          end
          else
          begin
            if fViewSize.cy >= 0 then
              my := 1
            else
              my := -1;
            fViewSize.cy := Trunc(fViewSize.cy * xdim / ydim + 0.5);
            if fViewSize.cy = 0 then
              fViewSize.cy := my;
          end;
        end;
      MM_ANISOTROPIC:
        ;  // TBD
    end;
    if fWinSize.cx = 0 then // avoid EZeroDivide
      fFactorX := 1.0
    else
      fFactorX := Abs(fViewSize.cx / fWinSize.cx);
    if fWinSize.cy = 0 then // avoid EZeroDivide
      fFactorY := 1.0
    else
      fFactorY := Abs(fViewSize.cy / fWinSize.cy);
    if Custom <> nil then
    begin
      // S.eM11=fFactorX S.eM12=0 S.eM21=0 S.eM22=fFactorY multiplied by Custom^
      case iMode of
        MWT_IDENTITY: // reset identity matrix
          WorldTransform := DefaultIdentityMatrix;
        MWT_LEFTMULTIPLY:
          WorldTransform := CombineTransform(Custom^, WorldTransform);
        MWT_RIGHTMULTIPLY:
          WorldTransform := CombineTransform(WorldTransform, Custom^);
        MWT_SET:
          WorldTransform := Custom^;
      end;
    end;
    // use transformation
    xf := WorldTransform;
    if (xf.eM11 > 0) and
       (xf.eM22 > 0) and
       (xf.eM12 = 0) and
       (xf.eM21 = 0) then
    begin // Scale
      fWorldFactorX := xf.eM11;
      fWorldFactorY := xf.eM22;
      fWorldOffsetX := WorldTransform.eDx;
      fWorldOffsetY := WorldTransform.eDy;
    end
    else if (xf.eM22 = xf.eM11) and
            (xf.eM21 = -xf.eM12) then
    begin // Rotate
      fAngle := ArcSin(xf.eM12) * c180divPI;
      fWorldOffsetCos := xf.eM11;
      fWorldOffsetSin := xf.eM12;
    end
    else if (xf.eM11 = 0) and
            (xf.eM22 = 0) and
            ((xf.eM12 <> 0) or
             (xf.eM21 <> 0)) then
    begin //Shear

    end
    else if ((xf.eM11 < 0) or
             (xf.eM22 < 0)) and
            (xf.eM12 = 0) and
            (xf.eM21 = 0) then
    begin //Reflection

    end;
  end;
end;

procedure TPdfEnum.InitMetaRgn(const ClientRect: TRect);
begin
  fInitMetaRgn := Canvas.BoxI(ClientRect, true);
  DC[nDC].ClipRgnNull := true;
  DC[nDC].MetaRgn := fInitMetaRgn;
end;

procedure TPdfEnum.SetMetaRgn;
begin
  try
    with DC[nDC] do
      if not ClipRgnNull then
      begin
        MetaRgn := IntersectClipRect(ClipRgn, MetaRgn);
        FillCharFast(ClipRgn, SizeOf(ClipRgn), 0);
        ClipRgnNull := true;
      end;
  except
    on e: Exception do
      ; // ignore any error (continue EMF enumeration)
  end;
end;

function TPdfEnum.IntersectClipRect(const ClpRect: TPdfBox;
  const CurrRect: TPdfBox): TPdfBox;
begin
  result := CurrRect;
  if (ClpRect.Width <> 0) or
     (ClpRect.Height <> 0) then
  begin // ignore null clipping area
    if ClpRect.Left > result.Left then
      result.Left := ClpRect.Left;
    if ClpRect.Top > result.Top then
      result.Top := ClpRect.Top;
    if (ClpRect.Left + ClpRect.Width) < (result.Left + result.Width) then
      result.Width := (ClpRect.Left + ClpRect.Width) - result.Left;
    if (ClpRect.Top + ClpRect.Height) < (result.Top + result.Height) then
      result.Height := (ClpRect.Top + ClpRect.Height) - result.Top;
    // fix rect
    if result.Width < 0 then
      result.Width := 0;
    if result.Height < 0 then
      result.Height := 0;
  end;
end;

procedure TPdfEnum.ExtSelectClipRgn(data: PEMRExtSelectClipRgn);
var
  i: integer;
  d: PRgnData;
  pr: PRect;
  r: TRect;
begin
  // see http://www.codeproject.com/Articles/1944/Guide-to-WIN-Regions
  if data^.iMode <> RGN_COPY then
    exit; // we are handling RGN_COPY (5) only
  if not DC[nDC].ClipRgnNull then // if current clip then finish
  begin
    Canvas.GRestore;
    Canvas.NewPath;
    Canvas.fNewPath := false;
    DC[nDC].ClipRgnNull := true;
    fFillColor := -1;
  end;
  if Data^.cbRgnData > 0 then
  begin
    Canvas.GSave;
    Canvas.NewPath;
    DC[nDC].ClipRgnNull := false;
    d := @Data^.RgnData;
    pr := @d^.Buffer;
    for i := 1 to d^.rdh.nCount do
    begin
      r := pr^;
      inc(r.Bottom);
      inc(r.Right);
      with Canvas.BoxI(r, false) do
        Canvas.Rectangle(Left, Top, Width, Height);
      inc(pr);
    end;
    Canvas.Closepath;
    Canvas.Clip;
    Canvas.NewPath;
    Canvas.FNewPath := false;
  end;
end;

function TPdfEnum.GetClipRect: TPdfBox;
begin // get current clip area
  with DC[nDC] do
    if ClipRgnNull then
      result := MetaRgn
    else
      result := ClipRgn;
end;

procedure TPdfEnum.SetFillColor(Value: integer);
begin
  if fFillColor = Value then
    exit;
  Canvas.SetRGBFillColor(Value);
  fFillColor := Value;
end;

procedure TPdfEnum.SetStrokeColor(Value: integer);
begin
  if fStrokeColor = Value then
    exit;
  Canvas.SetRGBStrokeColor(Value);
  fStrokeColor := Value;
end;

function DXTextWidth(DX: PIntegerArray; n: PtrInt): integer;
var
  i: PtrInt;
begin
  result := 0;
  for i := 0 to n - 1 do
    inc(result, DX^[i]);
end;

procedure TPdfEnum.TextOut(var R: TEMRExtTextOut);
var
  sx, sy, nspace, i: integer;
  cur: cardinal;
  ws, ss, xs, ys, ww, mw, w, h, hscale: single;
  a, acos, asin, fscaleX, fscaleY: single;
  dx: PIntegerArray; // not handled during drawing yet
  posi: TPoint;
  tmp: array of WideChar; // R.emrtext is not #0 terminated -> use tmp[]
  hasdx, clipped, isopaque: boolean;
  tmp2: array[0..1] of WideChar;
  clip: TPdfBox;
  back: TRect;
  po: TPdfCanvasRenderMetaFileTextPositioning;
  {$ifdef USE_UNISCRIBE}
  fnt: TPdfFont;
  dest: HDC;
  old: HGDIOBJ;
  siz: TSize;
  {$endif USE_UNISCRIBE}

  procedure DrawLine(var P: TPoint; aH: single);
  var
    tmp: TPdfEnumStatePen;
  begin
    with DC[nDC] do
    begin
      tmp := Pen;
      pen.color := Font.color;
      pen.width := ss / (fscaleY * 15);
      pen.style := PS_SOLID;
      pen.null := false;
      NeedPen;
      if Font.spec.angle = 0 then
      begin
        // P = textout original coords
        // (-w,-h) = delta to text start pos (at baseline)
        // ww = text width
        // aH = delta h for drawed line (from baseline)
        Canvas.MoveToS(P.X - w, (P.Y - (h - aH)));
        //  deltax := -w     deltaY := (-h+aH)
        Canvas.LineToS(P.X - w + ww, (P.Y - (h - aH)));
        //  deltax := -w+ww  deltaY := (-h+aH)
      end
      else
      begin
        // rotation pattern:
        //   rdx = deltax * acos + deltay * asin
        //   rdy = deltay * acos - deltax * asin
        Canvas.MoveToS(P.X + ((-w) * acos + (-h + aH) * asin),
                       P.Y + ((-h + aH) * acos - (-w) * asin));
        Canvas.LineToS(P.X + ((-w + ww) * acos + (-h + aH) * asin),
                       P.Y + ((-h + aH) * acos - (-w + ww) * asin));
      end;
      Canvas.Stroke;
      Pen := tmp;
      NeedPen;
    end;
  end;

begin
  if R.emrtext.nChars > 0 then
    with DC[nDC] do
    begin
      SetLength(tmp, R.emrtext.nChars + 1); // faster than WideString for our purpose
      MoveFast(pointer(PtrUInt(@R) + R.emrtext.offString)^, tmp[0], R.emrtext.nChars * 2);
      sy := 1;
      sx := 1;
      if (Canvas.fWorldFactorY) < 0 then
        sy := -1;
      if (Canvas.fWorldFactorX) < 0 then
        sx := -1;
      fscaleY := Abs(Canvas.fFactorY * Canvas.fWorldFactorY * Canvas.fDevScaleY);
      fscaleX := Abs(Canvas.fFactorX * Canvas.fWorldFactorX * Canvas.fDevScaleX);
      // guess the font size
      if Font.LogFont.lfHeight < 0 then
        ss := Abs(Font.LogFont.lfHeight) * fscaleY
      else
        ss := Abs(Font.spec.cell) * fscaleY;
      // ensure this font is selected (very fast if was already selected)
      {$ifdef USE_UNISCRIBE}fnt :={$endif} Canvas.SetFont(TPdfDocumentAccess(Canvas.fDoc).EmfDC, Font.LogFont, ss);
      // calculate coordinates
      po := Canvas.fUseMetaFileTextPositioning;
      if (R.emrtext.fOptions and ETO_GLYPH_INDEX <> 0) then
        mw := 0
      else
      begin
        ws := 0;
        {$ifdef USE_UNISCRIBE}
        if Assigned(fnt) and Canvas.fDoc.UseUniScribe and
           fnt.InheritsFrom(TPdfFontTrueType) then
        begin
          // the face's HFONT, selected for this measure only
          dest := TPdfDocumentAccess(Canvas.fDoc).EmfDC;
          old := SelectObject(dest,
            HGDIOBJ(TPdfFontTrueTypeAccess(fnt).fFace.Handle));
          if GetTextExtentPoint32W(dest, pointer(tmp), R.emrtext.nChars, siz) then
            ws := (siz.cX * Canvas.fPage.FontSize) / 1000;
          SelectObject(dest, old);
        end;
        {$endif USE_UNISCRIBE}
        if ws = 0 then
          ws := Canvas.UnicodeTextWidth(pointer(tmp));
        mw := Round(ws / fscaleX);
      end;
      hasdx := R.emrtext.offDx > 0;
      {$ifdef USE_UNISCRIBE}
      if Canvas.fDoc.UseUniScribe then
        hasdx := hasdx and (R.emrtext.fOptions and ETO_GLYPH_INDEX <> 0);
      {$endif USE_UNISCRIBE}
      if hasdx then
      begin
        dx := pointer(PtrUInt(@R) + R.emrtext.offDx);
        w := DXTextWidth(dx, R.emrText.nChars);
        if w < Trunc((R.rclBounds.Right - R.rclBounds.Left) / Canvas.fFactorX) then
          dx := nil; // offDX=0 or within box
      end
      else
        dx := nil;
      if dx = nil then
      begin
        w := mw;
        if po = tpExactTextCharacterPositining then
          po := tpSetTextJustification; // exact position expects dx
      end;
      nspace := 0;
      hscale := 100;
      if mw <> 0 then
      begin
        for i := 0 to R.emrtext.nChars - 1 do
          if tmp[i] = ' ' then
            inc(nspace);
        if (po = tpSetTextJustification) and
           ((nspace = 0) or (({%H-}w - mw) < nspace)) then
          po := tpKerningFromAveragePosition;
        if (po = tpExactTextCharacterPositining) and
           (Font.spec.angle <> 0) then
          po := tpKerningFromAveragePosition;
        case po of
          tpSetTextJustification:
            // we should have had a SetTextJustification() call -> modify word space
            with Canvas do
              SetWordSpace(((w - mw) * fscaleX) / nspace);
          tpKerningFromAveragePosition:
            begin
              // check if dx[] width differs from PDF width
              hscale := (w * 100) / mw;
              // implement some global kerning if needed (allow hysteresis around 100%)
              if (hscale < Canvas.fKerningHScaleBottom) or
                 (hscale > Canvas.fKerningHScaleTop) then
                if Font.spec.angle = 0 then
                  Canvas.SetHorizontalScaling(hscale)
                else
                  hscale := 100
              else
                hscale := 100;
            end;
        end;
      end
      else
        po := tpSetTextJustification;
      ww := w;                                    // right x
      // h Align Mask = TA_CENTER or TA_RIGHT or TA_LEFT = TA_CENTER
      if (Font.Align and TA_CENTER) = TA_CENTER then
        w := w / 2  // center x
      else if (Font.Align and TA_CENTER) = TA_LEFT then
        w := 0;     // left x
      // V Align mask = TA_BASELINE or TA_BOTTOM or TA_TOP = TA_BASELINE
      if (Font.Align and TA_BASELINE) = TA_BASELINE then
      // always zero ?
        h := Abs(Font.LogFont.lfHeight) - Abs(Font.spec.cell)  // center y
      else if (Font.Align and TA_BASELINE) = TA_BOTTOM then
        h := Abs(Font.spec.descent)  // bottom y
      else
        // needs - vertical coords of baseline from top
        h := -abs(Font.spec.ascent); // top
      if sy < 0 then // inverted coordinates
        h := Abs(Font.LogFont.lfHeight) + h;
      if sx < 0 then
        w := w + ww;
      if (Font.align and TA_UPDATECP) = TA_UPDATECP then
        posi := position
      else
        posi := R.emrtext.ptlReference;
      // detect clipping
      if Canvas.fUseMetaFileTextClipping <> tcNeverClip then
      begin
        with R.emrtext.rcl do
          clipped := (Right > Left) and (Bottom > Top);
        if clipped then
          clip := Canvas.BoxI(TRect(R.emrtext.rcl), true)
        else
        begin
          if Canvas.fUseMetaFileTextClipping = tcClipExplicit then
            with R.rclBounds do
              clipped := (Right > Left) and (Bottom > Top);
          if clipped then
            clip := Canvas.BoxI(TRect(R.rclBounds), true)
          else
          begin
            clipped := not ClipRgnNull and
                        (Canvas.fUseMetaFileTextClipping = tcAlwaysClip);
            if clipped then
              clip := GetClipRect;
          end;
        end;
      end
      else
        clipped := false;
      isopaque := not brush.null and
                 (brush.Color <> clWhite) and
                 ((R.emrtext.fOptions and ETO_OPAQUE <> 0) or
                  ((Font.BkMode = OPAQUE) and
                   (Font.BkColor = brush.color)));
      if isopaque then
        if clipped then
          back := TRect(R.emrtext.rcl)
        else
        begin
          back.TopLeft := posi;
          back.BottomRight := posi;
          inc(back.Right, Trunc(ww));
          inc(back.Bottom, Abs(Font.LogFont.lfHeight));
        end;
      NormalizeRect(back);
      if clipped then
      begin
        Canvas.GSave;
        Canvas.NewPath;
        Canvas.Rectangle({%H-}clip.Left, {%H-}clip.Top,
          {%H-}clip.Width, {%H-}clip.Height);
        Canvas.ClosePath;
        Canvas.Clip;
        if isopaque then
        begin
          FillRectangle(back, false);
          isopaque := false; //do not handle more
        end
        else
          Canvas.NewPath;
        Canvas.fNewPath := false;
      end;
      // draw background (if any)
      if isopaque then
        // don't handle BkMode, since global to the page, but only specific text
        // don't handle rotation here, since should not be used much
        FillRectangle(back, true);
      // draw text
      FillColor := Font.color;
      {$ifdef USE_UNISCRIBE}
      Canvas.RightToLeftText := (R.emrtext.fOptions and ETO_RTLREADING) <> 0;
      {$endif USE_UNISCRIBE}
      Canvas.BeginText;
      if Font.spec.angle <> 0 then
      begin
        a := Font.spec.angle * cPIdiv180;
        acos := cos(a);
        asin := sin(a);
        xs := 0;
        ys := 0;
        Canvas.SetTextMatrix(acos, asin, -asin, acos,
          Canvas.I2X(posi.X - Round(w * acos + h * asin)),
          Canvas.I2Y(posi.Y - Round(h * acos - w * asin)));
      end
      else if (WorldTransform.eM11 = WorldTransform.eM22) and
              (WorldTransform.eM12 = -WorldTransform.eM21) and
              not SameValue(ArcCos(WorldTransform.eM11), 0, 0.0001) then
      begin
        xs := 0;
        ys := 0;
        if SameValue(ArcCos(WorldTransform.eM11), 0, 0.0001) or      // 0 grad
           SameValue(ArcCos(WorldTransform.eM11), cPI, 0.0001) then  // 180 grad
          Canvas.SetTextMatrix(WorldTransform.eM11, WorldTransform.eM12,
            WorldTransform.eM21, WorldTransform.eM22,
            Canvas.S2X(posi.X * WorldTransform.eM11 +
              posi.Y * WorldTransform.eM21 + WorldTransform.eDx),
            Canvas.S2Y(posi.X * WorldTransform.eM12 +
              posi.Y * WorldTransform.eM22 + WorldTransform.eDy))
        else
          Canvas.SetTextMatrix(-WorldTransform.eM11, -WorldTransform.eM12, -
            WorldTransform.eM21, -WorldTransform.eM22,
            Canvas.S2X(posi.X * WorldTransform.eM11 +
              posi.Y * WorldTransform.eM21 + WorldTransform.eDx),
            Canvas.S2Y(posi.X * WorldTransform.eM12 +
              posi.Y * WorldTransform.eM22 + WorldTransform.eDy));
      end
      else
      begin
        acos := 0;
        asin := 0;
        if Canvas.fViewSize.cx > 0 then
          xs := posi.X - w   // zero point left
        else
          xs := posi.X + w;  // right
        if Canvas.fViewSize.cy > 0 then
          ys := posi.Y - h   // zero point beyond
        else
          ys := posi.Y + h;  // above
        Canvas.MoveTextPoint(Canvas.S2X(xs), Canvas.S2Y(ys));
      end;
      if (R.emrtext.fOptions and ETO_GLYPH_INDEX) <> 0 then
        Canvas.ShowGlyph(pointer(tmp), R.emrtext.nChars)
      else if po = tpExactTextCharacterPositining then
      begin
        cur := 0;
        tmp2[1] := #0;
        repeat
          tmp2[0] := tmp[cur];
          Canvas.ShowText(@tmp2, false);
          if cur = R.emrtext.nChars - 1 then
            break;
          xs := xs + dx^[cur];
          Canvas.EndText;
          Canvas.BeginText;
          Canvas.MoveTextPoint(Canvas.S2X(xs), Canvas.S2Y(ys));
          inc(cur);
        until false;
      end
      else
        Canvas.ShowText(pointer(tmp));
      Canvas.EndText;
      // handle underline or strike out styles (direct draw PDF lines on canvas)
      if Font.LogFont.lfUnderline <> 0 then
        DrawLine(posi, ss / (fScaleY * 8));
      if Font.LogFont.lfStrikeOut <> 0 then
        DrawLine(posi, -ss / (fScaleY * 4));
      // end any pending clipped TextRect() region
      if clipped then
      begin
        Canvas.GRestore;
        fFillColor := -1; // force set drawing color
      end;
      // restore previous text justification (after GRestore if clipped)
      case po of
        tpSetTextJustification:
          if nspace > 0 then
            Canvas.SetWordSpace(0);
        tpKerningFromAveragePosition:
          if hscale <> 100 then
            Canvas.SetHorizontalScaling(100); // reset horizontal scaling
      end;
      if not Canvas.fNewPath then
      begin
        if clipped then
          if not DC[nDC].ClipRgnNull then
          begin
            clip := GetClipRect;
            Canvas.GSave;
            Canvas.Rectangle(
              clip.Left, clip.Top, clip.Width, clip.Height);
            Canvas.Clip;
            Canvas.GRestore;
            Canvas.NewPath;
            Canvas.fNewPath := false;
          end;
      end
      else
        Canvas.fNewPath := false;
      if (Font.align and TA_UPDATECP) = TA_UPDATECP then
      begin
        position.X := posi.X + Trunc(ww);
        position.Y := posi.Y;
      end;
    end;
end;

{$endif USE_METAFILE}


end.
