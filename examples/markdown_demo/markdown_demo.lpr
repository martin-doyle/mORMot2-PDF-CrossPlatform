/// Markdown-Style Document Demo — mORMot2 PDF Cross-Platform
// Renders a semantic document with TGDIPages — headings H1-H6, paragraphs,
// quotes, lists, inline runs and a table — as a console app, no GUI.
//
// Worth noting:
// - the same content is rendered twice with two TPageConfig records, to show
//   that margins, font family, size and LineHeightFactor can change per section
// - DrawHeading writes the PDF bookmark PDF/UA expects for a heading
// - the invoice table uses a const TTableLayout and repeats its header row on
//   the page break the 20 data rows force
// - ExportPdfTagged must be set before the first drawing command: the export
//   font flags decide which metrics the layout is measured with
program markdown_demo;

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

type
  { Page rendering configuration }
  TPageConfig = record
    MarginLeft: Integer;
    MarginRight: Integer;
    MarginTop: Integer;
    MarginBottom: Integer;
    HeadingFontName: string;    { Font for H1-H6 headings }
    HeadingFontSize: Integer;
    BodyFontName: string;       { Font for paragraphs and body text }
    BodyFontSize: Integer;
    MonoFontName: string;       { Font for code blocks (Code format) }
    LineHeightFactor: Single;   { Line-height multiplier (default 1.1; try 1.3-1.4 for open layouts) }
    PageLabel: string;
  end;

const
  { Table layout for invoice items - uses current document font when names are empty }
  INVOICE_ITEMS_LAYOUT: TTableLayout = (
    ColumnWidths: [2500, 5000, 5000, 2500];
    ColumnAligns: [tcaLeft, tcaLeft, tcaRight, tcaRight];
    HeaderFontName: '';        { Empty = use current document font }
    HeaderFontSize: 0;         { 0 = use current font size }
    HeaderFontStyle: [fsBold];
    HeaderBkColor: $E0E0E0;
    BodyFontName: '';          { Empty = use current document font }
    BodyFontSize: 0;           { 0 = use current font size }
    BodyFontStyle: [];
    BodyBkColor: $FFFFFF;
    AlternateRowColor: $F5F5F5;
  );

procedure RenderMarkdownPage(Report: TGDIPages; const Config: TPageConfig);
var
  Fmt: TReportFormat;
  H1Size: Integer;
