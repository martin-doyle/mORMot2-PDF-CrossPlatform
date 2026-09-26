/// TGDIPages coordinate system and margin validation tests
unit test_report_coordinates;

interface

{$I mormot.defines.inc}

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
  /// TGDIPages coordinate system and margin validation test cases
  TCoordinateTests = class(TSynTestCase)
  published
    procedure TestA4WithMargins;
    procedure TestDifferentMargins;
    procedure TestPageDimensionConsistency;
    procedure TestMarginModification;
    procedure TestParagraphWrapsWithinPageWidth;
  end;

implementation

procedure TCoordinateTests.TestA4WithMargins;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    { Setup }
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;    { 15mm }
    Report.MarginRight := 1500;   { 15mm }
    Report.MarginTop := 1500;     { 15mm }
    Report.MarginBottom := 1500;  { 15mm }
    Report.NewPage;

    { Expected: A4 210x297 - (15+15)x(15+15) = 180x267 mm }
    CheckEqual(18000, Report.PageWidth, 'A4 PageWidth with 15mm margins');
    CheckEqual(26700, Report.PageHeight, 'A4 PageHeight with 15mm margins');
    CheckEqual(1500, Report.MarginLeft, 'MarginLeft');
    CheckEqual(1500, Report.MarginRight, 'MarginRight');
    CheckEqual(1500, Report.MarginTop, 'MarginTop');
    CheckEqual(1500, Report.MarginBottom, 'MarginBottom');
  finally
    Report.Free;
  end;
end;

procedure TCoordinateTests.TestDifferentMargins;
var
  Report: TGDIPages;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1000;    { 10mm }
    Report.MarginRight := 2000;   { 20mm }
    Report.MarginTop := 1500;     { 15mm }
    Report.MarginBottom := 2500;  { 25mm }
    Report.NewPage;

    { Expected: 210-(10+20) = 180mm width, 297-(15+25) = 257mm height }
    CheckEqual(18000, Report.PageWidth, 'PageWidth with asymmetric margins');
    CheckEqual(25700, Report.PageHeight, 'PageHeight with asymmetric margins');
  finally
    Report.Free;
  end;
end;

procedure TCoordinateTests.TestPageDimensionConsistency;
var
  Report1, Report2: TGDIPages;
begin
  Report1 := TGDIPages.Create(nil);
  Report2 := TGDIPages.Create(nil);
  try
    { Same setup for both }
    Report1.PaperSize := psA4;
    Report1.Orientation := poPortrait;
    Report1.MarginLeft := 1500;
    Report1.MarginRight := 1500;
    Report1.MarginTop := 1500;
    Report1.MarginBottom := 1500;
    Report1.NewPage;

    Report2.PaperSize := psA4;
    Report2.Orientation := poPortrait;
    Report2.MarginLeft := 1500;
    Report2.MarginRight := 1500;
    Report2.MarginTop := 1500;
    Report2.MarginBottom := 1500;
    Report2.NewPage;

    { Both should be identical }
    CheckEqual(Report1.PageWidth, Report2.PageWidth, 'Both PageWidth equal');
    CheckEqual(Report1.PageHeight, Report2.PageHeight, 'Both PageHeight equal');
  finally
    Report1.Free;
    Report2.Free;
  end;
end;

procedure TCoordinateTests.TestMarginModification;
var
  Report: TGDIPages;
  OldWidth, NewWidth: Integer;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;

    { Initial margins 15mm }
    Report.MarginLeft := 1500;
    Report.MarginRight := 1500;
    Report.MarginTop := 1500;
    Report.MarginBottom := 1500;
    Report.NewPage;

    OldWidth := Report.PageWidth;
    CheckEqual(18000, OldWidth, 'Initial PageWidth');

    { Change right margin to 20mm }
    Report.MarginRight := 2000;
    Report.NewPage;

    NewWidth := Report.PageWidth;
    { Expected: 210 - 15 - 20 = 175mm = 17500 }
    CheckEqual(17500, NewWidth, 'PageWidth after margin change');
    Check(NewWidth <> OldWidth, 'PageWidth correctly recalculated');
  finally
    Report.Free;
  end;
end;

procedure TCoordinateTests.TestParagraphWrapsWithinPageWidth;
const
  SENTENCE = 'This is a longer text that should wrap in a standard column ' +
    'width on an A4 page with 15mm margins on all sides.';
var
  Report: TGDIPages;
  Source, Joined: string;
  i, Lines, Unmeasured, W, Widest: Integer;
begin
  Source := SENTENCE + ' ' + SENTENCE + ' ' + SENTENCE + ' ' + SENTENCE;
  Report := TGDIPages.Create(nil);
  try
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;
    Report.MarginRight := 1500;
    Report.MarginTop := 1500;
    Report.MarginBottom := 1500;
    Report.NewPage;
    Report.SetFont(REPORT_FONT_SANS, 11);
    Report.DrawParagraph(Source);
    Report.EndDoc;
    Lines := 0;
    Unmeasured := 0;
    Widest := 0;
    Joined := '';
    for i := 0 to High(Report.Pages[0].Commands) do
      with Report.Pages[0].Commands[i] do
        if Kind = dckDrawText then
        begin
          Inc(Lines);
          { TextWidthMM is measured when the line is recorded, with the
            metrics the layout wrapped it with }
          if TextWidthMM <= 0 then
            Inc(Unmeasured);
          W := X + TextWidthMM;
          if W > Widest then
            Widest := W;
          if Joined <> '' then
            Joined := Joined + ' ';
          Joined := Joined + Trim(Text);
        end;
    Check(Lines > 1, 'the paragraph wraps');
    CheckEqual(0, Unmeasured, 'every line has its width recorded');
    Check(Widest <= Report.PageWidth, 'no line reaches past the right margin');
    CheckEqual(Source, Joined, 'the lines hold every word, in order');
  finally
    Report.Free;
  end;
end;

end.
