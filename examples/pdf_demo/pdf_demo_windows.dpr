program pdf_demo_windows;

{$ifdef FPC}
{$MODE DELPHI}
{$endif FPC}

uses
{$ifdef FPC}
  Interfaces,   // ‚Üê WICHTIG: registriert das Widgetset (Windows: win32/win64)
{$endif FPC}
  Windows,
  SysUtils,
  Graphics,
  Forms,        // f√ºr Application
  mormot.core.base,
  mormot.core.os,
  mormot.ui.pdf;

var
  Doc: TPdfDocumentGDI;
  C: TCanvas;
  Row, Col, X, Y: Integer;
  ColWidths: array[0..3] of Integer;
  Headers: array[0..3] of string;
  Data: array[0..4, 0..3] of string;
  MyX, MyY: Integer;
  MyXLoc: Integer;
  MyString: String;
begin
  Doc := TPdfDocumentGDI.Create;
  try
    Doc.Info.Title   := 'mORMot2 PDF Cross-Platform Demo';
    Doc.Info.Author  := 'Portierungsprojekt';
    Doc.EmbeddedTTF  := True;
    Doc.DefaultPaperSize := psA4;

    // --- Seite 1: Fonts & Text ---
    Doc.AddPage;
    C := Doc.VCLCanvas;

    // Title
    C.Font.Name  := 'Helvetica';
    C.Font.Size  := 24;
    C.Font.Style := [fsBold];
    C.Font.Color := $800000;
    C.TextOut(40, 40, 'mORMot2 PDF Cross-Platform Test');

    C.Font.Style := [];
    C.Font.Size  := 12;
    C.Font.Color := clBlack;
    C.TextOut(40, 100, 'Helvetica 12pt: The quick brown fox jumps over the lazy dog.');

    C.Font.Size := 9;
    C.TextOut(40, 125, 'Helvetica 9pt: Kleiner Text. 0123456789');

    C.Font.Name := 'Times New Roman';
    C.Font.Size := 12;
    C.TextOut(40, 150, 'Times New Roman 12pt: Klassische Serifenschrift.');

    C.Font.Name  := 'Helvetica';
    C.Font.Style := [fsBold];
    C.TextOut(40, 175, 'Helvetica Bold 12pt: Fettdruck.');

    C.Font.Name  := 'Courier New';
    C.Font.Style := [];
    C.Font.Size  := 11;
    C.TextOut(40, 200, 'Courier New 11pt: Monospace. function Foo: Integer;');

    C.Font.Name := 'Helvetica';
    C.Font.Size := 10;
    C.TextOut(40, 240, 'Umlaute und Sonderzeichen: ‰ ˆ ¸ ƒ ÷ ‹ ﬂ Ä ß © ô');

    // --- Seite 2: Vektorgrafik ---
    Doc.AddPage;
    C := Doc.VCLCanvas;

    // Rechtecke: Brush + Pen ‚Üí Rectangle
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

    // Linien
    C.Pen.Color := clBlack;
    C.Pen.Width := 1;
    C.Brush.Style := bsClear;
    C.MoveTo(40, 160); C.LineTo(550, 160);
    C.Pen.Width := 3;
    C.MoveTo(40, 180); C.LineTo(550, 180);
    C.Pen.Width := 6;
    C.MoveTo(40, 210); C.LineTo(550, 210);

    C.Pen.Width := 1;
    C.Font.Color := clBlack;
    MyY:=300;
    for MyX := 1 to 40  do begin
       MyXLoc:=MyX*120;
       MyString:=IntToStr(MyX);
       C.TextOut(MyXLoc, MyY, Mystring);
       C.Font.Size:= C.Font.Size+4;
       C.Rectangle(MyXLoc, MyY, MyXLoc+C.TextWidth(MyString), MyY+C.TextHeight(MyString));
    end;

    // --- Seite 3: Tabelle ---
    Doc.AddPage;
    C := Doc.VCLCanvas;

    ColWidths[0]:=180; ColWidths[1]:=100; ColWidths[2]:=110; ColWidths[3]:=120;
    Headers[0]:='Artikel'; Headers[1]:='Menge'; Headers[2]:='Einzel'; Headers[3]:='Gesamt';
    Data[0,0]:='Schraube M4x10'; Data[0,1]:='100'; Data[0,2]:='0,05 Ä'; Data[0,3]:='5,00 Ä';
    Data[1,0]:='Mutter M4';      Data[1,1]:='100'; Data[1,2]:='0,03 Ä'; Data[1,3]:='3,00 Ä';
    Data[2,0]:='Unterlegscheibe';Data[2,1]:='200'; Data[2,2]:='0,02 Ä'; Data[2,3]:='4,00 Ä';
    Data[3,0]:='D√ºbel 8mm';      Data[3,1]:='50';  Data[3,2]:='0,12 Ä'; Data[3,3]:='6,00 Ä';
    Data[4,0]:='Klebeband 25mm'; Data[4,1]:='5';   Data[4,2]:='2,50 Ä'; Data[4,3]:='12,50 Ä';

    // Header
    C.Brush.Color := $963232;
    C.Pen.Style   := psClear;
    C.Rectangle(40, 40, 550, 62);
    C.Font.Name  := 'Helvetica';
    C.Font.Style := [fsBold];
    C.Font.Size  := 11;
    C.Font.Color := clWhite;
    X := 45;
    for Col := 0 to 3 do begin
      C.TextOut(X, 44, Headers[Col]);
      Inc(X, ColWidths[Col]);
    end;

    // Datenzeilen
    C.Font.Style := [];
    C.Font.Size  := 10;
    C.Pen.Style  := psSolid;
    C.Pen.Color  := clSilver;
    C.Pen.Width  := 1;
    for Row := 0 to 4 do begin
      Y := 62 + Row * 22;
      if Odd(Row) then C.Brush.Color := $FFF0F0
      else             C.Brush.Color := clWhite;
      C.Rectangle(40, Y, 550, Y + 22);
      C.Font.Color := clBlack;
      X := 45;
      for Col := 0 to 3 do begin
        C.TextOut(X, Y + 4, Data[Row, Col]);
        Inc(X, ColWidths[Col]);
      end;
    end;

    Doc.SaveToFile('output_golden_master.pdf');
  finally
    Doc.Free;
  end;
end.
