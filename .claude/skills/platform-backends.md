# Platform Backends — IFontFace / IFontProvider / IFontEnumerator (+ optional IFontShaper / IFontSubsetter)

Contracts: `src/lib/mormot.lib.core.pas` of mORMot2 (during the refactoring
the branch `pdf-font-layer` of `landrix/mORMot2`, see `docs/REFACTORING.md`)
Former names, as aliases: `src/core/mormot.pdf.types.pas`
Windows backend: mORMot2 `src/lib/mormot.lib.uniscribe.pas` (the GDI services)
Unix/macOS backends: mORMot2 `src/lib/mormot.lib.freetype.pas` and
`mormot.lib.harfbuzz.pas` (shaper and subsetter), in the same branch

---

## The Font Interfaces

Every platform goes through them: since W3 (2026-10-09) for the engine's
font calls, since Phase 1b (2026-10-09) without a device context.
`TPdfFontTrueType` asks `FontProvider.CreateFace` for an `IFontFace` and reads
metrics, widths, tables, the embedded face and glyph advances by index from
it; the WinAnsi and the Unicode instance share that one face (reference
counted - no destructor deletes a font any more). `TPdfFaceMetrics`
(`TPdfFontMeasurer`) holds a face as well. Shaping and subsetting go through
`FontShaper` and `FontSubsetter` (W2) with the face's native `Handle`.

What stays Windows-only in `mormot.ui.pdf`:
- the `TLogFontW` overloads (`TPdfCanvas.SetFont(HDC, TLogFontW)`,
  `TPdfFontTrueType.Create(..., TLogFontW, ...)`,
  `GetRegisteredTrueTypeFont(TLogFontW)`). `SetFont(HDC, ...)` reduces the
  LOGFONT to name, style and charset and never used its DC; the constructor
  takes its face from `GdiCreateFace(TLogFontW)` of `mormot.lib.uniscribe`,
  from the whole LOGFONT (`lfWidth` or the precisions change widths and
  selection, which `TFontRequest` does not carry - decided with Sven,
  2026-10-09; cairo's LOGFONT constructor ignores `lfWidth`, a candidate for
  Phase 5; `TestLogFontWidth`)
- `ScreenLogPixels`: `GdiScreenLogPixels` (`GetDeviceCaps(LOGPIXELSY)` of a
  compatible DC) on Windows, 96 on POSIX - no font service; Phase 3 moves it
  to the canvas adapter. It follows the process's DPI awareness: a program
  whose `.res` carries the Lazarus DPI-aware manifest gets the real DPI (144
  at 150 % scaling), and `TGDIPages` lays its pages out with it - compare
  demo PDFs only between builds with the same `.res`
- the EMF code (`USE_METAFILE`): `TPdfDocument.EmfDC`, a compatible DC made
  when first needed, for `TMetaFileCanvas`, `EnumEnhMetaFile`, `TPdfEnum`'s
  own fonts and `GetTextExtentPoint32W`, which selects the face's HFONT for
  that one measure
- `AddGlyphs` with `TScriptVisAttr`; the printer and GDI+ code; the code page
  helpers (`LCIDToCodePage`, `CharNextA`), which are no font matter

Before W3, under `{$ifdef OSWINDOWS}` the core called GDI directly:
`CreateCompatibleDC`/`GetDeviceCaps` in the constructor,
`CreateFontIndirectW` (with output precision 0, where the GDI provider asks
for `OUT_TT_ONLY_PRECIS` - no difference in the golden files, as every font
the engine creates is an enumerated TrueType family),
`GetTextMetrics`, `GetOutlineTextMetrics`, `GetCharABCWidthsA`,
`GetCharABCWidthsI`, `SelectObject`, `windows.GetFontData`. Until Phase 1b
the document kept one DC and selected each font into it (`GetDCWithFont`):
`TPdfTtf.Create` read its four tables relying on the font its caller had
selected.

### IFontFace — One Face, Its Own State

```pascal
IFontFace = interface
  // The native handle for IFontShaper and IFontSubsetter: a HFONT on
  // Windows, a PFreeTypeFont with FreeType - valid while the face lives
  function  Handle: TFontHandle;
  function  GetTextMetrics(out Metrics: TFontMetrics): boolean;
  // ascent, descent, em-square, font box...
  function  GetOutlineMetrics(out Metrics: TFontOutlineMetrics): boolean;
  // ABC advance widths for FirstChar..LastChar - WinAnsi (cp1252) BYTE
  // values, not Unicode code points: the engine calls (32, 255) and indexes
  // the result by WinAnsi byte. Bytes 128..159 are printable punctuation in
  // WinAnsi but unassigned C1 controls in Unicode, so a backend doing a
  // Unicode lookup must translate first (see U-1)
  function  GetCharAbcWidths(FirstChar, LastChar: cardinal;
                             out Widths: TFontCharAbcArray): boolean;
  // The advance of one glyph by glyph index, in the units of GetCharAbcWidths
  // (GDI: GetCharABCWidthsI; FreeType: FT_Load_Glyph, design units scaled
  // once) - for a shaped glyph no character maps to (W3)
  function  GetGlyphAdvance(Glyph: cardinal; out Advance: integer): boolean;
  // Raw TrueType/OpenType table bytes (tag = 4-byte table name read as a
  // little-endian cardinal, e.g. 'cmap'; 0 = the whole font); returns bytes
  // read, or FONT_DATA_ERROR ($FFFFFFFF, a constant of mormot.lib.core)
  function  GetFontData(TableTag, Offset: cardinal;
                        Buffer: pointer; BufferSize: cardinal): cardinal;
  // The face as one standalone font file: a face of a .ttc is extracted
  // (GDI: TtcFaceIndex + ExtractSfntFromTtc; FreeType: the loaded face);
  // false if it cannot be found or extracted
  function  GetFaceFile(out Face: RawByteString): boolean;
end;
```

