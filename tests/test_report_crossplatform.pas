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
  {$IFDEF MSWINDOWS}
  CheckEqual('Arial', REPORT_FONT_SANS, 'Windows SANS = Arial');
  CheckEqual('Times New Roman', REPORT_FONT_SERIF, 'Windows SERIF = Times New Roman');
  CheckEqual('Courier New', REPORT_FONT_MONO, 'Windows MONO = Courier New');
  {$ELSE}
  CheckEqual('Liberation Sans', REPORT_FONT_SANS, 'Unix SANS = Liberation Sans');
  CheckEqual('Liberation Serif', REPORT_FONT_SERIF, 'Unix SERIF = Liberation Serif');
  CheckEqual('Liberation Mono', REPORT_FONT_MONO, 'Unix MONO = Liberation Mono');
  {$ENDIF}
end;

end.
