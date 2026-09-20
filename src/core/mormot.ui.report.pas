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
  mormot.core.text,     // ESynException
  mormot.core.unicode,
  mormot.pdf.types,     // PDF_FONT_STD_* + TPdfStructRole (Tagged PDF)
  mormot.ui.pdfcanvas;  // cross-platform PDF engine (uses FreeType2 on POSIX)
              // also re-exports TPdfFontMeasurer (layout metrics, ROADMAP B-5)
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
    dckBeginTR,       // begin table row (Color: 0 = data, 1 = header, 2 = repeated header) — for Tagged PDF structure
    dckEndTR,         // end table row — for Tagged PDF structure
    dckBeginList,     // begin list — for Tagged PDF structure (psrL)
    dckEndList,       // end list — for Tagged PDF structure
    dckBeginLI,       // begin list item — for Tagged PDF structure (psrLI)
    dckEndLI          // end list item — for Tagged PDF structure
  );

  /// style of an inline text run, mapped to a Tagged PDF Span element
  // - isPlain runs carry no semantics of their own: their marked content
  // belongs directly to the enclosing paragraph (ROADMAP B-3)
  TInlineStyle = (
    isPlain, isStrong, isEm, isCode, isLink);

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
    BlockId:     Integer;    // logical block: 0 = standalone, >0 = all lines of
                             // one wrapped paragraph share the id (Tagged PDF)
    IsInline:    boolean;    // true = inline run continuing the current line
    InlineStyle: TInlineStyle; // style of an inline run (Tagged PDF Span role)
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
    FooterFontName: string;                   // font name for the footer row
    FooterFontSize: Integer;                  // font size for the footer row (points)
    FooterFontStyle: TFontStyles;             // font style for the footer row
    FooterBkColor: TColor;                    // background color for the footer row
    // - leave all four Footer* fields at their default ('' / 0 / [] / 0) to
    // make DrawTableFooter look exactly like the header row
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
    fTableHeaderRepeat: boolean; // true while DrawTableRow repeats the header row
    // open THead/TBody/TFoot of the table being exported, psrTable = none:
    // a field, not a local of RenderPageToCanvas, because a table continues
    // across pages while its row group stays open (R-14)
    fRenderRowGroup:   TPdfStructRole;

    { --- List state (Tagged PDF L/LI grouping) --- }
    fInList:           boolean;       // true between dckBeginList and dckEndList
    fRecordingListItem: boolean;      // true while DrawListItem records its text

    { --- Phase 2: 1×1 bitmap for LCL text measurement (preview fallback) --- }
    fMeasureBitmap: TBitmap;

    { --- B-5: layout metrics taken from the PDF engine, not from the LCL --- }
    fMeasurer:        TPdfFontMeasurer;

    { --- saved state stack --- }
    fSavedStates:  array of TSavedState;
    fSavedCount:   Integer;

    { --- Phase 5: Format registry (Markdown-style) --- }
    fFormatRegistry: TFPGMap<string, TReportFormat>;  // H1..H6, Strong, Em, Code, etc.
    fHeadings:       array of THeadingInfo;  // stores heading metadata for PDF outlines
    fHeadingCount:   Integer;  // count of headings in fHeadings array
    fCurrentHeadingLevel: Integer;  // tracks current heading level for auto-spacing in EndHeading
    { --- logical blocks for Tagged PDF (one tag per paragraph, not per line) --- }
    fNextBlockId:      Integer;  // source of TDrawCommand.BlockId values
    fCurrentBlockId:   Integer;  // id stamped onto the commands emitted right now
    fRenderBlockId:    Integer;  // block whose struct element is currently reused
    fRenderBlockElem:  Integer;  // its index, for TPdfDocumentVcl.ResumeStructContent
    fRenderBlockOpen:  boolean;  // true while its marked-content region is open
    { --- inline runs sharing one visual line (Tagged PDF, ROADMAP B-3) --- }
    fInlineBlockId:    Integer;  // block id of the line being filled, 0 = none
    fEmitInline:       boolean;  // true while an inline overload emits
    fEmitInlineStyle:  TInlineStyle;  // style of the run being emitted
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
    /// emit dckEndList if a list is still open (no-op otherwise)
    procedure CloseOpenList;
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
    /// select the current font on fMeasurer; false = fall back to the LCL
    function  SetupPdfMeasureFont: boolean;
    /// advance width of S in PDF points, or -1 when the PDF metrics are absent
    function  MeasureTextWidthPt(const S: string): single;
    function  MeasureTextWidthPx(const S: string): Integer;
    function  LineHeightPx: Integer;
    function  LineHeightMM: Integer;
    function  MeasureTextWidthMM(const S: string): Integer;
    function  GetMeasureDPI: Integer;
    procedure RecordWrappedText(X: Integer; var Y: Integer;
                                const S: string; MaxWidthMM: Integer);
    procedure EmitTextCmd(X, Y: Integer; const S: string; Align: Integer);
    /// draw one fully styled table row - shared by DrawTableHeader/Footer
    // - ARowKind travels in dckBeginTR.Color: 1 = header, 2 = its repetition
    // on a continuation page (an artifact, B-11), 3 = footer
    procedure DrawTableStyledRow(const Cells: array of string;
      ARowKind: Integer; const AFontName: string; AFontSize: Integer;
      AFontStyle: TFontStyles; ABkColor: TColor);
    procedure InitializeFormatRegistry;
    procedure AddHeadingsToOutline(PDF: TPdfDocumentVcl);
    function  NormalizeX(X: Integer): Integer;
    function  NormalizeY(Y: Integer): Integer;
    /// 1/100mm -> render pixels, without the integer rounding of ScaleX/ScaleY
    function  ScaleXF(V: Integer): single;
    function  ScaleYF(V: Integer): single;
    /// draw text keeping sub-pixel precision when ACanvas is the PDF bridge
    procedure EmitCanvasText(ACanvas: TCanvas; X, Y: Integer;
                             const S: string);
    { Zentrale Skalierungsfunktionen - IMMER nutzen für Koordinaten-Umwandlung }
    function  ScaleX(V: Integer): Integer;  // Convert 1/100mm to render pixels
    function  ScaleY(V: Integer): Integer;  // Convert 1/100mm to render pixels
    procedure SetFontStyleProperty(Style: TFontStyles);
    procedure SetLineHeightFactor(Value: single);
    procedure SetMarginLeft(Value: Integer);
    procedure SetMarginRight(Value: Integer);
    procedure SetMarginTop(Value: Integer);
    procedure SetMarginBottom(Value: Integer);
    procedure SetExportPdfTagged(Value: boolean);
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
    /// advance Y cursor by mm millimetres
    // - for 1/100 mm units, the unit of every other coordinate, use
    // MoveToNextLine instead
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
    /// draw the closing row of a table, e.g. a totals line
    // - styled by the Footer* fields of TTableLayout, which default to the
    // header's look, so the footer is set apart from the data rows
    // - in a tagged export the row lands in a TFoot group instead of TBody
    // (ISO 32000-1 14.8.4.3.4), so assistive technology can tell it apart
    procedure DrawTableFooter(const Cells: array of string);
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
    // - PDF/UA needs embedded fonts, so setting this forces ExportPdfEmbeddedTTF
    // and clears ExportPdfStandardFonts
    // - those flags decide which metrics the layout is measured with, so this
    // has to be set before the first drawing command (ROADMAP P-6)
    property ExportPdfTagged: boolean read fExportPdfTagged write SetExportPdfTagged;
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

