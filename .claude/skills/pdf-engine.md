# PDF Engine — TPdfDocument / TPdfDocumentVcl

Source: `src/pdf/mormot.pdf.pas`, canvas bridge: `src/pdf/mormot.pdf.canvas.pas`

## Two Entry Points

| Class | Coordinates | Dependency | When to use |
|---|---|---|---|
| `TPdfDocument` | PDF points (72 DPI), Y=0 bottom | mORMot2-Core and the font backend - no VCL/LCL (`TBitmap`/EMF: `mormot.pdf.canvas`) | Server/CLI, no TCanvas |
| `TPdfDocumentVcl` | pixels (96 DPI), Y=0 top | + TCanvas bridge; the LCL, or the VCL on Delphi | TCanvas-compatible code, GUI apps |

`TPdfDocumentGdi` (Windows-only) uses EMF/GDI — not ported; it lives in
`mormot.pdf.canvas` with `RenderMetaFile`, the `GdiComment*` procedures, the
printer helpers and the `TBitmap`/`TGraphic` image functions. The adapter
reaches the engine's protected state through implementation-local access
classes (`TPdfCanvasAccess` ...).

**Compilers.** `TPdfDocument`/`TPdfCanvas` build with FPC everywhere and with
Delphi 7, Delphi 2010 and Delphi 13 (`tests\build_delphi7.bat`,
`tests\build_delphi2010.bat`, `tests\delphi13\`), and so does
`TPdfDocumentVcl` on Windows — Delphi 13 on Linux64/Android64 has no VCL and
builds layer 1 only. The `TCanvas` drawing methods are virtual in the LCL and
static in Delphi's VCL. `TPdfVclCanvas` overrides them under FPC and
reintroduces them under Delphi (`PDF_CANVASVIRTUAL`, defined for FPC only),
so on Delphi only a `TPdfVclCanvas` reference reaches the PDF: a call through
`TCanvas` draws on the measuring DC. `VclCanvas` therefore has the type
`TPdfVclCanvas`; keep it. Code for every compiler follows the rule in
`CLAUDE.md` (Coding Conventions): mORMot2 functions first — `PosEx`, not the
three-argument `Pos`; `MinPtrInt`, not `Min` — and no `Default()`, `for..in`
or records with methods; `inline` only behind `{$ifdef HASINLINE}`.

**Numbers in the output differ by compiler.** FPC formats `double` with
Grisu (`DOUBLETOSHORT_USEGRISU` in `mormot.defines.inc`), Delphi 7 with
`Str(Value:0:2)`. Both give `'3.40'`, but Grisu writes an exact 0 as `'0'`,
not `'0.00'`. Code that post-processes the text must not assume two
decimals: `TPdfWrite.Add(double)` cuts trailing zeros only after a `'.'`, so
a `'0'` stays (`TestZeroRealIsWritten`; trimming it empties every
`TPdfReal` of 0, e.g. `/XYZ 0 802 ]`). Comparing the FPC and Delphi 7 output
of one page is how such a difference shows up.

---

## Enums Reference

```pascal
// PDF/A conformance level
// pdfa3U is appended last, so the older members keep their ordinal values
TPdfALevel = (pdfaNone, pdfa1A, pdfa1B, pdfa2A, pdfa2B, pdfa3A, pdfa3B, pdfa3U);

// PDF file format version (mormot.pdf; mormot.pdf.report re-exports it)
TPdfFileFormat = (pdf13, pdf14, pdf15, pdf16, pdf17);

// How the document appears when opened in a viewer
TPdfPageMode = (pmUseNone, pmUseOutlines, pmUseThumbs, pmFullScreen,
                pmUseAttachments);  // PDF 1.6: SaveToStreamDirectBegin raises
                                    // FileFormat to pdf16, or raises
                                    // EPdfInvalidOperation under PDF/A-1;
                                    // not allowed (and dropped) for
                                    // NonFullScreenPageMode

// Page layout used when document is opened
TPdfPageLayout = (plSinglePage, plOneColumn, plTwoColumnLeft, plTwoColumnRight);

// Viewer UI preferences
TPdfViewerPreference = (vpHideToolbar, vpHideMenubar, vpHideWindowUI,
                        vpFitWindow, vpCenterWindow,
                        vpEnforcePrintScaling, // raises FileFormat to pdf16
                        vpDisplayDocTitle);    // set by Tagged (PDF/UA-1 7.1)
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
// elAES_256: AES-256-CBC, ISO 32000-2 Standard Security Handler R=6, written
//            as PDF 1.7 with the Adobe extension level 8
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
PDF_PERSMISSION_NOPRINT       // no printing (the misspelling is the declared name)
PDF_PERMISSION_NOCOPY         // no content copy
PDF_PERMISSION_NOCOPYNORPRINT // no copy and no print
```

---

## TPdfDocument — Direct PDF API

```pascal
uses mormot.pdf;

Doc := TPdfDocument.Create;        // (AUseOutlines, ACodePage, APdfA, AEncryption)
Doc.DefaultPaperSize := psA4;      // psA4, psLetter, psA3, psA5, ...
Doc.EmbeddedTtf := False;          // True = embed (a subset by default)
Doc.StandardFontsReplace := True;  // True = Helvetica/Times/Courier as Type1
Doc.PdfA := pdfa1B;                // pdfaNone, pdfa1A, pdfa1B, pdfa2A, pdfa2B, pdfa3A, pdfa3B, pdfa3U
                                   // setting PdfA calls NewDoc: prefer the constructor's APdfA
