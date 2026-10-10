# Call Graph — mORMot2 PDF Framework

This document traces all major call paths through the framework, from application code down to platform APIs and the PDF byte stream.

---

## Layer Overview

```
┌──────────────────────────────────────────────────────────────────┐
│  Application Code                                                │
├──────────────┬───────────────────────────┬───────────────────────┤
│  TGDIPages   │  TPdfDocumentVcl           │  TPdfDocument         │
│  (report)    │  (TCanvas bridge)          │  (direct PDF)         │
├──────────────┴──────────────┬────────────┴───────────────────────┤
│              TPdfVclCanvas (TCanvas subclass)                    │
├─────────────────────────────┴───────────────────────────────────┤
│              TPdfCanvas  /  TPdfDocument                        │
├─────────────────────────────────────────────────────────────────┤
│  IFontProvider → IFontFace          │  IFontEnumerator           │
├────────────────────┴───────────────────┴────────────────────────┤
│  IFontShaper  (HarfBuzz — Unix/macOS; nil on Windows)           │
├────────────────────┬───────────────────┬────────────────────────┤
│  GDI (Windows)     │                   │  FreeType2 (Unix/macOS)│
└────────────────────┴───────────────────┴────────────────────────┘
```

---

## Path 1 — Direct PDF API (TPdfDocument)

Lowest-level path. All coordinates in PDF points; Y=0 at bottom of page.

```
Application
  TPdfDocument.Create(UseOutlines, CodePage, PdfA, [Encryption])
  │  initialises xref table, TPdfInfo, TPdfOutlineRoot
  │  sets PdfA level → may set GeneratePdf15File
  │
  TPdfDocument.NewDoc
  │  clears page list, writes PDF header
  │
  TPdfDocument.AddPage → TPdfPage
  │  creates new page dictionary
  │  sets Doc.Canvas → TPdfCanvas pointing at this page
  │
  TPdfCanvas.SetFont(Name, Size, Style)
  │  TPdfDocument.GetRegisteredTrueTypeFont(LogFont)
  │  │  if not cached: face := FontProvider.CreateFace(TFontRequest)
  │  │                 face.GetTextMetrics
  │  │                 face.GetOutlineMetrics
  │  │                 face.GetCharAbcWidths(32, 255)
  │  │                 face.GetFontData('head'/…)  ← TTF bytes
  │  └─ returns TPdfFontTrueType (or TPdfFontStandard for Type1)
  │
  TPdfCanvas.TextOut(X, Y, Text)
  │  TPdfWrite.AddEscapeText / AddUnicodeHex
  │  TPdfFontTrueType: marks used chars in fWinAnsiUsed / fUsedWideChar
  │
  TPdfCanvas.Rectangle / MoveTo / LineTo / Fill / Stroke …
  │  TPdfWrite: low-level byte emitter to page content stream
  │
  CreateOrGetBitmapImage(Doc, Bitmap) → Path 5
  │  creates a TPdfImage; reuses one of the same pixels (CRC32C lanes)
  │
  TPdfDocument.SaveToFile / SaveToStream
     TPdfWrite: serialise xref table, objects, content streams
     FileFormat >= pdf15: TPdfTrailer.ToCrossReference → xref stream + object streams
     Compression: if cmFlateDecode → zlib DeflateStream
     Encryption (USE_PDFSECURITY):
       TPdfEncryptionRC4MD5 → RC4-40/RC4-128 stream cipher per object (same output size)
       TPdfEncryptionAES128 → AES-128-CBC per object:
         TPdfStream.InternalWriteTo: encLen := GetEncryptedSize(buflen)
           = 16 (IV) + ((buflen div 16)+1)*16
         len.Value := encLen  (set BEFORE DirectWriteTo so /Length is correct)
         separate tmpEnc buffer allocated; EncodeBuffer writes IV||ciphertext
       Tagged PDF: StructTreeRoot + ParentTree number tree → SaveToStreamDirectEnd
```

---

## Path 2 — VCL Canvas Bridge (TPdfDocumentVcl)

Adds a TCanvas-compatible wrapper. Pixel coordinates, Y=0 at top.

