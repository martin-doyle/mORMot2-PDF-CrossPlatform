/// Arabic RTL PDF Demo — mORMot2 PDF Cross-Platform
// Draws Arabic with TPdfDocumentVcl, once unshaped and once shaped, so the two
// paths can be compared side by side in the same PDF.
//
// Worth noting:
// - section 1 draws without a shaper: isolated letters only, resolved through
//   the CMAP — it verifies the per-glyph advance widths
// - section 2 shapes: Uniscribe on Windows (UseUniscribe := true), HarfBuzz on
//   Linux/macOS (mormot.pdf.harfbuzz registers PdfTextShaper at startup);
//   both need RightToLeftText := true
// - the face is embedded as a subset: both subsetters receive the shaped glyph
//   IDs, so the GSUB output survives
//
// Font requirement:
//   Windows  : Tahoma — covers Arabic, pre-installed on all versions
//   macOS    : Geeza Pro — pre-installed
//   Linux    : Noto Naskh Arabic — sudo apt install fonts-noto-core
//              (without it the fallback face shows boxes instead of Arabic)
//
// HarfBuzz requirement (Linux/macOS):
//   sudo apt install libharfbuzz0b   (Debian/Ubuntu)
//   sudo dnf install harfbuzz        (Fedora/RHEL)
//   brew install harfbuzz            (macOS)
program rtl_demo;

{$ifdef FPC}
{$mode delphi}
{$endif FPC}

uses
  {$ifdef FPC}
  Interfaces,
  {$endif FPC}
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  {$ifndef MSWINDOWS}
  mormot.pdf.freetype,   // FreeType2 backend (must be before mormot.pdf.harfbuzz)
  mormot.pdf.harfbuzz,   // HarfBuzz shaper — registers PdfTextShaper at startup
  {$endif MSWINDOWS}
  mormot.ui.pdf,
  mormot.ui.pdfcanvas,
  mormot.ui.report;

{$R *.res}

const
  {$ifdef MSWINDOWS}
  ARABIC_FONT = 'Tahoma';
  {$else}
  {$ifdef DARWIN}
  ARABIC_FONT = 'Geeza Pro';
  {$else}
  // Noto Naskh Arabic covers Arabic Unicode block with proper contextual forms.
  // Install: sudo apt install fonts-noto-core
  // If not found, the engine falls back to FontFallBackName (usually DejaVu Sans
  // which has no Arabic glyphs — squares will appear instead).
  ARABIC_FONT = 'Noto Naskh Arabic';
  {$endif DARWIN}
  {$endif MSWINDOWS}

  // UTF-8 encoded Arabic string constants
  // U+0628 ARABIC LETTER BA — isolated form
  ARABIC_BA     = #$D8#$A8;
  // مرحبا  (marhaba = Hello)
  // م=U+0645 ر=U+0631 ح=U+062D ب=U+0628 ا=U+0627
  ARABIC_HELLO  = #$D9#$85#$D8#$B1#$D8#$AD#$D8#$A8#$D8#$A7;
  // كتاب  (kitab = Book)
  // ك=U+0643 ت=U+062A ا=U+0627 ب=U+0628
  ARABIC_BOOK   = #$D9#$83#$D8#$AA#$D8#$A7#$D8#$A8;
  // مدرسة  (madrasa = School)
  // م=U+0645 د=U+062F ر=U+0631 س=U+0633 ة=U+0629
  ARABIC_SCHOOL = #$D9#$85#$D8#$AF#$D8#$B1#$D8#$B3#$D8#$A9;
  // بيت  (bayt = House)
  // ب=U+0628 ي=U+064A ت=U+062A
  ARABIC_HOUSE  = #$D8#$A8#$D9#$8A#$D8#$AA;

{ <demo>_<os>.pdf next to the executable: the runs of all platforms can then
  share one folder for checking. OS_KIND names the distribution on Linux }
function PdfFileName: TFileName;
begin
  result := Executable.ProgramFilePath + 'rtl_demo_' +
    Utf8ToString(LowerCase(ShortStringToAnsi7String(OS_NAME[OS_KIND]))) + '.pdf';
end;

var
  Doc:                  TPdfDocumentVcl;
  C:                    TCanvas;
  PdfC:                 TPdfCanvas;
  SansFont, SerifFont,
  MonoFont:             string;
  PdfSize:              Int64;

