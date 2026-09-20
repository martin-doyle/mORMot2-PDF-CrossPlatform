# Platform Backends — IPdfPlatformFont / IPdfSystemFonts / IPdfPlatformDC (+ optional IPdfFontSubsetter)

Source: `src/core/mormot.pdf.types.pas`
Windows backend: `src/platform/windows/mormot.pdf.gdi.pas`
Unix/macOS backend: `src/platform/unix/mormot.pdf.freetype.pas`

---

## Three Interfaces

All platform-specific operations run exclusively through these three interfaces. The core (`mormot.ui.pdf.pas`) contains no `{$ifdef}` for platform details.

### IPdfPlatformFont — Font Operations

```pascal
IPdfPlatformFont = interface
  // Create a font object from a logical font descriptor
  function  CreateFont(const ALogFont: TPdfLogFont): TPdfPlatformFontHandle;
  // Release a previously created font
  procedure DeleteFont(AFont: TPdfPlatformFontHandle);
  // Select font into DC; returns the previously selected font handle
  function  SelectFont(ADC: TPdfPlatformDC;
                       AFont: TPdfPlatformFontHandle): TPdfPlatformFontHandle;
  // Retrieve basic text metrics for the currently selected font
  function  GetTextMetrics(ADC: TPdfPlatformDC;
                           out AMetrics: TPdfTextMetrics): boolean;
  // Retrieve extended outline metrics (ascent, descent, em-square, etc.)
  function  GetOutlineMetrics(ADC: TPdfPlatformDC;
                              out AMetrics: TPdfOutlineMetrics): boolean;
  // Retrieve ABC advance widths for characters FirstChar..LastChar
  function  GetCharABCWidths(ADC: TPdfPlatformDC;
                             FirstChar, LastChar: cardinal;
                             out AWidths: TPdfCharABCArray): boolean;
  // Read raw TrueType/OpenType table bytes (tag = 4-byte table name, e.g. 'cmap')
  // Returns bytes read, or FontDataError on failure
  function  GetFontData(ADC: TPdfPlatformDC;
                        ATableTag, AOffset: cardinal;
                        ABuffer: pointer; ABufferSize: cardinal): cardinal;
  // Sentinel value returned by GetFontData on error ($FFFFFFFF on all platforms)
  function  FontDataError: cardinal;
end;
```

### IPdfSystemFonts — Font Enumeration

```pascal
IPdfSystemFonts = interface
  // Fill List with UTF-8 encoded font family names available on the system
  procedure EnumTrueTypeFonts(ADC: TPdfPlatformDC;
                              var List: TRawUtf8DynArray);
end;
```

### IPdfPlatformDC — Device Context

```pascal
IPdfPlatformDC = interface
  // Create a compatible device context for font measurements
  // Windows: CreateCompatibleDC(0); Unix/macOS: returns non-nil dummy pointer
  function  CreateDC: TPdfPlatformDC;
  // Release a device context created by CreateDC
  procedure DeleteDC(ADC: TPdfPlatformDC);
  // Return screen DPI (Y axis); Unix/macOS always returns 96
  function  GetScreenLogPixels(ADC: TPdfPlatformDC): integer;
end;
```

---

## Registration

Each backend registers its implementations in the `initialization` section:

```pascal
// In mormot.pdf.gdi.pas (Windows):
initialization
  RegisterPdfPlatform(
    TPdfGdiFontProvider.Create,
    TPdfGdiSystemFonts.Create,
    TPdfGdiDCProvider.Create);

// In mormot.pdf.freetype.pas (Unix/macOS):
initialization
  RegisterPdfPlatform(
    TPdfFreeTypeFontProvider.Create,
    TPdfFreeTypeSystemFonts.Create,
    TPdfFreeTypeDCProvider.Create);
```

The global variables `PdfPlatformFont`, `PdfSystemFonts`, `PdfPlatformDCProvider` in `mormot.pdf.types.pas` are set. The core calls them directly.

```pascal
// Check whether a platform backend has been registered:
if not PdfPlatformRegistered then
  raise ESynException.Create('No PDF platform registered');
```

**Conditional uses in the application project (not in the core):**

```pascal
uses
  {$ifdef MSWINDOWS}
  mormot.pdf.gdi,       // registers GDI backend
  {$else}
  mormot.pdf.freetype,  // registers FreeType2 backend
  {$endif}
  mormot.ui.pdf;
```

---

## Data Types (mormot.pdf.types.pas)

