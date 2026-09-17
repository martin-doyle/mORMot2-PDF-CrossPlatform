/// Cross-platform VCL/LCL canvas recording for the PDF engine
// - provides TPdfDocumentVcl and TPdfVclCanvas as cross-platform replacements
//   for TPdfDocumentGdi / TMetaFileCanvas + TPdfEnum on non-Windows systems
// - on Windows, use TPdfDocumentGdi (the original) — it is faster and more
//   complete (Uniscribe, GdiPlus, EMF comments, opacity...)
// - on Unix/macOS, use TPdfDocumentVcl with identical TCanvas API
unit mormot.ui.pdfcanvas;

{
  *****************************************************************************

    Cross-Platform Recording Canvas
    - TPdfVclCanvas   — TCanvas descendant that translates draw calls to PDF
    - TPdfDocumentVcl — TPdfDocument descendant exposing VclCanvas property

    Architecture:
      Windows:    TCanvas → TMetaFile (EMF) → TPdfEnum → TPdfCanvas → PDF
      CrossPlat:  TCanvas → TPdfVclCanvas  ──────────→ TPdfCanvas → PDF

    The ~15 canvas methods that TPdfEnum handles for the golden-master demo
    are all overridden here. State (pen color/width, brush color/style, font)
    is synchronized lazily before each draw operation.

  *****************************************************************************
}

interface

{$ifdef FPC}
  {$mode delphi}
{$endif FPC}

uses
  SysUtils,
  Classes,
  Types,
  Graphics,       // TCanvas, TColor, TFont, TPen, TBrush, TRect, TPoint
  LCLIntf,        // CreateCompatibleDC / DeleteDC for font metrics
  LCLType,        // HDC type
  mormot.core.base,
  mormot.core.unicode,
  mormot.pdf.types,  // TPdfStructRole (Tagged PDF)
  mormot.ui.pdf;     // TPdfDocument, TPdfCanvas, TPdfPage

