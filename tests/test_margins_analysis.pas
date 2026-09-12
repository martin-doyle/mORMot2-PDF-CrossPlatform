program test_margins_analysis;
{ Test to analyze and verify margin and coordinate calculations in TGDIPages }

{$IFDEF FPC}
  {$mode delphi}
  {$H+}
{$ENDIF}

uses
  {$IFDEF FPC}
  Interfaces,
  {$ENDIF}
  SysUtils,
  Classes,
  Graphics,
  mormot.ui.report;

procedure AnalyzeMarginCalculations;
var
  Report: TGDIPages;
  PageWidthMM: Integer;
  PageHeightMM: Integer;
  PrintableWidthMM: Integer;
  PrintableHeightMM: Integer;
  TestX1, TestX2: Integer;
  TestWidth: Integer;
begin
  Report := TGDIPages.Create(nil);
  try
    { Setup: A4 portrait with 15mm margins on all sides }
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;     { 15mm }
    Report.MarginRight := 1500;    { 15mm }
    Report.MarginTop := 1500;      { 15mm }
    Report.MarginBottom := 1500;   { 15mm }
    Report.NewPage;

    { Collect measurements }
    WriteLn('=== PAGE DIMENSIONS ===');
    WriteLn(Format('PaperSize: A4 Portrait'));
    WriteLn;

    WriteLn('=== MARGIN SETTINGS ===');
    WriteLn(Format('MarginLeft:   %d (1/100mm) = %.1f mm', [Report.MarginLeft, Report.MarginLeft / 100.0]));
    WriteLn(Format('MarginRight:  %d (1/100mm) = %.1f mm', [Report.MarginRight, Report.MarginRight / 100.0]));
    WriteLn(Format('MarginTop:    %d (1/100mm) = %.1f mm', [Report.MarginTop, Report.MarginTop / 100.0]));
    WriteLn(Format('MarginBottom: %d (1/100mm) = %.1f mm', [Report.MarginBottom, Report.MarginBottom / 100.0]));
    WriteLn;

    WriteLn('=== CALCULATED DIMENSIONS ===');
    WriteLn(Format('PageWidth:  %d (1/100mm) = %.1f mm', [Report.PageWidth, Report.PageWidth / 100.0]));
    WriteLn(Format('PageHeight: %d (1/100mm) = %.1f mm', [Report.PageHeight, Report.PageHeight / 100.0]));
    WriteLn;

    { A4 = 210x297 mm }
    PageWidthMM := 21000;   { 210mm in 1/100mm units }
    PageHeightMM := 29700;  { 297mm in 1/100mm units }
    PrintableWidthMM := PageWidthMM - Report.MarginLeft - Report.MarginRight;
    PrintableHeightMM := PageHeightMM - Report.MarginTop - Report.MarginBottom;

    WriteLn('=== EXPECTED VALUES (A4) ===');
    WriteLn(Format('Physical Page Width:  210mm = 21000 (1/100mm)'));
    WriteLn(Format('Physical Page Height: 297mm = 29700 (1/100mm)'));
    WriteLn(Format('Printable Width:  210 - 15 - 15 = 180mm = 18000 (1/100mm)'));
    WriteLn(Format('Printable Height: 297 - 15 - 15 = 267mm = 26700 (1/100mm)'));
    WriteLn;

    WriteLn('=== COORDINATE CONVENTION ===');
    WriteLn('All coordinates in TDrawCommand are RELATIVE to printable area:');
    WriteLn(Format('X ∈ [0, %d] where X=0 is left margin, X=%d is right margin',
      [Report.PageWidth, Report.PageWidth]));
    WriteLn(Format('Y ∈ [0, %d] where Y=0 is top margin, Y=%d is bottom margin',
      [Report.PageHeight, Report.PageHeight]));
    WriteLn;

    WriteLn('=== TEXT WIDTH TEST ===');
    Report.SetFont('Arial', 11);
    TestWidth := Report.MeasureTextWidthMM('This is a test text for measuring');
    WriteLn(Format('Text "This is a test text for measuring" = %d (1/100mm) = %.1f mm',
      [TestWidth, TestWidth / 100.0]));
    WriteLn;

    WriteLn('=== WRAPPING WIDTH CALCULATION ===');
    WriteLn('When DrawParagraph is called with X=0 (left edge):');
    WriteLn(Format('  MaxWidth = fPageWidth - X = %d - 0 = %d (1/100mm)',
      [Report.PageWidth, Report.PageWidth]));
    WriteLn(Format('  This should allow text to use full printable width = 180mm = 18000'));
    WriteLn;

    WriteLn('=== TEXT POSITION TEST ===');
    WriteLn('Drawing text at various X positions:');
    TestX1 := 0;
    WriteLn(Format('  X=%d (left edge):    Should start at left margin', [TestX1]));

    TestX2 := Report.PageWidth div 2;
    WriteLn(Format('  X=%d (center):       Should be at page center', [TestX2]));

    TestX2 := Report.PageWidth - 2000;
    WriteLn(Format('  X=%d (near right):   Should be 20mm from right margin', [TestX2]));
    WriteLn;

    WriteLn('=== CRITICAL QUESTION ===');
    WriteLn('Is RenderPageToCanvas applying margins correctly?');
    WriteLn('When rendering:');
    WriteLn('  - OffsetX should position text within the margin boundaries');
    WriteLn('  - ScX() should scale from 1/100mm to screen pixels without double-counting margins');
    WriteLn;

    WriteLn('=== NEXT STEPS ===');
    WriteLn('1. Verify that RenderPageToCanvas ScX() function is correct');
    WriteLn('2. Check that no margin is applied twice (once in OffsetX, once in X coordinate)');
    WriteLn('3. Test text wrapping with actual widths');

  finally
    Report.Free;
  end;
end;

begin
  WriteLn('Margin and Coordinate Analysis Test');
  WriteLn('====================================');
  WriteLn;
  AnalyzeMarginCalculations;
  WriteLn;
  WriteLn('Analysis complete. Check the values above for consistency.');
end.
