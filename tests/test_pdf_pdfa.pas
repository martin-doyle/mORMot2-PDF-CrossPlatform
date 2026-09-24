/// PDF/A-3 tests: associated files, XMP identification and extension
// schemas, the U level (roadmap R-17)
// - the output is uncompressed, so the objects stay searchable as text
unit test_pdf_pdfa;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  mormot.core.base,
  mormot.core.os,
  mormot.core.test,
  mormot.pdf.types,     // TPdfStructRole
  mormot.ui.pdf,
  mormot.ui.pdfcanvas,  // TPdfDocumentVcl
  mormot.ui.report,     // GetReportFonts
  test_pdf_subset;      // CountOf

type
  /// PDF/A test cases
  TPdfATests = class(TSynTestCase)
  protected
    // one page with aText, as PDF/A at aLevel, optionally tagged, with an
    // attachment from aAttachment when it is not '' and aExtension as
    // PdfAMetadaExtension
    function BuildPdf(aLevel: TPdfALevel; aTagged: boolean;
      const aText: string; const aAttachment: RawByteString = '';
      const aExtension: RawUtf8 = ''): RawByteString;
  published
    procedure TestPdfA3UIdentification;
    procedure TestPdfA3AssociatedFile;
    procedure TestAttachmentFromFile;
    procedure TestXmpExtensionSchemas;
    procedure TestFacturXMetadata;
    procedure TestPdfA3UToUnicodeForEveryFont;
    {$ifndef NO_USE_PDFSECURITY}
    procedure TestPdfAWithEncryptionRaises;
    {$endif NO_USE_PDFSECURITY}
  end;

implementation

function TPdfATests.BuildPdf(aLevel: TPdfALevel; aTagged: boolean;
  const aText: string; const aAttachment: RawByteString;
  const aExtension: RawUtf8): RawByteString;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  sans, serif, mono: string;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, aLevel);
    try
      PDF.CompressionMethod := cmNone;
      PDF.Tagged := aTagged;
      PDF.EmbeddedTTF := true;
      PDF.DefaultLanguage := 'en';
      PDF.Info.Title := 'PDF/A test';
      GetReportFonts(true, sans, serif, mono);
      PDF.AddPage;
      if aTagged then
        PDF.BeginStructContent(psrP);
      PDF.VclCanvas.Font.Name := sans;
      PDF.VclCanvas.TextOut(20, 20, aText);
      PDF.VclCanvas.Font.Name := serif;
      PDF.VclCanvas.TextOut(20, 60, aText);
      if aTagged then
        PDF.EndStructContent;
      if aAttachment <> '' then
        PDF.CreateFileAttachmentFrom(aAttachment, 'factur-x.xml', 'data',
          'text/xml', Now, Now, nil, afrData);
      PDF.PdfAMetadaExtension := aExtension;
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(result, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(result)^, Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure TPdfATests.TestPdfA3UIdentification;
var
  s: RawByteString;
begin
  s := BuildPdf(pdfa3U, false, 'Hello');
  Check(copy(s, 1, 8) = '%PDF-1.7', 'PDF/A-3 is based on PDF 1.7');
  Check(Pos(RawByteString('<pdfaid:part>3</pdfaid:part>' +
    '<pdfaid:conformance>U</pdfaid:conformance>'), s) > 0,
    'XMP identifies PDF/A-3U');
  Check(Pos(RawByteString('/OutputIntents'), s) > 0, 'sRGB output intent');
  { an untagged document claims no structure: the /MarkInfo and the empty
    StructTreeRoot PDF/A used to add were removed with the R-17 fix }
  CheckEqual(CountOf('/MarkInfo', s), 0, 'no MarkInfo without Tagged');
  CheckEqual(CountOf('/StructTreeRoot', s), 0, 'no StructTreeRoot without Tagged');
end;

procedure TPdfATests.TestPdfA3AssociatedFile;
const
  XML = '<?xml version="1.0"?><invoice/>';
var
  s: RawByteString;
begin
  s := BuildPdf(pdfa3U, false, 'Hello', XML);
  // '/AF' also starts '/AFRelationship': the difference is the catalog entry
  CheckEqual(CountOf('/AF', s) - CountOf('/AFRelationship', s), 1,
    'catalog carries one /AF array (ISO 19005-3 6.8)');
  Check(Pos(RawByteString('/AFRelationship/Data'), s) > 0,
    'the relationship given is written');
  Check(Pos(RawByteString('/EmbeddedFiles'), s) > 0, 'EmbeddedFiles name tree');
  Check(Pos(RawByteString('/Subtype/text#2Fxml'), s) > 0,
    'MIME type as a name, with the slash escaped');
  Check(Pos(RawByteString('/Params<</Size ' + IntToStr(length(XML))), s) > 0,
    'Params/Size is the length of the file');
  Check(Pos(RawByteString(XML), s) > 0, 'the file itself is embedded');
end;

procedure TPdfATests.TestAttachmentFromFile;
const
  XML = '<?xml version="1.0"?><from-file/>';
var
  fn: TFileName;
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  s: RawByteString;
begin
  { the file overload read the content through a stream and took /Size from
    the empty buffer, so it always wrote 0; it also had no relationship }
  fn := TemporaryFileName;
  FileFromString(XML, fn);
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfa3U);
    try
      PDF.CompressionMethod := cmNone;
      PDF.AddPage;
      Check(PDF.CreateFileAttachment(fn, 'from a file', 'text/xml',
        afrSource) <> nil, 'attached');
      PDF.SaveToStream(Stream);
    finally
      PDF.Free;
    end;
    SetLength(s, Stream.Size);
    Stream.Position := 0;
    Stream.Read(pointer(s)^, Stream.Size);
  finally
    Stream.Free;
    DeleteFile(fn);
  end;
  Check(Pos(RawByteString('/Params<</Size ' + IntToStr(length(XML))), s) > 0,
    'Params/Size counts the bytes read from the file');
  Check(Pos(RawByteString('/AFRelationship/Source'), s) > 0,
    'the file overload takes a relationship');