Page := Doc.AddPage;               // returns TPdfPage
C := Doc.Canvas;                   // TPdfCanvas (same per page)
C.SetFont('Helvetica', 12, []);
C.TextOut(72, 750, 'Hello');       // X,Y in points from bottom-left
Doc.SaveToFile('out.pdf');
Doc.Free;
```

The constructor calls `NewDoc`; call it again only to reset the whole
document.

### Key Properties

| Property | Type | Description |
|---|---|---|
| `Canvas` | `TPdfCanvas` | Draw on current page |
| `Info` | `TPdfInfo` | Document metadata |
| `Root` | `TPdfCatalog` | The catalog: `PageLayout`, `PageMode`, `NonFullScreenPageMode`, `ViewerPreference`, `OpenAction` (below) |
| `EmbeddedTtf` | boolean | True = embed TrueType fonts (a subset unless `EmbeddedWholeTtf`); default false |
| `EmbeddedWholeTtf` | boolean | True = embed the whole face instead of a subset; default false |
| `EmbeddedTtfIgnore` | `TRawUtf8List` | Font names excluded from optional embedding; ignored for PDF/A and tagged output |
| `StandardFontsReplace` | boolean | True = Arial/Times New Roman/Courier New (and Helvetica/Times/Courier) drawn as the base-14 Type1 fonts, WinAnsi text only; default false |
| `DefaultPaperSize` | `TPdfPaperSize` | psA4 (default), psLetter, etc.; resets the orientation to portrait |
| `DefaultPageWidth` | cardinal | Page width in PDF points (overrides PaperSize) |
| `DefaultPageHeight` | cardinal | Page height in PDF points |
| `DefaultPageLandscape` | boolean | Landscape orientation (swaps width and height) |
| `PdfA` | `TPdfALevel` | PDF/A conformance level; the setter calls `NewDoc` |
| `PdfAMetadaExtension` | `RawUtf8` | Raw XMP appended to the packet (below) |
| `CompressionMethod` | `TPdfCompressionMethod` | cmNone or cmFlateDecode (default) |
| `UseOutlines` | boolean | Must be true (or `AUseOutlines` of the constructor) before `OutlineRoot` or `CreateOutline` is used |
| `OutlineRoot` | `TPdfOutlineRoot` | Bookmarks root |
| `UseOptionalContent` | boolean | Enable PDF optional content (layers); forces PDF 1.5; the setter calls `NewDoc` |
| `UseFontFallBack` | boolean | Draw glyphs missing from the current face with `FontFallBackName`; default true |
| `FontFallBackName` | string | Face used for glyphs missing from the current one |
| `ForceJPEGCompression` | integer | 0 (default) = bitmaps as they are; a quality (e.g. 60, 80) = the `TBitmap`/`TGraphic` images of `mormot.pdf.canvas` stored as JPEG, except a bitmap with `TransparentMode = tmFixed` (lossless, its `/Mask` kept); no effect on raw pixels |
| `ForceNoBitmapReuse` | boolean | True = no lookup of identical images (faster, larger) |
| `ScreenLogPixels` | integer | DPI the pixel coordinates are mapped with: 96, the screen's on Windows for `TPdfDocumentVcl`/`TPdfDocumentGdi`; 0 or less raises `EPdfInvalidValue` |
| `FileFormat` | `TPdfFileFormat` | PDF version header: `pdf13`..`pdf17` (default `pdf13`); PDF/A raises it (A-1 to `pdf14`, A-2/A-3 to `pdf17`), as does `Tagged` (`pdf17`) |
| `HeaderFileFormat` | `TPdfFileFormat` | Read-only: the version actually streamed in the header |
| `GeneratePdf15File` | boolean | Compatibility alias, as in the trunk: below `pdf16`, `true` = `pdf15` and `false` = `pdf14`; from `pdf16` on it changes nothing |
| `Tagged` | boolean | Enable Tagged PDF (ISO 32000-1 §14); set before the first `AddPage` (raises `ESynException` later; `EPdfInvalidOperation` with an encryption without `/P` bit 10, see PDF Encryption); `true` raises `FileFormat` to `pdf17` and selects the fonts (Font Strategy) |
| `DefaultLanguage` | `RawUtf8` | BCP-47 tag for `/Lang` when tagged; default `'en'` |
| `UseUniscribe` | boolean | The one shaping switch: Uniscribe on Windows, HarfBuzz on Linux/macOS; `Canvas.RightToLeftText` is the direction only (`platform-backends.md`, Registration) |

The viewer settings are properties of the catalog, not of the document:
`Doc.Root.PageLayout`, `Doc.Root.PageMode`, `Doc.Root.NonFullScreenPageMode`
(the mode after leaving full-screen), `Doc.Root.ViewerPreference`.

### Methods

```pascal
Doc.NewDoc                                 // reset the document (the constructor calls it)
Doc.AddPage                                // new page; Canvas switches automatically
Doc.SaveToFile('out.pdf')                  // save to file; returns false on error
Doc.SaveToStream(Stream)                   // save to stream
Doc.SaveToStream(Stream, ForceModDate)     // save with explicit modification date

// Bookmarks
Doc.CreateBookMark(TopY, 'name')           // /XYZ destination, TopY in PDF points from the page bottom;
                                           // the name must be unique and not empty
Doc.CreateOutline(Title, Level, TopY)      // Level 1=H1, 2=H2 etc. (0 = root); nil without UseOutlines

// Links & annotations
Doc.CreateLink(Rect, 'bookmark')           // internal link; the bookmark may be created later
Doc.CreateHyperLink(Rect, 'http://', ...)  // external link
Doc.CreateAnnotation(Type, Rect, Border)   // free annotation

// Images
Doc.CreateOrGetImage(Pixels, ...)          // raw pixels (TPdfImagePixels), deduplicated; returns XObject name
CreateOrGetBitmapImage(Doc, Bitmap, ...)   // a VCL/LCL TBitmap, the same way (mormot.pdf.canvas)
Doc.AddTrueTypeFont('Calibri')             // register a face not enumerated by the system, right after Create; true on success

// Optional content (layers)
Doc.CreateOptionalContentGroup(Parent, Title, Visible)
Doc.CreateOptionalContentRadioGroup(Groups)

// File attachments (associated files, /AF in the catalog from PDF/A-2 up)
Doc.CreateFileAttachment(FileName, Description, MimeType, Relationship)
Doc.CreateFileAttachmentFrom(Buffer, Title, Description, MimeType,
  CreationDate, ModDate, Stream, Relationship)
// Relationship: afrUnspecified, afrSource, afrData, afrAlternative (default), afrSupplement

// XMP extension for PDF/A (raw XML, appended to the packet)
Doc.PdfAMetadaExtension := PdfMetadataFacturX('EN 16931');  // ZUGFeRD/Factur-X fx: + schema
// Tagged + PdfA: the engine adds the pdfuaid schema description itself, into
// the caller's <pdfaExtension:schemas><rdf:Bag> when there is one
// Verified: A-3U + PDF/UA-1, A-3A, A-3B; A levels need Tagged := True
// (the structure tree); A-1/A-2 implemented, unverified

