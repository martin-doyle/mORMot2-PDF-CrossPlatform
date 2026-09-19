# PDF Engine — TPdfDocument / TPdfDocumentVcl

Source: `src/core/mormot.ui.pdf.pas`, canvas bridge: `src/core/mormot.ui.pdfcanvas.pas`
FPImage adapter: `src/core/mormot.pdf.fpimage.pas`

## Two Entry Points

| Class | Coordinates | Dependency | When to use |
|---|---|---|---|
| `TPdfDocument` | PDF points (72 DPI), Y=0 bottom | mORMot2-Core only | Server/CLI, no LCL required |
| `TPdfDocumentVcl` | pixels (96 DPI), Y=0 top | + LCL | TCanvas-compatible code, GUI apps |

`TPdfDocumentGdi` (Windows-only, Delphi) uses EMF/GDI — not ported.

---

## Enums Reference

```pascal
// PDF/A conformance level
TPdfALevel = (pdfaNone, pdfa1A, pdfa1B, pdfa2A, pdfa2B, pdfa3A, pdfa3B);

// PDF file format version (defined in mormot.pdf.types — available to all units)
TPdfFileFormat = (pdf13, pdf14, pdf15, pdf16, pdf17);

// How the document appears when opened in a viewer
TPdfPageMode = (pmUseNone, pmUseOutlines, pmUseThumbs, pmFullScreen);

// Page layout used when document is opened
TPdfPageLayout = (plSinglePage, plOneColumn, plTwoColumnLeft, plTwoColumnRight);

// Viewer UI preferences
TPdfViewerPreference = (vpHideToolbar, vpHideMenubar, vpHideWindowUI,
                        vpFitWindow, vpCenterWindow, vpEnforcePrintScaling,
                        vpDisplayDocTitle);  // set by Tagged (PDF/UA-1 7.1)
TPdfViewerPreferences = set of TPdfViewerPreference;

// Available paper sizes
TPdfPaperSize = (psA4, psA5, psA3, psA2, psA1, psA0,
                 psLetter, psLegal, psUserDefined);

// Stream compression
TPdfCompressionMethod = (cmNone, cmFlateDecode);

// Text rendering — fill, stroke, clipping modes
TTextRenderingMode = (trFill, trStroke, trFillThenStroke, trInvisible,
                      trFillClipping, trStrokeClipping,
                      trFillStrokeClipping, trClipping);

// Annotation type
TPdfAnnotationSubType = (asTextNotes, asLink);

// Annotation border style
TPdfAnnotationBorder = (abSolid, abDashed, abBeveled, abInset, abUnderline);

// Destination type for bookmarks/links
TPdfDestinationType = (dtXYZ, dtFit, dtFitH, dtFitV,
                       dtFitR, dtFitB, dtFitBH, dtFitBV);

// Open/closed path cap shape
TLineCapStyle = (lcButt_End, lcRound_End, lcProjectingSquareEnd);

// Path corner shape
TLineJoinStyle = (ljMiterJoin, ljRoundJoin, ljBevelJoin);

// Encryption level (compile-time flag USE_PDFSECURITY required)
// elAES_128: AES-128-CBC, PDF 1.6, Standard Security Handler R=4
// elAES_256: defined but not yet implemented (returns nil from TPdfEncryption.New)
TPdfEncryptionLevel = (elNone, elRC4_40, elRC4_128, elAES_128, elAES_256);

// Encryption permission bits
TPdfEncryptionPermission = (epPrinting, epGeneralEditing, epContentCopy,
  epAuthoringComment, epFillingForms, epContentExtraction,
  epDocumentAssembly, epPrintingHighResolution);
TPdfEncryptionPermissions = set of TPdfEncryptionPermission;
```

Predefined permission sets (compile-time `USE_PDFSECURITY`):

```pascal
PDF_PERMISSION_ALL            // all permissions granted
PDF_PERMISSION_NOMODIF        // no modification or annotation
PDF_PERSMISSION_NOPRINT       // no printing
PDF_PERMISSION_NOCOPY         // no content copy
PDF_PERMISSION_NOCOPYNORPRINT // no copy and no print
```

