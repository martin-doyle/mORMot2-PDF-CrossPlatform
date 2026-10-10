/// Arabic RTL PDF Demo - mORMot2 PDF Cross-Platform
// Draws Arabic with TPdfDocumentVcl, once unshaped and once shaped, so the two
// paths can be compared side by side in the same PDF.
//
// Worth noting:
// - section 1 draws without a shaper: isolated letters only, resolved through
//   the CMAP - it verifies the per-glyph advance widths
// - section 2 shapes with UseUniscribe := true - Uniscribe on Windows,
//   HarfBuzz on Linux/macOS - and RightToLeftText := true for the direction
// - builds with FPC and Delphi 7: the canvas is held as TPdfVclCanvas and the
//   Arabic goes through TextOutUtf8, the same on every compiler
// - the face is embedded as a subset: both subsetters receive the shaped glyph
//   IDs, so the GSUB output survives
//
// Font requirement:
//   Windows  : Tahoma - covers Arabic, pre-installed on all versions
//   macOS    : Geeza Pro - pre-installed
//   Linux    : Noto Naskh Arabic - sudo apt install fonts-noto-core
//              (without it the fallback face shows boxes instead of Arabic)
//
// HarfBuzz requirement (Linux/macOS):
//   sudo apt install libharfbuzz0b   (Debian/Ubuntu)
//   sudo dnf install harfbuzz        (Fedora/RHEL)
//   brew install harfbuzz            (macOS)
program rtl_demo;

