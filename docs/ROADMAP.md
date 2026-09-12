# mORMot PDF Cross-Platform — Implementation Roadmap

This document describes all planned improvements with full technical background,
affected files, implementation steps, and verification criteria.

**Current baseline (as of this document):** rtl_demo and chinese_demo work on Windows.
Fixes A/B/C (ANSI_CHARSET, array bounds, evaluation order) and the VisualToLogical
loop fix are applied and committed.

---

## Priority 1-A — Fix fonts.md §10b Status

**Effort:** 5 minutes | **File:** `.claude/skills/fonts.md`

The skill file section §10b still says "Status: Fix not yet applied" even though
the VisualToLogical loop fix was applied in `src/core/mormot.ui.pdf.pas ~5420`.

**Change:** Update status line in fonts.md §10b from
`**Status:** Fix not yet applied` to
`**Status:** APPLIED (src/core/mormot.ui.pdf.pas ~5420)`.

**Verification:** No code change; cross-check call-graph.md Path 4c which already
shows the FIXED comments.

---

## Priority 1-B — CJK on Linux/macOS

**Effort:** 0.5 day | **Files:** `examples/chinese_demo/chinese_demo.lpr`,
`src/platform/unix/mormot.pdf.freetype.pas`

### Technical Background

On Linux/macOS the ANSI_CHARSET root cause does not exist:
- `fCodePage = CP_UTF8` (non-Windows) → `fCharSet = DEFAULT_CHARSET (1)` in
  `TPdfDocument` constructor (mormot.ui.pdf.pas ~7051–7054)
- FreeType backend reads the full CMAP via `FT_Load_Sfnt_Table('cmap')` —
  no GDI charset restriction applies
- `GetCharABCWidths` uses `FT_Load_Char + FT_GlyphSlot.advance.x` which works
  for any Unicode code point including all CJK blocks (U+4E00–U+9FFF)

CJK does not require text shaping (no GSUB ligatures) — the direct CMAP lookup
in `AddUnicodeHexTextNoUniScribe` is sufficient.

### Steps

1. Install a CJK font on the test Linux system:
   ```bash
   sudo apt install fonts-noto-cjk          # Debian/Ubuntu
   sudo dnf install google-noto-sans-cjk-fonts  # Fedora
   ```
   On macOS, system fonts include CJK coverage (e.g. PingFang SC, Hiragino).

2. In `chinese_demo.lpr`, set `FontFallBackName` for Linux/macOS:
   ```pascal
   {$ifdef OSWINDOWS}
   GetReportFonts(true, SansFont, SerifFont, MonoFont);
   Doc.FontFallBackName := 'Microsoft YaHei';
   {$else}
   SansFont := 'Noto Sans CJK SC';
   Doc.FontFallBackName := 'Noto Sans CJK SC';
   {$endif}
   ```

3. Build and run the chinese_demo on Linux:
   ```bash
   lazbuild examples/chinese_demo/chinese_demo_crossplat.lpi -B
   ./chinese_demo
   ```

4. Open the generated PDF and verify CJK characters render (no boxes □).

5. If the font is not found at runtime (fallback triggers), check the FreeType
   backend font search paths in `mormot.pdf.freetype.pas`:
   - Linux: `/usr/share/fonts/**`, `/usr/local/share/fonts/**`, `~/.fonts/**`
   - macOS: `/Library/Fonts/**`, `/System/Library/Fonts/**`, `~/Library/Fonts/**`

6. Extend `GetReportFonts()` in `mormot.pdf.types.pas` with a CJK font parameter
   if needed to allow callers to request a CJK-capable font by platform.

### Verification

```bash
strings chinese_demo.pdf | head -5   # Should show %PDF-
# Open PDF in viewer — no □ boxes, correct ideographs
```

---

## Priority 1-C — PDF Version 1.7 Output ✅ DONE

**Status:** APPLIED — `FileFormat` property, `PDF_HEADER` array, PDF/A and Tagged auto-upgrade all implemented.
`Tagged := true` now raises `FileFormat` to `pdf17` via `SetTagged` setter (mormot.ui.pdf.pas ~8676).

**Effort:** 2–3 hours | **Files:** `src/core/mormot.ui.pdf.pas`,
`src/core/mormot.pdf.types.pas`, `src/core/mormot.ui.report.pas`