---

## TPdfDocument — Direct PDF API

```pascal
uses mormot.ui.pdf;

Doc := TPdfDocument.Create;
Doc.DefaultPaperSize := psA4;     // psA4, psLetter, psA3, psA5, ...
Doc.EmbeddedTtf := False;          // True = embed full TTF
Doc.StandardFontsReplace := True;  // True = Helvetica/Times/Courier as Type1
Doc.PdfA := pdfA1B;               // pdfNone, pdfA1A, pdfA1B, pdfA2A, pdfA2B, pdfA3A, pdfA3B
Doc.NewDoc;
Page := Doc.AddPage;               // returns TPdfPage
C := Doc.Canvas;                   // TPdfCanvas (same per page)
C.SetFont('Helvetica', 12, []);
C.TextOut(72, 750, 'Hello');       // X,Y in points from bottom-left
Doc.SaveToFile('out.pdf');
Doc.Free;
```

### Key Properties

| Property | Type | Description |
|---|---|---|
| `Canvas` | `TPdfCanvas` | Draw on current page |
| `Info` | `TPdfInfo` | Document metadata |
| `EmbeddedTtf` | boolean | True = embed TrueType fonts (full TTF) |
| `EmbeddedTtfIgnore` | `TRawUtf8List` | Font names to exclude from embedding |
| `StandardFontsReplace` | boolean | True = Type1 fallback for Helvetica/Times/Courier |
| `DefaultPaperSize` | `TPdfPaperSize` | psA4, psLetter, etc. |
| `DefaultPageWidth` | cardinal | Page width in PDF points (overrides PaperSize) |
| `DefaultPageHeight` | cardinal | Page height in PDF points |
| `DefaultPageLandscape` | boolean | Landscape orientation |
| `PdfA` | `TPdfALevel` | PDF/A conformance level |
| `CompressionMethod` | `TPdfCompressionMethod` | cmNone or cmFlateDecode |
| `OutlineRoot` | `TPdfOutlineRoot` | Bookmarks root |
| `PageLayout` | `TPdfPageLayout` | Initial page layout in viewer |
| `PageMode` | `TPdfPageMode` | Initial display mode (outline panel, etc.) |
| `NonFullScreenPageMode` | `TPdfPageMode` | Mode after leaving full-screen |
| `ViewerPreference` | `TPdfViewerPreferences` | Viewer UI flags |
| `UseOptionalContent` | boolean | Enable PDF optional content (layers) |
| `FontFallBackName` | string | Font used when requested font not found |
| `FileFormat` | `TPdfFileFormat` | PDF version header: `pdf13`..`pdf17` (default `pdf13`); PDF/A and Tagged auto-raise this |
| `GeneratePdf15File` | boolean | Compatibility alias: `true` = `pdf15`, `false` leaves `FileFormat` unchanged |
| `Tagged` | boolean | Enable Tagged PDF (ISO 32000-1 §14); setting `true` auto-raises `FileFormat` to `pdf17` |
| `UseUniscribe` | boolean | Use Uniscribe for text shaping (Windows only) |

### Methods

