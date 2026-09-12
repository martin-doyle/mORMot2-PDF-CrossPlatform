/// Cross-platform report engine — TGDIPages (FPC/Lazarus)
// - on Delphi+Windows the original GDI/EMF implementation remains active
// - on FPC/Lazarus (all platforms) this unit provides a command-list-based
//   replacement rendered via LCL TCanvas, TPrinter and TPdfDocumentVcl
unit mormot.ui.report;

{$IFDEF FPC}
  {$mode delphi}
  {$H+}
{$ENDIF}

interface

{$IFDEF FPC}

// *** FPC/Lazarus: Cross-Platform implementation (all platforms) ***

uses
  Classes, SysUtils, Types, Math,
  Graphics, Controls, Forms, ExtCtrls, StdCtrls, ComCtrls, Dialogs,
  LCLType, LCLIntf,
  Printers,
  LazFileUtils,  // OpenDocument (cross-platform: xdg-open / open / ShellExecute)
  Contnrs, fgl,  // TObjectList + TFPGMap for generics
  mormot.core.base,
  mormot.core.unicode,
  mormot.pdf.types,     // PDF_FONT_STD_* + TPdfStructRole (Tagged PDF)
  mormot.ui.pdfcanvas;  // cross-platform PDF engine (uses FreeType2 on POSIX)
              // Re-exports TPdfALevel and PDF/A level constants from mormot.ui.pdf

{ =========================================================================
  Phase 1 – Types and structure
  ========================================================================= }

const
  /// minimum gray border around preview page (in pixels)
  GRAY_MARGIN = 10;
  /// token replaced by the page number inside header/footer texts
  PAGENUMBER = '<<pagenumber>>';

  { §5.4 Font-Fallback: platform-appropriate font names for TrueType embedding
    For standard PDF Type1 fonts (no embedding): use PDF_FONT_STD_SANS/SERIF/MONO
    from mormot.pdf.types.pas when StandardFontsReplace := true }

  /// default sans-serif font: Arial on Windows, Liberation Sans on Unix/macOS
  REPORT_FONT_SANS  = {$IFDEF MSWINDOWS}'Calibri'{$ELSE}{$IFDEF DARWIN}'Trebuchet MS'{$ELSE}'Liberation Sans'{$ENDIF}{$ENDIF};
  /// default serif font: Times New Roman on Windows, Times on macOS, Liberation Serif on Linux
  REPORT_FONT_SERIF = {$IFDEF MSWINDOWS}'Cambria'{$ELSE}{$IFDEF DARWIN}'Georgia'{$ELSE}'Liberation Serif'{$ENDIF}{$ENDIF};
  /// default monospace font: Courier New on Windows, Courier on macOS, Liberation Mono on Linux
  REPORT_FONT_MONO  = {$IFDEF MSWINDOWS}'Consolas'{$ELSE}{$IFDEF DARWIN}'Andale Mono'{$ELSE}'Liberation Mono'{$ENDIF}{$ENDIF};

/// Helper function for font selection based on embedding mode
// - When Embedded=true: returns platform-specific TTF fonts (REPORT_FONT_*)
// - When Embedded=false: returns PDF standard Type1 fonts (Helvetica/Times/Courier)
procedure GetReportFonts(Embedded: boolean;
  out SansFont, SerifFont, MonoFont: string);

type
  /// Re-export TPrinterOrientation from LCL Printers unit for TGDIPages.Orientation property
  // - Allows other units to use this type without directly importing Printers
  TPrinterOrientation = Printers.TPrinterOrientation;

const
  /// Re-export printer orientation constants
  poPortrait = Printers.poPortrait;
  poLandscape = Printers.poLandscape;

