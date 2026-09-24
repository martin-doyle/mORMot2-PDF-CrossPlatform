/// ZUGFeRD / Factur-X Demo — mORMot2 PDF Cross-Platform
// Produces a one-page tagged invoice as PDF/A-3 with the machine-readable
// invoice data (factur-x.xml, profile EN 16931 in CII syntax) embedded as
// associated file - a hybrid invoice for Germany (ZUGFeRD) and France
// (Factur-X). Invoices to German authorities take pure XML, not a PDF.
//
// Worth noting:
// - factur-x.xml is third-party test data: test case 01.01a of the KoSIT
//   xrechnung-testsuite, Apache-2.0, with its specification identifier changed
//   to EN 16931 (see THIRD_PARTY.md); the page draws its content, so both
//   have to be changed together
// - PdfA is passed to the constructor: setting the property later calls
//   NewDoc and erases everything drawn so far
// - Tagged := True comes after it and before the first AddPage, as always
// - the attachment goes through CreateFileAttachmentFrom, the only overload
//   that takes an /AFRelationship
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
  // page and table geometry, in pixels at 96 dpi
  LEFT_X      = 60;
  RIGHT_X     = 734;
  LINE_HEIGHT = 15;
  ROW_HEIGHT  = 24;
  // left edge of the description, right edges of the four number columns
  COL_TEXT = 66;
  COL_QTY  = 440;
  COL_UNIT = 540;
  COL_VAT  = 610;
  COL_SUM  = RIGHT_X - 6;
  // the content of factur-x.xml, as the page shows it
  ITEMS: array[0..1, 0..4] of string = (
    ('Zeitschrift [...], Art.-Nr. 246', '1', '288,79', '7 %', '288,79'),
    ('Porto + Versandkosten',           '1', '26,07',  '7 %', '26,07'));
  TOTALS: array[0..2, 0..1] of string = (
    ('Summe netto',            '314,86'),
    ('Umsatzsteuer 7 % auf 314,86', '22,04'),
    ('Gesamtbetrag (EUR)',     '336,90'));

var
  Doc: TPdfDocumentVcl;
  C: TCanvas;
  WithAttachment, WithTags: boolean;
  SansFont, SerifFont, MonoFont: string;
  Xml: RawByteString;
  Row, Y, i: integer;

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

// one paragraph of pre-broken lines, advancing Y past it
procedure Paragraph(const Lines: array of string);
var
  l: integer;
begin
  Open(psrP);
  for l := 0 to high(Lines) do
  begin
    C.TextOut(LEFT_X, Y, Lines[l]);
    Inc(Y, LINE_HEIGHT);
  end;
  Close;
  Inc(Y, LINE_HEIGHT div 2);
end;

// one table row: the description left-aligned, the other cells right-aligned
procedure TableRow(Cell: TPdfStructRole; const Values: array of string);
const
  RIGHT_EDGE: array[1..4] of integer = (COL_QTY, COL_UNIT, COL_VAT, COL_SUM);
var
  n: integer;
