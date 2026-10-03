/// Chinese (CJK) PDF Demo — mORMot2 PDF Cross-Platform
// Draws multi-line CJK text with TPdfDocumentVcl and embeds the face as a
// subset on every platform.
//
// Worth noting:
// - builds with FPC and Delphi 7: the canvas is held as TPdfVclCanvas and the
//   text goes through TextOutUtf8, the same on every compiler
// - CJK has no contextual shaping, so UseUniscribe stays false
// - subsetting is what keeps the file small: the whole face costs about 24 MB
//   against roughly 39 KB for the glyphs actually drawn
// - the CJK face is picked per platform (see CJK_FONT below)
// - macOS resolves a CFF face (Hiragino Sans GB), whose subset goes to
//   /FontFile3 with /Subtype /OpenType instead of /FontFile2 (roadmap R-15c)
//
// Font requirement:
//   Windows : Microsoft YaHei — pre-installed on Vista+ (all locales)
//   macOS   : Hiragino Sans GB — pre-installed
//   Linux   : Droid Sans Fallback — sudo apt install fonts-droid-fallback
program chinese_demo;

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
  mormot.pdf.types,   // GetPdfFonts
  mormot.ui.pdf,
  mormot.ui.pdfcanvas;

{$R *.res}

const
  {$ifdef OSWINDOWS}
  CJK_FONT = 'Microsoft YaHei';
  {$else}
  {$ifdef OSDARWIN}
  CJK_FONT = 'Hiragino Sans GB';
  {$else}
  CJK_FONT = 'Droid Sans Fallback';
  {$endif OSDARWIN}
  {$endif OSWINDOWS}

  // UTF-8 encoded strings, drawn with TextOutUtf8: TextOut reads a string as
  // the compiler holds it, the ANSI code page on Delphi 7
  CJK_TITLE: RawUtf8 = {$ifdef HASCODEPAGE}
    #$4E2D#$6587#$6F14#$793A {$else}
    #$E4#$B8#$AD#$E6#$96#$87#$E6#$BC#$94#$E7#$A4#$BA {$endif};
  // 中文演示  (Chinese Demo)
  CJK_HELLO: RawUtf8 = {$ifdef HASCODEPAGE}
    #$4F60#$597D#$FF0C#$4E16#$754C#$FF01 {$else}
    #$E4#$BD#$A0#$E5#$A5#$BD#$EF#$BC#$8C#$E4#$B8#$96#$E7#$95#$8C#$EF#$BC#$81 {$endif};
  // 你好，世界！  (Hello, World!)
  CJK_NUMBERS: RawUtf8 = {$ifdef HASCODEPAGE}
    #$4E00#$4E8C#$4E09#$56DB#$4E94#$516D#$4E03#$516B#$4E5D#$5341 {$else}
    #$E4#$B8#$80#$E4#$BA#$8C#$E4#$B8#$89#$E5#$9B#$9B#$E4#$BA#$94#$E5#$85#$AD#$E4#$B8#$83#$E5#$85#$AB#$E4#$B9#$9D#$E5#$8D#$81 {$endif};
  // 一二三四五六七八九十  (1–10 as Chinese numerals)
  CJK_FONT_TEST: RawUtf8 = {$ifdef HASCODEPAGE}
    #$5B57#$4F53#$5D4C#$5165#$6D4B#$8BD5 {$else}
    #$E5#$AD#$97#$E4#$BD#$93#$E5#$B5#$8C#$E5#$85#$A5#$E6#$B5#$8B#$E8#$AF#$95 {$endif};
  // 字体嵌入测试  (Font embedding test)
  CJK_SENTENCE: RawUtf8 = {$ifdef HASCODEPAGE}
    #$8FD9#$662F#$4E00#$4E2A#$6D4B#$8BD5#$3002 {$else}
    #$E8#$BF#$99#$E6#$98#$AF#$E4#$B8#$80#$E4#$B8#$AA#$E6#$B5#$8B#$E8#$AF#$95#$E3#$80#$82 {$endif};
  // 这是一个测试。  (This is a test.)
  // "Chinese PDF Demo  <em dash>  Font: "
  HEADER_TEXT: RawUtf8 = {$ifdef HASCODEPAGE}
    'Chinese PDF Demo  '#$2014'  Font: ' {$else}
    'Chinese PDF Demo  '#$E2#$80#$94'  Font: ' {$endif};

