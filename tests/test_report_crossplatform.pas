/// TGDIPages cross-platform report engine unit tests
// - tests command recording, page management, text measurement helpers
// - no GUI required: TGDIPages.Create(nil) works headless (no HWND created)
// - migrated to TSynTestCase framework for mORMot2 compatibility
unit test_report_crossplatform;

{$IFDEF FPC}
  {$mode delphi}
  {$H+}
{$ENDIF}

interface

uses
  {$ifdef FPC}
  Interfaces,   // registers the widgetset (Win32 on Windows, GTK2/Cocoa on Unix)
  {$endif FPC}
  Classes,
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.core.test,
  mormot.ui.report;  // includes TPrinterOrientation re-export

type
  /// TGDIPages report engine test cases
  TReportTests = class(TSynTestCase)
  published
    procedure TestMMHelpers;
    procedure TestDrawCommandRecording;
    procedure TestMultiplePages;
    procedure TestSaveRestoreLayout;
    procedure TestSaveLayoutStack;
    procedure TestPageDimensions;
    procedure TestDrawLine;
    procedure TestDrawFilledRect;
    procedure TestTextAlignment;
    procedure TestTextAlignmentXPosition;
    procedure TestMoveToNextLine;
    procedure TestBeginEndTableRestoresLayout;
    procedure TestFontConstants;
    procedure TestPlatformIndependentMetrics;
    procedure TestTaggedRepeatedHeaderAndTitle;
    procedure TestTableFooterRow;
    procedure TestTableGroupsAcrossPages;
    procedure TestListItemBullet;
  end;

implementation

procedure TReportTests.TestMMHelpers;
begin
  // 2540 units (= 1 inch) at 96 DPI → 96 pixels
  CheckEqual(96,  MMToPixels(2540, 96),  'MMToPixels(2540,96)');
  // half inch at 96 DPI → 48 pixels (MulDiv rounding)
  CheckEqual(48,  MMToPixels(1270, 96),  'MMToPixels(1270,96)');
  // A4 width 21000 units at 96 DPI → 794 pixels (MulDiv rounding)
  CheckEqual(794, MMToPixels(21000, 96), 'A4 width @ 96 DPI');
  // round-trip: PixelsToMM(MMToPixels(x,dpi),dpi) ≈ x  (MulDiv precision)
  CheckEqual(2540, PixelsToMM(MMToPixels(2540, 96), 96), 'round-trip 2540');
end;

procedure TReportTests.TestDrawCommandRecording;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.SetFont('Arial', 12);
    Report.DrawText(100, 100, 'Hallo Welt');
    Report.EndDoc;
    CheckEqual(1, Report.PageCount, 'PageCount = 1');
    Check(Length(Report.Pages[0].Commands) > 0, 'Commands not empty');
    CheckEqual(Ord(dckDrawText),
                Ord(Report.Pages[0].Commands[0].Kind), 'Kind = dckDrawText');
    CheckEqual('Hallo Welt',
             Report.Pages[0].Commands[0].Text, 'Text = Hallo Welt');
    CheckEqual(12, Report.Pages[0].Commands[0].FontSize, 'FontSize = 12');
    CheckEqual('Arial',
             Report.Pages[0].Commands[0].FontName, 'FontName = Arial');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestMultiplePages;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawText(0, 0, 'Seite 1');
    Report.NewPage;
    Report.DrawText(0, 0, 'Seite 2');
    Report.NewPage;
    Report.DrawText(0, 0, 'Seite 3');
    Report.EndDoc;
    CheckEqual(3, Report.PageCount, 'PageCount = 3');
    CheckEqual('Seite 1', Report.Pages[0].Commands[0].Text, 'Page 0 text');
    CheckEqual('Seite 2', Report.Pages[1].Commands[0].Text, 'Page 1 text');
    CheckEqual('Seite 3', Report.Pages[2].Commands[0].Text, 'Page 2 text');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestSaveRestoreLayout;