{ Convert PDF points (1/72 inch) to 1/100 mm — the unit of every TGDIPages
  coordinate. Kept as a single late rounding step, so sub-unit differences do
  not accumulate over the lines of a page (ROADMAP B-5). }
function PointsToMM100(Points: single): Integer;
begin
  Result := Round(Points * (2540 / 72));
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
  fMeasurer             := TPdfFontMeasurer.Create;
  // Phase 6 defaults
  fUseOutlines          := False;
  fExportPdfLevel       := pdfaNone;
  fExportPdfEmbeddedTTF := True;
  fExportPdfStandardFonts := True;
  fExportPdfFileFormat    := pdf13;
  fExportPdfTagged        := False;
  fRenderRowGroup         := psrTable; // no row group open
  fExportPdfLanguage      := 'en';

  // Phase 5: Initialize format registry with default Markdown-style formats
  fFormatRegistry := TFPGMap<string, TReportFormat>.Create;
  fHeadingCount := 0;
  SetLength(fHeadings, 0);
  fCurrentHeadingLevel := 0;
  fInParagraph := 0;
  fNextBlockId      := 0;
  fCurrentBlockId   := 0;
  fInlineBlockId    := 0;
  fEmitInline       := false;
  fEmitInlineStyle  := isPlain;
  fRenderBlockId    := 0;
  fRenderBlockElem  := -1;
  fRenderBlockOpen  := false;
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
  fMeasurer.Free;
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

