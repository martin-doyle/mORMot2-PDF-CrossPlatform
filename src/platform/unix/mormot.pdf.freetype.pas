/// FreeType2 backend for the cross-platform PDF engine
// - implements IPdfPlatformFont, IPdfSystemFonts and IPdfPlatformDC
//   using the FreeType2 library and filesystem font discovery
// - registers itself via RegisterPdfPlatform() in the initialization section
// - on Linux/macOS: include this unit (or via {$ifndef OSWINDOWS}) so that
//   the FreeType2 backend is registered before TPdfDocument.Create is called
unit mormot.pdf.freetype;

{
  *****************************************************************************

    FreeType2 Platform Backend for Unix/macOS
    - FreeType2 minimal API bindings (dynamic loading)
    - Font discovery: /usr/share/fonts, ~/.fonts, macOS /Library/Fonts
    - TPdfFreeTypeFontProvider  implements IPdfPlatformFont
    - TPdfFreeTypeSystemFonts   implements IPdfSystemFonts
    - TPdfFreeTypeDCProvider    implements IPdfPlatformDC
    - initialization registers all three via RegisterPdfPlatform()

  *****************************************************************************
}

interface

{$ifndef MSWINDOWS}

{$ifdef FPC}
  {$mode delphi}
{$endif FPC}

uses
  SysUtils,
  Classes,
  dynlibs,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.pdf.types;

// ---------------------------------------------------------------------------
// Minimal FreeType2 type bindings
// ---------------------------------------------------------------------------

type
  FT_Library  = pointer;
  FT_Face     = pointer;
  FT_Error    = integer;
  // FT_Long/FT_ULong follow the C 'long' type:
  //   - 64-bit on LP64 platforms (Linux x86_64, macOS/ARM64, macOS/x86_64)
  //   - 32-bit on LLP64 platforms (Windows 64-bit)
  {$ifdef CPU64}
  FT_Long    = Int64;
  FT_ULong   = QWord;
  FT_Pos     = Int64;     // typedef FT_Long FT_Pos
  FT_Fixed   = Int64;     // typedef FT_Long FT_Fixed
  FT_F26Dot6 = Int64;     // typedef FT_Long FT_F26Dot6
  {$else}
  FT_Long    = longint;
  FT_ULong   = cardinal;
  FT_Pos     = longint;
  FT_Fixed   = longint;
  FT_F26Dot6 = longint;
  {$endif CPU64}
  FT_Int      = integer;  // always 32-bit (C 'int')
  FT_UInt     = cardinal; // always 32-bit (C 'unsigned int')

  FT_BBox = record
    xMin, yMin, xMax, yMax: FT_Pos;
  end;

  // FT_FaceRec - we only access the fields we need via typed pointer
  PFT_FaceRec = ^FT_FaceRec;
  FT_FaceRec = record
    num_faces:        FT_Long;
    face_index:       FT_Long;
    face_flags:       FT_Long;
    style_flags:      FT_Long;
    num_glyphs:       FT_Long;
    family_name:      PAnsiChar;
    style_name:       PAnsiChar;
    num_fixed_sizes:  FT_Int;
    available_sizes:  pointer;
    num_charmaps:     FT_Int;
    charmaps:         pointer;
    generic_data:     pointer;
    generic_finalizer: pointer;
    bbox:             FT_BBox;
    units_per_EM:     Word;        // FT_UShort = 2 bytes
    ascender:         SmallInt;    // FT_Short  = 2 bytes
    descender:        SmallInt;    // negative value
    height:           SmallInt;
    max_advance_width:  SmallInt;
    max_advance_height: SmallInt;
    underline_position:  SmallInt;
    underline_thickness: SmallInt;
    glyph:           pointer;
    size:            pointer;
    charmap:         pointer;
  end;

  // FT_GlyphSlotRec - we only need metrics
  PFT_GlyphMetrics = ^FT_GlyphMetrics;
  FT_GlyphMetrics = record
    width:         FT_Pos;
    height:        FT_Pos;
    horiBearingX:  FT_Pos;
    horiBearingY:  FT_Pos;
    horiAdvance:   FT_Pos;
    vertBearingX:  FT_Pos;
    vertBearingY:  FT_Pos;
    vertAdvance:   FT_Pos;
  end;

  PFT_GlyphSlotRec = ^FT_GlyphSlotRec;
  FT_GlyphSlotRec = record
    library_:      FT_Library;
    face:          FT_Face;
    next:          pointer;
    reserved:      FT_UInt;
    generic_data:  pointer;
    generic_finalizer: pointer;
    metrics:       FT_GlyphMetrics;
    // ... more fields we don't need
  end;