type
  /// Re-export TPdfALevel from mormot.ui.pdf to allow importing only mormot.pdf.vclcanvas
  TPdfALevel = mormot.ui.pdf.TPdfALevel;

  /// Re-export TPdfFontMeasurer so TGDIPages can lay out its pages with the
  // metrics of the PDF font engine without pulling all of mormot.ui.pdf — that
  // unit re-exports Windows-style TRect/TPoint which clash with the LCL ones
  TPdfFontMeasurer = mormot.ui.pdf.TPdfFontMeasurer;

  /// coordinate scaling state used by TPdfVclCanvas
  TPdfVclScale = record
    // origin offset in PDF points
    OriginX, OriginY: single;
    // pixels-per-point ratio (screen DPI / 72)
    ScaleX, ScaleY: single;
  end;

  // forward declaration
  TPdfDocumentVcl = class;

  /// TCanvas descendant that records draw operations directly into a TPdfCanvas
  // - replaces TMetaFileCanvas + TPdfEnum for cross-platform use
  // - synchronizes Pen/Brush/Font state to PDF graphics state before each draw
  TPdfVclCanvas = class(TCanvas)
  private
    fPdfCanvas:  TPdfCanvas;
    fPdfDoc:     TPdfDocumentVcl;
    fScale:      TPdfVclScale;
    fMeasureDC:  HDC;   // dummy DC so TextWidth/TextHeight work without a widget
    // cached state for SetFont (expensive) and SetRGBStrokeColor
    fLastPenColor:  TColor;
    fLastPenWidth:  integer;
    fLastFontName:  string;
    fLastFontSize:  integer;
    fLastFontStyle: TFontStyles;
    fLastFontColor: TColor;
    fStateValid:    boolean;
    /// convert pixel X coordinate to PDF point
    function PxToPtX(AX: integer): single;
    /// convert pixel Y coordinate to PDF point (flips Y axis)
    function PxToPtY(AY: integer): single;
    /// sync pen state to PDF if changed
    procedure SyncPen;
    /// sync brush state to PDF if changed
    procedure SyncBrush;
    /// sync font state to PDF if changed
    procedure SyncFont;
    /// apply the PDF fill+stroke operation based on current brush/pen
    procedure FillAndStroke;
  protected
    procedure DoMoveTo(X, Y: integer); override;  // TCanvas.MoveTo calls this
    procedure DoLineTo(X, Y: integer); override;  // TCanvas.LineTo calls this
  public
    procedure TextOut(X, Y: integer; const AText: string); override;
    /// TextOut at a sub-pixel position
    // - TCanvas.TextOut only takes integers, so a caller that knows its layout
    // more precisely than whole screen pixels would lose that precision at the
    // 0.75 pt (1 px @ 96 DPI) grid; TGDIPages uses this overload to place text
    // at the position it actually computed (ROADMAP B-5)
    procedure TextOutFrac(X, Y: single; const AText: string);
    procedure Rectangle(X1, Y1, X2, Y2: integer); override;
    procedure Ellipse(X1, Y1, X2, Y2: integer); override;
    procedure RoundRect(X1, Y1, X2, Y2, X3, Y3: integer); override;
    procedure FillRect(const ARect: TRect); reintroduce;
    procedure Polyline(const Points: array of TPoint); reintroduce;
    procedure Polygon(const Points: array of TPoint); reintroduce;
    procedure Draw(X, Y: integer; AGraphic: TGraphic); override;
    procedure StretchDraw(const ARect: TRect; AGraphic: TGraphic); reintroduce;
  public
    constructor Create(APdfDoc: TPdfDocumentVcl; APdfCanvas: TPdfCanvas);
    destructor Destroy; override;
    /// reset all cached state (call when switching to a new page)
    procedure ResetState;
    /// the underlying TPdfCanvas this recording canvas writes to
    property PdfCanvas: TPdfCanvas read fPdfCanvas;
  end;

  /// TPdfDocument descendant that exposes a TCanvas-compatible interface
  // - use instead of TPdfDocumentGdi on non-Windows systems
  // - API is identical: AddPage returns a page, VclCanvas returns the canvas
  TPdfDocumentVcl = class(TPdfDocument)
  private
    fVclCanvas: TPdfVclCanvas;
    fCurrentPage: TPdfPage;
    function GetVclCanvas: TCanvas;
  public
    /// create the document (same parameters as TPdfDocument.Create)
    constructor Create(AUseOutlines: boolean = false;
      ACodePage: integer = 0; APdfA: TPdfALevel = pdfaNone
      {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption = nil{$endif});
    destructor Destroy; override;
    /// add a new page and prepare the VclCanvas for drawing on it
    function AddPage: TPdfPage; reintroduce;
    /// open a marked content sequence for Tagged PDF (ISO 32000-1 §14)
    // - call before drawing content, EndStructContent must follow
    // - no-op when Tagged = false
    // - AAltText is written as /Alt for Figure elements (image accessibility)
    procedure BeginStructContent(ARole: TPdfStructRole;
      const AAltText: RawUtf8 = '');
    /// open a struct element without any marked-content region
    // - a plain inline run then adds one via ContinueStructContent, a styled
    // run becomes a nested Span (ROADMAP B-3)
    procedure BeginStructGroup(ARole: TPdfStructRole);
    /// open one more marked-content region for the innermost open element
    procedure ContinueStructContent;
    /// close the region of the innermost open element, which stays open as
    // the parent of the elements nested next
    procedure SuspendStructContent;
    /// close the marked content sequence opened by BeginStructContent
    procedure EndStructContent;
    /// index of the struct element opened by the last BeginStructContent
    // - to be passed to ResumeStructContent, -1 when Tagged = false
    function LastStructContent: integer;
    /// reopen an already closed struct element on the current page
    // - lets one logical block interrupted by a page break stay one tag
    // - must be paired with EndStructContent
    procedure ResumeStructContent(AStructIndex: integer;
      AOpenRegion: boolean = true);
    /// set the fill (non-stroking) opacity for subsequent drawing operations
    // - Value is clamped to [0..1]: 0=fully transparent, 1=fully opaque
    procedure SetFillAlpha(Value: single);
    /// set the stroke opacity for subsequent drawing operations
    // - Value is clamped to [0..1]: 0=fully transparent, 1=fully opaque
    procedure SetStrokeAlpha(Value: single);
    /// the recording canvas — use this to draw on the current page
    // - identical API to TPdfDocumentGdi.VclCanvas
    property VclCanvas: TCanvas read GetVclCanvas;
  end;

const
  /// Re-export PDF/A level constants from mormot.ui.pdf
  pdfaNone = mormot.ui.pdf.pdfaNone;
  pdfa1A = mormot.ui.pdf.pdfa1A;
  pdfa1B = mormot.ui.pdf.pdfa1B;
  pdfa2A = mormot.ui.pdf.pdfa2A;
  pdfa2B = mormot.ui.pdf.pdfa2B;
  pdfa3A = mormot.ui.pdf.pdfa3A;
  pdfa3B = mormot.ui.pdf.pdfa3B;

implementation

// ---------------------------------------------------------------------------
// TPdfVclCanvas
// ---------------------------------------------------------------------------

constructor TPdfVclCanvas.Create(APdfDoc: TPdfDocumentVcl;
  APdfCanvas: TPdfCanvas);
begin
  inherited Create;
  fPdfDoc    := APdfDoc;
  fPdfCanvas := APdfCanvas;
  // default coordinate scale: 1 pixel = 1 point (approx for screen at 72 DPI)
  // For a proper mapping: scale = 72 / screen_dpi
  // TPdfDocument.fScreenLogPixels is set in Create (GetDeviceCaps/96 on POSIX)
  if APdfDoc.fScreenLogPixels > 0 then
  begin
    fScale.ScaleX := 72.0 / APdfDoc.fScreenLogPixels;
    fScale.ScaleY := 72.0 / APdfDoc.fScreenLogPixels;
  end
  else
  begin
    fScale.ScaleX := 1.0;
    fScale.ScaleY := 1.0;
  end;
  fScale.OriginX := 0;
  fScale.OriginY := 0;
  // Create a memory DC so that TCanvas.TextWidth/TextHeight (which call
  // RequiredState([csHandleValid])) work without a visible window.
  // All actual drawing is intercepted by our overrides and goes to fPdfCanvas.
  fMeasureDC := LCLIntf.CreateCompatibleDC(0);
  Handle := fMeasureDC;
  ResetState;
end;

destructor TPdfVclCanvas.Destroy;
begin
  Handle := 0;
  if fMeasureDC <> 0 then
  begin
    LCLIntf.DeleteDC(fMeasureDC);
    fMeasureDC := 0;
  end;
  inherited;
end;

procedure TPdfVclCanvas.ResetState;
begin
  fLastPenColor   := clBlack;
  fLastPenWidth  := 1;
  fLastFontName  := 'Helvetica';
  fLastFontSize   := 10;
  fLastFontStyle  := [];
  fLastFontColor  := clBlack;
  fStateValid     := false;
end;

function TPdfVclCanvas.PxToPtX(AX: integer): single;
begin
  result := (AX + fScale.OriginX) * fScale.ScaleX;
end;

function TPdfVclCanvas.PxToPtY(AY: integer): single;
var
  pageH: single;
begin
  // PDF Y=0 is at the bottom; screen Y=0 is at the top
  pageH := fPdfDoc.DefaultPageHeight;
  if pageH <= 0 then
    pageH := 841; // A4 fallback
  result := pageH - (AY + fScale.OriginY) * fScale.ScaleY;
end;

procedure TPdfVclCanvas.SyncPen;
begin
  if fStateValid and (Pen.Color = fLastPenColor) and
     (Pen.Width = fLastPenWidth) then
    exit;
  fLastPenColor := Pen.Color;
  fLastPenWidth := Pen.Width;
  fPdfCanvas.SetRGBStrokeColor(ColorToRGB(Pen.Color));
  fPdfCanvas.SetLineWidth(Pen.Width * fScale.ScaleX);
end;

procedure TPdfVclCanvas.SyncBrush;
begin
  // Always reapply fill color: SyncFont may have overwritten it for text
  if Brush.Style <> bsClear then
    fPdfCanvas.SetRGBFillColor(ColorToRGB(Brush.Color));
end;

procedure TPdfVclCanvas.SyncFont;
var
  style: TPdfFontStyles;
begin
  // Always reapply fill color for text: SyncBrush may have overwritten it
  if fStateValid and (Font.Name = fLastFontName) and
     (Font.Size = fLastFontSize) and (Font.Style = fLastFontStyle) then
  begin
    // SetFont is expensive — skip it when font attributes are unchanged,
    // but always reapply the fill color because shape draws may have changed it
    if Font.Color <> fLastFontColor then
      fLastFontColor := Font.Color;
    fPdfCanvas.SetRGBFillColor(ColorToRGB(Font.Color));
    exit;
  end;
  fLastFontName  := Font.Name;
  fLastFontSize  := Font.Size;
  fLastFontStyle := Font.Style;
  fLastFontColor := Font.Color;
  byte(style) := 0;
  if fsBold      in Font.Style then include(style, pfsBold);
  if fsItalic    in Font.Style then include(style, pfsItalic);
  if fsUnderline in Font.Style then include(style, pfsUnderline);
  if fsStrikeOut in Font.Style then include(style, pfsStrikeOut);
  fPdfCanvas.SetFont(Font.Name, Abs(Font.Size), style, Font.Charset);
  fPdfCanvas.SetRGBFillColor(ColorToRGB(Font.Color));
  fStateValid := true;
end;

procedure TPdfVclCanvas.FillAndStroke;
begin
  if Brush.Style = bsClear then
    fPdfCanvas.Stroke
  else if Pen.Style = psClear then
    fPdfCanvas.Fill
  else
    fPdfCanvas.FillStroke;
end;

// --- Text ---

procedure TPdfVclCanvas.TextOut(X, Y: integer; const AText: string);
begin
  TextOutFrac(X, Y, AText);
end;

procedure TPdfVclCanvas.TextOutFrac(X, Y: single; const AText: string);
var
  W: WideString;
  pageH: single;
begin
  if AText = '' then
    exit;
  SyncFont;
  pageH := fPdfDoc.DefaultPageHeight;
  if pageH <= 0 then
    pageH := 841; // A4 fallback
  // FPC string is UTF-8; TPdfCanvas.TextOutW handles Unicode→WinAnsi/CID mapping
  W := UTF8Decode(AText);
  fPdfCanvas.TextOutW((X + fScale.OriginX) * fScale.ScaleX,
    pageH - (Y + Font.Size + fScale.OriginY) * fScale.ScaleY, pointer(W));
end;

// --- Shapes ---

procedure TPdfVclCanvas.Rectangle(X1, Y1, X2, Y2: integer);
var
  x, y, w, h: single;
begin
  SyncPen;
  SyncBrush;
  x := PxToPtX(X1);
  y := PxToPtY(Y2);   // bottom in PDF coords
  w := (X2 - X1) * fScale.ScaleX;
  h := (Y2 - Y1) * fScale.ScaleY;
  fPdfCanvas.Rectangle(x, y, w, h);
  FillAndStroke;
end;

procedure TPdfVclCanvas.Ellipse(X1, Y1, X2, Y2: integer);
var
  cx, cy, rx, ry: single;
begin
  SyncPen;
  SyncBrush;
  cx := PxToPtX((X1 + X2) div 2);
  cy := PxToPtY((Y1 + Y2) div 2);
  rx := (X2 - X1) * fScale.ScaleX / 2;
  ry := (Y2 - Y1) * fScale.ScaleY / 2;
  fPdfCanvas.Ellipse(cx, cy, rx, ry);
  FillAndStroke;
end;

procedure TPdfVclCanvas.FillRect(const ARect: TRect);
begin
  Brush.Style := bsSolid;
  Pen.Style   := psClear;
  Rectangle(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom);
  Pen.Style := psSolid;
end;

// --- Lines ---

procedure TPdfVclCanvas.DoMoveTo(X, Y: integer);
begin
  SyncPen;
  fPdfCanvas.MoveTo(PxToPtX(X), PxToPtY(Y));
end;

procedure TPdfVclCanvas.DoLineTo(X, Y: integer);
begin
  SyncPen;
  fPdfCanvas.LineTo(PxToPtX(X), PxToPtY(Y));
  fPdfCanvas.Stroke;
end;

// --- Rounded Rectangle ---

procedure TPdfVclCanvas.RoundRect(X1, Y1, X2, Y2, X3, Y3: integer);
begin
  SyncPen;
  SyncBrush;
  // TPdfCanvas.RoundRect(x1, y1, x2, y2, cx, cy) where y1=bottom, y2=top in PDF coords
  // X3, Y3 are the corner ellipse dimensions (GDI convention); pass them directly
  // as cx/cy — this matches the existing EMF handler (TPdfCanvas.RoundRectI) behavior
  fPdfCanvas.RoundRect(
    PxToPtX(X1), PxToPtY(Y2),
    PxToPtX(X2), PxToPtY(Y1),
    X3 * fScale.ScaleX,
    Y3 * fScale.ScaleY);
  FillAndStroke;
end;

// --- Polyline / Polygon ---

procedure TPdfVclCanvas.Polyline(const Points: array of TPoint);
var
  i: integer;
begin
  if Length(Points) < 2 then
    exit;
  SyncPen;
  fPdfCanvas.MoveTo(PxToPtX(Points[0].X), PxToPtY(Points[0].Y));
  for i := 1 to high(Points) do
    fPdfCanvas.LineTo(PxToPtX(Points[i].X), PxToPtY(Points[i].Y));
  fPdfCanvas.Stroke;
end;

procedure TPdfVclCanvas.Polygon(const Points: array of TPoint);
var
  i: integer;
begin
  if Length(Points) < 2 then
    exit;
  SyncPen;
  SyncBrush;
  fPdfCanvas.MoveTo(PxToPtX(Points[0].X), PxToPtY(Points[0].Y));
  for i := 1 to high(Points) do
    fPdfCanvas.LineTo(PxToPtX(Points[i].X), PxToPtY(Points[i].Y));
  // close the path and apply fill/stroke based on current Brush/Pen style
  if Brush.Style = bsClear then
    fPdfCanvas.ClosePathStroke
  else if Pen.Style = psClear then
    fPdfCanvas.Fill    // Fill implicitly closes the path per PDF spec
  else
    fPdfCanvas.ClosepathFillStroke;
end;

// --- Bitmap drawing ---

procedure TPdfVclCanvas.Draw(X, Y: integer; AGraphic: TGraphic);
var
  bmp:   TBitmap;
  owned: boolean;
  xObj:  PdfString;
begin
  if (AGraphic = nil) or AGraphic.Empty then
    exit;
  owned := not (AGraphic is TBitmap);
  if owned then
  begin
    bmp := TBitmap.Create;
    bmp.Width  := AGraphic.Width;
    bmp.Height := AGraphic.Height;
    bmp.Canvas.Draw(0, 0, AGraphic);
  end
  else
    bmp := TBitmap(AGraphic);
  try
    xObj := fPdfDoc.CreateOrGetImage(bmp);
    if xObj = '' then
      exit;
    fPdfCanvas.DrawXObject(
      PxToPtX(X),
      PxToPtY(Y + AGraphic.Height),   // bottom-left in PDF coords
      AGraphic.Width  * fScale.ScaleX,
      AGraphic.Height * fScale.ScaleY,
      xObj);
  finally
    if owned then
      bmp.Free;
  end;
end;

procedure TPdfVclCanvas.StretchDraw(const ARect: TRect; AGraphic: TGraphic);
var
  bmp:   TBitmap;
  owned: boolean;
  xObj:  PdfString;
begin
  if (AGraphic = nil) or AGraphic.Empty then
    exit;
  owned := not (AGraphic is TBitmap);
  if owned then
  begin
    bmp := TBitmap.Create;
    bmp.Width  := AGraphic.Width;
    bmp.Height := AGraphic.Height;
    bmp.Canvas.Draw(0, 0, AGraphic);
  end
  else
    bmp := TBitmap(AGraphic);
  try
    xObj := fPdfDoc.CreateOrGetImage(bmp);
    if xObj = '' then
      exit;
    fPdfCanvas.DrawXObject(
      PxToPtX(ARect.Left),
      PxToPtY(ARect.Bottom),           // bottom-left in PDF coords
      (ARect.Right  - ARect.Left) * fScale.ScaleX,
      (ARect.Bottom - ARect.Top)  * fScale.ScaleY,
      xObj);
  finally
    if owned then
      bmp.Free;
  end;
end;

// ---------------------------------------------------------------------------
// TPdfDocumentVcl
// ---------------------------------------------------------------------------

constructor TPdfDocumentVcl.Create(AUseOutlines: boolean; ACodePage: integer;
  APdfA: TPdfALevel
  {$ifdef USE_PDFSECURITY}; AEncryption: TPdfEncryption{$endif});
begin
  inherited Create(AUseOutlines, ACodePage, APdfA
    {$ifdef USE_PDFSECURITY}, AEncryption{$endif});
  // fVclCanvas is created on first AddPage call
end;

destructor TPdfDocumentVcl.Destroy;
begin
  fVclCanvas.Free;
  inherited;
end;

function TPdfDocumentVcl.GetVclCanvas: TCanvas;
begin
  result := fVclCanvas;
end;

function TPdfDocumentVcl.AddPage: TPdfPage;
begin
  result := inherited AddPage;
  fCurrentPage := result;
  // (Re-)create or reinitialize the recording canvas for this page
  if fVclCanvas = nil then
    fVclCanvas := TPdfVclCanvas.Create(Self, fCanvas)
  else
    fVclCanvas.ResetState;
  // Switch the underlying PDF canvas to the new page
  // (TPdfDocument.AddPage already calls SetPage internally, so fCanvas
  // is pointing at the new page's content stream)
end;

procedure TPdfDocumentVcl.BeginStructContent(ARole: TPdfStructRole;
  const AAltText: RawUtf8);
begin
  Canvas.BeginStructContent(ARole, AAltText);
end;

procedure TPdfDocumentVcl.BeginStructGroup(ARole: TPdfStructRole);
begin
  Canvas.BeginStructGroup(ARole);
end;

procedure TPdfDocumentVcl.ContinueStructContent;
begin
  Canvas.ContinueStructContent;
end;

procedure TPdfDocumentVcl.SuspendStructContent;
begin
  Canvas.SuspendStructContent;
end;

procedure TPdfDocumentVcl.EndStructContent;
begin
  Canvas.EndStructContent;
end;

function TPdfDocumentVcl.LastStructContent: integer;
begin
  result := Canvas.LastStructContent;
end;

procedure TPdfDocumentVcl.ResumeStructContent(AStructIndex: integer;
  AOpenRegion: boolean);
begin
  Canvas.ResumeStructContent(AStructIndex, AOpenRegion);
end;

procedure TPdfDocumentVcl.SetFillAlpha(Value: single);
begin
  Canvas.SetFillAlpha(Value);
end;

procedure TPdfDocumentVcl.SetStrokeAlpha(Value: single);
begin
  Canvas.SetStrokeAlpha(Value);
end;

end.