// Streaming — page-by-page output to large streams without full buffering
Doc.SaveToStreamDirectBegin(Stream, ForceModDate)
Doc.SaveToStreamDirectPageFlush(FlushCurrentPageNow)
Doc.SaveToStreamDirectEnd
```

Callers of the trunk's `Doc.CreateOrGetImage(Bitmap)` and
`TPdfImage.Create(Graphic)`: `docs/MIGRATION.md`.

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
N := Page.MeasureText('Long text', MaxWidth); // index in the text of what fits in MaxWidth
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

`Title`, `Author`, `Subject`, `Keywords` and `Creator` are `string`,
`CreationDate` and `ModDate` are `TDateTime`, and `CustomMetadata` is
`RawUtf8` (custom XMP). `Producer` is set by the engine (`PDF_PRODUCER`).

---

## TPdfCanvas — Drawing Commands

Coordinates: PDF points, X=0 left, Y=0 bottom.

### Text

```pascal
C.SetFont('Times', 14, [pfsBold]);   // set font; returns TPdfFont
C.TextOut(X, Y, 'Text');             // output text at position
C.TextOutW(X, Y, PW);                // Unicode (PWideChar)
C.TextRect(Rect, 'Text', Alignment, Clipping); // text within a rectangle
C.MultilineTextRect(Rect, 'Text', WordWrap);   // CR+LF lines, optional word wrap

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

### Transparency

```pascal
C.SetFillAlpha(0.5);    // fill opacity: 0.0=transparent, 1.0=opaque (clamped)
C.SetStrokeAlpha(0.8);  // stroke opacity
```

Both methods lazily create a named `ExtGState` entry in the page's
`/Resources` dictionary and emit a `/<name> gs` operator: `/Fca<n>` (`/ca`)
and `/SCA<n>` (`/CA`), `<n>` the opacity in percent, so the same value gives
the same name on a page and no duplicate entry. Transparency needs PDF 1.4;
the methods do not raise `FileFormat` - set `pdf14` or higher yourself.
`TPdfDocumentVcl` has both methods too.

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
C.ClosePathStroke;
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
C.SetDash([4, 2], phase);     // dash pattern of integers, phase default 0 (empty array = solid)
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
// Draw an image registered with Doc.CreateOrGetImage / CreateOrGetBitmapImage:
C.DrawXObject(X, Y, Width, Height, 'ImageName');
C.DrawXObjectEx(X, Y, Width, Height, ClipX, ClipY, ClipWidth, ClipHeight, 'ImageName');
C.ExecuteXObject('ImageName');  // raw Do operator
```

**Raw pixels, no VCL/LCL** - what a framework adapter feeds:

```pascal
var px: TPdfImagePixels;
px.Width := W; px.Height := H;
px.Format := ipfRgb24;            // ipfBgr24, ipfBgrx32 (x skipped, no alpha), ipfIndexed8
px.Data := TopRow;                // row y at Data + y * Stride
px.Stride := RowBytes;            // negative for a bottom-up DIB
px.Size := BufferBytes;           // >= (H - 1) * Abs(Stride) + one row
px.Palette := Rgb768;             // ipfIndexed8 only: 256 x R, G, B
px.HasColorKey := true; px.ColorKey := $BBGGRR; // /Mask, RGB formats only
Name := Doc.CreateOrGetImage(px, @DrawAt, @ClipRc); // reuse by row bytes + palette
// JPEG bytes as they are, the colour space from their components (gray or
// RGB; CMYK raises EPdfInvalidValue, as CreateJpegDirect does for no JPEG):
Img := TPdfImage.CreateJpeg(Doc, Data, Len, W, H, {DontAddToFXref=}false);
Name := Doc.RegisterImage(Img);   // 'SynImg<n>'; AddXObject or RegisterXObject by xref state
Doc.DrawImage(Name, @DrawAt);
```

`CheckPixels` raises `EPdfInvalidValue` for an empty image, a stride below a
row, a short `Size`, a palette that is missing, not 768 bytes or given to an
RGB format, a color key with `ipfIndexed8`. `ForceJPEGCompression` does not
apply to raw pixels (no encoder in the engine). The reuse key of raw pixels
(CRC32C lanes over the row bytes, after the palette, the format and the
color key, one lane seeded apart) does not equal the key of
a `TBitmap` (`BitmapHash`) - the same picture added both ways gives two
images. `CreateGraphicImage(Doc, Graphic, ..)` and
`CreateOrGetBitmapImage(Doc, Bitmap, ..)` (`mormot.pdf.canvas`) fill a
`TPdfImagePixels` from `ScanLine[]` and call the same code.

How the image paths behave (covered by `tests/test_pdf_images.pas`):

- `CreateOrGetBitmapImage`: pf24bit and pf32bit become `/DeviceRGB` (alpha
  dropped); a pf24bit bitmap with `TransparentMode = tmFixed` writes `/Mask`,
  and stays lossless under `ForceJPEGCompression` (a JPEG has no colour key).
  `EMR_TRANSPARENTBLT` comes this way: `TPdfEnum.DrawBitmap` sets the key
  The same pixels give the same image, across pages too. An empty bitmap (no
  width or no height) gives no image: it returns ''
- `BitmapHash` (public) is that reuse key: CRC32C lanes over the rows - the
  DIB row on the VCL, `RawImage.Description.BytesPerLine` on the LCL, which
  may align rows less than a DIB (a pf1bit row of 10 pixels: 2 bytes on LCL
  win32), so a DIB row length would read past the last row - after the
  palette entries and the color key of a pf24bit bitmap
- pf1bit/pf4bit/pf8bit with the VCL: converted to pf8bit and written indexed
  (`/Indexed /DeviceRGB 255`) from the bitmap's 256-entry palette;
  `EPdfInvalidValue` without one. The LCL keeps no palette
  (`GetPaletteEntries` returns 0 on win32, GTK2 and Cocoa): such a bitmap is
  8-bit gray (pf4bit, pf8bit) or 1-bit mono, and `LclPixels` writes it
  indexed with a gray ramp (`<000000 010101 ...>`)
- **The LCL's layouts** (`LclPixels`, from `RawImage.Description`): pf24bit is
  24-bit B,G,R on win32 but 32 bits B,G,R,x on GTK2 and A,R,G,B on Cocoa;
  pf32bit is B,G,R,A on win32, R,G,B,A on GTK2, A,R,G,B on Cocoa. A Windows
  DIB layout (B,G,R or B,G,R,x little-endian) goes through as
  `ipfBgr24`/`ipfBgrx32`, gray 8-bit as `ipfIndexed8`; every other layout is
  repacked to `ipfRgb24` through `TLazIntfImage.Colors`. Never read an LCL
  bitmap as B,G,R: the tests compare with `TLazIntfImage.Colors`, not with
  an assumed layout
- `CreateGraphicImage` raises `EPdfInvalidValue` for an empty graphic. With
  `DontAddToFXref = false` it, `CreateJpeg(.., false)` and
  `CreateJpegDirect(.., false)` are already in the xref: register them with
  `RegisterImage` or `RegisterXObject`, not `AddXObject` (which adds them
  again and raises)
- `TPdfForm.Create(DocGdi, MetaFile)` (a metafile as a form XObject) draws
  on a `TPdfPage.Create(nil)`, which makes a MediaBox for `SetPageHeight`;
  `TPdfDocument.ShareFormResources` gives the form and that page the same
  indirect `/XObject`, `/ExtGState` and `/Properties` dictionaries
  (`TPdfFormWithCanvas` too), so the metafile's bitmaps land in the form's
  resources. The document canvas is saved and restored field by field,
  because there may be no current page to go back to. The form's `/BBox` is
  the metafile's `Width`/`Height`, which follow the reference DC's DPI.
  Outline, bookmark and link comments of the metafile are left out in a form
  (`TPdfEnum.HandleComment`): it has no page to point to. `MetaFileForm` and
  `FormWithCanvasImage` test it. `RenderMetaFile` into a page works
- `TPdfCanvas.DrawXObjectPrepare` copies the fonts of a `TPdfFormXObject`
  (the base of `TPdfForm`) into the font list of the page: `AddItem` wraps an
  indirect font in a new `TPdfVirtualObject`, so nothing is shared - a direct
  value would be (no form adds one). `TPdfImageRawTests.FormFonts` covers it
- `TPdfDocumentVcl.Create` takes the `AEncryption` of `TPdfDocument.Create`:
  `mormot.pdf.canvas` includes `mormot.pdf.defines.inc`, so `USE_PDFSECURITY`
  is the same there as in `mormot.pdf` (`TestVclCanvasEncryption`)

### Optional Content (Layers)

```pascal
C.BeginMarkedContent(Group: TPdfOptionalContentGroup);
// ... drawing commands visible only when group is on ...
C.EndMarkedContent;
```

### Pixel-Coordinate Helpers (protected)

`TPdfCanvas` maps device pixels to PDF points with protected helpers: the
`I` suffix takes integers, the `S` suffix `single` values. Both go through
the window/viewport mapping (`ViewOffsetX/Y`), the world transform and the
`ScreenLogPixels` scale, and flip Y (`I2X`/`I2Y`, `S2X`/`S2Y`). The EMF
renderer (`TPdfEnum`, `RenderMetaFile`) and the bridge use them through
access classes; they are not public API.

```pascal
MoveToI(x, y: integer);  LineToI(x, y: integer);
MoveToS(x, y: single);   LineToS(x, y: single);
CurveToCI(x1, y1, x2, y2, x3, y3: integer);
RoundRectI(x1, y1, x2, y2, cx, cy: integer);
ArcI(centerx, centery, W, H, Sx, Sy, Ex, Ey: integer; clockwise: boolean;
  arctype: TPdfCanvasArcType; var position: TPoint);