{ <demo>_<os>_<cpu>_<compiler>.pdf next to the executable, e.g.
  chinese_demo_windows_x64_free-pascal-3.2.2.pdf or ..._x86_delphi-7.pdf: the runs
  of all platforms and compilers can then share one folder for checking.
  OS_KIND names the distribution on Linux }
function PdfFileName: TFileName;
var
  compiler: RawUtf8;
begin
  compiler := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  result := Executable.ProgramFilePath + Utf8ToString(LowerCase('chinese_demo_' +
    ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' + CPU_ARCH_TEXT + '_' +
    StringReplaceAll(compiler, ' ', '-') + '.pdf'));
end;

var
  Doc:                  TPdfDocumentVcl;
  C:                    TPdfVclCanvas;
  SansFont, SerifFont,
  MonoFont:             string;
  PdfSize:              Int64;

begin
  Doc := TPdfDocumentVcl.Create;
  try
    Doc.EmbeddedTTF      := true;
    Doc.EmbeddedWholeTtf := false; // subset: hb-subset on POSIX (R-12),
                                   // CreateFontPackage on Windows (R-15) —
                                   // both keep the glyph IDs CJK is drawn with
    // CJK needs no contextual shaping; the property exists on every platform
    Doc.UseUniscribe     := false;
    Doc.Info.Title       := 'Chinese PDF Demo';
    Doc.DefaultPaperSize := psA4;
    GetPdfFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);

    Doc.AddPage;
    C := Doc.VclCanvas;

    // Latin header
    C.Font.Name  := SansFont;
    C.Font.Size  := 14;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    C.TextOutUtf8(40, 30, HEADER_TEXT + CJK_FONT);

    // Chinese title, large
    C.Font.Name  := CJK_FONT;
    C.Font.Size  := 36;
    C.Font.Style := [fsBold];
    C.TextOutUtf8(40, 65, CJK_TITLE);

    // Hello, World!
    C.Font.Style := [];
    C.Font.Size  := 28;
    C.TextOutUtf8(40, 125, CJK_HELLO);

    // Chinese numerals 1–10
    C.Font.Size  := 22;
    C.TextOutUtf8(40, 175, CJK_NUMBERS);

    // Font embedding label
    C.Font.Size  := 18;
    C.TextOutUtf8(40, 215, CJK_FONT_TEST);

    // A short sentence
    C.Font.Size  := 16;
    C.TextOutUtf8(40, 250, CJK_SENTENCE);

    Doc.SaveToFile(PdfFileName);
  finally
    Doc.Free;
  end;

  PdfSize := mormot.core.os.FileSize(PdfFileName);
  WriteLn('PDF saved : ', PdfFileName);
  WriteLn('File size : ', PdfSize div 1024, ' KB');
  WriteLn('Font used : ', CJK_FONT, '  (EmbeddedWholeTtf=false)');
  WriteLn('');
  WriteLn('Microsoft YaHei covers 28000+ CJK glyphs (~17 MB TTF), so only the glyphs');
  WriteLn('actually drawn are embedded: hb-subset on Linux/macOS (ROADMAP R-12),');
  WriteLn('CreateFontPackage with a glyph keep list on Windows (R-15). Both keep');
  WriteLn('the glyph numbering, so Identity-H and /ToUnicode stay valid.');
  WriteLn('Set EmbeddedWholeTtf := true to embed the complete face instead.');
  {$ifdef OSDARWIN}
  WriteLn('');
  WriteLn('Hiragino Sans GB is OpenType/CFF, so its subset is embedded as');
  WriteLn('/FontFile3 with /Subtype /OpenType, as a CIDFontType0 (R-15c).');
  {$endif OSDARWIN}
end.
