# Call Graph — mORMot2 PDF Framework

This document traces all major call paths through the framework, from application code down to platform APIs and the PDF byte stream.
Routines are named by their unit: `mormot.pdf` (layer 1), `mormot.pdf.canvas` (the TCanvas bridge, `TBitmap` images, EMF),
`mormot.pdf.report` and `mormot.pdf.report.preview` (layer 3); the font interfaces come from mORMot2's `mormot.lib.core`,
their backends from `mormot.lib.uniscribe`, `mormot.lib.freetype` and `mormot.lib.harfbuzz`.

---

## Layer Overview

```
┌──────────────────────────────────────────────────────────────────┐
│  Application Code                                                │
├─────────────────┬─────────────────────────┬──────────────────────┤
│  TGDIPages      │  TPdfDocumentVcl        │  TPdfDocument        │
│  (report)       │  (TCanvas bridge)       │  (direct PDF)        │
├─────────────────┴─────────────────────────┤                      │
│  TPdfVclCanvas (TCanvas subclass)         │                      │
├───────────────────────────────────────────┴──────────────────────┤
│  TPdfCanvas  /  TPdfDocument  /  TPdfWrite                       │
├──────────────────────────────────────────────────────────────────┤
│  mormot.lib.core: IFontProvider → IFontFace, IFontEnumerator     │
│  optional: IFontShaper (+ IFontRunShaper), IFontSubsetter        │
├────────────────────────────────┬─────────────────────────────────┤
│  mormot.lib.uniscribe          │  mormot.lib.freetype: faces     │
│  GDI faces, Uniscribe shaper,  │  mormot.lib.harfbuzz: shaper,   │
│  FontSub subsetter (Windows)   │  hb-subset (Linux/macOS)        │
└────────────────────────────────┴─────────────────────────────────┘
```

---

## Path 1 — Direct PDF API (TPdfDocument)

Lowest-level path. All coordinates in PDF points; Y=0 at bottom of page.

```
Application
  TPdfDocument.Create(UseOutlines, CodePage, PdfA, [Encryption])
  │  CodePage 0 → LCIDToCodePage (Windows: the locale's ANSI code page;
  │    POSIX: CP_UTF8); fCharSet := CodePageToCharSet(code page)
  │  raises ESynException if no font backend is registered (libfreetype)
  │  FontEnumerator.EnumTrueTypeFonts(fTrueTypeFonts), sorted
  │  fFontFallBackIndex: Arial Unicode MS, Lucida Sans Unicode, any
  │    "Unicode" face, DejaVu Sans, Liberation Sans, FreeSans, the first face
  │  → NewDoc
  │
  TPdfDocument.NewDoc                  (also called by the PdfA setter)
  │  clears pages, bookmarks, struct tree; new xref, trailer, catalog, info
  │  UseOptionalContent: /OCProperties, FileFormat >= pdf15
  │  PdfA: FileFormat >= pdf17 (A-2, A-3) or pdf14 (A-1), OutputIntent with
  │    the sRGB profile, /Metadata stream; encryption → EPdfInvalidOperation
  │  PdfA or encryption: /ID from random bytes; Encryption.AttachDocument
  │
  TPdfDocument.AddPage → TPdfPage
  │  page dictionary of DefaultPageWidth × DefaultPageHeight, resources,
  │    content stream
  │  fCanvas.SetPage(page) → Doc.Canvas draws on this page
  │  Tagged: /StructParents, first page sets up the catalog (Path 10)
  │
  TPdfCanvas.SetFont(Name, Size, Style)          → Path 4a
  │  returns TPdfFontTrueType (WinAnsi instance), or TPdfFontType1 for a
  │  base-14 name when StandardFontsReplace
  │
  TPdfCanvas.TextOut(X, Y, Text: PdfString) / TextOutW(X, Y, PWideChar)
  │  'BT x y Td' + ShowText + 'ET'
  │  ShowText(PdfString): WinAnsi text the face has → '(…) Tj' through
  │    AddEscapeText; else AddToUnicodeHexText (TrueType) or '<hex> Tj'
  │  ShowText(PWideChar) → TPdfWrite.AddUnicodeHexText   → Paths 4b, 4c
  │
  TPdfCanvas.Rectangle / MoveTo / LineTo / Fill / Stroke …
  │  TPdfWrite: operators into the page content stream
  │
  TPdfDocument.CreateOrGetImage(Pixels, DrawAt, ClipRc)   → Path 5
  │  creates a TPdfImage; reuses one of the same pixels (CRC32C lanes)
  │
  TPdfDocument.SaveToFile(FileName): boolean   ← false on any exception
  TPdfDocument.SaveToStream(Stream)  ← raises if no page was added
     SaveToStreamDirectBegin: '%PDF-1.x' header (from FileFormat); PDF/A
       writes its XMP packet here
     SaveToStreamDirectEnd: outlines, fonts (Path 4d), struct tree (Path 10),
       pending objects, xref
     HeaderFileFormat >= pdf15 (the version the header was written with, not
       a FileFormat raised after it): TPdfTrailer.ToCrossReference → xref
       stream + object streams
     Compression (TPdfStream.InternalWriteTo): cmFlateDecode → CompressMem
       level 7; a stream under 100 bytes is not compressed
     Encryption (USE_PDFSECURITY), per stream after compression:
       TPdfEncryptionRC4MD5 → RC4-40/RC4-128, in place (same size)
       TPdfEncryptionAES128 → AES-128-CBC (Path 8):
         encLen := GetEncryptedSize(buflen) = 16 (IV) + ((buflen div 16)+1)*16
         /Length := encLen BEFORE the dictionary is written
         separate tmpEnc buffer; EncodeBuffer writes IV||ciphertext
       TPdfEncryptionAES256 → AES-256-CBC with the file key itself, no
         per-object key: TAesCbc.EncryptPkcs7Buffer (IV at the beginning),
         the same sizes as AES-128 (Path 8)
```

---

## Path 2 — VCL Canvas Bridge (TPdfDocumentVcl)

`mormot.pdf.canvas`. Adds a TCanvas-compatible wrapper. Pixel coordinates, Y=0 at top.