begin
  { Set page parameters }
  Report.MarginLeft       := Config.MarginLeft;
  Report.MarginRight      := Config.MarginRight;
  Report.MarginTop        := Config.MarginTop;
  Report.MarginBottom     := Config.MarginBottom;
  // LineHeightFactor controls vertical spacing between text lines (default = 1.1).
  // A higher value opens up the layout without changing font size.
  Report.LineHeightFactor := Config.LineHeightFactor;

  { Adjust heading font sizes proportionally }
  { Base ratios from default format registry (H1=28pt is base) }
  H1Size := Config.HeadingFontSize;

  Fmt.FontName := Config.HeadingFontName;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;

  { H1: 28pt (base) }
  Fmt.FontSize := H1Size;
  Fmt.SpaceAfter := 800;
  Fmt.SpaceBefore := 600;
  Report.DefineFormat('H1', Fmt);

  { H2: 75% of H1 }
  Fmt.FontSize := (H1Size * 75) div 100;
  Fmt.SpaceAfter := 600;
  Fmt.SpaceBefore := 400;
  Report.DefineFormat('H2', Fmt);

  { H3: 57% of H1 }
  Fmt.FontSize := (H1Size * 57) div 100;
  Fmt.SpaceAfter := 400;
  Fmt.SpaceBefore := 300;
  Report.DefineFormat('H3', Fmt);

  { H4: 46% of H1 }
  Fmt.FontSize := (H1Size * 46) div 100;
  Fmt.SpaceAfter := 200;
  Fmt.SpaceBefore := 200;
  Report.DefineFormat('H4', Fmt);

  { H5: 39% of H1 }
  Fmt.FontSize := (H1Size * 39) div 100;
  Fmt.SpaceAfter := 200;
  Fmt.SpaceBefore := 100;
  Report.DefineFormat('H5', Fmt);

  { H6: 36% of H1 }
  Fmt.FontSize := (H1Size * 36) div 100;
  Fmt.SpaceAfter := 100;
  Fmt.SpaceBefore := 100;
  Report.DefineFormat('H6', Fmt);

  { P: Normal paragraph }
  Fmt.FontName := Config.BodyFontName;
  Fmt.FontSize := Config.BodyFontSize;
  Fmt.FontStyle := [];
  Fmt.SpaceAfter := 300;
  Fmt.SpaceBefore := 0;
  Report.DefineFormat('P', Fmt);

  { Strong: Bold text (same size as P) }
  Fmt.FontName := Config.BodyFontName;
  Fmt.FontSize := Config.BodyFontSize;
  Fmt.FontStyle := [fsBold];
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  Report.DefineFormat('Strong', Fmt);

  { Em: Italic text (same size as P) }
  Fmt.FontName := Config.BodyFontName;
  Fmt.FontSize := Config.BodyFontSize;
  Fmt.FontStyle := [fsItalic];
  Report.DefineFormat('Em', Fmt);

  { Code: Monospace code text, maroon color }
  Fmt.FontName := Config.MonoFontName;
  Fmt.FontSize := 0;  { 0 = proportional (90% of current font size) }
  Fmt.FontStyle := [];
  Fmt.Color := clMaroon;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  Report.DefineFormat('Code', Fmt);

  { Quote: Block quote, italic body font, gray color }
  Fmt.FontName := Config.BodyFontName;
  Fmt.FontSize := Config.BodyFontSize;
  Fmt.FontStyle := [fsItalic];
  Fmt.Color := $666666;
  Fmt.SpaceAfter := 300;
  Fmt.SpaceBefore := 200;
  Report.DefineFormat('Quote', Fmt);

  { LI: List item (same as P) }
  Fmt.FontName := Config.BodyFontName;
  Fmt.FontSize := Config.BodyFontSize;
  Fmt.FontStyle := [];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 100;
  Fmt.SpaceBefore := 0;
  Report.DefineFormat('LI', Fmt);

  { Caption: Footer text (smaller than body) }
  Fmt.FontName := Config.BodyFontName;
  Fmt.FontSize := (Config.BodyFontSize * 80) div 100;  { 80% of body size }
  Fmt.FontStyle := [];
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 200;
  Report.DefineFormat('Caption', Fmt);

  Report.NewPage;

  { Set the default body font for this page (ensures SaveLayout/RestoreLayout works correctly) }
  Report.SetFont(Config.BodyFontName, Config.BodyFontSize);

  { === H1: Main Title === }
  Report.DrawHeading(1, 'Markdown-Style Formatting Demo');

  Report.DrawParagraph(
    'This document showcases all Phase 5 formatting features: headings, inline styles, and structured content.');

  { === H2: Introduction === }
  Report.DrawHeading(2, 'Introduction');

  Report.DrawParagraph(
    'Phase 5 adds comprehensive Markdown-style formatting to TGDIPages, including 6-level headings with automatic PDF bookmarks, inline formatting for emphasis, and structured document elements.');

  { === H2: Heading Levels === }
  Report.DrawHeading(2, 'Heading Levels (H1 through H6)');

  Report.DrawParagraph(
    'Each heading level has a predefined format with appropriate font sizes and weights. All headings become PDF bookmarks.');

  Report.DrawHeading(3, 'H3: Subsection Example');
  Report.DrawText(0, Report.CurrentY, 'This is under an H3 heading');
  Report.MoveToNextLine(800);

  Report.DrawHeading(4, 'H4: Sub-subsection');
  Report.DrawText(0, Report.CurrentY, 'This is under an H4 heading');
  Report.MoveToNextLine(800);

  Report.DrawHeading(5, 'H5: Detailed Topic');
  Report.DrawText(0, Report.CurrentY, 'This is under an H5 heading');
  Report.MoveToNextLine(800);

  Report.DrawHeading(6, 'H6: Smallest Heading');
  Report.DrawText(0, Report.CurrentY, 'This is under an H6 heading');
  Report.MoveToNextLine(800);

  { === H2: Inline Formatting === }
  Report.DrawHeading(2, 'Inline Formatting');

  { Using new inline functions without coordinates - X advances automatically }
  Report.CurrentX := 0;  { reset X for inline formatting }
  Report.DrawText('Inline styles like ');
  Report.DrawStrong('bold');
  Report.DrawText(', ');
  Report.DrawEm('italic');
  Report.DrawText(', ');
  Report.DrawCode('code');
  Report.DrawText(' and ');
  Report.DrawLink('links');
  Report.DrawText(' can be mixed inline.');
  Report.MoveToNextLine(800);

  { === H2: Text Blocks === }
  Report.DrawHeading(2, 'Text Blocks');

  Report.DrawText(0, Report.CurrentY, 'Block elements auto-advance CurrentY:');
  Report.MoveToNextLine(800);

  Report.DrawQuote(
    '"The best way to predict the future is to invent it." — Alan Kay');

  Report.DrawText(0, Report.CurrentY, 'List example:');
  Report.MoveToNextLine(500);
  Report.DrawListItem(800, Report.CurrentY, 'First item in list');
  Report.DrawListItem(800, Report.CurrentY, 'Second item');
  Report.DrawListItem(800, Report.CurrentY, 'Third item');
  Report.MoveToNextLine(500);

  { === H2: Code Examples === }
  Report.DrawHeading(2, 'Code Example');

  Report.DrawText(500, Report.CurrentY, 'Pascal code sample:');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, 'Report.DrawHeading(1, ''Title'');');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, 'Report.DrawStrong(x, y, ''Bold'');');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, 'Report.DrawQuote(x, w, y, ''Quote'');');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, 'Report.DrawParagraph(x, w, y, ''Text'');');
  Report.MoveToNextLine(800);

  { === H2: Custom Formats === }
  Report.DrawHeading(2, 'Custom Format Definition');

  Report.DrawParagraph(
    'All formats are customizable. You can define custom formats before creating pages:');

  Report.DrawCode(800, Report.CurrentY, 'var CustomFormat: TReportFormat;');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, 'begin');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, '  CustomFormat.FontName := ''Courier'';');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, '  CustomFormat.FontSize := 16;');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, '  Report.DefineFormat(''MyFormat'', CustomFormat);');
  Report.MoveToNextLine(500);
  Report.DrawCode(800, Report.CurrentY, 'end;');
  Report.MoveToNextLine(800);

  { === H2: PDF Bookmarks === }
  Report.DrawHeading(2, 'PDF Bookmarks');

  Report.DrawParagraph(
    'All headings (H1 through H6) automatically create PDF bookmarks/outlines. Open this PDF in any reader and check the Bookmarks panel to navigate.');

  { === H2: Tables === }
  Report.DrawHeading(2, 'Tables — Flexible Layout');

  Report.DrawParagraph(
    'Tables are defined with flexible layouts (column widths, fonts, colors) and rendered row-by-row with automatic page breaks and alternating colors.');

  { Draw table with 20 rows — enough to cross a page boundary and demonstrate
    automatic table header repetition (R-9): the header is re-drawn at the top
    of every continuation page without any extra code. }
  Report.BeginTable(INVOICE_ITEMS_LAYOUT);
  Report.DrawTableHeader(['Date', 'Description', 'Quantity', 'Price']);
  Report.DrawTableRow(['2026-03-01', 'Professional Services',  '10', '$1,500.00']);
  Report.DrawTableRow(['2026-03-02', 'Software License',        '5',   '$500.00']);
  Report.DrawTableRow(['2026-03-03', 'Consulting Hours',         '8',   '$960.00']);
  Report.DrawTableRow(['2026-03-04', 'Support Package',          '1',   '$250.00']);
  Report.DrawTableRow(['2026-03-05', 'Training Session',         '6',   '$900.00']);
  Report.DrawTableRow(['2026-03-06', 'Hardware Procurement',    '12', '$2,400.00']);
  Report.DrawTableRow(['2026-03-07', 'Network Setup',            '4',   '$600.00']);
  Report.DrawTableRow(['2026-03-08', 'Security Audit',           '3',   '$900.00']);
  Report.DrawTableRow(['2026-03-09', 'Documentation',            '8',   '$800.00']);
  Report.DrawTableRow(['2026-03-10', 'Code Review',              '5',   '$750.00']);
  Report.DrawTableRow(['2026-03-11', 'Deployment Service',       '2',   '$300.00']);
  Report.DrawTableRow(['2026-03-12', 'Database Migration',       '6', '$1,200.00']);
  Report.DrawTableRow(['2026-03-13', 'Performance Tuning',       '4',   '$800.00']);
  Report.DrawTableRow(['2026-03-14', 'API Integration',          '7', '$1,050.00']);
  Report.DrawTableRow(['2026-03-15', 'Cloud Setup',              '3',   '$450.00']);
  Report.DrawTableRow(['2026-03-16', 'Monitoring Config',        '2',   '$300.00']);
  Report.DrawTableRow(['2026-03-17', 'User Training',            '8',   '$960.00']);
  Report.DrawTableRow(['2026-03-18', 'Incident Response',        '1',   '$350.00']);
  Report.DrawTableRow(['2026-03-19', 'Final Report',             '4',   '$600.00']);
  Report.DrawTableRow(['2026-03-20', 'Project Closeout',         '2',   '$400.00']);
  Report.EndTable;

  Report.MoveToNextLine(800);

  { === Footer Caption === }
  Report.DrawCaption(
    Format('Page: %s — Demonstrates Phase 5 Markdown-style formatting with automatic spacing.', [Config.PageLabel]));
