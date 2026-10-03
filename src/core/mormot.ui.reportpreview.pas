/// Preview Window and Printing for TGDIPages
// - this unit is a part of the Open Source Synopse mORMot framework 2,
// licensed under a MPL/GPL/LGPL three license - see LICENSE.md
unit mormot.ui.reportpreview;

{
  *****************************************************************************

   Preview Window and Printing for TGDIPages (LCL)
   - ShowReportPreview: the preview window
   - PrintReport: printing through the LCL printer
   - Kept apart from mormot.ui.report, so that a console program records,
     lays out and exports a report without forms or printer

  *****************************************************************************
}

interface

{$I mormot.defines.inc}

uses
  Classes,
  SysUtils,
  Types,
  Math,
  Graphics,
  Controls,
  Forms,
  ExtCtrls,
  StdCtrls,
  Dialogs,
  LCLType,
  Printers,
  mormot.core.base,
  mormot.core.unicode,
  mormot.ui.report;

/// show the pages of Report in a modal preview window
// - zoom (buttons, edit field, Ctrl+wheel, Ctrl +/-/0), page navigation
// (buttons, PgUp/PgDn/Home/End)
procedure ShowReportPreview(Report: TGDIPages);

/// print pages [From..To_] of Report on the default printer
// - the range is clipped to the existing pages; the defaults print them all
procedure PrintReport(Report: TGDIPages; From: integer = 0;
  To_: integer = MaxInt);


implementation

const
  /// U+2212 MINUS SIGN
  MINUS_SIGN: RawUtf8 = {$ifdef HASCODEPAGE} #$2212 {$else} #$E2#$88#$92 {$endif};

type
  /// state and event handlers of one modal preview window
  TReportPreview = class
  private
    fReport:     TGDIPages;
    fCurrPage:   Integer;
    fTotalPages: Integer;
    fLblPage:    TLabel;
    fEdtZoom:    TEdit;        // editable zoom percentage input
    fPaintBox:   TPaintBox;
    fScrollBox:  TScrollBox;   // scrollable container for zoomed page
    fW:          Integer;      // base preview width @ 96 DPI (unzoomed)
    fH:          Integer;      // base preview height @ 96 DPI (unzoomed)
    fZoom:       Double;       // zoom factor (1.0 = 100%)
    procedure UpdateLabel;
    procedure GoToPage(Page: Integer);
    procedure ApplyZoom;
    procedure DoPaint(Sender: TObject);
    procedure DoPrev(Sender: TObject);
    procedure DoNext(Sender: TObject);
    procedure DoZoomIn(Sender: TObject);
    procedure DoZoomOut(Sender: TObject);
    procedure DoFitPage(Sender: TObject);
    procedure DoFitWidth(Sender: TObject);
    procedure DoFormResize(Sender: TObject);
    procedure DoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DoMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure DoZoomEdit(Sender: TObject);
  public
    constructor Create(Report: TGDIPages);
    procedure Show;
  end;

constructor TReportPreview.Create(Report: TGDIPages);
begin
  inherited Create;
  fReport := Report;
end;

procedure TReportPreview.UpdateLabel;
begin
  if fLblPage <> nil then
    fLblPage.Caption := Format('Page %d / %d', [fCurrPage + 1, fTotalPages]);
end;

procedure TReportPreview.GoToPage(Page: Integer);
begin
  if (Page = fCurrPage) or (Page < 0) or (Page >= fTotalPages) then
    Exit;
  fCurrPage := Page;
  UpdateLabel;
  if fPaintBox <> nil then
    fPaintBox.Invalidate;
end;

procedure TReportPreview.DoPaint(Sender: TObject);
var
  PB: TPaintBox;
  ZW, ZH: Integer;