// FreeType2 function pointer types
type
  TFT_Init_FreeType     = function(var alibrary: FT_Library): FT_Error; cdecl;
  TFT_Done_FreeType     = function(alibrary: FT_Library): FT_Error; cdecl;
  TFT_New_Face          = function(alibrary: FT_Library; filepathname: PAnsiChar;
                            face_index: FT_Long; var aface: FT_Face): FT_Error; cdecl;
  TFT_Done_Face         = function(face: FT_Face): FT_Error; cdecl;
  TFT_Set_Char_Size     = function(face: FT_Face; char_width, char_height: FT_F26Dot6;
                            horz_resolution, vert_resolution: FT_UInt): FT_Error; cdecl;
  TFT_Load_Char         = function(face: FT_Face; char_code: FT_ULong;
                            load_flags: FT_Int): FT_Error; cdecl;
  TFT_Load_Sfnt_Table   = function(face: FT_Face; tag: FT_ULong; offset: FT_Long;
                            buffer: pointer; var length: FT_ULong): FT_Error; cdecl;

const
  FT_LOAD_DEFAULT         = 0;
  FT_LOAD_NO_SCALE        = 1;  // = 1 shl 0; returns raw design units, no 26.6 encoding
  FT_FACE_FLAG_FIXED_WIDTH = 1 shl 2;

  /// standard DPI used when no real screen DPI is available
  PDF_SCREEN_DPI = 96;

// ---------------------------------------------------------------------------
// Font discovery helpers
// ---------------------------------------------------------------------------

type
  /// maps a font family name (UTF-8) to the best matching .ttf/.otf file path
  TPdfFontMap = record
    FamilyName: RawUtf8;    // e.g. 'DejaVu Sans'
    FilePath:   RawUtf8;    // absolute path to the font file
    Bold:       boolean;
    Italic:     boolean;
  end;
  TPdfFontMapDynArray = array of TPdfFontMap;

/// scan a directory tree for .ttf/.otf files and populate a font map
procedure ScanFontsDir(const ADir: string; var AMap: TPdfFontMapDynArray);

/// find the best matching font file for the given face name and style
// - returns empty string if not found
function FindFontFile(const AMap: TPdfFontMapDynArray;
  const AFaceName: RawUtf8; ABold, AItalic: boolean): RawUtf8;

// ---------------------------------------------------------------------------
// FreeType2 library loader (singleton)
// ---------------------------------------------------------------------------

type
  /// holds the loaded FreeType2 library handle and function pointers
  TFreeTypeLib = record
    Handle:           TLibHandle;
    FTLibrary:        FT_Library;
    Init:             TFT_Init_FreeType;
    Done:             TFT_Done_FreeType;
    NewFace:          TFT_New_Face;
    DoneFace:         TFT_Done_Face;
    SetCharSize:      TFT_Set_Char_Size;
    LoadChar:         TFT_Load_Char;
    LoadSfntTable:    TFT_Load_Sfnt_Table;
    Loaded:           boolean;
  end;

var
  /// global FreeType2 library instance
  FreeType: TFreeTypeLib;

/// load the FreeType2 shared library; returns false if not found
function LoadFreeType: boolean;

// ---------------------------------------------------------------------------
// Interface implementations
// ---------------------------------------------------------------------------

type
  /// FreeType2 implementation of IPdfPlatformFont
  // - each TPdfPlatformFontHandle is actually a pointer to an internal record
  //   that stores FT_Face + the path used to load it
  TPdfFreeTypeFontProvider = class(TInterfacedObject, IPdfPlatformFont)
  private
    fFontMap: TPdfFontMapDynArray;
  public
    constructor Create;
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

  /// FreeType2 implementation of IPdfSystemFonts
  TPdfFreeTypeSystemFonts = class(TInterfacedObject, IPdfSystemFonts)
  private
    fFontMap: TPdfFontMapDynArray;
    procedure BuildFontMap;
  public
    constructor Create;
    procedure EnumTrueTypeFonts(ADC: TPdfPlatformDC;
      var List: TRawUtf8DynArray);
  end;

  /// FreeType2 implementation of IPdfPlatformDC
  TPdfFreeTypeDCProvider = class(TInterfacedObject, IPdfPlatformDC)
  public
    function CreateDC: TPdfPlatformDC;
    procedure DeleteDC(ADC: TPdfPlatformDC);
    function GetScreenLogPixels(ADC: TPdfPlatformDC): integer;
  end;

{$endif MSWINDOWS}

// ---------------------------------------------------------------------------
// Internal FT context stored behind TPdfPlatformFontHandle
// Exported here so that mormot.pdf.harfbuzz can access the FT_Face pointer.
// ---------------------------------------------------------------------------

