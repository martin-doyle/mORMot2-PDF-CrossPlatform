program test_wrap_analysis;
{ Test to analyze text wrapping and scaling issues }

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
  mormot.ui.report,
  mormot.ui.pdfcanvas;

procedure AnalyzeWrapAndScaling;
var
  Report: TGDIPages;
  PageWidthMM: Integer;
  PrintableWidthMM: Integer;
  TestText: string;
  TextWidthMM: Integer;
  TextWidthPx96: Integer;
  TextWidthPx120: Integer;
  i: Integer;
  TestTexts: array[0..3] of string;
begin
  TestTexts[0] := 'Short text';
  TestTexts[1] := 'This is a medium length text that might wrap in narrow columns';
  TestTexts[2] := 'This is a longer text that should definitely wrap in a standard column width on an A4 page with 15mm margins on all sides';
  TestTexts[3] := 'Heading Levels (H1 through H6)';

  Report := TGDIPages.Create(nil);
  try
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;
    Report.MarginRight := 1500;
    Report.MarginTop := 1500;
    Report.MarginBottom := 1500;
    Report.NewPage;

    WriteLn('=== TEXT WRAPPING & SCALING ANALYSIS ===');
    WriteLn;

    PageWidthMM := 21000;   { A4 width in 1/100mm }
    PrintableWidthMM := PageWidthMM - Report.MarginLeft - Report.MarginRight;
    WriteLn(Format('Page Width: %d (1/100mm) = %.1f mm', [PageWidthMM, PageWidthMM/100.0]));
    WriteLn(Format('Printable Width (fPageWidth): %d (1/100mm) = %.1f mm',
      [Report.PageWidth, Report.PageWidth/100.0]));
    WriteLn;

    WriteLn('=== TEST TEXTS ===');
    for i := 0 to High(TestTexts) do
    begin
      WriteLn;
      WriteLn(Format('Text %d: "%s"', [i, TestTexts[i]]));

      { Measure at different font sizes and DPIs }
      Report.SetFont('Arial', 11);
      TextWidthMM := Report.MeasureTextWidthMM(TestTexts[i]);
      WriteLn(Format('  Width (Arial 11): %d (1/100mm) = %.1f mm',
        [TextWidthMM, TextWidthMM/100.0]));

      { Calculate pixel width at different DPIs }
      { At 96 DPI: 25.4 mm/inch = 96 px/inch → 1mm ≈ 3.78 px }
      TextWidthPx96 := Round(TextWidthMM * 96 / 2540);
      WriteLn(Format('  Width at 96 DPI: %d pixels', [TextWidthPx96]));

      { At 120 DPI }
      TextWidthPx120 := Round(TextWidthMM * 120 / 2540);
      WriteLn(Format('  Width at 120 DPI: %d pixels', [TextWidthPx120]));

      { Check if it exceeds printable width }
      if TextWidthMM > Report.PageWidth then
        WriteLn(Format('  ⚠ WARNING: Text exceeds printable width by %d (1/100mm) = %.1f mm',
          [TextWidthMM - Report.PageWidth, (TextWidthMM - Report.PageWidth)/100.0]))
      else
        WriteLn(Format('  ✓ Fits in printable width (margin: %d 1/100mm = %.1f mm)',
          [Report.PageWidth - TextWidthMM, (Report.PageWidth - TextWidthMM)/100.0]));
    end;

    WriteLn;
    WriteLn('=== WRAPPING ANALYSIS ===');
    WriteLn('RecordWrappedText uses 96 DPI for all calculations.');
    WriteLn('This creates WYSIWYG between preview and PDF export.');
    WriteLn;
    WriteLn('But if RenderPageToCanvas receives different DPI or scaling,');
    WriteLn('text that fits at 96 DPI might overflow when rendered.');
    WriteLn;

    WriteLn('=== CRITICAL FINDINGS ===');
    WriteLn('1. RecordWrappedText measures text at fixed 96 DPI');
    WriteLn('2. Wrapping width = MaxWidth (passed from DrawParagraph as fPageWidth)');
    WriteLn('3. Final rendering scale in RenderPageToCanvas might differ');
    WriteLn('4. Result: Text wraps correctly, but overflows during rendering');
    WriteLn;

    WriteLn('=== SUGGESTED FIX ===');
    WriteLn('The wrapping calculation is correct. The issue is in rendering.');
    WriteLn('Possible solutions:');
    WriteLn('  A) Clip text to right margin in RenderPageToCanvas');
    WriteLn('  B) Reduce wrapping width by text measurement buffer');
    WriteLn('  C) Change text rendering to use MaxWidth clipping');

  finally
    Report.Free;
  end;
end;

begin
  WriteLn('Text Wrapping and Scaling Analysis');
  WriteLn('====================================');
  WriteLn;
  AnalyzeWrapAndScaling;
  WriteLn;
  WriteLn('Analysis complete.');
end.