end;

procedure DemoMarkdownFormatting;
var
  Report: TGDIPages;
  MS: TMemoryStream;
  FS: TFileStream;
  Config1, Config2: TPageConfig;
  SansFont, SerifFont, MonoFont: string;
begin
  Report := TGDIPages.Create(nil);
  try
    Report.UseOutlines := true;
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    { ExportPdfTagged := True wraps all draw commands in struct elements and
      auto-raises FileFormat to pdf17 (ISO 32000-1). It also selects the PDF/UA
      font mode — embedded TrueType instead of the base-14 Type1 faces — which
      is why it has to be set before anything is drawn: the export font flags
      decide which metrics the layout is measured with. }
    Report.ExportPdfTagged := True;
    Report.GetExportFonts(SansFont, SerifFont, MonoFont);

    { === PAGE 1: Standard layout with 15mm margins === }
    Config1.MarginLeft := 1500;
    Config1.MarginRight := 1500;
    Config1.MarginTop := 1500;
    Config1.MarginBottom := 1500;
    Config1.HeadingFontName := SansFont;
    Config1.HeadingFontSize := 28;
    Config1.BodyFontName := SansFont;
    Config1.BodyFontSize := 11;
    Config1.MonoFontName      := MonoFont;
    Config1.LineHeightFactor  := 1.1;   // default spacing
    Config1.PageLabel := '1 — Standard (15mm margins, ' + SansFont + ', 11pt body, LineHeight=1.1)';
    RenderMarkdownPage(Report, Config1);

    { === PAGE 2: Compact layout with different fonts === }
    Config2.MarginLeft := 1000;
    Config2.MarginRight := 1000;
    Config2.MarginTop := 1000;
    Config2.MarginBottom := 1000;
    Config2.HeadingFontName := SerifFont;
    Config2.HeadingFontSize := 22;
    Config2.BodyFontName := SerifFont;
    Config2.BodyFontSize := 9;
    Config2.MonoFontName      := MonoFont;
    Config2.LineHeightFactor  := 1.4;   // more open despite compact margins — contrast with page 1
    Config2.PageLabel := '2 — Compact (10mm margins, ' + SerifFont + ', 9pt body, LineHeight=1.4)';
    RenderMarkdownPage(Report, Config2);

    Report.EndDoc;

    { Export to PDF — ExportPdfTagged was set before drawing, see above. }
    MS := TMemoryStream.Create;
    try
      if Report.ExportPdfStream(MS) then
      begin
        FS := TFileStream.Create('markdown_demo.pdf', fmCreate);
        try
          MS.Position := 0;
          FS.CopyFrom(MS, MS.Size);
          WriteLn('✓ PDF exported to: markdown_demo.pdf');
        finally
          FS.Free;
        end;
      end;
    finally
      MS.Free;
    end;

  finally
    Report.Free;
  end;
end;

begin
  WriteLn('Markdown-Style Formatting Demo');
  WriteLn('==============================');
  WriteLn;
  DemoMarkdownFormatting;
  WriteLn;
  WriteLn('Features visible in the PDF:');
  WriteLn('  LineHeightFactor 1.1 (page 1, standard) vs 1.4 (page 2, open)');
  WriteLn('  Table header automatically repeated on each continuation page (R-9)');
  WriteLn('  Tagged PDF structure tags via ExportPdfTagged (FileFormat = pdf17)');
  WriteLn('Done!');
end.