```pascal
Doc.NewDoc                                 // initialise (call before AddPage)
Doc.AddPage                                // new page; Canvas switches automatically
Doc.SaveToFile('out.pdf')                  // save to file; returns false on error
Doc.SaveToStream(Stream)                   // save to stream
Doc.SaveToStream(Stream, ForceModDate)     // save with explicit modification date

// Bookmarks
Doc.CreateBookMark(TopY, 'name')           // Y in PDF points from top
Doc.CreateOutline(Title, Level, YTop)      // Level 1=H1, 2=H2 etc.

// Links & annotations
Doc.CreateLink(Rect, 'bookmark')           // internal link
Doc.CreateHyperLink(Rect, 'http://', ...)  // external link
Doc.CreateAnnotation(Type, Rect, Border)   // free annotation

// Images
Doc.CreateOrGetImage(Bitmap, ...)          // embed image, deduplicated; returns XObject name
Doc.AddTrueTypeFont('Calibri')             // pre-register font explicitly; returns true on success

// Optional content (layers)
Doc.CreateOptionalContentGroup(Parent, Name)
Doc.CreateOptionalContentRadioGroup(Groups)

// File attachments
Doc.CreateFileAttachment(FileName, Name, Description, Relationship)
Doc.CreateFileAttachmentFrom(Buffer, Name, MimeType, Description, Relationship)

// Streaming — page-by-page output to large streams without full buffering
Doc.SaveToStreamDirectBegin(Stream, ForceModDate)
Doc.SaveToStreamDirectPageFlush(FlushCurrentPageNow)
Doc.SaveToStreamDirectEnd
```

---

## TPdfPage

Retrieved via `Doc.AddPage` or indexed in `Doc.RawPages[]`.

```pascal
Page := Doc.AddPage;
Page.PageWidth  := 595;   // override page width in PDF points
Page.PageHeight := 842;   // override page height
Page.PageLandscape := True;

// Measure text using current font:
W := Page.TextWidth('Hello');       // returns single (PDF points)
N := Page.MeasureText('Long text', MaxWidth); // number of chars fitting in MaxWidth
```

| Property | Type | Description |
|---|---|---|
| `PageWidth` | integer | Page width in PDF points |
| `PageHeight` | integer | Page height in PDF points |
| `PageLandscape` | boolean | True = landscape (swaps W and H) |

---

## TPdfInfo — Document Metadata

```pascal
Doc.Info.Title    := 'Annual Report';
Doc.Info.Author   := 'Acme Corp';
Doc.Info.Subject  := 'Finance';
Doc.Info.Keywords := 'report, finance';
Doc.Info.Creator  := 'MyApp 1.0';
// Producer is set automatically
Doc.Info.CreationDate := Now;
Doc.Info.ModDate      := Now;
```

All properties are `string` (read/write). `Producer` is set automatically by the engine.

---

## TPdfCanvas — Drawing Commands

Coordinates: PDF points, X=0 left, Y=0 bottom.

### Text

```pascal
C.SetFont('Times', 14, [pfsBold]);   // set font; returns TPdfFont
C.TextOut(X, Y, 'Text');             // output text at position
C.TextOutW(X, Y, PW);                // Unicode (PWideChar)
C.TextRect(Rect, 'Text', Align, ...); // text within a rectangle
C.MultilineTextRect(Rect, 'Text', Align, ...); // multiline word-wrap in rect

// Advanced text positioning:
C.BeginText;
C.MoveTextPoint(tx, ty);
C.SetTextMatrix(a, b, c, d, x, y);
C.MoveToNextLine;
C.ShowText('Line', NextLine);
C.EndText;
```

### Text Style

```pascal
C.SetCharSpace(value: single);       // inter-character spacing
C.SetWordSpace(value: single);       // inter-word spacing
C.SetHorizontalScaling(value: single); // 100 = normal
C.SetLeading(value: single);         // line spacing
C.SetTextRenderingMode(trFill);      // fill/stroke/clip modes (TTextRenderingMode)
C.SetTextRise(rise: word);           // superscript/subscript offset
```

### Colours

```pascal
C.SetRGBFillColor(TPdfColor);        // fill colour (TColor / COLORREF)
C.SetRGBStrokeColor(TPdfColor);      // stroke colour
C.SetCMYKFillColor(C, M, Y, K);     // CMYK fill (0–100 each)
C.SetCMYKStrokeColor(C, M, Y, K);   // CMYK stroke
```

### Transparency (R-7)

```pascal
C.SetFillAlpha(0.5);    // fill opacity: 0.0=transparent, 1.0=opaque
C.SetStrokeAlpha(0.8);  // stroke opacity
```