begin
  PB := TPaintBox(Sender);
  ZW := Round(fW * fZoom);
  ZH := Round(fH * fZoom);
  PB.Canvas.Brush.Color := clWhite;
  PB.Canvas.FillRect(Rect(0, 0, ZW, ZH));
  if (fCurrPage >= 0) and (fCurrPage < fTotalPages) then
    fReport.RenderPageToCanvas(PB.Canvas, fCurrPage, ZW, ZH);
end;

procedure TReportPreview.DoPrev(Sender: TObject);
begin
  GoToPage(fCurrPage - 1);
end;

procedure TReportPreview.DoNext(Sender: TObject);
begin
  GoToPage(fCurrPage + 1);
end;

procedure TReportPreview.ApplyZoom;
var
  ZW, ZH, CX, CY: Integer;
begin
  if (fPaintBox = nil) or (fScrollBox = nil) then
    Exit;
  ZW := Round(fW * fZoom);
  ZH := Round(fH * fZoom);
  fPaintBox.Width  := ZW;
  fPaintBox.Height := ZH;
  CX := (fScrollBox.ClientWidth  - ZW) div 2;
  CY := (fScrollBox.ClientHeight - ZH) div 2;
  if CX < GRAY_MARGIN then CX := GRAY_MARGIN;
  if CY < GRAY_MARGIN then CY := GRAY_MARGIN;
  fPaintBox.Left := CX;
  fPaintBox.Top  := CY;
  if fEdtZoom <> nil then
    fEdtZoom.Text := Format('%d%%', [Round(fZoom * 100)]);
  fPaintBox.Invalidate;
end;

procedure TReportPreview.DoZoomIn(Sender: TObject);
begin
  if fZoom < 4.0 then
  begin
    fZoom := fZoom + 0.25;
    if fZoom > 4.0 then
      fZoom := 4.0;
    ApplyZoom;
  end;
end;

procedure TReportPreview.DoZoomOut(Sender: TObject);
begin
  if fZoom > 0.25 then
  begin
    fZoom := fZoom - 0.25;
    if fZoom < 0.25 then
      fZoom := 0.25;
    ApplyZoom;
  end;
end;

procedure TReportPreview.DoFitPage(Sender: TObject);
var
  ZX, ZY: Double;
begin
  if fScrollBox = nil then
    Exit;
  ZX := (fScrollBox.ClientWidth  - 2 * GRAY_MARGIN) / fW;
  ZY := (fScrollBox.ClientHeight - 2 * GRAY_MARGIN) / fH;
  fZoom := Min(ZX, ZY);
  if fZoom < 0.1 then
    fZoom := 0.1;
  ApplyZoom;
end;

procedure TReportPreview.DoFitWidth(Sender: TObject);
begin
  if fScrollBox = nil then
    Exit;
  fZoom := (fScrollBox.ClientWidth - 2 * GRAY_MARGIN) / fW;
  if fZoom < 0.1 then
    fZoom := 0.1;
  ApplyZoom;
end;

procedure TReportPreview.DoFormResize(Sender: TObject);
begin
  ApplyZoom;
  if fLblPage <> nil then
    fLblPage.Left := (fLblPage.Parent.Width - fLblPage.Width) div 2;
end;

procedure TReportPreview.DoKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_PRIOR:
      DoPrev(nil);
    VK_NEXT:
      DoNext(nil);
    VK_HOME:
      GoToPage(0);
    VK_END:
      GoToPage(fTotalPages - 1);
    VK_OEM_PLUS, VK_ADD:
      if ssCtrl in Shift then
        DoZoomIn(nil);
    VK_OEM_MINUS, VK_SUBTRACT:
      if ssCtrl in Shift then
        DoZoomOut(nil);
    VK_0, VK_NUMPAD0:
      if ssCtrl in Shift then
      begin
        fZoom := 1.0;
        ApplyZoom;
      end;
  end;
end;

procedure TReportPreview.DoMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      DoZoomIn(nil)
    else
      DoZoomOut(nil);
    Handled := True;
  end;
end;