BoxI(Rect, Normalize);   // TRect -> TPdfBox
RectI(Rect, Normalize);  // TRect -> TPdfRect
BoxInclI(Rect);          // EMR_RECTANGLE, EMR_ELLIPSE: + one device pixel
BoxExclI(Rect);          // the fills of TPdfEnum.FillRectangle: as they are
DevPixelX; DevPixelY;    // one device pixel in logical units of the map mode: Win / View, signed
```

How GDI records a box (measured, `MetaFileBoxes`): `Rectangle`, `Ellipse`
and `RoundRect(10, 10, 50, 50)` are stored as 10,10,49,49 - one **device**
pixel inside, so 100,100,490,490 at 10 logical units per pixel
(`MM_ANISOTROPIC`). With an axis mirrored (viewport extent -100) the box is
recorded as 500,100,110,490: the recorded Right is the device-right edge, the
smaller value. Under `GM_ADVANCED` the box is recorded as called, 10..50,
and GDI paints it with its right and bottom edges: 81 device pixels under a
world scale of 2, 21 under 0.5 (measured on a memory DC, `MetaFileWorldBoxes`).
Both ways the shape covers one device pixel more on the device's right and
bottom: `BoxInclI` and `RoundRectI` map both corners, normalize, and add
`fDevScaleX`/`fDevScaleY` - one device pixel in PDF points - to the device's
right and bottom (`AddDevicePixel`): whatever the mapping, a mirrored map mode
or the world scale, and on the page's left or top for a negative render
scale of `RenderMetaFile`. A mirroring world transform - a scale with a
negative factor, no shear - is a scale of the canvas too (`fWorldFactorX/Y`
negative): shapes and positions are mirrored, the line width taken with
`Abs`; a glyph is not mirrored but placed upright in the box GDI's mirrored
one takes (`TextOut`: `w - ww` for X, the ascent and descent swapped for Y;
its underline, strike-out and path frame start where the glyphs start and go
along and across them turned by the font's angle, then times `sx` and `sy`,
as the upright glyphs go on the device),
and a bitmap only on Y (the DIB flip of `EMR_STRETCHDIBITS`) - this for one
axis mirrored. Both factors negative, equal or not, turn the text by 180
degrees: `TextOut` writes `-1 0 0 -1` from the aligned start, the size and
the move coming from the canvas, and its lines turn with it (`sx`, `sy` stay
1) (`MetaFileWorldReflection`). `I2X`/`I2Y`/`S2X`/`S2Y` apply the world scale
and move before the window and viewport, as GDI maps world, page, device;
they applied them after, wrong with a viewport origin or extent.
They added a logical unit of the map mode per pixel, not divided by the world
factor (82 and 20.5); #686 normalized before that, which shifted a mirrored
shape. A
`FillRect` (`EMR_BITBLT` with `PATCOPY`), `FillRgn` and the opaque rectangle
of `ExtTextOut` are stored as called: `BoxExclI`, as are the exclusive
rectangles of `EMR_INTERSECTCLIPRECT` and of an `ETO_CLIPPED` `ExtTextOut`
(`MetaFileClipBoxes`). `BoxI` takes one logical unit off; the EMF renderer
no longer uses it for shapes, fills and those two rectangles. The corners of
`RoundRectI` go through the mapping as the coordinates do. The metric map
modes set the viewport from `fPrinterPxPerInch` (`TPdfEnum.ScaleMatrix`), not
from the reference DC, so there the device pixel is an approximation.

The clip of `EMR_EXTSELECTCLIPRGN` is a `q ... W n` of the canvas: PDF can
only narrow a clip, so a new one needs the `Q` of the one before. `TPdfEnum`
keeps every region as PDF boxes (`fClipRegions`; the rectangles of the
record are device units, mapped by `DeviceBox` without window, viewport or
world transform - as are the bounds of a record, `rclBounds`, with the right
and bottom pixel included: `DeviceBoundsBox` for the meta region of
`EMR_HEADER`, which clips a bitmap without a region, and the text clip of
`tcClipExplicit`; `MetaFileBitmapBounds`), each state names its own
(`ClipRegion`, saved and restored with the state), and `SelectClip` makes the
canvas hold that one (`fClipActive`): from `ExtSelectClipRgn`, `RestoreDC`
and, with 0, at the end of `RenderMetaFile`. `EMR_INTERSECTCLIPRECT` is such
a region too (`IntersectClip`): each rectangle of the current region within
the record's, or the record's alone without one, an empty box when nothing is
left - GDI clips all output to it, shapes as well. The state's `ClipRgn` is
the box around its region, which the text (`tcAlwaysClip`) and bitmaps clip
to besides: it was never set for a region, so the text after
`SelectClipRgn` clipped to an empty box. `SetMetaRgn` keeps the `q` of the
clip as part of the meta region: a node of `fMetaClips` inside the ones kept
before it, named by the state (`MetaClip`); a later clip opens its `q` inside,
and `SelectClip` closes a node only when the state it restores lies outside.
A `Q` restores the PDF colours, line width and dash, so `SelectClip` forgets
the cached `fFillColor`, `fStrokeColor`, `fPenWidth` and `fPenStyle`.

A GDI path is painted under the clip and with the pen of its painting record,
while PDF allows no `q`/`Q` or `w`/`RG`/`d` within a path. So from
`EMR_BEGINPATH` (`PathBegin`) to `EMR_ENDPATH` (`PathClose`) the records of
the path's geometry (moves, lines, curves, shapes, `EMR_CLOSEFIGURE`) write
to a stream of its own: `EnumEMFFunc` calls `PathIn` before them and
`PathOut` after. Everything else goes to the page as it comes - clips, pen
operators (`NeedPen` and `NeedBrushAndPen` step out of the path's stream),
text, bitmaps, the miter limit - so the canvas's caches and the order stay
right; the shapes (`FlushPenBrush`, pie, chord, polylines, `PolyPoly`) do not
paint while recording. The painting records end what the page left open
(`PathPaint`), set the pen and the brush, then `PathReplay` writes the path - with
an `h` closing each figure for `EMR_STROKEANDFILLPATH` - then the painting
operator (`f*` for `ALTERNATE`); `EMR_ABORTPATH`,
`EMR_SELECTCLIPPATH` and the end of `RenderMetaFile` drop it (`PathDone`).
A tagged document's `/Artifact BMC` goes with the path's stream, its `EMC`
with the painting operator (`fPathArtifact`, `fPathBufArtifact`).
`TPdfCanvas.fNewPath` means "a GDI path is being recorded" and is read by
the enumeration alone (`TPdfForm.Create` only saves and restores it):
`PathBegin` sets it, `PathClose` clears it, and
`TPdfCanvas.NewPath` only writes `n`. When `NewPath` also set it, every `n`
outside a path left the enumeration as if inside one: the next line had no
`S`, and without a `MoveTo` no `m`, and `PolylineTo` was never stroked. Outside a path each line
record strokes with a pen or ends with `n` in its own record, so no stroke
is ever pending (`MetaFileNullPenLines`, `MetaFileLineAfterEndedPath`).
Text in a GDI path is part of the path: GDI adds its outlines, a
rectangle for an underline or strike-out and for an opaque background (the
`ETO_OPAQUE` rectangle, the box of the `OPAQUE` background mode), never
uses the text colour, and adds nothing of `ETO_CLIPPED` text (measured
with `GetPath`). PDF text cannot join a path, so `PathTextOut` writes the
`BT`..`ET` to a stream of its own (`fPathText`, then `fPathTextBuf`) in a
`q`..`Q` with its own `Tf` (`fFontReselect`), `Tc`, `Tw` and `Tz` - other
text may change the page's before the painting - the page's text state kept.
`TextOut` writes the rectangles to the path's stream, turned with the text,
and an `m` to the current position after the text, which ends the figure
in GDI. The painting
record writes the text after its operator, in the render mode of its brush
and pen (`PathTextPaint`, `Tr` 0, 1 or 2); a dropped path drops it. The text
is painted after the other figures, not as one union with them, so the fill
rule does not combine them (`MetaFileTextInPath`). A world rotation turns
the text only: the canvas maps a world scale alone (`fWorldFactorX/Y`,
`fWorldOffsetX/Y` from `ScaleMatrix`), any other transform with factor 1 and
offset 0, so every shape - the rectangles of text in a path too - is drawn
unturned and unscaled, and only a rotation's text carries the transform in
its own matrix, (eM11, -eM12, -eM21, eM22) as GDI's Y goes down and PDF's up;
a shear is not applied at all, to text neither. They
kept the scale and move of the transform before (`MetaFileWorldRotation`: the
turned text of `emf_world` twice its size). A full transform of the geometry
would map each point pair, as LibreOffice's emfio does: after the freeze.
The path and its text are converted while recorded, as GDI keeps a path in
device units: a world transform set before the painting record moves
neither, only what follows (`MetaFileTransformAfterPath`). A layer comment
(`GdiCommentBeginMarkContent`) within a path goes to the page, never to the
path's streams: `EMR_GDICOMMENT` does not call `PathIn`. The path and its
text are in the layer when its painting record is, as GDI paints them then
(`MetaFileMarkedContentInPath`).

A stock font (`GetStockObject`) is not recorded in the metafile:
`SelectObjectFromIndex` takes its LOGFONT from this system (`GetObjectW`) and
measures it on the reference DC as `CreateFont` does (`MeasureFont`), so its
text does not keep the size and metrics of the font before; its size is of
device pixels under any map mode, as in GDI, turned into logical units when
selected and again when the map mode changes (`Font.StockFont`, from
`ScaleMatrix`; the `SYSTEM_FONT` of `EMR_HEADER` too): `TFontSpec` holds
them as `single`, as a fraction of a unit at 32 pixels per unit, with
`height` for `abs(lfHeight)`, whose integer rounds to 0 there; `TextOut`
sizes the positive `lfHeight` of a stock font by the cell, aligns by
`height` and builds an opaque background in single precision. `EMR_HEADER`
selects `SYSTEM_FONT`, the font of a new DC: text before any selection had
size 0 (`MetaFileStockFontMetrics`). `DEFAULT_GUI_FONT` is recorded as a font
of the metafile. An `EMR_EXTTEXTOUTA` decodes in the stock font's code page
(`StockCodePage`, `MetaFileAnsiStockFont`).

Records `TPdfEnum` reads through its own declarations: `EMR_CREATEBRUSHINDIRECT`
and `EMR_EXTCREATEPEN` (`TEmrCreateBrushIndirect32`, `TEmrExtCreatePen32`).
The `windows` unit of FPC 3.2.2 declares them with the native `LOGBRUSH` and
`EXTLOGPEN`, whose `ULONG_PTR` hatch moves the fields on Win64 (`lbColor` at
offset 20 instead of 16): every brush and extended pen was black there.
FPC trunk and Delphi have the 32-bit layout (`MetaFileRecordLayout`).

### Text Metrics

```pascal
W := C.TextWidth('Hello');             // width in PDF points
W := C.UnicodeTextWidth(PW);           // Unicode version
N := C.MeasureText('Long', MaxWidth);  // index in the text of what fits within MaxWidth
```

---

## TPdfDocumentVcl — TCanvas-Compatible Wrapper

```pascal
uses mormot.pdf, mormot.pdf.canvas;

