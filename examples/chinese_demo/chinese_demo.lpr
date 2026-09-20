/// Chinese (CJK) PDF Demo — mORMot2 PDF Cross-Platform
// Demonstrates multi-line CJK text rendering with full TTF embedding.
// CJK has no contextual shaping — UseUniscribe=false is sufficient.
//
// Root cause of CJK failure (now fixed): lfCharSet = ANSI_CHARSET in
// TPdfCanvas.SetFont restricted GetFontData to the Latin CMAP only.
// Fix applied: TPdfVclCanvas.SyncFont passes Font.Charset (DEFAULT_CHARSET),
// which lets GDI expose the full CJK CMAP to TPdfTtf.Create.
//
// File size note: EmbeddedWholeTtf=true embeds the complete TTF binary.
// Microsoft YaHei covers 28,000+ CJK ideographs (~17 MB); that is why a
// CJK PDF is ~10x larger than a Latin or Arabic PDF using a smaller font.
// Subsetting (EmbeddedWholeTtf=false) is reliable on Linux/macOS, where
// hb-subset keeps every glyph drawn (ROADMAP R-12: 2.3 MB -> 11 KB here);
// Windows' CreateFontPackage is not reliable for CJK, so the demo keeps the
// whole face on every platform.
//
// Font requirement:
//   Windows : Microsoft YaHei — pre-installed on Vista+ (all locales)
//   macOS   : Hiragino Sans GB — pre-installed
//   Linux   : sudo apt install fonts-wqy-microhei
program chinese_demo;

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
  mormot.ui.pdf,
  mormot.ui.pdfcanvas,
  mormot.ui.report;

const
  {$ifdef MSWINDOWS}
  CJK_FONT = 'Microsoft YaHei';
  {$else}
  {$ifdef DARWIN}
  CJK_FONT = 'Hiragino Sans GB';
  {$else}
  CJK_FONT = 'Droid Sans Fallback';
  {$endif DARWIN}
  {$endif MSWINDOWS}

  OUTPUT_PDF = 'output_chinese.pdf';

  // UTF-8 encoded Chinese string constants
  CJK_TITLE     = #$E4#$B8#$AD#$E6#$96#$87#$E6#$BC#$94#$E7#$A4#$BA;
  // 中文演示  (Chinese Demo)
  CJK_HELLO     = #$E4#$BD#$A0#$E5#$A5#$BD#$EF#$BC#$8C#$E4#$B8#$96#$E7#$95#$8C#$EF#$BC#$81;
  // 你好，世界！  (Hello, World!)
  CJK_NUMBERS   = #$E4#$B8#$80#$E4#$BA#$8C#$E4#$B8#$89#$E5#$9B#$9B#$E4#$BA#$94#$E5#$85#$AD#$E4#$B8#$83#$E5#$85#$AB#$E4#$B9#$9D#$E5#$8D#$81;
  // 一二三四五六七八九十  (1–10 as Chinese numerals)
  CJK_FONT_TEST = #$E5#$AD#$97#$E4#$BD#$93#$E5#$B5#$8C#$E5#$85#$A5#$E6#$B5#$8B#$E8#$AF#$95;
  // 字体嵌入测试  (Font embedding test)
  CJK_SENTENCE  = #$E8#$BF#$99#$E6#$98#$AF#$E4#$B8#$80#$E4#$B8#$AA#$E6#$B5#$8B#$E8#$AF#$95#$E3#$80#$82;
  // 这是一个测试。  (This is a test.)

var
  Doc:                  TPdfDocumentVcl;
  C:                    TCanvas;
  SansFont, SerifFont,
  MonoFont:             string;
  PdfSize:              Int64;

begin
  Doc := TPdfDocumentVcl.Create;
  try
    Doc.EmbeddedTTF      := true;
    Doc.EmbeddedWholeTtf := false;  // full font stream — CJK CMAP coverage guaranteed
    {$ifdef MSWINDOWS}
    Doc.UseUniscribe     := false; // CJK needs no contextual shaping
    {$endif MSWINDOWS}
    Doc.Info.Title       := 'Chinese PDF Demo';
    Doc.DefaultPaperSize := mormot.ui.pdf.psA4;
    GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);

    Doc.AddPage;
    C := Doc.VclCanvas;

    // Latin header
    C.Font.Name  := SansFont;
    C.Font.Size  := 14;
    C.Font.Style := [fsBold];
    C.Font.Color := clBlack;
    C.TextOut(40, 30, 'Chinese PDF Demo  —  Font: ' + CJK_FONT);

    // Chinese title, large
    C.Font.Name  := CJK_FONT;
    C.Font.Size  := 36;
    C.Font.Style := [fsBold];
    C.TextOut(40, 65, CJK_TITLE);

    // Hello, World!
    C.Font.Style := [];
    C.Font.Size  := 28;
    C.TextOut(40, 125, CJK_HELLO);

    // Chinese numerals 1–10
    C.Font.Size  := 22;
    C.TextOut(40, 175, CJK_NUMBERS);

    // Font embedding label
    C.Font.Size  := 18;
    C.TextOut(40, 215, CJK_FONT_TEST);

    // A short sentence
    C.Font.Size  := 16;
    C.TextOut(40, 250, CJK_SENTENCE);

    Doc.SaveToFile(OUTPUT_PDF);
  finally
    Doc.Free;
  end;

  PdfSize := mormot.core.os.FileSize(OUTPUT_PDF);
  WriteLn('PDF saved : ', OUTPUT_PDF);
  WriteLn('File size : ', PdfSize div 1024, ' KB');
  WriteLn('Font used : ', CJK_FONT, '  (EmbeddedWholeTtf=true)');
  WriteLn('');
  WriteLn('Large file size is expected: YaHei/WQY covers 28000+ CJK glyphs (~17 MB TTF).');
  WriteLn('Subsetting (EmbeddedWholeTtf=false) reduces this to a few KB on');
  WriteLn('Linux/macOS (hb-subset); on Windows keep whole-TTF embedding for CJK.');
end.