var
  Report: TGDIPages;
  Cmd: TDrawCommand;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.SetFont('Arial', 12);
    Report.TextColor := clBlack;
    Report.SaveLayout;
    // Change font + color
    Report.SetFont('Helvetica', 24);
    Report.TextColor := clRed;
    Report.RestoreLayout;
    // Draw — should use the restored Arial 12 / clBlack
    Report.DrawText(0, 0, 'Restored');
    Report.EndDoc;
    Cmd := Report.Pages[0].Commands[0];
    CheckEqual(12, Cmd.FontSize, 'FontSize restored to 12');
    CheckEqual('Arial', Cmd.FontName, 'FontName restored to Arial');
    CheckEqual(clBlack, Cmd.Color, 'Color restored to clBlack');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestSaveLayoutStack;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.SetFont('Arial', 10);
    Report.SaveLayout;               // depth 1 — Arial 10
    Report.SetFont('Helvetica', 14);
    Report.SaveLayout;               // depth 2 — Helvetica 14
    Report.SetFont('Courier', 18);
    Report.RestoreLayout;            // back to Helvetica 14
    Report.DrawText(0, 0, 'H14');
    Report.RestoreLayout;            // back to Arial 10
    Report.DrawText(0, 200, 'A10');
    Report.EndDoc;
    CheckEqual(14, Report.Pages[0].Commands[0].FontSize, 'Depth-2 restore');
    CheckEqual(10, Report.Pages[0].Commands[1].FontSize, 'Depth-1 restore');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestBeginEndTableRestoresLayout;
var
  Report: TGDIPages;
  Layout: TTableLayout;
  Cmd: TDrawCommand;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    // Setze Font VOR der Tabelle
    Report.SetFont('Arial', 14);
    // Erstelle TTableLayout mit allen erforderlichen Feldern
    FillChar(Layout, SizeOf(Layout), 0);
    SetLength(Layout.ColumnWidths, 1);
    SetLength(Layout.ColumnAligns, 1);
    Layout.ColumnWidths[0] := 17000;  // eine breite Spalte
    Layout.ColumnAligns[0] := tcaLeft;
    Layout.HeaderFontName := 'Arial';
    Layout.HeaderFontSize := 12;
    Layout.BodyFontName := 'Arial';
    Layout.BodyFontSize := 10;
    Layout.HeaderBkColor := clSilver;
    Layout.BodyBkColor := clWhite;
    // BeginTable → SaveLayout (Arial 14 wird gespeichert)
    Report.BeginTable(Layout);
    // Ändere Font innerhalb der Tabelle
    Report.SetFont('Courier', 9);
    // EndTable → RestoreLayout (soll Arial 14 wiederherstellen)
    Report.EndTable;
    // Zeichne Text NACH der Tabelle — muss Arial 14 verwenden
    Report.DrawText(0, 0, 'NachTabelle');
    Report.EndDoc;
    // Letzter Command = DrawText nach EndTable
    Cmd := Report.Pages[0].Commands[High(Report.Pages[0].Commands)];
    CheckEqual('Arial', Cmd.FontName, 'Font nach EndTable = Font vor BeginTable');
    CheckEqual(14, Cmd.FontSize, 'FontSize nach EndTable = 14');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestPageDimensions;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.PaperSize := psA4;
    Report.MarginLeft := 2000;  // 20 mm
    Report.MarginRight := 2000;
    Report.MarginTop := 2000;
    Report.MarginBottom := 2000;
    Report.NewPage;
    // A4 paper: 21000 × 29700; minus 4 × 2000 mm margins
    CheckEqual(17000, Report.PageWidth, 'A4 portrait PageWidth');
    CheckEqual(25700, Report.PageHeight, 'A4 portrait PageHeight');
    Report.EndDoc;
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestDrawLine;
var
  Report: TGDIPages;
  Cmd: TDrawCommand;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawLine(0, 500, 10000, 500, 2, clNavy);
    Report.EndDoc;
    CheckEqual(1, Length(Report.Pages[0].Commands), 'one command');
    Cmd := Report.Pages[0].Commands[0];
    CheckEqual(Ord(dckDrawLine), Ord(Cmd.Kind), 'Kind = dckDrawLine');
    CheckEqual(0, Cmd.X, 'X1 = 0');
    CheckEqual(500, Cmd.Y, 'Y1 = 500');
    CheckEqual(10000, Cmd.X2, 'X2 = 10000');
    CheckEqual(500, Cmd.Y2, 'Y2 = 500');
    CheckEqual(2, Cmd.LineWidth, 'LineWidth = 2');
    CheckEqual(clNavy, Cmd.Color, 'Color = clNavy');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestDrawFilledRect;