```
Application
  TPdfDocumentVcl.Create(...)          // inherits TPdfDocument.Create
  │
  TPdfDocumentVcl.AddPage
  │  calls TPdfDocument.AddPage → new TPdfPage
  │  creates TPdfVclCanvas(Self, Doc.Canvas)
  │  stores as internal VclCanvas instance
  │
  TPdfDocumentVcl.VclCanvas → TPdfVclCanvas (TCanvas subclass)
  │  (must be retrieved after each AddPage)
  │
  TPdfVclCanvas.TextOut(X, Y, Text)
  │  coordinate conversion: X_pdf = X * 72/96
  │                         Y_pdf = PageH - Y * 72/96   (Y-flip)
  │  → TPdfCanvas.TextOut(X_pdf, Y_pdf, Text)
  │     → TPdfWrite (see Path 1)
  │
  TPdfVclCanvas.Rectangle(X1,Y1,X2,Y2)
  │  → coordinate conversion → TPdfCanvas.Rectangle / Fill / Stroke
  │
  TPdfVclCanvas.Draw(X, Y, Graphic)
  TPdfVclCanvas.StretchDraw(Rect, Graphic)
  │  → CreateOrGetBitmapImage(fPdfDoc, Bitmap) (see Path 5)
  │     → TPdfCanvas.DrawXObject (see Path 1)
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
  │  initialises format registry (H1–H6, P, Code, etc. → TReportFormat)
  │  initialises fPages: array of TPageData
  │
  TGDIPages.NewPage
  │  appends new TPageData to fPages; resets CurrentY
  │
  TGDIPages.SetFont / SetFont + FontStyle
  │  updates internal font state (no canvas call yet)
  │
  TGDIPages.DrawHeading(Level, Title)
  │  looks up format 'H1'..'H6' from format registry
  │  checks remaining vertical space → ForceNewPage if needed
  │  EmitTextCmd → AddCommand → appends TDrawCommand(dckHeading) to current page
  │  if UseOutlines: records THeadingInfo for PDF bookmark
  │
  TGDIPages.DrawParagraph / DrawText / DrawStrong / DrawEm / DrawCode …
  │  word-wrap logic → one TDrawCommand(dckDrawText) per line segment
  │  CurrentY advances by line height
  │
  TGDIPages.BeginTable / DrawTableHeader / DrawTableRow / EndTable
  │  BeginTable(TTableLayout):
  │    SaveLayout  ← balanced by EndTable RestoreLayout
  │    copies Layout.ColumnWidths/ColumnAligns into fTableColWidths/fTableColAligns
  │    IMPORTANT: Length(Layout.ColumnWidths) must be > 0; if a typed constant's
  │      dynamic array initializes to Length=0 (FPC < 3.2 bug), NO cells are drawn
  │    TDrawCommand(dckBeginTable)  ← opens Table struct element
  │  DrawTableHeader:
  │    saves Headers[] into fTableSavedHeaders  ← for auto-repeat on page break (R-9)
  │    SaveLayout / (apply HeaderFontStyle) / cell drawing / RestoreLayout
  │    cell height = LineHeightMM + CELL_PADDING (CELL_PADDING = 200 = 2mm)
  │    TDrawCommand(dckBeginTR, Color=1)        ← header row marker
  │    per cell: TDrawCommand(dckFillRect, HeaderBkColor)
  │              TDrawCommand(dckDrawRect, clBlack)  ← border
  │              EmitTextCmd → TDrawCommand(dckDrawText)
  │    TDrawCommand(dckEndTR)
  │  DrawTableRow:
  │    RowHeight := LineHeightMM + CELL_PADDING  ← measured BEFORE SaveLayout
  │    if fCurrentY + RowHeight > fPageHeight:
  │      ForceNewPage → NewPage (fCurrentY=0) + fCurrentY:=0
  │      if fTableSavedHeaders <> nil: DrawTableHeader(fTableSavedHeaders) ← R-9 repeat
  │    TDrawCommand(dckBeginTR, Color=0)        ← data row marker
  │    SaveLayout / (apply BodyFontStyle) / cell drawing / RestoreLayout
  │    per cell: TDrawCommand(dckFillRect, BodyBkColor or AlternateRowColor)
  │              TDrawCommand(dckDrawRect, clBlack)
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
     finalises last page; nothing rendered yet
```

### 3b — Preview Path

```
ShowReportPreview(Report)                       (mormot.ui.reportpreview)
  │  TReportPreview.Show: modal LCL form, scroll box, paint box
  │
  TReportPreview.DoPaint (on each repaint)
  │  ZW := Round(fW * fZoom)   ← zoomed pixel dimensions
  │  ZH := Round(fH * fZoom)
  │  for each visible page:
  │  TGDIPages.RenderPageToCanvas(ScreenCanvas, PageIndex, ZW, ZH)   ← SourceDPI=0
  │  │  converts 1/100mm → screen pixels
  │  │  FontScale: BaseHeight := MMToPixels(totalPageHeight, ACanvas.Font.PixelsPerInch)
  │  │             FontScale  := ZH / BaseHeight   ← equals fPreviewZoom at 96 DPI
  │  │  iterates TPageData.Commands[]
  │  │  per command:
  │  │  State: InTableRow: boolean; InHeaderRow: boolean (both false at start)
  │  Note: SaveLayout/RestoreLayout saves fFontName/fFontSize/fFontStyle/fTextColor only —
  │        fCurrentY is NOT saved/restored
  │  │    dckDrawText   → ApplyFont (Font.Size := Round(Cmd.FontSize * FontScale))
  │  │                    + ACanvas.TextOut
  │  │    dckDrawLine   → Pen.Color + Pen.Width := Max(1,LineWidth) + MoveTo/LineTo
  │  │    dckFillRect   → Brush.* + Pen.Style=psClear + Rectangle (not FillRect!); Pen.Style restored
  │  │    dckDrawRect   → Pen.Color + Pen.Width := Max(1,LineWidth) + Brush.Style=bsClear + Rectangle
  │  │                    NOTE: Pen.Width must be set explicitly; without it the pen from a prior
  │  │                    dckDrawLine (e.g. thick decorative line) is inherited → table borders appear thick
  │  │    dckDrawBitmap → ACanvas.StretchDraw
  │  │    dckBeginTable/dckEndTable → (visual: no-op; struct: psrTable BDC/EMC)
  │  │    dckBeginTR    → InHeaderRow := Color<>0; InTableRow := true
  │  │    dckEndTR      → InTableRow := false; InHeaderRow := false
  │  │    dckHeading    → Font.Size := Round(Format.FontSize * FontScale) + TextOut
  │  │  header/footer: Font.Size := Round(fFontSize * FontScale); {#}/{total} substituted
  │  └─ ACanvas here is the screen TCanvas
```

