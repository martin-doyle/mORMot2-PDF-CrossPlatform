// the feature switches of the PDF engine and its VCL/LCL adapter
// - included by mormot.pdf and mormot.pdf.canvas after mormot.defines.inc,
// so that both units see the same switches: USE_PDFSECURITY changes the
// constructor of TPdfDocument and its descendants
// - each can be switched off for a whole project with its NO_USE_* define
// - the engine reads USE_PDFSECURITY, USE_UNISCRIBE and USE_METAFILE (its
// EmfDC); USE_SYNGDIPLUS and USE_GRAPHICS_UNIT concern mormot.pdf.canvas only,
// which needs the VCL or the LCL anyway
// - a unit that declares a descendant of TPdfDocument with the AEncryption
// parameter must include this file too (mormot.ui.pdfcanvas does not yet:
// its TPdfDocumentVcl.Create never has the parameter - for the bug-fix PR)

{$ifdef OSPOSIX}
  {$undef USE_METAFILE}
  {$undef USE_UNISCRIBE}
  {$undef USE_SYNGDIPLUS}
  {$undef USE_GRAPHICS_UNIT}
{$endif OSPOSIX}

{$define USE_PDFSECURITY}
// if defined, the TPdfDocument*.Create() constructor will have an additional
// AEncryption: TPdfEncryption parameter able to create secured PDF files
// - this feature links mormot.crypt.core.pas unit for MD5 and RC4 algorithms
{$ifdef NO_USE_PDFSECURITY}
  // this special conditional can be set globaly for an application which doesn't
  //  need the security features, therefore dependency to mormot.crypt.core.pas
  {$undef USE_PDFSECURITY}
{$endif NO_USE_PDFSECURITY}

{$define USE_UNISCRIBE}
// if defined, the PDF engine will use the Windows Uniscribe API to
// render Ordering and Shaping of the text (useful for Hebrew, Arabic and
// some Asiatic languages)
// - this feature need the TPdfDocument.UseUniscribe property to be forced to true
// according to the language of the text you want to render
// - the shaping itself is FontShaper, which mormot.lib.uniscribe registers
// unless NO_USE_UNISCRIBE is set for the whole project - as its subsetter;
// inside this unit the conditional only leaves the metafile text and the
// TScriptVisAttr filter of AddGlyphs

{$ifdef NO_USE_UNISCRIBE}
  // this special conditional can be set globaly for an application which does
  // not need the UniScribe features
  {$undef USE_UNISCRIBE}
{$endif NO_USE_UNISCRIBE}

{$define USE_SYNGDIPLUS}
// if defined, the PDF engine will use SynGdiPlus to handle all
// JPG, TIF, PNG and GIF image types (preferred way, but need XP or later OS)
// - if you'd rather use the default jpeg unit (and add some more code to your
// executable), undefine this conditional
{$ifdef NO_USE_SYNGDIPLUS}
// this special conditional can be set globaly for an application which doesn't
// need the SynGdiPlus features (like TMetaFile drawing), and would rather
// use the default jpeg unit
  {$undef USE_SYNGDIPLUS}
{$endif USE_SYNGDIPLUS}

{$define USE_METAFILE}
// if defined, the PDF engine will support TMetaFile / TPdfDocumentGdi
{$ifdef NO_USE_METAFILE}
  // this special conditional can be set globaly for an application which
  // doesn't need the TMetaFile / TPdfDocumentGdi features
  {$undef USE_METAFILE}
{$endif USE_METAFILE}

{$define USE_GRAPHICS_UNIT} // the VCL/LCL of mormot.pdf.canvas - not of the engine
{$ifdef OSPOSIX}
  {$ifndef FPC}
    // Delphi has no VCL on Linux/Android: no TBitmap/TGraphic images there
    {$undef USE_GRAPHICS_UNIT}
  {$endif FPC}
{$endif OSPOSIX}

// POSIX overrides: re-apply after all {$define} blocks above
{$ifdef OSPOSIX}
  {$undef USE_METAFILE}
  {$undef USE_UNISCRIBE}
  {$undef USE_SYNGDIPLUS}
{$endif OSPOSIX}
