# Font Handling — Deep Reference

Sources: `src/core/mormot.ui.pdf.pas`, `src/core/mormot.pdf.types.pas`,
`src/platform/windows/mormot.pdf.gdi.pas`, `src/platform/unix/mormot.pdf.freetype.pas`

**Skill boundaries:**
- User-facing font mode selection → brief overview here; see also `.claude/skills/pdf-engine.md` §"Font Strategy"
- Platform interface (IPdfPlatformFont, etc.) → see `.claude/skills/platform-backends.md`
- Call graph of font paths → see `.claude/skills/call-graph.md` Path 4a–4f

---

## 1. Two Embedding Modes — Do Not Mix

| Mode | Properties | Font names | Embedding |
|---|---|---|---|
| Standard Type1 | `StandardFontsReplace := True` | Helvetica, Times, Courier | none |
| TrueType | `EmbeddedTTF := True` | OS-specific (see §2) | full TTF (default) or subset (opt-in, §3) |

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

Fonts excluded from embedding: `TPdfDocument.EmbeddedTtfIgnore` (`TRawUtf8List`).
Fallback when a requested font is not found: `TPdfDocument.FontFallBackName` (string).

---

## 3. Font Embedding — Whole TTF vs. Subset

Controlled by `TPdfDocument.EmbeddedWholeTtf` (boolean, **default `false`** — the
constructor leaves it unset). Two things override that default:

- `Tagged := true` sets it to `true` (PDF/UA needs the complete face, see `pdf-engine.md`)
- on POSIX it has no effect at all: the subsetting branch in `PrepareForSaving`
  sits inside `{$ifdef USE_UNISCRIBE}`, so Linux/macOS always embed the whole
  face. The flag is a Windows-only switch.

| `EmbeddedWholeTtf` | Behaviour |
|---|---|
| `true` | Complete TTF bytes embedded. Safe for all scripts including RTL/Arabic. For a `.ttc`, the loaded face alone is extracted as a standalone sfnt — a raw `ttcf` container is not a valid `/FontFile2`. |
| `false` (default) | Font subset via `CreateFontPackage` (Windows only — POSIX ignores this and embeds the whole face). Smaller file, but risky for RTL/Arabic with Uniscribe shaping. |

```pascal
Doc.EmbeddedWholeTtf := False;  // opt-in to subsetting; only safe for Latin text
```

The subset input is built from:
- `fWinAnsiUsed` — 256-bit set of used WinAnsi code points
- `fUsedWideChar` — sorted array of used Unicode code points beyond WinAnsi

If both are empty (can happen with GSUB-shaped Arabic), the subset degenerates to unusable.

---

## 4. TPdfFontTrueType — Dual-Mode Font Object (`pdf.pas:2611`)

Every TrueType font exists as **two linked instances**:

| Instance | `fUnicode` | Purpose |
|---|---|---|
| WinAnsi font | `false` | Renders U+0000–U+00FF via `(text) Tj`; tracks actually-used chars |
| Unicode font | `true` | CID/Identity-H font; renders non-Latin via `<XXXX> Tj`; loaded with full CMAP at creation |

Navigation:
- `WinAnsiFont` — returns the WinAnsi instance (self or linked peer)
- `UnicodeFont` — `nil` until first non-Latin char; created lazily by `CreateAssociatedUnicodeFont`

### Key Fields (`pdf.pas:2611`)

| Field | Type | Instance | Purpose |
|---|---|---|---|
| `fUsedWideChar` | `TSortedWordArray` | WinAnsi | sorted Unicode code points used during rendering; drives `CreateFontPackage` and `/W` array |
| `fUsedWide` | `TUsedWide` (dyn. array) | WinAnsi | parallel to `fUsedWideChar`: packed `(Width: word; Glyph: word)` per code point |
| `fWinAnsiUsed` | `TSynAnsicharSet` | WinAnsi | 256-bit set of WinAnsi chars used (U+0020–U+00FF); drives `/FirstChar`–`/LastChar /Widths` |
| `fDefaultWidth` | `cardinal` | WinAnsi | advance width of space char; used as PDF `/DW` for unregistered glyphs |
| `fHGDI` | `TPdfPlatformFontHandle` | both | platform font handle (GDI `HFONT` or FreeType `FT_Face`) |
| `fFixedWidth` | `boolean` | WinAnsi | true = monospace; `/W` is omitted, all glyphs use `/DW` |
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
Uses `GetDCWithFont` to select the font into the DC.
Reads three TTF tables via `PdfPlatformFont.GetFontData`:

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
  UTF8Decode(S) → W: WideString
  → TPdfCanvas.TextOutW(X, Y, W)            pdf.pas:8992
      → TPdfWrite.ShowText(PW)              pdf.pas:9463
          → TPdfWrite.AddUnicodeHexText(PW, Len, false, Canvas)   pdf.pas:5549