procedure TReportPreview.DoZoomEdit(Sender: TObject);
var
  S: string;
  ZoomVal: Double;
  Code: Integer;
begin
  if fEdtZoom = nil then Exit;
  S := Trim(fEdtZoom.Text);
  if (Length(S) > 0) and (S[Length(S)] = '%') then
    S := Trim(Copy(S, 1, Length(S) - 1));
  Val(S, ZoomVal, Code);
  if Code <> 0 then
  begin
    fEdtZoom.Text := Format('%d%%', [Round(fZoom * 100)]);
    Exit;
  end;
  ZoomVal := ZoomVal / 100.0;
  if ZoomVal < 0.25 then ZoomVal := 0.25;
  if ZoomVal > 4.0  then ZoomVal := 4.0;
  fZoom := ZoomVal;
  ApplyZoom;
end;

procedure TReportPreview.Show;
var
  Form:               TForm;
  ScrollBox:          TScrollBox;
  PaintBox:           TPaintBox;
  TopPanel, BtnPanel: TPanel;
  BtnZoomOut, BtnZoomIn,
  BtnFitPage, BtnFitWidth: TButton;
  BtnPrev, BtnNext,
  BtnClose:           TButton;
  LblPage:            TLabel;
  EdtZoom:            TEdit;
  First:              TPageData;
