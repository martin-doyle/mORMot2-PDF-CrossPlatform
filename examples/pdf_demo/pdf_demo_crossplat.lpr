/// Cross-Platform PDF Demo — mORMot2 PDF Cross-Platform
// Produces a 3-page tagged PDF — text and fonts, vector graphics, a table —
// from plain TCanvas calls, with no report engine and no GUI.
//
// Worth noting:
// - the TCanvas drawing code is identical on all platforms and compilers
// - FPC/Lazarus always uses TPdfDocumentVcl: the LCL metafile canvas does not
//   record Brush state reliably, which would turn every fill black
// - Delphi on Windows uses TPdfDocumentGDI (full GDI + Uniscribe feature set)
// - Tagged := True must be set before AddPage and before the font names are
//   resolved; it raises FileFormat to pdf17 and selects the PDF/UA font mode
// - the low-level API leaves the structure to the caller, so this demo opens
//   the struct roles and the THead/TBody row groups itself
program pdf_demo_crossplat;

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
  mormot.pdf.types,   // TPdfStructRole: psrH1, psrP, psrFigure, psrTable, ...
  mormot.ui.pdf,
  mormot.ui.pdfcanvas,
  mormot.ui.report;   // for REPORT_FONT_SANS/SERIF/MONO constants

var
  // FPC/Lazarus: always use TPdfDocumentVcl — LCL metafile canvas does not
  // record Brush/Pen state reliably, so TPdfDocumentGDI produces black fills.
  // Delphi on Windows: TPdfDocumentGDI (full GDI+Uniscribe feature set).
  {$if defined(FPC) or not defined(MSWINDOWS)}
  Doc: TPdfDocumentVcl;
  {$else}
  Doc: TPdfDocumentGDI;
  {$ifend}
  C: TCanvas;
  Row, Col, X, Y: Integer;
  ColWidths: array[0..3] of Integer;
  Headers:   array[0..3] of string;
  Data:      array[0..4, 0..3] of string;
  MyX, MyY:  Integer;
  MyXLoc:    Integer;
  {$if defined(FPC) or not defined(MSWINDOWS)}
  VC:        TPdfVclCanvas;  // sub-pixel text metrics (ROADMAP B-4)
  {$ifend}
  MyString:  String;
  SansFont: String;
  SerifFont: String;
  MonoFont: String;