TPdfWrite.AddUnicodeHexText:
  if UseUniscribe=false or ttf=nil:
    → AddUnicodeHexTextNoUniScribe(PW, ttf, false, Canvas)

AddUnicodeHexTextNoUniScribe (pdf.pas:5484):
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

## 7. Text Rendering Chain — Uniscribe / HarfBuzz (RTL, Complex Scripts) (`pdf.pas:5295–5570`)

```
TPdfWrite.AddUnicodeHexText (pdf.pas:5549):
  if UseUniscribe and ttf <> nil:
    {$ifdef USE_UNISCRIBE}                       // Windows only
    shaped := AddUnicodeHexTextUniScribe(PW, Len, ttf.WinAnsiFont, NextLine, Canvas)
    {$endif}
    if not shaped and PdfTextShaper <> nil:      // Linux/macOS HarfBuzz
      shaped := AddUnicodeHexTextHarfBuzz(...)
  if not shaped:
    AddUnicodeHexTextNoUniScribe(...)            // Latin fallback

AddUnicodeHexTextUniScribe (pdf.pas:5295):
  ScriptItemize(PW, Len) → items[]              // split into script runs
  for each item in visual (bidi-reordered) order:
    ScriptShape(DC, W, L, …, OutGlyphs, glyphsCount)  // OpenType GSUB shaping
    → AddGlyphs(OutGlyphs, glyphsCount, Canvas, VisAttr)

AddGlyphs (pdf.pas:5573):
  SetPdfFont(ttf.UnicodeFont, FontSize)          // always use CID font for shaped text
  for each shapedGlyph in OutGlyphs:
    glyph := ttf.WinAnsiFont.GetAndMarkGlyphAsUsed(shapedGlyph)  // §8
    AddHex4(glyph)     // accumulate '<XXXX XXXX …>'
  Add('> Tj')
```

**Important:** `AddGlyphs` switches to `UnicodeFont` (CID font) unconditionally for all shaped output, including runs where `UseUniscribe=false` would have used the WinAnsi font.

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
  {$ifdef OSWINDOWS} only:
          GetDCWithFont(self)                              select font into DC
          GetCharABCWidthsI(fDoc.fDC, aGlyph, 1, nil, @abc)  ← by glyph index
          w := abc.abcA + integer(abc.abcB) + abc.abcC    ← advance in 1000/em units
          synChar := WideChar($E000 or (aGlyph and $0FFF)) ← PUA synthetic Unicode slot
          idx := FindOrAddUsedWideChar(synChar)
          fUsedWide[idx].Glyph := aGlyph                  ← override glyph
          fUsedWide[idx].Width := w                        ← set correct advance width
  → glyph now registered in /W array; no more overlap from /DW fallback
  {POSIX}: step 3 not implemented; glyphs still use /DW (overlap remains)
```

**Arabic Presentation Forms in CMAP:** Fonts like Tahoma map U+FE70–U+FEFF (Arabic
Presentation Forms-B) to the same glyph IDs that Uniscribe produces for shaped contextual
forms. Step 2 therefore finds most Arabic shaped glyphs. Step 3
remains the backstop for fonts whose GSUB glyphs have no Presentation-Form Unicode slot.

**Width unit compatibility:** `GetCharABCWidthsI` returns logical units. Because `lfHeight = -1000` (pdf.pas:8854), the DC em square = 1000 logical units, making these widths directly compatible with `fUsedWide[].Width` (also 1000/em from hmtx). No unit conversion needed.

---

## 9. Font Serialization — `PrepareForSaving` (`pdf.pas:6568`)

Called on `Doc.SaveToFile` / `Doc.SaveToStream` for every font in `fFontList`.
Runs for **both** WinAnsi and Unicode instances.

### Unicode font branch (`pdf.pas:6594`): builds CID font dictionary

```
/DW  = WinAnsiFont.fDefaultWidth               (space char width, e.g. 167 for Tahoma)

