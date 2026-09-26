/// FPImage bitmap adapter for the cross-platform PDF engine
// - implements IPdfBitmapAdapter using FCL's FPImage (included in FPC)
// - supports PNG and JPEG loading and pixel access
// - used by TPdfImage on non-Windows platforms instead of GDI BitBlt/GetDIBits
unit mormot.pdf.fpimage;

{
  *****************************************************************************

    FPImage Bitmap Adapter (Unix/macOS)
    - IPdfBitmapAdapter interface definition
    - TPdfFPImageAdapter: load PNG/JPEG, enumerate pixels, convert to raw bytes
    - Helper: ConvertFPImageToPdfStream() — produces the raw RGB byte stream
      expected by TPdfImage/TPdfRawImage

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

{$ifndef MSWINDOWS}

uses
  SysUtils,
  Classes,
  FPImage,
  FPReadPNG,
  FPReadJPEG,
  mormot.core.base,
  mormot.core.unicode;

type
  /// pixel format for cross-platform bitmap data exchange
  TPdfPixelFormat = (
    pfRGB24,    // 3 bytes per pixel: R, G, B
    pfRGBA32,   // 4 bytes per pixel: R, G, B, A
    pfGray8     // 1 byte per pixel: gray
  );

  /// interface for cross-platform bitmap operations used by TPdfImage
  IPdfBitmapAdapter = interface
    ['{D4E5F6A7-B8C9-0123-DEFA-456789012345}']
    /// load an image from a stream (auto-detect PNG or JPEG)
    function LoadFromStream(AStream: TStream): boolean;
    /// load an image from a file
    function LoadFromFile(const AFileName: string): boolean;
    /// width of the loaded image in pixels
    function GetWidth: integer;
    /// height of the loaded image in pixels
    function GetHeight: integer;
    /// return raw pixel data as a byte stream
    // - returns RGB24 bytes row by row, top-to-bottom
    function GetRawRGB: RawByteString;
    /// return a JPEG-compressed byte stream of the image
    // - AQuality: 1..100, JPEG compression quality
    function GetJpegBytes(AQuality: integer = 75): RawByteString;
  end;

  /// FPImage implementation of IPdfBitmapAdapter
  TPdfFPImageAdapter = class(TInterfacedObject, IPdfBitmapAdapter)
  private
    fImage: TFPMemoryImage;
    function DetectAndLoad(AStream: TStream): boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function LoadFromStream(AStream: TStream): boolean;
    function LoadFromFile(const AFileName: string): boolean;
    function GetWidth: integer;
    function GetHeight: integer;
    function GetRawRGB: RawByteString;
    function GetJpegBytes(AQuality: integer = 75): RawByteString;
  end;

/// create a new FPImage-based bitmap adapter
function CreatePdfBitmapAdapter: IPdfBitmapAdapter;

{$endif MSWINDOWS}

implementation

{$ifndef MSWINDOWS}

uses
  FPWriteJPEG;

// ---------------------------------------------------------------------------
// TPdfFPImageAdapter
// ---------------------------------------------------------------------------

constructor TPdfFPImageAdapter.Create;
begin
  inherited Create;
  fImage := TFPMemoryImage.Create(0, 0);
end;

destructor TPdfFPImageAdapter.Destroy;
begin
  fImage.Free;
  inherited;
end;

function TPdfFPImageAdapter.DetectAndLoad(AStream: TStream): boolean;
var
  sig:     array[0..3] of byte;
  savedPos: int64;
  reader:   TFPCustomImageReader;
begin
  result   := false;
  savedPos := AStream.Position;
  if AStream.Read(sig, 4) < 4 then
    exit;
  AStream.Position := savedPos;
  // PNG signature: 89 50 4E 47
  if (sig[0] = $89) and (sig[1] = $50) and (sig[2] = $4E) and (sig[3] = $47) then
    reader := TFPReaderPNG.Create
  // JPEG signature: FF D8 FF
  else if (sig[0] = $FF) and (sig[1] = $D8) and (sig[2] = $FF) then
    reader := TFPReaderJPEG.Create
  else
    exit; // unsupported format
  try
    fImage.LoadFromStream(AStream, reader);
    result := true;
  except
    // swallow load errors — caller should check result
  end;
  reader.Free;
end;

function TPdfFPImageAdapter.LoadFromStream(AStream: TStream): boolean;
begin
  result := DetectAndLoad(AStream);
end;

function TPdfFPImageAdapter.LoadFromFile(const AFileName: string): boolean;
var
  fs: TFileStream;
begin
  result := false;
  if not FileExists(AFileName) then
    exit;
  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    result := LoadFromStream(fs);
  finally
    fs.Free;
  end;
end;

function TPdfFPImageAdapter.GetWidth: integer;
begin
  result := fImage.Width;
end;

function TPdfFPImageAdapter.GetHeight: integer;
begin
  result := fImage.Height;
end;

function TPdfFPImageAdapter.GetRawRGB: RawByteString;
var
  w, h, x, y: integer;
  p:           PByte;
  col:         TFPColor;
begin
  result := '';
  w := fImage.Width;
  h := fImage.Height;
  if (w = 0) or (h = 0) then
    exit;
  SetLength(result, w * h * 3);
  p := pointer(result);
  for y := 0 to h - 1 do
    for x := 0 to w - 1 do
    begin
      col  := fImage.Colors[x, y];
      p^   := col.red shr 8;   inc(p);  // R (16-bit → 8-bit)
      p^   := col.green shr 8; inc(p);  // G
      p^   := col.blue shr 8;  inc(p);  // B
    end;
end;

function TPdfFPImageAdapter.GetJpegBytes(AQuality: integer): RawByteString;
var
  ms:     TMemoryStream;
  writer: TFPWriterJPEG;
begin
  result := '';
  ms := TMemoryStream.Create;
  try
    writer := TFPWriterJPEG.Create;
    try
      writer.CompressionQuality := AQuality;
      fImage.SaveToStream(ms, writer);
    finally
      writer.Free;
    end;
    SetLength(result, ms.Size);
    if ms.Size > 0 then
    begin
      ms.Position := 0;
      ms.Read(pointer(result)^, ms.Size);
    end;
  finally
    ms.Free;
  end;
end;

// ---------------------------------------------------------------------------
// Factory
// ---------------------------------------------------------------------------

function CreatePdfBitmapAdapter: IPdfBitmapAdapter;
begin
  result := TPdfFPImageAdapter.Create;
end;

{$endif MSWINDOWS}

end.