### 3c — PDF Export Path

```
TGDIPages.ExportPdfStream(aDest: TStream)
  │
  │  Doc := TPdfDocumentVcl.Create(UseOutlines, 0, ExportPdfLevel)
  │  Doc.FileFormat            := ExportPdfFileFormat   (default pdf13; set pdf17 for ISO 32000-1)
  │  if ExportPdfTagged:
  │    Doc.Tagged  := True          ← raises FileFormat to pdf17 AND picks the
  │                                   PDF/UA font mode (see Path 10)
  │    Doc.DefaultLanguage := ExportPdfLanguage
  │  Doc.EmbeddedTtf           := ExportPdfEmbeddedTTF
  │  Doc.StandardFontsReplace  := ExportPdfStandardFonts
  │    ↑ assigned after Tagged, and SetExportPdfTagged has already aligned them,
  │      so the two cannot contradict each other
  │  Doc.Info.Title/Author/Subject := ...
  │  Doc.PdfAMetadaExtension := ExportPdfMetadataExtension
  │    ↑ before SaveToStreamDirectBegin: PDF/A writes its XMP packet there
  │  Doc.SaveToStreamDirectBegin(aDest)
  │
  │  fActivePdfDoc := Doc   ← stored so RenderPageToCanvas can call BeginStructContent
  │
  │  for PageIndex := 0 to PageCount-1 do
  │    Doc.AddPage
  │    VclCanvas := Doc.VclCanvas   ← TPdfVclCanvas
  │
  │    TGDIPages.RenderPageToCanvas(VclCanvas, PageIndex, DestW, DestH, 96)
  │    │  SourceDPI=96 matches PDF.ScreenLogPixels → exact coordinate match
  │    │  fActivePdfDoc <> nil → struct content wrapping enabled:
  │    │    dckDrawText:  Cmd.BlockId = open block? → keep region open (or
  │    │                  ResumeStructContent after a page break)
  │    │                  else BeginStructContent(psrH1..6 / psrTH / psrTD /
  │    │                                          psrLBody / psrP)
  │    │                  Cmd.IsInline → BeginStructGroup instead, then per run:
  │    │                    isPlain  → ContinueStructContent (region on the P)
  │    │                    styled   → SuspendStructContent + psrSpan kid
  │    │    dckDrawBitmap: fActivePdfDoc.BeginStructContent(psrFigure)
  │    │    dckBeginTable: fActivePdfDoc.BeginStructContent(psrTable)
  │    │    dckEndTable:   fActivePdfDoc.EndStructContent + reset InTableRow
  │    │    dckBeginTR:    fActivePdfDoc.BeginStructContent(psrTR)
  │    │    dckEndTR:      fActivePdfDoc.EndStructContent + reset InTableRow
  │    │    dckHeading:    fActivePdfDoc.BeginStructContent(psrH1..H6)
  │    │  ACanvas calls → TPdfVclCanvas calls → TPdfCanvas → TPdfWrite
  │    └─ headings with UseOutlines: Doc.CreateOutline(Title, Level, Y)
  │
  │  fActivePdfDoc := nil
  │  (each page: SaveToStreamDirectPageFlush)
  │  AddHeadingsToOutline(Doc)
  │  Doc.CreateFileAttachmentFrom(...)  per AddExportPdfAttachment entry
  │  Doc.SaveToStreamDirectEnd    ← flushes StructTreeRoot + ParentTree,
  │                                 catalog (/AF, /EmbeddedFiles), xref
  └─ returns true on success
```

### 3d — Print Path

