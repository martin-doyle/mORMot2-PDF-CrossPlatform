# Font Handling — Deep Reference

Sources: `src/pdf/mormot.pdf.pas`,
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

// TrueType — embedded, as a subset by default (§3)
Doc.EmbeddedTTF := True;
C.SetFont('Calibri', 12, []);
```

Standard font name constants (`mormot.pdf.pas`):
- `PDF_FONT_STD_SANS` = `'Helvetica'`
- `PDF_FONT_STD_SERIF` = `'Times'`
- `PDF_FONT_STD_MONO` = `'Courier'`

---

## 2. Platform-Specific Font Selection

```pascal
// For TPdfDocument / TPdfDocumentVcl (mormot.pdf; string out parameters):
GetPdfFonts(EmbeddedTTF, SansFont, SerifFont, MonoFont);

// For TGDIPages (mormot.pdf.report; RawUtf8 out parameters):
Report.ExportPdfEmbeddedTTF := True;
Report.GetExportFonts(SansFont, SerifFont, MonoFont);
// GetReportFonts(Embedded, ...) is the RawUtf8 twin of GetPdfFonts
```

`Embedded = false` gives the Type1 names (`PDF_FONT_STD_*`), `true` the
platform faces (`PDF_FONT_TTF_*`):

| Platform | Sans | Serif | Mono |
|---|---|---|---|
| Windows | Calibri | Cambria | Consolas |
| macOS | Trebuchet MS | Georgia | Andale Mono |
| Android | Roboto | Noto Serif | Droid Sans Mono |
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
| `true` | Complete TTF bytes embedded. Safe for all scripts including RTL/Arabic. For a `.ttc`, the face alone is extracted as a standalone sfnt (`IFontFace.GetFaceFile`) — a raw `ttcf` container is not a valid `/FontFile2`. On every platform. |
| `false` (default), Linux/macOS | Subset via `IFontSubsetter` (`mormot.lib.harfbuzz`, `libharfbuzz-subset`). Glyph IDs retained, so content streams, `/W` and `/ToUnicode` stay valid. Safe for Latin, CJK, shaped RTL and tagged output. |
| `false` (default), Windows | Subset via `CreateFontPackage` with a glyph keep list (`TTFCFP_FLAGS_GLYPHLIST`). Glyph IDs retained, so it is safe for the same cases as hb-subset — Latin, CJK, shaped Arabic (Uniscribe), tagged output. |

The whole face is embedded instead — silently — when no
subsetter is registered (library missing, HarfBuzz < 2.9), for PDF/A-1 (6.3.5
would need a `/CIDSet`, which is not written), for symbol fonts on POSIX
(reached through the `(3,0)` cmap; R-15b). CFF-flavoured faces (`OTTO`)
**are** subset: a CID-keyed one is embedded as its bare
`CFF ` table (`/FontFile3 /Subtype /CIDFontType0C`), a name-keyed one as an
OpenType font file - see "CFF Faces: Type0 Only" below.

**macOS is where this matters.** Its CJK system faces are CFF:
`Hiragino Sans GB.ttc` is `OTTO` in all four faces, with a `CFF ` table and no
`glyf`. Embedded whole, that face makes `chinese_demo` ~10 MB; subset,
~23 KB. To check a face:

```bash
hb-info --face-index=0 <font> | grep outlines    # "Postscript" = CFF
grep -a -oE "/BaseFont[ ]*/[A-Za-z0-9+,#_-]+" out.pdf | sort -u
```

The grep only works on a file without object streams. Tagged output deflates
its font dictionaries, so it returns nothing there — which reads like "no fonts
embedded". Inflate every stream with `python3` and search the result instead.

**The CJK CFF faces are CID-keyed** (read with `PdfFaceCffInfo`,
`TPdfCffTests.SystemFaces`): Hiragino Sans GB is Adobe-GB1 with 288 glyphs
whose CID is not their glyph index; Noto Sans CJK is Adobe-Identity, every
CID its index. hb-subset keeps the ROS, the FDArray and the charset
(`--retain-gids`): a subset of Hiragino Sans GB is Adobe-GB1-6 with 3416
glyphs. The golden case `cjk_subset` draws with Test CJK (Adobe-Identity,
454 of 550 CIDs not their index); `SystemFaceCids` checks Hiragino. The
codes of a `CIDFontType0` are CIDs (ISO 32000-1 9.7.4.2), not glyph
indexes: glyph indexes under Identity-H would draw the wrong glyph for
those 288, hence `GlyphCode` (below). A veraPDF log line
`The Top DICT does not begin with ROS operator` does not make a face
name-keyed: read the face with `PdfFaceCffInfo`.

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

### CFF Faces: Type0 Only

A CID-keyed or an embedded CFF face (`TPdfFontTrueType.Type0Only`, decided
when the WinAnsi font is created: `fInternal`) draws all its text through
its Type0 font. A simple font cannot take a CID-keyed CFF program (9.6.2.1,
table 126). An unembedded
name-keyed face keeps its Latin text in the simple font: without a program
its glyph indexes mean nothing to a viewer, a WinAnsi font it substitutes.
The descendant, `/CIDToGIDMap` and the names follow `GetCff <> pcNone`.
Embedding switched on after such a face was created renames its simple font
`/Type1`; switched off after a name-keyed face was created embedded, the save
raises `EPdfInvalidOperation` (its text is glyph indexes without a program).

**A face without a (3,1) or (3,0) cmap takes the same path:**
a viewer reaches the glyphs of a simple TrueType font through its (3,1) or
(1,0) cmap only (ISO 32000-1 9.6.6.4); macOS Geeza Pro (the first faces of
`GeezaPro.ttc`) has (0,3) alone, so in a simple font even its space would
be `.notdef` (golden case `arabic_system`). `LoadCmap` falls back to the Unicode
platform then and sets `TPdfTtf.NoSimpleCmap`, as does the format 12
reader (§5); an embedded `glyf` face with it is `Type0Only`
(`FaceLacksSimpleCmap`, beside `PdfFaceCffInfo` in the constructor) -
CIDFontType2 in `/FontFile2`, Identity, `/ToUnicode`.
A (1,0) does not count: hb-subset drops it (it keeps (0,3), (0,4), (3,1),
(3,10) and format 14, filtered, and adds none). Not embedded, the simple
font stays, as for a name-keyed CFF face; embedding switched on after the
face was created keeps it too, with its gap - set `EmbeddedTTF` first.
GDI loads no face without a (3,1) or (3,0) cmap - it gives another font -
so `TestUnicodeOnlyCmap` (Test Unicode Only, (0,3) alone) and
`TestFormat12Cmap` (Test Format12, (3,10) format 12 alone) check the path
on Linux and macOS and the replacement on Windows. The CFF suite runs
the format 12 reader on every system and compiler: `Format12CmapFace` serves
Test Format12 through the fake provider, its record also set to (0,3) and
(0,1); `Format12CmapTables` checks the selection, the clipping at U+FFFF
and the rejections on tables built in code.
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
  face only: a glyf face keeps its plain `<...> Tj` - the one space allowed
  inside a Unicode run and the spaces of a symbol font get no adjustment.
  Spaces inside a shaped run and `ShowGlyph` get no adjustment
  (open: HarfBuzz gives clusters, Uniscribe not)
- **q/Q:** `GSave` keeps the page's font, size, word and character
  spacing, scaling and leading (`fTextStateSaved`), `GRestore` puts them
  back as `Q` restores `Tf`, `Tw`, `Tc`, `Tz` and `TL` - a cache kept
  across `Q` would skip a setting and compute the adjustment from a stale
  size. No font is put back (one selected inside q/Q only):
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
  start) `NeedFileFormat` sets `/Version /1.6` in the catalog, which is written last
  (7.5.2, as iText does); rechecked before the program is written, as
  `EmbeddedTTF` may change; PDF/A-1 refuses. The descendant is a
  `CIDFontType0` for every CFF face, read from the face - subset, whole or
  unembedded
- **Names:** `/BaseFont` and `/FontName` are the program's name behind the
  subset tag (tables 117, 122): the CIDFontName of a bare CFF
  (`TPdfCffInfo.FontName`), the PostScript name (name ID 6,
  `SfntPostScriptName`) of an OpenType font file, which may differ from its
  CFF name. A space in a name is `#20` (7.3.5, `ESCAPENAME`)