```
Application
  TPdfDocumentVcl.Create(...)          // inherits TPdfDocument.Create
  │  Windows: ScreenLogPixels := GdiScreenLogPixels (else 96)
  │
  TPdfDocumentVcl.AddPage
  │  inherited AddPage → new TPdfPage, Doc.Canvas on it
  │  first page: creates the TPdfVclCanvas(Self, Canvas); later pages:
  │    VclCanvas.ResetState - one canvas object for the whole document
  │
  TPdfDocumentVcl.VclCanvas → TPdfVclCanvas
  │  nil before the first AddPage
  │  Delphi 7: draw through a TPdfVclCanvas reference (static TCanvas methods)
  │
  TPdfVclCanvas.TextOut(X, Y, Text)
  │  TextOutFrac → StringToSynUnicode (TextOutUtf8: Utf8ToSynUnicode)
  │  → TextOutDecoded: SyncFont (Path 4e), then
  │    X_pdf = (X + OriginX) * ScaleX              ScaleX = 72 / ScreenLogPixels
  │    Y_pdf = PageH - (Y + Font.Size + OriginY) * ScaleY   (Y-flip, baseline)
  │  → TPdfCanvas.TextOutW(X_pdf, Y_pdf, W)       → Path 1
  │
  TPdfVclCanvas.Rectangle(X1,Y1,X2,Y2)
  │  SyncPen / SyncBrush → TPdfCanvas.Rectangle → Fill / Stroke / FillStroke
  │
  TPdfVclCanvas.Draw(X, Y, Graphic)
  TPdfVclCanvas.StretchDraw(Rect, Graphic)
  │  a graphic other than TBitmap is drawn into a temporary TBitmap first
  │  → CreateOrGetBitmapImage(fPdfDoc, Bitmap) → image name (Path 5)
  │  → TPdfCanvas.DrawXObject(x, y, w, h, name)
  │
  TPdfDocumentVcl.SaveToFile / SaveToStream
     → TPdfDocument.SaveToFile / SaveToStream (see Path 1)
```

---

## Path 3 — Report Engine (TGDIPages)

Highest-level path. Records commands, renders lazily. 1/100mm coordinates.

### 3a — Command Recording

```
Application
  TGDIPages.Create(nil)
  │  InitializeFormatRegistry (H1–H6, P, Code, etc. → TReportFormat)
  │  defaults: 10 pt sans, margins 2000 (20 mm), A4 portrait,
  │    ExportPdfEmbeddedTTF and ExportPdfStandardFonts true, UseOutlines false
  │  no page yet
  │
  TGDIPages.NewPage
  │  closes an open list unless a list item is being recorded
  │  (fRecordingListItem); appends a TPageData with this page's size and
  │  margins to fPages; resets CurrentY and CurrentX
  │
  TGDIPages.SetFont / FontStyle
  │  updates internal font state (no canvas call yet)
  │
  TGDIPages.DrawHeading(Level, Title)
  │  format 'H1'..'H6' from the registry; line height measured in it
  │  heading + 1/3 of its font size does not fit → NewPage
  │  records THeadingInfo (level, title, page, Y) in fHeadings - always;
  │    the export turns them into outlines (3c)
  │  RecordWrappedText with fCurrentHeadingLevel = Level → one
  │    TDrawCommand(dckDrawText, HeadingLevel) per line
  │  (dckHeading is still rendered, but no method records it)
  │
  TGDIPages.DrawParagraph / DrawText / DrawStrong / DrawEm / DrawCode …
  │  word-wrap logic → one TDrawCommand(dckDrawText) per line segment
  │  EmitTextCmd: measures the width once, pre-adjusts X for the alignment
  │  CurrentY advances by line height
  │
  TGDIPages.BeginTable / DrawTableHeader / DrawTableRow / DrawTableFooter / EndTable
  │  BeginTable(TTableLayout):
  │    raises EPdfReport if a table is in progress
  │    SaveLayout  ← balanced by EndTable RestoreLayout
  │    copies Layout.ColumnWidths/ColumnAligns into fTableColWidths/fTableColAligns
  │      (missing aligns: tcaLeft); empty ColumnWidths → no cell is drawn
  │    TDrawCommand(dckBeginTable)  ← opens Table struct element
  │  DrawTableHeader:
  │    saves Headers[] into fTableSavedHeaders  ← repeated on a page break
  │    → DrawTableStyledRow(kind 1, or 2 when repeated, Header* style)
  │  DrawTableFooter (a totals line):
  │    breaks the page first if it does not fit (with the header repeated)
  │    → DrawTableStyledRow(kind 3, Footer* style, else the header's)
  │  DrawTableStyledRow:
  │    TDrawCommand(dckBeginTR, Color = kind)  ← 1 header, 2 repeated
  │                                              header, 3 footer
  │    SaveLayout / apply the row's font / cell drawing / RestoreLayout
  │    cell height = LineHeightMM + CELL_PADDING (CELL_PADDING = 200 = 2mm)
  │    per cell: TDrawCommand(dckFillRect, background)
  │              TDrawCommand(dckDrawRect, Layout.GridColor, LineWidth 1)
  │              EmitTextCmd → TDrawCommand(dckDrawText)
  │                (footer with FooterRowHeader: first cell RowHeader)
  │    TDrawCommand(dckEndTR)
  │  DrawTableRow:
  │    RowHeight := LineHeightMM + CELL_PADDING  ← measured BEFORE SaveLayout
  │    if fCurrentY + RowHeight > fPageHeight:
  │      ForceNewPage (NewPage, fCurrentY := 0)
  │      if fTableSavedHeaders <> nil: DrawTableHeader(fTableSavedHeaders)
  │        as kind 2
  │    TDrawCommand(dckBeginTR, Color=0)        ← data row marker
  │    SaveLayout / (apply BodyFontStyle) / cell drawing / RestoreLayout
  │    per cell: TDrawCommand(dckFillRect, BodyBkColor or AlternateRowColor)
  │              TDrawCommand(dckDrawRect, Layout.GridColor, LineWidth 1)
  │              EmitTextCmd → TDrawCommand(dckDrawText)
  │    Inc(fCurrentY, RowHeight) / Inc(fTableRowIndex)
  │    TDrawCommand(dckEndTR)
  │  EndTable:
  │    fTableSavedHeaders := nil; TDrawCommand(dckEndTable)
  │    RestoreLayout  ← restores state from BeginTable SaveLayout
  │
  TGDIPages.DrawLine / DrawFilledRect
  │  TDrawCommand(dckDrawLine / dckFillRect)
  │
  TGDIPages.EndDoc
     closes an open list; seals the recording (fCurrCmds := nil);
     nothing rendered yet
```

`SaveLayout`/`RestoreLayout` save `fFontName`/`fFontSize`/`fFontStyle`/`fTextColor` only —
`fCurrentY` is NOT saved or restored.

### 3b — Preview Path

