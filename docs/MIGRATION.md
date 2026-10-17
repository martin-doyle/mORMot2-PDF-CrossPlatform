# Migrating From `mormot.ui.pdf` and `mormot.ui.report`

For programs that use the PDF units of the mORMot2 trunk, `src/ui/mormot.ui.pdf.pas`
and `src/ui/mormot.ui.report.pas`, and move to this engine. The trunk units go
at the 2.5 merge (docs/REFACTORING.md, Phase 4); there is no compatibility unit.

- **`mormot.ui.pdf`:** a change of `uses` and a few calls. Every public class,
  type and routine of the trunk unit exists under its old name.
- **`mormot.ui.report`:** a port. This `TGDIPages` is another class with the
  same name, and most of the trunk's methods have no counterpart.

The trunk state compared is that of the `pdf-font-layer` branch of
`landrix/mORMot2`: the trunk plus the `mormot.lib.*` units this engine
needs, which are not in the trunk yet.

## The Units

| Trunk | Now | For |
|---|---|---|
| `mormot.ui.pdf` | `mormot.pdf` | `TPdfDocument`, `TPdfCanvas`, fonts, images from pixels or JPEG; no VCL/LCL, every platform |
| `mormot.ui.pdf` | `mormot.pdf.canvas` | `TPdfDocumentVcl` (the TCanvas bridge), `TBitmap`/`TGraphic` images; on Windows `TPdfDocumentGdi`, `TPdfPageGdi`, `TPdfForm`, `RenderMetaFile`, the `GdiComment*` functions, `CurrentPrinterPaperSize`, `CurrentPrinterRes` |
| `mormot.ui.report` | `mormot.pdf.report` | `TGDIPages`: recording and PDF export, no `Forms`, no `Printers` |
| `mormot.ui.report` | `mormot.pdf.report.preview` | `ShowReportPreview`, `PrintReport` (LCL only) |

A report program uses `mormot.pdf.report` alone: it re-exports the PDF/A
levels, `TPdfFileFormat`, `afr*`, the page modes and `PdfMetadataFacturX`.
Do not put `mormot.pdf` beside it: both declare `psA4`, and `TRect` differs
from the LCL's, so the `uses` order would decide which one a name means.

**mORMot2 sources:** until the merge, the `pdf-font-layer` branch of
`landrix/mORMot2`, not the trunk: `mormot.pdf` uses `mormot.lib.core`,
`mormot.lib.freetype` and `mormot.lib.harfbuzz`, which only that branch
has in `src/lib`, and the font services that branch adds to the trunk's
`mormot.lib.uniscribe`. With a trunk checkout the build stops at the first
of them it needs.

**Search path:** this repository's `src/pdf`, and on Windows mORMot2's
`src/ui` for `mormot.ui.core` and `mormot.ui.gdiplus` (any project with
`mormot.pdf.canvas`). The `mormot2ui` package still lists the trunk's
`mormot.ui.pdf`: it does not bring this engine. A package for `src/pdf`
comes with the merge.

**Compilers and platforms:**

| | Trunk | Now |
|---|---|---|
| `mormot.ui.pdf` / `mormot.pdf` | Windows, VCL or LCL | Windows, Linux, macOS; FPC, Delphi 7 and later |
| TCanvas bridge, bitmaps | Windows | FPC with the LCL everywhere; Delphi on Windows |
| report | Delphi on Windows (an empty unit on FPC) | FPC/LCL everywhere, Delphi on Windows |
| report preview | Delphi on Windows | LCL only - none for Delphi yet (ROADMAP R-20) |

On POSIX the engine needs `libfreetype`; HarfBuzz is optional (shaping,
subsetting). See the README, "Runtime dependencies".

## `mormot.ui.pdf` → `mormot.pdf`

### Calls That Change

| Trunk | Now |
|---|---|
| `Doc.CreateOrGetImage(Bitmap, DrawAt, ClipRc)` | `CreateOrGetBitmapImage(Doc, Bitmap, DrawAt, ClipRc)` of `mormot.pdf.canvas`; `Doc.CreateOrGetImage` takes a `TPdfImagePixels` now |
| `TPdfImage.Create(Doc, Graphic, DontAddToFXref)` | `CreateGraphicImage(Doc, Graphic, DontAddToFXref)` of `mormot.pdf.canvas`; without the VCL/LCL `TPdfImage.CreatePixels`, `CreateJpeg` or `CreateJpegDirect` |
| an empty `TGraphic` | raises `EPdfInvalidValue` |

Unchanged, but Windows only: the `TLogFontW` constructor of
`TPdfFontTrueType` (beside a portable `TFontRequest` one) and
`TPdfCanvas.SetFont(HDC, TLogFontW, Size)`. Extended with a default
parameter, so existing calls compile: `CreateFileAttachment`
(`Relationship = afrAlternative`), `TPdfFont.Create` (`ARegister = true`).

