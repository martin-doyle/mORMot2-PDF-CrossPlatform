/// HarfBuzz text shaper for the cross-platform PDF engine
// - implements IPdfTextShaper using the HarfBuzz library + FreeType2 backend
// - registers PdfTextShaper in initialization when libharfbuzz is available
// - optional: include in the project uses clause to enable RTL/Arabic shaping
// - runtime dependency: libharfbuzz.so.0 (Linux) / libharfbuzz.0.dylib (macOS)
unit mormot.pdf.harfbuzz;

{
  *****************************************************************************

    HarfBuzz Text Shaper for Unix/macOS
    - Minimal HarfBuzz API bindings (dynamic loading via dlopen)
    - THarfBuzzTextShaper implements IPdfTextShaper
    - Shapes RTL/Arabic/complex-script text using OpenType GSUB/GPOS rules
    - Advance widths returned in 1000/em units (design-unit scale)
    - initialization registers PdfTextShaper when libharfbuzz is present

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

{$ifndef MSWINDOWS}

uses
  dynlibs,
  mormot.core.base,
  mormot.pdf.types,
  mormot.pdf.freetype;

/// load the HarfBuzz shared library dynamically; returns false if not found
function LoadHarfBuzz: boolean;

{$endif MSWINDOWS}

implementation

{$ifndef MSWINDOWS}

// ---------------------------------------------------------------------------
// HarfBuzz minimal type bindings
// ---------------------------------------------------------------------------

type
  hb_font_t      = pointer;
  hb_buffer_t    = pointer;
  hb_direction_t = integer;
  hb_codepoint_t = cardinal;
  hb_position_t  = integer;
  hb_mask_t      = cardinal;

  /// HarfBuzz glyph info record (matches hb_glyph_info_t in harfbuzz/hb.h)
  hb_glyph_info_t = packed record
    codepoint: hb_codepoint_t; // shaped glyph ID (not a Unicode codepoint)
    mask:      hb_mask_t;
    cluster:   cardinal;       // index of corresponding source character
    var1_:     cardinal;       // HarfBuzz-internal
    var2_:     cardinal;       // HarfBuzz-internal
  end;
  // array pointer for indexed access to hb_buffer_get_glyph_infos result
  hb_glyph_info_array     = array[0..high(integer) div SizeOf(hb_glyph_info_t) - 1]
                              of hb_glyph_info_t;
  Phb_glyph_info_array    = ^hb_glyph_info_array;

  /// HarfBuzz glyph position record (matches hb_glyph_position_t in harfbuzz/hb.h)
  hb_glyph_position_t = packed record
    x_advance: hb_position_t; // horizontal advance in font units
    y_advance: hb_position_t;
    x_offset:  hb_position_t;
    y_offset:  hb_position_t;
    var_:      integer;        // HarfBuzz-internal
  end;
  // array pointer for indexed access to hb_buffer_get_glyph_positions result
  hb_glyph_position_array  = array[0..high(integer) div SizeOf(hb_glyph_position_t) - 1]
                               of hb_glyph_position_t;
  Phb_glyph_position_array = ^hb_glyph_position_array;

const
  /// hb_direction_t values from harfbuzz/hb-common.h
  HB_DIRECTION_LTR = 4;
  HB_DIRECTION_RTL = 5;

  /// FT_LOAD_NO_HINTING keeps the advances free of grid-fitting distortion
  // - do NOT use FT_LOAD_NO_SCALE here: HarfBuzz dropped its "return raw design
  //   units" behaviour for that flag, and now always multiplies the advance by
  //   a factor derived from the font scale, which yields 0 for every glyph
  HB_FT_LOAD_NO_HINTING = 2; // = FT_LOAD_NO_HINTING = 1 shl 1

// HarfBuzz function pointer types (cdecl, all from libharfbuzz)
type
  Thb_ft_font_create = function(
    face: FT_Face; destroy_: pointer): hb_font_t; cdecl;
  Thb_ft_font_set_load_flags = procedure(
    font: hb_font_t; load_flags: integer); cdecl;
  Thb_font_destroy = procedure(
    font: hb_font_t); cdecl;
  Thb_buffer_create = function: hb_buffer_t; cdecl;
  Thb_buffer_destroy = procedure(
    buffer: hb_buffer_t); cdecl;
  Thb_buffer_add_utf16 = procedure(
    buffer: hb_buffer_t; text: PWideChar; text_length: integer;
    item_offset: cardinal; item_length: integer); cdecl;
  Thb_buffer_set_direction = procedure(
    buffer: hb_buffer_t; direction: hb_direction_t); cdecl;
  Thb_buffer_guess_segment_properties = procedure(
    buffer: hb_buffer_t); cdecl;
  Thb_shape = procedure(
    font: hb_font_t; buffer: hb_buffer_t;
    features: pointer; num_features: cardinal); cdecl;
  Thb_buffer_get_glyph_infos = function(
    buffer: hb_buffer_t; out length: cardinal): Phb_glyph_info_array; cdecl;
  Thb_buffer_get_glyph_positions = function(
    buffer: hb_buffer_t; out length: cardinal): Phb_glyph_position_array; cdecl;

  /// holds loaded HarfBuzz library handle and all required function pointers
  THarfBuzzLib = record
    Handle:          TLibHandle;
    ft_font_create:  Thb_ft_font_create;
    // optional — available since HarfBuzz 0.9.5; used to set FT_LOAD_NO_HINTING
    ft_font_set_load_flags: Thb_ft_font_set_load_flags;
    font_destroy:    Thb_font_destroy;
    buffer_create:   Thb_buffer_create;
    buffer_destroy:  Thb_buffer_destroy;
    buffer_add_utf16: Thb_buffer_add_utf16;
    buffer_set_direction: Thb_buffer_set_direction;
    buffer_guess_segment_properties: Thb_buffer_guess_segment_properties;
    shape:           Thb_shape;
    buffer_get_glyph_infos: Thb_buffer_get_glyph_infos;
    buffer_get_glyph_positions: Thb_buffer_get_glyph_positions;
    Loaded:          boolean;
  end;

var
  HarfBuzz: THarfBuzzLib;

// ---------------------------------------------------------------------------
// LoadHarfBuzz
// ---------------------------------------------------------------------------

function LoadHarfBuzz: boolean;
const
  {$ifdef DARWIN}
  HBLIB = 'libharfbuzz.0.dylib';
  {$else}
  HBLIB = 'libharfbuzz.so.0';
  {$endif DARWIN}
begin
  result := HarfBuzz.Loaded;
  if result then
    exit;
  HarfBuzz.Handle := SafeLoadLibrary(HBLIB);
  if HarfBuzz.Handle = NilHandle then
  begin
    {$ifdef DARWIN}
    HarfBuzz.Handle := SafeLoadLibrary('libharfbuzz.dylib');
    if HarfBuzz.Handle = NilHandle then
      HarfBuzz.Handle := SafeLoadLibrary('/opt/homebrew/lib/libharfbuzz.0.dylib');
    if HarfBuzz.Handle = NilHandle then
      HarfBuzz.Handle := SafeLoadLibrary('/opt/homebrew/lib/libharfbuzz.dylib');
    if HarfBuzz.Handle = NilHandle then
      HarfBuzz.Handle := SafeLoadLibrary('/usr/local/lib/libharfbuzz.0.dylib');
    if HarfBuzz.Handle = NilHandle then
      HarfBuzz.Handle := SafeLoadLibrary('/usr/local/lib/libharfbuzz.dylib');
    {$else}
    HarfBuzz.Handle := SafeLoadLibrary('libharfbuzz.so');
    {$endif DARWIN}
  end;
  if HarfBuzz.Handle = NilHandle then
    exit;
  @HarfBuzz.ft_font_create   := GetProcedureAddress(HarfBuzz.Handle, 'hb_ft_font_create');
  @HarfBuzz.font_destroy     := GetProcedureAddress(HarfBuzz.Handle, 'hb_font_destroy');
  @HarfBuzz.buffer_create    := GetProcedureAddress(HarfBuzz.Handle, 'hb_buffer_create');
  @HarfBuzz.buffer_destroy   := GetProcedureAddress(HarfBuzz.Handle, 'hb_buffer_destroy');
  @HarfBuzz.buffer_add_utf16 := GetProcedureAddress(HarfBuzz.Handle, 'hb_buffer_add_utf16');
  @HarfBuzz.buffer_set_direction
    := GetProcedureAddress(HarfBuzz.Handle, 'hb_buffer_set_direction');
  @HarfBuzz.buffer_guess_segment_properties
    := GetProcedureAddress(HarfBuzz.Handle, 'hb_buffer_guess_segment_properties');
  @HarfBuzz.shape              := GetProcedureAddress(HarfBuzz.Handle, 'hb_shape');
  @HarfBuzz.buffer_get_glyph_infos
    := GetProcedureAddress(HarfBuzz.Handle, 'hb_buffer_get_glyph_infos');
  @HarfBuzz.buffer_get_glyph_positions
    := GetProcedureAddress(HarfBuzz.Handle, 'hb_buffer_get_glyph_positions');
  // optional symbol — do not abort if missing on older HarfBuzz builds
  @HarfBuzz.ft_font_set_load_flags
    := GetProcedureAddress(HarfBuzz.Handle, 'hb_ft_font_set_load_flags');
  if (@HarfBuzz.ft_font_create = nil) or
     (@HarfBuzz.font_destroy = nil) or
     (@HarfBuzz.buffer_create = nil) or
     (@HarfBuzz.buffer_destroy = nil) or
     (@HarfBuzz.buffer_add_utf16 = nil) or
     (@HarfBuzz.buffer_set_direction = nil) or
     (@HarfBuzz.buffer_guess_segment_properties = nil) or
     (@HarfBuzz.shape = nil) or
     (@HarfBuzz.buffer_get_glyph_infos = nil) or
     (@HarfBuzz.buffer_get_glyph_positions = nil) then
  begin
    FreeLibrary(HarfBuzz.Handle);
    HarfBuzz.Handle := NilHandle;
    exit;
  end;
  HarfBuzz.Loaded := true;
  result := true;
end;

// ---------------------------------------------------------------------------
// THarfBuzzTextShaper
// ---------------------------------------------------------------------------

function From26Dot6(AValue: hb_position_t): integer;
  {$ifdef HASINLINE} inline; {$endif}
begin // round half away from zero, the sign being kept for x_offset
  if AValue >= 0 then
    result := (AValue + 32) shr 6
  else
    result := -((32 - AValue) shr 6);
end;

type
  THarfBuzzTextShaper = class(TInterfacedObject, IPdfTextShaper)
  public
    function ShapeText(AText: PWideChar; ALen: integer;
      AFontHandle: TPdfPlatformFontHandle; AIsRTL: boolean;
      out AGlyphs: TWordDynArray; out AAdvances: TIntegerDynArray;
      out AOffsets: TIntegerDynArray; out AClusters: TIntegerDynArray): boolean;
  end;

function THarfBuzzTextShaper.ShapeText(AText: PWideChar; ALen: integer;
  AFontHandle: TPdfPlatformFontHandle; AIsRTL: boolean;
  out AGlyphs: TWordDynArray; out AAdvances: TIntegerDynArray;
  out AOffsets: TIntegerDynArray; out AClusters: TIntegerDynArray): boolean;
var
  ctx:       PPdfFTContext;
  font:      hb_font_t;
  buf:       hb_buffer_t;
  infos:     Phb_glyph_info_array;
  positions: Phb_glyph_position_array;
  count:     cardinal;
  i:         integer;

begin
  result    := false;
  AGlyphs   := nil;
  AAdvances := nil;
  AOffsets  := nil;
  AClusters := nil;
  if not HarfBuzz.Loaded or (AFontHandle = nil) or
     (AText = nil) or (ALen <= 0) then
    exit;
  ctx := PPdfFTContext(AFontHandle);
  if ctx^.Face = nil then
    exit;
  // hb_ft_font_create() copies the scale out of ft_face^.size^.metrics, so the
  // face must be sized first or every advance comes back as 0
  if not PdfFTSetEmSize1000(ctx) then
    exit;
  font := HarfBuzz.ft_font_create(ctx^.Face, nil);
  if font = nil then
    exit;
  if Assigned(HarfBuzz.ft_font_set_load_flags) then
    HarfBuzz.ft_font_set_load_flags(font, HB_FT_LOAD_NO_HINTING);
  buf := HarfBuzz.buffer_create;
  try
    HarfBuzz.buffer_add_utf16(buf, AText, ALen, 0, -1);
    // set direction first; guess_segment_properties will only fill what is missing
    if AIsRTL then
      HarfBuzz.buffer_set_direction(buf, HB_DIRECTION_RTL)
    else
      HarfBuzz.buffer_set_direction(buf, HB_DIRECTION_LTR);
    HarfBuzz.buffer_guess_segment_properties(buf);
    HarfBuzz.shape(font, buf, nil, 0);
    count     := 0;
    infos     := HarfBuzz.buffer_get_glyph_infos(buf, count);
    positions := HarfBuzz.buffer_get_glyph_positions(buf, count);
    if (count = 0) or (infos = nil) or (positions = nil) then
      exit;
    SetLength(AGlyphs,   count);
    SetLength(AAdvances, count);
    SetLength(AOffsets,  count);
    SetLength(AClusters, count);
    for i := 0 to integer(count) - 1 do
    begin
      AGlyphs[i]   := word(infos[i].codepoint);
      AClusters[i] := integer(infos[i].cluster);
      // one em = 1000 units, so the 26.6 values are PDF units shifted by 6 bits
      AAdvances[i] := From26Dot6(positions[i].x_advance);
      AOffsets[i]  := From26Dot6(positions[i].x_offset);
    end;
    result := true;
  finally
    HarfBuzz.buffer_destroy(buf);
    HarfBuzz.font_destroy(font);
  end;
end;

// ---------------------------------------------------------------------------
// Initialization / Finalization
// ---------------------------------------------------------------------------

initialization
  if LoadHarfBuzz then
    PdfTextShaper := THarfBuzzTextShaper.Create;

finalization
  PdfTextShaper := nil; // release interface ref before unloading library
  if HarfBuzz.Loaded then
  begin
    FreeLibrary(HarfBuzz.Handle);
    HarfBuzz.Handle := NilHandle;
    HarfBuzz.Loaded := false;
  end;

{$endif MSWINDOWS}

end.