### Technical Background

The `TPdfFileFormat` enum already exists in `mormot.pdf.types.pas`:
```pascal
TPdfFileFormat = (pdf13, pdf14, pdf15, pdf16, pdf17);
```

Currently `GeneratePdf15File: boolean` is the only way to request ≥ 1.5 output.
The PDF header (`%PDF-1.x`) is written in `TPdfDocument.SaveToStream` /
`TPdfDocument.NewDoc`.

PDF 1.7 = ISO 32000-1 (2008). For documents without transparency, object streams,
or xref streams, upgrading the header is the only required change for 1.7 output.
PDF viewers accept 1.7 headers even for documents using only 1.3 features.

### Steps

1. **Add `FileFormat` property to `TPdfDocument`** (`mormot.ui.pdf.pas`):
   ```pascal
   // In class declaration:
   fFileFormat: TPdfFileFormat;
   property FileFormat: TPdfFileFormat read fFileFormat write fFileFormat;
   ```
   Default value in constructor: `fFileFormat := pdf13`.

2. **Keep `GeneratePdf15File` as a compatibility alias:**
   ```pascal
   function GetGeneratePdf15File: boolean;
   begin result := fFileFormat >= pdf15; end;
   procedure SetGeneratePdf15File(Value: boolean);
   begin if Value then fFileFormat := pdf15; end;
   property GeneratePdf15File: boolean
     read GetGeneratePdf15File write SetGeneratePdf15File;
   ```

3. **Update PDF/A level interaction:** PDF/A 1.x requires PDF 1.4; PDF/A 2.x
   requires PDF 1.7. In `NewDoc` or `Create`, auto-set minimum FileFormat when
   a PDF/A level is set:
   ```pascal
   if PdfA in [pdfa2A, pdfa2B, pdfa3A, pdfa3B] then
     if fFileFormat < pdf17 then fFileFormat := pdf17
   else if PdfA in [pdfa1A, pdfa1B] then
     if fFileFormat < pdf14 then fFileFormat := pdf14;
   ```

4. **Update the header write code** (search for `%PDF-1.` in `mormot.ui.pdf.pas`):
   ```pascal
   const PDF_VERSION: array[TPdfFileFormat] of RawUtf8 = (
     '%PDF-1.3', '%PDF-1.4', '%PDF-1.5', '%PDF-1.6', '%PDF-1.7');
   // Replace the hard-coded header string with:
   Add(PDF_VERSION[fFileFormat]);
   ```

5. **Add `ExportPdfFileFormat` to `TGDIPages`** (`mormot.ui.report.pas`):
   ```pascal
   property ExportPdfFileFormat: TPdfFileFormat
     read fExportPdfFileFormat write fExportPdfFileFormat;
   ```
   Pass through in `ExportPdfStream`:
   ```pascal
   Doc.FileFormat := ExportPdfFileFormat;
   ```
   Default: `pdf13` (backward-compatible).

6. **Update demos:** In `pdf_demo` or `report_demo`, add a commented example:
   ```pascal
   Doc.FileFormat := pdf17;  // output PDF 1.7 (ISO 32000-1)
   ```

### Verification

```bash
# Build and run any demo, then:
head -c 10 out.pdf
# Expected: %PDF-1.7

# Verify file opens cleanly in a PDF viewer
# Verify GeneratePdf15File still works (backward compat)
```

---

## Priority 2-A — HarfBuzz Integration for RTL on Linux/macOS ✅ DONE

**Status:** APPLIED — Arabic renders with correct ligatures and cursive connections on Linux/macOS.

**Effort:** 3–5 days | **New file:** `src/platform/unix/mormot.pdf.harfbuzz.pas` |
**Modified:** `src/core/mormot.pdf.types.pas`, `src/core/mormot.ui.pdf.pas`,
`src/platform/unix/mormot.pdf.freetype.pas`

### Technical Background

On Windows, Uniscribe (`ScriptItemize` / `ScriptShape`) handles Arabic, Hebrew,
and all complex scripts. The result path is `AddUnicodeHexTextUniScribe` →
`AddGlyphs` — this infrastructure already exists and is reusable.