```
ShowReportPreview(Report)                       (mormot.pdf.report.preview)
  │  TReportPreview.Show: modal LCL form, scroll box, paint box
  │  page size fW × fH: the first page at 96 DPI
  │
  TReportPreview.DoPaint (on each repaint, the current page)
  │  ZW := Round(fW * fZoom)   ← zoomed pixel dimensions
  │  ZH := Round(fH * fZoom)
  │  TGDIPages.RenderPageToCanvas(PaintBox.Canvas, CurrPage, ZW, ZH)   ← SourceDPI=0
  │  │  scale: DestWidth / full page width (page + margins), same for Y;
  │  │         offset = left/top margin
  │  │  FontScale: BaseHeight := MMToPixels(full page height, ACanvas.Font.PixelsPerInch)
  │  │             FontScale  := ZH / BaseHeight   ← equals fZoom at 96 DPI
  │  │  white background (FillRect, not on the PDF bridge)
  │  │  header: Font.Size := Round(fFontSize * FontScale); {#}/{total} substituted
  │  │  iterates TPageData.Commands[]
  │  │  State: InTableRow, InHeaderRow, InListItem (all false at start)
  │  │  per command:
  │  │    dckDrawText   → ApplyFont (Font.Size := Round(Cmd.FontSize * FontScale))
  │  │                    + EmitCanvasText → ACanvas.TextOut
  │  │    dckDrawLine   → Pen.Color + Pen.Width := Max(1,LineWidth) + MoveTo/LineTo
  │  │    dckFillRect   → Brush.* + Pen.Style=psClear + Rectangle (not FillRect!); Pen.Style restored
  │  │    dckDrawRect   → Pen.Color + Pen.Width := Max(1,LineWidth) + Brush.Style=bsClear + Rectangle
  │  │                    NOTE: Pen.Width must be set explicitly; without it the pen from a prior
  │  │                    dckDrawLine (e.g. thick decorative line) is inherited → table borders appear thick
  │  │    dckDrawBitmap → ACanvas.StretchDraw
  │  │    dckBeginTable/dckEndTable → (visual: no-op; struct: see 3c)
  │  │    dckBeginTR    → InHeaderRow := Color in [1, 2]; InTableRow := true
  │  │    dckEndTR      → InTableRow := false; InHeaderRow := false
  │  │    dckBeginLI/dckEndLI → InListItem
  │  │    dckHeading    → Font.Size := Round(Format.FontSize * FontScale) + TextOut
  │  │  footer: as the header, below the page body
  │  └─ ACanvas here is the screen TCanvas
```

### 3c — PDF Export Path

```
TGDIPages.ExportPdfStream(aDest: TStream; aRaiseException = false): boolean
  │  no page → false (EPdfReport with aRaiseException)
  │
  │  Doc := TPdfDocumentVcl.Create(UseOutlines, 0, ExportPdfLevel)
  │  Doc.Info: Title (tagged without one: the first H1), Creator
  │    (ExportPdfCreator or the program name), Author, Subject
  │  Doc.FileFormat            := ExportPdfFileFormat   (default pdf13; set pdf17 for ISO 32000-1;
  │                               SetFileFormat keeps the floor of the PDF/A level)
  │  if ExportPdfTagged:
  │    Doc.Tagged  := True          ← raises FileFormat to pdf17 AND picks the
  │                                   PDF/UA font mode (see Path 10)
  │    Doc.DefaultLanguage := ExportPdfLanguage
  │  Doc.EmbeddedTtf           := ExportPdfEmbeddedTTF
  │  Doc.StandardFontsReplace  := ExportPdfStandardFonts
  │    ↑ assigned after Tagged, and SetExportPdfTagged has already aligned them,
  │      so the two cannot contradict each other
  │  Doc.PdfAMetadaExtension := ExportPdfMetadataExtension
  │    ↑ before SaveToStreamDirectBegin: PDF/A writes its XMP packet there
  │  Doc.Root.PageMode := ExportPdfPageMode   (unless pmUseNone)
  │  Doc.SaveToStreamDirectBegin(aDest)
  │
  │  for PageIndex := 0 to PageCount-1 do
  │    Doc.DefaultPageWidth/Height := this page with its margins, in points
  │    Doc.AddPage
  │    fActivePdfDoc := Doc if ExportPdfTagged, else nil
  │      ← RenderPageToCanvas tags only through it
  │    TGDIPages.RenderPageToCanvas(Doc.VclCanvas, PageIndex, W, H,
  │                                 Doc.ScreenLogPixels)
  │    │  W, H: the full page in pixels at ScreenLogPixels; SourceDPI the same
  │    │    → FontScale = 1, exact coordinate match
  │    │  text through TPdfVclCanvas.TextOutUtf8 at fractional positions
  │    │    (EmitCanvasText), not snapped to the pixel grid
  │    │  header and footer: BeginArtifact / EndArtifact
  │    │  fActivePdfDoc <> nil → struct content wrapping enabled:
  │    │    any command but dckDrawText ends the open text block
  │    │    dckDrawText:  Cmd.BlockId = open block? → keep region open (or
  │    │                  ResumeStructContent after a page break)
  │    │                  else BeginStructContent(psrH1..6 / psrTH / psrTHRow /
  │    │                                          psrTD / psrLBody / psrP)
  │    │                  Cmd.IsInline → BeginStructGroup instead, then per run:
  │    │                    isPlain  → ContinueStructContent (region on the P)
  │    │                    styled   → SuspendStructContent + psrSpan kid
  │    │    dckDrawBitmap: BeginStructContent(psrFigure)
  │    │    dckBeginTable: BeginStructContent(psrTable); no row group open
  │    │    dckEndTable:   close the open row group, EndStructContent (Table)
  │    │    dckBeginTR:    row group and psrTR, or an artifact (Path 10)
  │    │    dckEndTR:      EndStructContent, or EndArtifact
  │    │    dckBeginList/dckBeginLI: BeginStructContent(psrL / psrLI)
  │    │    dckHeading:    BeginStructContent(psrH1..H6)
  │    │  ACanvas calls → TPdfVclCanvas calls → TPdfCanvas → TPdfWrite
  │    └─ a block still open at the page end is closed and kept for Resume
  │    fActivePdfDoc := nil
  │    Doc.SaveToStreamDirectPageFlush
  │
  │  AddHeadingsToOutline(Doc)   ← fHeadings → Doc.CreateOutline (Path 7)
  │  Doc.CreateFileAttachmentFrom(...)  per AddExportPdfAttachment entry
  │  Doc.SaveToStreamDirectEnd    ← fonts, StructTreeRoot + ParentTree,
  │                                 catalog (/AF, /EmbeddedFiles), xref
  └─ true on success; an exception → false, or re-raised with aRaiseException

TGDIPages.ExportPDF(FileName, Protect, Encrypt, Title, Company)
  Protect or Encrypt → EPdfReport (not implemented)
  ExportPdfStream into memory (raising), then the file is written
```

### 3d — Print Path

```
PrintReport(Report, From = 0, To_ = all)        (mormot.pdf.report.preview)
  │  no dialog: prints on the LCL's current printer (Printers.Printer); the range is clipped
  │  Printer.BeginDoc
  │  for PageIndex := From to To_ do
  │    Printer.NewPage  (except first page)
  │    TGDIPages.RenderPageToCanvas(Printer.Canvas, PageIndex, PageWidth, PageHeight)   ← SourceDPI=0
  └─ Printer.EndDoc
```

---

## Path 4 — Font Lifecycle (Registration → Rendering → Serialization)

Full internal detail in `.claude/skills/fonts.md`.

### 4a — Font Registration (first use of a TrueType font)