begin
  Doc := TPdfDocumentVcl.Create;
  try
    Doc.EmbeddedTTF      := true;
    // subset: both subsetters are fed the shaped glyph IDs themselves, so the
    // GSUB output survives — hb-subset on Linux/macOS (R-12), CreateFontPackage
    // with a glyph keep list on Windows (R-15)
    Doc.EmbeddedWholeTtf := false;
    Doc.Info.Title       := 'Arabic RTL Demo';
    Doc.DefaultPaperSize := mormot.ui.pdf.psA4;
    GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);

    Doc.AddPage;
    C    := Doc.VclCanvas;
    PdfC := (C as TPdfVclCanvas).PdfCanvas;

    // === Section 1: NoShaper path (isolated forms, no contextual shaping) ===
    Doc.UseUniscribe     := false;
    PdfC.RightToLeftText := false;

    // --- 1a: Single isolated letter — CMAP fix test ---
    C.Font.Name  := SansFont;
    C.Font.Size  := 13;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    C.TextOut(40, 30, 'Section 1a: Single char  (no shaper, CMAP fix)');

    C.Font.Name  := ARABIC_FONT;
    C.Font.Size  := 48;
    C.Font.Style := [];
    C.TextOut(40, 52, ARABIC_BA);

    C.Font.Name  := SansFont;
    C.Font.Size  := 10;
    C.Font.Color := $00808080;
    C.TextOut(40, 112, 'Expected: U+0628 BA visible. Box = DEFAULT_CHARSET fix missing.');

    // --- 1b: Multiple isolated letters — advance width test ---
    C.Font.Name  := SansFont;
    C.Font.Size  := 13;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    C.TextOut(40, 138, 'Section 1b: Multiple isolated chars  (no shaper, width test)');

    C.Font.Name  := ARABIC_FONT;
    C.Font.Size  := 24;
    C.Font.Style := [];
    C.TextOut(40, 162, ARABIC_HELLO);    // 5 isolated letters
    C.TextOut(40, 196, ARABIC_BOOK);     // 4 isolated letters
    C.TextOut(40, 230, ARABIC_SCHOOL);   // 5 isolated letters
    C.TextOut(40, 264, ARABIC_HOUSE);    // 3 isolated letters

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
    // Windows: Uniscribe   Linux/macOS: HarfBuzz (if libharfbuzz loaded)
    // no conditional here: USE_UNISCRIBE lives inside mormot.ui.pdf and never
    // reaches this unit, so an {$ifdef USE_UNISCRIBE} would compile the
    // assignment away and the shaper would never run (ROADMAP R-16).
    // The property exists on every platform and is inert where Uniscribe is.
    Doc.UseUniscribe := true;

    C.Font.Name  := SansFont;
    C.Font.Size  := 13;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    PdfC.RightToLeftText := false;
    {$ifdef MSWINDOWS}
    C.TextOut(40, 322, 'Section 2: Contextual shaping  (UseUniscribe=true, RTL)');
    {$else}
    C.TextOut(40, 322, 'Section 2: Contextual shaping  (HarfBuzz, RightToLeftText=true)');
    {$endif MSWINDOWS}

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
    C.TextOut(500, 366, ARABIC_BA);   // single Ba via shaper

    C.Font.Name  := SansFont;
    C.Font.Size  := 10;
    C.Font.Color := $00808080;
    PdfC.RightToLeftText := false;
    C.TextOut(40, 426, 'Expected: U+0628 BA — same glyph as 1a, now via shaper path.');

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
    C.TextOut(500, 472, ARABIC_HELLO);    // مرحبا — connected contextual forms
    C.TextOut(500, 516, ARABIC_BOOK);     // كتاب
    C.TextOut(500, 560, ARABIC_SCHOOL);   // مدرسة
    C.TextOut(500, 604, ARABIC_HOUSE);    // بيت

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
  WriteLn('Section 1a: isolated U+0628 BA — CMAP lookup (DEFAULT_CHARSET fix).');
  WriteLn('Section 1b: multiple isolated chars — advance widths from CMAP (no overlap).');
  {$ifdef MSWINDOWS}
  WriteLn('Section 2a: single char via Uniscribe — GetAndMarkGlyphAsUsed Step 2 fix.');
  WriteLn('Section 2b: Arabic words with Uniscribe shaping and RTL direction.');
  {$else}
  WriteLn('Section 2a: single char via HarfBuzz — GetAndMarkGlyphAsUsedWithWidth.');
  WriteLn('Section 2b: Arabic words with HarfBuzz shaping and RTL direction.');
  WriteLn('            Requires: libharfbuzz + ', ARABIC_FONT, ' font.');
  {$endif MSWINDOWS}
  WriteLn('            Letters should connect and not overlap.');
end.