{$I mormot.defines.inc}
{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  Interfaces,
  {$endif FPC}
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.pdf,         // TPdfDocument, GetPdfFonts
  mormot.ui.pdfcanvas;

{$R *.res}

const
  {$ifdef OSWINDOWS}
  ARABIC_FONT = 'Tahoma';
  {$else}
  {$ifdef OSDARWIN}
  ARABIC_FONT = 'Geeza Pro';
  {$else}
  // Noto Naskh Arabic covers Arabic Unicode block with proper contextual forms.
  // Install: sudo apt install fonts-noto-core
  // If not found, the engine falls back to FontFallBackName (usually DejaVu Sans
  // which has no Arabic glyphs - squares will appear instead).
  ARABIC_FONT = 'Noto Naskh Arabic';
  {$endif OSDARWIN}
  {$endif OSWINDOWS}

  // UTF-8 encoded strings, drawn with TextOutUtf8: TextOut reads a string as
  // the compiler holds it, the ANSI code page on Delphi 7
  // U+0628 ARABIC LETTER BA - isolated form
  ARABIC_BA: RawUtf8 = {$ifdef HASCODEPAGE} #$0628 {$else} #$D8#$A8 {$endif};
  // مرحبا  (marhaba = Hello)
  // م=U+0645 ر=U+0631 ح=U+062D ب=U+0628 ا=U+0627
  ARABIC_HELLO: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0645#$0631#$062D#$0628#$0627 {$else}
    #$D9#$85#$D8#$B1#$D8#$AD#$D8#$A8#$D8#$A7 {$endif};
  // كتاب  (kitab = Book)
  // ك=U+0643 ت=U+062A ا=U+0627 ب=U+0628
  ARABIC_BOOK: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0643#$062A#$0627#$0628 {$else}
    #$D9#$83#$D8#$AA#$D8#$A7#$D8#$A8 {$endif};
  // مدرسة  (madrasa = School)
  // م=U+0645 د=U+062F ر=U+0631 س=U+0633 ة=U+0629
  ARABIC_SCHOOL: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0645#$062F#$0631#$0633#$0629 {$else}
    #$D9#$85#$D8#$AF#$D8#$B1#$D8#$B3#$D8#$A9 {$endif};
  // بيت  (bayt = House)
  // ب=U+0628 ي=U+064A ت=U+062A
  ARABIC_HOUSE: RawUtf8 = {$ifdef HASCODEPAGE}
    #$0628#$064A#$062A {$else}
    #$D8#$A8#$D9#$8A#$D8#$AA {$endif};
  // "Expected: U+0628 BA <em dash> same glyph as 1a, now via shaper path."
  EXPECTED_2A: RawUtf8 = 'Expected: U+0628 BA ' +
    {$ifdef HASCODEPAGE} #$2014 {$else} #$E2#$80#$94 {$endif} +
    ' same glyph as 1a, now via shaper path.';

{ <demo>_<os>_<cpu>_<compiler>.pdf next to the executable, e.g.
  rtl_demo_windows_x64_free-pascal-3.2.2.pdf or ..._x86_delphi-7.pdf: the runs
  of all platforms and compilers can then share one folder for checking.
  OS_KIND names the distribution on Linux }
function PdfFileName: TFileName;
var
  compiler: RawUtf8;
begin
  compiler := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  result := Executable.ProgramFilePath + Utf8ToString(LowerCase('rtl_demo_' +
    ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' + CPU_ARCH_TEXT + '_' +
    StringReplaceAll(compiler, ' ', '-') + '.pdf'));
end;

var
  Doc:                  TPdfDocumentVcl;
  C:                    TPdfVclCanvas;
  PdfC:                 TPdfCanvas;
  SansFont, SerifFont,
  MonoFont:             string;
  PdfSize:              Int64;

begin
  Doc := TPdfDocumentVcl.Create;
  try
    Doc.EmbeddedTTF      := true;
    // subset: both subsetters are fed the shaped glyph IDs themselves, so the
    // GSUB output survives - hb-subset on Linux/macOS (R-12), CreateFontPackage
    // with a glyph keep list on Windows (R-15)
    Doc.EmbeddedWholeTtf := false;
    Doc.Info.Title       := 'Arabic RTL Demo';
    Doc.DefaultPaperSize := psA4;
    GetPdfFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);

    Doc.AddPage;
    C    := Doc.VclCanvas;
    PdfC := C.PdfCanvas;

    // === Section 1: NoShaper path (isolated forms, no contextual shaping) ===
    Doc.UseUniscribe     := false;
    PdfC.RightToLeftText := false;

    // --- 1a: Single isolated letter - CMAP fix test ---
    C.Font.Name  := SansFont;
    C.Font.Size  := 13;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    C.TextOut(40, 30, 'Section 1a: Single char  (no shaper, CMAP fix)');

    C.Font.Name  := ARABIC_FONT;
    C.Font.Size  := 48;
    C.Font.Style := [];
    C.TextOutUtf8(40, 52, ARABIC_BA);

    C.Font.Name  := SansFont;
    C.Font.Size  := 10;
    C.Font.Color := $00808080;
    C.TextOut(40, 112, 'Expected: U+0628 BA visible. Box = DEFAULT_CHARSET fix missing.');

    // --- 1b: Multiple isolated letters - advance width test ---
    C.Font.Name  := SansFont;
    C.Font.Size  := 13;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    C.TextOut(40, 138, 'Section 1b: Multiple isolated chars  (no shaper, width test)');

    C.Font.Name  := ARABIC_FONT;
    C.Font.Size  := 24;
    C.Font.Style := [];
    C.TextOutUtf8(40, 162, ARABIC_HELLO);    // 5 isolated letters
    C.TextOutUtf8(40, 196, ARABIC_BOOK);     // 4 isolated letters
    C.TextOutUtf8(40, 230, ARABIC_SCHOOL);   // 5 isolated letters
    C.TextOutUtf8(40, 264, ARABIC_HOUSE);    // 3 isolated letters

    C.Font.Name  := SansFont;
    C.Font.Size  := 10;
    C.Font.Color := $00808080;
    C.TextOut(260, 170, 'marhaba  (5 chars)');
    C.TextOut(260, 204, 'kitab  (4 chars)');
    C.TextOut(260, 238, 'madrasa  (5 chars)');
    C.TextOut(260, 272, 'bayt  (3 chars)');

    C.Font.Name  := SansFont;
    C.Font.Size  := 10;
    C.Font.Color := $00808080;
    C.TextOut(40, 296, 'Expected: isolated letter forms, each with correct advance width (no overlap).');

    // === Section 2: Shaper path (contextual shaping + RTL bidi) ===
    // UseUniscribe is the one shaping switch: Uniscribe on Windows, HarfBuzz
    // on Linux/macOS (if libharfbuzz loaded); RightToLeftText is the direction.
    // No conditional: an {$ifdef USE_UNISCRIBE} would compile the assignment
    // away, as that symbol never leaves mormot.pdf (ROADMAP R-16)
    Doc.UseUniscribe := true;

    C.Font.Name  := SansFont;
    C.Font.Size  := 13;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    PdfC.RightToLeftText := false;
    C.TextOut(40, 322, 'Section 2: Contextual shaping  (UseUniscribe=true, RTL)');

    // --- 2a: Single char with shaper ---
    C.Font.Name  := SansFont;
    C.Font.Size  := 11;
    C.Font.Style := [];
    C.Font.Color := clBlack;
    PdfC.RightToLeftText := false;
    C.TextOut(40, 348, '2a: Single char  (shaper, RightToLeftText=true):');

    C.Font.Name  := ARABIC_FONT;
    C.Font.Size  := 48;
    PdfC.RightToLeftText := true;
    C.TextOutUtf8(500, 366, ARABIC_BA);   // single Ba via shaper

    C.Font.Name  := SansFont;
    C.Font.Size  := 10;
    C.Font.Color := $00808080;
    PdfC.RightToLeftText := false;
    C.TextOutUtf8(40, 426, EXPECTED_2A);

    // --- 2b: Arabic words with shaper ---
    C.Font.Name  := SansFont;
    C.Font.Size  := 11;
    C.Font.Style := [];
    C.Font.Color := clBlack;
    PdfC.RightToLeftText := false;
    C.TextOut(40, 450, '2b: Arabic words  (shaper, RightToLeftText=true):');

    C.Font.Name  := ARABIC_FONT;
    C.Font.Size  := 36;
    PdfC.RightToLeftText := true;
    C.TextOutUtf8(500, 472, ARABIC_HELLO);    // مرحبا - connected contextual forms
    C.TextOutUtf8(500, 516, ARABIC_BOOK);     // كتاب
    C.TextOutUtf8(500, 560, ARABIC_SCHOOL);   // مدرسة
    C.TextOutUtf8(500, 604, ARABIC_HOUSE);    // بيت

    // Latin labels for each word
    PdfC.RightToLeftText := false;
    C.Font.Name  := SansFont;
    C.Font.Size  := 12;
    C.Font.Color := $00404040;
    C.TextOut(40, 483, 'marhaba = Hello');
    C.TextOut(40, 527, 'kitab = Book');
    C.TextOut(40, 571, 'madrasa = School');
    C.TextOut(40, 615, 'bayt = House');

    Doc.SaveToFile(PdfFileName);
  finally
    Doc.Free;
  end;

  PdfSize := mormot.core.os.FileSize(PdfFileName);
  WriteLn('PDF saved : ', PdfFileName, '  (', PdfSize div 1024, ' KB)');
  WriteLn('Font used : ', ARABIC_FONT);
  WriteLn('');
  WriteLn('Section 1a: isolated U+0628 BA - CMAP lookup (DEFAULT_CHARSET fix).');
  WriteLn('Section 1b: multiple isolated chars - advance widths from CMAP (no overlap).');
  {$ifdef OSWINDOWS}
  WriteLn('Section 2a: single char via Uniscribe - GetAndMarkGlyphAsUsed Step 2 fix.');
  WriteLn('Section 2b: Arabic words with Uniscribe shaping and RTL direction.');
  {$else}
  WriteLn('Section 2a: single char via HarfBuzz - GetAndMarkGlyphAsUsedWithWidth.');
  WriteLn('Section 2b: Arabic words with HarfBuzz shaping and RTL direction.');
  WriteLn('            Requires: libharfbuzz + ', ARABIC_FONT, ' font.');
  {$endif OSWINDOWS}
  WriteLn('            Letters should connect and not overlap.');
end.
