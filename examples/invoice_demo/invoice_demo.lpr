/// Accessible Invoice Demo - mORMot2 PDF Cross-Platform
// The invoice of zugferd_demo, laid out for a screen reader user: a heading
// per section, so that the headings list and the bookmarks lead to the
// invoice data, the parties, the items and the payment; the key data as
// tables with column headers; the bank accounts as a list; letterhead and
// page footer as artifacts, since every fact in them is tagged in the body.
// A proposal for review - zugferd_demo stays the reference demo.
//
// Worth noting:
// - factur-x.xml is the sample invoice of zugferd_demo (XRechnung for
//   Delphi, contributed under the licence of this project); the page is
//   drawn from what ReadInvoice finds in it and the file is embedded
// - the labels are ASCII German without umlauts ("Kunde", "Zahlbar bis");
//   every umlaut on the page comes from the UTF-8 XML
// - only the API of TGDIPages as it is: a label/value table with row
//   headers would need a body row header in TTableLayout, a sender line for
//   a window envelope a text artifact - see README.md
//
// Switches, to tell the sources of a checker failure apart:
//   --no-attachment   leave factur-x.xml out (the page is still read from it)
//   --untagged        no structure tree (PDF/A without PDF/UA)
program invoice_demo;

{$I mormot.defines.inc}
{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  Interfaces,   // registers the widgetset (Win32 on Windows, GTK2/Cocoa on Unix)
  {$endif FPC}
  SysUtils,
  Classes,
  Graphics,
  mormot.core.base,
  mormot.core.os,
  mormot.core.unicode,
  mormot.ui.report;

const
  XML_NAME = 'factur-x.xml';
  PROFILE = 'EN 16931';

type
  /// one invoice line, the values as the XML holds them
  TInvoiceItem = record
    Name, SellerId, Description, ClassCode, Note, OrderLine: RawUtf8;
    PeriodStart, PeriodEnd: RawUtf8;
    Quantity, Price, VatRate, Total: RawUtf8;
  end;

  /// the VAT of one rate
  TInvoiceTax = record
    Basis, Rate, Amount: RawUtf8;
  end;

  /// the invoice as the page shows it - amounts with a decimal point, dates
  // as yyyymmdd, formatted only when drawn
  TInvoice = record
    Number, IssueDate, DeliveryDate, Note, BuyerReference: RawUtf8;
    BuyerOrder, SellerOrder, Contract: RawUtf8;
    PeriodStart, PeriodEnd: RawUtf8;
    SellerName, SellerTradingName, SellerDescription: RawUtf8;
    SellerVatId, SellerTaxNumber: RawUtf8;
    SellerStreet, SellerPostcode, SellerCity, SellerCountry: RawUtf8;
    SellerContact, SellerPhone, SellerEmail: RawUtf8;
    BuyerId, BuyerName, BuyerEmail, BuyerVatId: RawUtf8;
    BuyerContact, BuyerPhone, BuyerContactEmail: RawUtf8;
    BuyerStreet, BuyerPostcode, BuyerCity, BuyerCountry: RawUtf8;
    Currency, PaymentTerms, DueDate, PaymentReference: RawUtf8;
    Ibans, AccountNames: array of RawUtf8;
    NetTotal, GrandTotal, DuePayable: RawUtf8;
    Taxes: array of TInvoiceTax;
    Items: array of TInvoiceItem;
  end;

var
  WithAttachment, WithTags: boolean;
  Xml: RawUtf8;
  Invoice: TInvoice;
  i: integer;

{ ---------- reading factur-x.xml ---------- }

// the content of the next <Tag>...</Tag> from From on, which then points
// behind it; '' when there is none. <Tag/> and <TagMore> do not match
function NextElement(const Xml, Tag: RawUtf8; var From: PtrInt): RawUtf8;
var
  p, q, e: PtrInt;
begin
  result := '';
  p := From - 1;
  repeat
    p := PosEx('<' + Tag, Xml, p + 1);
    if p = 0 then
    begin
      From := length(Xml) + 1;
      exit;
    end;
    q := p + length(Tag) + 1;
  until (q <= length(Xml)) and (Xml[q] in ['>', ' ']);
  q := PosEx('>', Xml, q);
  e := PosEx('</' + Tag + '>', Xml, q);
  if (q = 0) or (e = 0) then
  begin
    From := length(Xml) + 1;
    exit;
  end;
  result := copy(Xml, q + 1, e - q - 1);
  From := e + length(Tag) + 3;
end;

// the text at the end of a path of nested elements, '' when one is missing
function XmlText(const Xml: RawUtf8; const Path: array of RawUtf8): RawUtf8;
var
  n: integer;
  From: PtrInt;
begin
  result := Xml;
  for n := 0 to high(Path) do
  begin
    From := 1;
    result := NextElement(result, Path[n], From);
  end;
  result := TrimU(result);
end;

// "a, b, c" from the parts that are not empty
function Join(const Parts: array of RawUtf8): RawUtf8;
var
  n: integer;
begin
  result := '';
  for n := 0 to high(Parts) do
    if Parts[n] <> '' then
      if result = '' then
        result := Parts[n]
      else
        result := result + ', ' + Parts[n];
end;

// Xml up to the first <Tag: XmlText searches all descendants, so a child is
// looked for only in the part before the elements that hold the same name
function Before(const Xml, Tag: RawUtf8): RawUtf8;
var
  p: PtrInt;
begin
  p := PosEx('<' + Tag, Xml);
  if p = 0 then
    result := Xml
  else
    result := copy(Xml, 1, p - 1);
end;

// the text of the <ram:ID> whose schemeID is Scheme, '' when there is none
function SchemeId(const Xml, Scheme: RawUtf8): RawUtf8;
var
  p, q, e: PtrInt;
  Tag: RawUtf8;
begin
  result := '';
  p := PosEx('<ram:ID ', Xml);
  while p > 0 do
  begin
    q := PosEx('>', Xml, p);
    if q = 0 then
      exit;
    Tag := StringReplaceAll(copy(Xml, p, q - p), [' ', '', '''', '"']);
    if PosEx('schemeID="' + Scheme + '"', Tag) > 0 then
    begin
      e := PosEx('</ram:ID>', Xml, q);
      if e > q then
        result := TrimU(copy(Xml, q + 1, e - q - 1));
      exit;
    end;
    p := PosEx('<ram:ID ', Xml, q);
  end;
end;

// LineOne, LineTwo and LineThree of a PostalTradeAddress, joined
function AddressLines(const Party: RawUtf8): RawUtf8;
var
  Lines: array[0..2] of RawUtf8;
begin
  Lines[0] := XmlText(Party, ['ram:PostalTradeAddress', 'ram:LineOne']);
  Lines[1] := XmlText(Party, ['ram:PostalTradeAddress', 'ram:LineTwo']);
  Lines[2] := XmlText(Party, ['ram:PostalTradeAddress', 'ram:LineThree']);
  result := Join(Lines);
end;

function ReadItem(const Line: RawUtf8): TInvoiceItem;
var
  Product: RawUtf8;
begin
  // the characteristics after them hold a ram:Description of their own
  Product := Before(XmlText(Line, ['ram:SpecifiedTradeProduct']),
    'ram:ApplicableProductCharacteristic');
  result.Name := XmlText(Product, ['ram:Name']);
  result.SellerId := XmlText(Product, ['ram:SellerAssignedID']);
  result.Description := StringReplaceAll(XmlText(Product, ['ram:Description']),
    [#13, '', #10, ', ']);
  result.ClassCode := XmlText(Line, ['ram:SpecifiedTradeProduct',
    'ram:DesignatedProductClassification', 'ram:ClassCode']);
  result.Note := XmlText(Line, ['ram:AssociatedDocumentLineDocument',
    'ram:IncludedNote', 'ram:Content']);
  result.OrderLine := XmlText(Line, ['ram:SpecifiedLineTradeAgreement',
    'ram:BuyerOrderReferencedDocument', 'ram:LineID']);
  result.Price := XmlText(Line, ['ram:SpecifiedLineTradeAgreement',
    'ram:NetPriceProductTradePrice', 'ram:ChargeAmount']);
  result.Quantity := XmlText(Line, ['ram:SpecifiedLineTradeDelivery',
    'ram:BilledQuantity']);
  result.VatRate := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:ApplicableTradeTax', 'ram:RateApplicablePercent']);
  result.PeriodStart := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:BillingSpecifiedPeriod', 'ram:StartDateTime', 'udt:DateTimeString']);
  result.PeriodEnd := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:BillingSpecifiedPeriod', 'ram:EndDateTime', 'udt:DateTimeString']);
  result.Total := XmlText(Line, ['ram:SpecifiedLineTradeSettlement',
    'ram:SpecifiedTradeSettlementLineMonetarySummation', 'ram:LineTotalAmount']);
end;

// fills TInvoice from a CII invoice of the profile EN 16931 - only the fields
// this page shows
function ReadInvoice(const Xml: RawUtf8): TInvoice;
var
  Doc, Trade, Agreement, Seller, Buyer, Settlement, Line, Tax, Means: RawUtf8;
  From: PtrInt;
  n: integer;
begin
  Doc := XmlText(Xml, ['rsm:CrossIndustryInvoice', 'rsm:ExchangedDocument']);
  result.Number := XmlText(Doc, ['ram:ID']);
  result.IssueDate := XmlText(Doc, ['ram:IssueDateTime', 'udt:DateTimeString']);
  result.Note := XmlText(Doc, ['ram:IncludedNote', 'ram:Content']);
  Trade := XmlText(Xml, ['rsm:CrossIndustryInvoice',
    'rsm:SupplyChainTradeTransaction']);
  // the parties
  Agreement := XmlText(Trade, ['ram:ApplicableHeaderTradeAgreement']);
  result.BuyerReference := XmlText(Agreement, ['ram:BuyerReference']);
  result.BuyerOrder := XmlText(Agreement, ['ram:BuyerOrderReferencedDocument',
    'ram:IssuerAssignedID']);
  result.SellerOrder := XmlText(Agreement, ['ram:SellerOrderReferencedDocument',
    'ram:IssuerAssignedID']);
  result.Contract := XmlText(Agreement, ['ram:ContractReferencedDocument',
    'ram:IssuerAssignedID']);
  Seller := XmlText(Agreement, ['ram:SellerTradeParty']);
  result.SellerName := XmlText(Seller, ['ram:Name']);
  result.SellerTradingName := XmlText(Seller, ['ram:SpecifiedLegalOrganization',
    'ram:TradingBusinessName']);
  result.SellerDescription := XmlText(Seller, ['ram:Description']);
  result.SellerVatId := SchemeId(Seller, 'VA');
  result.SellerTaxNumber := SchemeId(Seller, 'FC');
  result.SellerStreet := AddressLines(Seller);
  result.SellerPostcode := XmlText(Seller, ['ram:PostalTradeAddress',
    'ram:PostcodeCode']);
  result.SellerCity := XmlText(Seller, ['ram:PostalTradeAddress', 'ram:CityName']);
  result.SellerCountry := XmlText(Seller, ['ram:PostalTradeAddress',
    'ram:CountryID']);
  result.SellerContact := XmlText(Seller, ['ram:DefinedTradeContact',
    'ram:PersonName']);
  result.SellerPhone := XmlText(Seller, ['ram:DefinedTradeContact',
    'ram:TelephoneUniversalCommunication', 'ram:CompleteNumber']);
  result.SellerEmail := XmlText(Seller, ['ram:DefinedTradeContact',
    'ram:EmailURIUniversalCommunication', 'ram:URIID']);
  Buyer := XmlText(Agreement, ['ram:BuyerTradeParty']);
  // the party's own ID precedes its name; a later ram:ID is a registration
  result.BuyerId := XmlText(copy(Buyer, 1, PosEx('<ram:Name', Buyer)), ['ram:ID']);
  result.BuyerName := XmlText(Buyer, ['ram:Name']);
  result.BuyerStreet := AddressLines(Buyer);
  result.BuyerPostcode := XmlText(Buyer, ['ram:PostalTradeAddress',
    'ram:PostcodeCode']);
  result.BuyerCity := XmlText(Buyer, ['ram:PostalTradeAddress', 'ram:CityName']);
  result.BuyerCountry := XmlText(Buyer, ['ram:PostalTradeAddress', 'ram:CountryID']);
  result.BuyerEmail := XmlText(Buyer, ['ram:URIUniversalCommunication',
    'ram:URIID']);
  result.BuyerVatId := SchemeId(Buyer, 'VA');
  result.BuyerContact := XmlText(Buyer, ['ram:DefinedTradeContact',
    'ram:PersonName']);
  result.BuyerPhone := XmlText(Buyer, ['ram:DefinedTradeContact',
    'ram:TelephoneUniversalCommunication', 'ram:CompleteNumber']);
  result.BuyerContactEmail := XmlText(Buyer, ['ram:DefinedTradeContact',
    'ram:EmailURIUniversalCommunication', 'ram:URIID']);
  result.DeliveryDate := XmlText(Trade, ['ram:ApplicableHeaderTradeDelivery',
    'ram:ActualDeliverySupplyChainEvent', 'ram:OccurrenceDateTime',
    'udt:DateTimeString']);
  // payment and totals
  Settlement := XmlText(Trade, ['ram:ApplicableHeaderTradeSettlement']);
  result.Currency := XmlText(Settlement, ['ram:InvoiceCurrencyCode']);
  result.PaymentReference := XmlText(Settlement, ['ram:PaymentReference']);
  result.PaymentTerms := XmlText(Settlement, ['ram:SpecifiedTradePaymentTerms',
    'ram:Description']);
  result.DueDate := XmlText(Settlement, ['ram:SpecifiedTradePaymentTerms',
    'ram:DueDateDateTime', 'udt:DateTimeString']);
  result.PeriodStart := XmlText(Settlement, ['ram:BillingSpecifiedPeriod',
    'ram:StartDateTime', 'udt:DateTimeString']);
  result.PeriodEnd := XmlText(Settlement, ['ram:BillingSpecifiedPeriod',
    'ram:EndDateTime', 'udt:DateTimeString']);
  // one account per means of payment, one breakdown per VAT rate
  result.Ibans := nil;
  result.AccountNames := nil;
  n := 0;
  From := 1;
  repeat
    Means := NextElement(Settlement, 'ram:SpecifiedTradeSettlementPaymentMeans',
      From);
    if Means = '' then
      break;
    SetLength(result.Ibans, n + 1);
    SetLength(result.AccountNames, n + 1);
    result.Ibans[n] := XmlText(Means, ['ram:PayeePartyCreditorFinancialAccount',
      'ram:IBANID']);
    result.AccountNames[n] := XmlText(Means,
      ['ram:PayeePartyCreditorFinancialAccount', 'ram:AccountName']);
    inc(n);
  until false;
  result.Taxes := nil;
  n := 0;
  From := 1;
  repeat
    Tax := NextElement(Settlement, 'ram:ApplicableTradeTax', From);
    if Tax = '' then
      break;
    SetLength(result.Taxes, n + 1);
    result.Taxes[n].Basis := XmlText(Tax, ['ram:BasisAmount']);
    result.Taxes[n].Rate := XmlText(Tax, ['ram:RateApplicablePercent']);
    result.Taxes[n].Amount := XmlText(Tax, ['ram:CalculatedAmount']);
    inc(n);
  until false;
  result.NetTotal := XmlText(Settlement,
    ['ram:SpecifiedTradeSettlementHeaderMonetarySummation', 'ram:LineTotalAmount']);
  result.GrandTotal := XmlText(Settlement,
    ['ram:SpecifiedTradeSettlementHeaderMonetarySummation', 'ram:GrandTotalAmount']);
  result.DuePayable := XmlText(Settlement,
    ['ram:SpecifiedTradeSettlementHeaderMonetarySummation', 'ram:DuePayableAmount']);
  // the lines
  result.Items := nil;
  n := 0;
  From := 1;
  repeat
    Line := NextElement(Trade, 'ram:IncludedSupplyChainTradeLineItem', From);
    if Line = '' then
      break;
    SetLength(result.Items, n + 1);
    result.Items[n] := ReadItem(Line);
    inc(n);
  until false;
end;

// why the file cannot be read, '' when it can: ZUGFeRD / Factur-X prescribe
// UTF-8, and the page shows the bytes as they are. mORMot's check refuses
// another encoding (Latin-1, UTF-16); it is no full RFC 3629 validator
function XmlProblem(const Xml: RawUtf8): RawUtf8;
var
  Prolog, Enc: RawUtf8;
  p, q: PtrInt;
begin
  result := '';
  if not IsValidUtf8NotVoid(Xml) then
  begin
    result := 'not valid UTF-8';
    exit;
  end;
  Prolog := Xml;
  // the BOM by its bytes: a #$EF literal is a character on Unicode Delphi
  if (length(Prolog) >= 3) and (ord(Prolog[1]) = $EF) and
     (ord(Prolog[2]) = $BB) and (ord(Prolog[3]) = $BF) then
    delete(Prolog, 1, 3);
  // the declaration, not a processing instruction like <?xml-stylesheet
  if not StartWithExact(Prolog, '<?xml') or (length(Prolog) < 6) or
     not (Prolog[6] in [' ', #9, #10, #13]) then
    exit;
  Prolog := copy(Prolog, 1, PosEx('?>', Prolog));
  p := PosEx('encoding', Prolog);
  if p = 0 then
    exit; // XML without a declared encoding is UTF-8
  p := PosEx('=', Prolog, p);
  while (p > 0) and (p < length(Prolog)) and not (Prolog[p] in ['"', '''']) do
    inc(p);
  if (p = 0) or (p >= length(Prolog)) then
    exit;
  q := PosEx(copy(Prolog, p, 1), Prolog, p + 1);
  if q = 0 then
    exit;
  Enc := copy(Prolog, p + 1, q - p - 1);
  if not IdemPropNameU(Enc, 'UTF-8') then
    result := 'declares the encoding ' + Enc + ', not UTF-8';
end;

{ ---------- formatting for a German invoice ---------- }

// 336.9 -> 336,90, 1234.5 -> 1.234,50, 0.1275 -> 0,1275: two decimals at
// least, never fewer than the XML has, so that the page shows what it holds
function Amount(const Value: RawUtf8): RawUtf8;
var
  Sign, Int, Frac: RawUtf8;
  p: PtrInt;
  n: integer;
begin
  result := '';
  if Value = '' then
    exit;
  Int := Value;
  Sign := '';
  if (Int <> '') and (Int[1] = '-') then
  begin
    Sign := '-';
    delete(Int, 1, 1);
  end;
  Frac := '';
  p := PosEx('.', Int);
  if p > 0 then
  begin
    Frac := copy(Int, p + 1, maxInt);
    Int := copy(Int, 1, p - 1);
  end;
  while length(Frac) < 2 do
    Frac := Frac + '0';
  if Int = '' then
    Int := '0'; // .5
  n := length(Int);
  while n > 3 do
  begin
    result := '.' + copy(Int, n - 2, 3) + result;
    dec(n, 3);
  end;
  result := Sign + copy(Int, 1, n) + result + ',' + Frac;
end;

// a quantity or a rate: 1 -> 1, 2.5000 -> 2,5, 19.00 -> 19
function Decimal(const Value: RawUtf8): RawUtf8;
begin
  result := Value;
  if (result <> '') and (result[1] = '.') then
    result := '0' + result // .5 -> 0.5
  else if (length(result) > 1) and (result[1] in ['-', '+']) and
          (result[2] = '.') then
    insert('0', result, 2); // -.5 -> -0.5
  if PosEx('.', result) > 0 then
  begin
    while (result <> '') and (result[length(result)] = '0') do
      SetLength(result, length(result) - 1);
    if (result <> '') and (result[length(result)] = '.') then
      SetLength(result, length(result) - 1);
  end;
  result := StringReplaceAll(result, '.', ',');
end;

// 20160404 -> 04.04.2016
function GermanDate(const Value: RawUtf8): RawUtf8;
begin
  if length(Value) = 8 then
    result := copy(Value, 7, 2) + '.' + copy(Value, 5, 2) + '.' +
      copy(Value, 1, 4)
  else
    result := Value;
end;

// DE79000000001234567890 -> DE79 0000 0000 1234 5678 90
function IbanGroups(const Iban: RawUtf8): RawUtf8;
var
  n: integer;
begin
  result := '';
  for n := 1 to length(Iban) do
  begin
    if (n > 1) and ((n - 1) mod 4 = 0) then
      result := result + ' ';
    result := result + copy(Iban, n, 1); // Iban[n], a char, would convert on Unicode Delphi
  end;
end;

// "a bis b", "ab a" or "bis b" - '' when neither date is there
function Period(const StartDate, EndDate: RawUtf8): RawUtf8;
begin
  if (StartDate <> '') and (EndDate <> '') then
    result := GermanDate(StartDate) + ' bis ' + GermanDate(EndDate)
  else if StartDate <> '' then
    result := 'ab ' + GermanDate(StartDate)
  else if EndDate <> '' then
    result := 'bis ' + GermanDate(EndDate)
  else
    result := '';
end;

// a rate as "19 %", '' when the XML has none
function Rate(const Value: RawUtf8): RawUtf8;
begin
  if Value = '' then
    result := ''
  else
    result := Decimal(Value) + ' %';
end;

// Prefix + Value, or '' when there is no value - a label never stands alone
function Labeled(const Prefix, Value: RawUtf8): RawUtf8;
begin
  if Value = '' then
    result := ''
  else
    result := Prefix + Value;
end;

{ ---------- the page ---------- }

// the item columns; 18000 = A4 (21000) minus the two 15 mm margins.
// Built at runtime: Delphi 7 has no constants for dynamic array fields
function ItemTableLayout: TTableLayout;
begin
  Finalize(result);
  FillChar(result, SizeOf(result), 0);
  SetLength(result.ColumnWidths, 5);
  result.ColumnWidths[0] := 8400;  // Bezeichnung
  result.ColumnWidths[1] := 1800;  // Menge
  result.ColumnWidths[2] := 2800;  // Einzelpreis
  result.ColumnWidths[3] := 1600;  // USt
  result.ColumnWidths[4] := 3400;  // Betrag
  SetLength(result.ColumnAligns, 5);
  result.ColumnAligns[0] := tcaLeft;
  result.ColumnAligns[1] := tcaRight;
  result.ColumnAligns[2] := tcaRight;
  result.ColumnAligns[3] := tcaRight;
  result.ColumnAligns[4] := tcaRight;
  result.HeaderFontStyle := [fsBold];
  result.HeaderBkColor := $F0E0D8;       // light blue (BGR)
  result.BodyBkColor := clWhite;
  result.AlternateRowColor := $FAF4F0;
  // the totals: bold on white, not in the header's colour
  result.FooterFontStyle := [fsBold];
  result.FooterBkColor := clWhite;
  result.GridColor := clSilver;          // quieter than the default black
  // "Gesamtbetrag" heads its row: a screen reader reads it with the amount
  result.FooterRowHeader := true;
end;

procedure DefineFormat(Report: TGDIPages; const Name, FontName: RawUtf8;
  Size: integer; Style: TFontStyles; Color: TColor; Before, After: integer);
var
  Fmt: TReportFormat;
begin
  Finalize(Fmt);
  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.FontName := FontName;
  Fmt.FontSize := Size;
  Fmt.FontStyle := Style;
  Fmt.Color := Color;
  Fmt.SpaceBefore := Before;
  Fmt.SpaceAfter := After;
  Report.DefineFormat(Name, Fmt);
end;

// the lines of an address block, one P each and close together; an empty
// line is left out
procedure DrawLines(Report: TGDIPages; const Sans: RawUtf8;
  const Lines: array of RawUtf8);
var
  n: integer;
begin
  DefineFormat(Report, 'P', Sans, 10, [], clBlack, 0, 0);
  for n := 0 to high(Lines) do
    if Lines[n] <> '' then
      Report.DrawParagraph(Lines[n]);
  DefineFormat(Report, 'P', Sans, 10, [], clBlack, 0, 250);
  Report.AddVerticalSpace(2);
end;

// label above value, in one row: a table whose column headers are the
// labels, so that a screen reader names the label with each value. A pair
// without its value is left out; the columns share the width
procedure DrawFields(Report: TGDIPages; const Labels, Values: array of RawUtf8);
var
  n, count: integer;
  L, V: TRawUtf8DynArray;
  Layout: TTableLayout;
begin
  count := 0;
  SetLength(L, length(Labels));
  SetLength(V, length(Labels));
  for n := 0 to high(Labels) do
    if Values[n] <> '' then
    begin
      L[count] := Labels[n];
      V[count] := Values[n];
      inc(count);
    end;
  if count = 0 then
    exit;
  SetLength(L, count);
  SetLength(V, count);
  Finalize(Layout);
  FillChar(Layout, SizeOf(Layout), 0);
  SetLength(Layout.ColumnWidths, count);
  SetLength(Layout.ColumnAligns, count);
  for n := 0 to count - 1 do
  begin
    Layout.ColumnWidths[n] := 18000 div count;
    Layout.ColumnAligns[n] := tcaLeft;
  end;
  // no grid, no fill: it reads as a line of labelled values
  Layout.HeaderFontSize := 8;
  Layout.HeaderBkColor := clWhite;
  Layout.BodyBkColor := clWhite;
  Layout.GridColor := clWhite;
  Report.BeginTable(Layout);
  Report.DrawTableHeader(L);
  Report.DrawTableRow(V);
  Report.EndTable;
  Report.AddVerticalSpace(2);
end;

// an H2 with room above it: DrawHeading takes size and style from the
// format, but not SpaceBefore
procedure DrawSection(Report: TGDIPages; const Title: RawUtf8);
begin
  Report.AddVerticalSpace(4);
  Report.DrawHeading(2, Title);
end;

procedure DrawInvoice(Report: TGDIPages; const Inv: TInvoice; const Sans: RawUtf8);
var
  n, k: integer;
  Item: TInvoiceItem;
  Name, Text, Due: RawUtf8;
begin
  DefineFormat(Report, 'H1', Sans, 20, [fsBold], clBlack, 0, 300);
  DefineFormat(Report, 'H2', Sans, 13, [fsBold], clBlack, 0, 0);
  DefineFormat(Report, 'P', Sans, 10, [], clBlack, 0, 250);
  DefineFormat(Report, 'LI', Sans, 10, [], clBlack, 0, 100);
  Report.SetFont(Sans, 10);
  Report.DrawHeading(1, 'Rechnung ' + Inv.Number);
  // the answer to "how much, by when" before any detail
  Due := Inv.DuePayable;
  if Due = '' then
    Due := Inv.GrandTotal;
  Text := Labeled('Rechnungsbetrag ', Amount(Due));
  if (Text <> '') and (Inv.Currency <> '') then
    Text := Text + ' ' + Inv.Currency;
  if Inv.DueDate <> '' then
    Text := Join([Text, 'zahlbar bis ' + GermanDate(Inv.DueDate)]);
  if Text <> '' then
  begin
    DefineFormat(Report, 'P', Sans, 11, [fsBold], clBlack, 0, 250);
    Report.DrawParagraph(Text + '.');
    DefineFormat(Report, 'P', Sans, 10, [], clBlack, 0, 250);
  end;
  // what identifies the invoice, and what it refers to
  DrawSection(Report, 'Rechnungsdaten');
  DrawFields(Report,
    ['Rechnungsnummer', 'Rechnungsdatum', 'Lieferdatum', 'Leistungszeitraum'],
    [Inv.Number, GermanDate(Inv.IssueDate), GermanDate(Inv.DeliveryDate),
     Period(Inv.PeriodStart, Inv.PeriodEnd)]);
  DrawFields(Report,
    ['Ihre Bestellung', 'Ihre Referenz', 'Unser Auftrag', 'Vertrag'],
    [Inv.BuyerOrder, Inv.BuyerReference, Inv.SellerOrder, Inv.Contract]);
  // the parties
  DrawSection(Report, 'Kunde');
  Name := Inv.BuyerName;
  if Inv.BuyerId <> '' then
    Name := Name + ' (Kundennummer ' + Inv.BuyerId + ')';
  DrawLines(Report, Sans, [Name, Inv.BuyerStreet,
    TrimU(Inv.BuyerPostcode + ' ' + Inv.BuyerCity), Inv.BuyerCountry,
    Labeled('USt-IdNr. ', Inv.BuyerVatId),
    Labeled('Ansprechpartner: ', Join([Inv.BuyerContact,
      Labeled('Tel. ', Inv.BuyerPhone), Inv.BuyerContactEmail])),
    Labeled('E-Mail: ', Inv.BuyerEmail)]);
  DrawSection(Report, 'Rechnungssteller');
  Name := Inv.SellerName;
  if Inv.SellerTradingName <> '' then
    Name := Name + ' (' + Inv.SellerTradingName + ')';
  DrawLines(Report, Sans, [Name, Inv.SellerStreet,
    TrimU(Inv.SellerPostcode + ' ' + Inv.SellerCity), Inv.SellerCountry,
    Join([Labeled('USt-IdNr. ', Inv.SellerVatId),
      Labeled('Steuernummer ', Inv.SellerTaxNumber)]),
    Inv.SellerDescription, Inv.Note,
    Labeled('Ansprechpartner: ', Join([Inv.SellerContact,
      Labeled('Tel. ', Inv.SellerPhone), Inv.SellerEmail]))]);
  // the items; the table breaks the page and repeats its header on its own
  DrawSection(Report, 'Positionen');
  Report.BeginTable(ItemTableLayout);
  Report.DrawTableHeader(['Bezeichnung', 'Menge', 'Einzelpreis', 'USt', 'Betrag']);
  for n := 0 to high(Inv.Items) do
  begin
    Item := Inv.Items[n];
    Name := Item.Name;
    if Item.SellerId <> '' then
      Name := Name + ', Art.-Nr. ' + Item.SellerId;
    Report.DrawTableRow([Name, Decimal(Item.Quantity), Amount(Item.Price),
      Rate(Item.VatRate), Amount(Item.Total)]);
  end;
  Report.DrawTableFooter(['Summe netto', '', '', '', Amount(Inv.NetTotal)]);
  for n := 0 to high(Inv.Taxes) do
    Report.DrawTableFooter([TrimU('Umsatzsteuer ' + Rate(Inv.Taxes[n].Rate)) +
      Labeled(' auf ', Amount(Inv.Taxes[n].Basis)), '', '', '',
      Amount(Inv.Taxes[n].Amount)]);
  Text := 'Gesamtbetrag';
  if Inv.Currency <> '' then
    Text := Text + ' (' + Inv.Currency + ')';
  Report.DrawTableFooter([Text, '', '', '', Amount(Inv.GrandTotal)]);
  Report.EndTable;
  Report.AddVerticalSpace(3);
  // what the items say beyond the table, right below it
  for n := 0 to high(Inv.Items) do
  begin
    Item := Inv.Items[n];
    Text := Join([Item.Description, Labeled('Klassifikation ', Item.ClassCode),
      Labeled('Abrechnungszeitraum ', Period(Item.PeriodStart, Item.PeriodEnd)),
      Labeled('Bestellposition ', Item.OrderLine)]);
    if Text <> '' then
      Text := Text + '.';
    if (Text <> '') or (Item.Note <> '') then
      Report.DrawParagraph(TrimU(Item.Name + ': ' + Text +
        Labeled(' ', Item.Note)));
  end;
  // payment: amount, date and reference as labelled values, the accounts as
  // a list - "list with 2 items" tells at once that there is a choice
  DrawSection(Report, 'Zahlung');
  Text := Amount(Due);
  if (Text <> '') and (Inv.Currency <> '') then
    Text := Text + ' ' + Inv.Currency;
  DrawFields(Report, ['Zahlbetrag', 'Zahlbar bis', 'Verwendungszweck'],
    [Text, GermanDate(Inv.DueDate), Inv.PaymentReference]);
  if Inv.PaymentTerms <> '' then
    Report.DrawParagraph(Inv.PaymentTerms);
  n := 0;
  for k := 0 to high(Inv.Ibans) do
    if Inv.Ibans[k] <> '' then
      inc(n);
  if n > 0 then
  begin
    if n = 1 then
      Report.DrawParagraph('Bankverbindung:')
    else
      Report.DrawParagraph('Bankverbindungen, zur Wahl:');
    // each account on one line, so that no line break falls into an IBAN
    for k := 0 to high(Inv.Ibans) do
      if Inv.Ibans[k] <> '' then
        Report.DrawListItem(300, Report.CurrentY, Join([Inv.AccountNames[k],
          'IBAN ' + IbanGroups(Inv.Ibans[k])]));
  end;
  // where the data comes from
  DrawSection(Report, 'Hinweise');
  DefineFormat(Report, 'P', Sans, 9, [], $505050, 0, 100);
  if WithAttachment then
    Report.DrawParagraph('Die Rechnungsdaten sind als ' + XML_NAME +
      ' (ZUGFeRD / Factur-X, Profil ' + PROFILE + ') in dieses PDF eingebettet.')
  else
    Report.DrawParagraph('Ohne eingebettete Rechnungsdaten erzeugt ' +
      '(--no-attachment), die Seite ist aus ' + XML_NAME + ' gelesen.');
  Report.DrawParagraph('Beispieldaten aus XRechnung for Delphi (Landrix ' +
    'Software) - keine echte Rechnung.');
  // header and footer are drawn in the font that is current at the export
  Report.SetFont(Sans, 8);
  Report.TextColor := $505050;
end;

{ ---------- the program ---------- }

{ <demo>_<os>_<cpu>_<compiler>.pdf next to the executable, e.g.
  invoice_demo_windows_x64_free-pascal-3.2.2.pdf or ..._x86_delphi-7.pdf: the runs
  of all platforms and compilers can then share one folder for checking.
  OS_KIND names the distribution on Linux }
function PdfFileName: TFileName;
var
  compiler: RawUtf8;
begin
  compiler := StringReplaceAll(COMPILER_VERSION, [' 32 bit', '', ' 64 bit', '']);
  result := Executable.ProgramFilePath + Utf8ToString(LowerCase('invoice_demo_' +
    ShortStringToAnsi7String(OS_NAME[OS_KIND]) + '_' + CPU_ARCH_TEXT + '_' +
    StringReplaceAll(compiler, ' ', '-') + '.pdf'));
end;

// factur-x.xml sits beside the .lpr; the executable is two levels below it
function LoadXml: RawUtf8;
begin
  result := StringFromFile(XML_NAME);
  if result = '' then
    result := StringFromFile(Executable.ProgramFilePath + '..' + PathDelim +
      '..' + PathDelim + XML_NAME);
end;

procedure ExportInvoice(const Inv: TInvoice; const FileName: TFileName);
var
  Report: TGDIPages;
  SansFont, SerifFont, MonoFont: RawUtf8;
  Stream: TFileStream;
begin
  Report := TGDIPages.Create(nil);
  try
    // all of this before the first NewPage - see the header
    Report.ExportPdfLevel := pdfa3U;
    Report.ExportPdfTagged := WithTags;
    Report.ExportPdfStandardFonts := false; // PDF/A embeds every font
    Report.ExportPdfEmbeddedTTF := true;
    Report.ExportPdfLanguage := 'de';
    Report.UseOutlines := true;             // PDF/UA: a bookmark per heading
    Report.GetExportFonts(SansFont, SerifFont, MonoFont);
    Report.PaperSize := psA4;
    Report.Orientation := poPortrait;
    Report.MarginLeft := 1500;
    Report.MarginRight := 1500;
    Report.MarginTop := 2000;               // room for the letterhead
    Report.MarginBottom := 2000;            // and the footer
    Report.Title := 'Rechnung ' + Inv.Number;
    Report.Author := Inv.SellerName;
    Report.Subject := 'Rechnung mit eingebetteten ZUGFeRD / Factur-X-Daten (' +
      PROFILE + ')';
    // letterhead and footer repeat on every page and are artifacts: their
    // facts are tagged in the body ("Rechnungssteller"), a screen reader
    // reads them once
    Report.SetHeader(Join([Inv.SellerName, Inv.SellerStreet,
      TrimU(Inv.SellerPostcode + ' ' + Inv.SellerCity)]));
    Report.SetFooter(Join([Inv.SellerName, Labeled('USt-IdNr. ', Inv.SellerVatId),
      'Rechnung ' + Inv.Number, 'Seite {#} von {total}']));
    Report.NewPage;
    DrawInvoice(Report, Inv, SansFont);
    Report.EndDoc;
    // the invoice data, under the file name ZUGFeRD and Factur-X prescribe,
    // and the XMP properties which point a reader at it
    if WithAttachment then
    begin
      Report.AddExportPdfAttachment(Xml, XML_NAME, 'Factur-X invoice data',
        'text/xml', afrAlternative);
      Report.ExportPdfMetadataExtension := PdfMetadataFacturX(PROFILE, XML_NAME);
      // the viewer opens with the attachments panel, factur-x.xml in sight
      Report.ExportPdfPageMode := pmUseAttachments;
    end;
    Stream := TFileStream.Create(FileName, fmCreate);
    try
      if not Report.ExportPdfStream(Stream) then
        raise Exception.Create('PDF export failed');
    finally
      Stream.Free;
    end;
  finally
    Report.Free;
  end;
end;

begin
  WithAttachment := true;
  WithTags := true;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--no-attachment' then
      WithAttachment := false
    else if ParamStr(i) = '--untagged' then
      WithTags := false;
  Xml := LoadXml;
  if Xml = '' then
  begin
    writeln('Cannot find ', XML_NAME, ' - run from the demo folder');
    ExitCode := 1;
    exit;
  end;
  if XmlProblem(Xml) <> '' then
  begin
    writeln(XML_NAME, ' ', XmlProblem(Xml));
    ExitCode := 1;
    exit;
  end;
  Invoice := ReadInvoice(Xml);
  ExportInvoice(Invoice, PdfFileName);
  writeln('PDF saved to ', PdfFileName);
end.