Metrics and widths are those of a 1000 units per em face: the engine asks
for `Height = -1000`; GDI scales to the requested height, the FreeType face
always to 1000 units. A face belongs to the thread that uses it: the GDI
face's DC is made by the thread which first measures it and is valid while
that thread lives, and all FreeType faces share one `FT_Library`, whose
`FT_New_Face`/`FT_Done_Face` are not serialized (as before Phase 1b). The
FreeType unit unloads the library only once the last face is released. The GDI face
(`TGdiFontFace`) owns its HFONT and a compatible DC made when first needed,
with the font selected into it for the face's lifetime; its destructor
restores the DC's old font, then deletes DC and font. The FreeType face
(`TFreeTypeFontFace`) owns its `PFreeTypeFont` record - `mormot.lib.harfbuzz`
reads the `FT_Face` from `Handle`.

`GetFontData(0, ...)` stays raw: on Windows it returns the face's table
directory with offsets into the collection, which `TtcFaceIndex` and the
FontSub subsetter need - only `GetFaceFile` promises a font file. The two
`.ttc` helpers, `ExtractSfntFromTtc` and `TtcFaceIndex`, live in
`mormot.lib.core` (2026-10-09), shared by both backends.

A font the backend cannot resolve (FreeType: not even DejaVu Sans or Roboto
found) gives no face; the engine then uses `TPdfNoFace`, whose queries all
fail - the metrics stay zero, as with the nil font of the FreeType backend
before Phase 1b.

### IFontProvider — Faces

```pascal
IFontProvider = interface
  // The face the system resolves Request to; nil on failure
  function CreateFace(const Request: TFontRequest): IFontFace;
end;
```

`IFontProvider`, `IFontEnumerator` and `IFontFace` got new GUIDs with Phase
1b; `IFontSubsetter` and `IFontShaper` kept theirs (same signatures, the
`Font` parameter is now `IFontFace.Handle`).

### IFontEnumerator — Font Enumeration

```pascal
IFontEnumerator = interface
  // Fill List with UTF-8 encoded font family names available on the system
  // (GDI: EnumFontFamiliesExW on a compatible DC of its own)
  procedure EnumTrueTypeFonts(var List: TRawUtf8DynArray);
end;
```

### IFontShaper — Text Shaping (optional: Uniscribe on Windows, HarfBuzz on Linux/macOS)

```pascal
IFontShaper = interface
  // false: draw the whole text unshaped, e.g. no part needs shaping.
  // RightToLeft forces the direction, false lets the script decide
  function Shape(Text: PWideChar; Len: integer; Font: TFontHandle;
    RightToLeft: boolean; out Runs: TFontShapedRuns): boolean;
end;
```

The result is a list of parts in visual order (`TFontShapedRun`) which covers
every code unit of the text once, a part left out included: `Kind` - how to
draw it (`fskPlain` - unshaped; `fskShaped` - glyphs hold the result;
`fskSkip` - nothing), `Outcome` - why (`fsoUnknown`; `fsoDone`;
`fsoNotNeeded`; `fsoFailed`, e.g. Uniscribe's dropped item is `fskSkip` +
`fsoFailed`). The zero values are the safe ones (Martin's review of #21,
2026-10-08): a shaper sets both fields on every run, and a run left zeroed
reads as `fskPlain` + `fsoUnknown`, which a caller draws unshaped whatever its
`Kind` (as HarfBuzz's `HB_DIRECTION_INVALID` = 0, proto3's `UNSPECIFIED`).
Then `TextStart`/`TextLen`
in UTF-16 code units of the whole text, then `Glyphs` and the parallel
`Advances`, `Offsets` (to the right), `YOffsets` (upwards; 1/1000 em, empty =
none; offsets never move the pen) and `Clusters`.

The two shapers:
- **`TUniscribeShaper`** (`mormot.lib.uniscribe`): itemizes exactly `Len`
  code units (`ScriptItemize`), returns false when no item is complex or
  right-to-left, and gives one run per item in visual order (`ScriptLayout`);
  an empty item gives none. `ScriptShape` runs without a DC first, then with
  its own DC holding the font on `E_PENDING`/`USP_E_SCRIPT_NOT_IN_FONT`.
  Failures: `E_OUTOFMEMORY` or a failed retry -> `fskPlain` + `fsoFailed`,
  any other error -> `fskSkip` + `fsoFailed`; no glyph at all -> `fskSkip` +
  `fsoDone`. Zero-width glyphs which are no diacritic are left out (a run may
  end up with no glyph: the caller still switches to the Unicode font). No
  `Advances`/`Offsets`: the font's apply. Its `SCRIPT_CACHE` is freed per call
- **`THarfBuzzShaper`** (`mormot.lib.harfbuzz`): returns false unless
  `RightToLeft` or `NeedsShaping` (a character of Hebrew, Arabic to Myanmar
  U+0590-109F, Khmer/Mongolian, U+A800-ABFF, presentation forms - what
  Uniscribe marks complex); otherwise one `fskShaped` + `fsoDone` run over the
  whole text with every glyph, `Advances`, `Offsets`, `YOffsets`, `Clusters`

**The one caller**, `TPdfWrite.AddUnicodeHexTextShaped` (since W2): checks
every run before writing anything - `TextStart`/`TextLen` inside the text,
at least one code unit each, covering it exactly; a shaped run's `Advances`
(if any) and `Offsets` (if any, and only with `Advances`: this writer
positions with them) as long as its glyphs - else the whole text takes the
simple path. Then
`MoveToNextLine` once, and per run: `fskPlain` or `fsoUnknown` -> the simple
path on a `#0`-terminated copy of its text; `fskShaped` -> `AddShapedRun` in
the Unicode font of the font the text was shaped with (a `Tj` with the font's
advances, or the `TJ` positioning when the run has `Advances`); `fskSkip` ->
nothing. **`YOffsets` are not drawn yet:** `TJ` moves horizontally only;
placing marks vertically needs a text rise (`Ts`) per glyph, and Uniscribe
`ScriptPlace` first - a change of its own (added to the contract 2026-10-08 so
that it is complete before it goes into the trunk).

---

## Registration

Each backend registers its implementations in the `initialization` section:

```pascal
// In mormot.lib.uniscribe.pas (Windows), RegisterUniscribe:
  RegisterFontPlatform(
    TGdiFontProvider.Create,
    TGdiFontEnumerator.Create);
  {$ifndef NO_USE_UNISCRIBE}
  FontShaper := TUniscribeShaper;                 // always
  FontSubsetter := TFontSubSubsetter;             // if HasCreateFontPackage
  {$endif NO_USE_UNISCRIBE}
// its finalization releases its own shaper and subsetter, then FontSub.dll

// In mormot.lib.freetype.pas (Unix/macOS), when LoadFreeType succeeds:
initialization
  RegisterFontPlatform(
    TFreeTypeFontProvider.Create,
    TFreeTypeFontEnumerator.Create);
// its finalization releases them again, before the library is unloaded
```

`RegisterFontPlatform` of `mormot.lib.core` sets the globals `FontProvider`
and `FontEnumerator` (the `FontDC` global and the DC parameter went with
Phase 1b); `mormot.lib.uniscribe` and `mormot.lib.harfbuzz`
assign `FontShaper` and `FontSubsetter` themselves. The core calls them directly. `mormot.pdf.types`
keeps the former type names as aliases (`TPdfLogFont`, `IPdfPlatformFont`...)
for code outside this repository; the globals, `IPdfTextShaper` and
`IPdfFontSubsetter` have none (renamed 2026-10-04, R-28 Phase 1), and
`TPdfPlatformDC`/`IPdfPlatformDC` are gone with the device context.

```pascal
// Check whether a platform backend has been registered:
if not FontPlatformRegistered then
  raise ESynException.Create('No PDF platform registered');
```

**Who pulls the units in — `mormot.ui.pdf`, never the application.** Its
interface `uses` takes `mormot.lib.uniscribe` on Windows (always: it holds
the GDI services; `NO_USE_UNISCRIBE`, set for the whole project, leaves its
shaper and subsetter unregistered, so no shaping and the whole faces
embedded, as before W2) and `mormot.lib.freetype`
and `mormot.lib.harfbuzz` elsewhere. `mormot.lib.harfbuzz` loads
`libharfbuzz` for the shaper and `libharfbuzz-subset` (with its own handle on
`libharfbuzz`) for the subsetter, each through `TSynLibrary`, and registers
each one only when its library resolves, so a missing library leaves shaping
or subsetting off — no build dependency. A program that names a platform unit
itself (the tests use `mormot.lib.freetype` for FreeType face checks) does no
harm; no program needs to. Until 2026-10-07 the backends were
`mormot.pdf.freetype`, `mormot.pdf.harfbuzz` and `mormot.pdf.hbsubset` in
`src/platform/unix` (R-28 Phase 1). Before 2026-09-29 `mormot.pdf.harfbuzz` had to be added by the
application, `layer1_demo` listed the backends, and `rtl_demo` wrongly
required FreeType before HarfBuzz.

**One shaping switch, `UseUniscribe`, on every platform**
(`TPdfWrite.AddUnicodeHexText` -> `AddUnicodeHexTextShaped` -> `FontShaper`):
- Windows: Uniscribe itemizes the run and shapes only complex items; the
  rest takes the simple font
- Linux/macOS: HarfBuzz shapes a run when `RightToLeftText` is set or
  `NeedsShaping` (in the shaper since W2) finds a character of a script that
  needs it; Latin text keeps the simple font, as with Uniscribe
- `RightToLeftText` is the direction only. HarfBuzz gets RTL forced when it
  is set; otherwise `hb_buffer_guess_segment_properties` takes the direction
  from the script (a forced LTR shaped Arabic in the wrong order). Glyphs come
  back in visual order either way
- Limit: a run mixing Arabic and Latin in one `TextOut` is not bidi-reordered
  on Linux/macOS; HarfBuzz shapes, it does not itemize by direction
- Changed 2026-09-29: HarfBuzz used to run on `RightToLeftText` alone and
  ignore `UseUniscribe`. Code for Linux/macOS that sets only
  `RightToLeftText` now draws unshaped; guarded by `TestShapingSwitch`

---

## Data Types (mormot.lib.core)

### TFontRequest — Font Request Descriptor

```pascal
TFontRequest = record
  FaceName:       SynUnicode;  // font family name (e.g. 'Calibri')
  Height:         integer;     // character height in logical units (negative = em height)
  Weight:         integer;     // FW_NORMAL=400, FW_BOLD=700
  Italic:         byte;        // 0 = upright, 1 = italic
  CharSet:        byte;        // 0 = ANSI_CHARSET
  PitchAndFamily: byte;        // FF_SWISS, FF_ROMAN, etc.
end;
```

### TFontHandle

```pascal
TFontHandle = type pointer;  // IFontFace.Handle: HFONT, PFreeTypeFont
```

### TFontMetrics

```pascal
TFontMetrics = record
  tmHeight, tmAscent, tmDescent: integer;
  tmInternalLeading, tmExternalLeading: integer;
  tmAveCharWidth, tmMaxCharWidth: integer;
  tmWeight: integer;
  tmOverhang: integer;
  tmFirstChar, tmLastChar, tmDefaultChar, tmBreakChar: WideChar;
  tmItalic, tmCharSet, tmPitchAndFamily: byte;
end;
```

### TFontOutlineMetrics

```pascal
TFontOutlineMetrics = record
  otmSize:         cardinal;
  otmAscent:       integer;
  otmDescent:      integer;
  otmLineGap:      integer;
  otmItalicAngle:  integer;
  otmrcFontBox:    record Left, Top, Right, Bottom: integer; end;
  otmMacAscent, otmMacDescent: integer;
  otmMacLineGap:   cardinal;
  otmEMSquare:     cardinal;
  otmCapEmHeight, otmXHeight: integer;
  otmStrikeoutPosition: integer;
  otmStrikeoutSize: cardinal;
  otmUnderscorePosition: integer;
  otmUnderscoreSize: cardinal;
end;
```

### TFontCharAbc