Doc := TPdfDocumentVcl.Create;
Doc.DefaultPaperSize := psA4;
Doc.EmbeddedTTF := False;
Doc.StandardFontsReplace := True;
Doc.AddPage;
C := Doc.VclCanvas;      // TPdfVclCanvas (keep the type for Delphi) — pixels, Y=0 top
C.Font.Name := 'Helvetica';
C.Font.Size := 12;
C.TextOut(40, 40, 'Text');
Doc.SaveToFile('out.pdf');
```

`VclCanvas` is created at the first `AddPage` and reused: each later
`AddPage` resets its cached pen/font state (the `Pen` and `Font` keep their
values), so the next draw writes them again.

- **Its scale is taken at the first page** from `ScreenLogPixels` (96 in the
  engine, the screen's on Windows - set by `TPdfDocumentVcl.Create`): set
  another value before the first `AddPage`; later it only reaches the engine
  (`canvas_bridge_pages` pins 144)
- **`TPoint`/`TRect` of `Polyline`, `Polygon`, `FillRect`, `StretchDraw`** are
  the ones `mormot.pdf.canvas` sees: `mormot.pdf`'s packed types on FPC (it
  comes last in the `uses`), those of `Types` on Delphi. A caller resolves
  them the same way when `mormot.pdf` comes after `Types` in its `uses`
- **`FillRect`, `StretchDraw`, `Polyline`, `Polygon` are reintroduced on
  every compiler:** through a plain `TCanvas` reference they reach the
  LCL/VCL, not the PDF (`TGDIPages` and its bitmaps: `report-engine.md`)
- `Draw`/`StretchDraw` of a graphic that is no `TBitmap` draw it on a
  bitmap of their own first; the same bitmap drawn twice is one image
  (`images_bridge`)

### Text Metrics

`TextWidth`/`TextHeight`/`TextExtent` measure with `TPdfFontMeasurer`, i.e.
the face and widths the PDF will really use, not the widgetset's own
resolution of `Font.Name`. They return `integer` pixels, so a caller that
needs the exact value takes the `single` methods and draws with
`RectangleFrac`:

```pascal
VC := Doc.VclCanvas;     // TPdfVclCanvas
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

