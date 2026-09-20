/// Cross-Platform PDF engine - shared types, records and platform interfaces
// - this unit is a part of the mORMot2 PDF cross-platform portierung
// - defines platform-neutral records mirroring Windows GDI structures
// - defines interfaces for font metrics, font creation and DC management
// - concrete implementations are in mormot.pdf.gdi (Windows) and
//   mormot.pdf.freetype (Unix/macOS)
unit mormot.pdf.types;

{
  *****************************************************************************

    Cross-Platform PDF Platform Abstraction Layer
    - Platform-neutral record types (mirrors of Windows GDI structures)
    - IPdfPlatformFont interface (font creation, metrics, glyph data)
    - IPdfSystemFonts interface (font enumeration)
    - IPdfPlatformDC interface (device context abstraction)
    - IPdfFontSubsetter interface (optional font subsetting)
    - Global registration via RegisterPdfPlatform()

  *****************************************************************************
}

interface

uses
  SysUtils,
  mormot.core.base,
  mormot.core.unicode;

{$ifdef FPC}
  {$mode delphi}
{$endif FPC}

const
  /// PDF standard Type 1 font names — supported by all PDF readers without embedding
  // - use with TPdfDocument.StandardFontsReplace := true
  PDF_FONT_STD_SANS  = 'Helvetica';
  PDF_FONT_STD_SERIF = 'Times';
  PDF_FONT_STD_MONO  = 'Courier';

