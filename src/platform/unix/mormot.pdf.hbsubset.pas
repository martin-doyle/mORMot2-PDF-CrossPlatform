/// HarfBuzz Font Subsetter for the Cross-Platform PDF Engine
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.pdf.hbsubset;

{
  *****************************************************************************

   HarfBuzz Font Subsetter for POSIX
   - Minimal hb-subset API bindings (dynamic loading)
   - THarfBuzzFontSubsetter implements IPdfFontSubsetter
   - Glyph IDs are retained, so the PDF engine needs no glyph remapping
   - initialization registers PdfFontSubsetter when libharfbuzz-subset and
     libharfbuzz (HarfBuzz 2.9+) load

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

{$ifndef OSWINDOWS}

uses
  mormot.core.base,
  mormot.core.os,
  mormot.pdf.types;

const
  /// hb_subset_flags_t values from harfbuzz/hb-subset.h (HarfBuzz 10.2.0)
  HB_SUBSET_FLAGS_NO_HINTING     = $00000001;
  HB_SUBSET_FLAGS_RETAIN_GIDS    = $00000002;
  HB_SUBSET_FLAGS_NOTDEF_OUTLINE = $00000040;

var
  /// flags passed to hb_subset_input_set_flags()
  // - RETAIN_GIDS is mandatory: the PDF engine writes the original glyph IDs
  // - NOTDEF_OUTLINE keeps the .notdef box, so a missing glyph stays visible
  // - NO_HINTING drops the TrueType bytecode, which PDF viewers hardly use
  HbSubsetFlags: cardinal = HB_SUBSET_FLAGS_RETAIN_GIDS or
    HB_SUBSET_FLAGS_NOTDEF_OUTLINE or HB_SUBSET_FLAGS_NO_HINTING;
  /// drop the GSUB/GPOS/GDEF tables from the subset
  // - a PDF viewer never shapes text, and the glyph set of the request already
  // holds every shaped glyph that was drawn
  HbSubsetDropLayoutTables: boolean = true;

/// load libharfbuzz-subset and libharfbuzz dynamically
// - returns false if a library or one of the required symbols is missing,
// e.g. with a HarfBuzz older than 2.9 which lacks hb_subset_or_fail()
function LoadHarfBuzzSubset: boolean;

{$endif OSWINDOWS}

implementation

{$ifndef OSWINDOWS}

// ---------------------------------------------------------------------------
// hb-subset minimal type bindings
// ---------------------------------------------------------------------------

type
  hb_blob_t         = pointer;
  hb_face_t         = pointer;
  hb_set_t          = pointer;
  hb_subset_input_t = pointer;

const
  /// hb_memory_mode_t from harfbuzz/hb-blob.h
  HB_MEMORY_MODE_READONLY = 1;
  /// hb_subset_sets_t from harfbuzz/hb-subset.h
  HB_SUBSET_SETS_DROP_TABLE_TAG = 3;
  /// HB_TAG() values of the OpenType layout tables
  HB_TAG_GSUB = $47535542;
  HB_TAG_GPOS = $47504F53;
  HB_TAG_GDEF = $47444546;

// hb-subset function pointer types (cdecl)
type
  Thb_blob_create = function(data: PAnsiChar; length: cardinal;
    mode: integer; user_data, destroy_: pointer): hb_blob_t; cdecl;
  Thb_blob_destroy = procedure(blob: hb_blob_t); cdecl;
  Thb_blob_get_data = function(blob: hb_blob_t;
    out length: cardinal): PAnsiChar; cdecl;
  Thb_face_create = function(blob: hb_blob_t; index: cardinal): hb_face_t; cdecl;
  Thb_face_destroy = procedure(face: hb_face_t); cdecl;
  Thb_face_reference_blob = function(face: hb_face_t): hb_blob_t; cdecl;
  Thb_set_add = procedure(set_: hb_set_t; codepoint: cardinal); cdecl;
  Thb_subset_input_create_or_fail = function: hb_subset_input_t; cdecl;
  Thb_subset_input_destroy = procedure(input: hb_subset_input_t); cdecl;
  Thb_subset_input_get_set = function(input: hb_subset_input_t): hb_set_t; cdecl;
  Thb_subset_input_set = function(input: hb_subset_input_t;
    set_type: integer): hb_set_t; cdecl;
  Thb_subset_input_set_flags = procedure(input: hb_subset_input_t;
    value: cardinal); cdecl;
  Thb_subset_or_fail = function(source: hb_face_t;
    input: hb_subset_input_t): hb_face_t; cdecl;

  /// holds both library handles and all required function pointers
  // - hb_blob_*, hb_face_* and hb_set_* live in libharfbuzz, not in
  // libharfbuzz-subset, so both libraries are opened explicitly
  THarfBuzzSubsetLib = record
    Handle: TLibHandle;
    SubsetHandle: TLibHandle;
    blob_create: Thb_blob_create;
    blob_destroy: Thb_blob_destroy;
    blob_get_data: Thb_blob_get_data;
    face_create: Thb_face_create;
    face_destroy: Thb_face_destroy;
    face_reference_blob: Thb_face_reference_blob;
    set_add: Thb_set_add;
    input_create_or_fail: Thb_subset_input_create_or_fail;
    input_destroy: Thb_subset_input_destroy;
    input_unicode_set: Thb_subset_input_get_set;
    input_glyph_set: Thb_subset_input_get_set;
    input_set: Thb_subset_input_set;
    input_set_flags: Thb_subset_input_set_flags;
    subset_or_fail: Thb_subset_or_fail;
    Loaded: boolean;
  end;

var
  HbSubset: THarfBuzzSubsetLib;

// ---------------------------------------------------------------------------
// LoadHarfBuzzSubset
// ---------------------------------------------------------------------------

function LoadFirst(const Names: array of string): TLibHandle;
var
  i: PtrInt;
begin
  for i := 0 to high(Names) do
  begin
    result := LibraryOpen(Names[i]);
    if result <> 0 then
      exit;
  end;
  result := 0;
end;

procedure UnloadHarfBuzzSubset;
begin
  if HbSubset.SubsetHandle <> 0 then
    LibraryClose(HbSubset.SubsetHandle);
  if HbSubset.Handle <> 0 then
    LibraryClose(HbSubset.Handle);
  HbSubset := Default(THarfBuzzSubsetLib);
end;

function LoadHarfBuzzSubset: boolean;
begin
  result := HbSubset.Loaded;
  if result then
    exit;
  {$ifdef OSDARWIN}
  HbSubset.Handle := LoadFirst(['libharfbuzz.0.dylib',
    '/opt/homebrew/lib/libharfbuzz.0.dylib',
    '/usr/local/lib/libharfbuzz.0.dylib']);
  HbSubset.SubsetHandle := LoadFirst(['libharfbuzz-subset.0.dylib',
    '/opt/homebrew/lib/libharfbuzz-subset.0.dylib',
    '/usr/local/lib/libharfbuzz-subset.0.dylib']);
  {$else}
  HbSubset.Handle := LoadFirst(['libharfbuzz.so.0', 'libharfbuzz.so']);
  HbSubset.SubsetHandle := LoadFirst(['libharfbuzz-subset.so.0',
    'libharfbuzz-subset.so']);
  {$endif OSDARWIN}
  if (HbSubset.Handle = 0) or
     (HbSubset.SubsetHandle = 0) then
  begin
    UnloadHarfBuzzSubset;
    exit;
  end;
  with HbSubset do
  begin
    @blob_create := LibraryResolve(Handle, 'hb_blob_create');
    @blob_destroy := LibraryResolve(Handle, 'hb_blob_destroy');
    @blob_get_data := LibraryResolve(Handle, 'hb_blob_get_data');
    @face_create := LibraryResolve(Handle, 'hb_face_create');
    @face_destroy := LibraryResolve(Handle, 'hb_face_destroy');
    @face_reference_blob := LibraryResolve(Handle, 'hb_face_reference_blob');
    @set_add := LibraryResolve(Handle, 'hb_set_add');
    @input_create_or_fail :=
      LibraryResolve(SubsetHandle, 'hb_subset_input_create_or_fail');
    @input_destroy := LibraryResolve(SubsetHandle, 'hb_subset_input_destroy');
    @input_unicode_set :=
      LibraryResolve(SubsetHandle, 'hb_subset_input_unicode_set');
    @input_glyph_set := LibraryResolve(SubsetHandle, 'hb_subset_input_glyph_set');
    @input_set := LibraryResolve(SubsetHandle, 'hb_subset_input_set');
    @input_set_flags := LibraryResolve(SubsetHandle, 'hb_subset_input_set_flags');
    @subset_or_fail := LibraryResolve(SubsetHandle, 'hb_subset_or_fail');
    // no partial mode: HarfBuzz < 2.9 has only the deprecated subset API
    if (@blob_create = nil) or
       (@blob_destroy = nil) or
       (@blob_get_data = nil) or
       (@face_create = nil) or
       (@face_destroy = nil) or
       (@face_reference_blob = nil) or
       (@set_add = nil) or
       (@input_create_or_fail = nil) or
       (@input_destroy = nil) or
       (@input_unicode_set = nil) or
       (@input_glyph_set = nil) or
       (@input_set = nil) or
       (@input_set_flags = nil) or
       (@subset_or_fail = nil) then
    begin
      UnloadHarfBuzzSubset;
      exit;
    end;
  end;
  HbSubset.Loaded := true;
  result := true;
end;

// ---------------------------------------------------------------------------
// THarfBuzzFontSubsetter
// ---------------------------------------------------------------------------

type
  THarfBuzzFontSubsetter = class(TInterfacedObject, IPdfFontSubsetter)
  public
    function Subset(const AFace: RawByteString;
      const ARequest: TPdfFontSubsetRequest;
      out ASubset: RawByteString): boolean;
  end;

// both outline flavours are embeddable: glyf goes to /FontFile2, CFF to
// /FontFile3 with /Subtype /OpenType - the caller tells them apart by the
// sfnt signature of the subset, which hb-subset preserves
function IsEmbeddableOutlines(const AFace: RawByteString): boolean;
begin
  result := (length(AFace) > 12) and
            ((copy(AFace, 1, 4) = #0#1#0#0) or
             (copy(AFace, 1, 4) = 'true') or
             (copy(AFace, 1, 4) = 'OTTO'));
end;

function THarfBuzzFontSubsetter.Subset(const AFace: RawByteString;
  const ARequest: TPdfFontSubsetRequest; out ASubset: RawByteString): boolean;
var
  blob, subblob: hb_blob_t;
  face, subface: hb_face_t;
  input: hb_subset_input_t;
  s: hb_set_t;
  data: PAnsiChar;
  len: cardinal;
  i: PtrInt;
begin
  result := false;
  ASubset := '';
  if not HbSubset.Loaded or
     not IsEmbeddableOutlines(AFace) then
    exit;
  with HbSubset do
  begin
    // READONLY: AFace outlives the blob, which is destroyed below
    blob := blob_create(pointer(AFace), length(AFace), HB_MEMORY_MODE_READONLY,
      nil, nil);
    face := face_create(blob, 0); // a .ttc face was already extracted
    input := input_create_or_fail;
    subface := nil;
    try
      if input = nil then
        exit;
      s := input_unicode_set(input);
      for i := 0 to high(ARequest.Unicodes) do
        set_add(s, ARequest.Unicodes[i]);
      s := input_glyph_set(input);
      set_add(s, 0); // .notdef is always part of a TrueType font
      for i := 0 to high(ARequest.Glyphs) do
        set_add(s, ARequest.Glyphs[i]);
      input_set_flags(input, HbSubsetFlags or HB_SUBSET_FLAGS_RETAIN_GIDS);
      if HbSubsetDropLayoutTables then
      begin
        s := input_set(input, HB_SUBSET_SETS_DROP_TABLE_TAG);
        set_add(s, HB_TAG_GSUB);
        set_add(s, HB_TAG_GPOS);
        set_add(s, HB_TAG_GDEF);
      end;
      subface := subset_or_fail(face, input);
      if subface = nil then
        exit;
      subblob := face_reference_blob(subface);
      try
        len := 0;
        data := blob_get_data(subblob, len);
        // HarfBuzz < 10.0 returns an sfnt without tables instead of nil for a
        // face without glyphs: no table means failure, so the face goes whole
        if (data = nil) or
           (len < 12) or
           (((ord(data[4]) shl 8) or ord(data[5])) = 0) then
          exit;
        FastSetRawByteString(ASubset, data, len);
        result := true;
      finally
        blob_destroy(subblob);
      end;
    finally
      if subface <> nil then
        face_destroy(subface);
      if input <> nil then
        input_destroy(input);
      face_destroy(face);
      blob_destroy(blob);
    end;
  end;
end;

// ---------------------------------------------------------------------------
// Initialization / Finalization
// ---------------------------------------------------------------------------

initialization
  if LoadHarfBuzzSubset then
    PdfFontSubsetter := THarfBuzzFontSubsetter.Create;

finalization
  PdfFontSubsetter := nil; // release interface ref before unloading library
  UnloadHarfBuzzSubset;

{$endif OSWINDOWS}

end.