var
  Report: TGDIPages;
  Cmd: TDrawCommand;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawFilledRect(100, 200, 3000, 800, clSilver);
    Report.EndDoc;
    CheckEqual(1, Length(Report.Pages[0].Commands), 'one command');
    Cmd := Report.Pages[0].Commands[0];
    CheckEqual(Ord(dckFillRect), Ord(Cmd.Kind), 'Kind = dckFillRect');
    CheckEqual(100, Cmd.X, 'X1');
    CheckEqual(200, Cmd.Y, 'Y1');
    CheckEqual(3000, Cmd.X2, 'X2');
    CheckEqual(800, Cmd.Y2, 'Y2');
    CheckEqual(clSilver, Cmd.Color, 'Color = clSilver');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestTextAlignment;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawText(0, 0, 'Left');         // Align = 0
    Report.DrawTextRight(0, 0, 'Right');   // Align = 1
    Report.DrawTextCenter(0, 0, 'Center'); // Align = 2
    Report.DrawTextAt(500, 0, 'At');       // Align = 0 (same as DrawText)
    Report.EndDoc;
    CheckEqual(0, Report.Pages[0].Commands[0].Align, 'DrawText → left');
    CheckEqual(1, Report.Pages[0].Commands[1].Align, 'DrawTextRight → right');
    CheckEqual(2, Report.Pages[0].Commands[2].Align, 'DrawTextCenter → center');
    CheckEqual(0, Report.Pages[0].Commands[3].Align, 'DrawTextAt → left');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestTextAlignmentXPosition;
var
  Report: TGDIPages;
  Cmd: TDrawCommand;
  PW: Integer;
begin
  // --- Right-Align X=0: Cmd.X = PageWidth - TextWidthMM ---
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawTextRight(0, 0, 'Right');
    Report.EndDoc;
    Cmd := Report.Pages[0].Commands[0];
    PW := Report.PageWidth;
    CheckEqual(PW - Cmd.TextWidthMM, Cmd.X,
      'Right-align X=0: Cmd.X vorberechnet = PageWidth - TextWidth');
  finally
    Report.Free;
  end;

  // --- Right-Align X>0: Cmd.X = X - TextWidthMM ---
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawTextRight(10000, 0, 'Right');
    Report.EndDoc;
    Cmd := Report.Pages[0].Commands[0];
    CheckEqual(10000 - Cmd.TextWidthMM, Cmd.X,
      'Right-align X>0: Cmd.X = X - TextWidth');
  finally
    Report.Free;
  end;

  // --- Center-Align X=0: Cmd.X = (PageWidth - TextWidthMM) div 2 ---
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawTextCenter(0, 0, 'Center');
    Report.EndDoc;
    Cmd := Report.Pages[0].Commands[0];
    PW := Report.PageWidth;
    CheckEqual((PW - Cmd.TextWidthMM) div 2, Cmd.X,
      'Center-align X=0: Cmd.X = (PageWidth - TextWidth) div 2');
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestMoveToNextLine;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    CheckEqual(0, Report.CurrentY, 'CurrentY starts at 0');
    Report.MoveToNextLine(350);
    CheckEqual(350, Report.CurrentY, 'After +350');
    Report.MoveToNextLine(200);
    CheckEqual(550, Report.CurrentY, 'After +200');
    { AddVerticalSpace takes millimetres, MoveToNextLine 1/100 mm — both land
      in the same fCurrentY, so 5 mm must be 500 units }
    Report.AddVerticalSpace(5);
    CheckEqual(1050, Report.CurrentY, 'After +5 mm');
    Report.EndDoc;
  finally
    Report.Free;
  end;
end;