procedure TGDIPages.CloseOpenList;
var
  Cmd: TDrawCommand;
begin
  if not fInList then
    exit;
  fInList := false; // reset first, so AddCommand does not recurse
  Cmd := Default(TDrawCommand);
  Cmd.Kind := dckEndList;
  AddCommand(Cmd);
end;

procedure TGDIPages.AddCommand(const Cmd: TDrawCommand);
var
  n: Integer;
begin
  if fCurrCmds = nil then
    raise Exception.Create('TGDIPages: call NewPage before drawing');
  { consecutive DrawListItem calls share one list: any other command ends it }
  if fInList and
     not fRecordingListItem and
     not (Cmd.Kind in [dckBeginList, dckEndList, dckBeginLI, dckEndLI]) then
    CloseOpenList;
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
  Phase 2 – Text measurement

  Layout is measured with the PDF font engine, not with the LCL: the glyphs are
  placed by TPdfCanvas later on, so measuring with a widgetset canvas made the
  two disagree — every advance was rounded to a whole screen pixel and each
  platform returned a different text height for the same nominal font
  (ROADMAP B-5). The LCL canvas remains as an explicit fallback for fonts the
  PDF engine cannot resolve, and for the on-screen preview.
  ========================================================================= }

procedure TGDIPages.SetupMeasureFont;
begin
  fMeasureBitmap.Canvas.Font.Name  := fFontName;
  fMeasureBitmap.Canvas.Font.Size  := fFontSize;
  fMeasureBitmap.Canvas.Font.Style := fFontStyle;
end;

function TGDIPages.SetupPdfMeasureFont: boolean;
begin
  if fMeasurer = nil then
    fMeasurer := TPdfFontMeasurer.Create;
  { the export flags decide which font the PDF will really use, so they decide
    which metrics the layout has to be measured with }
  Result := fMeasurer.SetFont(StringToUtf8(fFontName),
    fsBold in fFontStyle, fsItalic in fFontStyle, fExportPdfStandardFonts);
end;

function TGDIPages.MeasureTextWidthPt(const S: string): single;
begin
  if SetupPdfMeasureFont then
    Result := fMeasurer.TextWidth(StringToUtf8(S), fFontSize)
  else
    Result := -1; { no PDF metrics for this font — caller falls back to the LCL }
end;

function TGDIPages.MeasureTextWidthPx(const S: string): Integer;
begin
  SetupMeasureFont;
  Result := fMeasureBitmap.Canvas.TextWidth(S);
end;

function TGDIPages.LineHeightPx: Integer;
begin
  Result := MMToPixels(LineHeightMM, 96);
end;

procedure TGDIPages.SetLineHeightFactor(Value: single);
begin
  fLineHeightFactor   := Value;
  fCachedLineHeightPx := 0;
  fCachedLineHeightMM := 0;
end;

function TGDIPages.LineHeightMM: Integer;
begin
  { The per-line advance is FontSize x LineHeightFactor, expressed in PDF
    points. It used to be an LCL pixel text height times the factor, which
    absorbed the widgetset's own leading and quantised to whole screen pixels:
    11 pt text with LineHeightFactor=1.1 advanced by 16.5 pt on Linux and
    14.25 pt on macOS instead of 12.1 pt. Note that a face whose
    ascender+descender exceeds 1.1 em now needs a larger LineHeightFactor —
    this is the deliberate layout change of ROADMAP B-5. }
  Result := PointsToMM100(fFontSize * fLineHeightFactor);
end;

function TGDIPages.MeasureTextWidthMM(const S: string): Integer;
var
  Pt: single;
begin
  Pt := MeasureTextWidthPt(S);
  if Pt >= 0 then
    Result := PointsToMM100(Pt)
  else
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
  { close an open list on the page it started on, so L/LI never span pages }
  if not fRecordingListItem then
    CloseOpenList;
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
  fInlineBlockId := 0;
end;

procedure TGDIPages.EndDoc;
begin
  CloseOpenList;
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
  fInlineBlockId := 0;  { the inline run of the previous line is closed }
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