```
TPdfCanvas.SetFont('Calibri', 12, [pfsBold], ACharSet = -1)   (mormot.pdf)
│
│  StandardFontsReplace and a base-14 name (Helvetica/Arial, Times, Courier):
│    TPdfFontType1, registered once per name → done
│
│  face index: TPdfDocument.GetTrueTypeFontIndex('Calibri')
│    binary search in fTrueTypeFonts (enumerated and sorted by
│    TPdfDocument.Create; AddTrueTypeFont adds a registered face)
│    not found: fixed pitch → Courier New; a standard name → its Windows
│    face; else the fallback face, Arial, DejaVu Sans, Liberation Sans, the
│    first face; none at all → nil
│
│  ACharSet resolution:
│    if ACharSet < 0: ACharSet := fDoc.CharSet
│    fDoc.CharSet = CodePageToCharSet(code page of TPdfDocument.Create)
│    → ANSI_CHARSET (0) on Western Windows and on Unix/macOS (CP_UTF8
│      maps to ANSI_CHARSET)
│    → TPdfVclCanvas.SyncFont passes Font.Charset instead (Path 4e)
│
TPdfDocument.GetRegisteredTrueTypeFont(index + 1, Style, CharSet)
│  searches fFontList for a WinAnsi TPdfFontTrueType of that face, style
│  and charset - the charset is part of the key
│  found: return it
│
│  TFontRequest: FaceName, Height = -1000, Weight (FW_BOLD/FW_NORMAL),
│    Italic, CharSet   ← CharSet decides the GDI face (fonts.md,
│                        "lfCharSet Derivation Chain")
│  TPdfFontTrueType.Create(Doc, index, Style, Request, nil)  (WinAnsi instance)
│  │  fFace := FontProvider.CreateFace(Request)   (mormot.lib.core)
│  │    none → TPdfNoFace (no metrics)
│  │    (the Windows overload taking a TLogFontW: GdiCreateFace(LOGFONT))
│  │  name: TtfFontPostcriptName; PdfFaceCffInfo → fInternal for a CFF face
│  │    or one without a (3,1)/(3,0) cmap (Type0Only)
│  │  fFace.GetTextMetrics / GetOutlineMetrics / GetCharAbcWidths(32, 255)
│  │    → fWinAnsiWidth, fDefaultWidth (space advance), FontDescriptor
│  └─ fDoc.RegisterFont → fFontList
│
│  Note: UnicodeFont (fUnicode=true) is created lazily by CreateAssociatedUnicodeFont
│        on the first character drawn as a glyph — NOT here; it shares fFace.
│        A Type0Only face gets it at once: SetPdfFont creates it and draws
│        through it before any character.
│        CMAP loading (TPdfTtf.Create) happens at that point (see Path 4e).
│
└─ SetPdfFont(font, size); returns TPdfFontTrueType (WinAnsi instance)
```

### 4b — Text Rendering — WinAnsi / Latin Path (`TPdfWrite.AddUnicodeHexTextNoUniScribe`)

```
TPdfVclCanvas.TextOut(X, Y, S)
  StringToSynUnicode → W   (TextOutUtf8: Utf8ToSynUnicode)
  → TPdfCanvas.TextOutW(X, Y, W)
      → TPdfCanvas.ShowText(PW) → TPdfWrite.AddUnicodeHexText(PW, Len, false, Canvas)

TPdfWrite.AddUnicodeHexText:
  ttf := the page font if TrueType, else nil
  shaped := UseUniscribe and ttf present and AddUnicodeHexTextShaped(…)   [path 4c]
  not shaped → AddUnicodeHexTextNoUniScribe(PW, ttf, NextLine, Canvas)

TPdfWrite.AddUnicodeHexTextNoUniScribe:
  no TrueType font: a character outside WinAnsi is written as '?'
  Ttf := Ttf.WinAnsiFont
  every character goes to the glyph branch when the face is a symbol font
  or Type0Only (a CFF face, fonts.md "CFF Faces: Type0 Only")
  loop over the text:
    run of WinAnsi characters the face has (WideCharToWinAnsi > 0, not
    WinAnsiMissing):
      SetPdfFont(WinAnsiFont); '(' … ') Tj'   (\ before ( ) \; U+00A0 as space)
      Ttf.AddUsedWinAnsiChar(ch)              ← char marked as used
    run of other characters (one space inside stays in the run):
      per character: AddGlyphFromChar(ch, Canvas, Ttf, @NextLine)
      AddGlyphFlush → '> Tj' (or '>] TJ')

TPdfWrite.AddGlyphFromChar(ch, Canvas, Ttf, NextLine):
  idx := Ttf.FindOrAddUsedWideChar(ch)      ← lazy Unicode instance, CMAP (4e)
  Glyph := Ttf.fUsedWide[idx].Glyph
  glyph 0 of a default-ignorable code point → nothing drawn
  glyph 0 and font fallback on → the fallback font (Canvas.SetFont with a
    forced index, page font kept), its glyph; a font change flushes the string
  glyph 0 under PDF/A → EPdfInvalidOperation (no .notdef, ISO 19005-2 6.2.11.8)
  SetPdfFont(fnt.UnicodeFont)
  new string: '<', or '[<' for a Type0Only face with word spacing (each space
    then followed by a TJ adjustment, as Tw applies to code 32 only)
  AddHex4(fnt.GlyphCode(Glyph))             ← the CID of a CID-keyed CFF face,
                                              the glyph index otherwise
```

### 4c — Text Rendering — Uniscribe / HarfBuzz Path (RTL, Complex Scripts)