/W array construction:
  if WinAnsiFont.fFixedWidth:
    omit /W entirely (all glyphs use /DW)
  else:
    for i in 0..WinAnsiFont.fUsedWideChar.Count-1:
      emit [WinAnsiFont.fUsedWide[i].Glyph, [WinAnsiFont.fUsedWide[i].Width]]

fFirstChar / fLastChar = min/max .Glyph in WinAnsiFont.fUsedWide[]
ToUnicode CMap codespace = <fFirstChar> <fLastChar>

if WinAnsiFont.fUsedWideChar.Count = 0:
  /W = []
  codespace = <0000> <0000>
  (but: if fGlyphMin/fGlyphMax set by GetAndMarkGlyphAsUsed Step 3,
         use those as codespace — partial mitigation for shaped Arabic)
```

### WinAnsi font branch (`pdf.pas:6671`): builds /Widths array, embeds font file

```
/FirstChar, /LastChar, /Widths built from fWinAnsiUsed + WinAnsi ABC widths

Font embedding decision:
  if EmbeddedWholeTtf = true (default):
    PdfPlatformFont.GetFontData(DC, 0, 0, nil, 0)   → total byte count
    PdfPlatformFont.GetFontData(DC, 0, 0, Buf, Size) → full TTF bytes → embed as /FontFile2
    safe for all scripts; shaped GSUB glyph IDs are valid in the complete font
    .ttc: the FreeType backend returns just the loaded face, rebuilt as an sfnt
          (ExtractSfntFromTtc); Windows does the same via CreateFontPackage
    the stream is shared: TPdfDocument.GetOrCreateFontFile2() reuses one
    TPdfStream for byte-identical data, so Regular and Bold resolving to the
    same physical file embed it once, not twice

  if EmbeddedWholeTtf = false (the default):
    Windows only - the whole branch sits inside {$ifdef USE_UNISCRIBE}, which
    mormot.ui.pdf.pas undefines for OSPOSIX, so Linux/macOS never reach it and
    always embed the complete face. There is no POSIX subsetter; the flag is a
    no-op there.
      input: Unicode code points from fWinAnsiUsed + fUsedWideChar
      CreateFontPackage(input) → subset TTF bytes (FontSub.dll, resolved via
        HasCreateFontPackage; falls back to the whole face if absent)
      if fUsedWideChar.Count = 0 and fGlyphMin/fGlyphMax = 0:
        0 code points passed → degenerate/unusable subset → boxes in output
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

`UseUniscribe=true` (Windows, complex scripts):
- Uniscribe shapes Arabic contextual forms via `ScriptShape` → GSUB glyph IDs
- `GetAndMarkGlyphAsUsed` registers shaped glyph IDs via reverse CMAP scan (Step 2)
- Fonts like Tahoma: shaped glyphs found in Arabic Presentation Forms (U+FE70–U+FEFF)
- For fonts without Presentation-Form coverage: Step 3 (`GetCharABCWidthsI` + PUA slot) handles remaining GSUB-only glyphs (Windows only)

### Step 3 on Linux/macOS — HarfBuzz path (P2-A, APPLIED)

`GetAndMarkGlyphAsUsed` Step 3 uses `GetCharABCWidthsI` (GDI API, Windows only).
On Linux/macOS the equivalent is `GetAndMarkGlyphAsUsedWithWidth(aGlyph, aWidth)`:
- Called from `AddUnicodeHexTextHarfBuzz` instead of `GetAndMarkGlyphAsUsed`
- `aWidth` comes from HarfBuzz `positions[i].x_advance`
- Same PUA slot logic as Step 3: `synChar := WideChar($E000 or (aGlyph and $0FFF))`
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
FT_Face **must be sized first** — `PdfFTSetEmSize1000()` in the FreeType backend
does this (1000 units per em at 72 dpi). `CreateFont` deliberately does not size
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

`ShapeText` therefore sizes the face, sets `FT_LOAD_NO_HINTING`, and converts
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

### P3-B — Implementiert (aktuell wirkungslos für Noto Naskh Arabic)

P3-B ist implementiert:
- `IPdfTextShaper.ShapeText` hat `out AOffsets: TIntegerDynArray` (`mormot.pdf.types.pas`)
- `ShapeText` fills `AOffsets[i] = From26Dot6(positions[i].x_offset)` (`harfbuzz.pas`)
- `AddUnicodeHexTextHarfBuzz` verwendet `TJ`-Operator wenn ein Offset ≠ 0