end;

procedure TPdfATests.TestXmpExtensionSchemas;
var
  s: RawByteString;
begin
  { pdfuaid is no schema PDF/A predefines (ISO 19005-3 6.6.2.3.1), so tagged
    PDF/A has to describe it - veraPDF failed every tagged PDF/A without it }
  s := BuildPdf(pdfa3U, true, 'Hello');
  CheckEqual(CountOf('<pdfaExtension:schemas>', s), 1, 'one list of schemas');
  CheckEqual(CountOf('<pdfaSchema:prefix>pdfuaid</pdfaSchema:prefix>', s), 1,
    'pdfuaid is described');
  // a caller's list is extended rather than doubled: two pdfaExtension:schemas
  // on the same resource would not be valid XMP
  s := BuildPdf(pdfa3U, true, 'Hello', '', PdfMetadataFacturX('EN 16931'));
  CheckEqual(CountOf('<pdfaExtension:schemas>', s), 1,
    'still one list, with the fx: schema of the caller');
  CheckEqual(CountOf('<pdfaSchema:prefix>pdfuaid</pdfaSchema:prefix>', s), 1,
    'pdfuaid added to it');
  CheckEqual(CountOf('<pdfaSchema:prefix>fx</pdfaSchema:prefix>', s), 1,
    'fx kept in it');
  // without Tagged there is no pdfuaid property, so nothing to describe
  s := BuildPdf(pdfa3U, false, 'Hello');
  CheckEqual(CountOf('pdfuaid', s), 0, 'untagged: no pdfuaid at all');
end;

procedure TPdfATests.TestFacturXMetadata;
var
  x: RawUtf8;
begin
  x := PdfMetadataFacturX('EN 16931');
  Check(Pos('<fx:ConformanceLevel>EN 16931</fx:ConformanceLevel>', x) > 0,
    'profile');
  Check(Pos('<fx:DocumentFileName>factur-x.xml</fx:DocumentFileName>', x) > 0,
    'default file name');
  Check(Pos('<fx:Version>1.0</fx:Version>', x) > 0, 'default version');
  Check(Pos('<fx:DocumentType>INVOICE</fx:DocumentType>', x) > 0,
    'default document type');
  CheckEqual(CountOf('<pdfaProperty:name>', x), 4,
    'all four properties described');
  x := PdfMetadataFacturX('A&B', 'x<y>.xml');
  Check(Pos('<fx:ConformanceLevel>A&amp;B</fx:ConformanceLevel>', x) > 0,
    'values are XML-escaped');
  Check(Pos('<fx:DocumentFileName>x&lt;y&gt;.xml</fx:DocumentFileName>', x) > 0,
    'file name too');
end;

procedure TPdfATests.TestPdfA3UToUnicodeForEveryFont;
var
  s: RawByteString;
  fonts: integer;
begin
  { U means every text maps to Unicode: each font dictionary needs its
    /ToUnicode - two faces here, a sans and a serif, both WinAnsi
    - a CJK face beside them is the known open case: its unused WinAnsi peer
    has no used characters and so no /ToUnicode (see ROADMAP) }
  s := BuildPdf(pdfa3U, true, 'Hello ÄÖÜ € —');
  fonts := CountOf('/Subtype/TrueType', s) + CountOf('/Subtype/Type0', s);
  Check(fonts >= 2, 'both faces are in the file');
  CheckEqual(CountOf('/ToUnicode', s), fonts, 'one ToUnicode per font');
end;

{$ifndef NO_USE_PDFSECURITY}
procedure TPdfATests.TestPdfAWithEncryptionRaises;
var
  raised: boolean;
begin
  // ISO 19005 forbids encryption at every level
  raised := false;
  try
    TPdfDocument.Create(false, 0, pdfa3U,
      TPdfEncryption.New(elRC4_128, '', 'owner', PDF_PERMISSION_ALL)).Free;
  except
    on EPdfInvalidOperation do
      raised := true;
  end;
  Check(raised, 'PDF/A with encryption raises EPdfInvalidOperation');
end;
{$endif NO_USE_PDFSECURITY}

end.