procedure TGDIPages.EmitCanvasText(ACanvas: TCanvas; X, Y: Integer;
  const S: string);
begin
  { TCanvas.TextOut takes integer pixels, which on PDF export snaps every
    position to the 0.75 pt (1 px @ 96 DPI) grid. The PDF bridge can do better,
    so place the text where the layout actually put it (ROADMAP B-5). The
    preview keeps the integer path — it draws on a pixel grid anyway. }
  if ACanvas is TPdfVclCanvas then
    TPdfVclCanvas(ACanvas).TextOutFrac(ScaleXF(X), ScaleYF(Y), S)
  else
    ACanvas.TextOut(ScaleX(X), ScaleY(Y), S);
end;

function TGDIPages.ScaleXF(V: Integer): single;
begin
  Result := V * fRenderScaleX + fRenderOffsetX;
end;

function TGDIPages.ScaleYF(V: Integer): single;
begin
  Result := V * fRenderScaleY + fRenderOffsetY;
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
  fEmitInlineStyle := isStrong;
  try
    DrawText(AText);
  finally
    fEmitInlineStyle := isPlain;
  end;
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
  fEmitInlineStyle := isEm;
  try
    DrawText(AText);
  finally
    fEmitInlineStyle := isPlain;
  end;
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
  fEmitInlineStyle := isCode;
  try
    DrawText(AText);
  finally
    fEmitInlineStyle := isPlain;
  end;
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
  fEmitInlineStyle := isLink;
  try
    DrawText(AText);
  finally
    fEmitInlineStyle := isPlain;
  end;
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
  Cmd: TDrawCommand;
begin
  SaveLayout;
  Format := GetFormat('LI');
  SetFont(Format.FontName, Format.FontSize);
  FontStyle := Format.FontStyle;
  TextColor := Format.Color;
  if Format.SpaceBefore > 0 then
    MoveToNextLine(Format.SpaceBefore);
  { Tagged PDF: consecutive items share one psrL, each item gets its own psrLI.
    The bullet stays inside the item text, so the rendering is unchanged and
    the item is tagged as psrLBody — psrLbl would need a separate TextOut. }
  if not fInList then
  begin
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckBeginList;
    AddCommand(Cmd);
    fInList := true;
  end;
  fRecordingListItem := true;
  try
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckBeginLI;
    AddCommand(Cmd);
    DrawText(X, Y, APrefix + AText);
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckEndLI;
    AddCommand(Cmd);
  finally
    fRecordingListItem := false;
  end;
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
  Cmd.BlockId      := fCurrentBlockId;
  Cmd.IsInline     := fEmitInline;
  Cmd.InlineStyle  := fEmitInlineStyle;
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
  PrevBlockId: Integer;
begin
  { Check if line fits on current page, otherwise move to next page }
  LineH := LineHeightMM;
  if fCurrentY + LineH > fPageHeight then
  begin
    NewPage;
    fCurrentX := 0;
  end;

  { All runs of one visual line share a BlockId, so the tagged PDF export
    produces a single P with the styled runs as Span kids (ROADMAP B-3) }
  if fInlineBlockId = 0 then
  begin
    Inc(fNextBlockId);
    fInlineBlockId := fNextBlockId;
  end;
  PrevBlockId := fCurrentBlockId;
  fCurrentBlockId := fInlineBlockId;
  fEmitInline := true;
  try
    { Draw text at current position and advance X }
    EmitTextCmd(fCurrentX, fCurrentY, S, 0);
  finally
    fEmitInline := false;
    fCurrentBlockId := PrevBlockId;
  end;

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
  MaxPt:  single;
  SpaceW: single;
  LH:     Integer;
  Words:  TStringList;
  Line:   string;
  LineW:  single;
  WordW:  single;
  i:      Integer;
  PrevBlockId: Integer;