Both methods lazily create a named `ExtGState` entry in the page's `/Resources` dictionary and emit a `/gsNNN gs` operator. Minimum PDF version for transparency is PDF 1.4 (`pdf14`). Names are deduplicated per page (same value → same name, no duplicate dict entries).

### Paths & Shapes

```pascal
C.MoveTo(x, y: single);
C.LineTo(x, y: single);
C.CurveToC(x1, y1, x2, y2, x3, y3); // cubic Bézier (full control points)
C.CurveToV(x2, y2, x3, y3);          // Bézier with first CP = current point
C.CurveToY(x1, y1, x3, y3);          // Bézier with last CP = end point
C.Rectangle(x, y, w, h: single);
C.Ellipse(x, y, w, h: single);
C.RoundRect(x1, y1, x2, y2, cx, cy: single);
C.Closepath;
C.NewPath;                            // discard current path without drawing
```

### Path Rendering

```pascal
C.Stroke;                    // stroke only
C.Fill;                      // fill only (nonzero winding)
C.Eofill;                    // fill only (even-odd rule)
C.FillStroke;
C.ClosepathFillStroke;
C.EofillStroke;
C.ClosepathEofillStroke;
C.Clip;                      // use current path as clip region (nonzero)
C.Eoclip;                    // even-odd clip
```

### Stroke Attributes

```pascal
C.SetLineWidth(w: single);
C.SetLineCap(lcButt_End);     // TLineCapStyle
C.SetLineJoin(ljMiterJoin);   // TLineJoinStyle
C.SetMiterLimit(m: single);
C.SetDash([4, 2], phase: integer); // dash pattern (empty array = solid)
C.SetFlat(flatness: byte);    // curve flatness tolerance
```

### Graphics State

```pascal
C.GSave;     // save current graphics state (CTM, colour, clip)
C.GRestore;  // restore last saved state
C.ConcatToCTM(a, b, c, d, e, f: single); // multiply current transform matrix
```

### XObjects (Images & Forms)

```pascal
// Embed and draw an image registered with Doc.CreateOrGetImage:
C.DrawXObject(X, Y, Width, Height, 'ImageName');
C.DrawXObjectEx(X, Y, Width, Height, 'ImageName', ClipRect, Angle);
C.ExecuteXObject('ImageName');  // raw Do operator
```

### Optional Content (Layers)

```pascal
C.BeginMarkedContent(Group: TPdfOptionalContentGroup);
// ... drawing commands visible only when group is on ...
C.EndMarkedContent;
```

### Integer / Scaled Overloads

Integer overloads (`I` suffix) accept TRect/TPoint coordinates in PDF-point integers.
Scaled overloads (`S` suffix) accept single values mapped via `ViewOffsetX/Y`.

```pascal
C.MoveToI(x, y: integer);
C.LineToI(x, y: integer);
C.RoundRectI(x1, y1, x2, y2, cx, cy: integer);
C.ArcI(cx, cy, W, H, Sx, Sy, Ex, Ey: integer; ArcType: TPdfCanvasArcType);
W := C.BoxI(Rect, Normalize);   // TRect -> TPdfBox
R := C.RectI(Rect, Normalize);  // TRect -> TPdfRect
```

### Text Metrics

```pascal
W := C.TextWidth('Hello');             // width in PDF points
W := C.UnicodeTextWidth(PW);           // Unicode version
N := C.MeasureText('Long', MaxWidth);  // chars fitting within MaxWidth
```

---

## TPdfDocumentVcl — TCanvas-Compatible Wrapper

```pascal
uses mormot.ui.pdf, mormot.ui.pdfcanvas;

Doc := TPdfDocumentVcl.Create;
Doc.DefaultPaperSize := psA4;
Doc.EmbeddedTTF := False;
Doc.StandardFontsReplace := True;
Doc.AddPage;
C := Doc.VclCanvas;      // TCanvas — coordinates in pixels, Y=0 top
C.Font.Name := 'Helvetica';
C.Font.Size := 12;
C.TextOut(40, 40, 'Text');
Doc.SaveToFile('out.pdf');
```