type
  /// internal record behind TPdfPlatformFontHandle on POSIX
  // - exported in the interface section so mormot.pdf.harfbuzz can cast
  //   TPdfPlatformFontHandle to PPdfFTContext to obtain the FT_Face
  TPdfFTContext = record
    Face:         FT_Face;   // FreeType2 face handle
    FilePath:     RawUtf8;   // absolute path (for diagnostics)
    UnitsPerEM:   integer;   // face^.units_per_EM
    Ascent:       integer;   // scaled ascender  (design units * 1000 / UPM)
    Descent:      integer;   // scaled descender (negative)
    Height:       integer;
    IsFixedWidth: boolean;
    FaceIndex:    integer;   // index of the face opened within a .ttc
    Sfnt:         RawByteString; // cached standalone sfnt built from a .ttc
    SfntChecked:  boolean;   // true once the file has been tested for 'ttcf'
  end;
  PPdfFTContext = ^TPdfFTContext;

/// extract one face of a TrueType Collection as a standalone sfnt font
// - a 'ttcf' container is not a valid /FontFile2 stream: it must be turned into
//   a single font, which is what CreateFontPackage(TTFCFP_FLAGS_TTC) does on
//   Windows and what this function does for the FreeType backend
// - returns '' when ATtc is not a collection, i.e. already a usable sfnt
function ExtractSfntFromTtc(const ATtc: RawByteString;
  AFaceIndex: integer): RawByteString;

/// size the FT_Face so that one em equals exactly 1000 units
// - hb_ft_font_create() derives the HarfBuzz scale from ft_face^.size^.metrics,
//   which stays zero on a face that was never sized: every shaped advance then
//   comes back as 0.  Sizing to 1000 units per em makes HarfBuzz return 26.6
//   values which are just the PDF-unit widths shifted by 6 bits
// - CreateFont() does not size the face because the other entry points all use
//   FT_LOAD_NO_SCALE or read design-unit fields, so they are unaffected by this
function PdfFTSetEmSize1000(ACtx: PPdfFTContext): boolean;

implementation

{$ifndef MSWINDOWS}

// ---------------------------------------------------------------------------
// Internal DC type (not exported — only used inside this unit)
// ---------------------------------------------------------------------------

type
  TPdfFTDC = record
    Current: PPdfFTContext;
  end;
  PPdfFTDC = ^TPdfFTDC;

// ---------------------------------------------------------------------------
// LoadFreeType
// ---------------------------------------------------------------------------

function LoadFreeType: boolean;
const
  {$ifdef DARWIN}
  FTLIB = 'libfreetype.6.dylib';
  {$else}
  FTLIB = 'libfreetype.so.6';
  {$endif DARWIN}
begin
  result := FreeType.Loaded;
  if result then
    exit;
  FreeType.Handle := SafeLoadLibrary(FTLIB);
  if FreeType.Handle = NilHandle then
  begin
    // Try without version suffix
    {$ifdef DARWIN}
    FreeType.Handle := SafeLoadLibrary('libfreetype.dylib');
    {$else}
    FreeType.Handle := SafeLoadLibrary('libfreetype.so');
    {$endif DARWIN}
  end;
  {$ifdef DARWIN}
  // On Apple Silicon (ARM64), Homebrew installs to /opt/homebrew which is not
  // in the default dyld search path - try explicit paths as last resort
  if FreeType.Handle = NilHandle then
    FreeType.Handle := SafeLoadLibrary('/opt/homebrew/lib/libfreetype.6.dylib');
  if FreeType.Handle = NilHandle then
    FreeType.Handle := SafeLoadLibrary('/opt/homebrew/lib/libfreetype.dylib');
  if FreeType.Handle = NilHandle then
    FreeType.Handle := SafeLoadLibrary('/usr/local/lib/libfreetype.6.dylib');
  if FreeType.Handle = NilHandle then
    FreeType.Handle := SafeLoadLibrary('/usr/local/lib/libfreetype.dylib');
  {$endif DARWIN}
  if FreeType.Handle = NilHandle then
    exit;
  @FreeType.Init          := GetProcedureAddress(FreeType.Handle, 'FT_Init_FreeType');
  @FreeType.Done          := GetProcedureAddress(FreeType.Handle, 'FT_Done_FreeType');
  @FreeType.NewFace       := GetProcedureAddress(FreeType.Handle, 'FT_New_Face');
  @FreeType.DoneFace      := GetProcedureAddress(FreeType.Handle, 'FT_Done_Face');
  @FreeType.SetCharSize   := GetProcedureAddress(FreeType.Handle, 'FT_Set_Char_Size');
  @FreeType.LoadChar      := GetProcedureAddress(FreeType.Handle, 'FT_Load_Char');
  @FreeType.LoadSfntTable := GetProcedureAddress(FreeType.Handle, 'FT_Load_Sfnt_Table');
  if (@FreeType.Init = nil) or
     (@FreeType.Done = nil) or
     (@FreeType.NewFace = nil) or
     (@FreeType.DoneFace = nil) or
     (@FreeType.SetCharSize = nil) or
     (@FreeType.LoadChar = nil) or
     (@FreeType.LoadSfntTable = nil) then
  begin
    FreeLibrary(FreeType.Handle);
    FreeType.Handle := NilHandle;
    exit;
  end;
  if FreeType.Init(FreeType.FTLibrary) <> 0 then
  begin
    FreeLibrary(FreeType.Handle);
    FreeType.Handle := NilHandle;
    exit;
  end;
  FreeType.Loaded := true;
  result := true;
