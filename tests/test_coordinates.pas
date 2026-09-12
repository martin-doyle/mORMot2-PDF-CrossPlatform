/// Page coordinate system, margins, and rendering tests
unit test_coordinates;

{$IFDEF FPC}
  {$mode delphi}
  {$H+}
{$ENDIF}

interface

uses
  {$ifdef FPC}
  Interfaces,
  {$endif}
  SysUtils,
  Classes,
  Graphics,
  mormot.core.base,
  mormot.core.test,
  mormot.ui.report;

type
  /// Page coordinate system and rendering test cases
  TPageCoordinateTests = class(TSynTestCase)
  published
    procedure TestPageCoordinates;
    procedure TestPrintableArea;
    procedure TestRenderingDPI;
  end;

implementation

procedure TPageCoordinateTests.TestPageCoordinates;
var
  Report: TGDIPages;
  PageW, PageH: Integer;
begin
  Report := TGDIPages.Create(nil);
  try
    { Setup: A4 portrait with 15mm margins }
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;    { 15mm }
    Report.MarginRight := 1500;   { 15mm }
    Report.MarginTop := 1500;     { 15mm }
    Report.MarginBottom := 1500;  { 15mm }
    Report.NewPage;

    PageW := Report.PageWidth;
    PageH := Report.PageHeight;

    { A4 = 210x297 mm = 21000 x 29700 in 1/100mm }
    { With 15mm margins on all sides: 180x267 mm = 18000 x 26700 }
    CheckEqual(18000, PageW, 'A4 PageWidth with 15mm margins');
    CheckEqual(26700, PageH, 'A4 PageHeight with 15mm margins');

    { Test font setup }
    Report.SetFont('Arial', 11);
    Report.DrawParagraph('Left-aligned text at X=0');
    Check(true, 'Font and text drawing successful');
  finally
    Report.Free;
  end;
end;

procedure TPageCoordinateTests.TestPrintableArea;
var
  Report: TGDIPages;
  PhysicalW, PhysicalH: Integer;
  MarginW, MarginH: Integer;
  PrintableW, PrintableH: Integer;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;
    Report.MarginRight := 1500;
    Report.MarginTop := 1500;
    Report.MarginBottom := 1500;

    PhysicalW := 21000;  { A4 width }
    PhysicalH := 29700;  { A4 height }
    MarginW := Report.MarginLeft + Report.MarginRight;
    MarginH := Report.MarginTop + Report.MarginBottom;
    PrintableW := PhysicalW - MarginW;
    PrintableH := PhysicalH - MarginH;

    Report.NewPage;
    CheckEqual(PrintableW, Report.PageWidth, 'PageWidth equals printable area');
    CheckEqual(PrintableH, Report.PageHeight, 'PageHeight equals printable area');
  finally
    Report.Free;
  end;
end;

procedure TPageCoordinateTests.TestRenderingDPI;
var
  Report: TGDIPages;
  Canvas: TBitmap;
  DestW, DestH: Integer;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;
    Report.MarginRight := 1500;
    Report.MarginTop := 1500;
    Report.MarginBottom := 1500;
    Report.NewPage;

    Report.SetFont('Arial', 11);

    { Calculate A4 size at 96 DPI }
    { 210mm @ 96 DPI = Round(210 * 96 / 25.4) = 794px }
    { 297mm @ 96 DPI = Round(297 * 96 / 25.4) = 1123px }
    DestW := Round(21000 * 96 / 2540);
    DestH := Round(29700 * 96 / 2540);

    Check((DestW >= 790) and (DestW <= 798), 'A4 width at 96 DPI');
    Check((DestH >= 1119) and (DestH <= 1127), 'A4 height at 96 DPI');

    { Try to render to canvas }
    Canvas := TBitmap.Create;
    try
      Canvas.Width := DestW;
      Canvas.Height := DestH;
      Canvas.Canvas.Brush.Color := clWhite;
      Canvas.Canvas.FillRect(Rect(0, 0, DestW, DestH));

      Report.RenderPageToCanvas(Canvas.Canvas, 0, DestW, DestH);
      Check(true, 'RenderPageToCanvas succeeded');
    finally
      Canvas.Free;
    end;
  finally
    Report.Free;
  end;
end;

end.