```
TPdfWrite.AddUnicodeHexText — UseUniscribe gates the one shaper:

  shaped := UseUniscribe and ttf present and
            AddUnicodeHexTextShaped(PW, Len, ttf.WinAnsiFont, NL, Canvas)
    FontShaper.Shape(PW, Len, WinAnsiTtf.fFace.Handle, RightToLeftText, Runs)
      Windows - TUniscribeShaper (mormot.lib.uniscribe):
        ScriptApplyDigitSubstitution; ScriptItemize(PW, Len, state) →
          items[0..count-1], items[count] = end
          RightToLeftText: state.uBidiLevel := 1
        no item fComplex or fRtl → false (Latin: the simple path)
        ScriptLayout(count, levels, VisualToLogical) → visual order
        per item (empty ones skipped), UspShapeItem: ScriptShape(0, psc, ...)
          0                         → fskShaped/fsoDone, zero-width non-
                                      diacritic glyphs left out; no glyph at
                                      all → fskSkip/fsoDone; a kept glyph =
                                      wgDefault (ScriptGetFontProperties) →
                                      fsoMissingGlyphs
          E_OUTOFMEMORY             → fskPlain/fsoFailed
          E_PENDING, NOT_IN_FONT    → again with its own DC holding the font:
                                      0 → as above, else fskPlain/fsoFailed
          any other error           → fskSkip/fsoFailed
        UspDone: DC released, ScriptFreeCache(psc); true
      Linux/macOS - THarfBuzzShaper (mormot.lib.harfbuzz):
        HarfBuzz not loaded, or not RightToLeftText and not
          NeedsShaping(PW, Len) → false
        HbFont: the FreeType face sized to 1000 units per em,
          hb_ft_font_create, no hinting
        HbScriptRuns: script runs (hb_unicode_script, neutrals take the
          script before them)
        per run, HbShapeRun with the whole text as context: direction from
          the script, hb_shape → fskShaped/fsoDone (glyph 0 →
          fsoMissingGlyphs): Glyphs, Advances, Offsets (x), YOffsets (y, not
          drawn yet), Clusters - 1/1000 em; nothing from HarfBuzz →
          fskPlain/fsoFailed
        HbVisualOrder: two-level order, RightToLeftText the base direction
    false, or runs not covering the text / arrays misaligned → not shaped
    MoveToNextLine once if NL
    per run: AddShapedFallback: fsoMissingGlyphs or fskPlain/fsoFailed,
               fallback on and the shaper an IFontRunShaper →
               ShapeRun with the fallback face; fsoDone → AddShapedRun(r,
               fallback), done
             fskPlain or fsoUnknown → AddUnicodeHexTextNoUniScribe(copy + #0)
             fskShaped              → (fsoMissingGlyphs under PDF/A: raise)
                                      AddShapedRun(Run, WinAnsiTtf)
             fskSkip                → nothing

TPdfWrite.AddShapedRun(Run, WinAnsiTtf):   ← the font it was shaped with
  CreateAssociatedUnicodeFont if needed; SetPdfFont(UnicodeFont, size)
  no glyph → done (the font switch only)
  no Advances (Uniscribe): '<' GlyphCode(GetAndMarkGlyphAsUsed(g))… '> Tj'
  Advances (HarfBuzz): for each glyph
      WinAnsiTtf.GetAndMarkGlyphAsUsedWithWidth(Glyph, Advance_1000)
        Step 1: already registered (fUsedWide or fShapedGlyph) → exit
        Step 2: reverse CMAP → FindOrAddUsedCodePoint → exit
          ← hmtx width from TPdfTtf.Create: (int64(hmtx) * 1000) div UPM
        Step 3: AddShapedGlyph with the 'hmtx' width (GlyphHmtxWidth), the
          shaper's advance only if the tables cannot be read
      Widths[i] := UsedWideGlyphWidth(glyph) - the width /W will state
    one Tj, or a TJ where an offset or the hmtx width differs from the
    shaper's advance: HarfBuzz reports the positioned advance (a cursive
    glyph comes back shortened, even x_advance = 0), /W has to state the
    font's own (ISO 14289-1 7.21.5), and the TJ adjustment makes up the
    difference
    every code written as WinAnsiTtf.GlyphCode(g): the CID of a CID-keyed
    CFF face, the glyph index otherwise

  if not shaped:
    → AddUnicodeHexTextNoUniScribe(…)           ← Latin fallback

TPdfFontTrueType.GetAndMarkGlyphAsUsed(glyph) - from AddShapedRun (no
Advances) and from the public TPdfWrite.AddGlyphs (→ AddGlyphsOf with the
page font, the Uniscribe VisAttr filter if given), on the WinAnsi font:
    │  Step 1: already in fUsedWide[] or fShapedGlyph → return immediately
    │  Step 2: reverse CMAP scan in UnicodeFont.fUsedWide[]
    │           found → WinAnsiFont.FindOrAddUsedCodePoint → register in WinAnsi tracking
    │           not found → fall through to Step 3
    │  Step 3: GSUB glyph (Arabic form, ligature), every platform
    │           fFace.GetGlyphAdvance(glyph, w) → advance width
    │             (IFontFace: GDI GetCharABCWidthsI, FreeType FT_Load_Glyph);
    │             failure → fDefaultWidth
    │           AddShapedGlyph(glyph, w) → WinAnsiFont.fShapedGlyph (by glyph ID)
    │           → glyph registered in /W array; no overlap from /DW fallback
    AddHex4(Ttf.WinAnsiFont.GlyphCode(glyph))
  Add('> Tj') if any glyph was kept
```

### 4d — Font Serialization at Save (`TPdfDocument.SaveToStreamDirectEnd`)

```
TPdfDocument.SaveToStream / SaveToFile → SaveToStreamDirectEnd
  outlines saved (UseOutlines)
  TPdfDocument.PrepareFontSubsets                 (runs first)
    exit unless FontSubsetter <> nil (hb-subset on POSIX, FontSub on Windows)
                and not EmbeddedWholeTtf and PdfA not in [pdfa1A, pdfa1B]
                (PDF/A-1 needs a /CIDSet, which is not written)
    for every WinAnsi TPdfFontTrueType that IsEmbedded, and not IsSymbolic
    unless FontSubsetter.SupportsSymbolic (FontSub: yes, hb-subset: no):
      GetFaceData → whole face (fFace.GetFontData, tag 0): FreeType
                    extracts a .ttc face; GDI hands its tables with the
                    collection's offsets, from which FontSub finds the
                    face (TtcFaceIndex) - only GetFaceFile promises a
                    standalone font
      group by face bytes (crc32c + compare) in fFontSubsets[]
        ← Regular + Bold of one .ttc face land in the same entry
      AddToSubsetRequest: Unicodes += fWinAnsiUsed (via WinAnsi table) +
                          fUsedWideChar; Glyphs += fUsedWide[].Glyph +
                          fShapedGlyph (glyphs without a code point)
      fSubsetIndex := entry + 1
    per entry: FontSubsetter.Subset(Face, Request, Font.fFace.Handle) → Subset bytes
               (FontSub: Unicodes via GetGlyphIndicesW, .ttc index from the
                bytes - TtcFaceIndex; platform-backends.md, IFontSubsetter)
               a CID-keyed CFF subset that does not keep the CIDs
                 (PdfSubsetKeepsCids) → failure
               Tag := SubsetTag(Subset): 6 letters from crc32c + '+'
                 (deterministic)
               failure (refused face, error) → Subset = '' → whole face
  for every TrueType font in fFontList:
    TPdfFontTrueType.PrepareForSaving

    Unicode font branch (builds CID dictionary):
      descendant: CIDFontType0 for a CFF face, CIDFontType2 with
        /CIDToGIDMap /Identity otherwise; /CIDSystemInfo the ROS of a
        CID-keyed face, Adobe-Identity-0 otherwise
      /BaseFont of both from the WinAnsi font (tag prefix included: the
        WinAnsi instances are prepared first)
      /DW = WinAnsiFont.fDefaultWidth         (space char advance width)
      PdfUsedCodes ← WinAnsiFont.GetUsedGlyphs(keys, used): fUsedWide[] and
        fShapedGlyph merged in key order (a shaped glyph under $E000 + gid
        mod 4096); per used entry GlyphCode(Glyph) (the CID of a CID-keyed
        CFF face), sorted, one entry per code (the smallest code point wins)
      /W array from the codes:
        if fFixedWidth and not PDF/A: omit /W (use /DW for all)
        else: c [w1 w2 ...] per run of consecutive codes
      ToUnicode codespace = <0000> <FFFF>, bfchar sorted by code, 99 per block

    WinAnsi font branch (builds /Widths, embeds font file):
      /FirstChar, /LastChar, /Widths from fWinAnsiUsed + ABC widths
        (no WinAnsi character used: 32..32, the space width - required for a
         simple TrueType font)
      Type0Only face no longer embedded → EPdfInvalidOperation, except a
        CID-keyed CFF face, whose codes are its CIDs

      if IsEmbedded:
        GetSubset <> nil (prepared above):
          ttf := Subset bytes; prefix /FontName and /BaseFont with Tag
          (the Unicode instance copies the prefixed name to its CIDFont and
           Type0 /BaseFont)
        else: fFace.GetFaceFile(ttf) - the whole face, a .ttc face extracted
        no bytes → RaiseNotEmbeddable (EPdfInvalidOperation): an embedded
          font is never written without its font file

        a CFF face: /FontName and /BaseFont := tag + program name
        CID-keyed: SfntTableOf(ttf, 'CFF ') → /FontFile3 /CIDFontType0C
        other OTTO: CheckFontProgram (PDF 1.6) → /FontFile3 /OpenType
          (embedded after creation: the simple font becomes /Type1)
        glyf: /FontFile2 /Length1
        GetOrCreateFontFile2(bytes, subtype) → one stream per bytes+subtype
      PDF/A or Tagged: /ToUnicode for the WinAnsi codes too
      the WinAnsi font of a Type0Only face is internal: its dictionary is not
        written (fInternal), nor its /ToUnicode
  fFontSubsets := nil
```