begin
  fTotalPages := fReport.PageCount;
  if fTotalPages = 0 then
  begin
    ShowMessage('No pages available.');
    Exit;
  end;
  fCurrPage := 0;
  fZoom := 1.0;
  // Base preview size @ 96 DPI (unzoomed reference, same DPI as PDF export)
  First := fReport.Pages[0];
  if First.PageWidth > 0 then
  begin
    fW := MMToPixels(First.PageWidth + fReport.MarginLeft + fReport.MarginRight, 96);
    fH := MMToPixels(First.PageHeight + fReport.MarginTop + fReport.MarginBottom, 96);
  end
  else
  begin
    fW := 793;  // A4 portrait fallback: 210mm @ 96 DPI
    fH := 1175; // 297mm @ 96 DPI
  end;
  Form := TForm.Create(nil);
  try
    Form.Caption := Utf8ToString(fReport.Title);
    if Form.Caption = '' then
      Form.Caption := 'Print Preview';
    Form.Position    := poScreenCenter;
    Form.BorderStyle := bsSizeable;
    Form.KeyPreview  := True;
    Form.Width  := Min(Round(Screen.Width  * 0.8), 1200);
    Form.Height := Min(Round(Screen.Height * 0.8), 900);
    Form.OnResize    := DoFormResize;
    Form.OnKeyDown   := DoKeyDown;
    // --- top toolbar panel (zoom controls) ---
    TopPanel := TPanel.Create(Form);
    TopPanel.Parent     := Form;
    TopPanel.Align      := alTop;
    TopPanel.Height     := 36;
    TopPanel.BevelOuter := bvNone;
    BtnZoomOut := TButton.Create(Form);
    BtnZoomOut.Parent  := TopPanel;
    BtnZoomOut.Caption := Utf8ToString(MINUS_SIGN);
    BtnZoomOut.SetBounds(8, 4, 32, 28);
    BtnZoomOut.OnClick := DoZoomOut;
    EdtZoom := TEdit.Create(Form);
    EdtZoom.Parent    := TopPanel;
    EdtZoom.SetBounds(44, 6, 60, 24);
    EdtZoom.Alignment := taCenter;
    EdtZoom.OnEditingDone := DoZoomEdit;
    fEdtZoom          := EdtZoom;
    BtnZoomIn := TButton.Create(Form);
    BtnZoomIn.Parent  := TopPanel;
    BtnZoomIn.Caption := '+';
    BtnZoomIn.SetBounds(108, 4, 32, 28);
    BtnZoomIn.OnClick := DoZoomIn;
    BtnFitPage := TButton.Create(Form);
    BtnFitPage.Parent  := TopPanel;
    BtnFitPage.Caption := 'Fit Page';
    BtnFitPage.SetBounds(152, 4, 90, 28);
    BtnFitPage.OnClick := DoFitPage;
    BtnFitWidth := TButton.Create(Form);
    BtnFitWidth.Parent  := TopPanel;
    BtnFitWidth.Caption := 'Fit Width';
    BtnFitWidth.SetBounds(248, 4, 90, 28);
    BtnFitWidth.OnClick := DoFitWidth;
    // --- bottom panel (page navigation) ---
    BtnPanel := TPanel.Create(Form);
    BtnPanel.Parent     := Form;
    BtnPanel.Align      := alBottom;
    BtnPanel.Height     := 42;
    BtnPanel.BevelOuter := bvNone;
    BtnPrev := TButton.Create(Form);
    BtnPrev.Parent  := BtnPanel;
    BtnPrev.Caption := '< Back';
    BtnPrev.SetBounds(8, 6, 84, 28);
    BtnPrev.OnClick := DoPrev;
    LblPage := TLabel.Create(Form);
    LblPage.Parent    := BtnPanel;
    LblPage.AutoSize  := False;
    LblPage.Width     := 140;
    LblPage.Left      := (BtnPanel.Width - 140) div 2;
    LblPage.Top       := 14;
    LblPage.Alignment := taCenter;
    fLblPage          := LblPage;
    UpdateLabel;
    BtnClose := TButton.Create(Form);
    BtnClose.Parent      := BtnPanel;
    BtnClose.Caption     := 'Close';
    BtnClose.ModalResult := mrOk;
    BtnClose.Anchors     := [akTop, akRight];
    BtnClose.SetBounds(BtnPanel.Width - 112, 6, 96, 28);
    BtnNext := TButton.Create(Form);
    BtnNext.Parent  := BtnPanel;
    BtnNext.Caption := 'Next >';
    BtnNext.Anchors := [akTop, akRight];
    BtnNext.SetBounds(BtnPanel.Width - 208, 6, 84, 28);
    BtnNext.OnClick := DoNext;
    // --- scroll box (fills center area) ---
    ScrollBox := TScrollBox.Create(Form);
    ScrollBox.Parent      := Form;
    ScrollBox.Align       := alClient;
    ScrollBox.Color       := clSilver;
    ScrollBox.AutoScroll  := True;
    ScrollBox.BorderStyle := bsNone;
    ScrollBox.OnMouseWheel := DoMouseWheel;
    fScrollBox := ScrollBox;
    // --- paint box (inside scroll box, explicit size set by ApplyZoom) ---
    PaintBox := TPaintBox.Create(Form);
    PaintBox.Parent  := ScrollBox;
    PaintBox.Color   := clWhite;
    fPaintBox := PaintBox;
    PaintBox.OnPaint := DoPaint;
    ApplyZoom;
    Form.ShowModal;
  finally
    fPaintBox  := nil;
    fScrollBox := nil;
    fLblPage   := nil;
    fEdtZoom   := nil;
    Form.Free;
  end;
end;

procedure ShowReportPreview(Report: TGDIPages);
var
  Preview: TReportPreview;
begin
  Preview := TReportPreview.Create(Report);
  try
    Preview.Show;
  finally
    Preview.Free;
  end;
end;

procedure PrintReport(Report: TGDIPages; From, To_: integer);
var
  i: Integer;
begin
  if To_ >= Report.PageCount then
    To_ := Report.PageCount - 1;
  if From < 0 then
    From := 0;
  if From > To_ then
    Exit;
  Printer.BeginDoc;
  try
    for i := From to To_ do
    begin
      if i > From then
        Printer.NewPage;
      Report.RenderPageToCanvas(Printer.Canvas, i, Printer.PageWidth,
        Printer.PageHeight);
    end;
  finally
    Printer.EndDoc;
  end;
end;

end.