`VclCanvas` must be retrieved after each `AddPage` — a new instance is created per page.

### Text Metrics (ROADMAP B-4)

`TextWidth`/`TextHeight`/`TextExtent` are overridden: they measure with
`TPdfFontMeasurer`, i.e. the face and widths the PDF will really use, and no
longer with the widgetset's own resolution of `Font.Name`. They still return
`integer` pixels, so a caller that needs the exact value takes the `single`
overloads and draws with `RectangleFrac`:

```pascal
VC := Doc.VclCanvas as TPdfVclCanvas;
VC.TextOut(X, Y, S);
VC.RectangleFrac(X, Y, X + VC.TextWidthFrac(S), Y + VC.TextHeightFrac(S));
```

- widths come from the base-14 AFM tables when `StandardFontsReplace` is set and
  the name is Helvetica/Times/Courier (or an alias), from the platform backend
  otherwise — the resolution order of `TPdfCanvas.SetFont`
- `TextHeightFrac` is `Font.Size + Descent` of the face, because `TextOut` puts
  the baseline `Font.Size` below the requested top; a box of that height encloses
  the glyphs including descenders
- code points outside WinAnsi fall back to the face's default width, so CJK text
  is not measurable through this path
- if no PDF face resolves (no platform backend registered), all of them fall back
  to the LCL

### Available TCanvas Methods

Text: `TextOut`, `TextWidth`, `TextHeight`
Shapes: `Rectangle`, `Ellipse`, `RoundRect`, `FillRect`
Sub-pixel (TPdfVclCanvas only, `single` instead of `integer`):
`TextOutFrac`, `TextWidthFrac`, `TextHeightFrac`, `RectangleFrac`
Lines: `MoveTo`, `LineTo`, `Polyline`, `Polygon` — `MoveTo` only moves `PenPos`; each `LineTo` writes one complete path object (`RG w` → `m` from `PenPos` → `l` → `S`), so pen changes never land inside a path (B-12)
Images: `Draw`, `StretchDraw`
Font: `Name`, `Size`, `Style` (fsBold/fsItalic/fsUnderline/fsStrikeOut), `Color`
Pen: `Color`, `Width`, `Style` (psSolid/psClear)
Brush: `Color`, `Style` (bsSolid/bsClear)

---

## Tagged PDF (ISO 32000-1 §14 — Accessibility)

Tagged PDF adds structure tags (H1–H6, P, …) that screen readers and PDF/UA validators require.

### Enum

`TPdfStructRole` is defined in `mormot.pdf.types`:

```pascal
TPdfStructRole = (psrDocument, psrH1, psrH2, psrH3, psrH4, psrH5, psrH6,
                  psrP, psrSpan,
                  psrFigure,               // for images — carries /Alt text
                  psrTable, psrTR, psrTH, psrTD); // table structure
// Ordinal: psrDocument=0, psrH1=1..psrH6=6, psrP=7, psrSpan=8
//          psrFigure=9, psrTable=10, psrTR=11, psrTH=12, psrTD=13
// TPdfStructRole(Level) for heading Level 1..6 gives psrH1..psrH6
```

### Low-Level: TPdfDocument

```pascal
Doc.Tagged := True;               // enable structure tags; must be set before AddPage
Doc.DefaultLanguage := 'en';      // BCP-47 language tag for /Lang entry (default 'en')

// After AddPage, wrap each tagged content block:
Doc.Canvas.BeginStructContent(psrH1);
Doc.Canvas.TextOut(...);          // heading text
Doc.Canvas.EndStructContent;

Doc.Canvas.BeginStructContent(psrP);
Doc.Canvas.TextOut(...);          // paragraph text
Doc.Canvas.EndStructContent;

// Figure: optional AAltText for screen-reader accessibility
Doc.Canvas.BeginStructContent(psrFigure, 'Company logo');
Doc.Canvas.DrawXObject(...);
Doc.Canvas.EndStructContent;

// Table structure
Doc.Canvas.BeginStructContent(psrTable);
  Doc.Canvas.BeginStructContent(psrTR);
    Doc.Canvas.BeginStructContent(psrTH); Doc.Canvas.TextOut(...); Doc.Canvas.EndStructContent;
  Doc.Canvas.EndStructContent;
  Doc.Canvas.BeginStructContent(psrTR);
    Doc.Canvas.BeginStructContent(psrTD); Doc.Canvas.TextOut(...); Doc.Canvas.EndStructContent;
  Doc.Canvas.EndStructContent;
Doc.Canvas.EndStructContent;
```

