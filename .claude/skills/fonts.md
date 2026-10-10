# Font Handling — Deep Reference

Sources: `src/pdf/mormot.pdf.pas`, `src/pdf/mormot.pdf.types.pas`,
mORMot2 `src/lib/mormot.lib.uniscribe.pas` (GDI), `src/lib/mormot.lib.freetype.pas`

**Skill boundaries:**
- User-facing font mode selection → brief overview here; see also `.claude/skills/pdf-engine.md` §"Font Strategy"
- Platform interface (IFontProvider, etc.) → see `.claude/skills/platform-backends.md`
- Call graph of font paths → see `.claude/skills/call-graph.md` Path 4a–4f

---

## 1. Two Embedding Modes — Do Not Mix

| Mode | Properties | Font names | Embedding |
|---|---|---|---|
| Standard Type1 | `StandardFontsReplace := True` | Helvetica, Times, Courier | none |
| TrueType | `EmbeddedTTF := True` | OS-specific (see §2) | subset (default) or full TTF (`EmbeddedWholeTtf`, §3) |

```pascal
// Type1 — no embedding, PDF viewer supplies the font
Doc.StandardFontsReplace := True;
C.SetFont('Helvetica', 12, []);

// TrueType — full font file embedded
Doc.EmbeddedTTF := True;
C.SetFont('Calibri', 12, []);
```

Standard font name constants (`mormot.pdf.types.pas`):
- `PDF_FONT_STD_SANS` = `'Helvetica'`
- `PDF_FONT_STD_SERIF` = `'Times'`
- `PDF_FONT_STD_MONO` = `'Courier'`

---

## 2. Platform-Specific Font Selection

```pascal
// For TPdfDocument / TPdfDocumentVcl:
GetReportFonts(EmbeddedTTF, SansFont, SerifFont, MonoFont);

// For TGDIPages:
Report.ExportPdfEmbeddedTTF := True;
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
```

| Platform | Sans | Serif | Mono |
|---|---|---|---|
| Windows | Calibri | Cambria | Consolas |
| macOS | Trebuchet MS | Georgia | Andale Mono |
| Linux | Liberation Sans | Liberation Serif | Liberation Mono |

Fonts excluded from optional embedding: `TPdfDocument.EmbeddedTtfIgnore` (`TRawUtf8List`) - ignored for PDF/A and tagged output.
Fallback when a requested font is not found: `TPdfDocument.FontFallBackName` (string).

---

## 3. Font Embedding — Whole TTF vs. Subset

Controlled by `TPdfDocument.EmbeddedWholeTtf` (boolean, **default `false`** — the
constructor leaves it unset). Tagged output is subset on every platform, like
untagged output.

| `EmbeddedWholeTtf` | Behaviour |
|---|---|
| `true` | Complete TTF bytes embedded. Safe for all scripts including RTL/Arabic. For a `.ttc`, the face alone is extracted as a standalone sfnt (`IFontFace.GetFaceFile`) — a raw `ttcf` container is not a valid `/FontFile2`. On Windows only since 2026-10-09: before, the whole collection was embedded. |
| `false` (default), Linux/macOS | Subset via `IFontSubsetter` (`mormot.lib.harfbuzz`, `libharfbuzz-subset`, R-12). Glyph IDs retained, so content streams, `/W` and `/ToUnicode` stay valid. Safe for Latin, CJK, shaped RTL and tagged output. |
| `false` (default), Windows | Subset via `CreateFontPackage` with a glyph keep list (`TTFCFP_FLAGS_GLYPHLIST`, R-15). Glyph IDs retained, so it is safe for the same cases as hb-subset — Latin, CJK, shaped Arabic (Uniscribe), tagged output. |

The whole face is embedded instead — silently, as before R-12 — when no
subsetter is registered (library missing, HarfBuzz < 2.9), for PDF/A-1 (6.3.5
would need a `/CIDSet`, which is not written), for symbol fonts (reached
through the `(3,0)` cmap). CFF-flavoured faces (`OTTO`) **are** subset since
R-15c; since the CFF series of R-28 a CID-keyed one is embedded as its bare
`CFF ` table (`/FontFile3 /Subtype /CIDFontType0C`), a name-keyed one as an
OpenType font file - see "CFF Faces: Type0 Only" below.

**macOS is where this matters.** Its CJK system faces are CFF:
`Hiragino Sans GB.ttc` is `OTTO` in all four faces, with a `CFF ` table and no
`glyf`. Before R-15c that face was embedded whole *and* in the wrong key, and
`chinese_demo` was ~10 MB; it is now ~23 KB. To check a face:

```bash
hb-info --face-index=0 <font> | grep outlines    # "Postscript" = CFF
grep -a -oE "/BaseFont[ ]*/[A-Za-z0-9+,#_-]+" out.pdf | sort -u
```

The grep only works on a file without object streams. Tagged output deflates
its font dictionaries, so it returns nothing there — which reads like "no fonts
embedded". Inflate every stream with `python3` and search the result instead.

**The CJK CFF faces are CID-keyed** (measured 2026-10-10 with
`PdfFaceCffInfo`, `TPdfCffTests.SystemFaces`): Hiragino Sans GB is
Adobe-GB1 with 288 glyphs whose CID is not their glyph index; Noto Sans CJK
is Adobe-Identity, every CID its index. hb-subset keeps the ROS, the
FDArray and the charset: the subset in the Mac `cjk_subset` baseline is
Adobe-GB1-6, 3416 glyphs (`--retain-gids`). The codes of a `CIDFontType0`
are CIDs (ISO 32000-1 9.7.4.2), not glyph indexes, so writing glyph indexes
under Identity-H draws the wrong glyph for those 288 - fixed by the CFF
series of R-28 (below). An earlier note here called Hiragino name-keyed
after a veraPDF log line (`The Top DICT does not begin with ROS operator`);
the measurement contradicts it.

`PdfCffParse` (`mormot.pdf`) reads a bare `CFF ` table bounded - every INDEX
offset, the Top DICT operands, the charset formats 0/1/2 - and refuses
(`pcInvalid`) rather than guesses: duplicate CIDs, a predefined charset in a
CIDFont (TN #5176 13), a ROS string that is a CFF standard string (no real
face does that; the 391 names are not carried), CFF2 (variable OpenType:
no PDF 1.x font program). `PdfFaceCffInfo` reads the table raw through
`GetFontData` - `GetTtfData` swaps 16-bit words. A name-keyed face (a Latin
OTF such as Nimbus Sans of `fonts-urw-base35`) has no ROS; its code is the
glyph index. None is installed on the test machines: Windows 11 has no CFF
face at all, WSL Ubuntu only Noto CJK.