```
PrintReport(Report, From = 0, To_ = all)        (mormot.ui.reportpreview)
  │  no dialog: prints on the default printer
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
TPdfCanvas.SetFont('Calibri', 12, [pfsBold])       (pdf.pas:8749)
│
│  ACharSet resolution (pdf.pas:8835–8836):
│    if ACharSet < 0: ACharSet := fDoc.CharSet
│    fDoc.CharSet = CodePageToCharSet(LCIDToCodePage(SysLocale.DefaultLCID))
│    → ANSI_CHARSET (0) on Western Windows
│    → DEFAULT_CHARSET (1) on Unix/macOS
│
│  LOGFONTW construction (pdf.pas:8841–8854):
│    lfHeight   := -1000
│    lfCharSet  := ACharSet       ← controls what GetFontData exposes (see fonts.md §11)
│    lfFaceName := 'Calibri'
│
TPdfDocument.GetRegisteredTrueTypeFont(LogFont)
│  searches fRegisteredFonts cache by (name + style + charset)
│  if found in cache: return immediately
│
│  TPdfDocument.GetTrueTypeFontIndex('Calibri')
│  │  if not in fTrueTypeFonts list:
│  │    FontEnumerator.EnumTrueTypeFonts(List)   ← system font scan
│  │    searches List for 'Calibri'; stores in fTrueTypeFonts
│  │
│  creates TPdfFontTrueType (WinAnsi instance, fUnicode=false)   (pdf.pas:6252)
│  │  fFace := FontProvider.CreateFace(lf: TFontRequest) ← CharSet from above
│  │    (every platform since W3, no device context since Phase 1b; the
│  │     TLogFontW constructor: GdiCreateFace(LOGFONT); none -> TPdfNoFace)
│  │  fFace.GetTextMetrics / GetOutlineMetrics / GetCharAbcWidths
│  stores in fRegisteredFonts; fFontList
│
│  Note: UnicodeFont (fUnicode=true) is created lazily by CreateAssociatedUnicodeFont
│        on the first non-Latin character — NOT here; for a CFF face when
│        SetPdfFont selects it (it stands for the WinAnsi font).
│        CMAP loading (TPdfTtf.Create) happens at that point (see Path 4e).
│
└─ returns TPdfFontTrueType (WinAnsi instance)
```

### 4b — Text Rendering — WinAnsi / Latin Path (`pdf.pas:5484`)

```
TPdfVclCanvas.TextOut(X, Y, S)
  StringToSynUnicode → W   (TextOutUtf8: Utf8ToSynUnicode)
  → TPdfCanvas.TextOutW(X, Y, W)
      → TPdfWrite.ShowText(PW) → AddUnicodeHexText(PW, Len, false, Canvas)

AddUnicodeHexText (pdf.pas:5549):
  if UseUniscribe=false or no TrueType font:
    → AddUnicodeHexTextNoUniScribe(PW, ttf, false, Canvas)   [see path 4c]

AddUnicodeHexTextNoUniScribe (pdf.pas:5484):
  a CFF face (Type0Only): every character as a glyph of the Unicode font,
  the WinAnsi branch skipped - fonts.md "CFF Faces: Type0 Only"
  for each WideChar:
    if WideCharToWinAnsi(ch) >= 0:         // U+0000..U+00FF  (Latin-1)
      SetPdfFont(WinAnsiFont)
      Add('(…) Tj')
      include(WinAnsiFont.fWinAnsiUsed, ch)   ← char marked as used
    else:                                  // non-Latin
      ttf.CreateAssociatedUnicodeFont       ← lazy Unicode instance creation
      FindOrAddUsedWideChar(ch)             ← register in tracking arrays
      SetPdfFont(UnicodeFont)
      Add('<XXXX> Tj')                      ← CID glyph reference
```

### 4c — Text Rendering — Uniscribe / HarfBuzz Path (RTL, Complex Scripts)

```
AddUnicodeHexText (pdf.pas) — UseUniscribe gates the one shaper (since W2):

  shaped := UseUniscribe and ttf present and
            AddUnicodeHexTextShaped(PW, Len, ttf.WinAnsiFont, NL, Canvas)
    FontShaper.Shape(PW, Len, WinAnsiTtf.fFace.Handle, RightToLeftText, Runs)
      Windows - TUniscribeShaper (mormot.lib.uniscribe):
        ScriptItemize(PW, Len, state) → items[0..count-1], items[count] = end
          RightToLeftText: state.uBidiLevel := 1
        no item fComplex or fRtl → false (Latin: the simple path)
        ScriptLayout(count, levels, VisualToLogical) → visual order
        per item (empty ones skipped): ScriptShape(0, psc, ...)
          0                         → fskShaped/fsoDone, zero-width non-
                                      diacritic glyphs left out; no glyph at
                                      all → fskSkip/fsoDone
          E_OUTOFMEMORY             → fskPlain/fsoFailed
          E_PENDING, NOT_IN_FONT    → again with its own DC holding the font:
                                      0 → as above, else fskPlain/fsoFailed
          any other error           → fskSkip/fsoFailed
        ScriptFreeCache(psc); true
      Linux/macOS - THarfBuzzShaper (mormot.lib.harfbuzz):
        not RightToLeftText and not NeedsShaping(PW, Len) → false
        hb_ft_font_create(ctx^.Face), RTL forced or guessed, hb_shape
        → one run fskShaped/fsoDone: Glyphs, Advances, Offsets (x),
          YOffsets (y, not drawn yet), Clusters - 1/1000 em
    false, or runs not covering the text / arrays misaligned → not shaped
    MoveToNextLine once if NL
    per run: fskPlain or fsoUnknown → AddUnicodeHexTextNoUniScribe(copy + #0)
             fskShaped              → AddShapedRun(Run, WinAnsiTtf)
             fskSkip                → nothing

AddShapedRun(Run, WinAnsiTtf):          ← the font it was shaped with
  CreateAssociatedUnicodeFont if needed; SetPdfFont(UnicodeFont, size)
  no glyph → done (the font switch only)
  no Advances (Uniscribe): '<' GlyphCode(GetAndMarkGlyphAsUsed(g))… '> Tj'
  Advances (HarfBuzz): for each glyph
      WinAnsiTtf.GetAndMarkGlyphAsUsedWithWidth(Glyph, Advance_1000)
        Step 1: already registered (fUsedWide or fShapedGlyph) → exit
        Step 2: reverse CMAP → FindOrAddUsedWideChar → exit
          ← hmtx width from TPdfTtf.Create: (int64(hmtx) * 1000) div UPM
        Step 3: AddShapedGlyph with the hmtx width (not in CMAP)
    one Tj, or a TJ where an offset or the hmtx width differs (P3-B, U-2)
    every code written as WinAnsiTtf.GlyphCode(g): the CID of a CID-keyed
    CFF face, the glyph index otherwise

  if not shaped:
    → AddUnicodeHexTextNoUniScribe(…)           ← Latin fallback

GetAndMarkGlyphAsUsed(glyph) - from AddShapedRun (no Advances) and from the
public AddGlyphs (→ AddGlyphsOf with the page font, VisAttr filter if given):
    glyph := Ttf.WinAnsiFont.GetAndMarkGlyphAsUsed(shapedGlyph)
    │  Step 1: already in fUsedWide[] → return immediately
    │  Step 2: reverse CMAP scan in UnicodeFont.fUsedWide[]
    │           found → WinAnsiFont.FindOrAddUsedWideChar → register in WinAnsi tracking
    │           not found → fall through to Step 3
    │  Step 3: GSUB glyph (Arabic form, ligature) - every platform since W3
    │           FontProvider.GetGlyphAdvance(DC, glyph) → advance width
    │             (GDI GetCharABCWidthsI, FreeType FT_Load_Glyph);
    │             failure → fDefaultWidth
    │           AddShapedGlyph(glyph, w) → WinAnsiFont.fShapedGlyph (by glyph ID)
    │           → glyph registered in /W array; no overlap from /DW fallback
    │           (before W3 Windows only: on POSIX the glyph stayed out of /W)
    AddHex4(Ttf.WinAnsiFont.GlyphCode(glyph))
  Add('> Tj') if any glyph was kept
```