procedure TReportTests.TestFontConstants;
begin
  Check(REPORT_FONT_SANS  <> '', 'REPORT_FONT_SANS not empty');
  Check(REPORT_FONT_SERIF <> '', 'REPORT_FONT_SERIF not empty');
  Check(REPORT_FONT_MONO  <> '', 'REPORT_FONT_MONO not empty');
  { the three branches must match mormot.ui.report.pas:48-52 one for one -
    this test expected Arial/Times New Roman/Courier New long after the
    constants moved to the ClearType families, and had no DARWIN branch at
    all, so it failed on Windows and would have failed on macOS too }
  {$IFDEF MSWINDOWS}
  CheckEqual('Calibri', REPORT_FONT_SANS, 'Windows SANS = Calibri');
  CheckEqual('Cambria', REPORT_FONT_SERIF, 'Windows SERIF = Cambria');
  CheckEqual('Consolas', REPORT_FONT_MONO, 'Windows MONO = Consolas');
  {$ELSE}
  {$IFDEF DARWIN}
  CheckEqual('Trebuchet MS', REPORT_FONT_SANS, 'macOS SANS = Trebuchet MS');
  CheckEqual('Georgia', REPORT_FONT_SERIF, 'macOS SERIF = Georgia');
  CheckEqual('Andale Mono', REPORT_FONT_MONO, 'macOS MONO = Andale Mono');
  {$ELSE}
  CheckEqual('Liberation Sans', REPORT_FONT_SANS, 'Unix SANS = Liberation Sans');
  CheckEqual('Liberation Serif', REPORT_FONT_SERIF, 'Unix SERIF = Liberation Serif');
  CheckEqual('Liberation Mono', REPORT_FONT_MONO, 'Unix MONO = Liberation Mono');
  {$ENDIF DARWIN}
  {$ENDIF MSWINDOWS}
end;

procedure TReportTests.TestTaggedRepeatedHeaderAndTitle;
var
  Report: TGDIPages;
  Layout: TTableLayout;
  MS: TMemoryStream;
  s: RawByteString;
  i, p, Repeats, FirstPageRepeats: Integer;
begin
  Report := TGDIPages.Create(nil);
  MS := TMemoryStream.Create;
  try
    Report.ExportPdfTagged := true;
    Report.NewPage;
    { no Title set: the first H1 has to name the document (B-10) }
    Report.DrawHeading(1, 'Quarterly R&D');
    FillChar(Layout, SizeOf(Layout), 0);
    SetLength(Layout.ColumnWidths, 2);
    SetLength(Layout.ColumnAligns, 2);
    Layout.ColumnWidths[0] := 5000;
    Layout.ColumnWidths[1] := 5000;
    Layout.ColumnAligns[0] := tcaLeft;
    Layout.ColumnAligns[1] := tcaRight;
    Layout.HeaderBkColor := clSilver;
    Layout.BodyBkColor := clWhite;
    Report.BeginTable(Layout);
    Report.DrawTableHeader(['Item', 'Value']);
    for i := 1 to 150 do
      Report.DrawTableRow(['Row ' + IntToStr(i), IntToStr(i * 10)]);
    Report.EndTable;
    Report.EndDoc;
    Check(Report.PageCount > 1, 'the table paginates');
    { the header row repeated on a continuation page is recorded apart from
      the original, so the export can mark it as an artifact }
    Repeats := 0;
    FirstPageRepeats := 0;
    for p := 0 to Report.PageCount - 1 do
      for i := 0 to High(Report.Pages[p].Commands) do
        if (Report.Pages[p].Commands[i].Kind = dckBeginTR) and
           (Report.Pages[p].Commands[i].Color = 2) then
        begin
          Inc(Repeats);
          if p = 0 then
            Inc(FirstPageRepeats);
        end;
    CheckEqual(Report.PageCount - 1, Repeats, 'one repeated header per continuation page');
    CheckEqual(0, FirstPageRepeats, 'the original header row is tagged');
    { BeginArtifact/EndArtifact and the struct stack stay balanced, or the
      export raises and returns false }
    Check(Report.ExportPdfStream(MS), 'tagged export succeeds');
    SetLength(s, MS.Size);
    MS.Position := 0;
    MS.Read(pointer(s)^, MS.Size);
    Check(Pos(RawByteString('<rdf:li xml:lang="x-default">Quarterly R&amp;D</rdf:li>'), s) > 0,
      'dc:title falls back to the first H1');
  finally
    MS.Free;
    Report.Free;
  end;
end;