### CFF Faces: Type0 Only (the CFF series of R-28)

A CID-keyed or an embedded CFF face (`TPdfFontTrueType.Type0Only`, decided
when the WinAnsi font is created: `fInternal`) draws all its text through
its Type0 font. A simple font cannot take a CID-keyed CFF program (9.6.2.1,
table 126), and its Latin text went through one before. An unembedded
name-keyed face keeps its Latin text in the simple font: without a program
its glyph indexes mean nothing to a viewer, a WinAnsi font it substitutes.
The descendant, `/CIDToGIDMap` and the names follow `GetCff <> pcNone`.
Embedding switched on after such a face was created renames its simple font
`/Type1`; switched off after a name-keyed face was created embedded, the save
raises `EPdfInvalidOperation` (its text is glyph indexes without a program).
- **Codes:** `GlyphCode(glyph)` is the CID of a CID-keyed face (`fCff.Cid`,
  read once by `GetCff` on the WinAnsi font), the glyph index otherwise.
  Every writer of Type0 codes goes through it - the three branches of
  `AddShapedRun`, `AddGlyphFromChar` with the face that drew the glyph (a
  fallback face its own way), `AddGlyphsOf` - and `PdfUsedCodes`, which
  keys `/W` and `/ToUnicode`. Shaping, metrics and the subset request keep
  glyph indexes
- **Routing:** `SetPdfFont` puts the Type0 font in place of the WinAnsi font
  of such a face before its equality check, the page resources and `Tf`
  (`SetFont` still returns the WinAnsi font); `ShowText(PdfString)` leaves
  its literal fast path and decodes with the document code page; the
  unshaped writer keeps WinAnsi characters in the glyph string, one string
  per run
- **The WinAnsi font is internal:** created with `TPdfFont.Create(...,
  ARegister = false)` (`fInternal`), it keeps the metrics, the descriptor,
  the subset request and the font file, but its dictionary is not in the
  xref - it frees it - and it writes no `/ToUnicode` stream
- **Measurement:** `GetAnsiCharWidth` of the Unicode font asks the WinAnsi
  font (it has no WinAnsi widths: the default width - also after Unicode
  text with a glyf face); a Type0Only face measures with the widths of `/W`
  it is drawn with (`GetWideCharWidth` skips the WinAnsi shortcut) - which
  registers the measured characters as used: they reach `/W`, `/ToUnicode`
  and the subset even if never drawn, as non-Latin text measured did before
- **Word spacing:** `Tw` applies to the one-byte code 32 only (9.3.3). A
  Type0 glyph string with a word spacing is a `TJ` array with
  `-1000 * WordSpace / FontSize` after each U+0020/U+00A0, the next line
  written before it as `T*` (TJ has no next-line form) - for a Type0Only
  face only: a glyf face keeps its output - the one space allowed inside a
  Unicode run and the spaces of a symbol font get no adjustment, as before
  the series. Spaces inside a shaped run and `ShowGlyph` get no adjustment
  (open: HarfBuzz gives clusters, Uniscribe not)
- **q/Q:** `GSave` keeps the page's font, size, word and character
  spacing, scaling and leading (`fTextStateSaved`), `GRestore` puts them
  back as `Q` restores `Tf`, `Tw`, `Tc`, `Tz` and `TL` - the canvas cached
  them across `Q`, so a setting could be skipped and the adjustment computed
  from a stale size. No font is put back (one selected inside q/Q only):
  text after it keeps the font of before rather than none. `TPdfForm` keeps
  the page's saved states apart from its own q/Q
- **Subset:** kept only if every used glyph has the CID of the face in it,
  under the same ROS (`PdfSubsetKeepsCids`, on `Request.Glyphs`); the whole
  face otherwise. hb-subset keeps the charset as a prefix of the face's
- **Program:** CID-keyed - the bare `CFF ` table (`SfntTableOf`) as
  `/FontFile3 /Subtype /CIDFontType0C`, PDF 1.3, so also PDF/A-1 (whole face
  there, no `/CIDSet` needed), the face's ROS as `/CIDSystemInfo`;
  name-keyed - the OpenType font file, `/Subtype /OpenType`, PDF 1.6:
  `CheckFontProgram` raises `FileFormat` before the header; after it
  (`HeaderFileFormat` - `TPdfDocumentGdi` and `TGDIPages` stream from the
  start) it sets `/Version /1.6` in the catalog, which is written last
  (7.5.2, as iText does); rechecked before the program is written, as
  `EmbeddedTTF` may change; PDF/A-1 refuses. The descendant is a
  `CIDFontType0` for every CFF face, read from the face - a whole or
  unembedded one was a `CIDFontType2` before
- **Names:** `/BaseFont` and `/FontName` are the program's name behind the
  subset tag (tables 117, 122): the CIDFontName of a bare CFF
  (`TPdfCffInfo.FontName`), the PostScript name (name ID 6,
  `SfntPostScriptName`) of an OpenType font file, which may differ from its
  CFF name. A space in a name is `#20` (7.3.5): `ESCAPENAME` lacked it
- **Not conforming, left as before:** a CFF face the reader refuses
  (malformed, CFF2) is embedded as an OpenType font file with glyph-index
  codes. No name-keyed-to-CID-keyed rewriter (cairo and LuaTeX have one)
- **Checked on macOS** (2026-10-10): U+9FA6 of Hiragino Sans GB (glyph
  29064, CID 30284) rendered by PDFKit as CoreText draws it, and extracted
  as U+9FA6. The synthetic face of `test_pdf_cff` (`FakeFace`,
  `SwapInFakeFace`: cmap, head, hhea, hmtx, maxp, CFF and name tables built
  in code, swapped into `FontProvider`) runs every path on every platform

Found on the way: a run that switched to the fallback face mid-run wrote
the fallback codes without an opening `<` (also in the original,
`reference/mormot.ui.pdf.pas:5340`); and the `/ToUnicode` codespace of
every Type0 font ran from the glyph of the first character to the glyph of
the last - inverted whenever they were out of order. It is `<0000> <FFFF>`
now, and `/W` and `/ToUnicode` are sorted by code, one entry per code.

**Every `.ttc` face hinges on `TFreeTypeFont.SfntChecked`.** `GetFontData(0)`
extracts the loaded face once and caches it in `Sfnt`; with `SfntChecked` set
and `Sfnt` empty it hands out FreeType's whole collection instead. The face then
reads as neither CFF nor a single font, hb-subset fails, and the raw `ttcf`
container lands in `/FontFile2` (veraPDF `ua1` 7.21.4.1). `CreateFont` (now `CreateFace`) left
the flag to the heap until 2026-09-26 — `New()` initializes managed fields
only — so this happened at random, by heap layout, on Linux and macOS. The
signature: a PDF of megabytes, a CJK face without subset tag, a stream that
begins with `ttcf`. Set every non-managed field of a `New()`ed record.
`TestTaggedUnicode` asserts no `ttcf` stream and `/Subtype/OpenType` on every
`OTTO` stream.

