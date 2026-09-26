/// Layer 1 Demo — mORMot2 PDF Cross-Platform
// Produces a two-page tagged PDF with TPdfDocument and TPdfCanvas alone - no
// TCanvas bridge, no report engine - so it builds with FPC on every platform
// and with Delphi 7 on Win32 (tests\build_delphi7.bat): text, a figure, and
// a table with header, body and totals row.
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
// - a table is Table / THead, TBody, TFoot / TR / TH, TD, opened by the
//   caller; its fills and rules are drawn before it, outside any element, so
//   they are artifacts, and only the cell text is content
// - the file name carries OS, CPU and compiler, so the FPC and Delphi 7 runs
//   can be compared in one folder
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
  mormot.core.text,   // FormatUtf8
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
  /// the table: top edge, row height, and the right edge of the columns 1..3
  TABLE_TOP = 700;
  ROW_H = 20;
  COL_RIGHT: array[1..3] of single = (330, 430, 533);
  /// 'Unit €' and 'Total €' as UTF-8
  HEADERS: array[0..3] of RawUtf8 = ('Article', 'Qty',
    'Unit '#$E2#$82#$AC, 'Total '#$E2#$82#$AC);
  ROWS: array[0..3, 0..3] of RawUtf8 = (
    ('Bolt M4x10',  '100', '0.05', '5.00'),
    ('Nut M4',      '100', '0.03', '3.00'),
    ('Washer 4 mm', '200', '0.02', '4.00'),
    ('Dowel 8 mm',  '50',  '0.12', '6.00'));
  TOTALS: array[0..3] of RawUtf8 = ('Total', '450', '', '18.00');

var
  Doc: TPdfDocument;
  C: TPdfCanvas;
  SansFont, SerifFont, MonoFont: string;
  Sans, Serif, Mono: RawUtf8;
  i: integer;

{ <demo>_<os>_<cpu>_<compiler>.pdf next to the executable, e.g.
  layer1_demo_windows_x64_free-pascal-3.2.2.pdf or ..._x86_delphi-7.pdf }
function PdfFileName: TFileName;
var
  compiler: RawUtf8;
begin
  compiler := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  result := Executable.ProgramFilePath + Utf8ToString(LowerCase('layer1_demo_' +
    ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' + CPU_ARCH_TEXT + '_' +
    StringReplaceAll(compiler, ' ', '-') + '.pdf'));
end;

procedure DrawText(X, Y: single; const Text: RawUtf8);
var
  W: SynUnicode;
begin
  W := Utf8ToSynUnicode(Text);
  C.TextOutW(X, Y, pointer(W));
end;

{ width in points of Text in the current font, for right alignment }
function TextWidth(const Text: RawUtf8): single;
var
  W: SynUnicode;
begin
  W := Utf8ToSynUnicode(Text);
  result := C.UnicodeTextWidth(pointer(W));
end;

{ one TH or TD; column 0 is left-aligned, the numbers are right-aligned }
procedure Cell(Role: TPdfStructRole; Col: integer; Baseline: single;
  const Text: RawUtf8);
begin
  // an empty cell is still an element, so every row keeps four
  C.BeginStructContent(Role);
  if Text <> '' then
    if Col = 0 then
      DrawText(LEFT + 6, Baseline, Text)
    else
      DrawText(COL_RIGHT[Col] - TextWidth(Text), Baseline, Text);
  C.EndStructContent;
end;

{ baseline of table row Row (0 = header), 6 pt above the row's bottom edge }
function RowBaseline(Row: integer): single;
begin
  result := TABLE_TOP - (Row + 1) * ROW_H + 6;
end;

procedure Footer(Page: integer);
begin
  // a running footer is no content, but text needs the explicit mark
  C.BeginArtifact;
  C.SetFont(Sans, 9, [], DEFAULT_CHARSET);
  C.SetRGBFillColor($808080);
  DrawText(LEFT, 40, FormatUtf8('mORMot2 PDF Cross-Platform - layer1_demo - page %',
    [Page]));
  C.EndArtifact;
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

    Heading(2, 553, 15, 'Paths: rectangles, an ellipse, a curve, lines');
    C.BeginStructContent(psrP);
    C.SetFont(Sans, 11, [], DEFAULT_CHARSET);
    C.SetRGBFillColor(0);
    DrawText(LEFT, 530, 'The shapes below are one Figure element with an alternate text.');
    C.EndStructContent;
    // a Figure: its paths are real content, described by the /Alt text
    C.BeginStructContent(psrFigure,
      'Four shapes in a row - a rectangle, a rounded rectangle, an ellipse ' +
      'and an S-shaped curve - above three lines of increasing width');
    C.SetRGBStrokeColor($5A2D14);
    C.SetLineWidth(1.5);
    C.SetRGBFillColor($E8C8B4);
    C.Rectangle(LEFT, 420, 100, 70);        // x, y (bottom), width, height
    C.FillStroke;
    C.SetRGBFillColor($B4DCF0);
    C.RoundRect(LEFT + 125, 420, LEFT + 225, 490, 16, 16); // two corners
    C.FillStroke;
    C.SetRGBFillColor($C8E6C8);
    C.Ellipse(LEFT + 250, 420, 100, 70);    // the bounding rectangle
    C.FillStroke;
    C.MoveTo(LEFT + 375, 420);              // a cubic Bezier curve
    C.CurveToC(LEFT + 415, 520, LEFT + 443, 390, LEFT + 483, 490);
    C.Stroke;
    for i := 0 to 2 do
    begin
      C.SetLineWidth(0.5 + i * 1.75);       // 0.5, 2.25, 4 pt
      C.MoveTo(LEFT, 390 - i * 22);
      C.LineTo(539, 390 - i * 22);
      C.Stroke;
    end;
    C.EndStructContent;

    Footer(1);

    Doc.AddPage;
    C := Doc.Canvas;
    Heading(2, 780, 15, 'A table with header, body and totals');
    C.BeginStructContent(psrP);
    C.SetFont(Sans, 11, [], DEFAULT_CHARSET);
    C.SetRGBFillColor(0);
    DrawText(LEFT, 755, 'The fills and rules are drawn first, outside any element: artifacts.');
    DrawText(LEFT, 740, 'Then the cells, each a TH or TD inside a TR of THead, TBody or TFoot.');
    C.EndStructContent;

    // the table's decoration: header fill, zebra rows, rules
    C.SetRGBFillColor($5A2D14);
    C.Rectangle(LEFT, TABLE_TOP - ROW_H, 539 - LEFT, ROW_H);
    C.Fill;
    C.SetRGBFillColor($F5EEE8);
    for i := 0 to high(ROWS) do
      if odd(i) then
      begin
        C.Rectangle(LEFT, TABLE_TOP - (i + 2) * ROW_H, 539 - LEFT, ROW_H);
        C.Fill;
      end;
    C.SetRGBStrokeColor($C8C8C8);
    C.SetLineWidth(0.5);
    for i := 2 to high(ROWS) + 1 do
    begin
      C.MoveTo(LEFT, TABLE_TOP - i * ROW_H);
      C.LineTo(539, TABLE_TOP - i * ROW_H);
    end;
    C.Stroke;
    C.SetRGBStrokeColor(0);
    C.SetLineWidth(1);
    C.MoveTo(LEFT, TABLE_TOP - (high(ROWS) + 2) * ROW_H);
    C.LineTo(539, TABLE_TOP - (high(ROWS) + 2) * ROW_H);
    C.Stroke;

    // the table's content: TH get /Scope /Column from the engine
    C.BeginStructContent(psrTable);
    C.BeginStructContent(psrTHead);
    C.BeginStructContent(psrTR);
    C.SetFont(Sans, 11, [pfsBold], DEFAULT_CHARSET);
    C.SetRGBFillColor($FFFFFF);
    for i := 0 to 3 do
      Cell(psrTH, i, RowBaseline(0), HEADERS[i]);
    C.EndStructContent; // TR
    C.EndStructContent; // THead
    C.BeginStructContent(psrTBody);
    C.SetFont(Sans, 11, [], DEFAULT_CHARSET);
    C.SetRGBFillColor(0);
    for i := 0 to high(ROWS) do
    begin
      C.BeginStructContent(psrTR);
      Cell(psrTD, 0, RowBaseline(i + 1), ROWS[i, 0]);
      Cell(psrTD, 1, RowBaseline(i + 1), ROWS[i, 1]);
      Cell(psrTD, 2, RowBaseline(i + 1), ROWS[i, 2]);
      Cell(psrTD, 3, RowBaseline(i + 1), ROWS[i, 3]);
      C.EndStructContent; // TR
    end;
    C.EndStructContent; // TBody
    C.BeginStructContent(psrTFoot);
    C.BeginStructContent(psrTR);
    C.SetFont(Sans, 11, [pfsBold], DEFAULT_CHARSET);
    for i := 0 to 3 do
      Cell(psrTD, i, RowBaseline(high(ROWS) + 2), TOTALS[i]);
    C.EndStructContent; // TR
    C.EndStructContent; // TFoot
    C.EndStructContent; // Table
    Footer(2);

    // false when the file cannot be written, e.g. while a viewer holds it
    if Doc.SaveToFile(PdfFileName) then
      writeln('PDF saved to ', PdfFileName)
    else
    begin
      writeln('Cannot write ', PdfFileName, ' - is it open in a viewer?');
      ExitCode := 1;
    end;
  finally
    Doc.Free;
  end;
end.