### 4d — Font Serialization at Save (`pdf.pas:6568`)

```
TPdfDocument.SaveToStream / SaveToFile → SaveToStreamDirectEnd
  TPdfDocument.PrepareFontSubsets                 (R-12, runs first)
    exit unless FontSubsetter <> nil (hb-subset on POSIX, FontSub on Windows)
                and not EmbeddedWholeTtf and PdfA not in [pdfa1A, pdfa1B]
    for every WinAnsi TPdfFontTrueType that IsEmbedded, and not IsSymbolic
    unless FontSubsetter.SupportsSymbolic (FontSub: yes, hb-subset: no):
      GetFaceData → whole face (FontProvider.GetFontData, tag 0)
      group by face bytes (crc32c + compare) in fFontSubsets[]
        ← Regular + Bold of one .ttc face land in the same entry
      AddToSubsetRequest: Unicodes += fWinAnsiUsed (via WinAnsi table) +
                          fUsedWideChar; Glyphs += fUsedWide[].Glyph +
                          fShapedGlyph (glyphs without a code point)
      fSubsetIndex := entry + 1
    per entry: FontSubsetter.Subset(Face, Request, Font.fFace.Handle) → Subset bytes
               (FontSub: Unicodes via GetGlyphIndicesW, .ttc index from the
                bytes - TtcFaceIndex; platform-backends.md, IFontSubsetter)
               Tag := 'ABCDEF+' from crc32c(Subset)   (deterministic)
               failure (CFF, error) → Subset = '' → whole face
  for every font in fFontList:
    TPdfFontTrueType.PrepareForSaving

    Unicode font branch (builds CID dictionary):
      /DW = WinAnsiFont.fDefaultWidth         (space char advance width)
      WinAnsiFont.GetUsedGlyphs(keys, used): fUsedWide[] and fShapedGlyph
        merged in key order (a shaped glyph under $E000 + gid mod 4096)
      PdfUsedCodes: GlyphCode(Glyph) (the CID of a CID-keyed CFF face),
        sorted, one entry per code (the smallest Unicode value wins)
      /W array from the codes:
        if fFixedWidth and not PDF/A: omit /W (use /DW for all)
        else: c [w1 w2 ...] per run of consecutive codes
      ToUnicode codespace = <0000> <FFFF>, bfchar sorted by code
      descendant: CIDFontType0 for a CFF face (Type0Only), no CIDToGIDMap;
        CIDFontType2 with /CIDToGIDMap /Identity otherwise; /CIDSystemInfo
        the ROS of a CID-keyed face, Adobe-Identity-0 otherwise

    WinAnsi font branch (builds /Widths, embeds font file):
      /FirstChar, /LastChar, /Widths from fWinAnsiUsed + ABC widths

      if IsEmbedded:
        GetSubset <> nil (prepared above, every platform since W2):
          ttf := Subset bytes; prefix /FontName and /BaseFont with Tag
          (the Unicode instance copies the prefixed name to its CIDFont and
           Type0 /BaseFont - WinAnsi instances are prepared first)
        else: fFace.GetFaceFile(ttf) - the
          whole face, a .ttc face extracted
        no bytes → raise EPdfInvalidOperation (since Phase 1b: before, the
          font went out without a font file)

        a CFF face: /FontName and /BaseFont := tag + program name
        CID-keyed: SfntTableOf(ttf, 'CFF ') → /FontFile3 /CIDFontType0C
        other OTTO: CheckFontProgram (PDF 1.6) → /FontFile3 /OpenType
        glyf: /FontFile2 /Length1
        GetOrCreateFontFile2(bytes, subtype) → one stream per bytes+subtype
      the WinAnsi font of a CFF face is internal: its dictionary is not
        written (fInternal), nor its /ToUnicode
  fFontSubsets := nil
```