### 4e — CJK Text Rendering Path

Applies to: Chinese, Japanese, Korean, and any non-Latin non-RTL script.
CJK needs no GSUB shaping — `UseUniscribe=false` is sufficient and correct;
with it on, both shapers leave such text to this path.

```
TPdfVclCanvas.SyncFont                              (mormot.pdf.canvas)
│  skipped while name, size and style are unchanged (fill color reapplied)
│  fPdfCanvas.SetFont(Font.Name, Abs(Font.Size), style, Font.Charset)
│  Font.Charset = DEFAULT_CHARSET (1) by default
│
TPdfCanvas.SetFont(name, size, style, DEFAULT_CHARSET)   (Path 4a)
│  TFontRequest.CharSet := DEFAULT_CHARSET
│  FaceName := 'Microsoft YaHei'  (or another CJK font)
│  → WinAnsi font registered, FontProvider.CreateFace(request)
│
C.TextOut(40, 80, CJK_CHAR_ZHONG)                   (mormot.pdf.canvas)
│  StringToSynUnicode → [U+4E2D]
│  → TPdfCanvas.TextOutW → ShowText → TPdfWrite.AddUnicodeHexText
│     → AddUnicodeHexTextNoUniScribe

AddUnicodeHexTextNoUniScribe (U+4E2D):
│  WideCharToWinAnsi(U+4E2D) = -1   ← not WinAnsi
│  → AddGlyphFromChar(U+4E2D, Canvas, Ttf)
│     idx := Ttf.FindOrAddUsedWideChar(U+4E2D) → FindOrAddUsedCodePoint
│       new code point: inserted into fUsedWideChar / fUsedWide
│       UnicodeFont = nil → CreateAssociatedUnicodeFont
│         TPdfFontTrueType.Create(…, WinAnsiFont = self)  (same fFace)
│           TPdfTtf.Create(UnicodeFont).Free
│             LoadCmap: GetTtfData(fFace, 'cmap', …) → full CJK CMAP loaded
│               (format 12 groups when there is no format 4 subtable)
│             'head', 'hmtx', 'hhea' → widths
│             UnicodeFont.fUsedWideChar / fUsedWide populated for all CMAP code points
│       IndexOf(U+4E2D) → valid index i (a symbol font also tries the
│         $F000..$F2FF ranges)
│       fUsedWide[result].Used := UnicodeFont.fUsedWide[i].Used  (0 if absent)
│     Glyph := Ttf.fUsedWide[idx].Glyph   ← correct CJK glyph ID
│  Canvas.SetPdfFont(UnicodeFont, size)
│  '<' GlyphCode(Glyph) … '> Tj'          ← CID glyph reference
```

### 4f — Linux/macOS: FreeType Table Tag Byte-Order

Table tags from `GetTtfData` are little-endian DWORDs (`PCardinal(name)^`).
FreeType's `FT_Load_Sfnt_Table` expects big-endian (`FT_MAKE_TAG` convention).
`TFreeTypeFontFace.GetFontData` applies `bswap32(TableTag)` before the call.
`bswap32(0)` = 0 — the tag=0 "return whole font file" convention is preserved;
for tag 0 it hands out the loaded face only, extracted from a `.ttc`.

```
GetTtfData(aFace: IFontFace, 'cmap', Ref)  (mormot.pdf) — Linux/macOS path
│
│  tag := PCardinal(aTableName)^    ← LE: 'cmap' → $70616D63
│
│  aFace.GetFontData(tag, 0, nil, 0)
│    → TFreeTypeFontFace.GetFontData (mormot.lib.freetype)
│       bswap32($70616D63) = $636D6170   ← FT_MAKE_TAG('c','m','a','p')
│       FT_Load_Sfnt_Table(face, $636D6170, ...)  → returns CMAP bytes
│    → returns byte count (FONT_DATA_ERROR → nil)
│
│  SetLength(Ref, L shr 1 + 1)
│  aFace.GetFontData(tag, 0, Ref, L) → CMAP data read
│  bswap16array(result, L shr 1)     → big-endian TTF words → LE
│  → returns pointer to CMAP data
│
TPdfTtf.LoadCmap → full CMAP loaded → CJK/Arabic glyph IDs resolved correctly
```

Tag mapping: see `fonts.md`, "FreeType Backend — Table Tag Byte-Order".

---

## Path 5 — Image Embedding

```
CreateOrGetBitmapImage(Doc, Bitmap, DrawAt, ClipRc): name   (mormot.pdf.canvas)
│  empty bitmap (no width or height) → '' (no image)
│  unless Doc.ForceNoBitmapReuse:
│    hash := BitmapHash(Bitmap)  4 CRC32C lanes over the ScanLine[] rows (DIB
│                                rows on the VCL, BytesPerLine on the LCL),
│                                with the TPaletteEntry array and the color
│                                key of a pf24bit tmFixed bitmap; a device or
│                                custom PixelFormat converted to pf24bit first
│    Doc.GetXObjectImageName(hash, W, H) - existing image: reuse its name
│  new image:
│        ForceJPEGCompression = 0, or a tmFixed bitmap (JPEG drops the key):
│          CreateGraphicImage(Doc, Bitmap, true)
│            VCL: ScanLine[] → TPdfImagePixels (ipfBgr24 / ipfBgrx32 /
│            ipfIndexed8 with its palette; pf1/pf4 drawn to pf8)
│            LCL: LclPixels - RawImage.Description: a DIB layout as it is,
│            gray as ipfIndexed8 with a gray ramp, others repacked to
│            ipfRgb24 through TLazIntfImage.Colors
│            color key of a pf24bit tmFixed bitmap → /Mask
│            → TPdfImage.CreatePixels
│        else: TJpegImage.Assign(Bitmap) → CreateGraphicImage(Doc, jpg, false)
│            SaveToStream at the quality → TPdfImage.CreateJpeg (in the xref)
│        img.Hash := hash; Doc.RegisterImage(img) → 'SynImg<n>'
│          (AddXObject, or RegisterXObject if already in the xref)
└─ Doc.DrawImage(name, DrawAt, ClipRc) → Canvas.DrawXObject[Ex]
     (DrawAt nil: nothing drawn - TPdfVclCanvas.Draw/StretchDraw draw the
      name themselves)

TPdfDocument.CreateOrGetImage(Pixels, DrawAt, ClipRc)  (mormot.pdf, no VCL/LCL)
│  CheckPixels → PixelsHash (row bytes, palette, format, color key)
│  → GetXObjectImageName / TPdfImage.CreatePixels / RegisterImage / DrawImage

TPdfCanvas.DrawXObject(X, Y, W, H, 'SynImg0')
│  TPdfWrite: 'q ... cm /SynImg0 Do Q'
│  tagged, outside a region: the Do is wrapped as an artifact (Path 10)
└─ image rendered at position
```