Text: `TextOut`, `TextWidth`, `TextHeight`, `TextExtent`
Shapes: `Rectangle`, `Ellipse`, `RoundRect`, `FillRect`
Sub-pixel (TPdfVclCanvas only, `single` instead of `integer`):
`TextOutFrac`, `TextWidthFrac`, `TextHeightFrac`, `RectangleFrac`
UTF-8 (TPdfVclCanvas only, `RawUtf8` instead of `string`): `TextOutUtf8`, `TextWidthUtf8` — the same on every compiler, while the `string` methods read `string` as the compiler holds it (UTF-8 under FPC, the ANSI code page under Delphi 7, UTF-16 under Unicode Delphi) through `StringToSynUnicode`/`StringToUtf8`. Under FPC both read the same UTF-8 whatever the unit order and the Windows code page: `mormot.core.os` calls `SetMultiByteConversionCodePage(CP_UTF8)` before `mormot.core.unicode` sets `CurrentAnsiConvert`
Lines: `MoveTo`, `LineTo`, `Polyline`, `Polygon` — `MoveTo` only moves `PenPos`; each `LineTo` writes one complete path object (`RG w` → `m` from `PenPos` → `l` → `S`), so pen changes never land inside a path (ISO 32000-1 8.2); `psClear` draws nothing
Images: `Draw`, `StretchDraw`
Font: `Name`, `Size`, `Style` (fsBold/fsItalic/fsUnderline/fsStrikeOut), `Color`
Pen: `Color`, `Width`, `Style` (psSolid/psClear)
Brush: `Color`, `Style` (bsSolid/bsClear)

---

## Tagged PDF (ISO 32000-1 §14 — Accessibility)

Tagged PDF adds structure tags (H1–H6, P, …) that screen readers and PDF/UA validators require.
Table roles: `psrTable`, `psrTR`, `psrTH`, `psrTD`, plus the row groups
`psrTHead`, `psrTBody` and `psrTFoot` (ISO 32000-1 14.8.4.3.4).
`psrTHRow` is a `TH` that heads its row, e.g. the label of a totals line: it
writes `/S /TH` with `/Scope /Row` (PDF/UA-1 7.5); `psrTH` heads its column.
List roles: `psrL`, `psrLI`, `psrLbl`, `psrLBody`.

### Enum

`TPdfStructRole` is declared in `mormot.pdf` (with `TPdfFileFormat`, the
`PDF_FONT_*` constants and `GetPdfFonts`), so `uses mormot.pdf` is enough:

```pascal
TPdfStructRole = (psrDocument, psrH1, psrH2, psrH3, psrH4, psrH5, psrH6,
                  psrP, psrSpan,
                  psrFigure,                    // for images — carries /Alt text
                  psrTable, psrTR, psrTH, psrTD, // table structure
                  psrL, psrLI, psrLbl, psrLBody, // list structure
                  psrTHead, psrTBody, psrTFoot,  // row groups of a table
                  psrTHRow);                     // a TH heading its row (/S /TH)
// Ordinal: psrDocument=0, psrH1=1..psrH6=6, psrP=7, psrSpan=8,
//          psrFigure=9, psrTable=10, psrTR=11, psrTH=12, psrTD=13,
//          psrL=14, psrLI=15, psrLbl=16, psrLBody=17,
//          psrTHead=18, psrTBody=19, psrTFoot=20, psrTHRow=21
// TPdfStructRole(Level) for heading Level 1..6 gives psrH1..psrH6
// New roles are appended at the end: TPdfStructRole(Level) and the
// dckBeginTR logic of mormot.pdf.report depend on the existing ordinals
```

