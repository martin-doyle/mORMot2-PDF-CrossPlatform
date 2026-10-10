/// golden file tests of the report engine
// - see test_pdf_golden for the baseline and how the files are compared
// - a unit of its own: mormot.ui.report must not meet mormot.pdf in one
// uses clause (psA4, TRect)
unit test_report_golden;

interface

{$I mormot.defines.inc}

uses
  Classes,
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.core.text,     // FormatUtf8
  mormot.ui.report,
  test_pdf_golden;

type
  /// golden files of TGDIPages (layer 3)
  TReportGoldenTests = class(TPdfGoldenTestCase)
  published
    procedure ReportTagged;
    procedure ReportPdfA3U;
  end;


implementation

// a report with headings, paragraphs, a list and a table across two pages
procedure DrawReport(Report: TGDIPages);
var
  layout: TTableLayout;
  i: integer;
begin
  Report.ExportPdfCreator := 'golden';
  Report.NewPage;
  Report.DrawHeading(1, 'Golden report');
  Report.DrawParagraph('A paragraph long enough to wrap: the quick brown fox ' +
    'jumps over the lazy dog, and "quoted text" keeps its quotation marks ' +
    'while the line breaks where the margin says so.');
  Report.DrawHeading(2, 'A list');
  for i := 1 to 3 do
    Report.DrawListItem(0, Report.CurrentY, FormatUtf8('List item %', [i]));
  Report.DrawHeading(2, 'A table');
  FillChar(layout, SizeOf(layout), 0);
  SetLength(layout.ColumnWidths, 3);
  SetLength(layout.ColumnAligns, 3);
  layout.ColumnWidths[0] := 6000;
  layout.ColumnWidths[1] := 3000;
  layout.ColumnWidths[2] := 3000;
  layout.ColumnAligns[0] := tcaLeft;
  layout.ColumnAligns[1] := tcaRight;
  layout.ColumnAligns[2] := tcaRight;
  layout.HeaderBkColor := clSilver;
  layout.BodyBkColor := clWhite;
  Report.BeginTable(layout);
  Report.DrawTableHeader(['Article', 'Qty', 'Total']);
  for i := 1 to 60 do // runs onto a second page, with the header repeated
    Report.DrawTableRow([FormatUtf8('Article %', [i]), FormatUtf8('%', [i]),
      FormatUtf8('%.00', [i * 3])]);
  Report.DrawTableFooter(['Total', '1830', '5490.00']);
  Report.EndTable;
  Report.EndDoc;
end;

function ExportReport(Report: TGDIPages): RawByteString;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    if Report.ExportPdfStream(ms) then
      FastSetRawByteString(result, ms.Memory, ms.Size)
    else
      result := '';
  finally
    ms.Free;
  end;
end;

procedure TReportGoldenTests.ReportTagged;
var
  report: TGDIPages;
  pdf: RawByteString;
begin
  report := TGDIPages.Create(nil);
  try
    report.ExportPdfTagged := true;
    report.UseOutlines := true;
    DrawReport(report);
    pdf := ExportReport(report);
    if CheckFailed(pdf <> '', 'tagged export') then
      exit;
    CheckGolden('report_tagged', pdf);
  finally
    report.Free;
  end;
end;

procedure TReportGoldenTests.ReportPdfA3U;
var
  report: TGDIPages;
  pdf: RawByteString;
begin
  report := TGDIPages.Create(nil);
  try
    report.ExportPdfLevel := pdfa3U;
    report.ExportPdfTagged := true;
    DrawReport(report);
    report.AddExportPdfAttachment('<?xml version="1.0"?><invoice/>',
      'factur-x.xml', 'Factur-X invoice data', 'text/xml', afrAlternative);
    report.ExportPdfMetadataExtension := PdfMetadataFacturX('EN 16931');
    pdf := ExportReport(report);
    if CheckFailed(pdf <> '', 'PDF/A-3U export') then
      exit;
    CheckGolden('report_pdfa3u', pdf);
  finally
    report.Free;
  end;
end;

end.