On Linux/macOS the equivalent is HarfBuzz:
- `libharfbuzz.so` (Linux, typically installed alongside FreeType)
- `libharfbuzz.dylib` (macOS, via `brew install harfbuzz`)
- HarfBuzz can use an existing `FT_Face` as its font backend directly

The call site in `mormot.ui.pdf.pas` already has the hook:
```pascal
if not shaped and (PdfTextShaper <> nil) then
  shaped := AddUnicodeHexTextHarfBuzz(PW, Len, ttf.WinAnsiFont, NextLine, Canvas);
```
`PdfTextShaper` is currently always nil; it needs a registration mechanism.

### Interface Definition (`mormot.pdf.types.pas`)

Add a new interface (alongside the existing three):
```pascal
IPdfTextShaper = interface
  ['{A1B2C3D4-...}']
  // Shape a run of Unicode text using OpenType GSUB/GPOS rules.
  // Returns false if shaping fails (caller falls back to NoUniscribe path).
  // AGlyphs: shaped glyph IDs in visual order
  // AAdvances: advance widths in 1000/em units (compatible with fUsedWide[].Width)
  // AClusters: maps each glyph back to source character index (for ToUnicode CMap)
  function ShapeText(AText: PWideChar; ALen: integer;
                     AFontHandle: TPdfPlatformFontHandle;
                     AIsRTL: boolean;
                     out AGlyphs: TWordDynArray;
                     out AAdvances: TIntegerDynArray;
                     out AClusters: TIntegerDynArray): boolean;
end;

var PdfTextShaper: IPdfTextShaper;  // nil until registered
```

### HarfBuzz Backend (`mormot.pdf.harfbuzz.pas`)

```pascal
unit mormot.pdf.harfbuzz;
// Registers IPdfTextShaper via HarfBuzz + FreeType backend.
// Runtime dependency: libharfbuzz.so.0 / libharfbuzz.dylib
// Load dynamically via dlopen (same pattern as mormot.pdf.freetype.pas).

type
  THarfBuzzTextShaper = class(TInterfacedObject, IPdfTextShaper)
  public
    function ShapeText(AText: PWideChar; ALen: integer;
                       AFontHandle: TPdfPlatformFontHandle;
                       AIsRTL: boolean;
                       out AGlyphs: TWordDynArray;
                       out AAdvances: TIntegerDynArray;
                       out AClusters: TIntegerDynArray): boolean;
  end;

initialization
  PdfTextShaper := THarfBuzzTextShaper.Create;
```

Key HarfBuzz API calls needed:
```c
hb_font_t* hb_ft_font_create(FT_Face ft_face, NULL);
hb_buffer_t* hb_buffer_create();
hb_buffer_add_utf16(buf, text, len, 0, -1);
hb_buffer_set_direction(buf, HB_DIRECTION_RTL or HB_DIRECTION_LTR);
hb_buffer_set_script(buf, HB_SCRIPT_ARABIC / HB_SCRIPT_HEBREW / ...);
hb_shape(font, buf, NULL, 0);
hb_glyph_info_t*     infos    = hb_buffer_get_glyph_infos(buf, &count);
hb_glyph_position_t* positions= hb_buffer_get_glyph_positions(buf, &count);
// infos[i].codepoint = glyph ID; positions[i].x_advance = advance (in HB units)
```

HarfBuzz advance units: `position.x_advance` is in 64ths of a design unit when
`hb_ft_font_create` is used. Convert to 1000/em units:
```pascal
// FT_Face.units_per_EM is the em square size (e.g. 2048 for most fonts)
// HarfBuzz x_advance is in 26.6 fixed point of design units / 64
// Scale: Width_1000 = (x_advance * 1000) div (FT_Face.units_per_EM * 64)
```

### `AddUnicodeHexTextHarfBuzz` (`mormot.ui.pdf.pas`)

This function should mirror `AddUnicodeHexTextUniScribe` but consume HarfBuzz output:

```pascal
function TPdfWrite.AddUnicodeHexTextHarfBuzz(PW: PWideChar; WLen: integer;
  Ttf: TPdfFontTrueType; NextLine: boolean; Canvas: TPdfCanvas): boolean;
var
  Glyphs: TWordDynArray;
  Advances: TIntegerDynArray;
  Clusters: TIntegerDynArray;
begin
  result := false;
  if (PdfTextShaper = nil) or (Ttf = nil) then exit;
  if not PdfTextShaper.ShapeText(PW, WLen, Ttf.fHGDI,
       Canvas.RightToLeftText, Glyphs, Advances, Clusters) then exit;
  // Register all shaped glyphs via GetAndMarkGlyphAsUsed
  // (Step 3 for POSIX needs implementing — see below)
  AddGlyphs(Glyphs, length(Glyphs), Canvas);
  result := true;
end;
```

### GetAndMarkGlyphAsUsed Step 3 on POSIX

Currently Step 3 (`GetCharABCWidthsI` for GSUB-substituted glyph advance widths)
is `{$ifdef OSWINDOWS}` only. On POSIX, glyphs not found in the CMAP fall back
to `/DW` (default width), causing incorrect character spacing for shaped Arabic.

For the HarfBuzz path, the advance widths come directly from HarfBuzz
(`positions[i].x_advance`). Pass these widths alongside glyph IDs into
`GetAndMarkGlyphAsUsed` via a new overload or extended parameter:
```pascal
procedure GetAndMarkGlyphAsUsedWithWidth(aGlyph: word; aWidth: integer);
```
This avoids the need for `GetCharABCWidthsI` on POSIX entirely.

### Registration in mormot.pdf.freetype.pas

Add to `initialization`:
```pascal
{$ifdef UNIX}
if HarfBuzzAvailable then     // dlopen check
  PdfTextShaper := THarfBuzzTextShaper.Create;
{$endif}
```
The existing FreeType registration remains; HarfBuzz supplements it for shaping.

### Verification

```bash
lazbuild examples/rtl_demo/rtl_demo_crossplat.lpi -B
./rtl_demo
# Open rtl_demo.pdf — Arabic section must show shaped glyphs, not boxes
# Compare with Windows output: character forms should match
```

---

## Priority 2-C — Font Zoom in Preview ✅ DONE

**Status:** APPLIED (Commit `505bed0`) — `FontScale` computed in `RenderPageToCanvas`, applied to all text commands.

**Effort:** 0.5–1 day | **File:** `src/core/mormot.ui.report.pas`

### Technical Background

`TGDIPages.RenderPageToCanvas(ACanvas, PageIndex, DestW, DestH, SourceDPI)` scales
all 1/100mm coordinates to the destination canvas size. However, font sizes are set
as `ACanvas.Font.Size := <base_size>` (in points), which does not automatically
scale when `DestW/DestH` differ from the 96-DPI baseline.

The scale factor should be: `ScaleY = DestH / (PageHeight_mm * SourceDPI / 25.4)`

### Steps

1. In `RenderPageToCanvas`, calculate the vertical scale factor once at the start:
   ```pascal
   ScaleFactor := DestH / (fPageHeight * SourceDPI / (25.4 * 100));
   ```

2. For every `dckDrawText` and `dckHeading` command, apply the scale to Font.Size:
   ```pascal
   ACanvas.Font.Size := Round(Cmd.FontSize * ScaleFactor);
   ```
   `Cmd.FontSize` is the base font size stored in the `TDrawCommand` record.

3. Test zoom levels in the preview window: 50%, 75%, 100%, 150%, 200%.
   Verify text scales proportionally to the page area with no clipping or overlap.

### Verification

- Open report_demo, zoom to 200%: text and page outline scale together
- Zoom to 50%: readable, no layout overflow

---

## Priority 3 — Tagged PDF (Text-Relevant Structure Tags Only) ✅ DONE

**Effort:** 3–5 days | **Files:** `src/core/mormot.ui.pdf.pas`,
`src/core/mormot.ui.report.pas`

### Scope

This phase implements accessibility structure tags for text content only.
Images (Figure), tables (Table/TR/TD), form fields, and artifacts are
deferred to the "Rest" section.

Required PDF structures (§14 of ISO 32000-1):
- `/MarkInfo << /Marked true >>` in the document catalog
- `/StructTreeRoot` with a structure tree
- `/Lang` in the catalog (e.g. `'en'`, `'de'`)
- Structure elements (`/StructElem`) for: `H1`–`H6`, `P`, `Span`
- Marked content identifiers (`/MCID`) in content streams
- `/ParentTree` number tree: MCID → StructElem (required for conformance)