end;

// ---------------------------------------------------------------------------
// Font discovery
// ---------------------------------------------------------------------------

procedure ScanFontsDir(const ADir: string; var AMap: TPdfFontMapDynArray);
var
  sr:    TSearchRec;
  ext:   string;
  entry: TPdfFontMap;
  face:  FT_Face;
  fname: RawUtf8;
  n:     integer;
begin
  if not DirectoryExists(ADir) then
    exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faAnyFile, sr) = 0 then
  try
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then
        continue;
      if sr.Attr and faDirectory <> 0 then
        ScanFontsDir(IncludeTrailingPathDelimiter(ADir) + sr.Name, AMap)
      else
      begin
        ext := LowerCase(ExtractFileExt(sr.Name));
        if (ext = '.ttf') or (ext = '.otf') or (ext = '.ttc') then
        begin
          if not FreeType.Loaded then
            continue;
          face := nil;
          if FreeType.NewFace(FreeType.FTLibrary,
             PAnsiChar(AnsiString(IncludeTrailingPathDelimiter(ADir) + sr.Name)),
             0, face) = 0 then
          begin
            fname := RawUtf8(PFT_FaceRec(face)^.family_name);
            n := Length(AMap);
            SetLength(AMap, n + 1);
            entry.FamilyName := fname;
            StringToUTF8(IncludeTrailingPathDelimiter(ADir) + sr.Name,
              entry.FilePath);
            if PFT_FaceRec(face)^.style_name <> nil then
            begin
              entry.Bold   := Pos('Bold',   string(PFT_FaceRec(face)^.style_name)) > 0;
              entry.Italic := Pos('Italic', string(PFT_FaceRec(face)^.style_name)) > 0;
            end
            else
            begin
              entry.Bold   := false;
              entry.Italic := false;
            end;
            AMap[n] := entry;
            FreeType.DoneFace(face);
          end;
        end;
      end;
    until FindNext(sr) <> 0;
  finally
    FindClose(sr);
  end;
end;

function FindFontFile(const AMap: TPdfFontMapDynArray;
  const AFaceName: RawUtf8; ABold, AItalic: boolean): RawUtf8;
var
  i:     integer;
  best:  integer;
  score: integer;
  s:     integer;
  lname: RawUtf8;
begin
  result := '';
  lname  := LowerCase(AFaceName);
  best   := -1;
  score  := -1;
  for i := 0 to high(AMap) do
  begin
    if SameTextU(AMap[i].FamilyName, AFaceName) then
    begin
      s := 0;
      if AMap[i].Bold   = ABold   then inc(s, 2);
      if AMap[i].Italic = AItalic then inc(s, 2);
      if s > score then
      begin
        score := s;
        best  := i;
      end;
    end;
  end;
  if best >= 0 then
    result := AMap[best].FilePath;
end;

// ---------------------------------------------------------------------------
// Helper: scale design units to "GDI units" (design units * 1000 / UPM)
// ---------------------------------------------------------------------------

function MulDiv(nNumber, nNumerator, nDenominator: integer): integer;
  {$ifdef HASINLINE} inline; {$endif}
begin
  if nDenominator = 0 then
    result := -1
  else
    result := (int64(nNumber) * nNumerator + nDenominator div 2) div nDenominator;
end;

function ScaleDesignUnit(AValue, AUnitsPerEM: integer): integer;
begin
  if AUnitsPerEM <= 0 then
    result := AValue
  else
    result := MulDiv(AValue, 1000, AUnitsPerEM);
end;

const
  TTCF_MAGIC = $66637474; // 'ttcf' read as a little-endian cardinal

function ExtractSfntFromTtc(const ATtc: RawByteString;
  AFaceIndex: integer): RawByteString;
var
  base, dir, src, dst: PAnsiChar;
  numFonts, numTables, i, faceOfs, ofs, len, total, hd: PtrUInt;
  sum: cardinal;