### POSIX subset input (`TPdfDocument.PrepareFontSubsets`)

Built per **face bytes**, before the first font is serialized, as the union over
every WinAnsi `TPdfFontTrueType` resolving to that face (the WinAnsi/Unicode
pair shares one face by construction; Regular and Bold of a `.ttc` face can too):
- `Unicodes` — `fWinAnsiUsed` mapped through the WinAnsi table (0x80 → U+20AC)
  plus `fUsedWideChar`. **Required:** a simple TrueType font with
  `/WinAnsiEncoding` reaches its glyphs through the `(3,1)` cmap, and hb-subset
  rebuilds the cmap only for these code points
- `Glyphs` — every `fUsedWide[].Glyph`, and every glyph without a code point
  (`fShapedGlyph`, §8 Step 3). The Identity-H instance addresses glyphs by ID.
  `Unicodes` holds real code points only since 2026-10-08 (before, the
  synthetic `$E000` keys of shaped glyphs were in it too)

Flags: `RETAIN_GIDS` (mandatory), `NOTDEF_OUTLINE` (a missing glyph stays a
visible box), `NO_HINTING`; `GSUB/GPOS/GDEF` are dropped
(`HbSubsetFlags`, `HbSubsetDropLayoutTables`). With retain-gids `maxp.numGlyphs`
becomes highest kept ID + 1 — IDs never move. hb-subset also adds cmap entries
for glyphs requested by ID; harmless.

Each face is subset once, so its fonts share identical bytes and
`GetOrCreateFontFile2` still writes one stream. `/FontName` and `/BaseFont` of
the WinAnsi, CIDFont and Type0 objects get the same `ABCDEF+` tag, derived from
`crc32c` of the subset (deterministic output).

### Windows subset input (`CreateFontPackage`)

The same request as on POSIX, through `FontSubsetter` since W2
(`TFontSubSubsetter`, `mormot.lib.uniscribe`; `platform-backends.md`). A glyph
keep list (`TTFCFP_FLAGS_GLYPHLIST`) rather than code points, so the glyph IDs
stay where they are: the subsetter resolves `Request.Unicodes` to glyph
indices through the font itself (`GetGlyphIndicesW`; before W2 the engine did
it for the WinAnsi characters, `AddWinAnsiGlyphs`, R-15a), which works
whatever cmap the lookup goes through — symbol fonts included, unlike POSIX
(R-15b; `SupportsSymbolic`). A face of a `.ttc` is subset from the whole
collection at the index found from the bytes (`TtcFaceIndex`; before W2 the
family-name list `GetTtcIndex`, wrong for 14 of 30 collections).
`TestSubsetTtcFace` checks four such faces and two of index 0 on the saved
PDF, and `TestWholeTtcFace` the same faces embedded whole; both also cover
Noto Sans CJK JP on Linux and Hiragino Sans GB and Helvetica on macOS (the
FreeType side, face 0), when installed
(`EmbeddedWholeTtf`, PDF/A-1, no subsetter); both run wherever one of the
fonts is installed - on Windows, or on a Mac with the Office fonts (face 0
only there: `TFontFileMap` reaches no other). `TestSubsetSymbolFont`
subsets Wingdings (`SYMBOL_CHARSET`: only that makes a font symbolic) and
checks `SupportsSymbolic`. The subset has no `name` table left (`ReduceTtf`), and the faces of
these collections share `glyf` and `hmtx`: the test tells them apart by `cmap`
(`MS UI Gothic` maps 'H' to glyph 18634, `MS PGothic` to 16116) and `hhea`
(the UI faces of YaHei, JhengHei, Yu Gothic), read through `FontProvider`
from the face the platform selects. The whole face is embedded for PDF/A-1,
as on POSIX.