### 4e — CJK Text Rendering Path (`UseUniscribe=false`)

Applies to: Chinese, Japanese, Korean, and any non-Latin non-RTL script.
CJK needs no GSUB shaping — `UseUniscribe=false` is sufficient and correct.

```
TPdfVclCanvas.SyncFont                              (pdfcanvas.pas:232)
│  fPdfCanvas.SetFont(Font.Name, Abs(Font.Size), style, Font.Charset)
│  Font.Charset = DEFAULT_CHARSET (1) by default
│
TPdfCanvas.SetFont(name, size, style, DEFAULT_CHARSET)   (pdf.pas:8749)
│  lfCharSet := DEFAULT_CHARSET                          (pdf.pas:8853)
│  lf.lfFaceName := 'Microsoft YaHei'  (or CJK font)
│  CreateFontIndirectW(@lf)   ← HFONT with DEFAULT_CHARSET
│  → WinAnsi font registered

C.TextOut(40, 80, CJK_CHAR_ZHONG)                   (pdfcanvas.pas:279)
│  StringToSynUnicode → [U+4E2D]
│  → TPdfCanvas.TextOutW → TPdfWrite.ShowText
│     → AddUnicodeHexTextNoUniScribe                  (pdf.pas:5484)

AddUnicodeHexTextNoUniScribe (U+4E2D):
│  WideCharToWinAnsi(U+4E2D) = -1   ← not WinAnsi
│  → AddGlyphFromChar(U+4E2D, Canvas, Ttf)            (pdf.pas:5419)
│     idx := Ttf.FindOrAddUsedWideChar(U+4E2D)        (pdf.pas:5428)
│       UnicodeFont = nil → CreateAssociatedUnicodeFont
│         TPdfTtf.Create(UnicodeFont).Free             (pdf.pas:6313)
│           GetTtfData(fDC, 'cmap', …)  → full CJK CMAP loaded
│           fUsedWideChar / fUsedWide populated for all CMAP code points
│       IndexOf(U+4E2D) → valid index i
│       fUsedWide[result].Used := UnicodeFont.fUsedWide[i].Used
│     Glyph := Ttf.fUsedWide[idx].Glyph   ← correct CJK glyph ID
│  Canvas.SetPdfFont(UnicodeFont, size)
│  Add('<XXXX> Tj')                         ← CID glyph reference
```

### 4f — Linux/macOS: FreeType Table Tag Byte-Order

Table tags from `GetTtfData` are little-endian DWORDs (`PCardinal(name)^`).
FreeType's `FT_Load_Sfnt_Table` expects big-endian (`FT_MAKE_TAG` convention).
`TFreeTypeFontFace.GetFontData` applies `bswap32(TableTag)` before the call.
`bswap32(0)` = 0 — the tag=0 "return whole font file" convention is preserved.

```
GetTtfData (pdf.pas:3604) — Linux/macOS path
│
│  tag := PCardinal(aTableName)^    ← LE: 'cmap' → $70616D63
│
│  aFace.GetFontData(tag, 0, nil, 0)
│    → TFreeTypeFontFace.GetFontData (mormot.lib.freetype)
│       bswap32($70616D63) = $636D6170   ← FT_MAKE_TAG('c','m','a','p')
│       FT_Load_Sfnt_Table(face, $636D6170, ...)  → returns CMAP bytes
│    → returns byte count
│
│  SetLength(Ref, L shr 1 + 1)
│  aFace.GetFontData(tag, 0, Ref, L) → CMAP data read
│  SwapBuffer(result, L shr 1)       → byte-swap big-endian TTF → LE
│  → returns pointer to CMAP data
│
P := GetTtfData(aUnicodeTtf.fFace, 'cmap', fcmap)  ← valid CMAP
TPdfTtf.Create → full CMAP loaded → CJK/Arabic glyph IDs resolved correctly
```

Tag mapping: see `fonts.md §12a`.

---

## Path 5 — Image Embedding