begin
  { All lines emitted below belong to one logical paragraph: they share a
    BlockId, so the tagged PDF export produces a single P (ROADMAP B-2). }
  PrevBlockId := fCurrentBlockId;
  Inc(fNextBlockId);
  fCurrentBlockId := fNextBlockId;
  fInlineBlockId := 0;  { a block-level paragraph ends any open inline line }
  { Break lines in PDF points — the unit the glyphs are actually placed in.
    Widths are accumulated unrounded and only the emitted Y is converted to
    1/100 mm, so no per-word rounding error can add up over a paragraph. }
  MaxPt  := MaxWidthMM * (72 / 2540);
  LH     := LineHeightMM;
  SpaceW := MeasureTextWidthPt(' ');
  if SpaceW < 0 then
  begin
    { no PDF metrics for this font: fall back to the LCL measurement path,
      normalized to 96 DPI as before }
    SetupMeasureFont;
    SpaceW := PixelsToMM(fMeasureBitmap.Canvas.TextWidth(' '),
                GetMeasureDPI) * (72 / 2540);
  end;

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
      WordW := MeasureTextWidthPt(Words[i]);
      if WordW < 0 then
        WordW := PixelsToMM(fMeasureBitmap.Canvas.TextWidth(Words[i]),
                   GetMeasureDPI) * (72 / 2540);
      if (LineW > 0) and (LineW + SpaceW + WordW > MaxPt) then
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
        LineW := LineW + SpaceW + WordW;
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
    fCurrentBlockId := PrevBlockId;
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
  { fCurrentY is in 1/100 mm, so mm millimetres are mm * 100 units. This used
    to run the value through MMToPixels, converting an already-correct 1/100 mm
    figure into pixels: AddVerticalSpace(5) advanced by 18 units, not 500. }
  Inc(fCurrentY, mm * 100);
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

procedure TGDIPages.DrawTableStyledRow(const Cells: array of string;
  ARowKind: Integer; const AFontName: string; AFontSize: Integer;
  AFontStyle: TFontStyles; ABkColor: TColor);
var
  i: Integer;
  Cmd: TDrawCommand;
  TRCmd: TDrawCommand;
  CellX, CellWidth, CellY: Integer;
  AlignValue: Integer;
  CellHeight: Integer;
begin
  TRCmd := Default(TDrawCommand);
  TRCmd.Kind  := dckBeginTR;
  TRCmd.Color := ARowKind;
  AddCommand(TRCmd);
  SaveLayout;
  { Use table layout fonts if specified, otherwise use current document font }
  if AFontName <> '' then
    SetFont(AFontName, AFontSize)
  else
    { Keep current font name/size, only change style }
    fFontStyle := AFontStyle;
  fTextColor := clBlack;

  { Cell height includes padding above and small padding below text }
  CellHeight := LineHeightMM + CELL_PADDING;

  { Draw header cells }
  CellX := 0;
  for i := 0 to Min(High(Cells), High(fTableColWidths)) do
  begin
    CellWidth := fTableColWidths[i];

    { Fill header background }
    Cmd := Default(TDrawCommand);
    Cmd.Kind := dckFillRect;
    Cmd.X := NormalizeX(CellX);
    Cmd.Y := NormalizeY(fCurrentY);
    Cmd.X2 := NormalizeX(CellX + CellWidth);
    Cmd.Y2 := NormalizeY(fCurrentY + CellHeight);
    Cmd.Color := ABkColor;
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
        EmitTextCmd(NormalizeX(CellX + CellWidth - CELL_PADDING - MeasureTextWidthMM(Cells[i])), NormalizeY(CellY), Cells[i], 0);
      2: { Center: use middle of cell }
        EmitTextCmd(NormalizeX(CellX + CellWidth div 2), NormalizeY(CellY), Cells[i], AlignValue);
    else
      { Left: normal left-aligned }
      EmitTextCmd(NormalizeX(CellX + CELL_PADDING), NormalizeY(CellY), Cells[i], AlignValue);
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


procedure TGDIPages.DrawTableHeader(const Headers: array of string);
var
  i: Integer;
  kind: Integer;
begin
  if not fTableInProgress then
    raise Exception.Create('DrawTableHeader: BeginTable not called');

  // Save header content for automatic repetition on continuation pages
  SetLength(fTableSavedHeaders, Length(Headers));
  for i := 0 to High(Headers) do
    fTableSavedHeaders[i] := Headers[i];

  { 1 = header row, 2 = its repetition on a continuation page, which the
    tagged export marks as an artifact instead of tagging it again (B-11) }
  if fTableHeaderRepeat then
    kind := 2
  else
    kind := 1;
  DrawTableStyledRow(Headers, kind, fTableLayout.HeaderFontName,
    fTableLayout.HeaderFontSize, fTableLayout.HeaderFontStyle,
    fTableLayout.HeaderBkColor);
end;