begin
  result := '';
  base := pointer(ATtc);
  if (length(ATtc) < 16) or
     (PCardinal(base)^ <> TTCF_MAGIC) then
    exit; // not a collection: the caller may embed the data as it is
  numFonts := bswap32(PCardinal(base + 8)^);
  if (AFaceIndex < 0) or
     (PtrUInt(AFaceIndex) >= numFonts) or
     (PtrUInt(length(ATtc)) < 12 + numFonts * 4) then
    exit;
  faceOfs := bswap32(PCardinal(base + 12 + PtrUInt(AFaceIndex) * 4)^);
  if faceOfs + 12 > PtrUInt(length(ATtc)) then
    exit;
  numTables := bswap16(PWord(base + faceOfs + 4)^);
  if (numTables = 0) or
     (faceOfs + 12 + numTables * 16 > PtrUInt(length(ATtc))) then
    exit;
  // measure the standalone font: offset table, directory, then 4-byte aligned
  // table data - the table bytes are copied verbatim, so their per-table
  // checksums stay valid
  total := 12 + numTables * 16;
  dir := base + faceOfs + 12;
  for i := 0 to numTables - 1 do
  begin
    ofs := bswap32(PCardinal(dir + i * 16 + 8)^);
    len := bswap32(PCardinal(dir + i * 16 + 12)^);
    if ofs + len > PtrUInt(length(ATtc)) then
      exit; // truncated or malformed collection
    inc(total, (len + 3) and not PtrUInt(3));
  end;
  FastSetRawByteString(result, nil, total);
  dst := pointer(result);
  MoveFast(base[faceOfs], dst^, 12 + numTables * 16); // header + directory
  src := dst + 12 + numTables * 16;
  hd := 0;
  for i := 0 to numTables - 1 do
  begin
    ofs := bswap32(PCardinal(dir + i * 16 + 8)^);
    len := bswap32(PCardinal(dir + i * 16 + 12)^);
    if PCardinal(dir + i * 16)^ = $64616568 then // 'head' little-endian
      hd := PtrUInt(src - dst);
    PCardinal(dst + 12 + i * 16 + 8)^ := bswap32(cardinal(src - dst));
    MoveFast(base[ofs], src^, len);
    FillCharFast(src[len], ((len + 3) and not PtrUInt(3)) - len, 0);
    inc(src, (len + 3) and not PtrUInt(3));
  end;
  if hd <> 0 then
  begin
    // head.checkSumAdjustment covers the whole file, so it must be recomputed
    PCardinal(dst + hd + 8)^ := 0;
    sum := 0;
    for i := 0 to (total shr 2) - 1 do
      inc(sum, bswap32(PCardinalArray(dst)^[i]));
    PCardinal(dst + hd + 8)^ := bswap32(cardinal($B1B0AFBA) - sum);
  end;
end;

function PdfFTSetEmSize1000(ACtx: PPdfFTContext): boolean;
begin
  result := FreeType.Loaded and
            (ACtx <> nil) and
            (ACtx^.Face <> nil) and
            // 1000 in 26.6 fixed point, at 72 dpi -> ppem = 1000 = one em
            (FreeType.SetCharSize(ACtx^.Face, 0, 1000 shl 6, 72, 72) = 0);
end;

// ---------------------------------------------------------------------------
// TPdfFreeTypeFontProvider
// ---------------------------------------------------------------------------

constructor TPdfFreeTypeFontProvider.Create;
begin
  inherited Create;
  // Build a font map so CreateFont can find files
  if FreeType.Loaded then
  begin
    {$ifdef DARWIN}
    ScanFontsDir('/Library/Fonts', fFontMap);
    ScanFontsDir('/System/Library/Fonts', fFontMap);
    ScanFontsDir(GetEnvironmentVariable('HOME') + '/Library/Fonts', fFontMap);
    {$else}
    ScanFontsDir('/usr/share/fonts', fFontMap);
    ScanFontsDir('/usr/local/share/fonts', fFontMap);
    ScanFontsDir(GetEnvironmentVariable('HOME') + '/.fonts', fFontMap);
    ScanFontsDir(GetEnvironmentVariable('HOME') + '/.local/share/fonts', fFontMap);
    {$endif DARWIN}
  end;
end;

function TPdfFreeTypeFontProvider.CreateFont(
  const ALogFont: TPdfLogFont): TPdfPlatformFontHandle;
var
  filePath: RawUtf8;
  face:     FT_Face;
  ctx:      PPdfFTContext;
  faceRec:  PFT_FaceRec;
  bold, italic: boolean;