### TPdfLogFont — Font Request Descriptor

```pascal
TPdfLogFont = record
  FaceName:       SynUnicode;  // font family name (e.g. 'Calibri')
  Height:         integer;     // character height in logical units (negative = cell height)
  Weight:         integer;     // FW_NORMAL=400, FW_BOLD=700
  Italic:         integer;     // 0 = upright, 1 = italic
  CharSet:        integer;     // 0 = ANSI_CHARSET
  PitchAndFamily: integer;     // FF_SWISS, FF_ROMAN, etc.
end;
```

### TPdfPlatformFontHandle / TPdfPlatformDC

```pascal
TPdfPlatformFontHandle = type pointer;  // opaque font handle
TPdfPlatformDC         = type pointer;  // opaque device context
```

### TPdfTextMetrics

```pascal
TPdfTextMetrics = record
  tmHeight, tmAscent, tmDescent: integer;
  tmInternalLeading, tmExternalLeading: integer;
  tmAveCharWidth, tmMaxCharWidth: integer;
  tmWeight: integer;
  tmOverhang: integer;
  tmFirstChar, tmLastChar, tmDefaultChar, tmBreakChar: integer;
  tmItalic, tmUnderlined, tmStruckOut: byte;
  tmPitchAndFamily, tmCharSet: byte;
end;
```

### TPdfOutlineMetrics

```pascal
TPdfOutlineMetrics = record
  otmSize:         cardinal;
  otmAscent:       integer;
  otmDescent:      integer;
  otmLineGap:      cardinal;
  otmItalicAngle:  integer;
  otmEMSquare:     cardinal;
  otmrcFontBox:    TRect;        // tight bounding box of all glyphs
  otmMacAscent, otmMacDescent, otmMacLineGap: integer;
  otmCapEmHeight, otmXHeight: cardinal;
  otmStrikeoutPosition, otmStrikeoutSize: integer;
  otmUnderscorePosition, otmUnderscoreSize: integer;
end;
```

### TPdfCharABC

```pascal
TPdfCharABC = record
  abcA: integer;   // pre-character spacing (can be negative)
  abcB: cardinal;  // glyph width (always positive)
  abcC: integer;   // post-character spacing (can be negative)
end;
TPdfCharABCArray = array of TPdfCharABC;
```

Total character advance = `abcA + abcB + abcC`.

---

## Windows Backend (mormot.pdf.gdi.pas)

GDI API mapping:

| Interface method | Windows API |
|---|---|
| `CreateFont` | `CreateFontIndirectW` |
| `DeleteFont` | `DeleteObject` |
| `SelectFont` | `SelectObject` |
| `GetTextMetrics` | `GetTextMetricsW` |
| `GetOutlineMetrics` | `GetOutlineTextMetricsW` |
| `GetCharABCWidths` | `GetCharABCWidthsA` (ANSI — code points above 255 are not reachable through this call) |
| `GetFontData` | `GetFontData` |
| `FontDataError` | returns `GDI_ERROR` ($FFFFFFFF) |
| `EnumTrueTypeFonts` | `EnumFontFamiliesExW` with TRUETYPE_FONTTYPE |
| `CreateDC` | `CreateCompatibleDC(0)` |
| `DeleteDC` | `DeleteDC` |
| `GetScreenLogPixels` | `GetDeviceCaps(DC, LOGPIXELSY)` |

No additional runtime dependency — GDI is part of Windows.

---

## Unix/macOS Backend (mormot.pdf.freetype.pas)

FreeType2 API mapping:

| Interface method | FreeType2 API |
|---|---|
| `CreateFont` | `FT_New_Face` + `FT_Set_Char_Size` |
| `DeleteFont` | `FT_Done_Face` |
| `SelectFont` | internal context switch |
| `GetTextMetrics` | `FT_FaceRec.ascender/descender/height` |
| `GetOutlineMetrics` | `FT_FaceRec.bbox` + scaled values |
| `GetCharABCWidths` | `FT_Load_Char` + `horiAdvance` |
| `GetFontData` | `FT_Load_Sfnt_Table` |
| `FontDataError` | returns $FFFFFFFF |
| `EnumTrueTypeFonts` | filesystem scan + `FT_New_Face` |
| `CreateDC` | dummy non-nil pointer (no real DC needed) |
| `DeleteDC` | no-op |
| `GetScreenLogPixels` | constant 96 |

**Font search paths:**