`BeginStructContent(ARole, AAltText)` — `AAltText` is optional (default ''); written as `/Alt` for Figure elements. No-op when `Tagged = false`.

`/Alt` is emitted **twice**, and both are PDF strings — a WinAnsi literal in parenthesis, or `<FEFF…>` UTF-16BE outside WinAnsi (ROADMAP B-6):

```
/Figure <</MCID 0 /Alt (Vector graphics)>> BDC     ← marked-content dictionary
<</Type/StructElem/S/Figure/…/Alt(Vector graphics)>>  ← the tag tree, PDF/UA 7.3
```

`LastStructContent` returns the index of the element just opened, and
`ResumeStructContent(Index, AOpenRegion=true)` reopens that element on the
current page with a fresh MCID. Use it when one logical block is interrupted by
a page break: the element then owns several MCIDs and its `/K` becomes an array
of `/MCR` dicts, each carrying an explicit `/Pg` when it sits on another page
than the element. `AOpenRegion=false` reopens it without a region, as
`BeginStructGroup` does.

### Mixed content: one paragraph, several inline runs

An element may own both marked-content regions and child elements; `/K` then
lists `/MCR` dicts and kid references in **reading order**. This is how one
sentence with inline styling becomes one `P` (ROADMAP B-3):

```pascal
Canvas.BeginStructGroup(psrP);        // element only — no region, no MCID yet
  Canvas.ContinueStructContent;       // plain run: adds a region to the P
  Canvas.TextOut(...);                // 'Inline styles like '
  Canvas.SuspendStructContent;        // closes that region, P stays the parent
  Canvas.BeginStructContent(psrSpan); // styled run: nested Span kid
  Canvas.TextOut(...);                // 'bold'
  Canvas.EndStructContent;            // Span
  Canvas.ContinueStructContent;       // next plain run: one more P region
  Canvas.TextOut(...);                // ', '
Canvas.EndStructContent;              // P
```

Result: `P /K [ MCR 15  Span 16  MCR 17  … ]`, with every MCID mapped back to
its owner in `/ParentTree`.

- `BeginStructGroup(ARole)` — opens an element without a region; pair with
  `EndStructContent`
- `ContinueStructContent` — adds one region (fresh MCID) to the innermost open
  element; no-op when it already has an open region
- `SuspendStructContent` — closes that region but keeps the element open as the
  parent of what is nested next; no-op when no region is open

`EndStructContent` writes `EMC` only when the element actually has an open
region, so a group element and a container emit none.

**Important:** BDC/EMC must be outside BT/ET. Call `BeginStructContent` before and `EndStructContent` after the text command.

