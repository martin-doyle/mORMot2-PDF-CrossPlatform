/// Layer 1 Demo — mORMot2 PDF Cross-Platform
// Produces a one-page tagged PDF with TPdfDocument and TPdfCanvas alone - no
// TCanvas bridge, no report engine - so it builds with FPC on every platform
// and with Delphi 7 on Win32 (tests\build_delphi7.bat).
//
// Worth noting:
// - coordinates are PDF points (1/72 inch), X from the left edge and Y from
//   the BOTTOM edge of the page: a text line at Y = 780 sits near the top of
//   an A4 page (842 pt high), and Y is its baseline
// - the text goes in as UTF-8 and is drawn with TextOutW, which means the
//   same on both compilers: a Delphi 7 string literal would be in the ANSI
//   code page, an FPC one in UTF-8. Non-ASCII characters are UTF-8 bytes in a
//   RawUtf8 constant, never literal characters in the source
// - Tagged := True must be set before AddPage and before the font names are
//   resolved; it raises FileFormat to pdf17 and embeds the TrueType faces
// - the low-level API leaves the structure and the bookmarks to the caller:
//   every heading gets its outline entry here, PDF/UA wants one
// - a path drawn outside a struct element becomes an artifact by itself, a
//   running footer has to be marked with BeginArtifact/EndArtifact
program layer1_demo;

{$I mormot.defines.inc}

{$ifdef OSWINDOWS}
  {$apptype console}
{$endif OSWINDOWS}

uses
  {$ifdef FPC}
  Interfaces,   // registers the LCL widgetset - Delphi has no counterpart
  {$endif FPC}
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.pdf.types,   // TPdfStructRole, GetPdfFonts
  {$ifdef OSWINDOWS}
  mormot.pdf.gdi,       // registers the GDI backend
  {$else}
  mormot.pdf.freetype,  // registers the FreeType2 backend
  {$endif OSWINDOWS}
  mormot.ui.pdf;

const
  /// the face's full cmap, not the ANSI part only (fonts.md §10)
  DEFAULT_CHARSET = 1;
  LEFT = 56;
  /// 'Umlauts and symbols: ä ö ü Ä Ö Ü ß € § °' as UTF-8
  UMLAUTS: RawUtf8 = 'Umlauts and symbols: '#$C3#$A4' '#$C3#$B6' '#$C3#$BC' '#$C3#$84 +
    ' '#$C3#$96' '#$C3#$9C' '#$C3#$9F' '#$E2#$82#$AC' '#$C2#$A7' '#$C2#$B0;
  BAR_VALUES: array[0..3] of integer = (40, 75, 55, 90);
  BAR_COLORS: array[0..3] of TPdfColor = ($B4642D, $2D8CD2, $3CA03C, $3C3CC8);

var
  Doc: TPdfDocument;
  C: TPdfCanvas;
  SansFont, SerifFont, MonoFont: string;
  Sans, Serif, Mono: RawUtf8;
  i: integer;

{ <demo>_<os>.pdf next to the executable, as the other demos write it }
function PdfFileName: TFileName;
begin
  result := Executable.ProgramFilePath + 'layer1_demo_' +
    Utf8ToString(LowerCase(ShortStringToAnsi7String(OS_NAME[OS_KIND]))) + '.pdf';
end;

procedure DrawText(X, Y: single; const Text: RawUtf8);
var
  W: SynUnicode;
begin
  W := Utf8ToSynUnicode(Text);
  C.TextOutW(X, Y, pointer(W));
end;

{ a heading element and its bookmark; Y is the baseline }
procedure Heading(Level: integer; Y, Size: single; const Title: RawUtf8);
begin
  C.BeginStructContent(TPdfStructRole(Level)); // psrH1..psrH6
  C.SetFont(Sans, Size, [pfsBold], DEFAULT_CHARSET);
  C.SetRGBFillColor($5A2D14);
  DrawText(LEFT, Y, Title);
  C.EndStructContent;
  // the outline takes the top of the heading, in points from the page bottom
  Doc.CreateOutline(Utf8ToString(Title), Level, Y + Size);
end;