begin
  result := nil;
  if not FreeType.Loaded then
    exit;
  bold   := ALogFont.Weight >= 600;
  italic := ALogFont.Italic <> 0;
  filePath := FindFontFile(fFontMap, ALogFont.FaceName, bold, italic);
  if filePath = '' then
  begin
    // Fallback: try DejaVu Sans
    filePath := FindFontFile(fFontMap, 'DejaVu Sans', bold, italic);
    if filePath = '' then
      filePath := FindFontFile(fFontMap, 'DejaVuSans', bold, italic);
    if filePath = '' then
      exit; // no font found at all
  end;
  face := nil;
  if FreeType.NewFace(FreeType.FTLibrary, PAnsiChar(AnsiString(filePath)),
     0, face) <> 0 then
    exit;
  // GetCharABCWidths will use FT_LOAD_NO_SCALE to get raw design units,
  // so SetCharSize is not needed here anymore
  faceRec := PFT_FaceRec(face);
  New(ctx);
  ctx^.Face         := face;
  ctx^.FilePath     := filePath;
  ctx^.UnitsPerEM   := faceRec^.units_per_EM;
  ctx^.Ascent       := ScaleDesignUnit(faceRec^.ascender,    ctx^.UnitsPerEM);
  ctx^.Descent      := ScaleDesignUnit(faceRec^.descender,   ctx^.UnitsPerEM);
  ctx^.Height       := ScaleDesignUnit(faceRec^.height,      ctx^.UnitsPerEM);
  ctx^.IsFixedWidth := (faceRec^.face_flags and FT_FACE_FLAG_FIXED_WIDTH) <> 0;
  ctx^.FaceIndex    := 0; // FT_New_Face() above always opens the first face
  result := TPdfPlatformFontHandle(ctx);
end;

procedure TPdfFreeTypeFontProvider.DeleteFont(AFont: TPdfPlatformFontHandle);
var
  ctx: PPdfFTContext;
begin
  if AFont = nil then
    exit;
  ctx := PPdfFTContext(AFont);
  if ctx^.Face <> nil then
    FreeType.DoneFace(ctx^.Face);
  Dispose(ctx);
end;

function TPdfFreeTypeFontProvider.SelectFont(ADC: TPdfPlatformDC;
  AFont: TPdfPlatformFontHandle): TPdfPlatformFontHandle;
var
  dc: PPdfFTDC;
begin
  dc := PPdfFTDC(ADC);
  result := TPdfPlatformFontHandle(dc^.Current);
  dc^.Current := PPdfFTContext(AFont);
end;

function TPdfFreeTypeFontProvider.GetTextMetrics(ADC: TPdfPlatformDC;
  out AMetrics: TPdfTextMetrics): boolean;
var
  dc:  PPdfFTDC;
  ctx: PPdfFTContext;
  fr:  PFT_FaceRec;
begin
  result := false;
  dc := PPdfFTDC(ADC);
  if (dc = nil) or (dc^.Current = nil) then
    exit;
  ctx := dc^.Current;
  fr  := PFT_FaceRec(ctx^.Face);
  FillChar(AMetrics, SizeOf(AMetrics), 0);
  AMetrics.tmAscent  := ctx^.Ascent;
  AMetrics.tmDescent := -ctx^.Descent; // make positive like Windows
  AMetrics.tmHeight  := AMetrics.tmAscent + AMetrics.tmDescent;
  AMetrics.tmInternalLeading := 0;
  AMetrics.tmExternalLeading := ScaleDesignUnit(fr^.height, ctx^.UnitsPerEM)
                                - AMetrics.tmHeight;
  // Average char width ≈ em-width / 2 (rough estimate)
  AMetrics.tmAveCharWidth := ctx^.Ascent div 2;
  AMetrics.tmMaxCharWidth := ctx^.Ascent;
  AMetrics.tmWeight       := 400; // FW_NORMAL; caller sets bold separately
  AMetrics.tmFirstChar    := WideChar(32);
  AMetrics.tmLastChar     := WideChar(255);
  AMetrics.tmDefaultChar  := WideChar(Ord('?'));
  AMetrics.tmBreakChar    := WideChar(Ord(' '));
  AMetrics.tmItalic       := 0;
  AMetrics.tmCharSet      := 0; // ANSI_CHARSET
  if ctx^.IsFixedWidth then
    AMetrics.tmPitchAndFamily := 0  // fixed pitch: bit 0 = 0
  else
    AMetrics.tmPitchAndFamily := 1; // variable pitch: bit 0 = 1
  result := true;
end;

function TPdfFreeTypeFontProvider.GetOutlineMetrics(ADC: TPdfPlatformDC;
  out AMetrics: TPdfOutlineMetrics): boolean;
var
  dc:  PPdfFTDC;
  ctx: PPdfFTContext;
  fr:  PFT_FaceRec;