When `Tagged = true`:
- The catalog gains `/MarkInfo << /Marked true >>`, `/Lang`, and `/StructTreeRoot`
- Each page gains `/StructParents N`
- A `StructTreeRoot` with `Document` root, leaf StructElems, and `ParentTree` number tree is serialized at `SaveToStreamDirectEnd`
- The catalog gets `/ViewerPreferences <</DisplayDocTitle true>>`, and the XMP packet (`pdfuaid:part` 1, `dc:title` = `Info.Title`) is written at `SaveToStreamDirectEnd`. Set `Info.Title`: PDF/UA needs one
- Every `TH` gets `/A <</O/Table/Scope/Column>>`
- **Low-level API, caller's duties:** PDF/UA wants one bookmark per heading. Create the document with `AUseOutlines = true` and call `CreateOutline(Title, Level, TopPosition)` after each heading (`TopPosition` in PDF points from the page bottom); the engine cannot do it for you, because `BeginStructContent(psrHx)` never sees the heading text. `TGDIPages` does it itself. Text drawn inside a `Figure` is part of the image: a reader gets the `/Alt` instead, so the `/Alt` has to describe that text too. PAC 2024 warns "Possibly inappropriate use of figure structure element" on `pdf_demo`'s vector figure, both with and without its text, so the warning is accepted there (ROADMAP W-1)
- A `Figure` on one page gets `/A <</O/Layout/BBox[l b r t]>>`. `TPdfCanvas` collects it from the path points (widened by half the line width), from `TextOut`/`TextOutW` (width from the font engine; descent approximated as ¼ size) and from `DrawXObject`. Points drawn under a `ConcatToCTM` that is still active are ignored, because they are not in page space
- **Artifacts:** a path object (`m l c v y re` … paint/`n`) or an image `Do` drawn while no struct region is open is wrapped in `/Artifact BMC … EMC` automatically. Inside a region (e.g. `Figure`) it stays real content. For other skipped content, e.g. a repeated table header or a running page header, use `Canvas.BeginArtifact`/`EndArtifact` (also on `TPdfDocumentVcl`). Do not open a struct element inside it: `BeginArtifact` inside a region and an unmatched `EndArtifact` raise `EPdfInvalidOperation`

### High-Level: TPdfDocumentVcl wrapper

```pascal
Doc.BeginStructContent(psrH2);  // delegates to Canvas.BeginStructContent
Doc.EndStructContent;            // delegates to Canvas.EndStructContent
// same delegation for BeginStructGroup, ContinueStructContent,
// SuspendStructContent, LastStructContent and ResumeStructContent
```

### TGDIPages integration

```pascal
// In mormot.ui.report.pas — uses mormot.pdf.types (not mormot.ui.pdf)
Report.ExportPdfTagged   := True;    // default False — set BEFORE drawing:
                                     // it forces ExportPdfEmbeddedTTF / clears
                                     // ExportPdfStandardFonts, and those decide
                                     // which metrics the layout is measured with
                                     // (raises ESynException once PageCount > 0)
Report.ExportPdfLanguage := 'en';    // default 'en'
// then call Report.ExportPdfStream as usual
```

`RenderPageToCanvas` wraps drawing commands with struct content via `fActivePdfDoc: TPdfDocumentVcl`:
- `dckDrawText`: heading-level → `psrH1..psrH6`; inside table header row → `psrTH`; inside table data row → `psrTD`; otherwise → `psrP`
- `dckHeading`: `psrH1..psrH6`
- `dckDrawBitmap`: `psrFigure`
- `dckBeginTable`/`dckEndTable`: opens/closes `psrTable`
- `dckBeginTR`/`dckEndTR`: opens/closes `psrTR`; `Color <> 0` marks header row (→ `psrTH` for cells)

---

## PDF Encryption

Requires compile-time flag `USE_PDFSECURITY`.

```pascal
uses mormot.ui.pdf;

var Enc: TPdfEncryption;
// RC4-40 (PDF 1.3), RC4-128 (PDF 1.4), AES-128-CBC (PDF 1.6):
Enc := TPdfEncryption.New(
  elAES_128,             // TPdfEncryptionLevel: elNone, elRC4_40, elRC4_128, elAES_128
  'user-pass',           // user password (max 32 Latin-1 chars; '' = no open-doc password)
  'owner-pass',          // owner password (must be non-empty)
  PDF_PERMISSION_NOMODIF // TPdfEncryptionPermissions
);
Doc := TPdfDocument.Create(false, 0, pdfaNone, Enc);
// ...
```

The `TPdfEncryption` object is owned by `TPdfDocument` after passing to constructor.