procedure TGDIPages.DrawTableFooter(const Cells: array of string);
var
  nam: string;
  siz: Integer;
  sty: TFontStyles;
  bk: TColor;
  RowHeight: Integer;
begin
  if not fTableInProgress then
    raise Exception.Create('DrawTableFooter: BeginTable not called');

  { an unset Footer* set means "look like the header row" }
  nam := fTableLayout.FooterFontName;
  siz := fTableLayout.FooterFontSize;
  sty := fTableLayout.FooterFontStyle;
  bk  := fTableLayout.FooterBkColor;
  if (nam = '') and
     (siz = 0) and
     (sty = []) and
     (bk = 0) then
  begin
    nam := fTableLayout.HeaderFontName;
    siz := fTableLayout.HeaderFontSize;
    sty := fTableLayout.HeaderFontStyle;
    bk  := fTableLayout.HeaderBkColor;
  end;

  { never leave the footer alone on a page without its table: break first,
    repeating the column headers like DrawTableRow does }
  RowHeight := LineHeightMM + CELL_PADDING;
  if fCurrentY + RowHeight > fPageHeight then
  begin
    ForceNewPage;
    if Length(fTableSavedHeaders) > 0 then
    begin
      fTableHeaderRepeat := true;
      try
        DrawTableHeader(fTableSavedHeaders);
      finally
        fTableHeaderRepeat := false;
      end;
    end;
  end;

  DrawTableStyledRow(Cells, 3, nam, siz, sty, bk);
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
    begin
      fTableHeaderRepeat := true;
      try
        DrawTableHeader(fTableSavedHeaders);
      finally
        fTableHeaderRepeat := false;
      end;
    end;
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
  InListItem:     boolean;        // true between dckBeginLI and dckEndLI
  SpanOpen:       boolean;        // true while a Span wraps the current run
  ArtifactDoc:    TPdfDocumentVcl; // fActivePdfDoc, set aside in an artifact row


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

  { close the marked-content region of the logical block being rendered
    - AKeepBlock=true at a page boundary: the block may continue on the next
      page and is then reopened by ResumeStructContent }
  procedure CloseRenderBlock(AKeepBlock: boolean);
  begin
    if not fRenderBlockOpen then
      exit;
    if fActivePdfDoc <> nil then
      fActivePdfDoc.EndStructContent;
    fRenderBlockOpen := false;
    if not AKeepBlock then
    begin
      fRenderBlockId   := 0;
      fRenderBlockElem := -1;
    end;
  end;

  { role of the struct element matching the current dckDrawText command }
  function TextStructRole: TPdfStructRole;
  begin
    if Cmd.HeadingLevel > 0 then
      result := TPdfStructRole(Cmd.HeadingLevel)
    else if InTableRow then
      if InHeaderRow then
        result := psrTH
      else
        result := psrTD
    else if InListItem then
      result := psrLBody
    else
      result := psrP;
  end;

  { the row group a dckBeginTR belongs to, by its Color: 1 header, 3 footer }
  function RowGroupOf(ARowKind: Integer): TPdfStructRole;
  begin
    case ARowKind of
      1: result := psrTHead;
      3: result := psrTFoot;
    else
      result := psrTBody;
    end;
  end;

  { make ARole the open row group, closing the previous one if it differs }
  procedure OpenRowGroup(ARole: TPdfStructRole);
  begin
    if fRenderRowGroup = ARole then
      exit;
    if fRenderRowGroup <> psrTable then
      fActivePdfDoc.EndStructContent;
    fActivePdfDoc.BeginStructContent(ARole);
    fRenderRowGroup := ARole;
  end;

  { open the struct element matching the current dckDrawText command
    - an inline line opens it without a region: every run of the line adds
      its own, so plain runs and Span kids stay in reading order (B-3) }
  procedure BeginTextStructContent;
  begin
    if Cmd.IsInline then
      fActivePdfDoc.BeginStructGroup(TextStructRole)
    else
      fActivePdfDoc.BeginStructContent(TextStructRole);
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
  InListItem  := false;
  SpanOpen    := false;
  ArtifactDoc := nil;
  { preview and printing do not tag: never carry block state into them }
  if fActivePdfDoc = nil then
  begin
    fRenderBlockId   := 0;
    fRenderBlockElem := -1;
  end;
  fRenderBlockOpen := false;

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
    { a running header is pagination, not content (PDF/UA) }
    if fActivePdfDoc <> nil then
      fActivePdfDoc.BeginArtifact;
    ACanvas.TextOut(fRenderOffsetX, (fRenderOffsetY - ACanvas.TextHeight(HeaderText)) div 2, HeaderText);
    if fActivePdfDoc <> nil then
      fActivePdfDoc.EndArtifact;
  end;

  for i := 0 to High(Page.Commands) do
  begin
    Cmd := Page.Commands[i];
    { anything but text ends the logical block that is currently open }
    if Cmd.Kind <> dckDrawText then
      CloseRenderBlock(false);
    case Cmd.Kind of
      dckDrawText:
      begin
        if fActivePdfDoc <> nil then
          if (Cmd.BlockId <> 0) and
             (Cmd.BlockId = fRenderBlockId) then
          begin
            { same paragraph as the previous command }
            if not fRenderBlockOpen then
            begin
              { continued after a page break: reopen the very same element,
                which then owns MCIDs on both pages }
              fActivePdfDoc.ResumeStructContent(fRenderBlockElem,
                not Cmd.IsInline);
              fRenderBlockOpen := true;
            end;
            { else the region is still open — emit the line only }
          end
          else
          begin
            CloseRenderBlock(false);
            BeginTextStructContent;
            if Cmd.BlockId <> 0 then
            begin
              { keep the element open for the next line of this paragraph }
              fRenderBlockId   := Cmd.BlockId;
              fRenderBlockElem := fActivePdfDoc.LastStructContent;
              fRenderBlockOpen := fRenderBlockElem >= 0;
            end;
          end;
        { a styled inline run becomes a Span kid of the enclosing paragraph,
          a plain run one more region of the paragraph itself — both are
          listed in /K in reading order (ROADMAP B-3) }
        SpanOpen := (fActivePdfDoc <> nil) and
                    Cmd.IsInline and
                    fRenderBlockOpen and
                    (Cmd.InlineStyle <> isPlain);
        if SpanOpen then
        begin
          fActivePdfDoc.SuspendStructContent;
          fActivePdfDoc.BeginStructContent(psrSpan);
        end
        else if (fActivePdfDoc <> nil) and
                Cmd.IsInline and
                fRenderBlockOpen then
          fActivePdfDoc.ContinueStructContent;
        ApplyFont;
        ACanvas.Brush.Style := bsClear;
        { X position is pre-adjusted at recording time:
          - For right align: X has text width subtracted
          - For center align: X has half text width subtracted
          - For left align: X is unchanged
          - Just render at the adjusted X position }
        EmitCanvasText(ACanvas, Cmd.X, Cmd.Y,
          SubstitutePlaceholders(Cmd.Text, PageIndex));
        if SpanOpen then
          fActivePdfDoc.EndStructContent;
        if (fActivePdfDoc <> nil) and
           not fRenderBlockOpen then
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
        EmitCanvasText(ACanvas, Cmd.X, Cmd.Y,
          SubstitutePlaceholders(Cmd.HeadingTitle, PageIndex));
        if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
      end;
      dckBeginTable:
        if fActivePdfDoc <> nil then
        begin
          fActivePdfDoc.BeginStructContent(psrTable);
          fRenderRowGroup := psrTable; // = no row group open yet
        end;
      dckEndTable:
      begin
        if fActivePdfDoc <> nil then
        begin
          if fRenderRowGroup <> psrTable then
          begin
            fActivePdfDoc.EndStructContent; // close THead/TBody/TFoot
            fRenderRowGroup := psrTable;
          end;
          fActivePdfDoc.EndStructContent;   // close Table
        end;
        InTableRow  := false;
        InHeaderRow := false;
      end;
      dckBeginTR:
      begin
        { only rows 1 and 2 hold header cells; 3 is the footer, whose cells
          are TD like any data cell }
        InHeaderRow := Cmd.Color in [1, 2];
        InTableRow  := true;
        if fActivePdfDoc <> nil then
          if Cmd.Color = 2 then
          begin
            { a repeated header row is tagged once, on the first page: here it
              is an artifact, and without fActivePdfDoc its cells open no
              struct element }
            fActivePdfDoc.BeginArtifact;
            ArtifactDoc   := fActivePdfDoc;
            fActivePdfDoc := nil;
          end
          else
          begin
            { rows live in a THead/TBody/TFoot group (ISO 32000-1 14.8.4.3.4):
              open the one this row belongs to, closing the previous group.
              A repeated header (Color = 2) is an artifact and is handled
              above, so it never interrupts the open TBody (R-14) }
            OpenRowGroup(RowGroupOf(Cmd.Color));
            fActivePdfDoc.BeginStructContent(psrTR);
          end;
      end;
      dckEndTR:
      begin
        if ArtifactDoc <> nil then
        begin
          fActivePdfDoc := ArtifactDoc;
          ArtifactDoc   := nil;
          fActivePdfDoc.EndArtifact;
        end
        else if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
        InTableRow  := false;
        InHeaderRow := false;
      end;
      dckBeginList:
        if fActivePdfDoc <> nil then
          fActivePdfDoc.BeginStructContent(psrL);
      dckEndList:
        if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
      dckBeginLI:
      begin
        InListItem := true;
        if fActivePdfDoc <> nil then
          fActivePdfDoc.BeginStructContent(psrLI);
      end;
      dckEndLI:
      begin
        if fActivePdfDoc <> nil then
          fActivePdfDoc.EndStructContent;
        InListItem := false;
      end;
    end;
  end;

  { a block still open at the end of the page may continue on the next one:
    BDC/EMC must stay balanced inside each content stream }
  CloseRenderBlock(true);

  { Render footer if set }
  if fFooterText <> '' then
  begin
    FooterText := SubstitutePlaceholders(fFooterText, PageIndex);
    ACanvas.Font.Name  := fFontName;
    ACanvas.Font.Size  := Round(fFontSize * FontScale);
    ACanvas.Font.Style := fFontStyle;
    ACanvas.Font.Color := fTextColor;
    ACanvas.Brush.Style := bsClear;
    if fActivePdfDoc <> nil then
      fActivePdfDoc.BeginArtifact;
    ACanvas.TextOut(fRenderOffsetX,
      ScaleY(Page.PageHeight) +
      (DestHeight - ScaleY(Page.PageHeight) - ACanvas.TextHeight(FooterText)) div 2,
      FooterText);
    if fActivePdfDoc <> nil then
      fActivePdfDoc.EndArtifact;
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