begin
  result := false;
  dc := PPdfFTDC(ADC);
  if (dc = nil) or (dc^.Current = nil) then
    exit;
  ctx := dc^.Current;
  fr  := PFT_FaceRec(ctx^.Face);
  FillChar(AMetrics, SizeOf(AMetrics), 0);
  AMetrics.otmSize     := SizeOf(AMetrics);
  AMetrics.otmAscent   := ctx^.Ascent;
  AMetrics.otmDescent  := ctx^.Descent; // negative
  AMetrics.otmLineGap  := AMetrics.otmAscent - AMetrics.otmDescent;
  AMetrics.otmItalicAngle := 0;
  AMetrics.otmrcFontBox.Left   := ScaleDesignUnit(fr^.bbox.xMin, ctx^.UnitsPerEM);
  AMetrics.otmrcFontBox.Bottom := ScaleDesignUnit(fr^.bbox.yMin, ctx^.UnitsPerEM);
  AMetrics.otmrcFontBox.Right  := ScaleDesignUnit(fr^.bbox.xMax, ctx^.UnitsPerEM);
  AMetrics.otmrcFontBox.Top    := ScaleDesignUnit(fr^.bbox.yMax, ctx^.UnitsPerEM);
  AMetrics.otmMacAscent  := AMetrics.otmAscent;
  AMetrics.otmMacDescent := AMetrics.otmDescent;
  AMetrics.otmEMSquare   := ctx^.UnitsPerEM;
  result := true;
end;

function TPdfFreeTypeFontProvider.GetCharABCWidths(ADC: TPdfPlatformDC;
  FirstChar, LastChar: cardinal;
  out AWidths: TPdfCharABCArray): boolean;
var
  dc:    PPdfFTDC;
  ctx:   PPdfFTContext;
  n, i:  integer;
  slot:  PFT_GlyphSlotRec;
  adv:   FT_Pos;
  lsb:   FT_Pos;   // left side bearing (A width)
  rsb:   FT_Pos;   // right side bearing (C width)
  code:  cardinal;
  a, c:  integer;
  total: integer;
begin
  result := false;
  dc := PPdfFTDC(ADC);
  if (dc = nil) or (dc^.Current = nil) then
    exit;
  ctx := dc^.Current;
  n := integer(LastChar) - integer(FirstChar) + 1;
  if n <= 0 then
    exit;
  SetLength(AWidths, n);
  for i := 0 to n - 1 do
  begin
    FillChar(AWidths[i], SizeOf(AWidths[i]), 0);
    code := FirstChar + cardinal(i);
    // the caller asks for 32..255, i.e. WinAnsi byte values, because that is
    // what the Windows counterpart GetCharABCWidthsA takes - an ANSI call that
    // maps through the DC codepage. FT_Load_Char expects a Unicode code point,
    // so the byte has to be translated first: without this, 128..159 are read
    // as the unassigned C1 controls, miss the CMAP and silently return the
    // .notdef advance. That is what put the bullet (#$95 -> U+2022) and the
    // em dash (#$97 -> U+2014) into /Widths with a wrong value (U-1b).
    if code <= high(WinAnsiConvert.AnsiToWide) then
      code := WinAnsiConvert.AnsiToWide[code];
    // Use FT_LOAD_NO_SCALE to get raw design units (like faceRec^.ascender),
    // then apply uniform ScaleDesignUnit(value, UPM) across all metrics.
    if FreeType.LoadChar(ctx^.Face, code, FT_LOAD_NO_SCALE) = 0 then
    begin
      slot := PFT_GlyphSlotRec(PFT_FaceRec(ctx^.Face)^.glyph);
      // FreeType metrics in design units:
      // - horiBearingX = left side bearing (A)
      // - horiAdvance = total advance width (A + B + C)
      // - rsb = advance - (lsb + width)
      lsb := slot^.metrics.horiBearingX;
      adv := slot^.metrics.horiAdvance;
      // Calculate right side bearing
      // rsb = horiAdvance - horiBearingX - glyph_width
      rsb := adv - lsb - slot^.metrics.width;
      // the engine uses abcA + abcB + abcC as the advance width, and that sum
      // ends up in /Widths. Scaling the three parts on their own rounds three
      // times, so the sum could miss the scaled advance by up to 1.5 units -
      // enough to break ISO 14289-1 7.21.5, which allows 1 (U-1a). Scale the
      // advance once, and give abcB whatever the two bearings leave over, so
      // the sum is exact by construction.
      total := ScaleDesignUnit(adv, ctx^.UnitsPerEM);
      a := ScaleDesignUnit(lsb, ctx^.UnitsPerEM);
      c := ScaleDesignUnit(rsb, ctx^.UnitsPerEM);
      AWidths[i].abcA := a;
      AWidths[i].abcB := cardinal(total - a - c);
      AWidths[i].abcC := c;
    end;
  end;
  result := true;
end;

function TPdfFreeTypeFontProvider.GetFontData(ADC: TPdfPlatformDC;
  ATableTag: cardinal; AOffset: cardinal; ABuffer: pointer;
  ABufferSize: cardinal): cardinal;