begin
  Doc := TPdfDocument.Create({AUseOutlines=}true);
  try
    Doc.Tagged := true;
    Doc.DefaultLanguage := 'en';
    Doc.Info.Title := 'mORMot2 PDF Layer 1 Demo';
    Doc.DefaultPaperSize := psA4;
    // asked after Tagged, so the names match the embedded font mode
    GetPdfFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
    Sans := StringToUtf8(SansFont);
    Serif := StringToUtf8(SerifFont);
    Mono := StringToUtf8(MonoFont);
    Doc.AddPage;
    C := Doc.Canvas;

    Heading(1, 780, 22, 'TPdfDocument and TPdfCanvas');
    // a decorative rule: a path outside any element, written as an artifact
    C.SetRGBStrokeColor($5A2D14);
    C.SetLineWidth(1.5);
    C.MoveTo(LEFT, 770);
    C.LineTo(539, 770);
    C.Stroke;

    C.BeginStructContent(psrP);
    C.SetFont(Sans, 11, [], DEFAULT_CHARSET);
    C.SetRGBFillColor(0);
    DrawText(LEFT, 745, 'This page is drawn with the layer 1 API alone, in PDF points.');
    DrawText(LEFT, 730, 'Y counts from the bottom edge of the page, and each Y given is a baseline.');
    C.EndStructContent;

    Heading(2, 690, 15, 'Text in embedded TrueType faces');
    C.BeginStructContent(psrP);
    C.SetRGBFillColor(0);
    C.SetFont(Sans, 12, [], DEFAULT_CHARSET);
    DrawText(LEFT, 665, Sans + ' 12 pt: The quick brown fox jumps over the lazy dog.');
    C.SetFont(Sans, 12, [pfsBold], DEFAULT_CHARSET);
    DrawText(LEFT, 647, Sans + ' Bold 12 pt: bold text.');
    C.SetFont(Serif, 12, [pfsItalic], DEFAULT_CHARSET);
    DrawText(LEFT, 629, Serif + ' Italic 12 pt: a classic serif face.');
    C.SetFont(Mono, 11, [], DEFAULT_CHARSET);
    DrawText(LEFT, 611, Mono + ' 11 pt: function Foo: integer;');
    C.SetFont(Sans, 12, [], DEFAULT_CHARSET);
    DrawText(LEFT, 593, UMLAUTS);
    C.EndStructContent;

    Heading(2, 553, 15, 'Lines and rectangles');
    C.BeginStructContent(psrP);
    C.SetFont(Sans, 11, [], DEFAULT_CHARSET);
    C.SetRGBFillColor(0);
    DrawText(LEFT, 530, 'The chart below is one Figure element with an alternate text.');
    C.EndStructContent;
    // a Figure: its paths are real content, described by the /Alt text
    C.BeginStructContent(psrFigure,
      'Bar chart with four bars of the values 40, 75, 55 and 90 on a frame ' +
      'with five horizontal grid lines');
    C.SetRGBStrokeColor($A0A0A0);
    C.SetLineWidth(0.5);
    for i := 0 to 4 do
    begin
      C.MoveTo(LEFT, 330 + i * 40);
      C.LineTo(LEFT + 300, 330 + i * 40);
    end;
    C.Stroke;
    for i := 0 to high(BAR_VALUES) do
    begin
      C.SetRGBFillColor(BAR_COLORS[i]);
      C.Rectangle(LEFT + 20 + i * 70, 330, 50, BAR_VALUES[i] * 160 / 100);
      C.Fill;
    end;
    C.SetRGBStrokeColor(0);
    C.SetLineWidth(1);
    C.Rectangle(LEFT, 330, 300, 160);
    C.Stroke;
    C.EndStructContent;

    // a running footer is no content either, but text needs the explicit mark
    C.BeginArtifact;
    C.SetFont(Sans, 9, [], DEFAULT_CHARSET);
    C.SetRGBFillColor($808080);
    DrawText(LEFT, 40, 'mORMot2 PDF Cross-Platform - layer1_demo');
    C.EndArtifact;

    Doc.SaveToFile(PdfFileName);
    writeln('PDF saved to ', PdfFileName);
  finally
    Doc.Free;
  end;
end.