Für Noto Naskh Arabic sind alle `x_offset = 0` → `hasOffsets` immer false → `Tj`-Pfad immer aktiv.
P3-B kann bei anderen Fonts mit GPOS-Kerning relevant werden.

---

## 10b. RTL Paragraph — `VisualToLogical` Loop in `AddUnicodeHexTextUniScribe`

`RightToLeftText := true` sets `AScriptState.uBidiLevel := 1` before `ScriptItemize`.

`ScriptLayout` with uniform RTL level places the sentinel (logical index `count-1`) at
visual position 0: `VisualToLogical = [count-1, 0, 1, …]`.

Current loop (`pdf.pas:~5420`):
```pascal
for j := 0 to count - 1 do
  if VisualToLogical[j] < count - 1 then   // sentinel always has logical index count-1
    Append(VisualToLogical[j]);
```

The guard skips the sentinel by logical index regardless of its visual position.

| Scenario | VisualToLogical | Loop result |
|---|---|---|
| LTR, uBidiLevel=0, count=2 | [0, 1] | Append(0); skip sentinel |
| RTL, uBidiLevel=1, count=2 | [1, 0] | skip sentinel; Append(0) |
| Mixed, count=3 | [1, 0, 2] | Append(1); Append(0); skip sentinel |

---

## 10a. CJK (Chinese / Japanese / Korean)

| Property | CJK | Arabic |
|---|---|---|
| Shaping needed | No — `UseUniscribe=false` sufficient | Yes — Uniscribe/HarfBuzz for contextual forms |
| CMAP coverage | Format-4 BMP subtable covers all CJK Unified Ideographs (U+4E00–U+9FFF) | Arabic Presentation Forms (U+FE70–U+FEFF) |

With `UseUniscribe=false`, each CJK code point is looked up directly in the CMAP
(`UnicodeFont.fUsedWideChar.IndexOf`), glyph ID written as `<XXXX> Tj`.
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

The platform layer is reached via the global `PdfPlatformFont: IPdfPlatformFont` interface.
Registration happens in the `initialization` section of the backend unit.

---

## 12a. FreeType Backend — Table Tag Byte-Order

Table tags are formed in `GetTtfData` (`pdf.pas:3610`) as `PCardinal(aTableName)^`:
a 4-char ASCII name read as a little-endian DWORD on LE machines.

FreeType's `FT_Load_Sfnt_Table` uses the `FT_MAKE_TAG` big-endian convention.
`TPdfFreeTypeFontProvider.GetFontData` applies `SwapEndian(ATableTag)` before calling
`FT_Load_Sfnt_Table`. `SwapEndian(0)` = 0, preserving the tag=0 convention
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

Relevant for `GetAndMarkGlyphAsUsed` Step 3 when `UseUniscribe=true` on Windows.

### `GetCharABCWidthsI` — API details

Not in FPC's standard `windows` unit (commented out in `redef.inc`). Must be declared manually in `{$ifdef OSWINDOWS}` block at the start of `implementation`:

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

### Synthetic PUA entry approach

GSUB-substituted glyph IDs are not in the font CMAP. To give them a slot in the parallel arrays `fUsedWideChar`/`fUsedWide`, a synthetic Unicode code point in the Private Use Area is used:

```
synChar = WideChar($E000 or (aGlyph and $0FFF))   → U+E000..U+EFFF range
```

`FindOrAddUsedWideChar(synChar)` adds the PUA code point to `fUsedWideChar` (not in CMAP → i=0 default). After the call, `fUsedWide[idx].Glyph` and `.Width` are overridden with the correct values.

**Side effect:** The `ToUnicode` CMap in the PDF maps these shaped glyphs to PUA code points instead of their base Arabic characters. Text extraction / copy-paste is thus incorrect for shaped Arabic, but rendering is correct.

### Safety scope

`GetAndMarkGlyphAsUsed` Step 3 is only reached when:
- `{$ifdef OSWINDOWS}` — Windows only
- Called from `AddGlyphs` — only reached when Uniscribe is active
- `AddGlyphs` is only called from `AddUnicodeHexTextUniScribe`
- Which is gated by: `complex=true or R2L=true` (ScriptItemize flag check)

Latin text: `complex=false`, `R2L=false` → never reaches `AddGlyphs` → Step 3 unreachable.
CJK: `UseUniscribe=false` → `AddUnicodeHexTextUniScribe` not called → Step 3 unreachable.
Existing demos and tests: unaffected.