| Level | Class | PDF version | Cipher | Key derivation |
|---|---|---|---|---|
| `elRC4_40` | `TPdfEncryptionRC4MD5` | 1.3+ | RC4-40 | MD5 |
| `elRC4_128` | `TPdfEncryptionRC4MD5` | 1.4+ | RC4-128 | MD5 (50 iter) |
| `elAES_128` | `TPdfEncryptionAES128` | 1.6+ | AES-128-CBC | MD5 (same as RC4-128); IV prepended per object |
| `elAES_256` | — | — | not implemented | — |

AES-128 output size: `16 (IV) + ceil(N/16)*16` bytes per encrypted object/string. The stream `Length` attribute is updated automatically before writing.

---

## Font Strategy

| Mode | Property | Font names | Embedding |
|---|---|---|---|
| Standard Type1 | `StandardFontsReplace := True` | Helvetica, Times, Courier | none |
| TrueType | `EmbeddedTTF := True` | OS-specific (see below) | full TTF |

**`Tagged := True` picks the mode for you:** it sets `EmbeddedTTF`, clears
`StandardFontsReplace` and sets `EmbeddedWholeTtf`, because PDF/UA allows neither
a non-embedded base-14 face nor a subset (which would break `/ToUnicode`). It
raises `ESynException` when set after the first `AddPage`, and it also widens the
WinAnsi `/ToUnicode` CMap — previously written for PDF/A only — to tagged
documents. Resolve font names with `GetReportFonts` *after* setting `Tagged`.

Platform-specific TTF fonts via `GetReportFonts(Embedded, SansFont, SerifFont, MonoFont)`:
- Windows: Calibri, Cambria, Consolas
- macOS: Trebuchet MS, Georgia, Andale Mono
- Linux: Liberation Sans, Liberation Serif, Liberation Mono

Standard constants in `mormot.pdf.types.pas`: `PDF_FONT_STD_SANS` = 'Helvetica', `PDF_FONT_STD_SERIF` = 'Times', `PDF_FONT_STD_MONO` = 'Courier'.

`FontFallBackName` (TPdfDocument property): font substituted when a requested TrueType font is not found on the system.

---

## FPImage Bitmap Adapter (mormot.pdf.fpimage)

Used on non-Windows platforms to embed PNG/JPEG images. Not needed on Windows (GDI handles bitmaps).

```pascal
// Only needed when calling TPdfDocument.CreateOrGetImage on Unix/macOS:
uses mormot.pdf.fpimage;

var Adapter: IPdfBitmapAdapter;
Adapter := CreatePdfBitmapAdapter;
Adapter.LoadFromFile('photo.png');
// width, height, raw pixels:
W := Adapter.GetWidth;
H := Adapter.GetHeight;
Raw := Adapter.GetRawRGB;              // RGB24 bytes
Jpg := Adapter.GetJpegBytes(85);      // JPEG-encoded at quality 85

// In practice, the adapter is used internally by TPdfDocument.CreateOrGetImage.
// Application code calls CreateOrGetImage directly and does not need IPdfBitmapAdapter.
```

`CreatePdfBitmapAdapter` is registered automatically by the unit's `initialization` section.

---

## Font Internals

For the full internal implementation of font loading, the dual WinAnsi/Unicode instance model, the text rendering chain (WinAnsi vs. Uniscribe vs. HarfBuzz), glyph tracking arrays (`fWinAnsiUsed`, `fUsedWideChar`, `fUsedWide`), font serialization, and RTL/Arabic limitations, see `.claude/skills/fonts.md`.

---

## Coordinate Conversion (TPdfVclCanvas)

```
Pixels (TCanvas, 96 DPI) -> PDF points (72 DPI)
X_pdf = X_px * 72 / 96
Y_pdf = PageHeight_pt - Y_px * 72 / 96   (Y-flip)
```

This conversion happens automatically in `TPdfVclCanvas`. In direct `TPdfCanvas` mode, convert manually.
