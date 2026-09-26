/// Windows GDI backend for the cross-platform PDF engine
// - implements IPdfPlatformFont, IPdfSystemFonts and IPdfPlatformDC
//   using Windows GDI API calls
// - registers itself via RegisterPdfPlatform() in the initialization section
// - include this unit in the uses clause (or via {$ifdef OSWINDOWS}) so that
//   the GDI backend is registered before TPdfDocument.Create is called
unit mormot.pdf.gdi;

{
  *****************************************************************************

    Windows GDI Platform Backend
    - TPdfGdiFontProvider   implements IPdfPlatformFont
    - TPdfGdiSystemFonts    implements IPdfSystemFonts
    - TPdfGdiDCProvider     implements IPdfPlatformDC
    - initialization registers all three via RegisterPdfPlatform()

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

{$ifdef MSWINDOWS}

uses
  Windows,
  SysUtils,
  mormot.core.base,
  mormot.core.unicode,
  mormot.pdf.types;

type
  /// Windows GDI implementation of IPdfPlatformFont
  TPdfGdiFontProvider = class(TInterfacedObject, IPdfPlatformFont)
  public
    function CreateFont(const ALogFont: TPdfLogFont): TPdfPlatformFontHandle;
    procedure DeleteFont(AFont: TPdfPlatformFontHandle);
    function SelectFont(ADC: TPdfPlatformDC;
      AFont: TPdfPlatformFontHandle): TPdfPlatformFontHandle;
    function GetTextMetrics(ADC: TPdfPlatformDC;
      out AMetrics: TPdfTextMetrics): boolean;
    function GetOutlineMetrics(ADC: TPdfPlatformDC;
      out AMetrics: TPdfOutlineMetrics): boolean;
    function GetCharABCWidths(ADC: TPdfPlatformDC;
      FirstChar, LastChar: cardinal;
      out AWidths: TPdfCharABCArray): boolean;
    function GetFontData(ADC: TPdfPlatformDC; ATableTag: cardinal;
      AOffset: cardinal; ABuffer: pointer; ABufferSize: cardinal): cardinal;
    function FontDataError: cardinal;
  end;

  /// Windows GDI implementation of IPdfSystemFonts
  TPdfGdiSystemFonts = class(TInterfacedObject, IPdfSystemFonts)
  public
    procedure EnumTrueTypeFonts(ADC: TPdfPlatformDC;
      var List: TRawUtf8DynArray);
  end;

  /// Windows GDI implementation of IPdfPlatformDC
  TPdfGdiDCProvider = class(TInterfacedObject, IPdfPlatformDC)
  public
    function CreateDC: TPdfPlatformDC;
    procedure DeleteDC(ADC: TPdfPlatformDC);
    function GetScreenLogPixels(ADC: TPdfPlatformDC): integer;
  end;

{$endif MSWINDOWS}

implementation

{$ifdef MSWINDOWS}

{ TPdfGdiFontProvider }

function TPdfGdiFontProvider.CreateFont(
  const ALogFont: TPdfLogFont): TPdfPlatformFontHandle;
var
  lf: TLogFontW;
begin
  FillChar(lf, SizeOf(lf), 0);
  lf.lfHeight    := ALogFont.Height;
  lf.lfWeight    := ALogFont.Weight;
  lf.lfItalic    := ALogFont.Italic;
  lf.lfCharSet   := ALogFont.CharSet;
  lf.lfPitchAndFamily := ALogFont.PitchAndFamily;
  lf.lfOutPrecision   := OUT_TT_ONLY_PRECIS;
  lf.lfClipPrecision  := CLIP_DEFAULT_PRECIS;
  lf.lfQuality        := DEFAULT_QUALITY;
  if ALogFont.FaceName <> '' then
    Move(ALogFont.FaceName[1], lf.lfFaceName[0],
      MinPtrInt(Length(ALogFont.FaceName), LF_FACESIZE - 1) * SizeOf(WideChar));
  result := TPdfPlatformFontHandle(CreateFontIndirectW(lf));
end;

procedure TPdfGdiFontProvider.DeleteFont(AFont: TPdfPlatformFontHandle);
begin
  if AFont <> nil then
    DeleteObject(HGDIOBJ(AFont));
end;

function TPdfGdiFontProvider.SelectFont(ADC: TPdfPlatformDC;
  AFont: TPdfPlatformFontHandle): TPdfPlatformFontHandle;
begin
  result := TPdfPlatformFontHandle(SelectObject(HDC(ADC), HGDIOBJ(AFont)));
end;

function TPdfGdiFontProvider.GetTextMetrics(ADC: TPdfPlatformDC;
  out AMetrics: TPdfTextMetrics): boolean;
var
  tm: TTextMetric;
begin
  result := Windows.GetTextMetrics(HDC(ADC), tm);
  if result then
  begin
    AMetrics.tmHeight          := tm.tmHeight;
    AMetrics.tmAscent          := tm.tmAscent;
    AMetrics.tmDescent         := tm.tmDescent;
    AMetrics.tmInternalLeading := tm.tmInternalLeading;
    AMetrics.tmExternalLeading := tm.tmExternalLeading;
    AMetrics.tmAveCharWidth    := tm.tmAveCharWidth;
    AMetrics.tmMaxCharWidth    := tm.tmMaxCharWidth;
    AMetrics.tmWeight          := tm.tmWeight;
    AMetrics.tmOverhang        := tm.tmOverhang;
    AMetrics.tmFirstChar       := WideChar(tm.tmFirstChar);
    AMetrics.tmLastChar        := WideChar(tm.tmLastChar);
    AMetrics.tmDefaultChar     := WideChar(tm.tmDefaultChar);
    AMetrics.tmBreakChar       := WideChar(tm.tmBreakChar);
    AMetrics.tmItalic          := tm.tmItalic;
    AMetrics.tmCharSet         := tm.tmCharSet;
    AMetrics.tmPitchAndFamily  := tm.tmPitchAndFamily;
  end;
end;

function TPdfGdiFontProvider.GetOutlineMetrics(ADC: TPdfPlatformDC;
  out AMetrics: TPdfOutlineMetrics): boolean;
var
  otm: TOutlineTextmetric;
begin
  FillChar(otm, SizeOf(otm), 0);
  otm.otmSize := SizeOf(otm);
  result := Windows.GetOutlineTextMetrics(HDC(ADC), SizeOf(otm), @otm) <> 0;
  if result then
  begin
    AMetrics.otmSize              := otm.otmSize;
    AMetrics.otmAscent            := otm.otmAscent;
    AMetrics.otmDescent           := otm.otmDescent;
    AMetrics.otmLineGap           := otm.otmLineGap;
    AMetrics.otmItalicAngle       := otm.otmItalicAngle;
    AMetrics.otmrcFontBox.Left    := otm.otmrcFontBox.Left;
    AMetrics.otmrcFontBox.Top     := otm.otmrcFontBox.Top;
    AMetrics.otmrcFontBox.Right   := otm.otmrcFontBox.Right;
    AMetrics.otmrcFontBox.Bottom  := otm.otmrcFontBox.Bottom;
    AMetrics.otmMacAscent         := otm.otmMacAscent;
    AMetrics.otmMacDescent        := otm.otmMacDescent;
    AMetrics.otmMacLineGap        := otm.otmMacLineGap;
    AMetrics.otmEMSquare          := otm.otmEMSquare;
    AMetrics.otmCapEmHeight       := otm.otmsCapEmHeight;
    AMetrics.otmXHeight           := otm.otmsXHeight;
    AMetrics.otmStrikeoutPosition := otm.otmsStrikeoutPosition;
    AMetrics.otmStrikeoutSize     := otm.otmsStrikeoutSize;
    AMetrics.otmUnderscorePosition := otm.otmsUnderscorePosition;
    AMetrics.otmUnderscoreSize    := otm.otmsUnderscoreSize;
  end;
end;

function TPdfGdiFontProvider.GetCharABCWidths(ADC: TPdfPlatformDC;
  FirstChar, LastChar: cardinal;
  out AWidths: TPdfCharABCArray): boolean;
var
  n: integer;
  W: array of TABC;
  i: integer;
begin
  n := integer(LastChar) - integer(FirstChar) + 1;
  if n <= 0 then
  begin
    result := false;
    exit;
  end;
  SetLength(W, n);
  result := GetCharABCWidthsA(HDC(ADC), FirstChar, LastChar, W[0]);
  if result then
  begin
    SetLength(AWidths, n);
    for i := 0 to n - 1 do
    begin
      AWidths[i].abcA := W[i].abcA;
      AWidths[i].abcB := W[i].abcB;
      AWidths[i].abcC := W[i].abcC;
    end;
  end;
end;

function TPdfGdiFontProvider.GetFontData(ADC: TPdfPlatformDC;
  ATableTag: cardinal; AOffset: cardinal; ABuffer: pointer;
  ABufferSize: cardinal): cardinal;
begin
  result := Windows.GetFontData(HDC(ADC), ATableTag, AOffset,
    ABuffer, ABufferSize);
end;

function TPdfGdiFontProvider.FontDataError: cardinal;
begin
  result := GDI_ERROR;
end;

{ TPdfGdiSystemFonts }

// internal callback used by EnumFontFamiliesExW
// FPC requires ENUMLOGFONTEXW / NEWTEXTMETRICEXW; lParam is Int64 on Win64
type
  PRawUtf8DynArrayLocal = ^TRawUtf8DynArray;

function EnumFontsProcW(var LogFont: ENUMLOGFONTEXW;
  var TextMetric: NEWTEXTMETRICEXW;
  FontType: integer; lParam: LPARAM): integer; stdcall;
var
  u: RawUtf8;
begin
  with LogFont.elfLogFont do
    if ((FontType = DEVICE_FONTTYPE) or
        (FontType = TRUETYPE_FONTTYPE)) and
       (lfFaceName[0] <> '@') then
    begin
      RawUnicodeToUtf8(@lfFaceName[0], StrLenW(@lfFaceName[0]), u);
      AddRawUtf8(PRawUtf8DynArrayLocal(PtrUInt(lParam))^, u, true, true);
    end;
  result := 1; // continue enumeration
end;

procedure TPdfGdiSystemFonts.EnumTrueTypeFonts(ADC: TPdfPlatformDC;
  var List: TRawUtf8DynArray);
var
  LFont: TLogFontW;
begin
  FillChar(LFont, SizeOf(LFont), 0);
  LFont.lfCharSet := DEFAULT_CHARSET; // enumerate ALL fonts
  EnumFontFamiliesExW(HDC(ADC), LFont, @EnumFontsProcW,
    LPARAM(@List), 0);
end;

{ TPdfGdiDCProvider }

function TPdfGdiDCProvider.CreateDC: TPdfPlatformDC;
begin
  result := TPdfPlatformDC(Windows.CreateCompatibleDC(0));
end;

procedure TPdfGdiDCProvider.DeleteDC(ADC: TPdfPlatformDC);
begin
  if ADC <> nil then
    Windows.DeleteDC(HDC(ADC));
end;

function TPdfGdiDCProvider.GetScreenLogPixels(ADC: TPdfPlatformDC): integer;
begin
  result := GetDeviceCaps(HDC(ADC), LOGPIXELSY);
end;

initialization
  RegisterPdfPlatform(
    TPdfGdiFontProvider.Create,
    TPdfGdiSystemFonts.Create,
    TPdfGdiDCProvider.Create);

{$endif MSWINDOWS}

end.