var
  dc:  PPdfFTDC;
  ctx: PPdfFTContext;
  len: FT_ULong;
  err: FT_Error;
begin
  result := FontDataError;
  dc := PPdfFTDC(ADC);
  if (dc = nil) or (dc^.Current = nil) then
    exit;
  ctx := dc^.Current;
  if ATableTag = 0 then
  begin
    // "whole font file": for a .ttc this would return the entire collection,
    // which is not a valid /FontFile2 - hand out just the face we loaded
    if not ctx^.SfntChecked then
    begin
      ctx^.SfntChecked := true; // a plain .ttf is returned by FreeType as it is
      if ctx^.FilePath <> '' then
        ctx^.Sfnt := ExtractSfntFromTtc(
          StringFromFile(Utf8ToString(ctx^.FilePath)), ctx^.FaceIndex);
    end;
    if ctx^.Sfnt <> '' then
    begin
      result := length(ctx^.Sfnt);
      if ABuffer <> nil then
        if ABufferSize < result then
          result := FontDataError
        else
          MoveFast(pointer(ctx^.Sfnt)^, ABuffer^, result);
      exit;
    end;
  end;
  len := ABufferSize;
  // The PDF engine forms table tags as PCardinal(name)^ — a 4-char ASCII
  // name read as a little-endian DWORD (e.g. 'cmap' → $70616D63).
  // FreeType uses big-endian tags (FT_MAKE_TAG: 'cmap' → $636D6170).
  // SwapEndian converts between the two; SwapEndian(0)=0 so tag=0
  // ("return whole font file") is passed through correctly.
  err := FreeType.LoadSfntTable(ctx^.Face, SwapEndian(ATableTag), AOffset,
    ABuffer, len);
  if err <> 0 then
    exit;
  result := len;
end;

function TPdfFreeTypeFontProvider.FontDataError: cardinal;
begin
  result := $FFFFFFFF;
end;

// ---------------------------------------------------------------------------
// TPdfFreeTypeSystemFonts
// ---------------------------------------------------------------------------

constructor TPdfFreeTypeSystemFonts.Create;
begin
  inherited Create;
  BuildFontMap;
end;

procedure TPdfFreeTypeSystemFonts.BuildFontMap;
begin
  {$ifdef DARWIN}
  ScanFontsDir('/Library/Fonts', fFontMap);
  ScanFontsDir('/System/Library/Fonts', fFontMap);
  ScanFontsDir(GetEnvironmentVariable('HOME') + '/Library/Fonts', fFontMap);
  {$else}
  ScanFontsDir('/usr/share/fonts', fFontMap);
  ScanFontsDir('/usr/local/share/fonts', fFontMap);
  ScanFontsDir(GetEnvironmentVariable('HOME') + '/.fonts', fFontMap);
  ScanFontsDir(GetEnvironmentVariable('HOME') + '/.local/share/fonts', fFontMap);
  {$endif DARWIN}
end;

procedure TPdfFreeTypeSystemFonts.EnumTrueTypeFonts(ADC: TPdfPlatformDC;
  var List: TRawUtf8DynArray);
var
  i: integer;
begin
  { Enumerate all fonts in fFontMap, but only add family names once (duplicates
    are filtered by AddRawUtf8 with true,true). The font variants (Bold, Italic)
    are found via CreateFont -> FindFontFile which matches against Bold/Italic flags. }
  for i := 0 to high(fFontMap) do
    AddRawUtf8(List, fFontMap[i].FamilyName, true, true);
end;

// ---------------------------------------------------------------------------
// TPdfFreeTypeDCProvider
// ---------------------------------------------------------------------------

function TPdfFreeTypeDCProvider.CreateDC: TPdfPlatformDC;
var
  dc: PPdfFTDC;
begin
  New(dc);
  dc^.Current := nil;
  result := TPdfPlatformDC(dc);
end;

procedure TPdfFreeTypeDCProvider.DeleteDC(ADC: TPdfPlatformDC);
begin
  if ADC <> nil then
    Dispose(PPdfFTDC(ADC));
end;

function TPdfFreeTypeDCProvider.GetScreenLogPixels(ADC: TPdfPlatformDC): integer;
begin
  result := PDF_SCREEN_DPI;
end;

// ---------------------------------------------------------------------------
// Initialization
// ---------------------------------------------------------------------------

initialization
  if LoadFreeType then
    RegisterPdfPlatform(
      TPdfFreeTypeFontProvider.Create,
      TPdfFreeTypeSystemFonts.Create,
      TPdfFreeTypeDCProvider.Create);

finalization
  if FreeType.Loaded then
  begin
    FreeType.Done(FreeType.FTLibrary);
    FreeLibrary(FreeType.Handle);
    FreeType.Loaded := false;
  end;

{$endif MSWINDOWS}

end.