begin
  Open(psrTR);
  for n := 0 to high(Values) do
  begin
    Open(Cell);
    if n = 0 then
      C.TextOut(COL_TEXT, Y + 5, Values[0])
    else if Values[n] <> '' then
      TextRight(RIGHT_EDGE[n], Y + 5, Values[n]);
    Close;
  end;
  Close; // TR
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
  Doc := TPdfDocumentVcl.Create(true, 0, pdfa3U);
  try
    Doc.Tagged := WithTags;
    Doc.DefaultLanguage := 'de';
    // PDF/A embeds every font, so ask for the names of the embedded mode
    Doc.EmbeddedTTF := true;
    GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);
    Doc.Info.Title   := 'Rechnung 123456XX';
    Doc.Info.Author  := '[Seller name]';
    Doc.Info.Subject := 'Rechnung mit eingebetteten ZUGFeRD / Factur-X-Daten (EN 16931)';
    Doc.DefaultPaperSize := mormot.ui.pdf.psA4;
    Doc.AddPage;
    C := Doc.VclCanvas;
    C.Font.Name := SansFont;
    C.Font.Color := clBlack;
    // heading
    Open(psrH1);
    C.Font.Size := 22;
    C.Font.Style := [fsBold];
    C.TextOut(LEFT_X, 60, 'Rechnung 123456XX');
    Close;
    Doc.CreateOutline('Rechnung 123456XX', 1,
      Doc.DefaultPageHeight - 60 * 72 / 96);
    // parties, dates and references
    C.Font.Size := 10;
    C.Font.Style := [];
    Y := 110;
    Paragraph([
      '[Seller name] ([Seller trading name]), [Seller address line 1], ' +
        '12345 [Seller city], DE',
      'USt-IdNr. DE 123456789, 123/456/7890, HRA-Eintrag in […]',
      'Kontakt: nicht vorhanden, Tel. +49 1234-5678, seller@email.de']);
    Paragraph([
      'An: [Buyer name] ([Buyer identifier]), [Buyer address line 1], ' +
        '12345 [Buyer city], DE, buyer@info.de']);
    Paragraph([
      'Rechnungsdatum: 04.04.2016',
      'Käuferreferenz: 04011000-12345-03']);
    // the items, as a table with header, body and totals
    Inc(Y, LINE_HEIGHT div 2);
    Open(psrTable);
    Open(psrTHead);
    C.Pen.Style := psClear;
    C.Brush.Color := $963232;
    C.Rectangle(LEFT_X, Y, RIGHT_X, Y + ROW_HEIGHT);
    C.Font.Style := [fsBold];
    C.Font.Color := clWhite;
    TableRow(psrTH, ['Bezeichnung', 'Menge', 'Einzelpreis', 'USt', 'Betrag']);
    Close; // THead
    C.Font.Style := [];
    C.Font.Color := clBlack;
    C.Pen.Style := psSolid;
    C.Pen.Color := clSilver;
    C.Pen.Width := 1;
    Open(psrTBody);
    for Row := 0 to high(ITEMS) do
    begin
      Inc(Y, ROW_HEIGHT);
      if Odd(Row) then
        C.Brush.Color := $FFF0F0
      else
        C.Brush.Color := clWhite;
      C.Rectangle(LEFT_X, Y, RIGHT_X, Y + ROW_HEIGHT);
      TableRow(psrTD, [ITEMS[Row, 0], ITEMS[Row, 1], ITEMS[Row, 2],
        ITEMS[Row, 3], ITEMS[Row, 4]]);
    end;
    Close; // TBody
    // totals: label in the first column, amount in the last, the columns
    // between them left empty
    Open(psrTFoot);
    for Row := 0 to high(TOTALS) do
    begin
      Inc(Y, ROW_HEIGHT);
      if Row = high(TOTALS) then
        C.Font.Style := [fsBold];
      TableRow(psrTD, [TOTALS[Row, 0], '', '', '', TOTALS[Row, 1]]);
    end;
    Close; // TFoot
    Close; // Table
    C.Font.Style := [];
    Inc(Y, ROW_HEIGHT + LINE_HEIGHT);
    // the notes of the first item, then payment and terms
    Paragraph([
      'Zeitschrift [...]: Zeitschrift Inland, ISSN 0721-880X, ' +
        'Abrechnungszeitraum 01.01.2016 bis 31.12.2016,',
      'Bestellposition 6171175.1. Die letzte Lieferung im Rahmen des ' +
        'abgerechneten Abonnements erfolgt in 12/2016',
      'Lieferung erfolgt / erfolgte direkt vom Verlag']);
    Paragraph([
      'Zahlbar sofort ohne Abzug. SEPA-Überweisung auf ' +
        'IBAN DE79 0000 0000 1234 5678 90.']);
    Paragraph([
      'Es gelten unsere Allgem. Geschäftsbedingungen, die Sie unter […] ' +
        'finden.']);
    // where the data comes from - also required by its license
    C.Font.Size := 8;
    C.Font.Color := $505050;
    Y := 1040;
    if WithAttachment then
      Paragraph([
        'Die Rechnungsdaten sind als ' + XML_NAME + ' (ZUGFeRD / Factur-X, ' +
          'Profil EN 16931) in dieses PDF eingebettet.',
        'Nach Testdatensatz 01.01a der KoSIT xrechnung-testsuite, ' +
          'Apache License 2.0, angepasst - siehe THIRD_PARTY.md der Demo.'])
    else
      Paragraph([
        'Ohne eingebettete Rechnungsdaten erzeugt (--no-attachment).',
        'Inhalt nach Testdatensatz 01.01a der KoSIT xrechnung-testsuite, ' +
          'Apache License 2.0.']);
    // the invoice data, under the file name ZUGFeRD and Factur-X prescribe
    // and the XMP properties which point a reader at it (fx:)
    if WithAttachment then
    begin
      Doc.CreateFileAttachmentFrom(Xml, XML_NAME,
        'Factur-X invoice data', 'text/xml', Now, Now, nil, afrAlternative);
      Doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931', XML_NAME);
    end;
    Doc.SaveToFile(PDF_NAME);
    writeln('PDF saved to ', PDF_NAME);
  finally
    Doc.Free;
  end;
end.