```pascal
TFontCharAbc = record
  abcA: integer;   // pre-character spacing (can be negative)
  abcB: cardinal;  // glyph width (always positive)
  abcC: integer;   // post-character spacing (can be negative)
end;
TFontCharAbcArray = array of TFontCharAbc;
```

Total character advance = `abcA + abcB + abcC`, and that sum is what reaches
`/Widths` in the PDF.

**The sum must equal the scaled advance exactly.** A backend scaling design
units to the 1000-per-em grid rounds each of the three members, and three
roundings accumulate to ±1.5 — enough to break ISO 14289-1 7.21.5, which allows
a deviation of 1 against the embedded font program. Scale the advance once and
give `abcB` the remainder after the two bearings; the bearings stay correct
individually, which is what the other callers of the triple need. See U-1.

---

## Windows Backend (mormot.lib.uniscribe)

GDI API mapping:

| Interface method | Windows API |
|---|---|
| `CreateFace` | `CreateFontIndirectW` (the face: `TGdiFontFace`; from a whole LOGFONT: `GdiCreateFace`) |
| face destructor | `SelectObject` back, `DeleteDC`, `DeleteObject` |
| (face DC) | `CreateCompatibleDC(0)` + `SelectObject`, when first needed |
| `GetTextMetrics` | `GetTextMetricsW` |
| `GetOutlineMetrics` | `GetOutlineTextMetricsW` |
| `GetCharAbcWidths` | `GetCharABCWidthsA` (ANSI — maps the byte through the DC codepage, so bytes 128..159 resolve to their WinAnsi characters; code points above 255 are not reachable through this call) |
| `GetFontData` | `GetFontData` |
| `GetGlyphAdvance` | `GetCharABCWidthsI` |
| `GetFaceFile` | `GetFontData` (`'ttcf'`, the table directory) + `TtcFaceIndex` + `ExtractSfntFromTtc` |
| `EnumTrueTypeFonts` | `EnumFontFamiliesExW` with TRUETYPE_FONTTYPE, on a DC of its own |
| `GdiScreenLogPixels` (no interface) | `GetDeviceCaps(CreateCompatibleDC(0), LOGPIXELSY)` |

No additional runtime dependency — GDI is part of Windows.

---

## Unix/macOS Backend (mormot.lib.freetype)

FreeType2 API mapping:

| Interface method | FreeType2 API |
|---|---|
| `CreateFace` | `FT_New_Face` (face 0 of the file; the face: `TFreeTypeFontFace`) |
| face destructor | `FT_Done_Face` |
| `GetTextMetrics` | `FT_FaceRec.ascender/descender/height` |
| `GetOutlineMetrics` | `FT_FaceRec.bbox` + scaled values |
| `GetCharAbcWidths` | `WinAnsiConvert.AnsiToWide[]`, then `FT_Load_Char` + `horiAdvance` |
| `GetFontData` | `FT_Load_Sfnt_Table` |
| `GetGlyphAdvance` | `FT_Load_Glyph` (`FT_LOAD_NO_SCALE`) + `horiAdvance` |
| `GetFaceFile` | `GetFontData(0)`: the loaded face, extracted from a `.ttc` (`ExtractSfntFromTtc`) |
| `EnumTrueTypeFonts` | filesystem scan + `FT_New_Face` |

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

**Runtime library:** `libfreetype.so.6` (Linux) / `libfreetype.6.dylib` (macOS) — loaded at run time through `TSynLibrary` (`LoadFreeType`, Homebrew paths tried on macOS). If not present, nothing is registered and `TPdfDocument.Create` raises.

---

## Optional: IFontSubsetter (hb-subset on Linux/macOS — R-12, FontSub on Windows — R-15)

```pascal
TFontSubsetRequest = record
  Unicodes: TIntegerDynArray;  // code points whose cmap entries must survive
  Glyphs: TIntegerDynArray;    // glyph IDs that must survive
end;

IFontSubsetter = interface
  // false: face cannot be subset (invalid, library error) -> caller embeds
  // Face unchanged; glyph IDs of Output equal those of Face. Font is the
  // handle Face was read from - hb-subset ignores it (the engine hands it a
  // face already extracted from a .ttc), FontSub needs it
  function Subset(const Face: RawByteString; const Request: TFontSubsetRequest;
    Font: TFontHandle; out Output: RawByteString): boolean;
  // true if a symbol font (glyphs through a (3,0) cmap at U+F0xx) is kept;
  // false (hb-subset): PrepareFontSubsets embeds such a font whole
  function SupportsSymbolic: boolean;
end;

var FontSubsetter: IFontSubsetter;  // mormot.lib.core; nil = no subsetter
```

- `mormot.ui.pdf` uses `mormot.lib.harfbuzz` on POSIX itself, like the FreeType
  backend: no project-side `uses` needed. Its `initialization` calls
  `LoadHarfBuzzSubset` and registers only when every symbol resolved, so
  `FontSubsetter <> nil` means "usable"
- Two libraries: `hb_subset_*` from `libharfbuzz-subset.so.0` /
  `libharfbuzz-subset.0.dylib`, `hb_blob_*`/`hb_face_*`/`hb_set_*` from
  `libharfbuzz.so.0` / `libharfbuzz.0.dylib` (Homebrew paths tried on macOS)
- Needs HarfBuzz 2.9+ (`hb_subset_or_fail`, `hb_subset_input_set_flags`); older
  libraries leave it unregistered → whole-face embedding