procedure TGDIPages.SetExportPdfTagged(Value: boolean);
begin
  if Value = fExportPdfTagged then
    exit;
  { the export font flags feed SetupPdfMeasureFont, i.e. they decide how the
    recorded pages were broken into lines - switching them afterwards would set
    the text with a face it was not measured with (ROADMAP B-5 / P-6) }
  if Value and
     (fPageCount > 0) then
    raise ESynException.Create('TGDIPages.ExportPdfTagged must be set before ' +
      'the first page is drawn: it selects the fonts the layout is measured with');
  fExportPdfTagged := Value;
  if not Value then
    exit;
  // PDF/UA forbids the non-embedded base-14 Type1 faces
  fExportPdfEmbeddedTTF := true;
  fExportPdfStandardFonts := false;
end;

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
      { PDF/UA needs a title (dc:title, DisplayDocTitle): without one, the
        first H1 names the document (ROADMAP B-10) }
      if fExportPdfTagged and
         (PDF.Info.Title = '') then
        for i := 0 to fHeadingCount - 1 do
          if fHeadings[i].Level = 1 then
          begin
            PDF.Info.Title := SysUtils.Trim(fHeadings[i].Title);
            break;
          end;
      PDF.Info.Creator := SysUtils.Trim(Application.Title);
      PDF.Info.Author  := PdfAuthor;
      PDF.Info.Subject := PdfSubject;
      PDF.FileFormat   := fExportPdfFileFormat;
      { Tagged first: TPdfDocument.SetTagged picks the PDF/UA font mode, and
        SetExportPdfTagged has already aligned our own flags with it }
      if fExportPdfTagged then
      begin
        PDF.Tagged := true;
        if fExportPdfLanguage <> '' then
          PDF.DefaultLanguage := fExportPdfLanguage;
      end;
      PDF.EmbeddedTTF  := fExportPdfEmbeddedTTF;
      PDF.StandardFontsReplace := fExportPdfStandardFonts;
      PDF.SaveToStreamDirectBegin(aDest);
      { logical block state is per export run (see ROADMAP B-2) }
      fRenderBlockId   := 0;
      fRenderBlockElem := -1;
      fRenderBlockOpen := false;
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