---

## Path 6 — Optional Content (Layers)

```
TPdfDocument.UseOptionalContent := true
│  /OCProperties in the catalog (NewDoc), FileFormat >= pdf15
│
TPdfDocument.CreateOptionalContentGroup(Parent, 'Layer Name', Visible)
│  creates TPdfOptionalContentGroup (PDF /OCG dictionary), listed in /OCGs
│    and /D /Order (under Parent if given), in /D /OFF when not Visible
│  nil without UseOptionalContent
│
TPdfCanvas.BeginMarkedContent(Group)
│  registers the group in the page's /Resources /Properties as oc<objnum>
│  TPdfWrite: '/OC /oc<objnum> BDC'  (Group nil: '/OC BMC')
│  all following draw commands belong to this layer
│
TPdfCanvas.EndMarkedContent
│  TPdfWrite: 'EMC'
│
TPdfDocument.CreateOptionalContentRadioGroup(Groups)
   links groups into a /D /RBGroups entry (mutually exclusive layers)
```

---

## Path 7 — Bookmarks & Links

```
// From TGDIPages (heading-level bookmarks):
TGDIPages.DrawHeading(1, 'Title')  → THeadingInfo in fHeadings
  → ExportPdfStream, after all pages: AddHeadingsToOutline(Doc)
    per heading: Doc.Canvas.SetPage(its page); Y in points from the page
    bottom: (page height + bottom margin - heading Y) * 72 / 2540
    TPdfDocument.CreateOutline('Title', 1, Y_pdf)
    │  nothing without UseOutlines
    │  creates a TPdfOutlineEntry below the last one of a lower level
    └─ linked into the /Outlines tree at SaveToStream

// From application (manual):
TPdfDocument.CreateBookMark(Y_pdf, 'anchor')
  → TPdfDestination /XYZ on the current page, kept by name
    (raises on a duplicate or empty name); links created before it get
    their /Dest now

TPdfDocument.CreateLink(Rect, 'anchor')
  → TPdfAnnotation(asLink) on the current page, /Dest of the bookmark

TPdfDocument.CreateHyperLink(Rect, 'https://...')
  → TPdfAnnotation(asLink) with a /URI action
```

---

## Path 8 — AES Encryption (AES-128, AES-256)

```
TPdfEncryption.New(elAES_128, userPw, ownerPw, perms)
  → TPdfEncryptionAES128.Create(...)
      inherits TPdfEncryption.Create: stores passwords, permissions

TPdfEncryptionAES128.AttachDocument(aDoc)   ← from NewDoc, after the /ID
  aDoc.NeedFileFormat(pdf16): FileFormat and its floor
  Key derivation (same as RC4-128 / Algorithm 3.2):
    Pad(user) → usr[32];  Pad(owner) → own[32]
    MD5(own) × 50 iterations → ownerKeyMD5[16]
    RC4.Init(ownerKeyMD5, 16) → RC4.Encrypt(usr, fOwnerPass)
    RC4 × 19 more iterations (Algorithm 3.3) → /O value
    MD5(usr + fOwnerPass + flags + fileID) × 50 → fInternalKey[16]
    Algorithm 3.5 (user pass validation) → fUserPass[32]
  Encryption dictionary (Filter=Standard, V=4, R=4, Length=128):
    CF.StdCF: { CFM=AESV2, AuthEvent=DocOpen, Length=16 }
    StmF=StdCF, StrF=StdCF
    P=fFlags, O=fOwnerPass, U=fUserPass
  trailer /Encrypt

TPdfEncryptionAES128.EncodeBuffer(BufIn, BufOut, Count)
  Per-object key (Algorithm 3.1a):
    MD5(fInternalKey[16] || objNum[3] || genNum[2] || 'sAlT') → objKey[16]
  RandomBytes → iv[16]   ← written first to BufOut
  PKCS7-pad BufIn to padLen := ((Count div 16)+1)*16
  TAesCbc.Create(objKey, 128); aes.IV := iv; aes.Encrypt(padBuf, BufOut+16, padLen)

GetEncryptedSize(InSize): 16 + ((InSize div 16)+1)*16
  → TPdfStream.InternalWriteTo uses this to pre-set /Length and allocate tmpEnc
  → string encryption callers (TPdfWrite.AddEscapeContent, AddUnicodeHex)
    allocate via GetEncryptedSize
```

AES-256 (`elAES_256`, ISO 32000-2 R=6) has no per-object key:

```
TPdfEncryptionAES256.AttachDocument(aDoc)   ← from NewDoc
  aDoc.NeedFileFormat(pdf17): FileFormat and its floor
  TAesPrng → fFileKey[32]; fAes := TAesCbc.Create(fFileKey, 256)
  Wrap(user UTF-8, no user key) → /U = Hash2B(validation salt) + 2 salts,
    /UE = AES-256-CBC(Hash2B(key salt), IV 0) of fFileKey
  Wrap(owner UTF-8, user key = the 48 bytes of /U) → /O, /OE
  /Perms = AES-256-ECB(fFileKey) of P, FFFFFFFF, 'T', 'adb', 4 random bytes
  dictionary V=5, R=6, Length=256, StdCF { CFM=AESV3, Length=32 }
  catalog /Extensions /ADBE { BaseVersion 1.7, ExtensionLevel 8 }
Hash2B = Algorithm 2.B: SHA-256, then >= 64 rounds of AES-128-CBC and
  SHA-256/384/512 chosen by the first 16 bytes of each round modulo 3
```

PDF/A and encryption exclude each other: `NewDoc` raises `EPdfInvalidOperation`.

---

## Path 9 — Transparency via ExtGState

```
TPdfCanvas.SetFillAlpha(Value: single)   [or SetStrokeAlpha]
  Value clamped to [0..1]
  intVal := Round(Value * 100)
  gsName := 'Fca' + IntToStr(intVal)     ['SCA' for stroke]
  extGs := fPage.GetResources('ExtGState')
  if extGs = nil:
    extGs := TPdfDictionary.Create(fDoc.fXRef)
    page /Resources.AddItem('ExtGState', extGs)
  if extGs.ValueByName(gsName) = nil:    ← deduplication
    gsDict := TPdfDictionary: { Type=ExtGState, ca=Value }   ['CA' for stroke]
    extGs.AddItem(gsName, gsDict)
  fContents.Writer.Add('/Fca50 gs')      ← emits graphics state operator
```