### New Classes (`mormot.ui.pdf.pas`)

```pascal
TPdfStructRole = (psrDocument, psrH1, psrH2, psrH3, psrH4, psrH5, psrH6,
                  psrP, psrSpan);

const PDF_STRUCT_ROLE: array[TPdfStructRole] of RawUtf8 = (
  'Document', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'P', 'Span');

TPdfStructElement = class
  Role: TPdfStructRole;
  PageObjNum: integer;   // PDF object number of the page dictionary
  MCID: integer;         // marked content identifier on this page
  ObjNum: integer;       // this StructElem's object number (assigned at save)
  Parent: TPdfStructElement;
  Children: array of TPdfStructElement;
end;
```

### New Properties (`TPdfDocument`)

```pascal
property Tagged: boolean read fTagged write fTagged;
property DefaultLanguage: RawUtf8 read fDefaultLanguage write fDefaultLanguage;
```

### Content Stream Changes

When `Tagged = true`, every text emission must be wrapped in marked content:
```
/P <</MCID 0>> BDC
BT (Hello) Tj ET
EMC
```

New canvas methods:
```pascal
procedure TPdfCanvas.BeginStructContent(Role: TPdfStructRole; MCID: integer);
// Writes: /<Role> <</MCID N>> BDC
procedure TPdfCanvas.EndStructContent;
// Writes: EMC
```

These are separate from `BeginMarkedContent`/`EndMarkedContent` (which are for
optional content layers / `/OC`).

### MCID Counter

Add `fCurrentMCID: integer` to `TPdfPage`, incremented for each marked content
region on the page. Reset to 0 on each new page.

### Catalog Additions (`SaveToStream`)

When `Tagged = true`, add to the catalog dictionary before writing:
```
/MarkInfo << /Marked true >>
/Lang (en)
/StructTreeRoot N 0 R
```

### StructTreeRoot and ParentTree Serialization

At `SaveToStream`, after all pages are written:
1. Assign object numbers to all `TPdfStructElement` instances
2. Write each `TPdfStructElement` as a PDF dictionary:
   ```
   N 0 obj
   << /Type /StructElem /S /H1 /P M 0 R /Pg P 0 R /K << /Type /MCR /MCID 0 >> >>
   endobj
   ```
3. Write the `ParentTree` number tree mapping each MCID to its StructElem object
4. Write the `StructTreeRoot` pointing to all top-level StructElems and the ParentTree

### TGDIPages Integration (`mormot.ui.report.pas`)

Add property `ExportPdfTagged: boolean` to `TGDIPages`.

In `ExportPdfStream`, when `ExportPdfTagged = true`:
- Set `Doc.Tagged := true` and `Doc.DefaultLanguage := ExportPdfLanguage`
- For each command in `RenderPageToCanvas`:
  - `dckHeading` with level L → `BeginStructContent(TPdfStructRole(L), MCID)`
  - `dckDrawText` → `BeginStructContent(psrP, MCID)`
  - Wrap the existing canvas call between Begin/EndStructContent

### Verification

```bash
# Install veraPDF (free, open-source PDF/UA validator):
# https://verapdf.org
veraPDF --flavour 1b output.pdf    # Check PDF/A-1b
veraPDF --flavour ua1 output.pdf   # Check PDF/UA-1

# Minimum expected: MarkInfo present, StructTreeRoot present, no MCID gaps
# Adobe Acrobat Pro → Tools → Accessibility → Reading Order: shows headings
```

---

## Rest — Remaining Items

These items are planned but have lower priority than the above.

### P2-B — AES Encryption (PDF 1.7)

**Effort:** 1–2 days | **Files:** `src/core/mormot.ui.pdf.pas`

RC4 is deprecated as of PDF 2.0. PDF 1.7 introduced AES-128 (PDF 1.6 technically).

Extend `TPdfEncryptionLevel`:
```pascal
TPdfEncryptionLevel = (elNone, elRC4_40, elRC4_128, elAES_128, elAES_256);
```