type
  /// column alignment for table cells
  TTableColumnAlign = (tcaLeft, tcaCenter, tcaRight);

  /// atomic drawing commands stored per page (all lengths in 1/100 mm)
  TDrawCmdKind = (
    dckDrawText,      // text at (X,Y) — Align 0=left, 1=right, 2=center
    dckDrawLine,      // line from (X,Y) to (X2,Y2); LineWidth in screen pixels
    dckDrawRect,      // empty rectangle outline
    dckFillRect,      // filled rectangle (no border)
    dckDrawBitmap,    // stretch-draw bitmap (BitmapIndex into TGDIPages.fBitmaps)
    dckClip,          // push clip rect (X,Y,X2,Y2)
    dckRestoreClip,   // pop clip rect
    dckBeginTable,    // mark beginning of table (used for layout)
    dckTableRow,      // table row with cells (Text holds cell data, Color = header flag)
    dckEndTable,      // mark end of table
    dckHeading,       // heading (Level 1..6, Title in Text)
    dckBeginTR,       // begin table row (Color<>0 = header row) — for Tagged PDF structure
    dckEndTR          // end table row — for Tagged PDF structure
  );

  /// one drawing command (all coordinates in 1/100 mm unless noted)
  TDrawCommand = record
    Kind:        TDrawCmdKind;
    X, Y,
    X2, Y2:      Integer;    // position / extent in 1/100 mm
    FontName:    string;
    FontSize:    Integer;
    FontStyle:   TFontStyles;
    Color:       TColor;     // pen / text / fill color
    BkColor:     TColor;     // background color (reserved)
    Text:        string;
    TextWidthMM: Integer;    // pre-measured text width in 1/100 mm (for alignment)
    BitmapIndex: Integer;    // index into TGDIPages.fBitmaps (-1 = none)
    LineWidth:   Integer;    // pen width in screen pixels (1 = hairline)
    Align:       Integer;    // 0=left, 1=right, 2=center (dckDrawText)
    FormatName:  string;     // format registry key (H1, H2, P, Strong, Em, Code, etc. for dckDrawText/dckHeading)
    HeadingLevel: Integer;   // heading level 1..6 (for dckHeading)
    HeadingTitle: string;    // heading text (for dckHeading)
  end;

  /// ordered list of drawing commands for one page
  TDrawCommandList = array of TDrawCommand;

  /// data for one report page
  TPageData = record
    Commands:    TDrawCommandList;
    PageWidth:   Integer;  // printable width  in 1/100 mm
    PageHeight:  Integer;  // printable height in 1/100 mm
    MarginLeft:  Integer;  // margins active when this page was created (1/100 mm)
    MarginRight: Integer;
    MarginTop:   Integer;
    MarginBottom:Integer;
  end;

  /// available paper sizes
  TGdiPagePaperSize = (
    psA4,
    psA5,
    psA3,
    psLetter,
    psLegal);

  /// font + color state for SaveLayout / RestoreLayout
  TSavedState = record
    FontName:  string;
    FontSize:  Integer;
    FontStyle: TFontStyles;
    TextColor: TColor;
  end;

  /// text format definition (like CSS styles)
  // - used for H1..H6 headings, P paragraphs, Strong/Em emphasis, etc.
  // - user can define custom formats via DefineFormat() and override defaults
  TReportFormat = record
    FontName:    string;        // font name (e.g. 'Arial', 'Times New Roman')
    FontSize:    Integer;       // font size in points (10, 12, 16, 24, etc.)
    FontStyle:   TFontStyles;   // styling (bold, italic, underline, strikethrough)
    Color:       TColor;        // text color (RGB)
    SpaceAfter:  Integer;       // space after text in 1/100 mm (for headings, paragraphs)
    SpaceBefore: Integer;       // space before text in 1/100 mm
  end;

  /// table layout definition (columns, fonts, colors)
  // - used to define table structure before rendering rows
  // - BeginTable(const Layout: TTableLayout) begins table rendering
  TTableLayout = record
    ColumnWidths: array of Integer;           // column widths in 1/100 mm
    ColumnAligns: array of TTableColumnAlign; // alignment per column
    HeaderFontName: string;                   // font name for header row
    HeaderFontSize: Integer;                  // font size for header row (points)
    HeaderFontStyle: TFontStyles;             // font style for header row
    HeaderBkColor: TColor;                    // background color for header row
    BodyFontName: string;                     // font name for data rows
    BodyFontSize: Integer;                    // font size for data rows (points)
    BodyFontStyle: TFontStyles;               // font style for data rows
    BodyBkColor: TColor;                      // background color for data rows
    AlternateRowColor: TColor;                // alternating row color (0 = off, else applies to odd rows)
  end;

  /// heading information tracked for PDF outline generation
  THeadingInfo = record
    Level:    Integer;  // heading level 1..6
    Title:    string;   // heading text
    PageNum:  Integer;  // 1-based page number
    Y:        Integer;  // Y position in 1/100 mm
  end;

  { TGDIPages }

  /// cross-platform report engine
  // - records drawing operations as TDrawCommand lists (one list per page)
  // - renders on any TCanvas via RenderPageToCanvas
  // - public surface is API-compatible with the Delphi TGdiPages for the
  //   methods listed in MIGRATION_PLAN.md §8 (Beibehaltung der öffentl. API)
  TGDIPages = class(TScrollBox)
  private
    { --- page storage --- }
    fPages:        array of TPageData;
    fBitmaps:      TObjectList;          // owns TBitmap objects
    fPageCount:    Integer;
    fCurrCmds:     ^TDrawCommandList;    // points to current page's command list

    { --- current layout state --- }
    fFontName:     string;
    fFontSize:     Integer;
    fFontStyle:    TFontStyles;
    fTextColor:    TColor;

    { --- page geometry (1/100 mm) --- }
    fPaperSize:    TGdiPagePaperSize;
    fOrientation:  TPrinterOrientation;
    fMarginLeft:   Integer;
    fMarginRight:  Integer;
    fMarginTop:    Integer;
    fMarginBottom: Integer;
    fPageWidth:    Integer;   // paper - margins (computed by UpdatePageDimensions)
    fPageHeight:   Integer;

    { --- cursor position --- }
    fCurrentY:     Integer;   // vertical position within printable area (1/100 mm)
    fCurrentX:     Integer;   // horizontal position within printable area (1/100 mm)

    { --- metadata --- }
    fTitle:        string;
    fAuthor:       string;
    fSubject:      string;

    { --- Phase 3: Header and Footer --- }
    fHeaderText:   string;
    fFooterText:   string;

    { --- Phase 4: Table state --- }
    fTableStartY:      Integer;       // Y position where table started
    fTableColWidths:   array of Integer;   // column widths in 1/100 mm
    fTableColAligns:   array of TTableColumnAlign;  // column alignments
    fTableInProgress:  boolean;       // true if inside BeginTable..EndTable
    fTableRowStartY:   Integer;       // Y position of current row start
    fTableLayout:      TTableLayout;  // current table layout (column widths, fonts, colors)
    fTableRowIndex:    Integer;       // current row number (0-based, for alternating colors)
    fTableSavedHeaders: TStringDynArray; // headers saved for continuation-page repetition

    { --- Phase 2: 1×1 bitmap for LCL text measurement --- }
    fMeasureBitmap: TBitmap;

    { --- saved state stack --- }
    fSavedStates:  array of TSavedState;
    fSavedCount:   Integer;

    { --- Phase 5: Format registry (Markdown-style) --- }
    fFormatRegistry: TFPGMap<string, TReportFormat>;  // H1..H6, Strong, Em, Code, etc.
    fHeadings:       array of THeadingInfo;  // stores heading metadata for PDF outlines
    fHeadingCount:   Integer;  // count of headings in fHeadings array
    fCurrentHeadingLevel: Integer;  // tracks current heading level for auto-spacing in EndHeading
    fInParagraph:    Integer;  // depth counter for nested paragraph begin/end

    { --- Phase 6: PDF export options --- }
    fUseOutlines:          boolean;
    fExportPdfLevel:       TPdfALevel;
    fExportPdfEmbeddedTTF: boolean;
    fExportPdfStandardFonts: boolean;
    fExportPdfAuthor:      string;
    fExportPdfSubject:     string;
    fExportPdfFileFormat:  TPdfFileFormat;
    fExportPdfTagged:      boolean;
    fExportPdfLanguage:    RawUtf8;
    fActivePdfDoc:         TPdfDocumentVcl;  // non-nil during tagged PDF export only

    { --- Preview Form temporary state (for ShowPreviewForm callbacks) --- }
    fPreviewCurrPage:      Integer;
    fPreviewTotalPages:    Integer;
    fPreviewLblPage:       TLabel;
    fPreviewEdtZoom:       TEdit;        // editable zoom percentage input
    fPreviewPaintBox:      TPaintBox;
    fPreviewScrollBox:     TScrollBox;   // scrollable container for zoomed page
    fPreviewW:             Integer;      // base preview width @ 96 DPI (unzoomed)
    fPreviewH:             Integer;      // base preview height @ 96 DPI (unzoomed)
    fPreviewZoom:          Double;       // zoom factor (1.0 = 100%)
    fPreviewForm:          TForm;        // reference to modal form for resize events

    { === CACHING: Zentrale Berechnung (einmal, viel verwendet) === }
    { --- Seiten-Geometrie Cache (berechnet in NewPage) --- }
    fPrintableWidth: Integer;       { fPageWidth (ohne Margins) in 1/100mm }
    fPrintableHeight: Integer;      { fPageHeight (ohne Margins) in 1/100mm }
    fWrappingWidthPx: Integer;      { Printable width in pixels @ 96 DPI }

    { --- Font-Metriken Cache (berechnet in SetFont) --- }
    fCachedFontName: string;        { Tracked font name for cache validation }
    fCachedFontSize: Integer;       { Tracked font size for cache validation }
    fCachedFontStyle: TFontStyles;  { Tracked font style for cache validation }
    fCachedLineHeightPx: Integer;   { Zeilenhöhe in Pixeln @ 96 DPI }
    fCachedLineHeightMM: Integer;   { Zeilenhöhe in 1/100mm }
    fLineHeightFactor:   single;    { multiplier applied to raw TextHeight — default 1.1 }

    { --- Rendering Cache (berechnet in RenderPageToCanvas) --- }
    fRenderScaleX: Double;          { Scaling factor für Pixel-Konvertierung }
    fRenderScaleY: Double;          { Scaling factor für Pixel-Konvertierung }
    fRenderOffsetX: Integer;        { Pixel offset for left margin }
    fRenderOffsetY: Integer;        { Pixel offset for top margin }

    { --- internal --- }
    procedure AddCommand(const Cmd: TDrawCommand);
    procedure UpdatePageDimensions;
    procedure PreviewUpdateLabel;
    procedure PreviewDoPaint(Sender: TObject);
    procedure PreviewDoPrev(Sender: TObject);
    procedure PreviewDoNext(Sender: TObject);
    procedure PreviewApplyZoom;
    procedure PreviewDoZoomIn(Sender: TObject);
    procedure PreviewDoZoomOut(Sender: TObject);
    procedure PreviewDoFitPage(Sender: TObject);
    procedure PreviewDoFitWidth(Sender: TObject);
    procedure PreviewDoFormResize(Sender: TObject);
    procedure PreviewDoKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PreviewDoMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure PreviewDoZoomEdit(Sender: TObject);
    function  GetPageCount: Integer;
    function  GetCurrentPageIndex: Integer;
    function  GetPage(Index: Integer): TPageData;
    procedure SetupMeasureFont;
    function  MeasureTextWidthPx(const S: string): Integer;
    function  LineHeightPx: Integer;
    function  LineHeightMM: Integer;
    function  MeasureTextWidthMM(const S: string): Integer;
    function  GetMeasureDPI: Integer;
    procedure RecordWrappedText(X: Integer; var Y: Integer;
                                const S: string; MaxWidthMM: Integer);
    procedure EmitTextCmd(X, Y: Integer; const S: string; Align: Integer);
    procedure InitializeFormatRegistry;
    procedure AddHeadingsToOutline(PDF: TPdfDocumentVcl);
    function  NormalizeX(X: Integer): Integer;
    function  NormalizeY(Y: Integer): Integer;
    { Zentrale Skalierungsfunktionen - IMMER nutzen für Koordinaten-Umwandlung }
    function  ScaleX(V: Integer): Integer;  // Convert 1/100mm to render pixels
    function  ScaleY(V: Integer): Integer;  // Convert 1/100mm to render pixels
    procedure SetFontStyleProperty(Style: TFontStyles);
    procedure SetLineHeightFactor(Value: single);
    procedure SetMarginLeft(Value: Integer);
    procedure SetMarginRight(Value: Integer);
    procedure SetMarginTop(Value: Integer);
    procedure SetMarginBottom(Value: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;

    { --- page management (Phase 3) --- }
    procedure NewPage;
    procedure EndDoc;

    { --- layout (Phase 1/2) --- }
    procedure SaveLayout;
    procedure RestoreLayout;
    procedure SetFont(const Name: string; Size: Integer);
    /// font styling (bold, italic, underline, strikethrough)
    property  FontStyle: TFontStyles read fFontStyle write SetFontStyleProperty;
    /// text color (RGB) for TextOut and other text operations
    property  TextColor: TColor      read fTextColor  write fTextColor;
    /// line height multiplier applied to the raw font TextHeight — default 1.1
    // - increase to e.g. 1.5 for more leading; decrease towards 1.0 for tighter spacing
    // - changing this property invalidates the cached line height immediately
    property LineHeightFactor: single read fLineHeightFactor write SetLineHeightFactor;
    /// advance Y cursor by offset in 1/100 mm units
    procedure MoveToNextLine(Offset: Integer);
    /// add vertical spacing in millimeters
    procedure AddVerticalSpace(mm: Integer);
    /// force a page break and reset Y cursor to top
    procedure ForceNewPage;

    { --- page settings (set before first NewPage) --- }
    /// paper size (A4, A5, A3, Letter, Legal) - default psA4
    property PaperSize:    TGdiPagePaperSize   read fPaperSize    write fPaperSize;
    /// page orientation (poPortrait or poLandscape) - default poPortrait
    property Orientation:  TPrinterOrientation read fOrientation  write fOrientation;
    /// left margin in 1/100 mm units - default 2000 (20mm) — updates page dimensions
    property MarginLeft:   Integer             read fMarginLeft   write SetMarginLeft;
    /// right margin in 1/100 mm units - default 2000 (20mm) — updates page dimensions
    property MarginRight:  Integer             read fMarginRight  write SetMarginRight;
    /// top margin in 1/100 mm units - default 2000 (20mm) — updates page dimensions
    property MarginTop:    Integer             read fMarginTop    write SetMarginTop;
    /// bottom margin in 1/100 mm units - default 2000 (20mm) — updates page dimensions
    property MarginBottom: Integer             read fMarginBottom write SetMarginBottom;

    { --- header/footer (Phase 3) --- }
    /// set page header text with placeholders: {#} = page number (1-based), {total} = total pages
    procedure SetHeader(const AText: string);
    /// set page footer text with placeholders: {#} = page number (1-based), {total} = total pages
    procedure SetFooter(const AText: string);

    { --- Phase 5: Format registry (Markdown-style) --- }
    /// define or override a named text format (H1, H2, P, Strong, Em, Code, etc.)
    // - used to customize the appearance of headings and text elements
    // - predefined formats: H1, H2, H3, H4, H5, H6 (headings with auto PDF bookmarks)
    //   and: P (paragraph), Strong (bold), Em (italic), Code (monospace), Link (blue underlined)
    //   and: Quote (italic gray), LI (list items), Caption (small italic)
    //   and: TableHeader, TableCell, TableCellAlt (table cells)
    // - formats should be defined before NewPage() to take effect
    // - example: DefineFormat('H1', TReportFormat(FontName: 'Arial', FontSize: 28, ...))
    procedure DefineFormat(const AName: string; const AFormat: TReportFormat);

    /// get defined format by name (returns safe default if not found)
    // - returns a TReportFormat record with font properties and spacing
    // - if format name not found, returns default: 11pt Arial, regular style, black color
    function GetFormat(const AName: string): TReportFormat;

    /// draw heading with automatic PDF bookmark and auto-spacing
    // - ALevel: heading level 1..6 (H1 is top-level, H6 is smallest)
    // - ATitle: heading text (displayed in report + PDF outline/bookmarks)
    // - automatically sets PDF bookmark at current Y position
    // - automatically uses format 'H{Level}' from registry (H1, H2, ..., H6)
    // - auto-advances CurrentY based on heading format spacing
    // - raises exception if ALevel not in 1..6 or ATitle is empty
    procedure DrawHeading(ALevel: Integer; const ATitle: string);

    { --- Phase 5: Inline text formatting (Markdown-style) --- }
    /// draw text in bold (Strong format)
    procedure DrawStrong(X, Y: Integer; const AText: string);
    /// inline bold: uses CurrentX/CurrentY, advances CurrentX
    procedure DrawStrong(const AText: string); overload;
    /// draw text in italic (Em format)
    procedure DrawEm(X, Y: Integer; const AText: string);
    /// inline italic: uses CurrentX/CurrentY, advances CurrentX
    procedure DrawEm(const AText: string); overload;
    /// draw text in monospace (Code format)
    procedure DrawCode(X, Y: Integer; const AText: string);
    /// inline code: uses CurrentX/CurrentY, advances CurrentX
    procedure DrawCode(const AText: string); overload;
    /// draw text as hyperlink (blue underlined)
    // - ATarget: optional target URL (for future use)
    procedure DrawLink(X, Y: Integer; const AText: string; const ATarget: string = '');
    /// inline link: uses CurrentX/CurrentY, advances CurrentX
    procedure DrawLink(const AText: string; const ATarget: string = ''); overload;
    /// draw block quote (italic gray with left margin)
    // - overloaded: auto uses page margins
    procedure DrawQuote(const AText: string); overload;
    /// draw block quote (italic gray with left margin) — legacy version with explicit positioning
    // - MaxWidth: maximum line width in 1/100 mm
    procedure DrawQuote(X, MaxWidth, Y: Integer; const AText: string); overload;

    /// draw paragraph with word wrapping — auto uses page margins
    // - auto-advances CurrentY
    procedure DrawParagraph(const AText: string); overload;
    /// draw paragraph with word wrapping — legacy version with explicit positioning
    // - MaxWidth: maximum line width in 1/100 mm
    // - auto-advances CurrentY
    procedure DrawParagraph(X, MaxWidth, Y: Integer; const AText: string); overload;

    /// draw list item with bullet prefix
    // - APrefix: bullet character (default '• ')
    procedure DrawListItem(X, Y: Integer; const AText: string; const APrefix: string = '• ');

    /// draw figure/table caption (small italic gray) — auto uses page margins
    procedure DrawCaption(const ACaption: string); overload;
    /// draw figure/table caption (small italic gray) — legacy version with explicit positioning
    // - MaxWidth: maximum line width in 1/100 mm
    procedure DrawCaption(X, MaxWidth, Y: Integer; const ACaption: string); overload;

    { --- metadata --- }
    property Title:   string read fTitle   write fTitle;
    property Author:  string read fAuthor  write fAuthor;
    property Subject: string read fSubject write fSubject;

    { --- page geometry (read-only) --- }
    /// printable page width in 1/100 mm
    property PageWidth:        Integer read fPageWidth;
    /// printable page height in 1/100 mm
    property PageHeight:       Integer read fPageHeight;
    /// current Y cursor within the printable area (1/100 mm)
    property CurrentY:         Integer read fCurrentY;
    property CurrentX:         Integer read fCurrentX write fCurrentX;
    /// 1-based index of the last page (0 = no pages yet)
    property CurrentPageIndex: Integer read GetCurrentPageIndex;
    /// number of completed pages
    property PageCount:        Integer  read GetPageCount;
    /// direct access to page data by index — mainly for unit tests
    property Pages[Index: Integer]: TPageData read GetPage;

    { --- drawing (Phase 3) --- }
    procedure DrawText(X, Y: Integer; const S: string);
    /// Draw text without coordinates: uses CurrentX/CurrentY, advances CurrentX by text width
    procedure DrawText(const S: string); overload;
    procedure DrawTextRight(X, Y: Integer; const S: string);
    procedure DrawTextAt(X, Y: Integer; const S: string);
    procedure DrawTextCenter(X, Y: Integer; const S: string);
    /// draw text with automatic word wrapping at MaxWidth (in 1/100 mm); updates CurrentY
    procedure DrawTextWrapped(X, MaxWidth, Y: Integer; const AText: string);
    procedure DrawLine(X1, Y1, X2, Y2, Width: Integer; Color: TColor);
    procedure DrawFilledRect(X1, Y1, X2, Y2: Integer; Color: TColor);
    procedure Columns2(Gap: Integer; const Text1, Text2: string);

    { --- tables (Phase 4) --- }
    /// begin table with TTableLayout definition (column widths, fonts, colors, alignment)
    // - TTableLayout defines all formatting; type-safe and explicit
    // - recommended primary API for new code
    procedure BeginTable(const Layout: TTableLayout); overload;
    /// draw table header row with TTableLayout formatting
    procedure DrawTableHeader(const Headers: array of string);
    /// draw table data row with alternating colors and automatic page breaks
    procedure DrawTableRow(const Values: array of string);
    /// begin table with specified column widths (1/100 mm) and optional alignments
    // - legacy API; prefer BeginTable(const Layout: TTableLayout)
    procedure BeginTable(const ColWidths: array of Integer;
                        const ColAligns: array of TTableColumnAlign); overload;
    /// add table row with cells; IsHeader=true renders with gray background
    // - legacy API; prefer DrawTableHeader / DrawTableRow
    procedure AddTableRow(const Cells: array of string; IsHeader: boolean = false);
    /// end table block and finalize layout
    procedure EndTable;

    { --- rendering (Phase 3) --- }
    /// render a page to a target canvas with optional DPI (for PDF export consistency)
    // - ACanvas: target canvas to render to (must be valid before call)
    // - PageIndex: 0-based page number to render (must be < PageCount)
    // - DestWidth, DestHeight: rendering area size in pixels (including margins)
    // - SourceDPI: optional DPI for coordinate conversion (0 = use Screen.PixelsPerInch)
    //   set to PDF.ScreenLogPixels (96) for PDF export to ensure consistency
    // - renders header/footer with {#} and {total} placeholder substitution
    procedure RenderPageToCanvas(ACanvas: TCanvas;
                                 PageIndex, DestWidth, DestHeight: Integer;
                                 SourceDPI: Integer = 0);

    { --- preview (Phase 4) --- }
    procedure ShowPreviewForm;

    { --- §5.2 print dialog --- }
    /// show the OS printer dialog and print if the user confirms
    procedure ShowPrintDialog;

    { --- §5.3 open exported PDF --- }
    /// open FileName with the default PDF viewer (xdg-open / open / ShellExecute)
    procedure OpenPdfFile(const FileName: string);

    { --- output (Phase 5/6) --- }
    /// print pages [From..To_] on the default printer
    procedure PrintPages(From, To_: Integer);
    /// export all pages as PDF to an existing stream; returns false on error
    // - uses ExportPdfLevel, ExportPdfEmbeddedTTF, ExportPdfAuthor/Subject
    // - IMPORTANT: uses PDF.ScreenLogPixels for MMToPixels (not Screen.PixelsPerInch)
    //   so TPdfVclCanvas coordinates match the PDF coordinate system exactly
    function  ExportPdfStream(aDest: TStream): boolean;
    /// export all pages as PDF to a file; calls ExportPdfStream internally
    procedure ExportPDF(const FileName: string;
                        Protect, Encrypt: Boolean;
                        const ATitle, ACompany: string);

    { --- Phase 6: PDF export options --- }
    /// include PDF outlines/bookmarks (default: false)
    property UseOutlines:          boolean    read fUseOutlines          write fUseOutlines;
    /// PDF/A compliance level; pdfaNone = standard PDF 1.x (default)
    property ExportPdfLevel:       TPdfALevel read fExportPdfLevel       write fExportPdfLevel;
    /// embed TrueType fonts in the PDF (default: true)
    property ExportPdfEmbeddedTTF: boolean    read fExportPdfEmbeddedTTF write fExportPdfEmbeddedTTF;
    /// use PDF Type1 standard fonts (Helvetica/Times/Courier) instead of TTF (default: true)
    property ExportPdfStandardFonts: boolean  read fExportPdfStandardFonts write fExportPdfStandardFonts;
    /// PDF author field (defaults to Author property when empty)
    property ExportPdfAuthor:      string     read fExportPdfAuthor      write fExportPdfAuthor;
    /// PDF subject field (defaults to Subject property when empty)
    property ExportPdfSubject:     string     read fExportPdfSubject     write fExportPdfSubject;
    /// PDF version written to the file header; default is pdf13 (backward-compatible)
    property ExportPdfFileFormat:  TPdfFileFormat read fExportPdfFileFormat write fExportPdfFileFormat;
    /// enable Tagged PDF (ISO 32000-1 §14) on export; adds structure tags H1-H6 and P
    property ExportPdfTagged: boolean read fExportPdfTagged write fExportPdfTagged;
    /// BCP-47 language tag for the Tagged PDF /Lang entry (default 'en')
    property ExportPdfLanguage: RawUtf8 read fExportPdfLanguage write fExportPdfLanguage;

    /// Get font names based on current embedding mode
    // - When ExportPdfEmbeddedTTF=true: returns platform-specific TTF fonts
    // - When ExportPdfEmbeddedTTF=false: returns PDF standard Type1 fonts
    procedure GetExportFonts(out SansFont, SerifFont, MonoFont: string);
  end;

/// convert 1/100-mm value to pixels at the given DPI
function MMToPixels(Value100: Integer; DPI: Integer): Integer;
/// convert pixels to 1/100-mm at the given DPI
function PixelsToMM(Pixels: Integer; DPI: Integer): Integer;

{$ELSE}

// *** Delphi + Windows: no-op placeholder ***
// The original mormot.ui.report (from the mORMot2 source tree) is used on
// Delphi builds — this stub keeps the unit parseable on those compilers.
procedure Register;

implementation

procedure Register;
begin
end;

{$ENDIF FPC}

implementation

{$IFDEF FPC}

{ =========================================================================
  Constants
  ========================================================================= }

const
  /// paper widths (portrait) in 1/100 mm
  PAPER_WIDTH: array[TGdiPagePaperSize] of Integer = (
    21000, 14800, 29700, 21590, 21590);
  /// paper heights (portrait) in 1/100 mm
  PAPER_HEIGHT: array[TGdiPagePaperSize] of Integer = (
    29700, 21000, 42000, 27940, 35560);
  // internal alias — matches the public REPORT_FONT_SANS constant
  FONT_SANS  = REPORT_FONT_SANS;
  /// cell padding for table cells in 1/100 mm (2mm)
  CELL_PADDING = 200;
  /// conversion factor: 1 point = 3.528 × 1/100mm
  PT_TO_100MM = 3528;

{ =========================================================================
  Helper functions
  ========================================================================= }

function MMToPixels(Value100: Integer; DPI: Integer): Integer;
begin
  Result := MulDiv(Value100, DPI, 2540);
end;

function PixelsToMM(Pixels: Integer; DPI: Integer): Integer;
begin
  if DPI <= 0 then DPI := 96;
  Result := MulDiv(Pixels, 2540, DPI);
end;

procedure GetReportFonts(Embedded: boolean;
  out SansFont, SerifFont, MonoFont: string);
begin
  if Embedded then
  begin
    SansFont  := REPORT_FONT_SANS;
    SerifFont := REPORT_FONT_SERIF;
    MonoFont  := REPORT_FONT_MONO;
  end
  else
  begin
    SansFont  := PDF_FONT_STD_SANS;
    SerifFont := PDF_FONT_STD_SERIF;
    MonoFont  := PDF_FONT_STD_MONO;
  end;
end;

{ =========================================================================
  TGDIPages – construction
  ========================================================================= }

constructor TGDIPages.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fBitmaps           := TObjectList.Create(True);
  fFontName          := FONT_SANS;
  fFontSize          := 10;
  fFontStyle         := [];
  fTextColor         := clBlack;
  fPaperSize         := psA4;
  fOrientation       := poPortrait;
  fMarginLeft        := 2000;
  fMarginRight       := 2000;
  fMarginTop         := 2000;
  fMarginBottom      := 2000;
  fMeasureBitmap        := TBitmap.Create;
  fMeasureBitmap.Width  := 1;
  fMeasureBitmap.Height := 1;
  // Phase 6 defaults
  fUseOutlines          := False;
  fExportPdfLevel       := pdfaNone;
  fExportPdfEmbeddedTTF := True;
  fExportPdfStandardFonts := True;
  fExportPdfFileFormat    := pdf13;
  fExportPdfTagged        := False;
  fExportPdfLanguage      := 'en';

  // Phase 5: Initialize format registry with default Markdown-style formats
  fFormatRegistry := TFPGMap<string, TReportFormat>.Create;
  fHeadingCount := 0;
  SetLength(fHeadings, 0);
  fCurrentHeadingLevel := 0;
  fInParagraph := 0;
  InitializeFormatRegistry;

  UpdatePageDimensions;

  { === Initialize Cache Variables === }
  fPrintableWidth := fPageWidth;
  fPrintableHeight := fPageHeight;
  fWrappingWidthPx := MMToPixels(fPrintableWidth, 96);
  fLineHeightFactor   := 1.1;
  fCachedLineHeightPx := 0;
  fCachedLineHeightMM := 0;
  fRenderScaleX := 1.0;
  fRenderScaleY := 1.0;
  fRenderOffsetX := 0;
  fRenderOffsetY := 0;
end;

destructor TGDIPages.Destroy;
begin
  fBitmaps.Free;
  fMeasureBitmap.Free;
  fFormatRegistry.Free;
  SetLength(fHeadings, 0);  // clear dynamic array
  inherited;
end;

{ =========================================================================
  Internal helpers — format registry initialization
  ========================================================================= }

procedure TGDIPages.InitializeFormatRegistry;
var
  Fmt: TReportFormat;
begin
  { H1: Top-level heading, 28pt bold }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 28;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 800;
  Fmt.SpaceBefore := 600;
  DefineFormat('H1', Fmt);

  { H2: Section heading, 21pt bold }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 21;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 600;
  Fmt.SpaceBefore := 400;
  DefineFormat('H2', Fmt);

  { H3: Subsection heading, 16pt bold }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 16;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 400;
  Fmt.SpaceBefore := 300;
  DefineFormat('H3', Fmt);

  { H4: Small heading, 13pt bold }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 13;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 200;
  Fmt.SpaceBefore := 200;
  DefineFormat('H4', Fmt);

  { H5: Minor heading, 11pt bold }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 200;
  Fmt.SpaceBefore := 100;
  DefineFormat('H5', Fmt);

  { H6: Smallest heading, 10pt bold }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 10;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 100;
  Fmt.SpaceBefore := 100;
  DefineFormat('H6', Fmt);

  { P: Normal paragraph, 11pt regular }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 300;
  Fmt.SpaceBefore := 0;
  DefineFormat('P', Fmt);

  { Strong: Bold inline text }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  DefineFormat('Strong', Fmt);

  { Em: Italic inline text }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [fsItalic];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  DefineFormat('Em', Fmt);

  { Code: Monospace code text, maroon color }
  { FontSize := 0 means "use 90% of current font size" (proportional scaling) }
  Fmt.FontName := REPORT_FONT_MONO;
  Fmt.FontSize := 0;
  Fmt.FontStyle := [];
  Fmt.Color := clMaroon;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  DefineFormat('Code', Fmt);

  { Link: Blue underlined hyperlink text }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [fsUnderline];
  Fmt.Color := clBlue;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  DefineFormat('Link', Fmt);

  { Quote: Block quote, italic gray }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [fsItalic];
  Fmt.Color := $666666;
  Fmt.SpaceAfter := 300;
  Fmt.SpaceBefore := 200;
  DefineFormat('Quote', Fmt);

  { LI: List item text }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 100;
  Fmt.SpaceBefore := 0;
  DefineFormat('LI', Fmt);

  { TableHeader: Table header cell, bold white text }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 11;
  Fmt.FontStyle := [fsBold];
  Fmt.Color := clWhite;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  DefineFormat('TableHeader', Fmt);

  { TableCell: Normal table cell text }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 10;
  Fmt.FontStyle := [];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  DefineFormat('TableCell', Fmt);

  { TableCellAlt: Alternate row text }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 10;
  Fmt.FontStyle := [];
  Fmt.Color := clBlack;
  Fmt.SpaceAfter := 0;
  Fmt.SpaceBefore := 0;
  DefineFormat('TableCellAlt', Fmt);

  { Caption: Figure/table caption, small italic gray }
  Fmt.FontName := REPORT_FONT_SANS;
  Fmt.FontSize := 9;
  Fmt.FontStyle := [fsItalic];
  Fmt.Color := $666666;
  Fmt.SpaceAfter := 200;
  Fmt.SpaceBefore := 100;
  DefineFormat('Caption', Fmt);
end;

{ =========================================================================
  Internal helpers — page geometry
  ========================================================================= }

procedure TGDIPages.UpdatePageDimensions;
var
  PW, PH: Integer;
begin
  if fOrientation = poPortrait then
  begin
    PW := PAPER_WIDTH[fPaperSize];
    PH := PAPER_HEIGHT[fPaperSize];
  end
  else
  begin
    PW := PAPER_HEIGHT[fPaperSize]; // landscape: swap
    PH := PAPER_WIDTH[fPaperSize];
  end;
  fPageWidth  := PW - fMarginLeft - fMarginRight;
  fPageHeight := PH - fMarginTop  - fMarginBottom;
end;

procedure TGDIPages.AddCommand(const Cmd: TDrawCommand);
var
  n: Integer;
begin
  if fCurrCmds = nil then
    raise Exception.Create('TGDIPages: call NewPage before drawing');
  n := Length(fCurrCmds^);
  SetLength(fCurrCmds^, n + 1);
  fCurrCmds^[n] := Cmd;
end;

function TGDIPages.GetPageCount: Integer;
begin
  Result := fPageCount;
end;

function TGDIPages.GetCurrentPageIndex: Integer;
begin
  Result := fPageCount; // 1-based; 0 = no pages
end;

function TGDIPages.GetPage(Index: Integer): TPageData;
begin
  Result := fPages[Index];
end;

{ =========================================================================
  Phase 2 – Text measurement via LCL TCanvas.TextExtent
  ========================================================================= }

procedure TGDIPages.SetupMeasureFont;
begin
  fMeasureBitmap.Canvas.Font.Name  := fFontName;
  fMeasureBitmap.Canvas.Font.Size  := fFontSize;
  fMeasureBitmap.Canvas.Font.Style := fFontStyle;
end;

function TGDIPages.MeasureTextWidthPx(const S: string): Integer;
begin
  SetupMeasureFont;
  Result := fMeasureBitmap.Canvas.TextWidth(S);
end;

function TGDIPages.LineHeightPx: Integer;
begin
  SetupMeasureFont;
  Result := Round(fMeasureBitmap.Canvas.TextHeight('Hg') * fLineHeightFactor);
end;

procedure TGDIPages.SetLineHeightFactor(Value: single);
begin
  fLineHeightFactor   := Value;
  fCachedLineHeightPx := 0;
  fCachedLineHeightMM := 0;
end;

function TGDIPages.LineHeightMM: Integer;
begin
  Result := PixelsToMM(LineHeightPx, GetMeasureDPI);
end;

function TGDIPages.MeasureTextWidthMM(const S: string): Integer;
begin
  Result := PixelsToMM(MeasureTextWidthPx(S), GetMeasureDPI);
end;

function TGDIPages.GetMeasureDPI: Integer;
begin
  { Return the actual screen DPI that the bitmap canvas uses for font rendering.
    LCL bitmap canvas (all platforms) measures fonts using Screen.PixelsPerInch.
    On HiDPI systems (e.g., Retina display in Parallels on Apple Silicon) this
    value is > 96. Using the wrong DPI causes systematic errors in all text
    width measurements: text wraps too early, inline positions drift, and
    right-aligned text is shifted. }
  Result := Screen.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

{ =========================================================================
  Phase 3 – Page recording
  ========================================================================= }

procedure TGDIPages.NewPage;
begin
  UpdatePageDimensions;

  { === Cache zentrale Seitengeometrie ===}
  fPrintableWidth := fPageWidth;    { Bereits ohne Margins in UpdatePageDimensions }
  fPrintableHeight := fPageHeight;
  fWrappingWidthPx := MMToPixels(fPrintableWidth, 96);

  SetLength(fPages, fPageCount + 1);
  fPages[fPageCount].Commands    := nil;
  fPages[fPageCount].PageWidth   := fPageWidth;
  fPages[fPageCount].PageHeight  := fPageHeight;
  fPages[fPageCount].MarginLeft  := fMarginLeft;
  fPages[fPageCount].MarginRight := fMarginRight;
  fPages[fPageCount].MarginTop   := fMarginTop;
  fPages[fPageCount].MarginBottom:= fMarginBottom;
  Inc(fPageCount);
  fCurrCmds := @fPages[fPageCount - 1].Commands;
  fCurrentY := 0;
  fCurrentX := 0;  { reset horizontal position on new page }
end;

procedure TGDIPages.EndDoc;
begin
  fCurrCmds := nil; // seal: catch stray drawing calls early
end;

procedure TGDIPages.SaveLayout;
begin
  if fSavedCount >= Length(fSavedStates) then
    SetLength(fSavedStates, fSavedCount + 8);
  fSavedStates[fSavedCount].FontName  := fFontName;
  fSavedStates[fSavedCount].FontSize  := fFontSize;
  fSavedStates[fSavedCount].FontStyle := fFontStyle;
  fSavedStates[fSavedCount].TextColor := fTextColor;
  Inc(fSavedCount);
end;

procedure TGDIPages.RestoreLayout;
begin
  if fSavedCount <= 0 then Exit;
  Dec(fSavedCount);
  fFontName  := fSavedStates[fSavedCount].FontName;
  fFontSize  := fSavedStates[fSavedCount].FontSize;
  fFontStyle := fSavedStates[fSavedCount].FontStyle;
  fTextColor := fSavedStates[fSavedCount].TextColor;
end;

procedure TGDIPages.SetFont(const Name: string; Size: Integer);
begin
  fFontName := Name;
  fFontSize := Size;

  { === Cache Font-Metriken wenn sich Font ändert === }
  if (fCachedFontName <> Name) or (fCachedFontSize <> Size) or
     (fCachedFontStyle <> fFontStyle) then
  begin
    SetupMeasureFont;
    fCachedLineHeightPx := LineHeightPx;
    fCachedLineHeightMM := LineHeightMM;
    fCachedFontName := Name;
    fCachedFontSize := Size;
    fCachedFontStyle := fFontStyle;
  end;
end;

procedure TGDIPages.MoveToNextLine(Offset: Integer);
begin
  Inc(fCurrentY, Offset);
end;

procedure TGDIPages.SetHeader(const AText: string);
begin
  fHeaderText := AText;
end;

procedure TGDIPages.SetFooter(const AText: string);
begin
  fFooterText := AText;
end;

{ --- format registry methods --- }

procedure TGDIPages.DefineFormat(const AName: string; const AFormat: TReportFormat);
var
  Index: Integer;
begin
  Index := fFormatRegistry.IndexOf(AName);
  if Index >= 0 then
    fFormatRegistry.Data[Index] := AFormat
  else
    fFormatRegistry.Add(AName, AFormat);
end;

function TGDIPages.GetFormat(const AName: string): TReportFormat;
var
  Index: Integer;
begin
  Index := fFormatRegistry.IndexOf(AName);
  if Index >= 0 then
    Result := fFormatRegistry.Data[Index]
  else
  begin
    { Return safe default if format not found }
    Result.FontName := REPORT_FONT_SANS;
    Result.FontSize := 11;
    Result.FontStyle := [];
    Result.Color := clBlack;
    Result.SpaceAfter := 0;
    Result.SpaceBefore := 0;
  end;
end;

procedure TGDIPages.AddHeadingsToOutline(PDF: TPdfDocumentVcl);
var
  i: Integer;
  HeadingRec: THeadingInfo;
  YInPoints: Single;
begin
  if PDF = nil then Exit;
  if fHeadingCount = 0 then Exit;

  { Process each heading and add to PDF outline }
  for i := 0 to fHeadingCount - 1 do
  begin
    HeadingRec := fHeadings[i];

    { Navigate canvas to the correct page so CreateDestination captures the right page }
    if HeadingRec.PageNum < PDF.RawPages.Count then
      PDF.Canvas.SetPage(PDF.RawPages.List[HeadingRec.PageNum]);

    { Convert Y from top-down 1/100mm to PDF bottom-up points.
      Full page H = PageHeight + fMarginTop + fMarginBottom.
      Top of printable area from page bottom = PageHeight + fMarginBottom.
      Heading sits HeadingRec.Y below the printable top. }
    YInPoints := (fPages[HeadingRec.PageNum].PageHeight + fMarginBottom - HeadingRec.Y) * 72 / 2540;

    { Create outline entry for this heading }
    PDF.CreateOutline(HeadingRec.Title, HeadingRec.Level, YInPoints);
  end;
end;

function TGDIPages.NormalizeX(X: Integer): Integer;
begin
  { Validate: X must be relative to printable area [0, fPageWidth] }
  {$IFDEF DEBUG}
  Assert((X >= 0) and (X <= fPageWidth),
    Format('NormalizeX: X=%d out of bounds [0, %d]', [X, fPageWidth]));
  {$ENDIF}
  Result := X;
end;

function TGDIPages.NormalizeY(Y: Integer): Integer;
begin
  { Validate: Y must be relative to printable area [0, fPageHeight] }
  {$IFDEF DEBUG}
  Assert((Y >= 0) and (Y <= fPageHeight),
    Format('NormalizeY: Y=%d out of bounds [0, %d]', [Y, fPageHeight]));
  {$ENDIF}
  Result := Y;
end;

function TGDIPages.ScaleX(V: Integer): Integer;
begin
  { ZENTRALE Skalierungsfunktion für X-Koordinaten: 1/100mm → Render-Pixel }
  Result := Round(V * fRenderScaleX) + fRenderOffsetX;
end;

function TGDIPages.ScaleY(V: Integer): Integer;
begin
  { ZENTRALE Skalierungsfunktion für Y-Koordinaten: 1/100mm → Render-Pixel }
  Result := Round(V * fRenderScaleY) + fRenderOffsetY;
end;

procedure TGDIPages.SetFontStyleProperty(Style: TFontStyles);
begin
  if fFontStyle <> Style then
  begin
    fFontStyle := Style;
    { === Invalidiere Font-Cache - wird neu berechnet bei nächstem SetFont === }
    fCachedLineHeightPx := 0;
    fCachedLineHeightMM := 0;
  end;
end;

procedure TGDIPages.SetMarginLeft(Value: Integer);
begin
  fMarginLeft := Value;
  UpdatePageDimensions;
  { === Update Cache nach Margin-Änderung === }
  fPrintableWidth := fPageWidth;
  fWrappingWidthPx := MMToPixels(fPrintableWidth, 96);
end;

procedure TGDIPages.SetMarginRight(Value: Integer);
begin
  fMarginRight := Value;
  UpdatePageDimensions;
  { === Update Cache nach Margin-Änderung === }
  fPrintableWidth := fPageWidth;
  fWrappingWidthPx := MMToPixels(fPrintableWidth, 96);
end;

procedure TGDIPages.SetMarginTop(Value: Integer);
begin
  fMarginTop := Value;
  UpdatePageDimensions;
  { === Update Cache nach Margin-Änderung === }
  fPrintableHeight := fPageHeight;
end;

procedure TGDIPages.SetMarginBottom(Value: Integer);
begin
  fMarginBottom := Value;
  UpdatePageDimensions;
  { === Update Cache nach Margin-Änderung === }
  fPrintableHeight := fPageHeight;
end;

{ --- inline text formatting --- }

procedure TGDIPages.DrawStrong(X, Y: Integer; const AText: string);
begin
  SaveLayout;
  FontStyle := FontStyle + [fsBold];
  DrawText(X, Y, AText);
  RestoreLayout;
end;

procedure TGDIPages.DrawStrong(const AText: string); overload;
begin
  SaveLayout;
  FontStyle := FontStyle + [fsBold];
  DrawText(AText);
  RestoreLayout;
end;

procedure TGDIPages.DrawEm(X, Y: Integer; const AText: string);
begin
  SaveLayout;
  FontStyle := FontStyle + [fsItalic];
  DrawText(X, Y, AText);
  RestoreLayout;
end;

procedure TGDIPages.DrawEm(const AText: string); overload;
begin
  SaveLayout;
  FontStyle := FontStyle + [fsItalic];
  DrawText(AText);
  RestoreLayout;
end;

procedure TGDIPages.DrawCode(X, Y: Integer; const AText: string);
var
  Format: TReportFormat;
  CodeSize: Integer;
begin
  SaveLayout;
  Format := GetFormat('Code');
  { If Code.FontSize is 0, use 90% of current font; otherwise use explicit size }
  if Format.FontSize > 0 then
    CodeSize := Format.FontSize
  else
    CodeSize := (fFontSize * 90) div 100;
  SetFont(Format.FontName, CodeSize);
  TextColor := Format.Color;
  DrawText(X, Y, AText);
  RestoreLayout;
end;

procedure TGDIPages.DrawCode(const AText: string); overload;
var
  Format: TReportFormat;
  CodeSize: Integer;
begin
  SaveLayout;
  Format := GetFormat('Code');
  { If Code.FontSize is 0, use 90% of current font; otherwise use explicit size }
  if Format.FontSize > 0 then
    CodeSize := Format.FontSize
  else
    CodeSize := (fFontSize * 90) div 100;
  SetFont(Format.FontName, CodeSize);
  TextColor := Format.Color;
  DrawText(AText);
  RestoreLayout;
end;

procedure TGDIPages.DrawLink(X, Y: Integer; const AText: string; const ATarget: string = '');
begin
  SaveLayout;
  SetFont(fFontName, fFontSize);
  FontStyle := FontStyle + [fsUnderline];
  TextColor := clBlue;
  DrawText(X, Y, AText);
  RestoreLayout;
  { Future: could add PDF annotation with ATarget as URL }
end;

procedure TGDIPages.DrawLink(const AText: string; const ATarget: string = ''); overload;
begin
  SaveLayout;
  SetFont(fFontName, fFontSize);
  FontStyle := FontStyle + [fsUnderline];
  TextColor := clBlue;
  DrawText(AText);
  RestoreLayout;
  { Future: could add PDF annotation with ATarget as URL }
end;

procedure TGDIPages.DrawQuote(const AText: string);
begin
  { X=0: start at left edge of printable area }
  { Nutze zentral berechnete fPrintableWidth - kein Buffer-Hack nötig }
  DrawQuote(0, fPrintableWidth, fCurrentY, AText);
end;

procedure TGDIPages.DrawQuote(X, MaxWidth, Y: Integer; const AText: string);
const
  QUOTE_INDENT = 1000; { 10mm indent for quotes }
var
  Format: TReportFormat;
begin
  SaveLayout;
  Format := GetFormat('Quote');
  SetFont(Format.FontName, Format.FontSize);
  FontStyle := Format.FontStyle;
  TextColor := Format.Color;
  if Format.SpaceBefore > 0 then
    MoveToNextLine(Format.SpaceBefore);
  DrawTextWrapped(X + QUOTE_INDENT, MaxWidth - QUOTE_INDENT, Y, AText);
  RestoreLayout;
  { RecordWrappedText already handles line height; only add format spacing }
  MoveToNextLine(Format.SpaceAfter);
end;

procedure TGDIPages.DrawParagraph(const AText: string);
begin
  { X=0: start at left edge of printable area }
  { Nutze zentral berechnete fPrintableWidth - kein Buffer-Hack nötig }
  DrawParagraph(0, fPrintableWidth, fCurrentY, AText);
end;

procedure TGDIPages.DrawParagraph(X, MaxWidth, Y: Integer; const AText: string);
var
  Format: TReportFormat;
begin
  SaveLayout;
  Format := GetFormat('P');
  SetFont(Format.FontName, Format.FontSize);
  FontStyle := Format.FontStyle;
  TextColor := Format.Color;
  if Format.SpaceBefore > 0 then
    MoveToNextLine(Format.SpaceBefore);
  DrawTextWrapped(X, MaxWidth, Y, AText);
  RestoreLayout;
  { RecordWrappedText already handles line height; only add format spacing }
  MoveToNextLine(Format.SpaceAfter);
end;

procedure TGDIPages.DrawListItem(X, Y: Integer; const AText: string; const APrefix: string = '• ');
var
  Format: TReportFormat;
  LH: Integer;
begin
  SaveLayout;
  Format := GetFormat('LI');
  SetFont(Format.FontName, Format.FontSize);
  FontStyle := Format.FontStyle;
  TextColor := Format.Color;
  if Format.SpaceBefore > 0 then
    MoveToNextLine(Format.SpaceBefore);
  DrawText(X, Y, APrefix + AText);
  LH := LineHeightMM;  { Measure with LI-font active }
  RestoreLayout;
  { Advance by line height + format spacing to adapt to font size }
  MoveToNextLine(LH + Format.SpaceAfter);
end;

procedure TGDIPages.DrawCaption(const ACaption: string);
begin
  { X=0: start at left edge of printable area }
  DrawCaption(0, fPrintableWidth, fCurrentY, ACaption);
end;

procedure TGDIPages.DrawCaption(X, MaxWidth, Y: Integer; const ACaption: string);
var
  Format: TReportFormat;
begin
  SaveLayout;
  Format := GetFormat('Caption');
  SetFont(Format.FontName, Format.FontSize);
  FontStyle := Format.FontStyle;
  TextColor := Format.Color;
  if Format.SpaceBefore > 0 then
    MoveToNextLine(Format.SpaceBefore);
  DrawTextWrapped(X, MaxWidth, Y, ACaption);
  RestoreLayout;
  { RecordWrappedText already handles line height; only add format spacing }
  MoveToNextLine(Format.SpaceAfter);
end;

procedure TGDIPages.DrawHeading(ALevel: Integer; const ATitle: string);
var
  HeadingInfo: THeadingInfo;
  Format: TReportFormat;
  TotalSpace: Integer;
  SavedFontName: string;
  SavedFontSize: Integer;
  SavedFontStyle: TFontStyles;
  HeadingLineHeight: Integer;
  FontSizeIn100mm: Integer;
  CurrY: Integer;
begin
  { Validate inputs }
  if (ALevel < 1) or (ALevel > 6) then
    raise Exception.Create('DrawHeading: level must be 1..6');

  if ATitle = '' then
    raise Exception.Create('DrawHeading: title cannot be empty');

  { Get heading format (H1, H2, ..., H6) }
  Format := GetFormat('H' + IntToStr(ALevel));

  { Auto-calculate heading line height for page break check }
  SavedFontName := fFontName;
  SavedFontSize := fFontSize;
  SavedFontStyle := fFontStyle;

  SetFont(Format.FontName, Format.FontSize);
  fFontStyle := Format.FontStyle;
  HeadingLineHeight := LineHeightMM;

  fFontName := SavedFontName;
  fFontSize := SavedFontSize;
  fFontStyle := SavedFontStyle;

  { Space AFTER heading = 1/3 of FONT SIZE (not line height) }
  FontSizeIn100mm := MulDiv(Format.FontSize, PT_TO_100MM, 1000);
  TotalSpace := HeadingLineHeight + (FontSizeIn100mm div 3);

  { Check if heading fits on current page, otherwise move to next page }
  if fCurrentY + TotalSpace > fPageHeight then
    NewPage;

  { Track for PDF bookmarks (save initial Y position before rendering) }
  HeadingInfo.Level := ALevel;
  HeadingInfo.Title := ATitle;
  HeadingInfo.PageNum := fPageCount - 1;  { 0-based current page }
  HeadingInfo.Y := fCurrentY;

  { Render heading with word wrapping (checks right margin) }
  SaveLayout;
  SetFont(Format.FontName, Format.FontSize);
  fFontStyle := Format.FontStyle;
  fTextColor := Format.Color;

  CurrY := fCurrentY;
  fCurrentHeadingLevel := ALevel;
  RecordWrappedText(0, CurrY, ATitle, fPrintableWidth);
  fCurrentHeadingLevel := 0;

  RestoreLayout;
  fCurrentY := CurrY;

  { Add to headings array }
  if fHeadingCount >= Length(fHeadings) then
    SetLength(fHeadings, fHeadingCount + 16);  // grow by 16 elements
  fHeadings[fHeadingCount] := HeadingInfo;
  Inc(fHeadingCount);

  { Advance Y by spacing after heading }
  MoveToNextLine((FontSizeIn100mm div 3));
end;

{ --- drawing helpers --- }

procedure TGDIPages.EmitTextCmd(X, Y: Integer; const S: string; Align: Integer);
var
  Cmd: TDrawCommand;
  TextWidthMM: Integer;
  AdjustedX: Integer;
begin
  Cmd              := Default(TDrawCommand);
  Cmd.Kind         := dckDrawText;
  Cmd.Text         := S;
  Cmd.Color        := fTextColor;
  Cmd.FontName     := fFontName;
  Cmd.FontSize     := fFontSize;
  Cmd.FontStyle    := fFontStyle;
  Cmd.Align        := Align;
  Cmd.HeadingLevel := fCurrentHeadingLevel;
  { Measure text width ONCE at recording time in normalized units }
  TextWidthMM := MeasureTextWidthMM(S);
  Cmd.TextWidthMM := TextWidthMM;

  { Adjust X position based on alignment at recording time }
  AdjustedX := X;
  case Align of
    1: // right-align
      if X = 0 then
        AdjustedX := fPrintableWidth - TextWidthMM  { right-align to page edge }
      else
        AdjustedX := X - TextWidthMM;               { right-align to X position }
    2: // center-align
      if X = 0 then
        AdjustedX := (fPrintableWidth - TextWidthMM) div 2  { center on page }
      else
        AdjustedX := X - (TextWidthMM div 2);               { center at X position }
    // 0 = left — no adjustment
  end;

  Cmd.X         := NormalizeX(AdjustedX);
  Cmd.Y         := NormalizeY(Y);
  AddCommand(Cmd);
end;

procedure TGDIPages.DrawText(X, Y: Integer; const S: string);
begin
  EmitTextCmd(X, Y, S, 0);
end;

procedure TGDIPages.DrawText(const S: string); overload;
var
  TextWidth: Integer;
  LineH: Integer;
begin
  { Check if line fits on current page, otherwise move to next page }
  LineH := LineHeightMM;
  if fCurrentY + LineH > fPageHeight then
  begin
    NewPage;
    fCurrentX := 0;
  end;

  { Draw text at current position and advance X }
  EmitTextCmd(fCurrentX, fCurrentY, S, 0);

  { Measure text width and advance X }
  TextWidth := MeasureTextWidthMM(S);
  fCurrentX := fCurrentX + TextWidth;
end;

procedure TGDIPages.DrawTextRight(X, Y: Integer; const S: string);
begin
  EmitTextCmd(X, Y, S, 1);
end;

procedure TGDIPages.DrawTextAt(X, Y: Integer; const S: string);
begin
  EmitTextCmd(X, Y, S, 0);
end;

procedure TGDIPages.DrawTextCenter(X, Y: Integer; const S: string);
begin
  EmitTextCmd(X, Y, S, 2);
end;

procedure TGDIPages.DrawTextWrapped(X, MaxWidth, Y: Integer; const AText: string);
var
  CurrY: Integer;
begin
  CurrY := Y;
  RecordWrappedText(X, CurrY, AText, MaxWidth);
  fCurrentY := CurrY;
end;

procedure TGDIPages.DrawLine(X1, Y1, X2, Y2, Width: Integer; Color: TColor);
var
  Cmd: TDrawCommand;
begin
  Cmd           := Default(TDrawCommand);
  Cmd.Kind      := dckDrawLine;
  Cmd.X         := NormalizeX(X1);
  Cmd.Y         := NormalizeY(Y1);
  Cmd.X2        := NormalizeX(X2);
  Cmd.Y2        := NormalizeY(Y2);
  Cmd.LineWidth := Width;
  Cmd.Color     := Color;
  AddCommand(Cmd);
end;

procedure TGDIPages.DrawFilledRect(X1, Y1, X2, Y2: Integer; Color: TColor);
var
  Cmd: TDrawCommand;
begin
  Cmd       := Default(TDrawCommand);
  Cmd.Kind  := dckFillRect;
  Cmd.X     := NormalizeX(X1);
  Cmd.Y     := NormalizeY(Y1);
  Cmd.X2    := NormalizeX(X2);
  Cmd.Y2    := NormalizeY(Y2);
  Cmd.Color := Color;
  AddCommand(Cmd);
end;

{ --- Phase 3: word-wrap helper for Columns2 --- }

procedure TGDIPages.RecordWrappedText(X: Integer; var Y: Integer;
  const S: string; MaxWidthMM: Integer);
var
  MaxPx:  Integer;
  SpaceW: Integer;
  LH:     Integer;
  Words:  TStringList;
  Line:   string;
  LineW:  Integer;
  WordW:  Integer;
  i:      Integer;
  MeasureDPI: Integer;
begin
  { Get the actual DPI of the measurement canvas }
  MeasureDPI := GetMeasureDPI;
  { MaxPx is always in 96-DPI-pixels (matches the normalized WordW values below) }
  MaxPx  := MMToPixels(MaxWidthMM, 96);
  SetupMeasureFont;

  { Nutze Font-Cache statt neu zu berechnen }
  if fCachedLineHeightMM > 0 then
    LH := fCachedLineHeightMM
  else
    LH := LineHeightMM;

  { Canvas.TextWidth returns pixels in MeasureDPI. Normalize to 96 DPI for PDF. }
  SpaceW := MMToPixels(PixelsToMM(fMeasureBitmap.Canvas.TextWidth(' '), MeasureDPI), 96);

  Words  := TStringList.Create;
  try
    Words.Delimiter       := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText   := S;
    Line  := '';
    LineW := 0;
    for i := 0 to Words.Count - 1 do
    begin
      if Words[i] = '' then Continue;
      { Canvas.TextWidth returns pixels in MeasureDPI. Normalize to 96 DPI for PDF. }
      WordW := MMToPixels(PixelsToMM(fMeasureBitmap.Canvas.TextWidth(Words[i]), MeasureDPI), 96);
      if (LineW > 0) and (LineW + SpaceW + WordW > MaxPx) then
      begin
        { === Check for page break before emitting line === }
        if Y + LH > fPageHeight then
        begin
          NewPage;
          Y := 0;
        end;
        EmitTextCmd(NormalizeX(X), NormalizeY(Y), Line, 0);
        Inc(Y, LH);
        Line  := Words[i];
        LineW := WordW;
      end
      else if Line <> '' then
      begin
        Line  := Line + ' ' + Words[i];
        Inc(LineW, SpaceW + WordW);
      end
      else
      begin
        Line  := Words[i];
        LineW := WordW;
      end;
    end;
    if Line <> '' then
    begin
      { === Check for page break before emitting final line === }
      if Y + LH > fPageHeight then
      begin
        NewPage;
        Y := 0;
      end;
      EmitTextCmd(NormalizeX(X), NormalizeY(Y), Line, 0);
      Inc(Y, LH);
    end;
  finally
    Words.Free;
  end;
end;

procedure TGDIPages.Columns2(Gap: Integer; const Text1, Text2: string);
var
  ColW:    Integer;
  Y1, Y2: Integer;
begin
  ColW := (fPageWidth - Gap) div 2;
  Y1   := fCurrentY;
  Y2   := fCurrentY;
  RecordWrappedText(0,          Y1, Text1, ColW);
  RecordWrappedText(ColW + Gap, Y2, Text2, ColW);
  fCurrentY := Max(Y1, Y2);
end;

procedure TGDIPages.AddVerticalSpace(mm: Integer);
begin
  Inc(fCurrentY, MMToPixels(mm * 100, 96));
end;

procedure TGDIPages.ForceNewPage;
begin
  NewPage;
  fCurrentY := 0;
end;

{ ========================================================================
  Phase 4: Table rendering with flexible TTableLayout
  ======================================================================== }

procedure TGDIPages.BeginTable(const Layout: TTableLayout); overload;
var
  i: Integer;
  BTCmd: TDrawCommand;
begin
  if fTableInProgress then
    raise Exception.Create('BeginTable: table already in progress');
  fTableInProgress := True;
  SaveLayout;  { Save font/style to restore after EndTable }
  fTableStartY := fCurrentY;
  fTableRowStartY := fCurrentY;
  fTableLayout := Layout;
  fTableRowIndex := 0;

  { Copy column widths and aligns from layout }
  SetLength(fTableColWidths, Length(Layout.ColumnWidths));
  for i := 0 to High(Layout.ColumnWidths) do
    fTableColWidths[i] := Layout.ColumnWidths[i];

  SetLength(fTableColAligns, Length(Layout.ColumnAligns));
  for i := 0 to High(Layout.ColumnAligns) do
    fTableColAligns[i] := Layout.ColumnAligns[i];

  { Default alignments if not provided }
  if Length(fTableColAligns) < Length(fTableColWidths) then
    for i := Length(fTableColAligns) to Length(fTableColWidths) - 1 do
      fTableColAligns[i] := tcaLeft;
  BTCmd := Default(TDrawCommand);
  BTCmd.Kind := dckBeginTable;
  AddCommand(BTCmd);
end;

procedure TGDIPages.DrawTableHeader(const Headers: array of string);
var
  i: Integer;
  Cmd: TDrawCommand;
  TRCmd: TDrawCommand;
  CellX, CellWidth, CellY: Integer;
  AlignValue: Integer;
  CellHeight: Integer;
begin
  if not fTableInProgress then
    raise Exception.Create('DrawTableHeader: BeginTable not called');

  // Save header content for automatic repetition on continuation pages
  SetLength(fTableSavedHeaders, Length(Headers));
  for i := 0 to High(Headers) do
    fTableSavedHeaders[i] := Headers[i];

  TRCmd := Default(TDrawCommand);
  TRCmd.Kind  := dckBeginTR;
  TRCmd.Color := 1;  // 1 = header row
  AddCommand(TRCmd);
  SaveLayout;
  { Use table layout fonts if specified, otherwise use current document font }
  if fTableLayout.HeaderFontName <> '' then
    SetFont(fTableLayout.HeaderFontName, fTableLayout.HeaderFontSize)
  else
    { Keep current font name/size, only change style to HeaderFontStyle }
    fFontStyle := fTableLayout.HeaderFontStyle;
  fTextColor := clBlack;

  { Cell height includes padding above and small padding below text }
  CellHeight := LineHeightMM + CELL_PADDING;

  { Draw header cells }
  CellX := 0;
  for i := 0 to Min(High(Headers), High(fTableColWidths)) do
  begin
    CellWidth := fTableColWidths[i];

    { Fill header background }
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckFillRect;
    Cmd.X := NormalizeX(CellX);
    Cmd.Y := NormalizeY(fCurrentY);
    Cmd.X2 := NormalizeX(CellX + CellWidth);
    Cmd.Y2 := NormalizeY(fCurrentY + CellHeight);
    Cmd.Color := fTableLayout.HeaderBkColor;
    AddCommand(Cmd);

    { Draw header border }
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckDrawRect;
    Cmd.X := NormalizeX(CellX);
    Cmd.Y := NormalizeY(fCurrentY);
    Cmd.X2 := NormalizeX(CellX + CellWidth);
    Cmd.Y2 := NormalizeY(fCurrentY + CellHeight);
    Cmd.Color := clBlack;
    Cmd.LineWidth := 1;
    AddCommand(Cmd);

    { Draw header text }
    CellY := fCurrentY + CELL_PADDING;
    case fTableColAligns[i] of
      tcaRight:
        AlignValue := 1;
      tcaCenter:
        AlignValue := 2;
    else
      AlignValue := 0;
    end;
    { WICHTIG: Für Rechtsbündigkeit muss Textlänge SCHON in X-Position eingerechnet sein! }
    case AlignValue of
      1: { Right: X = right_edge - text_width, dann wird Text linksbündig gerendert }
        EmitTextCmd(NormalizeX(CellX + CellWidth - CELL_PADDING - MeasureTextWidthMM(Headers[i])), NormalizeY(CellY), Headers[i], 0);
      2: { Center: use middle of cell }
        EmitTextCmd(NormalizeX(CellX + CellWidth div 2), NormalizeY(CellY), Headers[i], AlignValue);
    else
      { Left: normal left-aligned }
      EmitTextCmd(NormalizeX(CellX + CELL_PADDING), NormalizeY(CellY), Headers[i], AlignValue);
    end;

    CellX := CellX + CellWidth;
  end;

  RestoreLayout;
  Inc(fCurrentY, CellHeight);
  Inc(fTableRowIndex);
  TRCmd := Default(TDrawCommand);
  TRCmd.Kind := dckEndTR;
  AddCommand(TRCmd);
end;

procedure TGDIPages.DrawTableRow(const Values: array of string);
var
  i: Integer;
  Cmd: TDrawCommand;
  TRCmd: TDrawCommand;
  CellX, CellWidth, CellY: Integer;
  AlignValue: Integer;
  BgColor: TColor;
  RowHeight: Integer;
begin
  if not fTableInProgress then
    raise Exception.Create('DrawTableRow: BeginTable not called');

  { Calculate row height with padding above and small padding below text }
  RowHeight := LineHeightMM + CELL_PADDING;

  { Check for page break — repeat column headers on the continuation page }
  if fCurrentY + RowHeight > fPageHeight then
  begin
    ForceNewPage;
    if Length(fTableSavedHeaders) > 0 then
      DrawTableHeader(fTableSavedHeaders);
  end;

  TRCmd := Default(TDrawCommand);
  TRCmd.Kind  := dckBeginTR;
  TRCmd.Color := 0;  // 0 = data row
  AddCommand(TRCmd);

  { Determine background color (alternating rows) }
  if (fTableLayout.AlternateRowColor <> 0) and (fTableRowIndex mod 2 = 1) then
    BgColor := fTableLayout.AlternateRowColor
  else
    BgColor := fTableLayout.BodyBkColor;

  SaveLayout;
  { Use table layout fonts if specified, otherwise use current document font }
  if fTableLayout.BodyFontName <> '' then
    SetFont(fTableLayout.BodyFontName, fTableLayout.BodyFontSize)
  else
    { Keep current font name/size, only change style to BodyFontStyle }
    fFontStyle := fTableLayout.BodyFontStyle;
  fTextColor := clBlack;

  { Draw body cells }
  CellX := 0;
  for i := 0 to Min(High(Values), High(fTableColWidths)) do
  begin
    CellWidth := fTableColWidths[i];

    { Fill body background }
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckFillRect;
    Cmd.X := NormalizeX(CellX);
    Cmd.Y := NormalizeY(fCurrentY);
    Cmd.X2 := NormalizeX(CellX + CellWidth);
    Cmd.Y2 := NormalizeY(fCurrentY + RowHeight);
    Cmd.Color := BgColor;
    AddCommand(Cmd);

    { Draw body border }
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckDrawRect;
    Cmd.X := NormalizeX(CellX);
    Cmd.Y := NormalizeY(fCurrentY);
    Cmd.X2 := NormalizeX(CellX + CellWidth);
    Cmd.Y2 := NormalizeY(fCurrentY + RowHeight);
    Cmd.Color := clBlack;
    Cmd.LineWidth := 1;
    AddCommand(Cmd);

    { Draw body text }
    CellY := fCurrentY + CELL_PADDING;
    case fTableColAligns[i] of
      tcaRight:
        AlignValue := 1;
      tcaCenter:
        AlignValue := 2;
    else
      AlignValue := 0;
    end;
    { WICHTIG: Für Rechtsbündigkeit muss Textlänge SCHON in X-Position eingerechnet sein! }
    case AlignValue of
      1: { Right: X = right_edge - text_width, dann wird Text linksbündig gerendert }
        EmitTextCmd(NormalizeX(CellX + CellWidth - CELL_PADDING - MeasureTextWidthMM(Values[i])), NormalizeY(CellY), Values[i], 0);
      2: { Center: use middle of cell }
        EmitTextCmd(NormalizeX(CellX + CellWidth div 2), NormalizeY(CellY), Values[i], AlignValue);
    else
      { Left: normal left-aligned }
      EmitTextCmd(NormalizeX(CellX + CELL_PADDING), NormalizeY(CellY), Values[i], AlignValue);
    end;

    CellX := CellX + CellWidth;
  end;

  RestoreLayout;
  Inc(fCurrentY, RowHeight);
  fTableRowStartY := fCurrentY;
  Inc(fTableRowIndex);
  TRCmd := Default(TDrawCommand);
  TRCmd.Kind := dckEndTR;
  AddCommand(TRCmd);
end;

procedure TGDIPages.BeginTable(const ColWidths: array of Integer;
                              const ColAligns: array of TTableColumnAlign);
var
  i: Integer;
  Cmd: TDrawCommand;
begin
  if fTableInProgress then
    raise Exception.Create('BeginTable: table already in progress');
  fTableInProgress := True;
  fTableStartY := fCurrentY;
  fTableRowStartY := fCurrentY;
  SetLength(fTableColWidths, Length(ColWidths));
  for i := 0 to High(ColWidths) do
    fTableColWidths[i] := ColWidths[i];
  SetLength(fTableColAligns, Length(ColAligns));
  for i := 0 to High(ColAligns) do
    fTableColAligns[i] := ColAligns[i];
  // If no aligns provided, default to left
  if Length(fTableColAligns) < Length(fTableColWidths) then
    for i := Length(fTableColAligns) to Length(fTableColWidths) - 1 do
      fTableColAligns[i] := tcaLeft;
  // Emit a marker command
  Cmd := Default(TDrawCommand);
  Cmd.Kind := dckBeginTable;
  AddCommand(Cmd);
end;

procedure TGDIPages.AddTableRow(const Cells: array of string; IsHeader: boolean = false);
const
  HEADER_COLOR = $E0E0E0;  // light gray
  ROW_COLOR = $FFFFFF;     // white
var
  i, RowHeight, CellY: Integer;
  Cmd: TDrawCommand;
  CellX, CellWidth: Integer;
  AlignValue: Integer;
  CellText: string;
begin
  if not fTableInProgress then
    raise Exception.Create('AddTableRow: BeginTable not called');

  // Calculate row height based on font (including cell padding)
  RowHeight := LineHeightMM + CELL_PADDING;

  // Check for page break
  if fCurrentY + RowHeight > fPageHeight then
    ForceNewPage;

  // Draw table cells
  CellX := 0;
  for i := 0 to Min(High(Cells), High(fTableColWidths)) do
  begin
    CellWidth := fTableColWidths[i];

    // Draw cell background
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckFillRect;
    Cmd.X := NormalizeX(CellX);
    Cmd.Y := NormalizeY(fCurrentY);
    Cmd.X2 := NormalizeX(CellX + CellWidth);
    Cmd.Y2 := NormalizeY(fCurrentY + RowHeight);
    if IsHeader then
      Cmd.Color := HEADER_COLOR
    else
      Cmd.Color := ROW_COLOR;
    AddCommand(Cmd);

    // Draw cell border
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckDrawRect;
    Cmd.X := NormalizeX(CellX);
    Cmd.Y := NormalizeY(fCurrentY);
    Cmd.X2 := NormalizeX(CellX + CellWidth);
    Cmd.Y2 := NormalizeY(fCurrentY + RowHeight);
    Cmd.Color := clBlack;
    Cmd.LineWidth := 1;
    AddCommand(Cmd);

    // Draw cell text
    CellText := Cells[i];
    CellY := fCurrentY + CELL_PADDING;
    case fTableColAligns[i] of
      tcaRight:
        AlignValue := 1;
      tcaCenter:
        AlignValue := 2;
    else
      AlignValue := 0;
    end;
    { WICHTIG: Für Rechtsbündigkeit muss Textlänge SCHON in X-Position eingerechnet sein! }
    case AlignValue of
      1: { Right: X = right_edge - text_width, dann wird Text linksbündig gerendert }
        EmitTextCmd(NormalizeX(CellX + CellWidth - CELL_PADDING - MeasureTextWidthMM(CellText)), NormalizeY(CellY), CellText, 0);
      2: { Center: use middle of cell }
        EmitTextCmd(NormalizeX(CellX + CellWidth div 2), NormalizeY(CellY), CellText, AlignValue);
    else
      { Left: normal left-aligned }
      EmitTextCmd(NormalizeX(CellX + CELL_PADDING), NormalizeY(CellY), CellText, AlignValue);
    end;

    CellX := CellX + CellWidth;
  end;

  Inc(fCurrentY, RowHeight);
  fTableRowStartY := fCurrentY;
end;

procedure TGDIPages.EndTable;
var
  Cmd: TDrawCommand;
begin
  if not fTableInProgress then
    raise Exception.Create('EndTable: BeginTable not called');
  fTableInProgress := False;
  fTableSavedHeaders := nil; // release saved headers
  // Emit end table marker
  Cmd := Default(TDrawCommand);
  Cmd.Kind := dckEndTable;
  AddCommand(Cmd);
  { Restore font/style from BeginTable SaveLayout }
  RestoreLayout;
end;

{ =========================================================================
  Phase 3 – RenderPageToCanvas
  ========================================================================= }

procedure TGDIPages.RenderPageToCanvas(ACanvas: TCanvas;
  PageIndex, DestWidth, DestHeight: Integer;
  SourceDPI: Integer = 0);
var
  Page:           TPageData;
  Cmd:            TDrawCommand;
  i, TX, TW:     Integer;
  R:              TRect;
  HeaderText, FooterText: string;
  Format:         TReportFormat;  // For heading/text formatting
  FontScale:      Double;
  BaseHeight:     Integer;
  InTableRow:     boolean;        // true between dckBeginTR and dckEndTR
  InHeaderRow:    boolean;        // true if current TR is a header row


  function SubstitutePlaceholders(const AText: string; PageNum: Integer): string;
  begin
    Result := AText;
    Result := StringReplace(Result, '{#}', IntToStr(PageNum + 1), [rfReplaceAll]);
    Result := StringReplace(Result, '{total}', IntToStr(fPageCount), [rfReplaceAll]);
  end;

  procedure ApplyFont;
  begin
    ACanvas.Font.Name  := Cmd.FontName;
    ACanvas.Font.Size  := Round(Cmd.FontSize * FontScale);
    ACanvas.Font.Style := Cmd.FontStyle;
    ACanvas.Font.Color := Cmd.Color;
  end;

begin
  if (PageIndex < 0) or (PageIndex >= fPageCount) then Exit;
  Page := fPages[PageIndex];
  if (Page.PageWidth <= 0) or (Page.PageHeight <= 0) then Exit;

  { === Cache Rendering-Parameter einmalig am Anfang === }
  fRenderScaleX := DestWidth  / (Page.PageWidth  + Page.MarginLeft + Page.MarginRight);
  fRenderScaleY := DestHeight / (Page.PageHeight + Page.MarginTop  + Page.MarginBottom);
  fRenderOffsetX := Round(Page.MarginLeft * fRenderScaleX);
  fRenderOffsetY := Round(Page.MarginTop  * fRenderScaleY);

  { Font scaling: at base DPI without zoom, FontScale=1.0.
    When DestHeight differs from base (e.g. preview zoom), scale fonts proportionally.
    SourceDPI>0 (PDF export): BaseHeight uses same DPI as DestHeight → FontScale=1.0 always. }
  if SourceDPI > 0 then
    BaseHeight := MMToPixels(Page.PageHeight + Page.MarginTop + Page.MarginBottom, SourceDPI)
  else
    BaseHeight := MMToPixels(Page.PageHeight + Page.MarginTop + Page.MarginBottom,
                             ACanvas.Font.PixelsPerInch);
  if BaseHeight > 0 then
    FontScale := DestHeight / BaseHeight
  else
    FontScale := 1.0;

  InTableRow  := false;
  InHeaderRow := false;

  ACanvas.Brush.Color := clWhite;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.FillRect(Rect(0, 0, DestWidth, DestHeight));

  { Render header if set }
  if fHeaderText <> '' then
  begin
    HeaderText := SubstitutePlaceholders(fHeaderText, PageIndex);
    ACanvas.Font.Name  := fFontName;
    ACanvas.Font.Size  := Round(fFontSize * FontScale);
    ACanvas.Font.Style := fFontStyle;
    ACanvas.Font.Color := fTextColor;
    ACanvas.Brush.Style := bsClear;
    ACanvas.TextOut(fRenderOffsetX, (fRenderOffsetY - ACanvas.TextHeight(HeaderText)) div 2, HeaderText);
  end;

  for i := 0 to High(Page.Commands) do
  begin
    Cmd := Page.Commands[i];
    case Cmd.Kind of
      dckDrawText:
      begin
        if fActivePdfDoc <> nil then
        begin
          if Cmd.HeadingLevel > 0 then
            fActivePdfDoc.BeginStructContent(TPdfStructRole(Cmd.HeadingLevel))
          else if InTableRow then
          begin
            if InHeaderRow then
              fActivePdfDoc.BeginStructContent(psrTH)
            else
              fActivePdfDoc.BeginStructContent(psrTD);
          end
          else
            fActivePdfDoc.BeginStructContent(psrP);
        end;
        ApplyFont;
        ACanvas.Brush.Style := bsClear;
        { X position is pre-adjusted at recording time:
          - For right align: X has text width subtracted
          - For center align: X has half text width subtracted
          - For left align: X is unchanged
          - Just render at the adjusted X position }
        TX := ScaleX(Cmd.X);
        ACanvas.TextOut(TX, ScaleY(Cmd.Y), SubstitutePlaceholders(Cmd.Text, PageIndex));
        if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
      end;
      dckDrawLine:
      begin
        ACanvas.Pen.Color := Cmd.Color;
        ACanvas.Pen.Width := Max(1, Cmd.LineWidth);
        ACanvas.MoveTo(ScaleX(Cmd.X),  ScaleY(Cmd.Y));
        ACanvas.LineTo(ScaleX(Cmd.X2), ScaleY(Cmd.Y2));
      end;
      dckFillRect:
      begin
        R := Rect(ScaleX(Cmd.X), ScaleY(Cmd.Y), ScaleX(Cmd.X2), ScaleY(Cmd.Y2));
        ACanvas.Brush.Color := Cmd.Color;
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Pen.Style   := psClear;
        ACanvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
        ACanvas.Pen.Style   := psSolid;
      end;
      dckDrawRect:
      begin
        R := Rect(ScaleX(Cmd.X), ScaleY(Cmd.Y), ScaleX(Cmd.X2), ScaleY(Cmd.Y2));
        ACanvas.Pen.Color   := Cmd.Color;
        ACanvas.Pen.Width   := Max(1, Cmd.LineWidth);
        ACanvas.Brush.Style := bsClear;
        ACanvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
      end;
      dckDrawBitmap:
        if (Cmd.BitmapIndex >= 0) and (Cmd.BitmapIndex < fBitmaps.Count) then
        begin
          if fActivePdfDoc <> nil then
            fActivePdfDoc.BeginStructContent(psrFigure);
          R := Rect(ScaleX(Cmd.X), ScaleY(Cmd.Y), ScaleX(Cmd.X2), ScaleY(Cmd.Y2));
          ACanvas.StretchDraw(R, TBitmap(fBitmaps[Cmd.BitmapIndex]));
          if fActivePdfDoc <> nil then
            fActivePdfDoc.EndStructContent;
        end;
      dckHeading:
      begin
        if fActivePdfDoc <> nil then
          fActivePdfDoc.BeginStructContent(TPdfStructRole(Cmd.HeadingLevel));
        { Render heading with format from registry }
        Format := GetFormat('H' + IntToStr(Cmd.HeadingLevel));
        ACanvas.Font.Name := Format.FontName;
        ACanvas.Font.Size := Round(Format.FontSize * FontScale);
        ACanvas.Font.Style := Format.FontStyle;
        ACanvas.Font.Color := Format.Color;
        ACanvas.Brush.Style := bsClear;
        { Render heading text (left-aligned) }
        TX := ScaleX(Cmd.X);
        ACanvas.TextOut(TX, ScaleY(Cmd.Y), SubstitutePlaceholders(Cmd.HeadingTitle, PageIndex));
        if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
      end;
      dckBeginTable:
        if fActivePdfDoc <> nil then
          fActivePdfDoc.BeginStructContent(psrTable);
      dckEndTable:
      begin
        if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
        InTableRow  := false;
        InHeaderRow := false;
      end;
      dckBeginTR:
      begin
        InHeaderRow := Cmd.Color <> 0;
        InTableRow  := true;
        if fActivePdfDoc <> nil then
          fActivePdfDoc.BeginStructContent(psrTR);
      end;
      dckEndTR:
      begin
        if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
        InTableRow  := false;
        InHeaderRow := false;
      end;
    end;
  end;

  { Render footer if set }
  if fFooterText <> '' then
  begin
    FooterText := SubstitutePlaceholders(fFooterText, PageIndex);
    ACanvas.Font.Name  := fFontName;
    ACanvas.Font.Size  := Round(fFontSize * FontScale);
    ACanvas.Font.Style := fFontStyle;
    ACanvas.Font.Color := fTextColor;
    ACanvas.Brush.Style := bsClear;
    ACanvas.TextOut(fRenderOffsetX,
      ScaleY(Page.PageHeight) +
      (DestHeight - ScaleY(Page.PageHeight) - ACanvas.TextHeight(FooterText)) div 2,
      FooterText);
  end;
end;

{ =========================================================================
  Phase 4 – ShowPreviewForm (modal LCL form with TPaintBox)
  ========================================================================= }

procedure TGDIPages.PreviewUpdateLabel;
begin
  if fPreviewLblPage <> nil then
    fPreviewLblPage.Caption := Format('Page %d / %d', [fPreviewCurrPage + 1, fPreviewTotalPages]);
end;

procedure TGDIPages.PreviewDoPaint(Sender: TObject);
var
  PB: TPaintBox;
  ZW, ZH: Integer;
begin
  PB := TPaintBox(Sender);
  ZW := Round(fPreviewW * fPreviewZoom);
  ZH := Round(fPreviewH * fPreviewZoom);
  PB.Canvas.Brush.Color := clWhite;
  PB.Canvas.FillRect(Rect(0, 0, ZW, ZH));
  if (fPreviewCurrPage >= 0) and (fPreviewCurrPage < fPreviewTotalPages) then
    RenderPageToCanvas(PB.Canvas, fPreviewCurrPage, ZW, ZH);
end;

procedure TGDIPages.PreviewDoPrev(Sender: TObject);
begin
  if fPreviewCurrPage > 0 then
  begin
    Dec(fPreviewCurrPage);
    PreviewUpdateLabel;
    if fPreviewPaintBox <> nil then
      fPreviewPaintBox.Invalidate;
  end;
end;

procedure TGDIPages.PreviewDoNext(Sender: TObject);
begin
  if fPreviewCurrPage < fPreviewTotalPages - 1 then
  begin
    Inc(fPreviewCurrPage);
    PreviewUpdateLabel;
    if fPreviewPaintBox <> nil then
      fPreviewPaintBox.Invalidate;
  end;
end;

procedure TGDIPages.PreviewApplyZoom;
var
  ZW, ZH, CX, CY: Integer;
begin
  if (fPreviewPaintBox = nil) or (fPreviewScrollBox = nil) then
    Exit;
  ZW := Round(fPreviewW * fPreviewZoom);
  ZH := Round(fPreviewH * fPreviewZoom);
  fPreviewPaintBox.Width  := ZW;
  fPreviewPaintBox.Height := ZH;
  CX := (fPreviewScrollBox.ClientWidth  - ZW) div 2;
  CY := (fPreviewScrollBox.ClientHeight - ZH) div 2;
  if CX < GRAY_MARGIN then CX := GRAY_MARGIN;
  if CY < GRAY_MARGIN then CY := GRAY_MARGIN;
  fPreviewPaintBox.Left := CX;
  fPreviewPaintBox.Top  := CY;
  if fPreviewEdtZoom <> nil then
    fPreviewEdtZoom.Text := Format('%d%%', [Round(fPreviewZoom * 100)]);
  fPreviewPaintBox.Invalidate;
end;

procedure TGDIPages.PreviewDoZoomIn(Sender: TObject);
begin
  if fPreviewZoom < 4.0 then
  begin
    fPreviewZoom := fPreviewZoom + 0.25;
    if fPreviewZoom > 4.0 then
      fPreviewZoom := 4.0;
    PreviewApplyZoom;
  end;
end;

procedure TGDIPages.PreviewDoZoomOut(Sender: TObject);
begin
  if fPreviewZoom > 0.25 then
  begin
    fPreviewZoom := fPreviewZoom - 0.25;
    if fPreviewZoom < 0.25 then
      fPreviewZoom := 0.25;
    PreviewApplyZoom;
  end;
end;

procedure TGDIPages.PreviewDoFitPage(Sender: TObject);
var
  ZX, ZY: Double;
begin
  if fPreviewScrollBox = nil then
    Exit;
  ZX := (fPreviewScrollBox.ClientWidth  - 2 * GRAY_MARGIN) / fPreviewW;
  ZY := (fPreviewScrollBox.ClientHeight - 2 * GRAY_MARGIN) / fPreviewH;
  fPreviewZoom := Min(ZX, ZY);
  if fPreviewZoom < 0.1 then
    fPreviewZoom := 0.1;
  PreviewApplyZoom;
end;

procedure TGDIPages.PreviewDoFitWidth(Sender: TObject);
begin
  if fPreviewScrollBox = nil then
    Exit;
  fPreviewZoom := (fPreviewScrollBox.ClientWidth - 2 * GRAY_MARGIN) / fPreviewW;
  if fPreviewZoom < 0.1 then
    fPreviewZoom := 0.1;
  PreviewApplyZoom;
end;

procedure TGDIPages.PreviewDoFormResize(Sender: TObject);
begin
  PreviewApplyZoom;
  if fPreviewLblPage <> nil then
    fPreviewLblPage.Left := (fPreviewLblPage.Parent.Width - fPreviewLblPage.Width) div 2;
end;

procedure TGDIPages.PreviewDoKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  case Key of
    VK_PRIOR:
      PreviewDoPrev(nil);
    VK_NEXT:
      PreviewDoNext(nil);
    VK_HOME:
      if fPreviewCurrPage <> 0 then
      begin
        fPreviewCurrPage := 0;
        PreviewUpdateLabel;
        if fPreviewPaintBox <> nil then
          fPreviewPaintBox.Invalidate;
      end;
    VK_END:
      if fPreviewCurrPage <> fPreviewTotalPages - 1 then
      begin
        fPreviewCurrPage := fPreviewTotalPages - 1;
        PreviewUpdateLabel;
        if fPreviewPaintBox <> nil then
          fPreviewPaintBox.Invalidate;
      end;
    VK_OEM_PLUS, VK_ADD:
      if ssCtrl in Shift then
        PreviewDoZoomIn(nil);
    VK_OEM_MINUS, VK_SUBTRACT:
      if ssCtrl in Shift then
        PreviewDoZoomOut(nil);
    VK_0, VK_NUMPAD0:
      if ssCtrl in Shift then
      begin
        fPreviewZoom := 1.0;
        PreviewApplyZoom;
      end;
  end;
end;

procedure TGDIPages.PreviewDoMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  if ssCtrl in Shift then
  begin
    if WheelDelta > 0 then
      PreviewDoZoomIn(nil)
    else
      PreviewDoZoomOut(nil);
    Handled := True;
  end;
end;

procedure TGDIPages.PreviewDoZoomEdit(Sender: TObject);
var
  S: string;
  ZoomVal: Double;
  Code: Integer;
begin
  if fPreviewEdtZoom = nil then Exit;
  S := Trim(fPreviewEdtZoom.Text);
  if (Length(S) > 0) and (S[Length(S)] = '%') then
    S := Trim(Copy(S, 1, Length(S) - 1));
  Val(S, ZoomVal, Code);
  if Code <> 0 then
  begin
    fPreviewEdtZoom.Text := Format('%d%%', [Round(fPreviewZoom * 100)]);
    Exit;
  end;
  ZoomVal := ZoomVal / 100.0;
  if ZoomVal < 0.25 then ZoomVal := 0.25;
  if ZoomVal > 4.0  then ZoomVal := 4.0;
  fPreviewZoom := ZoomVal;
  PreviewApplyZoom;
end;

procedure TGDIPages.ShowPreviewForm;
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
begin
  fPreviewTotalPages := fPageCount;
  if fPreviewTotalPages = 0 then
  begin
    ShowMessage('No pages available.');
    Exit;
  end;
  fPreviewCurrPage := 0;
  fPreviewZoom := 1.0;
  // Base preview size @ 96 DPI (unzoomed reference, same DPI as PDF export)
  if fPages[0].PageWidth > 0 then
  begin
    fPreviewW := MMToPixels(fPages[0].PageWidth + fMarginLeft + fMarginRight, 96);
    fPreviewH := MMToPixels(fPages[0].PageHeight + fMarginTop + fMarginBottom, 96);
  end
  else
  begin
    fPreviewW := 793;  // A4 portrait fallback: 210mm @ 96 DPI
    fPreviewH := 1175; // 297mm @ 96 DPI
  end;
  Form := TForm.Create(nil);
  try
    Form.Caption := fTitle;
    if Form.Caption = '' then
      Form.Caption := 'Print Preview';
    Form.Position    := poScreenCenter;
    Form.BorderStyle := bsSizeable;
    Form.KeyPreview  := True;
    Form.Width  := Min(Round(Screen.Width  * 0.8), 1200);
    Form.Height := Min(Round(Screen.Height * 0.8), 900);
    Form.OnResize    := PreviewDoFormResize;
    Form.OnKeyDown   := PreviewDoKeyDown;
    fPreviewForm     := Form;
    // --- top toolbar panel (zoom controls) ---
    TopPanel := TPanel.Create(Form);
    TopPanel.Parent     := Form;
    TopPanel.Align      := alTop;
    TopPanel.Height     := 36;
    TopPanel.BevelOuter := bvNone;
    BtnZoomOut := TButton.Create(Form);
    BtnZoomOut.Parent  := TopPanel;
    BtnZoomOut.Caption := '−';
    BtnZoomOut.SetBounds(8, 4, 32, 28);
    BtnZoomOut.OnClick := PreviewDoZoomOut;
    EdtZoom := TEdit.Create(Form);
    EdtZoom.Parent    := TopPanel;
    EdtZoom.SetBounds(44, 6, 60, 24);
    EdtZoom.Alignment := taCenter;
    EdtZoom.OnEditingDone := PreviewDoZoomEdit;
    fPreviewEdtZoom   := EdtZoom;
    BtnZoomIn := TButton.Create(Form);
    BtnZoomIn.Parent  := TopPanel;
    BtnZoomIn.Caption := '+';
    BtnZoomIn.SetBounds(108, 4, 32, 28);
    BtnZoomIn.OnClick := PreviewDoZoomIn;
    BtnFitPage := TButton.Create(Form);
    BtnFitPage.Parent  := TopPanel;
    BtnFitPage.Caption := 'Fit Page';
    BtnFitPage.SetBounds(152, 4, 90, 28);
    BtnFitPage.OnClick := PreviewDoFitPage;
    BtnFitWidth := TButton.Create(Form);
    BtnFitWidth.Parent  := TopPanel;
    BtnFitWidth.Caption := 'Fit Width';
    BtnFitWidth.SetBounds(248, 4, 90, 28);
    BtnFitWidth.OnClick := PreviewDoFitWidth;
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
    BtnPrev.OnClick := PreviewDoPrev;
    LblPage := TLabel.Create(Form);
    LblPage.Parent    := BtnPanel;
    LblPage.AutoSize  := False;
    LblPage.Width     := 140;
    LblPage.Left      := (BtnPanel.Width - 140) div 2;
    LblPage.Top       := 14;
    LblPage.Alignment := taCenter;
    fPreviewLblPage   := LblPage;
    PreviewUpdateLabel;
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
    BtnNext.OnClick := PreviewDoNext;
    // --- scroll box (fills center area) ---
    ScrollBox := TScrollBox.Create(Form);
    ScrollBox.Parent      := Form;
    ScrollBox.Align       := alClient;
    ScrollBox.Color       := clSilver;
    ScrollBox.AutoScroll  := True;
    ScrollBox.BorderStyle := bsNone;
    ScrollBox.OnMouseWheel := PreviewDoMouseWheel;
    fPreviewScrollBox := ScrollBox;
    // --- paint box (inside scroll box, explicit size set by PreviewApplyZoom) ---
    PaintBox := TPaintBox.Create(Form);
    PaintBox.Parent  := ScrollBox;
    PaintBox.Color   := clWhite;
    fPreviewPaintBox := PaintBox;
    PaintBox.OnPaint := PreviewDoPaint;
    // initial zoom: 100%
    fPreviewZoom := 1.0;
    PreviewApplyZoom;
    Form.ShowModal;
  finally
    fPreviewForm      := nil;
    fPreviewPaintBox  := nil;
    fPreviewScrollBox := nil;
    fPreviewLblPage   := nil;
    fPreviewEdtZoom   := nil;
    Form.Free;
  end;
end;

{ =========================================================================
  §5.2 – ShowPrintDialog (LCL TPrintDialog)
  ========================================================================= }

procedure TGDIPages.ShowPrintDialog;
begin
  // Phase 5.2: Print all pages directly (TPrintDialog not available/reliable)
  // TODO: implement proper printer dialog when LCL stabilizes TPrintDialog
  PrintPages(0, fPageCount - 1);
end;

{ =========================================================================
  §5.3 – OpenPdfFile (cross-platform: xdg-open / open / ShellExecute)
  ========================================================================= }

procedure TGDIPages.OpenPdfFile(const FileName: string);
begin
  // Phase 5.3: Open PDF with system viewer (cross-platform)
  // Note: Not implemented; PDF file is saved, user can open manually
  // TODO: implement system viewer integration when LCL OpenDocument stabilizes
end;

{ =========================================================================
  Phase 5 – PrintPages via LCL TPrinter
  ========================================================================= }

procedure TGDIPages.PrintPages(From, To_: Integer);
var
  i: Integer;
begin
  if fPageCount = 0 then Exit;
  if From < 0 then          From := 0;
  if To_ >= fPageCount then To_  := fPageCount - 1;
  if From > To_ then Exit;
  Printer.BeginDoc;
  try
    for i := From to To_ do
    begin
      if i > From then
        Printer.NewPage;
      RenderPageToCanvas(Printer.Canvas, i, Printer.PageWidth, Printer.PageHeight);
    end;
  finally
    Printer.EndDoc;
  end;
end;

{ =========================================================================
  Phase 6 – ExportPdfStream / ExportPDF via TPdfDocumentVcl
  ========================================================================= }

procedure TGDIPages.GetExportFonts(out SansFont, SerifFont, MonoFont: string);
begin
  GetReportFonts(fExportPdfEmbeddedTTF, SansFont, SerifFont, MonoFont);
end;

function TGDIPages.ExportPdfStream(aDest: TStream): boolean;
var
  PDF:          TPdfDocumentVcl;
  i:            Integer;
  PageW, PageH: Integer;
  PdfAuthor,
  PdfSubject:   string;
begin
  Result := False;
  if fPageCount = 0 then Exit;
  try
    PDF := TPdfDocumentVcl.Create(fUseOutlines, 0, fExportPdfLevel);
    try
      // Resolve author/subject: use dedicated export fields when set,
      // otherwise fall back to the report-level Author/Subject properties.
      PdfAuthor  := fExportPdfAuthor;
      if PdfAuthor  = '' then PdfAuthor  := fAuthor;
      PdfSubject := fExportPdfSubject;
      if PdfSubject = '' then PdfSubject := fSubject;
      PDF.Info.Title   := SysUtils.Trim(fTitle);
      PDF.Info.Creator := SysUtils.Trim(Application.Title);
      PDF.Info.Author  := PdfAuthor;
      PDF.Info.Subject := PdfSubject;
      PDF.EmbeddedTTF  := fExportPdfEmbeddedTTF;
      PDF.StandardFontsReplace := fExportPdfStandardFonts;
      PDF.FileFormat   := fExportPdfFileFormat;
      if fExportPdfTagged then
      begin
        PDF.Tagged := true;
        if fExportPdfLanguage <> '' then
          PDF.DefaultLanguage := fExportPdfLanguage;
      end;
      PDF.SaveToStreamDirectBegin(aDest);
      for i := 0 to fPageCount - 1 do
      begin
        // PDF page size = FULL page in PDF points (including margins)
        // This must match the canvas size used in RenderPageToCanvas
        PDF.DefaultPageWidth  := MulDiv(fPages[i].PageWidth  + fPages[i].MarginLeft + fPages[i].MarginRight,  72, 2540);
        PDF.DefaultPageHeight := MulDiv(fPages[i].PageHeight + fPages[i].MarginTop  + fPages[i].MarginBottom, 72, 2540);
        PDF.AddPage;
        // Render page to PDF canvas with FULL page size (including per-page margins)
        PageW := MMToPixels(fPages[i].PageWidth  + fPages[i].MarginLeft + fPages[i].MarginRight,
          PDF.ScreenLogPixels);
        PageH := MMToPixels(fPages[i].PageHeight + fPages[i].MarginTop  + fPages[i].MarginBottom,
          PDF.ScreenLogPixels);
        if fExportPdfTagged then
          fActivePdfDoc := PDF
        else
          fActivePdfDoc := nil;
        RenderPageToCanvas(PDF.VclCanvas, i, PageW, PageH, PDF.ScreenLogPixels);
        fActivePdfDoc := nil;
        PDF.SaveToStreamDirectPageFlush;
      end;

      { Add PDF outlines/bookmarks from headings (if headings exist) }
      if fHeadingCount > 0 then
        AddHeadingsToOutline(PDF);

      PDF.SaveToStreamDirectEnd;
    finally
      PDF.Free;
    end;
    Result := True;
  except
    // swallow exception — caller checks Result
  end;
end;

procedure TGDIPages.ExportPDF(const FileName: string;
  Protect, Encrypt: Boolean; const ATitle, ACompany: string);
var
  FS: TFileStream;
begin
  // Transfer per-call title/company into the export properties so
  // ExportPdfStream picks them up through the unified code path.
  fTitle             := ATitle;
  fExportPdfSubject  := ACompany;
  FS := TFileStream.Create(FileName, fmCreate);
  try
    ExportPdfStream(FS);
  finally
    FS.Free;
  end;
end;

{$ENDIF FPC}

end.