```
CreateOrGetBitmapImage(Doc, Bitmap, DrawAt, ClipRc)   (VCL/LCL, Phase 2: adapter)
│  hash := BitmapHash(Bitmap)  4 CRC32C lanes over the ScanLine[] rows (DIB
│                              rows on the VCL, BytesPerLine on the LCL),
│                              after the TPaletteEntry array and the color
│                              key of a pf24bit bitmap
│  Doc.GetXObjectImageName(hash, W, H) - existing image: reuse its name
│  else  ForceJPEGCompression = 0:
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

TPdfDocument.CreateOrGetImage(Pixels, DrawAt, ClipRc)  (no VCL/LCL)
│  CheckPixels → PixelsHash (row bytes, palette, format, color key)
│  → GetXObjectImageName / TPdfImage.CreatePixels / RegisterImage / DrawImage

TPdfCanvas.DrawXObject(X, Y, W, H, 'SynImg0')
│  TPdfWrite: 'q ... cm /SynImg0 Do Q'
└─ image rendered at position
```

---

## Path 6 — Optional Content (Layers)

```
TPdfDocument.CreateOptionalContentGroup(Parent, 'Layer Name')
│  creates TPdfOptionalContentGroup (PDF /OCG dictionary)
│
TPdfCanvas.BeginMarkedContent(Group)
│  TPdfWrite: '/OC /MC0 BDC'  (begin marked content)
│  all following draw commands belong to this layer
│
TPdfCanvas.EndMarkedContent
│  TPdfWrite: 'EMC'
│
TPdfDocument.CreateOptionalContentRadioGroup(Groups)
   links groups into a PDF /OCRadioGroups entry (mutually exclusive layers)
```

---

## Path 7 — Bookmarks & Links

```
// From TGDIPages (heading-level bookmarks):
TGDIPages.DrawHeading(1, 'Title')
  → after RenderPageToCanvas:
    TPdfDocument.CreateOutline('Title', 1, Y_pdf)
    │  creates TPdfOutlineNode in OutlineRoot
    └─ linked into the /Outlines tree at SaveToStream

// From application (manual):
TPdfDocument.CreateBookMark(Y_pdf, 'anchor')
  → creates TPdfDestination (named destination)

TPdfDocument.CreateLink(Rect, 'anchor')
  → creates TPdfAnnotation(asLink) referencing the named destination

TPdfDocument.CreateHyperLink(Rect, 'https://...')
  → creates TPdfAnnotation(asLink) with /URI action
```

---

## Path 8 — AES-128 Encryption (R-1)

```
TPdfEncryption.New(elAES_128, userPw, ownerPw, perms)
  → TPdfEncryptionAES128.Create(...)
      inherits TPdfEncryption.Create: stores passwords, permissions

TPdfEncryptionAES128.AttachDocument(aDoc)
  aDoc.fFileFormat raised to pdf16 if lower
  Key derivation (same as RC4-128 / Algorithm 3.2):
    Pad(user) → usr[32];  Pad(owner) → own[32]
    MD5(own) × 50 iterations → ownerKeyMD5[16]
    RC4.Init(ownerKeyMD5, 16) → RC4.Encrypt(usr, fOwnerPass)
    RC4 × 19 more iterations (Algorithm 3.3) → /O value
    MD5(usr + fOwnerPass + flags + fileID) × 50 → fInternalKey[16]
    Algorithm 3.5 (user pass validation) → fUserPass[32]
  Encryption dictionary (V=4, R=4, L=128):
    CF.StdCF: { CFM=AESV2, AuthEvent=DocOpen, Length=16 }
    StmF=StdCF, StrF=StdCF
    P=fFlags, O=fOwnerPass, U=fUserPass

TPdfEncryptionAES128.EncodeBuffer(BufIn, BufOut, Count)
  Per-object key (Algorithm 3.1a):
    MD5(fInternalKey[16] || objNum[3] || genNum[2] || 'sAlt') → objKey[16]
  RandomBytes → iv[16]   ← written first to BufOut
  PKCS7-pad BufIn to padLen := ((Count div 16)+1)*16
  TAesCbc.Create(objKey, 128); aes.IV := iv; aes.Encrypt(padBuf, BufOut+16, padLen)

GetEncryptedSize(InSize): 16 + ((InSize div 16)+1)*16
  → TPdfStream.InternalWriteTo uses this to pre-set /Length and allocate tmpEnc
  → string encryption callers (AddEscapeText, AddUnicodeHexStr) allocate via GetEncryptedSize
```

---

## Path 9 — Transparency via ExtGState (R-7)

```
TPdfCanvas.SetFillAlpha(Value: single)   [or SetStrokeAlpha]
  Value clamped to [0..1]
  intVal := Round(Value * 100)
  gsName := 'Fca' + IntToStr(intVal)     ['SCA' for stroke]
  extGs := fPage.GetResources('ExtGState')
  if extGs = nil:
    extGs := TPdfDictionary.Create(fDoc.fXRef)
    fPage.Resources.AddItem('ExtGState', extGs)
  if extGs.ValueByName(gsName) = nil:    ← deduplication
    gsDict := TPdfDictionary: { Type=ExtGState, ca=Value }   ['CA' for stroke]
    extGs.AddItem(gsName, gsDict)
  fContents.Writer.Add('/Fca50 gs')      ← emits graphics state operator
```

Entries accumulate in the page's ExtGState resource dict across multiple calls. Identical alpha values on the same page reuse the same entry (no duplicates). Minimum PDF version for transparency support: PDF 1.4.

---