- **HarfBuzz < 10.0 does not fail on a face without glyphs**: `hb_subset_or_fail`
  returns a 12-byte sfnt with no tables instead of nil. Fixed upstream in
  10.0.0 ("Subsetting will now fail if source font has no glyphs"). `Subset`
  therefore treats `numTables = 0` as failure itself — never trust a non-nil
  result alone. `TestSubsetAcceptsCff` (`'OTTO'` + 60 zero bytes) guards it;
  it only bites on such a HarfBuzz (issue #4, Ubuntu 24.04)
- HarfBuzz has no long-term releases. What the distributions ship (Repology,
  2026-10-02):

  | Distribution | HarfBuzz | Subsetting |
  |---|---|---|
  | RHEL / AlmaLinux / Rocky 8 | 1.7.5 | off (< 2.9) |
  | Debian 11, Ubuntu 22.04 LTS, RHEL / AlmaLinux / Rocky 9 | 2.7.4 | off (< 2.9) |
  | Debian 12 | 6.0.0 | on, empty result caught (< 10.0) |
  | Ubuntu 24.04 LTS, openSUSE Leap 15.6 | 8.3.0 | on, empty result caught (< 10.0) |
  | RHEL 10 (CentOS Stream 10) | 8.4.0 | on, empty result caught (< 10.0) |
  | Debian 13 (the Linux dev machine), Ubuntu 25.04 / 25.10 | 10.2.0 | on |
  | Ubuntu 26.04 LTS | 12.3.2 | on |
  | Fedora 43 / 44 | 11.5.1 / 14.1.0 | on |
  | macOS (Homebrew) | 14.5.1 | on |
- Tuning globals: `HbSubsetFlags` (default `RETAIN_GIDS or NOTDEF_OUTLINE or
  NO_HINTING`; `RETAIN_GIDS` is always forced), `HbSubsetDropLayoutTables`
  (default true: drop `GSUB/GPOS/GDEF`). Measured on the untagged
  `markdown_demo` / CJK / Arabic outputs: defaults 44.7 / 10.8 / 15.1 KB,
  keeping the layout tables 46.8 / 11.4 / 17.0 KB, keeping the hinting
  83.8 / 14.7 / 29.1 KB — all three variants render pixel-identically, so the
  smallest is the default. A PDF viewer never shapes text, and the glyph set
  of the request already holds every shaped glyph that was drawn
- **Windows (since W2): `TFontSubSubsetter`** in `mormot.lib.uniscribe`,
  registered when `HasCreateFontPackage` (FontSub.dll) resolves.
  `CreateFontPackage` with a glyph keep list (`TTFCFP_FLAGS_GLYPHLIST`,
  `TTFMFP_SUBSET`: glyph IDs kept): `Request.Glyphs` plus `Request.Unicodes`
  resolved through the cmap of `Font` with `GetGlyphIndicesW`
  (`GGI_MARK_NONEXISTING_GLYPHS`; unmapped ones and code points outside the
  BMP dropped). A face of a `.ttc`: the whole collection (`'ttcf'`) is
  subset, at the index `TtcFaceIndex` finds by the face's table directory in
  the collection header; no single match -> false, and as `GetFaceFile`
  needs the same match, saving raises `EPdfInvalidOperation` (embedding
  required, neither a subset nor the whole face).
  `ReduceTtf` keeps the ten tables a PDF needs. `SupportsSymbolic` = true:
  GDI maps the WinAnsi bytes of a symbol font. Without `Font` it returns
  false, and for a CFF face too (`CreateFontPackage` takes TrueType outlines
  only, error 1035 - Codex, 2026-10-08): such a face is embedded whole on
  Windows. Registering it loads FontSub.dll at program start
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

- `SetFont` repeats `TPdfCanvas.SetFont`'s resolution order: the base-14 AFM tables (`STANDARDFONTS`) when `aStandardFonts` is set and the name is Helvetica/Times/Courier or an alias, otherwise `FontProvider.CreateFace` on a `Height = -1000` request plus `GetCharAbcWidths(32, 255)` — i.e. 1000-per-em units, like every other width in the engine.
- Returns `false` when nothing resolves (no backend registered); the caller then falls back to its own measurement.
- Faces are cached per (name, bold, italic, standard-flag) on the measurer instance; `TPdfFaceMetrics` holds its `IFontFace` until the measurer is freed.
- Code points above WinAnsi use `DefaultWidth` — the GDI backend's `GetCharAbcWidths` is the ANSI call, so per-code-point Unicode widths are not available through this path.

---

## Compiler Switches and `{$ifdef FPC}` (R-21)

Every unit starts with `{$I mormot.defines.inc}` after `interface` (by name, no relative path).

- **Enum size does not reach the C libraries.** `mormot.defines.inc` sets `{$MINENUMSIZE 1}` and `{$PACKSET 1}`, but the bindings in `mormot.lib.freetype` and `mormot.lib.harfbuzz` declare every C enum as `integer` and hold no set. Keep it that way in new bindings.
- **The `{$ifdef FPC}` branches that remain are real differences.** The six in `mormot.ui.pdf` all come from the original (`reference/`): LCL against VCL units, the compatibility types, and three Windows API calls FPC declares differently — `EnumPrinters` (pointers), `GdiComment` (`var`), `EnumEnhMetaFile` (`RECT`); the fourth, `CreateFontIndirectW` on a `const` parameter in the `TPdfFontTrueType` constructor, went with W3: the `TLogFontW` constructor passes a local copy, a `var` that fits both declarations. No mORMot2 function wraps them. The GDI services in `mormot.lib.uniscribe` need no branch: a local `var` fits both. The branches in `mormot.ui.core` and `mormot.ui.gdiplus` come with the mORMot2 originals. The one around all of `mormot.ui.report` is gone since R-20.
- **LCL against VCL units** (R-20): `mormot.ui.pdfcanvas` and `mormot.ui.report` take `LCLIntf`/`LCLType` under FPC and `Windows` under Delphi — `Windows` *before* `Graphics`, or its record `TBitmap` hides the class (dozens of errors on every `TBitmap.Create`).
- **`PDF_CANVASVIRTUAL`** (`mormot.ui.pdfcanvas`, defined under FPC): the LCL's `TCanvas` drawing methods are virtual, Delphi 7's are static. The bridge declares `TextOut`, `TextExtent`, `TextWidth`, `TextHeight`, `Rectangle`, `Ellipse`, `RoundRect`, `Draw` with `override` or `reintroduce` by this switch, and has `DoMoveTo`/`DoLineTo` (LCL) or reintroduced `MoveTo`/`LineTo` (Delphi). `DoLineTo` checks `psClear` itself: `TFPCustomCanvas.LineTo` skips it then, our Delphi `LineTo` does not.
- **Delphi on Linux/Android** (R-27): the POSIX backends load their libraries through `TSynLibrary` of `mormot.core.os` (before Phase 1: `LibraryOpen`/`LibraryResolve`) — FPC's `dynlibs` does not exist there, and `TLibHandle` comes from `System` under FPC, from `mormot.core.os` under Delphi. `mormot.ui.pdf` turns `USE_GRAPHICS_UNIT` off for Delphi on `OSPOSIX` (no VCL): the `TBitmap`/`TGraphic` image API is left out, `GetSysColor` and `MM_TEXT` get local fallbacks. Android: `/system/fonts` is scanned, Roboto is the last fallback face; the app has to ship an NDK-built `libfreetype.so` (a glibc build does not load), and a program without a configured `TSynLog` family crashed in `TSynLog.FillInfo` on the first raised exception — configure it as `TSynTests.RunAsConsole` does.
- **Delphi 7 syntax** met in R-20: every declaration of an overloaded method needs `overload` (FPC accepts it on one); no `Default(T)` — `mormot.ui.report` has `NewCommand` (`Finalize` + `FillChar`); no typed constants with dynamic-array fields — build a `TTableLayout` in a function, zeroed first like a constant's omitted fields.

---

## Adding a New Platform

1. Create a new unit `mormot.lib.<library>.pas` in mORMot2 `src/lib`
2. Implement three classes:
   - `T<Library>FontFace(TInterfacedObject, IFontFace)`
   - `T<Library>FontProvider(TInterfacedObject, IFontProvider)`
   - `T<Library>FontEnumerator(TInterfacedObject, IFontEnumerator)`
3. Register in `initialization` via `RegisterFontPlatform(Provider, Enumerator)`
4. Add conditional `uses` in the application project

No changes to `mormot.ui.pdf.pas` required.

---

## Phase 1 Notes (R-28) — What the Font Layer Has to Absorb

Read from the source on 2026-10-03 for the cut into `mormot.lib.core` and
the library units (`docs/REFACTORING.md`, Phase 1). Facts, not yet decisions.

The names in these notes are those of the time; since 2026-10-04 the engine
uses those of `mormot.lib.core` (`PdfPlatformFont` -> `FontProvider`,
`PdfPlatformDCProvider` -> `FontDC`, `IPdfTextShaper.ShapeText` ->
`IFontShaper.Shape`...).

**Global use in `mormot.ui.pdf`** (code references, comments not counted):
`PdfPlatformFont` 29, `PdfPlatformDCProvider` 6, `PdfFontSubsetter` 4,
`PdfTextShaper` 3, `PdfSystemFonts` 1 - 43 in all. Besides,
`PdfPlatformRegistered` in `mormot.pdf.types` reads three of them, and the
backends register. A document-local copy (gist §18) touches those places.

**`mormot.pdf.types` mixed two kinds:** generic font types (the three
platform interfaces, `IPdfTextShaper`, `IPdfFontSubsetter`,
`TPdfFontSubsetRequest`, `TPdfLogFont`, `TPdfTextMetrics`,
`TPdfOutlineMetrics`, `TPdfCharABC*`, the handles, `RegisterPdfPlatform`) and
PDF types (`TPdfFileFormat`, `TPdfStructRole`, `PDF_FONT_STD_*`,
`PDF_FONT_TTF_*`, `GetPdfFonts`). Gist §17: the second kind stays on the PDF
side.

**Windows shaping is not behind `IPdfTextShaper`.**
`TPdfWrite.AddUnicodeHexTextUniScribe` (`USE_UNISCRIBE`) calls
`ScriptItemize`/`ScriptGetProperties`/`ScriptLayout`/`ScriptShape` itself.
It differs from the HarfBuzz path in shape, not only in library:
- Uniscribe itemizes the run; it returns early (unshaped) when no item is
  complex or RTL, and inside a shaped run every item is shaped on its own,
  appended in visual order (`ScriptLayout`). Per item, `ScriptShape`:
  - succeeds: its glyphs are added
  - `E_OUTOFMEMORY`: the item goes through `AddUnicodeHexTextNoUniScribe`
  - `E_PENDING` / `USP_E_SCRIPT_NOT_IN_FONT`: retried with the DC; if that
    fails too, the simple path as above
  - any other error: the item is **dropped** - nothing is written for it
  An unchanged-output refactor has to keep all four outcomes
- the result goes to `AddGlyphsOf(WinAnsiTtf, glyphs, count, Canvas,
  TScriptVisAttr[])`: glyph IDs plus visual attributes, widths from the font
- HarfBuzz (`AddUnicodeHexTextHarfBuzz`, POSIX) shapes the whole run in one
  call (`NeedsShaping` decides first). `/W` keeps the font's own `hmtx`
  width; where the shaper's advance or offset differs, a `TJ` adjusts the
  position, otherwise a plain `Tj` is written (U-2)
- `ScriptShape` needs the DC with the font selected on `E_PENDING`
  (`fDoc.GetDCWithFont`)
A common shaper interface therefore needs an itemized result (per item:
shaped glyphs, "leave to the simple path" or "drop"), or the Windows output
changes.

**Windows subsetting is not behind `IPdfFontSubsetter`.**
`PrepareFontSubsets` groups the fonts by face and merges their requests on
both platforms, then subsets each face once: `PdfFontSubsetter.Subset` when
one is registered, otherwise `TPdfFontTrueType.SubsetWithFontPackage`
(`USE_UNISCRIBE`); `PrepareForSaving` uses the shared result. The Windows call
differs from hb-subset:
- reads the face through the DC: whole `.ttc` plus its index
  (`TTCF_TABLE`, `GetTtcIndex`) — hb-subset gets the extracted face
- keeps by glyph list only (`TTFCFP_FLAGS_GLYPHLIST`): the WinAnsi
  characters are resolved to glyphs first (`AddWinAnsiGlyphs`,
  `GetGlyphIndicesW` on the DC); hb-subset takes `Unicodes` and `Glyphs`
- `ReduceTTF` on the result; `PdfCanSubsetRetainingGids` ORs
  `HasCreateFontPackage` in

**The bindings already in the trunk:** `mormot.lib.uniscribe` holds Uniscribe
and the FontSub API (`CreateFontPackage`, `HasCreateFontPackage`) — the
fork's copy was dropped in PR #2. FreeType and HarfBuzz had no trunk
binding; theirs sat in `mormot.pdf.freetype` (FT types and loader),
`mormot.pdf.harfbuzz` (used `mormot.pdf.freetype` for the face) and
`mormot.pdf.hbsubset` (its own `hb_blob/face/set` imports) - since PR #15
they are `mormot.lib.freetype` and `mormot.lib.harfbuzz`.

**Unit names, decided** (gist, 2026-10-03): the trunk keeps `mormot.lib.*`
for library units, so the contracts go to one `mormot.lib.core` and the
implementations into the units of their libraries - `mormot.lib.uniscribe`
(the GDI font part, the Uniscribe shaper, the FontSub subsetter),
`mormot.lib.freetype`, `mormot.lib.harfbuzz` (shaping and subsetting). The
gist's `mormot.lib.font*` is replaced. They are written in the branch
`pdf-font-layer` of `landrix/mORMot2` at `src/lib`, where
`mormot.lib.uniscribe` is extended in place - a copy here would shadow the
package's unit; this repository builds against a pinned commit of that
branch (`docs/REFACTORING.md`, Phase 1, "Where the code lives").

**The POSIX backends, read on 2026-10-04** (for `mormot.lib.freetype` /
`mormot.lib.harfbuzz`; files: the three in `src/platform/unix` and
`mormot.pdf.types`):
- The records of `mormot.pdf.types` match `mormot.lib.core` field for field
  (`TPdfLogFont` = `TFontRequest` with byte `Italic`/`CharSet`/
  `PitchAndFamily`; `TPdfTextMetrics` = `TFontMetrics` with `WideChar`
  character fields and no `tmUnderlined`/`tmStruckOut`). The data types
  section was older than the code (corrected since). Type aliases are
  enough, nothing is copied
- `mormot.pdf.freetype` does not compile on Windows: `TPdfFTContext`,
  `ExtractSfntFromTtc` and `PdfFTSetEmSize1000` sit outside its
  `{$ifndef OSWINDOWS}`, while `uses` and `FT_Face` are inside. Nobody built
  it there; the trunk package builds every unit on every target, so the
  library unit has to compile empty on Windows
- The HarfBuzz shaper reaches the FreeType face through the public
  `TPdfFTContext` record behind the font handle, and sizes it to 1000 per em
  with `PdfFTSetEmSize1000` first (`hb_ft_font_create` copies the scale)
- `NeedsShaping` is not in the shaper: `mormot.ui.pdf` decides before it
  calls `ShapeText`. The shaper returns one run - glyphs, advances, offsets,
  clusters - or false; it filters nothing
- `hbsubset` ignores any face index (`hb_face_create(blob, 0)`): the engine
  hands it a face already extracted from a `.ttc`. It opens `libharfbuzz`
  itself, for `hb_blob/face/set`, beside `libharfbuzz-subset`
- Loading: records of function pointers with `LibraryOpen`/`LibraryResolve`
  (needed for Delphi on Linux/Android), not the trunk's `TSynLibrary`
- Assigned from outside: the tests save, clear and restore
  `PdfFontSubsetter`; the Android form calls `LoadFreeType`. A global
  turned into a function would break them

**The Windows paths, read on 2026-10-07** (for the Uniscribe shaper and the
FontSub subsetter in `mormot.lib.uniscribe`; read in `mormot.ui.pdf`:
`AddUnicodeHexTextUniScribe`, `AddGlyphs`, `AddUnicodeHexText`,
`AddUnicodeHexTextNoUniScribe`, `SubsetWithFontPackage`, `AddWinAnsiGlyphs`,
`GetTtcIndex`, `PrepareFontSubsets`):
- Per item, `ScriptShape` first runs without a DC; on `E_PENDING` or
  `USP_E_SCRIPT_NOT_IN_FONT` again with `GetDCWithFont` (the font selected
  into the document DC). The `SCRIPT_CACHE` (`psc`) is local to the call and
  never freed with `ScriptFreeCache`
- The simple path of an item gets a `#0`-terminated copy of its text
  (`AddUnicodeHexTextNoUniScribe` reads to `#0`), with `NextLine` false:
  `MoveToNextLine` runs once, before the first item, when the run is shaped
- `AddGlyphs` switches to the Unicode font as soon as `ScriptShape` returned
  any glyph, even when the filter then drops all of them; with no glyph at
  all it does nothing. It writes at most one `<...> Tj` per item - none when
  the filter dropped every glyph - with no positioning, and
  marks glyphs with `GetAndMarkGlyphAsUsed` (no width from the shaper)
- It used the font active on the page. After an item drawn unshaped whose
  characters came from the fallback font, that was the fallback font: the
  next shaped item wrote the main font's glyph IDs there and marked them in
  the fallback font (found 2026-10-08, Devanagari then Arabic in Tahoma).
  Fixed before W2: the Uniscribe path calls `AddGlyphsOf` with the font it
  shaped with; `TestShapedAfterFallback` covers it. The W2 writer keeps
  that rule for every run
- `RightToLeftText` sets `uBidiLevel := 1` before `ScriptItemize`;
  `ScriptApplyDigitSubstitution` runs first
- `ScriptItemize` gets `PWLen + 1` code units (the `#0` after the text) and
  the loop skips item `count - 1` as "the sentinel". The terminal boundary of
  the API is `items[count]`; item `count - 1` is the item holding that `#0`,
  which may hold real text too: input `U+0628 U+0000` gives the boundaries
  `[0,1,3]` (Codex, 2026-10-08, native `ScriptItemize`), and the real `U+0000`
  is lost. The W2 shaper itemizes exactly `Len` units and takes every item,
  and sets `Outcome` on every run it returns (`fsoFailed` for the simple path
  after an error and for a dropped item, `fsoDone` otherwise); a
  zero-length item covers nothing and gives no run
- `SubsetWithFontPackage` reads the whole `.ttc` through the DC
  (`TTCF_TABLE`) and finds the face index with `GetTtcIndex` - a list of
  family names (`batang`, `cambria math`, `ms gothic`, localized CJK names...)
  matched against `fTrueTypeFonts[...]`, the enumerated family name; the
  font handle alone does not give it. **The list is wrong on Windows 11**
  (measured 2026-10-07, Windows on ARM, 424 families, 30 in a `.ttc`):
  matching the face's table directory against the offsets of the TTC header
  gives another index for 14 of them - `MS UI Gothic` is face 1, not 2,
  `MS PGothic` face 2, not 1 (`msgothic.ttc` changed its order), and `Yu
  Gothic UI`, `Microsoft YaHei UI`, `Microsoft JhengHei UI`, `Nirmala Text`,
  `MingLiU_MSCS-ExtB` are not listed and fall back to 0 although they are
  not face 0. For those, `CreateFontPackage` subsets the wrong face of the
  collection. `Microsoft YaHei` (the CJK font of the demos and tests) and
  `Cambria` get the same index both ways. Decided: the FontSub subsetter
  finds the index from the bytes
- The Windows keep list is glyphs only: `AddToSubsetRequest` adds the glyphs
  of the used WinAnsi characters through `GetGlyphIndicesW` (unmapped ones
  dropped), under `USE_UNISCRIBE`; `CreateFontPackage` never sees
  `Request.Unicodes`, which also hold the code points of Identity-H text

**The Windows bypass, checked on 2026-10-07** (search for the GDI font calls
in `mormot.ui.pdf`, hit lines with their POSIX branch read): still there.
Under `OSWINDOWS` the engine calls GDI itself where POSIX calls the
`mormot.lib.core` services - `GetTtfData` (`windows.GetFontData`),
`TPdfFontTrueType.Create` (`CreateFontIndirectW`, `GetTextMetrics`,
`GetOutlineTextMetrics`, `GetCharABCWidthsA`) and `Destroy`
(`DeleteObject`), `TPdfDocument.Create`/`Destroy`/`GetDCWithFont`
(`CreateCompatibleDC`, `GetDeviceCaps`, `SelectObject`), and the whole-face
embedding, which reads the `.ttc` and calls `GetTtcIndex` (on POSIX too).
`fM`/`fOTM` are the Windows records there (`otms...` fields). A shaped glyph
missing from the cmap gets its width from `GetCharABCWidthsI` by glyph index
(`GetAndMarkGlyphAsUsed`, step 3) - `IFontProvider` had no such method
(`GetGlyphAdvance` since W3). The printer (`GetDeviceCaps` for page size) and
EMF (`TPdfEnum`) calls are Windows-only features and stay. Done as step W3
(2026-10-09), after the Uniscribe shaper and the FontSub subsetter (W2). The whole-face embedding went first,
as a bug fix (2026-10-09): it read the whole collection and wrote it to
`/FontFile2` - `GetTtcIndex`'s index was never used - and goes through
`FontProvider.GetFaceFile` now; `GetTtcIndex` is gone.

**W2 done (2026-10-08):** `TUniscribeShaper` and `TFontSubSubsetter` in
`mormot.lib.uniscribe`, `NeedsShaping` in the HarfBuzz shaper,
`SupportsSymbolic` in the contract; in `mormot.ui.pdf` one caller
(`AddUnicodeHexTextShaped`/`AddShapedRun`), `PrepareFontSubsets` through
`FontSubsetter` only - `AddUnicodeHexTextUniScribe`,
`AddUnicodeHexTextHarfBuzz`, `SubsetWithFontPackage`, `AddWinAnsiGlyphs`,
`ReduceTTF` are gone. The notes above ("not behind `IPdfTextShaper`" / "not
behind `IPdfFontSubsetter`", "The Windows paths") describe the code before
W2. Intended differences, all outside the golden files: the TTC index of the
Windows subset comes from the bytes (right for the 14 collections the name
list got wrong); Uniscribe itemizes exactly the text, without the `#0` item
that could swallow real text (Codex probed 15,000 strings with Arabic or
Hebrew: the same items and order; with digits the `#0` changes their bidi
level and the item boundaries - `rtl_demo`, line `EXPECTED_2A`: `0628` +
` BA ` became `0628 ` + `BA `, the space moving from one `Tj` to the one
before, the same page; Martin, #25; `docs/REFACTORING.md`, Phase 1); its
`SCRIPT_CACHE` is freed; `ShowText(...,
NextLine = true)` of shaped text on POSIX writes `T*` before the font switch
(as Uniscribe did); FontSub resolves every code point of the request, not
only the WinAnsi ones (the same glyphs, as the cmap gives them).

**Phase 1 steps done:** `mormot.lib.core` (89d652a77), `mormot.lib.freetype`
and `mormot.lib.harfbuzz` moved and renamed (80e78bb4d, compared against the
old units on Linux: 206 families, 19850 checks, identical), loaded through
`TSynLibrary` (5a1fb60fc). In this repository the engine, the backends and
the tests use the `mormot.lib.core` names (2026-10-04, rename only,
PR #13), and the old POSIX backends are replaced by the library units
(2026-10-07, move only). The Windows part: W1, the GDI services moved
into `mormot.lib.uniscribe` (2dce8feb6, `mormot.pdf.gdi` gone, move only);
W2, the Uniscribe shaper and the FontSub subsetter there (2f8bf3d76, see "W2
done" above); the whole face of a `.ttc` through `GetFaceFile` (0e40ec95c,
bug fix); W3, the engine's direct GDI calls behind `FontProvider`
(84012287b, 2026-10-09: `IFontProvider.GetGlyphAdvance`; the document DC, the
font, its metrics, tables and glyph advances through the interfaces on every
platform; `TLogFontW` kept as adapters). Next: Phase 1b, the DC removed.