type
  /// PDF file format version written to the %PDF-1.x header
  // - pdf13 (default) through pdf17 (ISO 32000-1)
  TPdfFileFormat = (pdf13, pdf14, pdf15, pdf16, pdf17);

  /// structure role for Tagged PDF (ISO 32000-1 §14) accessibility tags
  // - psrDocument=0; psrH1..psrH6=1..6; psrP=7; psrSpan=8
  // - psrFigure=9 for image/graphic elements
  // - psrTable=10, psrTR=11, psrTH=12, psrTD=13 for table structure
  // - psrL=14, psrLI=15, psrLbl=16, psrLBody=17 for list structure
  // - TPdfStructRole(Level) for heading Level 1..6 gives psrH1..psrH6
  // - new roles are appended at the end: TPdfStructRole(Level) and the
  // dckBeginTR logic in mormot.ui.report depend on the existing ordinals
  TPdfStructRole = (psrDocument, psrH1, psrH2, psrH3, psrH4, psrH5, psrH6,
                    psrP, psrSpan,
                    psrFigure,
                    psrTable, psrTR, psrTH, psrTD,
                    psrL, psrLI, psrLbl, psrLBody);

  /// platform-neutral font handle
  // - on Windows: HGDIOBJ (GDI font handle)
  // - on Unix/macOS: FT_Face pointer (FreeType2 face)
  TPdfPlatformFontHandle = type pointer;

  /// platform-neutral device context handle
  // - on Windows: HDC
  // - on Unix/macOS: always nil (no real DC needed)
  TPdfPlatformDC = type pointer;

  /// mirrors Windows TTextMetric for cross-platform font metrics
  TPdfTextMetrics = record
    tmHeight: integer;
    tmAscent: integer;
    tmDescent: integer;
    tmInternalLeading: integer;
    tmExternalLeading: integer;
    tmAveCharWidth: integer;
    tmMaxCharWidth: integer;
    tmWeight: integer;
    tmOverhang: integer;
    tmFirstChar: WideChar;
    tmLastChar: WideChar;
    tmDefaultChar: WideChar;
    tmBreakChar: WideChar;
    tmItalic: byte;
    tmCharSet: byte;
    tmPitchAndFamily: byte;
  end;

  /// mirrors Windows TOutlineTextmetric for cross-platform outline metrics
  TPdfOutlineMetrics = record
    otmSize: cardinal;
    otmAscent: integer;
    otmDescent: integer;
    otmLineGap: integer;
    otmItalicAngle: integer;
    otmrcFontBox: record
      Left: integer;
      Top: integer;
      Right: integer;
      Bottom: integer;
    end;
    otmMacAscent: integer;
    otmMacDescent: integer;
    otmMacLineGap: cardinal;
    otmEMSquare: cardinal;
    otmCapEmHeight: integer;
    otmXHeight: integer;
    otmStrikeoutPosition: integer;
    otmStrikeoutSize: cardinal;
    otmUnderscorePosition: integer;
    otmUnderscoreSize: cardinal;
  end;

  /// mirrors Windows TABC for glyph advance width components
  // - abcA: spacing before the glyph (can be negative)
  // - abcB: width of the glyph body
  // - abcC: spacing after the glyph (can be negative)
  TPdfCharABC = record
    abcA: integer;
    abcB: cardinal;
    abcC: integer;
  end;

  /// array of TPdfCharABC, indexed by character code
  TPdfCharABCArray = array of TPdfCharABC;

  /// mirrors Windows TLogFontW for cross-platform font creation parameters
  TPdfLogFont = record
    FaceName: SynUnicode;
    Height: integer;
    Weight: integer;
    Italic: byte;
    CharSet: byte;
    PitchAndFamily: byte;
  end;

  /// callback type for font enumeration
  // - called once per available TrueType font
  // - FontName: the UTF-8 encoded font family name
  // - return true to continue enumeration, false to stop
  TPdfFontEnumCallback = procedure(const FontName: RawUtf8;
    var List: TRawUtf8DynArray);

  /// interface for all font-related platform operations
  // - implemented by TPdfGdiFontProvider (Windows) and
  //   TPdfFreeTypeFontProvider (Unix/macOS)
  IPdfPlatformFont = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    /// create a font handle from logical font parameters
    // - returns nil/0 on failure
    function CreateFont(const ALogFont: TPdfLogFont): TPdfPlatformFontHandle;
    /// release a font handle previously created by CreateFont
    procedure DeleteFont(AFont: TPdfPlatformFontHandle);
    /// select a font into the DC (required before calling metric functions)
    // - returns the previously selected font handle (for restore)
    function SelectFont(ADC: TPdfPlatformDC;
      AFont: TPdfPlatformFontHandle): TPdfPlatformFontHandle;
    /// retrieve text metrics for the currently selected font
    function GetTextMetrics(ADC: TPdfPlatformDC;
      out AMetrics: TPdfTextMetrics): boolean;
    /// retrieve outline text metrics for the currently selected font
    function GetOutlineMetrics(ADC: TPdfPlatformDC;
      out AMetrics: TPdfOutlineMetrics): boolean;
    /// retrieve ABC widths for characters FirstChar..LastChar
    // - AWidths must have capacity for (LastChar - FirstChar + 1) entries
    function GetCharABCWidths(ADC: TPdfPlatformDC;
      FirstChar, LastChar: cardinal;
      out AWidths: TPdfCharABCArray): boolean;
    /// read raw TrueType/OpenType table data (equivalent to Windows GetFontData)
    // - ATableName is a 4-byte tag like 'cmap', 'glyf', 'head', etc.
    // - returns number of bytes read, or FontDataError on failure
    function GetFontData(ADC: TPdfPlatformDC; ATableTag: cardinal;
      AOffset: cardinal; ABuffer: pointer; ABufferSize: cardinal): cardinal;
    /// returns the sentinel value that GetFontData returns on error
    // - on Windows: GDI_ERROR = $FFFFFFFF
    // - on other platforms: $FFFFFFFF (same convention)
    function FontDataError: cardinal;
  end;

  /// interface for system font enumeration
  IPdfSystemFonts = interface
    ['{B2C3D4E5-F6A7-8901-BCDE-F12345678901}']
    /// enumerate all available TrueType fonts on the system
    // - fills List with UTF-8 encoded font family names
    procedure EnumTrueTypeFonts(ADC: TPdfPlatformDC;
      var List: TRawUtf8DynArray);
  end;

  /// interface for Unicode text shaping (RTL, Arabic, Indic scripts)
  // - implemented by THarfBuzzTextShaper (Unix/macOS) when libharfbuzz is present
  // - PdfTextShaper is nil by default; set by mormot.pdf.harfbuzz initialization
  IPdfTextShaper = interface
    ['{D4E5F6A7-B8C9-0123-DEF0-234567890123}']
    /// shape a run of Unicode text using OpenType GSUB/GPOS rules
    // - returns false if shaping fails (caller falls back to NoUniScribe path)
    // - AGlyphs: shaped glyph IDs in visual order
    // - AAdvances: x_advance per glyph in 1000/em units (GPOS-adjusted)
    // - AOffsets: x_offset per glyph in 1000/em units (GPOS kerning displacement)
    // - AClusters: maps each output glyph to the source character index
    function ShapeText(AText: PWideChar; ALen: integer;
      AFontHandle: TPdfPlatformFontHandle; AIsRTL: boolean;
      out AGlyphs: TWordDynArray; out AAdvances: TIntegerDynArray;
      out AOffsets: TIntegerDynArray; out AClusters: TIntegerDynArray): boolean;
  end;

  /// input of IPdfFontSubsetter.Subset: what a subset must keep
  // - Unicodes: code points whose cmap entries must survive - a simple
  // TrueType font with /WinAnsiEncoding reaches its glyphs through the cmap
  // - Glyphs: glyph IDs that must survive - an Identity-H font addresses
  // glyphs directly, and shaped glyphs have no code point of their own
  TPdfFontSubsetRequest = record
    Unicodes: TIntegerDynArray;
    Glyphs: TIntegerDynArray;
  end;

  /// interface for TrueType font subsetting
  // - implemented by THarfBuzzFontSubsetter (Unix/macOS) in mormot.pdf.hbsubset
  // - PdfFontSubsetter is nil when no subsetter is registered: the whole face
  // is embedded then (Windows uses CreateFontPackage instead)
  IPdfFontSubsetter = interface
    ['{E5F6A7B8-C9D0-1234-EF01-345678901234}']
    /// return a subset of AFace keeping the glyphs listed in ARequest
    // - glyph IDs are retained, so content streams, /W arrays and /ToUnicode
    // CMaps built against AFace stay valid for ASubset
    // - returns false if the face cannot be subset (e.g. CFF outlines, invalid
    // data, library unavailable): the caller then embeds AFace unchanged
    function Subset(const AFace: RawByteString;
      const ARequest: TPdfFontSubsetRequest;
      out ASubset: RawByteString): boolean;
  end;

  /// interface for device context management
  IPdfPlatformDC = interface
    ['{C3D4E5F6-A7B8-9012-CDEF-123456789012}']
    /// create a compatible device context
    // - on Windows: CreateCompatibleDC(0)
    // - on Unix/macOS: returns a non-nil dummy pointer to signal success
    function CreateDC: TPdfPlatformDC;
    /// release a device context previously created by CreateDC
    procedure DeleteDC(ADC: TPdfPlatformDC);
    /// return the screen resolution in logical pixels per inch (Y axis)
    // - on Windows: GetDeviceCaps(DC, LOGPIXELSY)
    // - on Unix/macOS: returns 96 (standard web DPI)
    function GetScreenLogPixels(ADC: TPdfPlatformDC): integer;
  end;