procedure TReportTests.TestPlatformIndependentMetrics;
const
  { Adobe AFM advances of the base-14 Helvetica, in 1000-per-em units:
    H=722 e=556 l=222 l=222 o=556 -> 'Hello' = 2278, space = 278.
    Taken from the AFM, not from our own code, so this test fails if the
    engine ever measures with something other than the font the PDF uses. }
  W_HELLO = 2278;
  W_SPACE = 278;
  SIZE    = 10;
  FACTOR  = 1.1;
var
  Report: TGDIPages;
  ExpectedW, ExpectedLH, PairW: Integer;
  Lines: Integer;

  function CountTextCmds(P: Integer): Integer;
  var
    j: Integer;
  begin
    Result := 0;
    for j := 0 to High(Report.Pages[P].Commands) do
      if Report.Pages[P].Commands[j].Kind = dckDrawText then
        Inc(Result);
  end;

begin
  { PDF points -> 1/100 mm is x 2540/72 }
  ExpectedW  := Round(W_HELLO * SIZE / 1000 * 2540 / 72);
  ExpectedLH := Round(SIZE * FACTOR * 2540 / 72);
  PairW      := Round((W_HELLO * 2 + W_SPACE) * SIZE / 1000 * 2540 / 72);
  Report := TGDIPages.Create(nil);
  try
    Report.ExportPdfStandardFonts := true; // base-14 AFM widths on every OS
    Report.PaperSize   := psA4;
    Report.Orientation := poPortrait;
    Report.LineHeightFactor := FACTOR;
    Report.NewPage;
    Report.SetFont('Helvetica', SIZE);
    { right-aligned text is placed at PageWidth - TextWidth, so the recorded X
      reveals the width the layout measured }
    Report.DrawTextRight(0, 0, 'Hello');
    CheckEqual(Report.PageWidth - ExpectedW, Report.Pages[0].Commands[0].X,
      'Helvetica 10pt measures Hello with its AFM width');
    { line breaking happens at the same place on every platform: the pair fits
      just above its own width and wraps just below it }
    Report.ForceNewPage;
    Report.DrawTextWrapped(0, PairW + 100, Report.CurrentY, 'Hello Hello');
    CheckEqual(1, CountTextCmds(1), 'pair fits on one line');
    Report.ForceNewPage;
    Report.DrawTextWrapped(0, PairW - 100, Report.CurrentY, 'Hello Hello');
    Lines := CountTextCmds(2);
    CheckEqual(2, Lines, 'pair wraps into two lines');
    { and those lines are exactly one line height apart }
    CheckEqual(ExpectedLH,
      Report.Pages[2].Commands[1].Y - Report.Pages[2].Commands[0].Y,
      'line advance is FontSize x LineHeightFactor, not a widgetset height');
    CheckEqual('Hello', Report.Pages[2].Commands[0].Text, 'first wrapped line');
    CheckEqual('Hello', Report.Pages[2].Commands[1].Text, 'second wrapped line');
    Report.EndDoc;
  finally
    Report.Free;
  end;
end;


procedure TReportTests.TestTableFooterRow;
var
  Report: TGDIPages;
  Layout: TTableLayout;
  MS: TMemoryStream;
  i, p, Footers, HeaderBk, FooterBk, LastTR: Integer;
