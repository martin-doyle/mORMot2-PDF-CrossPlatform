/// ZUGFeRD / Factur-X Demo — mORMot2 PDF Cross-Platform
// Produces a one-page tagged invoice as PDF/A-3 with the machine-readable
// invoice data (factur-x.xml, MINIMUM profile) embedded as associated file.
//
// Worth noting:
// - PdfA is passed to the constructor: setting the property later calls
//   NewDoc and erases everything drawn so far
// - Tagged := True comes after it and before the first AddPage, as always
// - the attachment goes through CreateFileAttachmentFrom, the only overload
//   that takes an /AFRelationship; ZUGFeRD prescribes /Data for MINIMUM
// - this is roadmap R-17 work in progress: the output is not yet claimed to be
//   conformant to PDF/A-3, PDF/UA-1 or ZUGFeRD
//
// Switches, to tell the sources of a checker failure apart:
//   --no-attachment   leave factur-x.xml out
//   --untagged        no structure tree (PDF/A without PDF/UA)
program zugferd_demo;

{$ifdef FPC}
{$mode delphi}
{$endif FPC}

uses
  {$ifdef FPC}
  Interfaces,   // registers the widgetset (Win32 on Windows, GTK2/Cocoa on Unix)
  {$endif FPC}
  SysUtils,
  Graphics,
  mormot.core.base,
  mormot.core.os,
  mormot.pdf.types,   // TPdfStructRole
  mormot.ui.pdf,
  mormot.ui.pdfcanvas,
  mormot.ui.report;   // GetReportFonts

const
  XML_NAME = 'factur-x.xml';
  PDF_NAME = 'zugferd_invoice.pdf';
  // table geometry, in pixels at 96 dpi
  TABLE_LEFT  = 60;
  TABLE_RIGHT = 734;
  ROW_HEIGHT  = 24;
  COL_X: array[0..3] of integer = (66, 380, 500, 620);

var
  Doc: TPdfDocumentVcl;
  C: TCanvas;
  WithAttachment, WithTags: boolean;
  SansFont, SerifFont, MonoFont: string;
  Xml: RawByteString;
  Items: array[0..4, 0..3] of string;
  Totals: array[0..2, 0..1] of string;
  Row, Col, Y, i: integer;

// the structure calls, skipped for --untagged
procedure Open(Role: TPdfStructRole);
begin
  if WithTags then
    Doc.BeginStructContent(Role);
end;

procedure Close;
begin
  if WithTags then
    Doc.EndStructContent;
end;

// factur-x.xml sits beside the .lpr; the executable is two levels below it
function LoadXml: RawByteString;
begin
  result := StringFromFile(XML_NAME);
  if result = '' then
    result := StringFromFile(Executable.ProgramFilePath + '..' + PathDelim +
      '..' + PathDelim + XML_NAME);
end;

// text right-aligned against x = Right, for the amount columns
procedure TextRight(Right, Top: integer; const s: string);
begin
  C.TextOut(Right - C.TextWidth(s), Top, s);
end;