Use `mormot.crypt.core` `TAesFast` for AES-CBC stream cipher. The encryption
dictionary needs `/Filter /Standard /V 4 /R 4` for AES-128, `/V 5 /R 6` for AES-256.

### Cross-Reference Streams (PDF 1.5+)

**Effort:** 2–3 days

Replace the text-format `xref` table with a compressed `/XRef` stream.
Required for Object Streams. Reduces file size for documents with many objects.

### Object Streams (PDF 1.5+)

**Effort:** 2–3 days

Batch small PDF objects into `/ObjStm` compressed streams. Significant file size
reduction for documents with many font dictionaries, annotations, or struct elements.

### XMP Metadata (`/Metadata` stream)

**Effort:** 1 day

PDF/UA-1 requires an XMP metadata stream in the catalog. The stream contains
RDF/XML describing the document (title, author, PDF/UA identifier).

### Table Structure Tags (P3 Extension)

**Effort:** 2 days

Extend P3 to include `/Table /TR /TD /TH` StructElems for tables produced by
`TGDIPages.BeginTable` / `DrawTableRow` / `EndTable`.

### Figure Tags (Image Accessibility)

**Effort:** 1 day

Wrap `DrawXObject` calls in `/Figure <</MCID N>> BDC ... EMC` and attach a
`/Alt` string to each Figure StructElem.

### Transparency (`/ExtGState /ca /CA`)

**Effort:** 2 days

Add `TPdfCanvas.SetFillAlpha(value: single)` and `SetStrokeAlpha(value: single)`.
Requires adding an ExtGState dictionary to the page resources and `/gs0 gs` operator.
Minimum PDF version 1.4.

### Line Height Configurable

**Effort:** 0.5 day | **File:** `src/core/mormot.ui.report.pas`

The line height multiplier is hardcoded at approximately 1.3 × FontSize. Add:
```pascal
property LineHeightFactor: single  // default 1.3
```
to `TGDIPages` and apply it in the vertical advance calculation.

### Table Row Pagination

**Effort:** 2–3 days | **File:** `src/core/mormot.ui.report.pas`

Currently a table row that is taller than the remaining page space triggers a full
page break before the row. Allow the row to split across pages: emit partial cell
content on the current page, continue on the next page.

---

## Summary Table

| ID | Feature | Effort | Files |
|---|---|---|---|
| P1-A | Fix fonts.md §10b status | 5 min | .claude/skills/fonts.md |
| P1-B | CJK on Linux/macOS | 0.5 day | chinese_demo, freetype.pas |
| P1-C | PDF 1.7 output ✅ | DONE | mormot.ui.pdf.pas, mormot.pdf.types.pas, report.pas |
| P2-A | HarfBuzz RTL on Linux/macOS ✅ | DONE | harfbuzz.pas (new), types.pas, pdf.pas |
| P2-C | Font zoom in preview ✅ | DONE | mormot.ui.report.pas |
| P3 | Tagged PDF (text tags) ✅ | DONE | mormot.ui.pdf.pas, mormot.ui.report.pas |
| R-1 | AES-128 encryption ✅ | DONE | mormot.ui.pdf.pas (TPdfEncryptionAES128) |
| R-2 | xref streams ✅ | DONE | mormot.ui.pdf.pas (TPdfTrailer.ToCrossReference, pdf15+) |
| R-3 | Object streams ✅ | DONE | mormot.ui.pdf.pas (TPdfTrailer.ToCrossReference, pdf15+) |
| R-4 | XMP metadata ✅ | DONE | mormot.ui.pdf.pas (AddPage lazy setup + SaveToStreamDirectBegin) |
| R-5 | Table structure tags ✅ | DONE | mormot.ui.pdf.pas, mormot.ui.report.pas (dckBeginTR/EndTR) |
| R-6 | Figure tags + /Alt ✅ | DONE | mormot.ui.pdf.pas (BeginStructContent AAltText), report.pas |
| R-7 | Transparency ✅ | DONE | mormot.ui.pdf.pas (SetFillAlpha/SetStrokeAlpha + ExtGState) |
| R-8 | Line height property ✅ | DONE | mormot.ui.report.pas (LineHeightFactor property) |
| R-9 | Table header repeat ✅ | DONE | mormot.ui.report.pas (fTableSavedHeaders, auto-repeat on page break) |