begin
  Report := TGDIPages.Create(nil);
  MS := TMemoryStream.Create;
  try
    Report.ExportPdfTagged := true;
    Report.NewPage;
    Report.DrawHeading(1, 'Order List');
    FillChar(Layout, SizeOf(Layout), 0);
    SetLength(Layout.ColumnWidths, 2);
    SetLength(Layout.ColumnAligns, 2);
    Layout.ColumnWidths[0] := 5000;
    Layout.ColumnWidths[1] := 5000;
    Layout.ColumnAligns[0] := tcaLeft;
    Layout.ColumnAligns[1] := tcaRight;
    Layout.HeaderBkColor := clSilver;
    Layout.BodyBkColor := clWhite;
    Report.BeginTable(Layout);
    Report.DrawTableHeader(['Item', 'Value']);
    for i := 1 to 3 do
      Report.DrawTableRow(['Row ' + IntToStr(i), IntToStr(i * 10)]);
    { the Footer* fields are unset, so the footer takes the header's look }
    Report.DrawTableFooter(['Total', '60']);
    Report.EndTable;
    Report.EndDoc;
    { exactly one footer row (dckBeginTR.Color = 3), and it is the last row }
    Footers := 0;
    LastTR := -1;
    HeaderBk := 0;
    FooterBk := -1;
    for p := 0 to Report.PageCount - 1 do
      for i := 0 to High(Report.Pages[p].Commands) do
        with Report.Pages[p].Commands[i] do
          if Kind = dckBeginTR then
          begin
            LastTR := Color;
            if Color = 3 then
              inc(Footers);
          end
          else if Kind = dckFillRect then
          begin
            if (LastTR = 1) and (HeaderBk = 0) then
              HeaderBk := Color;
            if (LastTR = 3) and (FooterBk < 0) then
              FooterBk := Color;
          end;
    CheckEqual(1, Footers, 'one footer row');
    CheckEqual(3, LastTR, 'the footer is the last row of the table');
    CheckEqual(HeaderBk, FooterBk, 'an unset footer style follows the header');
    { the THead/TBody/TFoot groups have to be opened and closed in order, or
      the struct stack is unbalanced and the export raises }
    Check(Report.ExportPdfStream(MS), 'tagged export with a footer succeeds');
  finally
    MS.Free;
    Report.Free;
  end;
end;


procedure TReportTests.TestTableGroupsAcrossPages;
var
  Report: TGDIPages;
  Layout: TTableLayout;
  MS: TMemoryStream;
  i, p, Repeats: Integer;
begin
  Report := TGDIPages.Create(nil);
  MS := TMemoryStream.Create;
  try
    Report.ExportPdfTagged := true;
    Report.NewPage;
    Report.DrawHeading(1, 'Long List');
    FillChar(Layout, SizeOf(Layout), 0);
    SetLength(Layout.ColumnWidths, 2);
    SetLength(Layout.ColumnAligns, 2);
    Layout.ColumnWidths[0] := 5000;
    Layout.ColumnWidths[1] := 5000;
    Layout.HeaderBkColor := clSilver;
    Layout.BodyBkColor := clWhite;
    Report.BeginTable(Layout);
    Report.DrawTableHeader(['Item', 'Value']);
    for i := 1 to 150 do
      Report.DrawTableRow(['Row ' + IntToStr(i), IntToStr(i * 10)]);
    Report.DrawTableFooter(['Total', '113250']);
    Report.EndTable;
    Report.EndDoc;
    Check(Report.PageCount > 1, 'the table paginates');
    Repeats := 0;
    for p := 0 to Report.PageCount - 1 do
      for i := 0 to High(Report.Pages[p].Commands) do
        if (Report.Pages[p].Commands[i].Kind = dckBeginTR) and
           (Report.Pages[p].Commands[i].Color = 2) then
          inc(Repeats);
    Check(Repeats > 0, 'the header row is repeated');
    { A repeated header is an artifact and must not open a second THead, and
      the TBody stays open across the page break: otherwise a struct element
      is left open and the export raises instead of returning true (R-14) }
    Check(Report.ExportPdfStream(MS), 'row groups stay balanced across pages');
  finally
    MS.Free;
    Report.Free;
  end;
end;

procedure TReportTests.TestListItemBullet;
var
  Report: TGDIPages;
  i: Integer;
  t: RawByteString;
begin
  // the default bullet has to reach the command as UTF-8 bytes: as the
  // default value '• ' of a parameter, compiled under CODEPAGE UTF8, it was
  // converted at the call site and arrived as '?'
  Report := TGDIPages.Create(nil);
  try
    Report.NewPage;
    Report.DrawListItem(800, Report.CurrentY, 'Item');
    Report.EndDoc;
    t := '';
    for i := 0 to High(Report.Pages[0].Commands) do
      if Report.Pages[0].Commands[i].Kind = dckDrawText then
      begin
        t := Report.Pages[0].Commands[i].Text;
        break;
      end;
    CheckEqual(8, Length(t), 'bullet, space and item');
    Check((Length(t) >= 4) and (t[1] = #$E2) and (t[2] = #$80) and (t[3] = #$A2) and (t[4] = ' '),
      'U+2022 as UTF-8');
  finally
    Report.Free;
  end;
end;

end.