begin
  // AUseOutlines = true: PDF/UA wants a bookmark per heading, and the
  // low-level API leaves the outline to the caller (TGDIPages builds its own)
  {$if defined(FPC) or not defined(MSWINDOWS)}
  Doc := TPdfDocumentVcl.Create(true);
  {$else}
  Doc := TPdfDocumentGDI.Create(true);
  {$ifend}
  try
    // Tagged PDF (ISO 32000-1 §14) — must be set BEFORE AddPage and before the
    // font names are resolved: Tagged := True auto-raises FileFormat to pdf17
    // and selects the PDF/UA font mode (EmbeddedTTF on, StandardFontsReplace
    // off), because PDF/UA does not allow the viewer's own base-14 faces.
    Doc.Tagged          := True;
    Doc.DefaultLanguage := 'en';
    // asked afterwards, so the names match the mode Tagged just selected
    GetReportFonts(Doc.EmbeddedTTF, SansFont, SerifFont, MonoFont);

    Doc.Info.Title   := 'mORMot2 PDF Cross-Platform Demo';
    Doc.Info.Author  := 'Portierungsprojekt';
    Doc.DefaultPaperSize :=  mormot.ui.pdf.psA4;

    // --- Page 1: Fonts & Text ---
    Doc.AddPage;
    C := Doc.VclCanvas;

    // Title — Tagged PDF: H1 heading
    Doc.BeginStructContent(psrH1);
    C.Font.Name  := SansFont;
    C.Font.Size  := 24;
    C.Font.Style := [fsBold];
    C.Font.Color := $800000;
    C.TextOut(40, 40, 'mORMot2 PDF Cross-Platform Test');
    Doc.EndStructContent;
    // its bookmark: TopPosition is in PDF points from the page bottom, the
    // heading sits 40 px (96 dpi) below the top edge
    Doc.CreateOutline('mORMot2 PDF Cross-Platform Test', 1,
      Doc.DefaultPageHeight - 40 * 72 / 96);

    // Font samples — Tagged PDF: paragraph (P)
    Doc.BeginStructContent(psrP);
    C.Font.Style := [];
    C.Font.Size  := 12;
    C.Font.Color := clBlack;
    C.TextOut(40, 100, SansFont + ' 12pt: The quick brown fox jumps over the lazy dog.');

    C.Font.Size := 9;
    C.TextOut(40, 125, SansFont + ' 9pt: Small text. 0123456789');

    C.Font.Name := SerifFont;
    C.Font.Size := 12;
    C.TextOut(40, 150, SerifFont + ' 12pt: Classic serif typeface.');

    C.Font.Name  := SansFont;
    C.Font.Style := [fsBold];
    C.TextOut(40, 175, SansFont + ' Bold 12pt: Bold text.');

    C.Font.Name  := MonoFont;
    C.Font.Style := [];
    C.Font.Size  := 11;
    C.TextOut(40, 200, MonoFont + ' 11pt: Monospace. function Foo: Integer;');

    C.Font.Name := SansFont;
    C.Font.Size := 10;
    C.TextOut(40, 240, 'Special chars: ä ö ü Ä Ö Ü ß € § °');
    Doc.EndStructContent;

    // --- Page 2: Vector graphics ---
    Doc.AddPage;
    C := Doc.VclCanvas;

    // Vector graphics — Tagged PDF: one figure (with /Alt text for screen
    // readers) for the whole page, the numbers included: they are part of the
    // drawing (text in an image), so a reader gets the /Alt instead of them
    // - PAC 2024 keeps a warning here, also listed under WCAG: "Possibly
    // inappropriate use of figure structure element". It stays when the
    // numbers are moved out of the figure, so it is accepted (ROADMAP W-1)
    Doc.BeginStructContent(psrFigure,
      'Vector graphics: three filled rectangles, three lines of increasing ' +
      'width, and the numbers 1 to 10 in growing font sizes, each inside its ' +
      'measured bounding box');

    // Rectangles with Brush + Pen
    C.Brush.Color := $DCDCFF;
    C.Pen.Color   := $C80000;
    C.Pen.Width   := 2;
    C.Rectangle(40, 40, 190, 120);

    C.Brush.Color := $DCFFDC;
    C.Pen.Color   := $009600;
    C.Rectangle(210, 40, 360, 120);

    C.Brush.Color := $FFDCDC;
    C.Pen.Color   := $0000C8;
    C.Rectangle(380, 40, 530, 120);

    // Lines
    C.Pen.Color := clBlack;
    C.Pen.Width := 1;
    C.Brush.Style := bsClear;
    C.MoveTo(40, 160); C.LineTo(550, 160);
    C.Pen.Width := 3;
    C.MoveTo(40, 180); C.LineTo(550, 180);
    C.Pen.Width := 6;
    C.MoveTo(40, 210); C.LineTo(550, 210);

    // Text with bounding boxes — increasing font size
    C.Pen.Width := 1;
    C.Font.Color := clBlack;
    MyY := 300;
    for MyX := 1 to 10 do
    begin
      MyXLoc   := MyX * 50;
      MyString := IntToStr(MyX);
      C.TextOut(MyXLoc, MyY, MyString);
      // measure and draw the box in single precision: the integer TCanvas API
      // would snap both edges back to the 1 px (0.75 pt) grid
      {$if defined(FPC) or not defined(MSWINDOWS)}
      VC := TPdfVclCanvas(C);
      VC.RectangleFrac(MyXLoc, MyY,
        MyXLoc + VC.TextWidthFrac(MyString),
        MyY + VC.TextHeightFrac(MyString));
      {$else}
      C.Rectangle(MyXLoc, MyY,
        MyXLoc + C.TextWidth(MyString),
        MyY + C.TextHeight(MyString));
      {$ifend}
      C.Font.Size := C.Font.Size + 2;
    end;
    Doc.EndStructContent; // Figure

    // --- Page 3: Table ---
    Doc.AddPage;
    C := Doc.VclCanvas;

    ColWidths[0] := 180; ColWidths[1] := 100;
    ColWidths[2] := 110; ColWidths[3] := 120;
    Headers[0] := 'Article';  Headers[1] := 'Qty';
    Headers[2] := 'Unit';     Headers[3] := 'Total';
    Data[0,0] := 'Bolt M4x10';    Data[0,1] := '100'; Data[0,2] := '0.05'; Data[0,3] := '5.00';
    Data[1,0] := 'Nut M4';        Data[1,1] := '100'; Data[1,2] := '0.03'; Data[1,3] := '3.00';
    Data[2,0] := 'Washer 4mm';    Data[2,1] := '200'; Data[2,2] := '0.02'; Data[2,3] := '4.00';
    Data[3,0] := 'Dowel 8mm';     Data[3,1] := '50';  Data[3,2] := '0.12'; Data[3,3] := '6.00';
    Data[4,0] := 'Tape 25mm';     Data[4,1] := '5';   Data[4,2] := '2.50'; Data[4,3] := '12.50';

    // Table — Tagged PDF: Table / THead|TBody / TR / TH|TD structure.
    // The row groups of ISO 32000-1 14.8.4.3.4 tell the header rows from the
    // data rows; TGDIPages emits them on its own, the low-level API asks the
    // caller to open them (ROADMAP R-14).
    Doc.BeginStructContent(psrTable);

    // Header-Zeile
    Doc.BeginStructContent(psrTHead);
    C.Brush.Color := $963232;
    C.Pen.Style   := psClear;
    C.Rectangle(40, 40, 550, 62);
    C.Font.Name  := SansFont;
    C.Font.Style := [fsBold];
    C.Font.Size  := 11;
    C.Font.Color := clWhite;
    Doc.BeginStructContent(psrTR);
    X := 45;
    for Col := 0 to 3 do
    begin
      Doc.BeginStructContent(psrTH);
      C.TextOut(X, 44, Headers[Col]);
      Doc.EndStructContent;
      Inc(X, ColWidths[Col]);
    end;
    Doc.EndStructContent; // TR
    Doc.EndStructContent; // THead

    // Datenzeilen
    Doc.BeginStructContent(psrTBody);
    C.Font.Name  := SansFont;
    C.Font.Style := [];
    C.Font.Size  := 10;
    C.Pen.Style  := psSolid;
    C.Pen.Color  := clSilver;
    C.Pen.Width  := 1;
    for Row := 0 to 4 do
    begin
      Y := 62 + Row * 22;
      if Odd(Row) then C.Brush.Color := $FFF0F0
      else             C.Brush.Color := clWhite;
      C.Rectangle(40, Y, 550, Y + 22);
      C.Font.Color := clBlack;
      Doc.BeginStructContent(psrTR);
      X := 45;
      for Col := 0 to 3 do
      begin
        Doc.BeginStructContent(psrTD);
        C.TextOut(X, Y + 4, Data[Row, Col]);
        Doc.EndStructContent;
        Inc(X, ColWidths[Col]);
      end;
      Doc.EndStructContent; // TR
    end;
    Doc.EndStructContent; // TBody
    Doc.EndStructContent; // Table

    Doc.SaveToFile('output_crossplat.pdf');
    writeln('PDF saved to output_crossplat.pdf');
  finally
    Doc.Free;
  end;
end.