`psrDocument`, `psrTable`, `psrTR`, `psrL`, `psrLI`, `psrTHead`, `psrTBody`
and `psrTFoot` are containers (`PDF_STRUCT_CONTAINER`): they group kids only
and own no marked-content region, so `BeginStructContent` writes no `BDC`
for them.

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
  Doc.Canvas.BeginStructContent(psrTHead);
    Doc.Canvas.BeginStructContent(psrTR);
      Doc.Canvas.BeginStructContent(psrTH); Doc.Canvas.TextOut(...); Doc.Canvas.EndStructContent;
    Doc.Canvas.EndStructContent;
  Doc.Canvas.EndStructContent;
  Doc.Canvas.BeginStructContent(psrTBody);
    Doc.Canvas.BeginStructContent(psrTR);
      Doc.Canvas.BeginStructContent(psrTD); Doc.Canvas.TextOut(...); Doc.Canvas.EndStructContent;
    Doc.Canvas.EndStructContent;
  Doc.Canvas.EndStructContent;
Doc.Canvas.EndStructContent;
```

`BeginStructContent(ARole, AAltText)` — `AAltText` is optional (default ''); when given it is written as `/Alt`, whatever the role (PDF/UA needs it on a `Figure`). No-op when `Tagged = false`.

`/Alt` is emitted **twice**, and both are PDF strings — a WinAnsi literal in parenthesis, or `<FEFF…>` UTF-16BE outside WinAnsi:

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
sentence with inline styling becomes one `P`:

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
- Every `TH` gets `/A <</O/Table/Scope/Column>>`; a `psrTHRow` element
  (also `/S /TH`) gets `/A <</O/Table/Scope/Row>>`. The role is appended to
  `TPdfStructRole` instead of a scope parameter on `BeginStructContent`, so
  it passes the bridge and `TGDIPages` unchanged
- **Low-level API, caller's duties:** PDF/UA wants one bookmark per heading. Create the document with `AUseOutlines = true` and call `CreateOutline(Title, Level, TopPosition)` after each heading (`TopPosition` in PDF points from the page bottom); the engine cannot do it for you, because `BeginStructContent(psrHx)` never sees the heading text. `TGDIPages` does it itself. Text drawn inside a `Figure` is part of the image: a reader gets the `/Alt` instead, so the `/Alt` has to describe that text too. PAC 2024 gives the hint "Possibly inappropriate use of figure structure element" on every Figure - path or image, with or without text or `/BBox` - so it is accepted (ROADMAP W-1)
- A `Figure` on one page gets `/A <</O/Layout/BBox[l b r t]>>`. `TPdfCanvas` collects it from the path points (widened by half the line width), from `TextOut`/`TextOutW` (width from the font engine; descent approximated as ¼ size) and from `DrawXObject`. Points drawn under a `ConcatToCTM` that is still active are ignored, because they are not in page space
- **Artifacts:** a path object (`m l c v y re` … paint/`n`) or an image `Do` drawn while no struct region is open is wrapped in `/Artifact BMC … EMC` automatically. Inside a region (e.g. `Figure`) it stays real content. For other skipped content, e.g. a repeated table header or a running page header, use `Canvas.BeginArtifact`/`EndArtifact` (also on `TPdfDocumentVcl`). Do not open a struct element inside it: `BeginArtifact` inside a region and an unmatched `EndArtifact` raise `EPdfInvalidOperation`

### High-Level: TPdfDocumentVcl wrapper

```pascal
Doc.BeginStructContent(psrH2);  // delegates to Canvas.BeginStructContent
Doc.EndStructContent;            // delegates to Canvas.EndStructContent
// same delegation for BeginStructGroup, ContinueStructContent,
// SuspendStructContent, LastStructContent, ResumeStructContent,
// BeginArtifact and EndArtifact
```

### TGDIPages integration

```pascal
// In mormot.pdf.report.pas — a report program uses this unit only
Report.ExportPdfTagged   := True;    // default False — set BEFORE drawing:
                                     // it forces ExportPdfEmbeddedTTF / clears
                                     // ExportPdfStandardFonts, and those decide
                                     // which metrics the layout is measured with
                                     // (raises EPdfReport, an ESynException,
                                     // once a page exists)
Report.ExportPdfLanguage := 'en';    // default 'en'
// then call Report.ExportPdfStream as usual
```

`RenderPageToCanvas` wraps drawing commands with struct content via `fActivePdfDoc: TPdfDocumentVcl` (details: `report-engine.md`):
- `dckDrawText`: heading level → `psrH1..psrH6`; in a header row → `psrTH`; a row-header cell (`RowHeader`) → `psrTHRow`; other cells → `psrTD`; in a list item → `psrLBody`; otherwise → `psrP`. An inline line opens its element with `BeginStructGroup`, each run adding a region or a `Span`
- `dckHeading`: `psrH1..psrH6`
- `dckDrawBitmap`: `psrFigure`
- `dckBeginTable`/`dckEndTable`: opens/closes `psrTable`, `dckEndTable` also the open row group
- `dckBeginTR`/`dckEndTR`: `Color` is the row kind - 0 data, 1 header, 2 repeated header, 3 footer. A row opens its group first (`psrTHead` for 1, `psrTFoot` for 3, `psrTBody` otherwise; a change of group closes the previous one), then `psrTR`. Rows 1 and 2 hold `psrTH` cells. A repeated header (2) is an artifact and opens no struct element
- `dckBeginList`/`dckBeginLI` and their ends: `psrL`, `psrLI`

---

## PDF Encryption

Requires compile-time flag `USE_PDFSECURITY`.

```pascal
uses mormot.pdf;