## Path 10 — Tagged PDF Struct Tree (R-4/R-5/R-6/R-14)

Table shape emitted by `TGDIPages.RenderPageToCanvas` (R-14):

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
  fFileFormat raised to pdf17
  PDF/UA font mode: fStandardFontsReplace := false; fEmbeddedTtf := true;
                    fEmbeddedWholeTtf := FontSubsetter = nil
                    ← POSIX subsets (retain-gids keeps /ToUnicode valid, R-12);
                      Windows embeds the whole face
  Catalog: /MarkInfo << /Marked true >> /Lang 'en' /StructTreeRoot→fStructTree

TPdfDocument.AddPage
  page.fStructParents := fRawPages.Count - 1  ← /StructParents N
  if fMetaData = nil: (first tagged page, non-PDF/A)
    fMetaData := TPdfStream; Subtype=XML; Type=Metadata; fSaveAtTheEnd
    fFileID generated lazily
  catalog /ViewerPreferences gains vpDisplayDocTitle (PDF/UA-1 7.1, B-7)

TPdfCanvas path operators (m l c v y re, and Do)  ← B-9
  BeginPathArtifact: tagged and InMarkedContent = false
    → '/Artifact BMC' before the first construction operator
  painting operator (S s f f* B B* b b*) or 'n' → EndPathArtifact → 'EMC'
  inside an open region (e.g. Figure) nothing is added: real content
  SetPage closes a path artifact left open

TPdfCanvas.BeginArtifact / EndArtifact  ← explicit, e.g. repeated header row
  raises EPdfInvalidOperation inside a region / without a matching Begin

TPdfCanvas.BeginStructContent(ARole, AAltText='')
  if not fDoc.fTagged: exit  ← no-op guard
  elem: TPdfStructElement := (Role, PageIndex=fPage.fStructParents)
  fDoc.fStructElems.Add(elem)
  if fStructStack <> []: top.AddKid(elem)   ← nesting (B-1)
  fStructStack.Add(elem)
  if PDF_STRUCT_CONTAINER[ARole]: exit      ← Document/Table/TR/L/LI own no MCID
  mcid := fPage.fCurrentMCID; Inc(fPage.fCurrentMCID)   ← per-page counter
  elem.AddMCID(mcid, fPage.fStructParents)
  fContents.Writer.Add('/H1 <</MCID 3')     ← e.g.
  if AAltText <> '': fContents.Writer.Add(' /Alt (…)')
  fContents.Writer.Add('>> BDC')

TPdfCanvas.ResumeStructContent(Index, AOpenRegion=true)
  ← B-2: block continued on next page
  reopens fStructElems[Index]: pushes it again, allocates a new MCID on the
  current page, writes another BDC — the element then owns several MCIDs
  AOpenRegion=false: pushed back without a region (inline line, B-3)

TPdfCanvas.BeginStructGroup(ARole)           ← B-3: element without a region
  as BeginStructContent, but no MCID and no BDC

TPdfCanvas.ContinueStructContent             ← B-3: plain inline run
  top of fStructStack gains one more MCID + BDC; no-op if its region is open

TPdfCanvas.SuspendStructContent              ← B-3: before a nested Span
  writes 'EMC' for the top element but leaves it on fStructStack, so the next
  BeginStructContent still becomes its kid

TPdfCanvas.EndStructContent
  pops fStructStack; writes 'EMC' only when that element has an open region

SaveToStreamDirectEnd (called by ExportPdfStream):
  if fTagged:
    SerializeStructTree, then WriteTaggedMetadata:
      if fMetaData <> nil and fPdfA=pdfaNone:
        fMetaData filled with PDF/UA-1 XMP (pdfuaid:part=1, dc:title from
        Info.Title, XML-escaped) — here, not in SaveToStreamDirectBegin,
        because a streamed export creates fMetaData on its first AddPage (B-8)
      (PDF/A writes its packet in SaveToStreamDirectBegin, plus pdfuaid when
       tagged)
    SerializeStructTree details:
      one indirect dict per element; /P points at the real parent
      leaf without kids → /K MCR dict, or an array of MCR dicts (each with
        /Pg when it differs from the element's /Pg)
      element with kids → /K [kid dicts and own MCR dicts], merged in
        document order via KidSeqs[]/MCIDSeqs[] (B-3: P with Span kids)
      /ParentTree /Nums: per page an array indexed by MCID; an element
        continued across a page break appears in both pages' arrays
```

---

## Coordinate Conversion Summary

| Layer | Unit | DPI | Y origin | Conversion to PDF points |
|---|---|---|---|---|
| TGDIPages | 1/100 mm | — | top (Y=0) | `* 72 / (25.4 * 100)` |
| TPdfVclCanvas | pixels | 96 | top (Y=0) | `* 72 / 96`; Y-flip |
| TPdfCanvas | PDF points | 72 | bottom (Y=0) | identity |
| Screen preview | pixels | Screen DPI | top (Y=0) | `* ScreenDPI / (25.4 * 100)` |
| Printer | pixels | Printer DPI | top (Y=0) | `* PrinterDPI / (25.4 * 100)` |

All conversions happen at the boundary of each layer; inner code always works in its native unit.