A class derived from `TPdfDocument` or `TPdfFontTrueType` loses the
protected font DC (`GetDCWithFont`): fonts are `TFontRequest`,
`TFontMetrics`, `TFontOutlineMetrics` and an `IFontFace` of `mormot.lib.core`.
`TPdfWrite.B`/`BEnd`/`BEnd4` are `fB`/`fBEnd`/`fBEnd4`, and its protected
`AddUnicodeHexTextUniScribe` is gone.

### Behaviour That Changes

- **`ScreenLogPixels` of a plain `TPdfDocument` is 96**, not the screen's
  DPI; on Windows `TPdfDocumentGdi` and `TPdfDocumentVcl` still read the
  screen, on Linux and macOS they keep 96. Set it before the first page
- **`UseUniscribe` is the one shaping switch:** Uniscribe on Windows,
  HarfBuzz on Linux and macOS, only for the runs of a script that needs it.
  `RightToLeftText` is the direction only
- **A font that cannot be embedded raises:** when embedding is asked for
  (`EmbeddedTtf`, `Tagged`, PDF/A) and neither a subset nor the whole face
  can be read, saving raises `EPdfInvalidOperation`. The trunk wrote the font
  without its file. With plain `EmbeddedTtf`, `EmbeddedTtfIgnore` writes such
  a font unembedded
- **New: `Tagged`** (PDF/UA): set it before the first `AddPage`; it embeds
  every font and switches `StandardFontsReplace` off
- **New: fonts from memory** with `RegisterFontData`, before the document is
  created

### Output That Differs

The defaults are the same (`EmbeddedTtf`, `EmbeddedWholeTtf` and
`StandardFontsReplace` all false): nothing is embedded that was not
before. The font objects can still differ, embedded or not:

- **Subsets on Windows** keep the glyph IDs (FontSub with a glyph list), one
  subset per face; PDF/A-1 embeds the whole face. A face of a `.ttc` is
  extracted from the collection, not guessed by its family name
- **`/ToUnicode`** for the WinAnsi fonts of tagged output too; the Type0
  codespace is `<0000> <FFFF>`, `/W` and the mappings sorted by code
- **The fallback font** draws WinAnsi characters the face lacks; a run that
  switched to it mid-way wrote a broken string in the trunk
- **Widths** of faces whose `unitsPerEm` is no power of two, and of glyphs
  past the last `hmtx` pair, are read correctly - text can wrap differently
- **CFF (OpenType) faces** are embedded as CFF in a Type0 font
  (`/FontFile3`), not in `/FontFile2`. A name-keyed CFF face needs PDF 1.6
  and is refused in PDF/A-1: such an export raises - choose another face
  or another PDF/A level
- **Faces with a format 12 cmap only** draw their BMP characters; characters
  above U+FFFF stay unsupported
- **`x:xmptk="mormot.ui.pdf"`** in the XMP stays until the units move into
  the trunk

The full list, with the reason for each: CHANGELOG.md and docs/ROADMAP.md,
"To Announce".

## `mormot.ui.report` → `mormot.pdf.report`

The trunk's `TGdiPages` is a `TScrollBox` that draws metafile pages and shows
them itself. This `TGDIPages` is a `TComponent` that records drawing
commands; the PDF export and the preview render them. Pascal names are not
case-sensitive, so the two classes cannot be told apart by their spelling:
a port changes the `uses` and every call below.

**Units:** positions and sizes are **1/100 mm** within the printable area,
the trunk's millimetres times 100. `AddVerticalSpace` is the one method in
millimetres.