begin
  WithAttachment := true;
  WithTags := true;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--no-attachment' then
      WithAttachment := false
    else if ParamStr(i) = '--untagged' then
      WithTags := false;
  if WithAttachment then
  begin
    Xml := LoadXml;
    if Xml = '' then
    begin
      writeln('Cannot find ', XML_NAME, ' - run from the demo folder');
      ExitCode := 1;
      exit;
    end;
  end;
  // AUseOutlines = true: PDF/UA wants a bookmark per heading
  Doc := TPdfDocumentVcl.Create(true, 0, pdfa3B);
  try
    Doc.Tagged := WithTags;
    Doc.DefaultLanguage := 'en';
    // PDF/A embeds every font, so ask for the names of the embedded mode
    Doc.EmbeddedTTF := true;
    GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
    Doc.Info.Title   := 'Invoice RE-2026-0042';
    Doc.Info.Author  := 'Example Hardware Ltd.';
    Doc.Info.Subject := 'Invoice with embedded Factur-X data (MINIMUM)';
    Doc.DefaultPaperSize := mormot.ui.pdf.psA4;
    Doc.AddPage;
    C := Doc.VclCanvas;
    C.Font.Name := SansFont;
    C.Font.Color := clBlack;
    // heading
    Open(psrH1);
    C.Font.Size := 22;
    C.Font.Style := [fsBold];
    C.TextOut(TABLE_LEFT, 60, 'Invoice RE-2026-0042');
    Close;
    Doc.CreateOutline('Invoice RE-2026-0042', 1,
      Doc.DefaultPageHeight - 60 * 72 / 96);
    // parties and date
    C.Font.Size := 10;
    C.Font.Style := [];
    Open(psrP);
    C.TextOut(TABLE_LEFT, 110, 'Example Hardware Ltd., VAT ID DE123456789');
    Close;
    Open(psrP);
    C.TextOut(TABLE_LEFT, 128, 'Bill to: Sample Workshop Inc.');
    Close;
    Open(psrP);
    C.TextOut(TABLE_LEFT, 146, 'Invoice date: 2026-09-24');
    Close;
    // the items, as a table with header, body and totals
    Items[0, 0] := 'Bolt M4x10';  Items[0, 1] := '100'; Items[0, 2] := '0.05'; Items[0, 3] := '5.00';
    Items[1, 0] := 'Nut M4';      Items[1, 1] := '100'; Items[1, 2] := '0.03'; Items[1, 3] := '3.00';
    Items[2, 0] := 'Washer 4mm';  Items[2, 1] := '200'; Items[2, 2] := '0.02'; Items[2, 3] := '4.00';
    Items[3, 0] := 'Dowel 8mm';   Items[3, 1] := '50';  Items[3, 2] := '0.12'; Items[3, 3] := '6.00';
    Items[4, 0] := 'Tape 25mm';   Items[4, 1] := '5';   Items[4, 2] := '2.50'; Items[4, 3] := '12.50';
    Totals[0, 0] := 'Net amount';  Totals[0, 1] := '30.50';
    Totals[1, 0] := 'VAT 19 %';    Totals[1, 1] := '5.80';
    Totals[2, 0] := 'Total (EUR)'; Totals[2, 1] := '36.30';
    Open(psrTable);
    Y := 190;
    Open(psrTHead);
    C.Pen.Style := psClear;
    C.Brush.Color := $963232;
    C.Rectangle(TABLE_LEFT, Y, TABLE_RIGHT, Y + ROW_HEIGHT);
    C.Font.Style := [fsBold];
    C.Font.Color := clWhite;
    Open(psrTR);
    Open(psrTH);
    C.TextOut(COL_X[0], Y + 5, 'Article');
    Close;
    Open(psrTH);
    TextRight(COL_X[1] + 60, Y + 5, 'Qty');
    Close;
    Open(psrTH);
    TextRight(COL_X[2] + 90, Y + 5, 'Unit price');
    Close;
    Open(psrTH);
    TextRight(TABLE_RIGHT - 6, Y + 5, 'Amount');
    Close;
    Close; // TR
    Close; // THead
    C.Font.Style := [];
    C.Font.Color := clBlack;
    C.Pen.Style := psSolid;
    C.Pen.Color := clSilver;
    C.Pen.Width := 1;
    Open(psrTBody);
    for Row := 0 to high(Items) do
    begin
      Inc(Y, ROW_HEIGHT);
      if Odd(Row) then
        C.Brush.Color := $FFF0F0
      else
        C.Brush.Color := clWhite;
      C.Rectangle(TABLE_LEFT, Y, TABLE_RIGHT, Y + ROW_HEIGHT);
      Open(psrTR);
      for Col := 0 to 3 do
      begin
        Open(psrTD);
        case Col of
          0: C.TextOut(COL_X[0], Y + 5, Items[Row, 0]);
          1: TextRight(COL_X[1] + 60, Y + 5, Items[Row, 1]);
          2: TextRight(COL_X[2] + 90, Y + 5, Items[Row, 2]);
          3: TextRight(TABLE_RIGHT - 6, Y + 5, Items[Row, 3]);
        end;
        Close;
      end;
      Close; // TR
    end;
    Close; // TBody
    // totals: label in the first column, amount in the last, the two columns
    // between them left empty
    Open(psrTFoot);
    C.Brush.Color := clWhite;
    for Row := 0 to high(Totals) do
    begin
      Inc(Y, ROW_HEIGHT);
      if Row = high(Totals) then
        C.Font.Style := [fsBold];
      Open(psrTR);
      Open(psrTD);
      C.TextOut(COL_X[0], Y + 5, Totals[Row, 0]);
      Close;
      Open(psrTD);
      Close;
      Open(psrTD);
      Close;
      Open(psrTD);
      TextRight(TABLE_RIGHT - 6, Y + 5, Totals[Row, 1]);
      Close;
      Close; // TR
    end;
    Close; // TFoot
    Close; // Table
    // closing note
    C.Font.Style := [];
    C.Font.Size := 9;
    Inc(Y, 2 * ROW_HEIGHT);
    Open(psrP);
    if WithAttachment then
      C.TextOut(TABLE_LEFT, Y,
        'The machine-readable invoice data is embedded in this file as ' +
        XML_NAME + ' (Factur-X, MINIMUM profile).')
    else
      C.TextOut(TABLE_LEFT, Y, 'Built without the embedded invoice data.');
    Close;
    // the invoice data: ZUGFeRD 2.x / Factur-X prescribe the name factur-x.xml
    // and /AFRelationship /Data for the MINIMUM profile
    if WithAttachment then
      Doc.CreateFileAttachmentFrom(Xml, XML_NAME,
        'Factur-X invoice data', 'text/xml', Now, Now, nil, afrData);
    Doc.SaveToFile(PDF_NAME);
    writeln('PDF saved to ', PDF_NAME);
  finally
    Doc.Free;
  end;
end.