Linux:
- `/usr/share/fonts/**`
- `/usr/local/share/fonts/**`
- `~/.fonts/**`

macOS:
- `/Library/Fonts/**`
- `/System/Library/Fonts/**`
- `~/Library/Fonts/**`

If a font is not found: fallback to DejaVu Sans (Linux) or Helvetica (macOS).

**Runtime library:** `libfreetype.so.6` (Linux) / `libfreetype.6.dylib` (macOS) — loaded dynamically via `dlopen`. If not present: exception on first font access.

---

## Optional: IPdfFontSubsetter (mormot.pdf.hbsubset, Linux/macOS) — R-12

```pascal
TPdfFontSubsetRequest = record
  Unicodes: TIntegerDynArray;  // code points whose cmap entries must survive
  Glyphs: TIntegerDynArray;    // glyph IDs that must survive
end;

IPdfFontSubsetter = interface
  // false: face cannot be subset (CFF, invalid, library error) -> caller
  // embeds AFace unchanged; glyph IDs of ASubset equal those of AFace
  function Subset(const AFace: RawByteString;
    const ARequest: TPdfFontSubsetRequest; out ASubset: RawByteString): boolean;
end;

var PdfFontSubsetter: IPdfFontSubsetter;  // nil = no subsetter
```

- `mormot.ui.pdf` uses `mormot.pdf.hbsubset` on POSIX itself, like the FreeType
  backend: no project-side `uses` needed. Its `initialization` calls
  `LoadHarfBuzzSubset` and registers only when every symbol resolved, so
  `PdfFontSubsetter <> nil` means "usable"
- Two libraries: `hb_subset_*` from `libharfbuzz-subset.so.0` /
  `libharfbuzz-subset.0.dylib`, `hb_blob_*`/`hb_face_*`/`hb_set_*` from
  `libharfbuzz.so.0` / `libharfbuzz.0.dylib` (Homebrew paths tried on macOS)
- Needs HarfBuzz 2.9+ (`hb_subset_or_fail`, `hb_subset_input_set_flags`); older
  libraries leave it unregistered → whole-face embedding
- Tuning globals: `HbSubsetFlags` (default `RETAIN_GIDS or NOTDEF_OUTLINE or
  NO_HINTING`; `RETAIN_GIDS` is always forced), `HbSubsetDropLayoutTables`
  (default true: drop `GSUB/GPOS/GDEF`)
- Windows registers none and keeps `CreateFontPackage`
- How the engine builds the request and shares the result: `fonts.md` §3

---

## Document-Independent Measurement — TPdfFontMeasurer

`mormot.ui.pdf.pas` exposes the metrics of a face **without a `TPdfDocument`**, so `TGDIPages` can lay out its pages with the widths the PDF will really use (ROADMAP B-5):

```pascal
var M: TPdfFontMeasurer;
M := TPdfFontMeasurer.Create;
try
  if M.SetFont('Helvetica', {bold=}false, {italic=}false, {standardFonts=}true) then
    W := M.TextWidth('Hello', 11);   // PDF points
finally
  M.Free;
end;
```

- `SetFont` repeats `TPdfCanvas.SetFont`'s resolution order: the base-14 AFM tables (`STANDARDFONTS`) when `aStandardFonts` is set and the name is Helvetica/Times/Courier or an alias, otherwise `PdfPlatformFont.CreateFont` on a `Height = -1000` logfont plus `GetCharABCWidths(32, 255)` — i.e. 1000-per-em units, like every other width in the engine.
- Returns `false` when nothing resolves (no backend registered); the caller then falls back to its own measurement.
- Faces are cached per (name, bold, italic, standard-flag) on the measurer instance; `TPdfFaceMetrics` owns the platform font handle and its DC until the measurer is freed.
- Code points above WinAnsi use `DefaultWidth` — the GDI backend's `GetCharABCWidths` is the ANSI call, so per-code-point Unicode widths are not available through this path.

---

## Adding a New Platform

1. Create new unit `mormot.pdf.<platform>.pas`
2. Implement three classes:
   - `TPdf<Platform>FontProvider(TInterfacedObject, IPdfPlatformFont)`
   - `TPdf<Platform>SystemFonts(TInterfacedObject, IPdfSystemFonts)`
   - `TPdf<Platform>DCProvider(TInterfacedObject, IPdfPlatformDC)`
3. Register in `initialization` via `RegisterPdfPlatform(...)`
4. Add conditional `uses` in the application project

No changes to `mormot.ui.pdf.pas` required.