| Trunk | Now |
|---|---|
| `TGdiPages.Create(Owner)` on a form, `Parent`, `Align` | `TGDIPages.Create(Owner)`, no control; the preview is `ShowReportPreview` |
| `BeginDoc` ... `EndDoc` | set the options, `NewPage`, draw, `EndDoc`; a new report is a new instance |
| `NewPage(ForceEndGroup)` | `NewPage`, `ForceNewPage` |
| `NewPageIfAnyContent` | no counterpart: both methods always add a page, so keep track of whether the page has content |
| `PageMargins` (10 mm at `BeginDoc`) | `MarginLeft`, `MarginRight`, `MarginTop`, `MarginBottom` in 1/100 mm, default 2000 (20 mm) |
| `CurrentYPos` | `CurrentY`, read-only; `CurrentX` |
| `NewLine`, `NewHalfLine`, `NewLines`, `LineSpacing` | `MoveToNextLine(Offset)`, `AddVerticalSpace(mm)`, `LineHeightFactor` (1.1); they move Y only - set `CurrentX := 0` to start a line after inline text |
| `DrawText(S)` - a wrapped paragraph | `DrawParagraph(S)` with the format `P`, or `DrawTextWrapped(X, MaxWidth, Y, S)`; `DrawText(S)` now draws inline and advances X. Both wrap at spaces only and align left: split the text at its line breaks yourself; no justified or right-aligned paragraphs |
| `DrawTextFmt` | format the text first, then draw it |
| `DrawTextAt(S, XPos, Link, ...)`, `TextAlign` | `DrawTextAt(X, Y, S)`, `DrawTextRight`, `DrawTextCenter` |
| `DrawTitle(S, DrawBottomLine, OutlineLevel, ...)` | `DrawHeading(Level, S)` (1 to 6), its look by `DefineFormat`; outlines with `UseOutlines := true` (default false, the trunk's true) |
| `Font.Name`, `Font.Size`, `Font.Style`, `Font.Color` | `SetFont(Name, Size)`, `FontStyle`, `TextColor`; the first font is the platform's sans at 10 pt (the trunk's Tahoma 12) |
| `SaveLayout`, `RestoreSavedLayout` | `SaveLayout`, `RestoreLayout` - font, style and color, not the cursor |
| `AddColumns(Percent)`, `AddColumnHeaders`, `DrawTextAcrossCols` | a `TTableLayout` with widths in 1/100 mm and `tcaLeft`/`tcaCenter`/`tcaRight`; `BeginTable`, `DrawTableHeader`, `DrawTableRow`, `DrawTableFooter`, `EndTable` - the header repeats on a new page. A cell is one line, neither wrapped nor clipped (no `WordWrapLeftCols`): a long text runs into the next column |
| header and footer lists | `SetHeader(S)`, `SetFooter(S)`, one text each, `{#}` and `{total}` for the page numbers |
| `PaperSize: TSize`, `Orientation: TPrinterOrientation` | `PaperSize: TGdiPagePaperSize` (A4, A5, A3, Letter, Legal), `Orientation: TReportOrientation`, before `NewPage`; no custom size |
| `ExportPdf(FileName, ShowError, Launch): boolean` | `ExportPDF(FileName, false, false, Title, Company)`, a procedure that raises; `Protect` or `Encrypt` true raises `EPdfReport` |
| `ExportPdfStream(Stream, RaiseException)` | the same |
| `ExportPdfEmbeddedTTF` (default false) | the same, default true |
| - (the trunk never replaced fonts) | `ExportPdfStandardFonts`, default **true**: Arial, Times New Roman and Courier New become the unembedded Helvetica, Times and Courier, with their metrics and WinAnsi only. Set it to false before the first `NewPage` to keep the TrueType faces (`ExportPdfTagged` does that itself) |
| `ExportPdfGeneratePdf15File` (false: PDF 1.4) | `ExportPdfFileFormat`, default `pdf13`: `pdf14` or `pdf15` for the trunk's output |
| `ExportPdfApplication` (`/Creator`, the application title when empty) | `ExportPdfCreator` (the executable's name when empty) |
| `ShowPreviewForm(Buttons)` | `ShowReportPreview(Report)`: modal, navigation and zoom, LCL only |
| `PrintPages(From, To)` - 1-based, (0, 0) all, negative a dialog | `PrintReport(Report, From, To)` - 0-based, all by default, the current printer settings, no dialog |
| `Pages`, `PageCount` | `Pages[Index]` holds commands, not metafiles; `PageCount`; `CurrentPageIndex` is 1-based |
| `EReport` | `EPdfReport` (an `ESynException`) |

New, with no trunk counterpart: tagged PDF (`ExportPdfTagged`, before the
first `NewPage`), PDF/A-3 attachments (`AddExportPdfAttachment`), named
formats (`DefineFormat`: H1 to H6, P, Strong, Em, Code), lists, quotes,
captions, `Columns2`.

**Gone, to be rewritten in the program:**

- the GDI `Canvas` of a page, metafile pages, `DrawBmp`, `DrawMeta`,
  `DrawGraphic` - there is no public image method in the report yet; draw
  images through `mormot.pdf.canvas`
- `AppendRichEdit`, rotated text, arrows, dashed and double lines. The
  trunk's `DrawLine(DoubleLine)` spanned the margins and moved the cursor:
  now `DrawLine(X1, Y1, X2, Y2, Width, Color)` and then `MoveToNextLine`;
  its `DrawBoxFilled` drew a border too: now `DrawFilledRect` and four
  `DrawLine`
- groups (`BeginGroup`/`EndGroup`), tab stops, hanging indents, `HasSpaceFor*`,
  currency columns
- bookmarks and links: headings make outlines; `DrawLink` draws the text as a
  link but writes no link annotation (ROADMAP R-29)
- `TextWidth`: the report has no public text measuring
- the report unit's printer functions `CurrentPrinterName`,
  `CurrentPrinterPaperSize` (a string, not the `TPdfPaperSize` one of
  `mormot.pdf.canvas`), `UseDefaultPrinter`, `SetCurrentPrinterAsDefault`
- `BiDiMode` and the export's shaping and fallback options
- background image, keywords, encryption
- the preview's buttons, menus, clipboard and the page and zoom events

## Tests

The trunk's `test/test.ui.pdf.pas` uses `mormot.ui.pdf`. It moves to
`mormot.pdf` and `mormot.pdf.canvas` with the merge; its font hashes depend
on the installed fonts and may change. This repository's suites go to
`mormot2tests` as `test.pdf.*.pas` (docs/REFACTORING.md).