Entries accumulate in the page's ExtGState resource dict across multiple calls. Identical alpha values on the same page reuse the same entry (no duplicates); values that round to the same percentage share the first one's alpha. Minimum PDF version for transparency support: PDF 1.4.

---

## Path 10 — Tagged PDF Struct Tree

Table shape emitted by `TGDIPages.RenderPageToCanvas`:

```
dckBeginTable            BeginStructContent(psrTable); fRenderRowGroup := psrTable
dckBeginTR  Color=1      OpenRowGroup(psrTHead) → BeginStructContent(psrTR) → cells TH
            Color=0      OpenRowGroup(psrTBody) → TR → cells TD
            Color=3      OpenRowGroup(psrTFoot) → TR → cells TD; with
                         FooterRowHeader the first cell psrTHRow (Cmd.RowHeader)
            Color=2      BeginArtifact: repeated header, no struct, group untouched
dckEndTable              close the open group, then the Table
```
`OpenRowGroup` closes the previous group first, so groups never nest.
`fRenderRowGroup` is a field: a table continues on the next page while its
group stays open.

```
TPdfDocument.SetTagged(true)
  raises ESynException if fRawPages.Count > 0   ← too late: the pages were
                                                  measured with another face
  fTagged := true
  NeedFileFormat(pdf17): FileFormat and its floor
  PDF/UA font mode: fStandardFontsReplace := false; fEmbeddedTtf := true;
                    fEmbeddedWholeTtf := not PdfCanSubsetRetainingGids
                    ← both subsetters keep the glyph IDs, so /ToUnicode stays
                      valid: subsets on Windows (FontSub) and POSIX (hb-subset);
                      the whole face only without a subsetter
  (the catalog entries follow on the first AddPage)

TPdfDocument.AddPage
  page.fStructParents := fRawPages.Count - 1  ← /StructParents N; MCIDs restart at 0
  first tagged page (fStructTree = nil):
    FileFormat >= pdf14
    Catalog: /MarkInfo << /Marked true >>, /Lang DefaultLanguage,
             /StructTreeRoot (indirect, saved at the end)
    catalog /ViewerPreferences gains vpDisplayDocTitle (PDF/UA-1 7.1)
    non-PDF/A: fMetaData := TPdfStream; Subtype=XML; Type=Metadata;
      fSaveAtTheEnd (filled by WriteTaggedMetadata); /ID generated if missing

TPdfCanvas path operators (m l c v y re, and Do through ExecuteXObject)
  BeginPathArtifact: tagged and InMarkedContent = false
    → '/Artifact BMC' before the first construction operator
  painting operator (S s f f* B B* b b*) or 'n' → EndPathArtifact → 'EMC'
  inside an open region (e.g. Figure) nothing is added: real content
  SetPage closes a path artifact left open

TPdfCanvas.BeginArtifact / EndArtifact  ← explicit, e.g. repeated header row
  raises EPdfInvalidOperation inside a region / without a matching Begin

TPdfCanvas.BeginStructContent(ARole, AAltText='')
  if not fDoc.fTagged: exit  ← no-op guard
  elem: TPdfStructElement := (Role, AltText, PageIndex=fPage.fStructParents)
  fDoc.fStructElems.Add(elem)
  if fDoc.fStructStack <> []: top.AddKid(elem)   ← nesting
  fDoc.fStructStack.Add(elem)
  if PDF_STRUCT_CONTAINER[ARole]: exit      ← Document/Table/TR/L/LI/THead/TBody/TFoot own no MCID
  mcid := fPage.fCurrentMCID; Inc(fPage.fCurrentMCID)   ← per-page counter
  elem.AddMCID(mcid, fPage.fStructParents); elem.RegionOpen := true
  fContents.Writer.Add('/H1 <</MCID 3')     ← e.g.
  if AAltText <> '': ' /Alt (…)' (WinAnsi, escaped) or ' /Alt <FEFF…>' (UTF-16)
  fContents.Writer.Add('>> BDC')

TPdfCanvas.ResumeStructContent(Index, AOpenRegion=true)
  ← a block continued on the next page
  reopens fStructElems[Index]: pushes it again, allocates a new MCID on the
  current page, writes another BDC — the element then owns several MCIDs
  AOpenRegion=false: pushed back without a region (inline line)
  raises for an unknown index or a container

TPdfCanvas.BeginStructGroup(ARole)           ← element without a region
  as BeginStructContent, but no MCID and no BDC

TPdfCanvas.ContinueStructContent             ← plain inline run
  top of fStructStack gains one more MCID + BDC; no-op if its region is open

TPdfCanvas.SuspendStructContent              ← before a nested Span
  writes 'EMC' for the top element but leaves it on fStructStack, so the next
  BeginStructContent still becomes its kid

TPdfCanvas.EndStructContent
  pops fStructStack; writes 'EMC' only when that element has an open region
  raises without a matching Begin

SaveToStreamDirectEnd (called by ExportPdfStream):
  if fTagged:
    elements left open → EPdfInvalidOperation (missing EndStructContent)
    SerializeStructTree, then WriteTaggedMetadata:
      if fMetaData <> nil and fPdfA=pdfaNone:
        fMetaData filled with PDF/UA-1 XMP (pdfuaid:part=1, dc:title from
        Info.Title, XML-escaped) — here, not in SaveToStreamDirectBegin,
        because a streamed export creates fMetaData on its first AddPage
      (PDF/A writes its packet in SaveToStreamDirectBegin, plus pdfuaid when
       tagged)
    SerializeStructTree details:
      one indirect dict per element; /P points at the real parent
      leaf without kids → /K MCR dict, or an array of MCR dicts (each with
        /Pg when it differs from the element's /Pg)
      element with kids → /K [kid dicts and own MCR dicts], merged in
        document order via KidSeqs[]/MCIDSeqs[] (a P with Span kids)
      a Figure gets /Alt and a /BBox layout attribute from what was drawn
        inside it (ExtendFigure)
      /ParentTree /Nums: per page an array indexed by MCID; an element
        continued across a page break appears in both pages' arrays
```

---

## Coordinate Conversion Summary

| Layer | Unit | DPI | Y origin | Conversion to PDF points |
|---|---|---|---|---|
| TGDIPages | 1/100 mm | — | top (Y=0) | `* 72 / (25.4 * 100)` |
| TPdfVclCanvas | pixels | ScreenLogPixels (96; Windows: the screen's) | top (Y=0) | `* 72 / ScreenLogPixels`; Y-flip |
| TPdfCanvas | PDF points | 72 | bottom (Y=0) | identity |
| Screen preview | pixels | Screen DPI | top (Y=0) | `* ScreenDPI / (25.4 * 100)` |
| Printer | pixels | Printer DPI | top (Y=0) | `* PrinterDPI / (25.4 * 100)` |

All conversions happen at the boundary of each layer; inner code always works in its native unit.