var
  /// global platform font provider - set by RegisterPdfPlatform()
  PdfPlatformFont: IPdfPlatformFont;
  /// global system font enumerator - set by RegisterPdfPlatform()
  PdfSystemFonts: IPdfSystemFonts;
  /// global DC provider - set by RegisterPdfPlatform()
  PdfPlatformDCProvider: IPdfPlatformDC;
  /// global text shaper for complex scripts (RTL, Arabic, Indic)
  // - nil until mormot.pdf.harfbuzz is included and libharfbuzz is loaded
  PdfTextShaper: IPdfTextShaper;
  /// global font subsetter used when EmbeddedWholeTtf is false
  // - nil until mormot.pdf.hbsubset registers itself (Unix/macOS)
  PdfFontSubsetter: IPdfFontSubsetter;

/// register the platform-specific implementations
// - called in the initialization section of mormot.pdf.gdi or
//   mormot.pdf.freetype - the first call wins (the platform unit is listed
//   in the uses clause before this unit)
// - passing nil for any parameter leaves the existing registration unchanged
procedure RegisterPdfPlatform(const AFont: IPdfPlatformFont;
  const AFonts: IPdfSystemFonts; const ADC: IPdfPlatformDC);

/// returns true if a platform has been registered (i.e. RegisterPdfPlatform
// was called at least once with non-nil parameters)
function PdfPlatformRegistered: boolean;

implementation

procedure RegisterPdfPlatform(const AFont: IPdfPlatformFont;
  const AFonts: IPdfSystemFonts; const ADC: IPdfPlatformDC);
begin
  if AFont <> nil then
    PdfPlatformFont := AFont;
  if AFonts <> nil then
    PdfSystemFonts := AFonts;
  if ADC <> nil then
    PdfPlatformDCProvider := ADC;
end;

function PdfPlatformRegistered: boolean;
begin
  result := (PdfPlatformFont <> nil) and
            (PdfSystemFonts <> nil) and
            (PdfPlatformDCProvider <> nil);
end;

end.
