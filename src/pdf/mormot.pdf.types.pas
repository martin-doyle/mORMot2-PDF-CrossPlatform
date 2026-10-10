/// Cross-Platform PDF Engine Shared Types and Platform Interfaces
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.pdf.types;

{
  *****************************************************************************

   Cross-Platform PDF Shared Types
   - PDF font names for the two embedding modes
   - PDF file format and Tagged PDF structure roles
   - transitional aliases of the font types of mormot.lib.core: the font
     interfaces, their records and their registration live there now

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

uses
  SysUtils,
  mormot.core.base,
  mormot.core.unicode,
  mormot.lib.core;

const
  /// PDF standard Type 1 font names - supported by all PDF readers without embedding
  // - use with TPdfDocument.StandardFontsReplace := true
  PDF_FONT_STD_SANS  = 'Helvetica';
  PDF_FONT_STD_SERIF = 'Times';
  PDF_FONT_STD_MONO  = 'Courier';

  /// platform TrueType font names - for embedding, and for tagged output
  // - Calibri/Cambria/Consolas on Windows, Trebuchet MS/Georgia/Andale Mono
  // on macOS, Liberation Sans/Serif/Mono on Linux, the /system/fonts faces
  // Roboto/Noto Serif/Droid Sans Mono on Android
  PDF_FONT_TTF_SANS  = {$ifdef OSWINDOWS}'Calibri'{$else}{$ifdef OSDARWIN}'Trebuchet MS'{$else}{$ifdef OSANDROID}'Roboto'{$else}'Liberation Sans'{$endif}{$endif}{$endif};
  PDF_FONT_TTF_SERIF = {$ifdef OSWINDOWS}'Cambria'{$else}{$ifdef OSDARWIN}'Georgia'{$else}{$ifdef OSANDROID}'Noto Serif'{$else}'Liberation Serif'{$endif}{$endif}{$endif};
  PDF_FONT_TTF_MONO  = {$ifdef OSWINDOWS}'Consolas'{$else}{$ifdef OSDARWIN}'Andale Mono'{$else}{$ifdef OSANDROID}'Droid Sans Mono'{$else}'Liberation Mono'{$endif}{$endif}{$endif};

/// font names matching the embedding mode
// - Embedded=true: the platform TrueType fonts (PDF_FONT_TTF_*)
// - Embedded=false: the PDF standard Type1 fonts (PDF_FONT_STD_*)
procedure GetPdfFonts(Embedded: boolean;
  out SansFont, SerifFont, MonoFont: string);

type
  /// PDF file format version written to the %PDF-1.x header
  // - pdf13 (default) through pdf17 (ISO 32000-1)
  TPdfFileFormat = (pdf13, pdf14, pdf15, pdf16, pdf17);

  /// structure role for Tagged PDF (ISO 32000-1 14) accessibility tags
  // - psrDocument=0; psrH1..psrH6=1..6; psrP=7; psrSpan=8
  // - psrFigure=9 for image/graphic elements
  // - psrTable=10, psrTR=11, psrTH=12, psrTD=13 for table structure
  // - psrL=14, psrLI=15, psrLbl=16, psrLBody=17 for list structure
  // - psrTHead=18, psrTBody=19, psrTFoot=20 group the rows of a table
  // (ISO 32000-1 14.8.4.3.4): a totals row in a TFoot is told apart from the
  // data rows by assistive technology
  // - psrTHRow=21 is a TH which heads its row (/Scope /Row), e.g. the label
  // of a totals row; psrTH heads its column
  // - TPdfStructRole(Level) for heading Level 1..6 gives psrH1..psrH6
  // - new roles are appended at the end: TPdfStructRole(Level) and the
  // dckBeginTR logic in mormot.ui.report depend on the existing ordinals
  TPdfStructRole = (psrDocument, psrH1, psrH2, psrH3, psrH4, psrH5, psrH6,
                    psrP, psrSpan,
                    psrFigure,
                    psrTable, psrTR, psrTH, psrTD,
                    psrL, psrLI, psrLbl, psrLBody,
                    psrTHead, psrTBody, psrTFoot,
                    psrTHRow);

  /// callback type for font enumeration
  // - called once per available TrueType font
  // - FontName: the UTF-8 encoded font family name
  // - return true to continue enumeration, false to stop
  TPdfFontEnumCallback = procedure(const FontName: RawUtf8;
    var List: TRawUtf8DynArray);

  // former names of the font types and interfaces of mormot.lib.core, kept
  // while the refactoring runs (R-28): the shaper and the subsetter changed
  // their signatures and have no alias, the globals are FontProvider,
  // FontEnumerator, FontShaper, FontSubsetter and FontPlatformRegistered of
  // mormot.lib.core; the device context (TPdfPlatformDC, IPdfPlatformDC) is
  // gone with Phase 1b, IFontFace replaces it
  TPdfPlatformFontHandle = TFontHandle;
  TPdfTextMetrics = TFontMetrics;
  TPdfOutlineMetrics = TFontOutlineMetrics;
  TPdfCharABC = TFontCharAbc;
  TPdfCharABCArray = TFontCharAbcArray;
  TPdfLogFont = TFontRequest;
  TPdfFontSubsetRequest = TFontSubsetRequest;
  IPdfPlatformFont = IFontProvider;
  IPdfSystemFonts = IFontEnumerator;

implementation

procedure GetPdfFonts(Embedded: boolean;
  out SansFont, SerifFont, MonoFont: string);
begin
  if Embedded then
  begin
    SansFont  := PDF_FONT_TTF_SANS;
    SerifFont := PDF_FONT_TTF_SERIF;
    MonoFont  := PDF_FONT_TTF_MONO;
  end
  else
  begin
    SansFont  := PDF_FONT_STD_SANS;
    SerifFont := PDF_FONT_STD_SERIF;
    MonoFont  := PDF_FONT_STD_MONO;
  end;
end;

end.
