/// Smoke test für PDF-Export-Funktionalität (ohne LCL-Abhängigkeiten)
// - migrated to TSynTestCase framework for mORMot2 compatibility
unit test_pdf_smoke;

{$mode delphi}{$H+}

interface

uses
  Classes,
  SysUtils,
  mormot.core.base,
  mormot.core.test,
  mormot.ui.pdfcanvas;  // TPdfDocumentVcl

type
  /// PDF smoke test cases
  TPdfSmokeTests = class(TSynTestCase)
  published
    procedure TestPdfCreation;
    procedure TestPdfMetadata;
    procedure TestPdfMultiplePages;
    procedure TestPdfDifferentSizes;
  end;

implementation

procedure TPdfSmokeTests.TestPdfCreation;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  Size: Integer;
  Header: AnsiString;
begin
  Stream := TMemoryStream.Create;
  try
    // Create PDF with default options (no PDF/A)
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);  // Use Outlines=false, CodePage=0, pdfaNone
    try
      // Set metadata
      PDF.Info.Title := 'Test Document';
      PDF.Info.Author := 'mORMot2 Test Suite';
      PDF.Info.Subject := 'PDF Export Smoke Test';
      PDF.Info.Creator := 'mormot.ui.pdfcanvas';

      // Create empty PDF (minimum valid structure)
      PDF.DefaultPageWidth  := 595;   // A4 width in points (210 mm)
      PDF.DefaultPageHeight := 842;   // A4 height in points (297 mm)
      PDF.AddPage;

      // Export to stream
      PDF.SaveToStream(Stream);

      // Verify stream has content
      Size := Stream.Size;
      Check(Size > 100, Format('PDF size too small: %d bytes (expected > 100)', [Size]));

      // Verify PDF header
      Stream.Position := 0;
      SetLength(Header, 4);
      Stream.Read(pointer(Header)^, 4);
      Check(copy(string(Header), 1, 1) = '%', 'Invalid PDF header (should start with %)');
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestPdfMetadata;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      // Verify we can set metadata without errors
      PDF.Info.Title := 'Metadata Test';
      PDF.Info.Author := 'Test Author';
      PDF.Info.Subject := 'Test Subject';
      PDF.Info.Keywords := 'test, pdf, export';
      PDF.Info.Creator := 'mORMot2';
      PDF.DefaultPageWidth  := 595;
      PDF.DefaultPageHeight := 842;
      PDF.AddPage;
      PDF.SaveToStream(Stream);
      Check(Stream.Size > 100, 'PDF with metadata too small');
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestPdfMultiplePages;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
  i: Integer;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.Info.Title := 'Multi-Page Test';
      PDF.DefaultPageWidth  := 595;
      PDF.DefaultPageHeight := 842;
      // Create multiple pages
      for i := 1 to 5 do
        PDF.AddPage;
      PDF.SaveToStream(Stream);
      Check(Stream.Size > 500, Format('Multi-page PDF too small: %d bytes', [Stream.Size]));
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TPdfSmokeTests.TestPdfDifferentSizes;
var
  PDF: TPdfDocumentVcl;
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    PDF := TPdfDocumentVcl.Create(false, 0, pdfaNone);
    try
      PDF.Info.Title := 'Different Sizes';
      // A4: 210mm × 297mm = 595 × 842 points
      PDF.DefaultPageWidth  := 595;
      PDF.DefaultPageHeight := 842;
      PDF.AddPage;
      // US Letter: 216mm × 279mm = 612 × 792 points
      PDF.DefaultPageWidth  := 612;
      PDF.DefaultPageHeight := 792;
      PDF.AddPage;
      // A3: 297mm × 420mm = 842 × 1191 points
      PDF.DefaultPageWidth  := 842;
      PDF.DefaultPageHeight := 1191;
      PDF.AddPage;
      PDF.SaveToStream(Stream);
      Check(Stream.Size > 300, 'Variable-size PDF too small');
    finally
      PDF.Free;
    end;
  finally
    Stream.Free;
  end;
end;

end.