The 32-bit `fontsub.dll` writes `language` = `0x0008CA34` into the format 12
(3/10) `cmap` subtable of a subset, the 64-bit one 0 (spec: 0). Source face and
our input both say 0 and the tables are copied unchanged, so it is the DLL's
own output — stable, ignored by viewers and validators. It is the one
byte-level difference between Delphi/Win32 and FPC/Win64 subsets
(`chinese_demo`'s Microsoft YaHei; faces without format 12 are identical).

---

## 4. TPdfFontTrueType — Dual-Mode Font Object (`pdf.pas:2611`)

Every TrueType font exists as **two linked instances**:

| Instance | `fUnicode` | Purpose |
|---|---|---|
| WinAnsi font | `false` | Renders U+0000–U+00FF via `(text) Tj`; tracks actually-used chars - of a CFF face: internal, never selected, not written |
| Unicode font | `true` | CID/Identity-H font; renders non-Latin via `<XXXX> Tj` - of a CFF face: all text; loaded with full CMAP at creation |

Navigation:
- `WinAnsiFont` — returns the WinAnsi instance (self or linked peer)
- `UnicodeFont` — `nil` until first non-Latin char (of a CFF face: until
  `SetPdfFont` selects it); created lazily by `CreateAssociatedUnicodeFont`

Two rules of the written dictionaries, both found by PAC 2024 on tagged CJK and
Arabic output (R-19, 2026-09-26):
- **A WinAnsi peer with no used character** — a glyf face that draws only
  CJK or Arabic: `SetFont` writes `Tf` for it anyway, and it was written without
  `/FirstChar`, `/LastChar` and `/Widths`, which a simple TrueType font
  requires. It now gets `/FirstChar 32 /LastChar 32` and the width of the
  space. Dropping the peer altogether is on the roadmap.
- **`/CIDToGIDMap /Identity`** is written for every `CIDFontType2`, not for
  PDF/A only: PDF/UA-1 7.21.3.2 wants it although Identity is the default. A
  `CIDFontType0` (CFF) never has one (table 117 defines it for Type2 only) -
  since the CFF series; before, it was written for PDF/A.
`TestTaggedUnicode` (`test_pdf_smoke`) asserts both for glyf faces,
`EmbeddedPrograms` (`test_pdf_cff`) the CFF side.

### Key Fields (`pdf.pas:2611`)

| Field | Type | Instance | Purpose |
|---|---|---|---|
| `fUsedWideChar` | `TSortedWordArray` | WinAnsi | sorted Unicode code points used during rendering; drives `CreateFontPackage` and `/W` array |
| `fUsedWide` | `TUsedWide` (dyn. array) | WinAnsi | parallel to `fUsedWideChar`: packed `(Width: word; Glyph: word)` per code point |
| `fWinAnsiUsed` | `TSynAnsicharSet` | WinAnsi | 256-bit set of WinAnsi chars used (U+0020–U+00FF); drives `/FirstChar`–`/LastChar /Widths` |
| `fDefaultWidth` | `cardinal` | WinAnsi | advance width of space char; used as PDF `/DW` for unregistered glyphs |
| `fFace` | `IFontFace` | both | the face, shared by both instances (reference counted); `fFace.Handle` is the GDI `HFONT` or the `PFreeTypeFont` (Phase 1b; `fHGDI` before) |
| `fFixedWidth` | `boolean` | WinAnsi | true = monospace; outside PDF/A `/W` is omitted, all glyphs use `/DW` |
| `fIsSymbolFont` | `boolean` | Unicode | true = Symbol charset (glyphs at U+F0xx) |

### TUsedWide Packed Record (`pdf.pas:2598`)

```pascal
TUsedWide = array of packed record
  case byte of
    0: (Width: word; Glyph: word;);   // access Width and Glyph separately
    1: (Used: integer;);              // copy as single 32-bit: (Width shl 16) or Glyph
end;
```

**Critical invariant:** `length(fUsedWide) >= fUsedWideChar.Count` always.
Both arrays grow together inside `FindOrAddUsedWideChar` (§8).
The UnicodeFont's arrays are fully populated at construction (entire CMAP);
the WinAnsi font's arrays only contain actually-used code points.

---

## 5. Font Loading — `TPdfTtf.Create` (`pdf.pas:6065`)

Called once per Unicode font instance: `TPdfTtf.Create(self).Free`.
Reads its tables from the face, `aUnicodeTtf.fFace.GetFontData` (before
Phase 1b it read the document DC and relied on the font its caller had
selected):

1. **`head` + `hhea`** — provides `UnitsPerEm` and `numOfLongHorMetrics`
2. **`cmap`** — Format 4 segment map: populates
   - `UnicodeFont.fUsedWideChar.Values[]` — one entry per code point in the CMAP
   - `UnicodeFont.fUsedWide[].Glyph` — glyph ID per code point
3. **`hmtx`** — Horizontal metrics: sets `UnicodeFont.fUsedWide[].Width` per glyph
   - Formula: `Width = (hmtx_advance * 1000) shr unitShr`
     where `unitShr = floor(log2(UnitsPerEm))` (i.e. divide by em-square, scale to 1000 units)
   - **Fixed (P3-C):** The original formula `shr unitShr` where `unitShr = floor(log2(UnitsPerEm))`
     was only correct for power-of-2 UPM (1024, 2048, …). For UPM=1000 fonts (e.g. Noto Naskh
     Arabic): divisor was 512 instead of 1000 → every `/W` width 1.953× too large → characters
     spaced too far apart. Fixed to `(int64(hmtx_advance) * 1000) div UnitsPerEm`.

### Subtable selection (cmap)

Preference order, in `TPdfTtf.Create`:
1. Microsoft platform `(3,1)` Unicode BMP — preferred, `break`s the scan
2. Microsoft platform `(3,0)` symbol — also sets `fIsSymbolFont := true`
3. **Unicode platform `(0,3)` then `(0,4)`** — fallback used only when no
   Microsoft subtable exists at all. Required for Apple fonts: faces 0–4 of
   macOS `GeezaPro.ttc` expose *only* `(0,3)`, and before this fallback the
   parser returned an empty CMAP, so every Arabic glyph came out `.notdef` and
   the document silently fell back to `FontFallBackName` (Arial Unicode MS).

Only **format 4** is parsed. A `(0,4)`/`(3,10)` format 12 subtable is selected
only when nothing else exists, and then rejected by the format check.

### Odd subtable offsets

`GetTtfData` byte-swaps the table as 16-bit words, so a subtable at an **odd**
byte offset cannot be read directly — every 16-bit field would straddle two
swapped words. `TPdfTtf.Create` detects this and undoes the swap, then redoes
it from the odd boundary (the same repair `TrueTypeFontName` applies to the
`name` table).

> The guard used to run *before* the 32-bit offset halves were swapped back, so
> it tested bit 16 instead of bit 0 and never fired. macOS `Hiragino Sans GB`
> has its `(3,1)` subtable at `$A5B` and was silently mis-parsed despite having
> a perfectly good Microsoft map.

After `TPdfTtf.Create`:
- UnicodeFont has **all** code points from the font CMAP with correct PDF-unit widths
- WinAnsi font's tracking arrays (`fUsedWideChar`, `fUsedWide`, `fWinAnsiUsed`) remain empty until text is actually rendered

---

## 6. Text Rendering Chain — WinAnsi (Latin) Path (`pdf.pas:5484–5548`)

```
TPdfVclCanvas.TextOut(X, Y, S)              pdfcanvas.pas:273
  StringToSynUnicode(S) → W: SynUnicode   (TextOutUtf8: Utf8ToSynUnicode)
  → TPdfCanvas.TextOutW(X, Y, W)            pdf.pas:8992
      → TPdfWrite.ShowText(PW)              pdf.pas:9463
          → TPdfWrite.AddUnicodeHexText(PW, Len, false, Canvas)   pdf.pas:5549

TPdfWrite.AddUnicodeHexText:
  if UseUniscribe=false or ttf=nil:
    → AddUnicodeHexTextNoUniScribe(PW, ttf, false, Canvas)

AddUnicodeHexTextNoUniScribe (pdf.pas:5484):
  (a CFF face: every character takes the non-Latin branch below)
  for each WideChar PW^:
    if WideCharToWinAnsi(PW^) >= 0:           // U+0000..U+00FF in Latin-1
      Add('(') … Add(') Tj')
      include(WinAnsiFont.fWinAnsiUsed, Char)  // mark char used (pdf.pas:5554)
    else:                                      // non-Latin char
      glyph := AddGlyphFromChar(PW^, Canvas, Ttf)
        ttf.CreateAssociatedUnicodeFont         // lazily create Unicode instance
        FindOrAddUsedWideChar(Char)             // register in tracking arrays
        → SetPdfFont(UnicodeFont)               // switch to CID font
        → Add('<XXXX> Tj')                      // write CID glyph reference
```

---

## 7. Text Rendering Chain — Uniscribe / HarfBuzz (RTL, Complex Scripts)

One path on every platform since W2 (2026-10-08); the shaper is `FontShaper`
(`TUniscribeShaper` on Windows, `THarfBuzzShaper` on Linux/macOS):

```
TPdfWrite.AddUnicodeHexText:
  shaped := UseUniscribe and ttf <> nil and
            AddUnicodeHexTextShaped(PW, Len, ttf.WinAnsiFont, NextLine, Canvas)
  if not shaped:
    AddUnicodeHexTextNoUniScribe(...)            // Latin text, or no shaper

AddUnicodeHexTextShaped:
  FontShaper.Shape(PW, Len, WinAnsiTtf.fFace.Handle, RightToLeftText, Runs)
    false → not shaped                           // e.g. no complex/RTL item
  every run checked first: inside the text, covering it, arrays aligned
    else → not shaped
  MoveToNextLine once if NextLine
  per run (visual order):
    fskPlain or fsoUnknown → AddUnicodeHexTextNoUniScribe(#0-terminated copy)
    fskShaped              → AddShapedRun(Run, WinAnsiTtf)
    fskSkip                → nothing

AddShapedRun(Run, WinAnsiTtf):
  SetPdfFont(WinAnsiTtf.UnicodeFont, FontSize)   // CID font, even with no glyph
  no glyph → done (Uniscribe: every glyph was zero-width)
  no Advances (Uniscribe): '<' + GlyphCode(GetAndMarkGlyphAsUsed(g))... + '> Tj'  // §8
  Advances (HarfBuzz): GetAndMarkGlyphAsUsedWithWidth per glyph, then one Tj,
    or a TJ where an offset or the hmtx width differs (§10, U-2) - the codes
    GlyphCode(g): the CID of a CID-keyed CFF face
```

**Important:** a shaped run always goes to the Unicode (CID) font of the font
it was shaped with - never to the font left active by the run before it,
which may be the fallback font (fixed 2026-10-08, `TestShapedAfterFallback`).
The zero-width filter of Uniscribe is in the shaper; the public `AddGlyphs`
keeps its own for callers passing `TScriptVisAttr`s. Details per outcome:
`platform-backends.md`, IFontShaper.

---

## 8. Key Internal Functions

### `FindOrAddUsedWideChar(aWideChar)` — WinAnsi font only (`pdf.pas:6189`)

Registers a Unicode code point in the WinAnsi font's tracking arrays.
Called from the WinAnsi text rendering path for every non-Latin character.

```
fUsedWideChar.Add(ord(aWideChar))   — sorted insertion into WinAnsi tracking array
                                       returns -(found_index+1) if already present
if already present:
  result := -(Add_result + 1)        — decode the existing index
  exit                               — fast path, no further work

if new entry (result = insertion index):
  if length(fUsedWide) = fUsedWideChar.Count - 1:
    SetLength(fUsedWide, fUsedWideChar.Count + 100)   — grow in chunks of 100
  MoveFast(fUsedWide[result], fUsedWide[result+1], ...)  — shift right to make room
  if UnicodeFont = nil:
    CreateAssociatedUnicodeFont              — lazy creation on first non-Latin char

  i := UnicodeFont.fUsedWideChar.IndexOf(ord(aWideChar))
  if (i < 0) or (i >= length(UnicodeFont.fUsedWide)):
    i := 0                           — char absent from CMAP → .notdef glyph
  else:
    i := UnicodeFont.fUsedWide[i].Used
  fUsedWide[result].Used := i               — copies Width + Glyph as one int32

returns: index into WinAnsi fUsedWideChar[] / fUsedWide[]
```

### `AddGlyphFromChar(Char, Canvas, Ttf, NextLine)` — `TPdfWrite` (`pdf.pas:5419`)

Entry point for every non-Latin character in the `AddUnicodeHexTextNoUniScribe` path.
`Ttf` is always the WinAnsi font (enforced by the assert at pdf.pas:5426 and the
`Ttf := Ttf.WinAnsiFont` assignment at pdf.pas:5496 in the caller).

```
assert (Ttf <> nil) and (not Ttf.Unicode)
idx := Ttf.FindOrAddUsedWideChar(Char)    — grows Ttf.fUsedWide if this is a new char
if idx < length(Ttf.fUsedWide) then
  Glyph := Ttf.fUsedWide[idx].Glyph
else
  Glyph := 0

if Glyph = 0 and fUseFontFallBack and fFontFallBackIndex >= 0:
  fnt := Canvas.SetFont('', size, style, -1, fFontFallBackIndex)   — switch to fallback
  idx  := fnt.FindOrAddUsedWideChar(Char)
  if idx < length(fnt.fUsedWide) then
    Glyph := fnt.fUsedWide[idx].Glyph
  else
    Glyph := 0
else:
  fnt := Ttf

Canvas.SetPdfFont(fnt.UnicodeFont, size)  — switch page font to CID font for output
Add('<XXXX>')                              — write CID hex
```

### `GetAndMarkGlyphAsUsed(aGlyph)` — WinAnsi font only (`pdf.pas:6273`)

Called by `AddGlyphs` for every Uniscribe/HarfBuzz shaped glyph.
Maps shaped (GSUB-substituted) glyph IDs back to tracked entries via reverse CMAP.

```
Step 1: scan WinAnsiFont.fUsedWide[0..Count-1].Glyph == aGlyph
          → found: already registered, return aGlyph unchanged (fast path)

Step 2: scan UnicodeFont.fUsedWide[0..Count-1].Glyph == aGlyph  (reverse CMAP)
          → found: WinAnsiFont.FindOrAddUsedWideChar(UnicodeFont.fUsedWideChar.Values[i])
                   return WinAnsiFont.fUsedWide[idx].Glyph
                   (call must be qualified as WinAnsiFont.FindOrAddUsedWideChar —
                    bare call inside "with UnicodeFont do" would resolve to UnicodeFont's method)
          → not found: fall through to Step 3

Step 3: GSUB-substituted glyph — not in CMAP at all (rare ligature, etc.)
  every platform since W3 (2026-10-09; Windows only before):
          fFace.GetGlyphAdvance(aGlyph, w)
                                    ← by glyph index, 1000/em units
                                      (GDI GetCharABCWidthsI, FreeType
                                       FT_Load_Glyph); failure → fDefaultWidth
          AddShapedGlyph(aGlyph, w)                        ← WinAnsiFont.fShapedGlyph
  → glyph now registered in /W array; no more overlap from /DW fallback
  HarfBuzz runs carry their advances: GetAndMarkGlyphAsUsedWithWidth (see §10)
```

**Arabic Presentation Forms in CMAP:** Fonts like Tahoma map U+FE70–U+FEFF (Arabic
Presentation Forms-B) to the same glyph IDs that Uniscribe produces for shaped contextual
forms. Step 2 therefore finds most Arabic shaped glyphs. Step 3
remains the backstop for fonts whose GSUB glyphs have no Presentation-Form Unicode slot.

**Width unit compatibility:** `GetGlyphAdvance` returns logical units (GDI's `GetCharABCWidthsI`). Because `lfHeight = -1000` (pdf.pas:8854), the DC em square = 1000 logical units, making these widths directly compatible with `fUsedWide[].Width` (also 1000/em from hmtx). No unit conversion needed.

---

## 9. Font Serialization — `PrepareForSaving` (`pdf.pas:6568`)

Called on `Doc.SaveToFile` / `Doc.SaveToStream` for every font in `fFontList`,
after `PrepareFontSubsets` (§3). Runs for **both** WinAnsi and Unicode instances.

### Unicode font branch (`pdf.pas:6594`): builds CID font dictionary

```
/DW  = WinAnsiFont.fDefaultWidth               (space char width, e.g. 167 for Tahoma)

PdfUsedCodes(WinAnsiFont)   GetUsedGlyphs: characters (fUsedWide[]) and
                            glyphs without a code point (fShapedGlyph),
                            merged in key order (§8); each glyph's code
                            GlyphCode() (the CID of a CID-keyed CFF face),
                            sorted by code, one entry per code - the
                            smallest Unicode value wins
/W array construction:
  if WinAnsiFont.fFixedWidth and not PDF/A:
    omit /W entirely (all glyphs use /DW)
  else:
    c [w1 w2 ...] per run of consecutive codes

ToUnicode CMap codespace = <0000> <FFFF>, bfchar sorted by code
```

Until the CFF series of R-28 the codespace ran from the glyph of the first
to the glyph of the last entry by key - with Segoe UI's shaped glyphs 240,
241 and 4336 `<0000> <00F1>`, glyph `<10F0>` outside; the Windows CJK golden
file had the inverted `<040D> <036B>`

### WinAnsi font branch (`pdf.pas:6671`): builds /Widths array, embeds font file

```
/FirstChar, /LastChar, /Widths built from fWinAnsiUsed + WinAnsi ABC widths

Font embedding decision:
  if EmbeddedWholeTtf = true, for PDF/A-1, or with no FontSubsetter (or a
  symbol font and not SupportsSymbolic, or a failed subset):
    fFace.GetFaceFile(ttf)                       → the face as one font file
    (no face → the save raises EPdfInvalidOperation; IsEmbedded is true for
    PDF/A, for Tagged, or with EmbeddedTtf unless in EmbeddedTtfIgnore)
    safe for all scripts; shaped GSUB glyph IDs are valid in the complete font
    .ttc: just the face, rebuilt as an sfnt (ExtractSfntFromTtc) - FreeType
          the face it loaded, GDI the face TtcFaceIndex finds (since
          2026-10-09; before, Windows embedded the whole collection)
    the stream is shared: TPdfDocument.GetOrCreateFontFile2() reuses one
    TPdfStream for byte-identical data, so Regular and Bold resolving to the
    same physical file embed it once, not twice

  if EmbeddedWholeTtf = false (the default):
    Linux/macOS: the subset prepared by PrepareFontSubsets replaces the bytes
      (see §3 "POSIX subset input"); the name gets its ABCDEF+ tag
    Windows: the same, the subset made by FontSub (TFontSubSubsetter,
      CreateFontPackage) in PrepareFontSubsets since W2; FontSub.dll absent
      or NO_USE_UNISCRIBE → no FontSubsetter → the whole face
```

---

## 10. RTL / Arabic — Behavior and Known Limitations

### `lfCharSet` on Windows

`TPdfVclCanvas.SyncFont` passes `Font.Charset` (LCL default: `DEFAULT_CHARSET (1)`) to
`TPdfCanvas.SetFont`. This ensures GDI exposes the full Unicode CMAP to `GetFontData`
regardless of the system codepage (`fDoc.CharSet`).

When `TPdfCanvas.SetFont` is called directly with `ACharSet < 0`, it falls back to
`fDoc.CharSet`. On Western Windows (codepage 1252) this is `ANSI_CHARSET (0)`, which
restricts the CMAP to ANSI-mapped characters. Always pass an explicit charset when
calling `SetFont` directly with non-Latin fonts.

On Unix/macOS: `fCodePage = CP_UTF8 → fCharSet = DEFAULT_CHARSET (1)` — safe regardless.

### Arabic rendering

**Setting the flag: never behind `{$ifdef USE_UNISCRIBE}`.** That symbol is
defined in `mormot.pdf.defines.inc`, which only `mormot.pdf` and `mormot.pdf.canvas`
include: it does not reach the units that use them, so a
guarded `Doc.UseUniscribe := true` compiles to nothing and the shaper never
runs — Section 2 of `rtl_demo` then produces output byte-identical to its
no-shaper Section 1. This was ROADMAP R-16. The property is declared
unconditionally for that reason, and since 2026-09-29 it is the shaping switch
on Linux/macOS too (HarfBuzz; `RightToLeftText` is the direction only —
`platform-backends.md`, Registration). `TestUseUniscribeIsPortable` fails to
compile if it is ever gated again; `TestShapingSwitch` checks the output.

`UseUniscribe=true` (Windows, complex scripts):
- Uniscribe shapes Arabic contextual forms via `ScriptShape` → GSUB glyph IDs
- `GetAndMarkGlyphAsUsed` registers shaped glyph IDs via reverse CMAP scan (Step 2)
- Fonts like Tahoma: shaped glyphs found in Arabic Presentation Forms (U+FE70–U+FEFF)
- For fonts without Presentation-Form coverage: Step 3 (`GetGlyphAdvance` + `fShapedGlyph`) handles remaining GSUB-only glyphs

### Step 3 on Linux/macOS — HarfBuzz path (P2-A, APPLIED)

`GetAndMarkGlyphAsUsed` Step 3 uses `FontProvider.GetGlyphAdvance` (every
platform since W3; before, `GetCharABCWidthsI`, Windows only). A HarfBuzz run
brings its own advances, so Linux/macOS use
`GetAndMarkGlyphAsUsedWithWidth(aGlyph, aWidth)` there:
- Called from `AddShapedRun` for a run with `Advances` (HarfBuzz) instead of
  `GetAndMarkGlyphAsUsed`
- the width written to `/W` comes from `GlyphHmtxWidth()`, i.e. the font's own
  `hmtx` advance. `aWidth` — the HarfBuzz `x_advance` — is only a fallback for
  when the tables cannot be read.
- **The two are not the same number.** HarfBuzz returns the *positioned*
  advance, so a glyph with a GPOS cursive adjustment comes back shortened by
  exactly the amount it is offset. `/W` must state the unpositioned advance
  (ISO 14289-1 7.21.5), and the caller makes up the difference in `TJ`, so the
  pen still moves by the shaper's advance. Writing `aWidth` into `/W` made both
  wrong at once and cancelled out on screen — invisible in a viewer, a PDF/UA
  failure (U-2).
- Same registration as Step 3: `AddShapedGlyph` into `fShapedGlyph`
- Result: GSUB-only shaped glyphs get correct `/W` entries; no `/DW` overlap

**Whether Step 3 is reached at all depends on the font's CMAP**, and this is the
single most important thing to know about RTL here:

| Font | Presentation forms U+FE70–FEFF in CMAP? | Path taken | Width source |
|---|---|---|---|
| Noto Naskh Arabic (Linux) | yes | Step 2 | `hmtx`, via the CMAP |
| Geeza Pro (macOS) | **no** | Step 3 | HarfBuzz advance |

So on Linux the HarfBuzz advance is computed and then **discarded** — the shaper
width path is effectively dead code there. Any bug in it is invisible on Linux
and fatal on macOS. Check the `ToUnicode` CMap to tell which path ran: real
U+06xx code points mean Step 2, PUA U+E0xx values mean Step 3.

### HarfBuzz scaling — do NOT use FT_LOAD_NO_SCALE

`hb_ft_font_create` copies its scale out of `ft_face^.size^.metrics`, so the
FT_Face **must be sized first** — `FreeTypeSetEmSize1000()` in the FreeType backend
does this (1000 units per em at 72 dpi). `CreateFace` deliberately does not size
the face, because every other entry point uses `FT_LOAD_NO_SCALE` or reads
design-unit fields.

Modern HarfBuzz (~2.6.5+) dropped the old "`FT_LOAD_NO_SCALE` returns raw design
units" behaviour and now always multiplies the advance by a factor derived from
the font scale. With an unsized face that factor is 0, so **every advance came
back as 0** and all shaped glyphs stacked on one spot. Measured on HarfBuzz
10.2.0 with Noto Naskh Arabic (correct design units: 253 292 636 404 456):

| face sized | load flags | resulting advances |
|---|---|---|
| no | default | 0 0 0 0 0 |
| no | `NO_SCALE` | 0 0 1 0 0 |
| **yes** | **default / `NO_HINTING`** | **253 292 636 404 456** (26.6, `div 64`) |
| yes | `NO_SCALE` | 0 0 1 0 0 |

`Shape` therefore sizes the face, sets `FT_LOAD_NO_HINTING`, and converts
26.6 to PDF units with `From26Dot6()`. Regression test:
`TestTextShaperAdvances` in `tests/test_pdf_crossplatform.pas`.

### Arabic rendering on Linux/macOS — Status nach P2-A ✅ COMPLETE

HarfBuzz shaping is implemented and Arabic renders with correct ligatures and
cursive joining on both Linux and macOS.

> This section previously claimed completeness on the strength of Linux output
> alone. That was misleading: with Noto Naskh Arabic every shaped glyph resolves
> through the CMAP (Step 2), so Linux never exercised the shaper's own advances.
> On macOS with Geeza Pro it did, and they were all zero. Validate RTL changes
> against a font **without** Arabic presentation forms, or the broken path stays
> invisible — that is what `TestTextShaperAdvances` now pins down.

---

### P3-A — Falscher Fix (zurückgenommen)

Ursprüngliche Hypothese: Step 2 in `GetAndMarkGlyphAsUsedWithWidth` ignoriert den HarfBuzz-`aWidth`-Parameter; Fix wäre Überschreiben nach `FindOrAddUsedWideChar`.

**Hypothese war falsch.** Für CursiveAttachment-Glyphen (Mittelformen arabischer Schrift) setzt HarfBuzz `x_advance = 0`. P3-A schrieb diese Nullwerte in `/W` → alle Mittelglyphen hatten Breite 0 → Zeichen stapelten sich. Reverted.

**Wahre Ursache** war die `shr`-Formel in `TPdfTtf.Create` (§5): für UPM=1000 ergab `shr 9` den Divisor 512 statt 1000 → alle hmtx-Breiten 1.953× zu groß → Lücken.
Fix (P3-C, applied): `(int64(hmtx_advance) * 1000) div UnitsPerEm` in `TPdfTtf.Create`.

---

### P3-B — Implemented (no effect with Noto Naskh Arabic)

- `IFontShaper.Shape` returns the offset per glyph in `Runs[0].Offsets`
  (`TFontShapedRun`, `mormot.lib.core`)
- the HarfBuzz shaper fills `Offsets[i] = From26Dot6(positions[i].x_offset)`
- `AddShapedRun` writes a `TJ` when an offset is not 0

With Noto Naskh Arabic every `x_offset` is 0, so `hasOffsets` stays false and
the `Tj` path is taken; fonts with GPOS positioning take the `TJ` path.

---

## 10b. RTL Paragraph — `VisualToLogical` Loop in `TUniscribeShaper.Shape`

`RightToLeftText := true` sets `uBidiLevel := 1` before `ScriptItemize`.

Since W2 the shaper itemizes exactly the text (`Len` code units) and takes
every item `ScriptLayout` orders: `for j := 0 to count - 1 do i :=
VisualToLogical[j]`. Before W2 the engine itemized `Len + 1` units (the `#0`
after the text) and skipped item `count - 1` as "the sentinel", which the RTL
level placed at visual position 0 - but that item may hold real text before
the `#0` (`platform-backends.md`, "The Windows paths").

---

## 10a. CJK (Chinese / Japanese / Korean)

| Property | CJK | Arabic |
|---|---|---|
| Shaping needed | No — `UseUniscribe=false` sufficient | Yes — Uniscribe/HarfBuzz for contextual forms |
| CMAP coverage | Format-4 BMP subtable covers all CJK Unified Ideographs (U+4E00–U+9FFF) | Arabic Presentation Forms (U+FE70–U+FEFF) |

With `UseUniscribe=false`, each CJK code point is looked up directly in the CMAP
(`UnicodeFont.fUsedWideChar.IndexOf`), its code `GlyphCode(glyph)` written
as `<XXXX> Tj` - the glyph ID, or the CID of a CID-keyed CFF face.
No GSUB shaping; `GetAndMarkGlyphAsUsed` is not called.

**Linux/macOS CJK font note:** CJK-only fallback fonts (e.g. `Droid Sans Fallback`) do not
contain Latin glyphs. Mixed Latin+CJK strings rendered with a CJK font will show `.notdef`
for the Latin portion. Render Latin segments with a separate Latin font.

---

## 11. `lfCharSet` Derivation Chain

How `lfCharSet` is determined when rendering via `TPdfVclCanvas`:

```
LCL TFont.Charset                        (graphics.pp:122)
  default = DEFAULT_CHARSET (1)

TPdfVclCanvas.SyncFont                   (pdfcanvas.pas:256)
  fPdfCanvas.SetFont(Font.Name, Abs(Font.Size), style, Font.Charset)
  ← Font.Charset passed explicitly → DEFAULT_CHARSET (1) by default
  ← user sets Font.Charset := SYMBOL_CHARSET (2) for symbol fonts

TPdfCanvas.SetFont(name, size, style, ACharSet)   (pdf.pas:8749)
  if ACharSet < 0: ACharSet := fDoc.CharSet       ← fallback (direct calls only)
  lfCharSet := ACharSet                            (pdf.pas:8853)
  CreateFontIndirectW(@lf)    ← HFONT with lfCharSet
  GetFontData(fDoc.fDC, 'cmap', ...)  ← full Unicode CMAP with DEFAULT_CHARSET

On Unix/macOS: no HFONT; FreeType reads CMAP directly from the TTF file.
```

**Symbol font safety:** `lfCharSet = SYMBOL_CHARSET (2)` selects the symbol CMAP subtable
(`platformSpecificID = TTFCFP_SYMBOL_CHAR_SET`). Set `Font.Charset := SYMBOL_CHARSET`
before rendering; `SyncFont` passes it through unchanged.

---

## 12. Platform Backend Summary

For full interface documentation see `.claude/skills/platform-backends.md`.

| Backend | Font handle | Key font APIs used |
|---|---|---|
| Windows GDI | `HFONT` (via `CreateFontIndirectW`) | `GetCharABCWidthsA/W`, `GetCharABCWidthsI`, `GetFontData` |
| FreeType2 (Unix/macOS) | `FT_Face` (via `FT_New_Face`) | `FT_Load_Char`, `FT_Load_Sfnt_Table` |

`GetFontData` / `FT_Load_Sfnt_Table` are used by `TPdfTtf.Create` to read raw TTF table bytes
(`cmap`, `hmtx`, `head`, `hhea`) for CMAP loading and glyph width extraction.

The platform layer is reached via the global `FontProvider: IFontProvider` interface.
Registration happens in the `initialization` section of the backend unit.

---

## 12a. FreeType Backend — Table Tag Byte-Order

Table tags are formed in `GetTtfData` (`pdf.pas:3610`) as `PCardinal(aTableName)^`:
a 4-char ASCII name read as a little-endian DWORD on LE machines.

FreeType's `FT_Load_Sfnt_Table` uses the `FT_MAKE_TAG` big-endian convention.
`TFreeTypeFontFace.GetFontData` applies `bswap32(TableTag)` before calling
`FT_Load_Sfnt_Table`. `bswap32(0)` = 0, preserving the tag=0 convention
("return entire font file") used by the whole-font embedding path.

| Table | LE tag (PDF engine) | BE tag (FreeType) |
|---|---|---|
| `cmap` | `$70616D63` | `$636D6170` |
| `head` | `$64616568` | `$68656164` |
| `hmtx` | `$78746D68` | `$686D7478` |
| `hhea` | `$61656868` | `$68686561` |
| `ttcf` | `$66637474` | `$74746366` |
| (whole font) | `$00000000` | `$00000000` |

---

## 13. GSUB Glyph Width — Implementation Notes (`pdf.pas:6247`)

Relevant for `GetAndMarkGlyphAsUsed` Step 3: a run without advances
(Uniscribe) or the public `AddGlyphs`.

### `GetCharABCWidthsI` — API details

Behind `IFontProvider.GetGlyphAdvance` in `mormot.lib.uniscribe` since W3.
Not in FPC's standard `windows` unit (commented out in `redef.inc`), so it is
declared there by hand:

```pascal
// 5 parameters — pgi=nil means consecutive glyphs starting at giFirst
function GetCharABCWidthsI(DC: HDC; giFirst, cgi: UINT; pgi: PWORD; lpabc: LPABC): BOOL;
  external 'gdi32' name 'GetCharABCWidthsI';
```

FPC type: use `TABC` (not `ABC`) in `var` blocks — `TABC = ABC` is the FPC alias. `LPABC = ^ABC`.

### Width unit compatibility

`lfHeight = -1000` (pdf.pas:8854) → DC em square = 1000 logical units.
`GetCharABCWidthsI` returns widths in those same 1000-per-em logical units.
`fUsedWide[].Width` (from `hmtx` via `TPdfTtf.Create`) is also 1000-per-em.
→ No unit conversion needed; values are directly comparable.

### Glyphs without a code point (`fShapedGlyph`)

GSUB-substituted glyph IDs are not in the font CMAP. They are kept on the
WinAnsi font in their own sorted list, `fShapedGlyph` (glyph IDs) with
`fShapedWidth` in parallel, beside `fUsedWideChar`/`fUsedWide` (characters).
`GetUsedGlyphs` merges both for `/W` and `/ToUnicode`, listing a shaped glyph
under the value it had before:

```
$E000 or (aGlyph and $0FFF)   → U+E000..U+EFFF, sorted by that value, then by glyph
```

**Until 2026-10-08 that value was the glyph's key in `fUsedWideChar`.** Two
shaped glyphs 4096 apart, or a shaped glyph and a real character of that value,
then shared one slot: the later one overwrote glyph and width of the earlier,
which vanished from `/W`, `/ToUnicode` and the subset keep list, and the
synthetic keys went to hb-subset as code points (`TestShapedGlyphKeys`). The
merge kept the old order (since the CFF series `/W` and `/ToUnicode` are
sorted by code anyway). The subset may still change on POSIX:
hb-subset no longer gets the synthetic keys as code points.

**Still open:** `/ToUnicode` maps these shaped glyphs to the PUA values instead
of their source text. Text extraction / copy-paste is thus incorrect for shaped
Arabic, but rendering is correct. The fix needs the source text per glyph
(shaper clusters) and `/ActualText` where one glyph stands for different text
- a PR of its own

### Safety scope

`GetAndMarkGlyphAsUsed` Step 3 is only reached when:
- (every platform since W3; Windows only before)
- Called from `AddShapedRun` for a run without `Advances` (Uniscribe), or from
  the public `AddGlyphs`
- Uniscribe gives runs only when an item is complex or right-to-left

Latin text: the shaper returns false → the simple path → Step 3 unreachable.
CJK: `UseUniscribe=false` → no shaper call → Step 3 unreachable.
Existing demos and tests: unaffected.