var Enc: TPdfEncryption;
// RC4-40 (PDF 1.3), RC4-128 (PDF 1.4), AES-128-CBC (PDF 1.6),
// AES-256-CBC (PDF 1.7 + Adobe extension level 8):
Enc := TPdfEncryption.New(
  elAES_128,             // TPdfEncryptionLevel: elNone, elRC4_40, elRC4_128, elAES_128, elAES_256
  'user-pass',           // user password ('' = no open-doc password): RC4 and AES-128
                         // max 32 Latin-1 chars, AES-256 UTF-8 cut at 127 bytes
  'owner-pass',          // owner password (must be non-empty)
  PDF_PERMISSION_NOMODIF // TPdfEncryptionPermissions
);
Doc := TPdfDocument.Create(false, 0, pdfaNone, Enc);
// ...
```

The `TPdfEncryption` object is owned by `TPdfDocument` after passing to
constructor. PDF/A forbids encryption: a PDF/A level with an encryption
raises `EPdfInvalidOperation` (`TestPdfAWithEncryptionRaises`). PDF/UA-1
(7.16) needs `/P` bit 10, `epContentExtraction`: `Tagged := true` raises
`EPdfInvalidOperation` without it - write `PDF_PERMISSION_NOCOPY +
[epContentExtraction]`, copying stays refused (bit 5). RC4-40 (R=2) always
sets bit 10 (`TestTaggedEncryptionNeedsAccessibility`). The check sits in
`SetTagged` alone: the encryption is fixed at `Create`, `fTagged` set nowhere
else.

| Level | Class | PDF version | Cipher | Key derivation |
|---|---|---|---|---|
| `elRC4_40` | `TPdfEncryptionRC4MD5` | 1.3+ | RC4-40 | MD5 |
| `elRC4_128` | `TPdfEncryptionRC4MD5` | 1.4+ | RC4-128 | MD5 (50 iter) |
| `elAES_128` | `TPdfEncryptionAES128` | 1.6+ | AES-128-CBC | MD5 (same as RC4-128); IV prepended per object |
| `elAES_256` | `TPdfEncryptionAES256` | 1.7 + ADBE ext. 8 | AES-256-CBC | SHA-256/384/512 (Algorithm 2.B); random file key wrapped in `/UE` `/OE`; IV prepended per object |

AES-256 (R=6) encrypts every string and stream with the 32-byte file key
itself (no per-object key, `/CFM /AESV3`); `/Perms` holds `/P` again,
encrypted, `T` for encrypted metadata. Its passwords are UTF-8, cut at 127
bytes, **without SASLprep** (ISO 32000-2 asks for it): beyond ASCII, a
reader that applies SASLprep opens the file only when the password was
given already prepared (NFKC alone is not enough: SASLprep also drops
characters such as the soft hyphen). `TestEncryptionAES256` checks
`Hash2B` against vectors of pypdf, recovers the file key from `/UE` and
`/OE` with both passwords, and decrypts with it; checked once with pypdf
too: an empty user password, one beyond ASCII, one beyond 127 bytes.
With encryption no object stream is written (`ToCrossReference`), the xref
stream stays in clear.

AES output size: `16 (IV) + (N div 16 + 1) * 16` bytes (PKCS#7 adds a
whole block when N is a multiple of 16) per encrypted object/string. The stream `Length` attribute is updated automatically before writing.

A string is encrypted whole: a text string beyond WinAnsi as its byte order
mark and UTF-16BE together (`TPdfWrite.AddUnicodeHexString`). A string
inside a content stream is not encrypted on its own - the stream is, as a
whole - so `AddUnicodeHex` and `AddEscape` never encrypt; `AddEscapeContent`
does, for an object's string. With RC4 every string of one object starts
its key stream again (`TestEncryptedUnicodeString` relies on it).

---

## Font Strategy

| Mode | Property | Font names | Embedding |
|---|---|---|---|
| Standard Type1 | `StandardFontsReplace := True` | Helvetica, Times, Courier | none |
| TrueType | `EmbeddedTTF := True` | OS-specific (see below) | subset (`EmbeddedWholeTtf = False`, default) or the whole face — see `fonts.md` §3 |

**`Tagged := True` picks the mode for you:** it sets `EmbeddedTTF` and clears
`StandardFontsReplace`, because PDF/UA allows no non-embedded base-14 face. It
sets `EmbeddedWholeTtf := not PdfCanSubsetRetainingGids`: the faces are subset
with retained glyph IDs, which keeps `/ToUnicode` valid — by hb-subset on
Linux/macOS, by `CreateFontPackage` with a glyph keep list on Windows. Only
without a subsetter (no `libharfbuzz-subset`, no `FontSub.dll`) is the whole
face embedded. Set `EmbeddedWholeTtf := True` afterwards to force the whole
face. `Tagged` raises `ESynException` when set after the first `AddPage`,
and `EPdfInvalidOperation` with an encryption that refuses
`epContentExtraction` (PDF Encryption).
PDF/A and tagged documents get a `/ToUnicode` CMap for every font, the
WinAnsi one included. Resolve font names with `GetPdfFonts` *after* setting
`Tagged`.

Platform-specific TTF fonts via `GetPdfFonts(Embedded, SansFont, SerifFont, MonoFont)`
in `mormot.pdf` (constants `PDF_FONT_TTF_SANS/SERIF/MONO`; `Embedded = false`
gives the `PDF_FONT_STD_*` names) — layer 1, no report engine needed.
`GetReportFonts` and `REPORT_FONT_*` in `mormot.pdf.report` are aliases of
them:
- Windows: Calibri, Cambria, Consolas
- macOS: Trebuchet MS, Georgia, Andale Mono
- Android: Roboto, Noto Serif, Droid Sans Mono
- Linux: Liberation Sans, Liberation Serif, Liberation Mono

Standard constants in `mormot.pdf.pas`: `PDF_FONT_STD_SANS` = 'Helvetica', `PDF_FONT_STD_SERIF` = 'Times', `PDF_FONT_STD_MONO` = 'Courier'.

**Calling `TPdfCanvas.SetFont` directly with a non-Latin face:** pass
`DEFAULT_CHARSET` (1) as `ACharSet`, as `TPdfVclCanvas` does. Without it,
Windows falls back to the document charset, and GDI's mapper may select
another face than the one asked for — see `fonts.md` §10. The tests use `PDF_DEFAULT_CHARSET` from
`test_pdf_subset`, which needs no `{$ifdef}`.

`FontFallBackName` (TPdfDocument property): the face that draws glyphs the
current face lacks, while `UseFontFallBack` is true (the default).

**CFF faces** (the CJK faces of macOS and Linux): all their text goes
through the Type0 font (an unembedded name-keyed face keeps its Latin text in
the simple font), a CID-keyed one is embedded as its bare CFF
(`/CIDFontType0C`, PDF 1.3), a name-keyed one as an OpenType font file -
`FileFormat` is raised to `pdf16` for it, or the catalog gets `/Version
/1.6` once a lower header was streamed (`HeaderFileFormat`);
`EPdfInvalidOperation` under PDF/A-1. The CFF
reader is public: `PdfCffParse(Data, Len, Info)` / `PdfFaceCffInfo(Face,
Info)` give `TPdfCffInfo` (`Kind` pcNone/pcNameKeyed/pcCidKeyed/pcInvalid,
`GlyphCount`, `FontName`, `Registry`/`Ordering`/`Supplement`, `Cid[]`).
Details: `fonts.md` "CFF Faces: Type0 Only"

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

This conversion happens automatically in `TPdfVclCanvas`, at `ScreenLogPixels` instead of 96 when that was changed before the first page. In direct `TPdfCanvas` mode, convert manually.