- **Not conforming, left as before:** a CFF face the reader refuses
  (malformed, CFF2) is embedded as an OpenType font file with glyph-index
  codes. No name-keyed-to-CID-keyed rewriter (cairo and LuaTeX have one)
- **Checked on macOS:** U+9FA6 of Hiragino Sans GB (glyph
  29064, CID 30284) rendered by PDFKit as CoreText draws it, and extracted
  as U+9FA6. The synthetic face of `test_pdf_cff` (`FakeFace`,
  `SwapInFakeFace`: cmap, head, hhea, hmtx, maxp, CFF and name tables built
  in code, swapped into `FontProvider`) runs every path on every platform

Two rules of every Type0 font, not only of CFF faces:
- a run that switches to the fallback face mid-run opens a new hex string
  for the fallback codes (`AddGlyphFlush`, then `<`); the trunk's
  `mormot.ui.pdf.pas` lacks that `<`, at
  [63d06371a, line 5340](https://github.com/synopse/mORMot2/blob/63d06371ad6a75948398ebc1d90cb64af39ca474/src/ui/mormot.ui.pdf.pas#L5340)
- the `/ToUnicode` codespace is `<0000> <FFFF>`, and `/W` and `/ToUnicode`
  are sorted by code, one entry per code: a codespace from the glyph of the
  first character to the glyph of the last is inverted whenever the glyphs
  are out of order

**Every `.ttc` face hinges on `TFreeTypeFont.SfntChecked`.** `GetFontData(0)`
extracts the loaded face once and caches it in `Sfnt`; with `SfntChecked` set
and `Sfnt` empty it hands out FreeType's whole collection instead. The face then
reads as neither CFF nor a single font and hb-subset fails; `GetFaceFile`
refuses a `ttcf` container, so the face cannot be embedded and saving
raises (`RaiseNotEmbeddable`). `CreateFace`
sets the flag `false` explicitly: `New()` initializes managed fields only,
and a flag left to the heap makes this happen at random, by heap layout, on
Linux and macOS. Set every non-managed field of a `New()`ed record.
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
  `Unicodes` holds real code points only, never the synthetic `$E000`
  values of shaped glyphs (§13)

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

The same request as on POSIX, through `FontSubsetter`
(`TFontSubSubsetter`, `mormot.lib.uniscribe`; `platform-backends.md`). A glyph
keep list (`TTFCFP_FLAGS_GLYPHLIST`) rather than code points, so the glyph IDs
stay where they are: the subsetter resolves `Request.Unicodes` to glyph
indices through the font itself (`GetGlyphIndicesW`), which works
whatever cmap the lookup goes through — symbol fonts included, unlike POSIX
(R-15b; `SupportsSymbolic`). A face of a `.ttc` is subset from the whole
collection at the index found from the bytes (`TtcFaceIndex`): a lookup by
family name picks the wrong face in 14 of 30 collections.
`TestSubsetTtcFace` checks four such faces and two of index 0 on the saved
PDF, and `TestWholeTtcFace` the same faces embedded whole (`EmbeddedWholeTtf`,
PDF/A-1, no subsetter); both also cover Noto Sans CJK JP on Linux and
Hiragino Sans GB and Helvetica on macOS (the FreeType side, face 0), and run
wherever one of the fonts is installed - on Windows, or on a Mac with the
Office fonts (face 0 only there: `TFontFileMap` reaches no other, R-11).
`TestSubsetSymbolFont`
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

## 4. TPdfFontTrueType — Dual-Mode Font Object

Every TrueType font exists as **two linked instances**:

| Instance | `fUnicode` | Purpose |
|---|---|---|
| WinAnsi font | `false` | Renders the WinAnsi (cp1252) characters via `(text) Tj`, through `WideCharToWinAnsi`; tracks actually-used chars - of a CFF face: internal, never selected, not written |
| Unicode font | `true` | CID/Identity-H font; renders non-Latin via `<XXXX> Tj` - of a CFF face: all text; loaded with full CMAP at creation |

Navigation:
- `WinAnsiFont` — returns the WinAnsi instance (self or linked peer)
- `UnicodeFont` — `nil` until first non-Latin char (of a CFF face: until
  `SetPdfFont` selects it); created lazily by `CreateAssociatedUnicodeFont`

Two rules of the written dictionaries, both checked by PAC 2024 on tagged
CJK and Arabic output:
- **A WinAnsi peer with no used character** — a glyf face that draws only
  CJK or Arabic: `SetFont` writes `Tf` for it anyway, and a simple TrueType
  font requires `/FirstChar`, `/LastChar` and `/Widths`. Such a peer gets
  `/FirstChar 32 /LastChar 32` and the width of the space. Dropping the peer
  altogether is open (ROADMAP "The Unused WinAnsi Peer Beside a CJK or
  Arabic Font").
- **`/CIDToGIDMap /Identity`** is written for every `CIDFontType2`, not for
  PDF/A only: PDF/UA-1 7.21.3.2 wants it although Identity is the default. A
  `CIDFontType0` (CFF) never has one (table 117 defines it for Type2 only).
`TestTaggedUnicode` (`test_pdf_smoke`) asserts both for glyf faces,
`EmbeddedPrograms` (`test_pdf_cff`) the CFF side.

### Key Fields

| Field | Type | Instance | Purpose |
|---|---|---|---|
| `fUsedWideChar` | `TSortedIntegerArray` | WinAnsi | sorted Unicode code points used during rendering (32-bit keys, for the planes beyond the BMP: R-32); drives the subset request (`AddToSubsetRequest`), `/W` and `/ToUnicode` |
| `fUsedWide` | `TUsedWide` (dyn. array) | WinAnsi | parallel to `fUsedWideChar`: packed `(Width: word; Glyph: word)` per code point |
| `fWinAnsiUsed` | `TSynAnsicharSet` | WinAnsi | 256-bit set of WinAnsi chars used (U+0020–U+00FF); drives `/FirstChar`–`/LastChar /Widths` |
| `fDefaultWidth` | `cardinal` | both (the Unicode one copies it) | advance width of space char; used as PDF `/DW` for unregistered glyphs |
| `fFace` | `IFontFace` | both | the face, shared by both instances (reference counted); `fFace.Handle` is the GDI `HFONT` or the `PFreeTypeFont` |
| `fShapedGlyph`, `fShapedWidth` | `TSortedWordArray`, `TWordDynArray` | WinAnsi | glyphs used without a code point (shaped glyphs out of the cmap) and their widths, §13 |
| `fFixedWidth` | `boolean` | WinAnsi | true = monospace; outside PDF/A `/W` is omitted, all glyphs use `/DW` |
| `fIsSymbolFont` | `boolean` | Unicode | true = `LoadCmap` selected a (3,0) symbol cmap (glyphs at U+F0xx) |

### TUsedWide Packed Record

```pascal
TUsedWide = array of packed record
  case byte of
    0: (Width: word; Glyph: word;);   // access Width and Glyph separately
    1: (Used: integer;);              // copy as single 32-bit: (Width shl 16) or Glyph
end;
```

**Critical invariant:** `length(fUsedWide) >= fUsedWideChar.Count` always.
Both arrays grow together inside `FindOrAddUsedCodePoint` (§8).
The UnicodeFont's arrays are fully populated at construction (entire CMAP);
the WinAnsi font's arrays only contain actually-used code points.

---

## 5. Font Loading — `TPdfTtf.Create`

Called once per Unicode font instance: `TPdfTtf.Create(self).Free`.
Reads its tables from the face through `GetTtfData` (`IFontFace.GetFontData`):

1. **`cmap`** — read by `TPdfTtf.LoadCmap`: the format 4 segment map, or the
   BMP groups of format 12 (`LoadCmap12`); populates
   - `UnicodeFont.fUsedWideChar.Values[]` — one entry per code point in the CMAP
   - `UnicodeFont.fUsedWide[].Glyph` — glyph ID per code point
2. **`head` + `hhea`** — provide `UnitsPerEm` and `numOfLongHorMetrics`
3. **`hmtx`** — Horizontal metrics: sets `UnicodeFont.fUsedWide[].Width` per glyph
   - Formula: `Width = (int64(hmtx_advance) * 1000) div UnitsPerEm`.
     `UnitsPerEm` may be any value from 16 to 16384 (Noto Naskh Arabic:
     1000), so this is a division, never a shift by `log2(UnitsPerEm)`: a
     shift is right for powers of two only, and for a 1000-unit face makes
     every `/W` width 1.953 times too large
   - A fixed-width font gives every code point the advance of glyph 0
   - A glyph at or past `numOfLongHorMetrics` has the advance of the last
     pair, as in `GlyphHmtxWidth`: past the pairs, `hmtx` holds bearings
     only (a monospaced tail) - not the bearing after the last pair, nor
     the advance of `.notdef`. 194 of 641 Windows faces have such a tail
     (Times, Tahoma, SimSun, Yu Gothic, Source Code Pro). `GetTtfData` adds
     a zero word past the table: both readers stop before it
     (`length(fhmtx) - 1`), so a glyph past the end of a `hmtx` shorter than
     `hhea` says gets `W`, the width of `.notdef`, here, and 0 from
     `GlyphHmtxWidth`, whose callers fall back. `ShortHmtxWidths` (Test
     Format12's `hmtx` cut after glyph 66) checks the loop; `GlyphHmtxWidth`'s
     bound has no test: it is reached through a shaper only.

### Subtable selection (cmap)

Preference order, in `TPdfTtf.LoadCmap`:
1. Microsoft platform `(3,1)` Unicode BMP — preferred, `break`s the scan
2. Microsoft platform `(3,0)` symbol — also sets `fIsSymbolFont := true`
3. **Unicode platform `(0,3)` then `(0,4)`** — fallback used only when no
   Microsoft subtable exists at all. Required for Apple fonts: faces 0–4 of
   macOS `GeezaPro.ttc` expose *only* `(0,3)`; without it the CMAP is empty,
   every Arabic glyph `.notdef`, and the text silently falls back to
   `FontFallBackName`.
   It sets `NoSimpleCmap`: embedded, such a face draws through its Type0
   font ("CFF Faces: Type0 Only").
4. **Format 12, `(3,10)`, then `(0,4)`, then the first other `(0,x)`** -
   when none of the above is a format 4 table (`LoadCmap12`; Geneva has it
   under `(0,3)`, Big Caslon under `(0,1)`). On macOS 26, 33 of 788 faces
   have format 12 and no format 4 - Hiragino Kaku Gothic (Hiragino Sans,
   every weight), STHeiti, Geneva, Big Caslon, Apple Symbols, Apple Color
   Emoji; none on Windows (641 faces) or Linux (348). Without this reader
   all their text would come from the fallback font. Read from the raw bytes (`GetFontData`, all fields 32-bit, so
   not through `GetTtfData`'s 16-bit swap) into `TPdfTtf.Groups`, **clipped
   to the BMP**: the engine keys characters by UTF-16 code unit, so a
   character beyond the BMP is unsupported in the plain path for every
   face (ROADMAP "Supplementary-Plane Text"). Groups out of order or
   overlapping, or a glyph beyond 65535, make the cmap unreadable rather
   than guessed. Sets `NoSimpleCmap` unless a (3,0)/(3,1) record exists;
   leaves `Symbol` as `LoadCmap` set it, so a face with a (3,0) of another
   format stays a symbol font. Apple Color Emoji (format 12 under `(0,4)`)
   is read too, and still draws no emoji: its pictures are `sbix` bitmaps,
   its `glyf` outlines empty placeholders except space, `#`, `*` and the
   digits: its WinAnsi text is drawn, ©, ™, ☀ come out empty (PDFKit).
   Color bitmaps are out of reach of a PDF font.

Formats 4 and 12 are parsed; `HasCmap` says whether one was read.

Bounds of format 4 (`Format4CmapBounds`): the directory, the subtable
header and its four arrays (`segCountX2 * 4 + 2` bytes) must lie in the table
- else no cmap is read, as `LoadCmap12` rejects a broken format 12. The bound
is the table's own byte length, `fcmapSize` (`GetTtfData`'s `Size`), which
may be odd: `fcmap` holds one zero word more, and a glyph word half in it is
no glyph. Every read of `glyphIndexArray` goes through `TPdfTtf.GlyphIndex`
(0 before the array or past the table), in `GlyphOf` and in `Create` alike;
a segment with `startCode > endCode` holds no code.

### Odd subtable offsets

`GetTtfData` byte-swaps the table as 16-bit words, so a subtable at an **odd**
byte offset cannot be read directly — every 16-bit field would straddle two
swapped words. `TPdfTtf.LoadCmap` detects this and undoes the swap, then redoes
it from the odd boundary (the same repair `TrueTypeFontName` applies to the
`name` table).

> The test of bit 0 has to run *after* the two 16-bit halves of the 32-bit
> offset are swapped back; before, it tests bit 16. macOS `Hiragino Sans GB`
> has its `(3,1)` subtable at `$A5B`.

After `TPdfTtf.Create`:
- UnicodeFont has **all** code points from the font CMAP with correct PDF-unit widths
- WinAnsi font's tracking arrays (`fUsedWideChar`, `fUsedWide`, `fWinAnsiUsed`) remain empty until text is actually rendered

---

## 6. Text Rendering Chain — WinAnsi (Latin) Path

```
TPdfVclCanvas.TextOut(X, Y, S)              mormot.pdf.canvas
  StringToSynUnicode(S) → W: SynUnicode   (TextOutUtf8: Utf8ToSynUnicode)
  → TPdfCanvas.TextOutW(X, Y, W)
      → TPdfCanvas.ShowText(PW)
          → TPdfWrite.AddUnicodeHexText(PW, StrLenW(PW), NextLine, Canvas)

TPdfWrite.AddUnicodeHexText:
  if UseUniscribe=false or ttf=nil, or the shaper declines (§7):
    → AddUnicodeHexTextNoUniScribe(PW, ttf, NextLine, Canvas)

AddUnicodeHexTextNoUniScribe:
  Ttf := Ttf.WinAnsiFont
  (a symbol font or a Type0Only face: every character takes the glyph
   branch below; so does a WinAnsi character in Ttf.WinAnsiMissing, §8)
  for each WideChar PW^:
    if WideCharToWinAnsi(PW^) > 0:            // a WinAnsi character
      SetPdfFont(Ttf) if not the page font
      Add('(') … Add(') Tj')                   // one string per run
      Ttf.AddUsedWinAnsiChar(ansi)             // marks it in fWinAnsiUsed
    else:                                      // non-Latin char
      AddGlyphFromChar(PW^, Canvas, Ttf)       // §8: registers the code point,
                                               // SetPdfFont(UnicodeFont), '<XXXX'
      (one space between non-Latin characters stays in the glyph string)
      AddGlyphFlush                            // '> Tj'
```

---

## 7. Text Rendering Chain — Uniscribe / HarfBuzz (RTL, Complex Scripts)

One path on every platform; the shaper is `FontShaper`
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
    fsoMissingGlyphs, or fskPlain + fsoFailed, with the fallback on
                           → AddShapedFallback: shaped again in the fallback
                             face (IFontRunShaper), drawn from it if fsoDone
    fskPlain or fsoUnknown → AddUnicodeHexTextNoUniScribe(#0-terminated copy)
    fskShaped              → AddShapedRun(Run, WinAnsiTtf); a missing-glyph
                             run raises under PDF/A
    fskSkip                → nothing

AddShapedRun(Run, WinAnsiTtf):
  SetPdfFont(WinAnsiTtf.UnicodeFont, FontSize)   // CID font, even with no glyph
  no glyph → done (Uniscribe: every glyph was zero-width)
  no Advances (Uniscribe): '<' + GlyphCode(GetAndMarkGlyphAsUsed(g))... + '> Tj'  // §8
  Advances (HarfBuzz): GetAndMarkGlyphAsUsedWithWidth per glyph, then one Tj,
    or a TJ where an offset or the hmtx width differs (§10) - the codes
    GlyphCode(g): the CID of a CID-keyed CFF face
```

**Important:** a shaped run always goes to the Unicode (CID) font of the font
it was shaped with - never to the font left active by the run before it,
which may be the fallback font (`TestShapedAfterFallback`).
The zero-width filter of Uniscribe is in the shaper; the public `AddGlyphs`
keeps its own for callers passing `TScriptVisAttr`s. Details per outcome:
`platform-backends.md`, IFontShaper.

---

## 8. Key Internal Functions

### `FindOrAddUsedCodePoint(aCode)` — WinAnsi font only

Registers a Unicode code point in the WinAnsi font's tracking arrays.
Called from the WinAnsi text rendering path for every non-Latin character,
through `FindOrAddUsedWideChar(aWideChar)`, its public wrapper for a UTF-16
unit. The keys are code points (32-bit); the text paths still pass one
UTF-16 unit at a time - pairing surrogates is open work (R-32).
`FindOrAddUsedCodePoint` stays protected until then: `/ToUnicode` writes a
code point through `AddHex4`, correct up to U+FFFF only.

```
called on the Unicode instance: delegates to WinAnsiFont.FindOrAddUsedCodePoint
fUsedWideChar.Add(aCode)            — sorted insertion into WinAnsi tracking array
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

  i := UnicodeFont.fUsedWideChar.IndexOf(aCode)
  if i < 0 and a symbol font: look up $F000/$F100/$F200 + its WinAnsi byte
                              (the ranges of a (3,0) cmap, ISO 32000-1 9.6.6.4)
  if (i < 0) or (i >= length(UnicodeFont.fUsedWide)):
    i := 0                           — char absent from CMAP → .notdef glyph
  else:
    i := UnicodeFont.fUsedWide[i].Used
  fUsedWide[result].Used := i               — copies Width + Glyph as one int32

returns: index into WinAnsi fUsedWideChar[] / fUsedWide[]
```

### `TPdfWrite.AddGlyphFromChar(Char, Canvas, Ttf, NextLine)`

Entry point for every non-Latin character in the `AddUnicodeHexTextNoUniScribe` path.
`Ttf` is always the WinAnsi font (enforced by its assert and by
`Ttf := Ttf.WinAnsiFont` in `AddUnicodeHexTextNoUniScribe`).

```
assert (Ttf <> nil) and (not Ttf.Unicode)
idx := Ttf.FindOrAddUsedWideChar(Char)    — grows Ttf.fUsedWide if this is a new char
if idx < length(Ttf.fUsedWide) then
  Glyph := Ttf.fUsedWide[idx].Glyph
else
  Glyph := 0
if Glyph = 0 and IsDefaultIgnorable(Char): exit   — a control: nothing to draw

if Glyph = 0 and doc.fUseFontFallBack and doc.fFontFallBackIndex >= 0:
  fnt := Canvas.SetFont('', size, style, -1, fFontFallBackIndex)   — switch to fallback
  idx  := fnt.FindOrAddUsedWideChar(Char)
  if idx < length(fnt.fUsedWide) then
    Glyph := fnt.fUsedWide[idx].Glyph
  else
    Glyph := 0
else:
  fnt := Ttf
  (a switch between main and fallback face flushes the open string first)
if Glyph = 0 and Canvas.fDoc.fPdfA <> pdfaNone: raise EPdfInvalidOperation — PDF/A forbids .notdef

Canvas.SetPdfFont(fnt.UnicodeFont, size)  — switch page font to CID font for output
'<' (or '[<' for a TJ with word spacing, §3) when a new string starts
AddHex4(fnt.GlyphCode(Glyph))             — the code of the face drawing it
                                            (AddGlyphFlush closes the string)
```
`Canvas` is the canvas drawn on, for the fallback font too: a form
XObject's canvas has a page of its own, the document's canvas none before
the first `AddPage` - never choose the fallback font through
`TPdfDocument.Canvas` (`TestFormFallback`).
**A WinAnsi character the face lacks takes this path too:**
`AddUnicodeHexTextNoUniScribe` writes WinAnsi
text as a `(...)` string in the simple font only while
`Ttf.WinAnsiMissing(ansi)` is false. That set is read once per WinAnsi font
from the face's own cmap (`TPdfTtf.CreateCmap` + `GlyphOf`, the reader of
`TPdfTtf.Create` on its own), never through the Unicode instance, which
would add a font object to every document. It applies only where a missing
character has a way out - `UseFontFallBack` with a fallback face, or PDF/A
(which raises) - and not to symbol fonts or an unreadable cmap; elsewhere
the simple font draws it. `ShowText(PdfString)` sends such a text
the Unicode way (`WinAnsiTextMissing`), and `GetWideCharWidth` gives 0 for
it, so `UnicodeTextWidth` measures it in the fallback face. PDF/A raises for
every glyph left 0 - fallback off, none registered, or the fallback face
lacking it too (ISO 19005-2 6.2.11.8).

### `GetAndMarkGlyphAsUsed(aGlyph)` — `TPdfFontTrueType`

Called on the WinAnsi font by `AddShapedRun` for every glyph of a run
without advances (Uniscribe) and by `AddGlyphs` (`ShowGlyph`); a HarfBuzz
run takes `GetAndMarkGlyphAsUsedWithWidth` (§10).
Maps shaped (GSUB-substituted) glyph IDs back to tracked entries via reverse CMAP.

```
Step 1: scan WinAnsiFont.fUsedWide[0..Count-1].Glyph == aGlyph,
        then WinAnsiFont.fShapedGlyph
          → found: already registered, return aGlyph unchanged (fast path)

Step 2: scan UnicodeFont.fUsedWide[0..Count-1].Glyph == aGlyph  (reverse CMAP)
          → found: WinAnsiFont.FindOrAddUsedCodePoint(UnicodeFont.fUsedWideChar.Values[i])
                   return WinAnsiFont.fUsedWide[idx].Glyph
                   (the index is one of the WinAnsi instance's fUsedWide[], not of
                    the Unicode one's CMAP array - both instances have the method)
          → not found: fall through to Step 3

Step 3: GSUB-substituted glyph — not in CMAP at all (rare ligature, etc.),
  on every platform:
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

**Width unit compatibility:** on Windows `GetGlyphAdvance` returns logical units (GDI's `GetCharABCWidthsI`). `TPdfCanvas.SetFont` requests every face with `Height = -1000`, so the em square is 1000 logical units, making these widths directly compatible with `fUsedWide[].Width` (also 1000/em from hmtx). No unit conversion needed (§13).

---

## 9. Font Serialization — `TPdfFontTrueType.PrepareForSaving`

Called on `Doc.SaveToFile` / `Doc.SaveToStream` for every font in `fFontList`,
after `PrepareFontSubsets` (§3). Runs for **both** WinAnsi and Unicode instances.

### Unicode font branch: builds CID font dictionary

```
/DW  = WinAnsiFont.fDefaultWidth               (space char width, e.g. 167 for Tahoma)

PdfUsedCodes(WinAnsiFont)   GetUsedGlyphs: characters (fUsedWide[]) and
                            glyphs without a code point (fShapedGlyph),
                            merged in key order (§8); each glyph's code
                            GlyphCode() (the CID of a CID-keyed CFF face),
                            sorted by code, one entry per code - the
                            smallest code point wins (packed as GlyphCode
                            shl 37 + code point shl 16 + width: 16 + 21 +
                            16 bits)
/W array construction:
  if WinAnsiFont.fFixedWidth and not PDF/A:
    omit /W entirely (all glyphs use /DW)
  else:
    c [w1 w2 ...] per run of consecutive codes

ToUnicode CMap codespace = <0000> <FFFF>, bfchar sorted by code (§3)
```

### WinAnsi font branch: builds /Widths array, embeds font file

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
          the face it loaded, GDI the face TtcFaceIndex finds
    the stream is shared: TPdfDocument.GetOrCreateFontFile2() reuses one
    TPdfStream for byte-identical data, so Regular and Bold resolving to the
    same physical file embed it once, not twice

  if EmbeddedWholeTtf = false (the default):
    Linux/macOS: the subset prepared by PrepareFontSubsets replaces the bytes
      (see §3 "POSIX subset input"); the name gets its ABCDEF+ tag
    Windows: the same, the subset made by FontSub (TFontSubSubsetter,
      CreateFontPackage) in PrepareFontSubsets; FontSub.dll absent
      or NO_USE_UNISCRIBE → no FontSubsetter → the whole face
```

---

## 10. RTL / Arabic — Behavior and Known Limitations

### `lfCharSet` on Windows

`TPdfVclCanvas.SyncFont` passes `Font.Charset` (LCL default: `DEFAULT_CHARSET (1)`) to
`TPdfCanvas.SetFont`. A direct `SetFont` with `ACharSet < 0` takes `fDoc.CharSet`
instead - on Western Windows (codepage 1252) `ANSI_CHARSET (0)`.

**What the charset decides on Windows:** which face GDI's font mapper selects.
With `ANSI_CHARSET` it prefers an installed font that has that code page over
a registered one that lacks it, and silently substitutes it: `SetFont`
succeeds and draws with the other face (`platform-backends.md`, "Registered
Fonts"; `call-graph.md` 4a). It does not filter the cmap: `GetFontData`
returns the whole `cmap` table of the selected face,
and `TPdfTtf.LoadCmap` picks the subtable from the table itself - (3,1), else
(3,0), a symbol face, else (0,3)/(0,4). `SYMBOL_CHARSET (2)` also sets
`PDF_FONT_SYMBOLIC` in the font's `/Flags` (the `TPdfFontTrueType`
constructor), which `IsSymbolic` reads (§3). Pass `DEFAULT_CHARSET` when
calling `SetFont` directly with a non-Latin face.

On Unix/macOS: `fCodePage = CP_UTF8 → fCharSet = ANSI_CHARSET (0)`
(`CodePageToCharSet`) — safe regardless.

### Arabic rendering

**Setting the flag: never behind `{$ifdef USE_UNISCRIBE}`.** That symbol is
defined in `mormot.pdf.defines.inc`, which only `mormot.pdf` and `mormot.pdf.canvas`
include: it does not reach the units that use them, so a
guarded `Doc.UseUniscribe := true` compiles to nothing and the shaper never
runs — Section 2 of `rtl_demo` then produces output byte-identical to its
no-shaper Section 1. The property is declared
unconditionally for that reason, and it is the shaping switch
on Linux/macOS too (HarfBuzz; `RightToLeftText` is the base direction only —
`platform-backends.md`, Registration). `TestUseUniscribeIsPortable` fails to
compile if it is ever gated again; `TestShapingSwitch` checks the output.

`UseUniscribe=true` (Windows, complex scripts):
- Uniscribe shapes Arabic contextual forms via `ScriptShape` → GSUB glyph IDs
- `GetAndMarkGlyphAsUsed` registers shaped glyph IDs via reverse CMAP scan (Step 2)
- Fonts like Tahoma: shaped glyphs found in Arabic Presentation Forms (U+FE70–U+FEFF)
- For fonts without Presentation-Form coverage: Step 3 (`GetGlyphAdvance` + `fShapedGlyph`) handles remaining GSUB-only glyphs

### Step 3 on Linux/macOS — HarfBuzz Advances

`GetAndMarkGlyphAsUsed` Step 3 uses `IFontFace.GetGlyphAdvance` on every
platform. A HarfBuzz run brings its own advances, so Linux/macOS use
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
  pen still moves by the shaper's advance. Writing `aWidth` into `/W` makes
  both wrong at once and cancels out on screen — invisible in a viewer, a
  PDF/UA failure. For a cursive-attachment glyph (a medial Arabic form)
  HarfBuzz even gives `x_advance = 0`: in `/W`, that width stacks the glyphs
  on one spot.
- Same registration as Step 3: `AddShapedGlyph` into `fShapedGlyph`
- Result: GSUB-only shaped glyphs get correct `/W` entries; no `/DW` overlap

**Whether Step 3 is reached at all depends on the font's CMAP**, and this is the
single most important thing to know about RTL here:

| Font | Presentation forms U+FE70–FEFF in CMAP? | Path taken | Width source |
|---|---|---|---|
| Noto Naskh Arabic (Linux) | yes | Step 2 | `hmtx`, via the CMAP |
| Geeza Pro (macOS) | **no** | Step 3 | `hmtx` by glyph index (`GlyphHmtxWidth`); the shaper's positioned advance goes into `TJ` |
| mORMot Test Arabic (`tests/fonts`, every platform) | **no** | Step 3 | the same; Windows: `GetGlyphAdvance` |

So with Noto Naskh Arabic the width in `/W` comes from `hmtx` through the
CMAP, while `AddShapedRun` still positions the glyphs with the HarfBuzz
advances — the Step 3 path never runs, and a bug in it stays invisible on Linux while
it breaks Geeza Pro on macOS. Validate RTL changes against a font
**without** Arabic presentation forms: the tests use Test Arabic, which
reaches Step 3 everywhere. Check the `ToUnicode` CMap to tell which path ran: real
U+06xx code points mean Step 2, PUA U+E0xx values mean Step 3.

### HarfBuzz scaling — do NOT use FT_LOAD_NO_SCALE

`hb_ft_font_create` copies its scale out of `ft_face^.size^.metrics`, so the
FT_Face **must be sized first** — `FreeTypeSetEmSize1000()` in the FreeType backend
does this (1000 units per em at 72 dpi). `CreateFace` deliberately does not size
the face, because every other entry point uses `FT_LOAD_NO_SCALE` or reads
design-unit fields.

HarfBuzz (~2.6.5 and later) has no "`FT_LOAD_NO_SCALE` returns raw design
units" behaviour: it always multiplies the advance by a factor derived from
the font scale. With an unsized face that factor is 0, so **every advance comes
back as 0** and all shaped glyphs stack on one spot. HarfBuzz
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

### Arabic on Linux/macOS — Status

HarfBuzz shaping is implemented; Arabic renders with correct ligatures and
cursive joining on Linux and macOS. `TestTextShaperAdvances` pins down the
shaper's own advances. In a font with Arabic presentation forms only the
glyphs its cmap does not reach take Step 3, the width registration of
GSUB-only glyphs by glyph index (above); the positioning by the advances
runs either way.

### GPOS Offsets

- `IFontShaper.Shape` returns the offset per glyph in `Runs[0].Offsets`
  (`TFontShapedRun`, `mormot.lib.core`)
- the HarfBuzz shaper fills `Offsets[i] = From26Dot6(positions[i].x_offset)`
- `AddShapedRun` writes a `TJ` when an offset is not 0, or a glyph's `/W`
  width differs from the shaper's advance

With Noto Naskh Arabic every `x_offset` is 0, so the `Tj` path is taken where
each glyph's `/W` width also equals the shaper's advance, and `TJ` where it
does not; fonts with GPOS positioning take the `TJ` path.
Vertical offsets (`y_offset`) are not written: ROADMAP "Shaped Text: Real
`/ToUnicode` and Vertical Offsets".

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
contain Latin glyphs. In mixed Latin+CJK strings rendered with a CJK font, the Latin
comes from the fallback font on the plain path (§8, `AddGlyphFromChar`), and in shaped
text (`UseUniscribe`) the part the font lacks is shaped again in the fallback face
(platform-backends skill, "The one caller").

---

## 10b. RTL Paragraph — `VisualToLogical` Loop in `TUniscribeShaper.Shape`

`RightToLeftText := true` sets `uBidiLevel := 1` before `ScriptItemize`.

The shaper itemizes exactly the text (`Len` code units) and takes every
item `ScriptLayout` orders: `for j := 0 to count - 1 do i :=
VisualToLogical[j]`. The level `ScriptLayout` gets is `uBidiLevel and $1f`:
the byte holds state bits above the five level bits (an override control
sets one), which would reorder the runs. Do not itemize the `#0` after the
text and skip the last item as a sentinel: the RTL level places that item
at visual position 0, and it may hold real text before the `#0`.

---

## 11. `lfCharSet` Derivation Chain

How `lfCharSet` is determined when rendering via `TPdfVclCanvas`:

```
LCL TFont.Charset                        (graphics.pp)
  default = DEFAULT_CHARSET (1)

TPdfVclCanvas.SyncFont                   (mormot.pdf.canvas)
  fPdfCanvas.SetFont(Font.Name, Abs(Font.Size), style, Font.Charset)
  ← Font.Charset passed explicitly → DEFAULT_CHARSET (1) by default
  ← user sets Font.Charset := SYMBOL_CHARSET (2) for symbol fonts

TPdfCanvas.SetFont(name, size, style, ACharSet)
  if ACharSet < 0: ACharSet := fDoc.CharSet       ← fallback (direct calls only)
  lf.CharSet := ACharSet; lf.Height := -1000       (lf: TFontRequest)
  TPdfFontTrueType.Create(fDoc, ..., lf, nil)
    → FontProvider.CreateFace(lf)
        Windows: TGdiFontProvider.CreateFace → lfCharSet, CreateFontIndirectW
                 → HFONT with lfCharSet
  TPdfTtf.Create → GetTtfData → fFace.GetFontData('cmap', ...)
                 ← the whole cmap of the face GDI selected (§10)

On Unix/macOS: no HFONT; FreeType reads CMAP directly from the TTF file.
```

**Symbol fonts:** the symbol subtable (3,0) is chosen by `LoadCmap` from the
table when the face has no (3,1), whatever the charset. `SYMBOL_CHARSET (2)` makes the font symbolic in
its `/Flags` (§10). Set `Font.Charset := SYMBOL_CHARSET` before rendering;
`SyncFont` passes it through unchanged.

---

## 12. Platform Backend Summary

For full interface documentation see `.claude/skills/platform-backends.md`.

| Backend | Font handle | Key font APIs used |
|---|---|---|
| Windows GDI | `HFONT` (via `CreateFontIndirectW`) | `GetCharABCWidthsA`, `GetCharABCWidthsI`, `GetFontData` |
| FreeType2 (Unix/macOS) | `FT_Face` (via `FT_New_Face`, `FT_New_Memory_Face` for registered font data) | `FT_Load_Char`, `FT_Load_Glyph`, `FT_Load_Sfnt_Table` |

`GetFontData` / `FT_Load_Sfnt_Table` are used by `TPdfTtf.Create` (through `GetTtfData`) to read raw TTF table bytes
(`cmap`, `hmtx`, `head`, `hhea`) for CMAP loading and glyph width extraction.

The platform layer is reached via the global `FontProvider: IFontProvider` interface.
Registration happens in the `initialization` section of the backend unit.

---

## 12a. FreeType Backend — Table Tag Byte-Order

Table tags are formed in `GetTtfData` (`mormot.pdf`) as `PCardinal(aTableName)^`:
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

## 13. GSUB Glyph Width — Implementation Notes (`GetAndMarkGlyphAsUsed`)

Relevant for `GetAndMarkGlyphAsUsed` Step 3: a run without advances
(Uniscribe) or the public `AddGlyphs`.

### `GetCharABCWidthsI` — API details

Behind `IFontFace.GetGlyphAdvance` (`TGdiFontFace`, `mormot.lib.uniscribe`),
which returns `abcA + abcB + abcC` of one glyph.
Not in FPC's standard `windows` unit (commented out in `redef.inc`), so it is
declared there by hand:

```pascal
// 5 parameters — pgi=nil means consecutive glyphs starting at giFirst
function GetCharABCWidthsI(DC: HDC; giFirst, cgi: cardinal; pgi: PWord;
  lpabc: PABC): BOOL; stdcall; external 'gdi32.dll' name 'GetCharABCWidthsI';
```

FPC type: use `TABC` (not `ABC`) in `var` blocks — `TABC = ABC` is the FPC alias. `LPABC = ^ABC`.

### Width unit compatibility

`lfHeight = -1000` (`TPdfCanvas.SetFont`, `Height` of the `TFontRequest`) → DC em square = 1000 logical units.
`GetCharABCWidthsI` returns widths in those same 1000-per-em logical units.
`fUsedWide[].Width` (from `hmtx` via `TPdfTtf.Create`) is also 1000-per-em.
→ No unit conversion needed; values are directly comparable.

### Glyphs without a code point (`fShapedGlyph`)

GSUB-substituted glyph IDs are not in the font CMAP. They are kept on the
WinAnsi font in their own sorted list, `fShapedGlyph` (glyph IDs) with
`fShapedWidth` in parallel, beside `fUsedWideChar`/`fUsedWide` (characters).
`GetUsedGlyphs` merges both for `/W` and `/ToUnicode`, listing a shaped glyph
under a synthetic value:

```
$E000 or (aGlyph and $0FFF)   → U+E000..U+EFFF, sorted by that value, then by glyph
```

**The value is never a key of `fUsedWideChar`:** there, two shaped glyphs
4096 apart, or a shaped glyph and a real character of that value, would share
one slot - the later one overwriting glyph and width of the earlier, which
would vanish from `/W`, `/ToUnicode` and the subset keep list - and the
synthetic values would reach hb-subset as code points (`TestShapedGlyphKeys`).
`/W` and `/ToUnicode` are sorted by code (§9).

**Still open:** `/ToUnicode` maps these shaped glyphs to the PUA values instead
of their source text, and the characters of a shaped run also stay in `/W`,
`/ToUnicode` and the subset under their cmap glyphs, which are never drawn
(measured with `mORMot Test Arabic`: the isolated forms of 'marhaba' listed
beside the drawn joined forms). Text extraction / copy-paste is thus incorrect for shaped
Arabic, but rendering is correct. The fix needs the source text per glyph
(shaper clusters) and `/ActualText` where one glyph stands for different text:
ROADMAP "Shaped Text: Real `/ToUnicode` and Vertical Offsets".

### Safety scope

`GetAndMarkGlyphAsUsed` Step 3 is only reached, on every platform, when:
- Called from `AddShapedRun` for a run without `Advances` (Uniscribe), or from
  the public `AddGlyphs`
- Uniscribe gives runs only when an item is complex or right-to-left

Latin text: the shaper returns false → the simple path → Step 3 unreachable.
CJK: `UseUniscribe=false` → no shaper call → Step 3 unreachable.
Existing demos and tests: unaffected.
