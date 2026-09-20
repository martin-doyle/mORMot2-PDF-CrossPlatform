# R-12 — Font Subsetting on POSIX via hb-subset — Implementation Plan

**Branch:** `feature/r12-posix-subset` (created from `main` @ `3537752`)
**Roadmap entry:** [ROADMAP.md › R-12](ROADMAP.md#r-12--font-subsetting-on-posix-via-hb-subset--implemented-on-linux-2026-09-19)
**Priority:** 3 | **Effort:** 3–4 days (the roadmap said 2–3; Step 10 and the
shared-stream pre-pass were not in that estimate)
**Status:** **merged into `main` on 2026-09-20** (`4ef4bc3`) — Steps 0–10 and
13–14 done, PAC 2024 green.
Open: Step 11 (macOS) and Step 12 (Windows), both platform checks on code that
is already in `main`.
Results in §7, deviations from the plan in §9.

This plan turns the roadmap entry into ordered, individually verifiable steps.
It follows the [Working Method](ROADMAP.md#working-method): one step at a time,
each built and tested before the next begins, development on Linux, macOS as
the third platform, and Windows for the regression check and PAC.

---

## 1. Goal and Scope

**Goal.** On Linux and macOS, `EmbeddedWholeTtf = false` embeds a subset of each
TrueType face, holding only the glyphs the document uses. Glyph IDs stay as
they are (`HB_SUBSET_FLAGS_RETAIN_GIDS`), so nothing in the content streams,
the `/W` arrays or the `/ToUnicode` CMaps changes. The only thing that changes
is which bytes go into `/FontFile2`.

**In scope**

- Load `libharfbuzz-subset` at runtime, behind a new optional interface
  `IPdfFontSubsetter`
- Call it from `PrepareForSaving`, with the used glyphs of **every** font
  instance that shares one font file (see F-5) as input
- Add the subset tag (`ABCDEF+`) that ISO 32000-1 §9.6.4 requires on a subset
  font's name
- Tests, rendering checks on Linux and macOS, and a Windows regression check
- A separate decision on whether tagged documents may subset too
  (Step 10, see F-1)

**Out of scope**

- Windows: `CreateFontPackage` stays. `libharfbuzz-subset.dll` does not ship
  with the OS, and the backend is not registered there.
- CFF-flavoured OpenType (`OTTO`): a subset would still be CFF, which belongs in
  `/FontFile3`, not in `/FontFile2`. Such faces keep being embedded whole.
- Renumbering glyph IDs (dropping `RETAIN_GIDS`): it saves little after deflate
  (+0.7 % for Liberation Sans, see the roadmap) and would need a glyph map
  through the whole engine.
- TTC face selection (R-11). The FreeType backend already gives us the loaded
  face as a standalone sfnt, so the subsetter always opens face index 0.

---

## 2. New Findings: What the Roadmap Entry Gets Wrong or Leaves Out

These came up while writing the plan. Each one changes a step below.

### F-1 — Tagged documents gain nothing: the headline figure does not apply

`Tagged := True` forces `EmbeddedWholeTtf := True` (P-6, Step 6).
`markdown_demo` is tagged, so the **88 % saving that the roadmap measures on
`markdown_demo.pdf` will not happen** with R-12 as specified. With the entry as
written, the untagged documents benefit (`chinese_demo`, `rtl_demo`, and user
code that calls `EmbeddedWholeTtf := False`), and the two demos everyone looks
at do not.

The reason P-6 gave for the override was "a subset breaks the `/ToUnicode`
round-trip". That was about `CreateFontPackage`. PDF/UA-1 and PDF/A allow
subset fonts, and with retained glyph IDs the `/ToUnicode` CMap maps the same
IDs as before. Whether tagged documents may subset on POSIX is therefore a
separate decision. It is made in **Step 10**, after the subsetter has proven
itself on untagged output. That step needs its own PAC run.

### F-2 — The entry points live in two libraries

Checked with `nm -D` against HarfBuzz 10.2.0 (Debian 13):

| Library | Exports |
|---|---|
| `libharfbuzz-subset.so.0` | `hb_subset_input_create_or_fail`, `hb_subset_input_destroy`, `hb_subset_input_unicode_set`, `hb_subset_input_glyph_set`, `hb_subset_input_set`, `hb_subset_input_set_flags`, `hb_subset_or_fail` |
| `libharfbuzz.so.0` (imported by the subset library) | `hb_blob_create`, `hb_blob_destroy`, `hb_blob_get_data`, `hb_face_create`, `hb_face_destroy`, `hb_face_reference_blob`, `hb_set_add`, `hb_set_add_range` |

The roadmap listed `hb_face_create`, `hb_face_reference_blob` and
`hb_blob_get_data` as subset symbols. They are not. `dlsym` on the subset
handle may still find them through the dependency chain on glibc, but relying
on that is fragile, and dyld on macOS is not guaranteed to behave the same way.
The loader opens **both** libraries explicitly, or reuses the `libharfbuzz`
handle that `mormot.pdf.harfbuzz.pas` already holds (settled in Step 1).

### F-3 — Minimum HarfBuzz version

`hb_subset_input_set_flags`, `hb_subset_input_set` and `hb_subset_or_fail`
arrived with the 2.9 subset API rework. Older libraries (Ubuntu 20.04 ships
2.6.4) only have the deprecated `hb_subset_input_set_retain_gids` family. The
loader requires the new API. If any required symbol is missing, the subsetter
reports "unavailable" and the engine embeds the whole face, which is exactly
today's behaviour. We do not add a second code path for the old API. *(Confirm
the exact version against the HarfBuzz NEWS file in Step 3.)*

### F-4 — Both inputs are needed, not just the glyph set

The roadmap says the glyph set is "the right input, not the unicode set". That
is true for shaped Arabic, but it breaks Latin text:

- The **WinAnsi instance** is a simple TrueType font with `WinAnsiEncoding`.
  The viewer maps each byte to a Unicode value and then looks the glyph up in
  the font's `(3,1)` `cmap`. `hb-subset` rebuilds `cmap` **only from the
  unicode set**. With a glyph-set-only input, the glyphs survive but their cmap
  entries do not, and every Latin character comes out blank.
- The **Unicode/CID instance** (`Identity-H`) addresses glyphs by ID directly,
  so it only needs the glyph set.

The input is therefore the **union of both**. The unicode set holds the
WinAnsi bytes that were used, converted to Unicode (0x80–0x9F go through the
WinAnsi table, not 1:1: 0x80 → U+20AC `€`), plus the code points in
`fUsedWideChar`. The glyph set holds every `fUsedWide[].Glyph`, which also
covers the PUA slots that shaping Step 3 creates.

### F-5 — The shared stream spans more than one font pair

`GetOrCreateFontFile2` reuses one stream for **byte-identical** font data. That
covers the WinAnsi/Unicode pair of one font, and also Regular and Bold when
both resolve to the same physical file (see `fonts.md` §9). If each instance
subsets its own glyphs, two things can go wrong:

1. The bytes differ per instance, so the deduplication silently stops working
   and the same face is embedded several times.
2. If the lookup key is the *source* bytes and the first subset wins, later
   instances lose their glyphs.

So the union has to be built per **source face** across every
`TPdfFontTrueType` instance that uses it, **before** the first instance is
serialized. That means a pre-pass in the save routine (Step 6), not a local
change inside `PrepareForSaving`.

### F-6 — The subset tag is mandatory

ISO 32000-1 §9.6.4 requires `/BaseFont` (and `/FontName` in the descriptor) of
a subset to start with six upper-case letters and `+`. `pdffonts` reports
`sub=yes` only when the tag is present, and preflight tools flag its absence.
The tag must be identical on the Type0 font, its CIDFont, the WinAnsi font and
their descriptors, because they share one file. It must also be
**deterministic** (derived from a hash of the glyph set), so that two runs
produce byte-identical PDFs.

### F-7 — `.notdef` must keep its outline

By default `hb-subset` drops the outline of glyph 0. Today a missing character
is drawn as the font's `.notdef` box, and the subset would draw nothing. Set
`HB_SUBSET_FLAGS_NOTDEF_OUTLINE`, so that a missing glyph still looks like one.

### F-8 — Tooling on the development machine

Available: `pdffonts`, `pdfinfo`, `pdftotext`, `pdftoppm` (poppler), `python3`
(with `zlib`). Missing: `qpdf`, `mutool`, `veraPDF`, ImageMagick `compare`,
`hb-subset`, `fontTools`. The rendering check in Step 9 therefore compares
`pdftoppm` PNGs byte for byte, or with a short Python script.
`libharfbuzz-subset0` 10.2.0 is installed.

---

## 3. Open Unknowns — Need Source Access

`CLAUDE.md` requires approval before reading `src/`. The skills do not cover
the following, and Step 1 settles them. **Each needs an explicit "yes"
before the file is opened.**

| # | Question | File | Why it matters |
|**Answers (Step 1, read from the source):**

| # | Answer |
|---|---|
| U-1 | `SaveToStreamDirectEnd` (also reached from `SaveToStream`) loops over `fFontList` and calls `PrepareForSaving` for every font with `fTrueTypeFontsIndex <> 0`; all pages are drawn by then. `PrepareFontSubsets` now runs right before that loop. WinAnsi instances precede their Unicode peers in `fFontList` (the peer is created lazily later), so the CIDFont can copy the already-prefixed name |
| U-2 | `GetOrCreateFontFile2(const aTtf: PdfString)`: key is `crc32c` + a full byte compare, the stream copies the bytes. Subset bytes shared per face therefore deduplicate unchanged |
| U-3 | `/BaseFont` and `/FontName` are written in the `TPdfFontTrueType` constructor and rewritten in `PrepareForSaving`; the CIDFont copies the WinAnsi `/BaseFont` ("may have been prefixed"), the Type0 font keeps the plain name |
| U-4 | Windows prefixes via `TPdfName.AppendPrefix` — **random** (`Random32`) and only on the WinAnsi font and descriptor. POSIX uses a deterministic tag instead and also prefixes the Type0 font; the Windows path is untouched |
| U-5 | `mormot.pdf.harfbuzz` loads `libharfbuzz.so.0` in `initialization`, registers only if all symbols resolve, and keeps its handle private. The subsetter follows the same pattern with its own handles |
| U-6 | A plain global `PdfTextShaper` set in `initialization`; `PdfFontSubsetter` mirrors it |
| U-7 | `SetTagged` set `fEmbeddedWholeTtf := true` unconditionally; nothing resets it later, so a caller can override it after `Tagged` |
| U-8 | `mormot.ui.pdf` itself uses `mormot.pdf.freetype` on POSIX, so `mormot.pdf.hbsubset` went there too: no demo or project needs a `uses` change |

---|---|---|---|
| U-1 | Where exactly does the save routine call `PrepareForSaving`, in which order over `fFontList`, and is text output finished at that point? | `src/core/mormot.ui.pdf.pas` (`SaveToStream*`, `PrepareForSaving`) | Placement of the pre-pass (F-5) |
| U-2 | Signature and hash/lookup of `GetOrCreateFontFile2`: what is the key, and who owns the buffer? | same | Keying the subset cache by source face |
| U-3 | Where `/BaseFont` and `/FontName` are written for the WinAnsi, Type0 and CIDFont objects, and whether they are written before or after the font file is known | same | Where the subset tag goes (F-6) |
| U-4 | What the Windows `CreateFontPackage` branch does with the name: does it already add a tag? | same, inside `{$ifdef USE_UNISCRIBE}` | Keep one tag scheme for both platforms |
| U-5 | How `mormot.pdf.harfbuzz.pas` loads its library: names, search order, failure handling, whether the handle is exported | `src/platform/unix/mormot.pdf.harfbuzz.pas` | Template and handle reuse (F-2) |
| U-6 | How the text shaper is registered in `mormot.pdf.types.pas` (`PdfTextShaper`, register function) | `src/core/mormot.pdf.types.pas` | The new interface should mirror it exactly |
| U-7 | Does `SetTagged` set `fEmbeddedWholeTtf` unconditionally, and does anything reset it afterwards? | `src/core/mormot.ui.pdf.pas` (`SetTagged`) | Step 10 |
| U-8 | Which units the demos and the test runner `uses` for the FreeType/HarfBuzz backends (the `.lpr` files, `test_runner.lpr`) | `examples/`, `tests/` — **no approval needed** | Where the new unit must be added |

---

## 4. Branch and Commit Rules

- All work happens on `feature/r12-posix-subset`. `main` is not touched until
  the merge in Step 14.
- **One commit per step**, in the existing style:
  `feat(subset): IPdfFontSubsetter interface (R-12)`,
  `feat(subset): hb-subset backend (R-12)`, `test(subset): …`,
  `docs(roadmap): R-12 …`.
- Before every commit: `test_runner` is green on Linux and every demo still
  builds. A step that fails its verification gets fixed within that step. We
  do not stack a second step on top of a broken one.
- Rebase onto `main` before Step 11 (macOS) and again before the merge, so the
  platform checks run against current code.
- Baselines and rendered PNGs live outside the repository
  (`~/r12-baseline/`, `~/r12-after/`), not in the branch.

---

## 5. Steps

### Step 0 — Baseline (no code)

On `main` (Linux), before the first commit on the branch:

```bash
LAZ=/home/parallels/fpc-fixes/lazarus/lazbuild
for p in pdf_demo/pdf_demo_crossplat markdown_demo/markdown_demo \
         chinese_demo/chinese_demo rtl_demo/rtl_demo; do
  $LAZ examples/$p.lpi -B
done
# run each demo, then per output PDF:
pdffonts  X.pdf > ~/r12-baseline/X.fonts
pdftotext X.pdf   ~/r12-baseline/X.txt
pdftoppm -r 110 -png X.pdf ~/r12-baseline/X
stat -c '%s %n' X.pdf >> ~/r12-baseline/sizes.txt
```

Also produce an **untagged variant of `markdown_demo`** (a temporary local
switch, not committed). Without it, Step 9 has no document that shows the 88 %
case before Step 10.

**Done when:** baseline files exist for all four demos plus the untagged
variant, and the sizes are recorded in the result table (§7).

### Step 1 — Settle the open unknowns (needs source approval)

Read the places listed in §3 and record the answers here, in §3, the way
ROADMAP Step 6 did. If an answer contradicts this plan (for example, if
`/BaseFont` is written before the font file exists), revise the affected step
**before** writing code.

**Done when:** U-1 … U-8 each have an answer with a line reference.

### Step 2 — Interface in `mormot.pdf.types.pas`

Mirror the text shaper's registration (U-6). Sketch, to be adjusted once
Step 1 is done:

```pascal
type
  /// input for IPdfFontSubsetter.Subset
  TPdfFontSubsetRequest = record
    /// Unicode code points whose cmap entries must survive (WinAnsi instance)
    Unicodes: TIntegerDynArray;
    /// glyph IDs that must survive (CID instance, shaped and PUA glyphs)
    Glyphs: TIntegerDynArray;
  end;

  /// optional font subsetter - registered by a platform unit, nil otherwise
  IPdfFontSubsetter = interface
    ['{…new GUID…}']
    /// return false when the face cannot be subset (CFF, corrupt, library
    // error): the caller then embeds AFace unchanged
    // - glyph IDs of the result must equal those of AFace (retain-gids)
    function Subset(const AFace: RawByteString;
      const ARequest: TPdfFontSubsetRequest; out ASubset: RawByteString): boolean;
  end;

var
  PdfFontSubsetter: IPdfFontSubsetter;

procedure RegisterPdfFontSubsetter(const ASubsetter: IPdfFontSubsetter);
```

`RawByteString` in and out keeps ownership simple. The face is copied once per
source face and document, which is negligible next to the deflate step.

**Verify:** everything compiles on Linux; nothing registers yet, so the output
is byte-identical to the baseline.

### Step 3 — New unit `src/platform/unix/mormot.pdf.hbsubset.pas`

Modelled on `mormot.pdf.harfbuzz.pas` (U-5).

1. **Loading.** Candidate names, in order:
   - Linux: `libharfbuzz-subset.so.0`, then `libharfbuzz-subset.so`
   - macOS: `libharfbuzz-subset.0.dylib`,
     `/opt/homebrew/lib/libharfbuzz-subset.0.dylib`,
     `/usr/local/lib/libharfbuzz-subset.0.dylib`

   `libharfbuzz` is taken from the shaper unit's handle if it exposes one
   (U-5), otherwise opened the same way. Load lazily, on the first `Subset`
   call, so that a program which never subsets never touches the library.
2. **Bindings.** The 15 functions from F-2, all `cdecl`. If a single symbol is
   missing, the backend is unavailable (F-3). There is no partial mode.
3. **`Subset` implementation:**
   ```
   reject unless the sfnt version is $00010000 or 'true'   (§1: CFF is out of scope)
   blob  := hb_blob_create(data, len, HB_MEMORY_MODE_READONLY, nil, nil)
   face  := hb_face_create(blob, 0)             // TTC already extracted
   input := hb_subset_input_create_or_fail
   hb_set_add(unicode_set, each Unicodes[i]); hb_set_add(glyph_set, each Glyphs[i])
   hb_set_add(glyph_set, 0)                      // .notdef always
   flags := RETAIN_GIDS or NOTDEF_OUTLINE or NO_HINTING
   hb_subset_input_set_flags(input, flags)
   drop tables: GSUB GPOS GDEF (a PDF viewer never shapes; the glyph set is
                the authority, see below)
   sub   := hb_subset_or_fail(face, input)       // nil -> return false
   copy hb_blob_get_data(hb_face_reference_blob(sub)) into ASubset
   destroy blob/face/input/sub in a try..finally
   ```
   Flag values are taken from `hb-subset.h` of the installed version and
   declared as constants, with a comment giving the header's version.
4. **Registration** in `initialization`: `RegisterPdfFontSubsetter(...)`. It
   registers only an object; the library is loaded lazily (point 1).

**Why the layout tables are dropped.** When `GSUB` stays, `hb-subset` runs its
GSUB closure and adds every alternate reachable from the unicode set. That is
what made the Arabic measurement in the roadmap work with only base letters.
Our glyph set already contains every glyph that was actually drawn, including
the shaped ones, so the closure only adds dead weight. **This is an assumption
that Step 9 checks:** the size with and without the drop goes into the result
table, and `rtl_demo` must render identically either way. If it does not, the
glyph tracking is missing a glyph, and that is a bug to fix, not a reason to
keep the closure.

**`NO_HINTING`**: PDF viewers rasterise without the TrueType bytecode on most
platforms, and the hinting tables are a large share of Liberation. Also
measured in Step 9. If any viewer renders visibly worse, drop the flag.

**Verify:** compiles on Linux; `test_runner` green; demos unchanged (the engine
does not call the subsetter yet).

### Step 4 — Subsetter tests in isolation

New unit `tests/test_pdf_subset.pas`, added to `test_runner.lpr`. On POSIX
only; when the library is missing, each test **skips with a message** instead
of failing, so that a machine without `libharfbuzz-subset0` stays green.

| Test | Asserts |
|---|---|
| `TestSubsetterRegistered` | `PdfFontSubsetter <> nil` on POSIX |
| `TestSubsetRetainsGids` | Liberation Sans (whole face via the FreeType backend), subset to `A`: `maxp.numGlyphs` unchanged, the `glyf` entry for `A`'s original glyph ID is non-empty, a glyph not requested is empty |
| `TestSubsetKeepsCmapForUnicodes` | a code point in `Unicodes` is still in the subset's `(3,1)` cmap, one only in `Glyphs` is not (F-4) |
| `TestSubsetKeepsNotdef` | glyph 0 has an outline (F-7) |
| `TestSubsetIsSmaller` | the subset is < 10 % of the whole face for a 10-glyph request |
| `TestSubsetRejectsCff` | a buffer starting with `OTTO` returns `false` |
| `TestSubsetRejectsGarbage` | random bytes return `false` and do not crash |

The table checks parse the sfnt directly (tag directory → `maxp`, `loca`,
`cmap`) with a small helper in the test unit. `TPdfTtf` expects a DC and does
not fit here.

**Verify:** new tests green on Linux; a run with `LD_LIBRARY_PATH` pointing at
an empty directory (or with the library temporarily renamed) skips cleanly.

### Step 5 — Build the subset request from the font instances

In `mormot.ui.pdf.pas`, one private method on `TPdfFontTrueType`, with no
`{$ifdef}`:

```
AddToSubsetRequest(var R: TPdfFontSubsetRequest)
  WinAnsi instance:
    for c in fWinAnsiUsed:            R.Unicodes += WinAnsiToUnicode(c)   (F-4)
    for i < fUsedWideChar.Count:      R.Unicodes += fUsedWideChar.Values[i]
                                      R.Glyphs   += fUsedWide[i].Glyph
  Unicode instance: nothing of its own. Its tracking arrays hold the whole CMAP
    (fonts.md §4), and what was really drawn is recorded on the WinAnsi peer.
```

The PUA code points from shaping Step 3 do end up in `Unicodes`. That does no
harm: the font has no cmap entry for them, so `hb-subset` ignores them. Their
glyphs arrive through `Glyphs`.

`WinAnsiToUnicode` must use the engine's existing WinAnsi table (the one behind
`WideCharToWinAnsi`), not a new one.

**Verify:** a unit test in `test_pdf_smoke.pas` draws `"Aä€"` + `"Ω"` and
checks the resulting request: U+0041, U+00E4, U+20AC, U+03A9, plus the glyph
of `Ω`.

### Step 6 — Pre-pass and hook in the save path

Placement follows U-1/U-2. The intended shape:

1. **Pre-pass** in the save routine, before the `PrepareForSaving` loop, only
   when `EmbeddedTTF and not EmbeddedWholeTtf and (PdfFontSubsetter <> nil)`:
   - for every WinAnsi `TPdfFontTrueType` in `fFontList`, get its whole-face
     bytes (the same `GetFontData(…, 0, …)` call the embed path uses today)
   - key them by a hash of the bytes (`crc32c` + length, then a byte compare on
     collision). This is the same identity `GetOrCreateFontFile2` uses (F-5).
   - `AddToSubsetRequest` into that key's request
   - after the loop, run `PdfFontSubsetter.Subset` once per key and keep
     `source-key → subset bytes` (or "failed") in a document-local map
2. **Hook** in the WinAnsi branch of `PrepareForSaving`, immediately before
   `GetOrCreateFontFile2`: if the map has a subset for this face, pass the
   subset bytes instead of the whole face. Every instance of that face gets the
   **same** subset bytes, so `GetOrCreateFontFile2` still deduplicates.
3. **Precedence:** a registered `PdfFontSubsetter` comes first. Otherwise the
   existing `{$ifdef USE_UNISCRIBE}` / `CreateFontPackage` branch runs
   unchanged. Windows registers no subsetter, so Windows behaviour does not
   change at all.
4. **Failure:** `Subset = false` → whole face, like today. No exception: a
   larger PDF is better than no PDF. Log it through the existing logging, if
   the engine has one (U-1).
5. Free the map when the save finishes. A document saved twice must subset
   twice, because more text may have been drawn in between.

**Verify:** `test_runner` green; `chinese_demo` and `rtl_demo` are now smaller
on Linux; the tagged demos are unchanged in size (the F-1 expectation).

### Step 7 — Subset tag on the font names

Placement follows U-3/U-4.

- Tag = six letters `A`–`Z`, derived from `crc32c` over the sorted glyph set
  of the source face (base 26, 6 digits). Deterministic, so identical input
  gives identical output.
- Prefix `/BaseFont` of the WinAnsi font, the Type0 font and the CIDFont, and
  `/FontName` of the descriptors, **only** for faces that were really subset
  (not when `Subset` returned false).
- If the Windows branch already writes a tag (U-4), use the same helper for
  both, and do not add a second scheme.

**Verify:** `pdffonts` on `chinese_demo`/`rtl_demo` shows `sub=yes` and names
like `QKZJTA+LiberationSans`; two consecutive runs produce identical tags.

### Step 8 — Engine-level tests

In `tests/test_pdf_smoke.pas` (POSIX-only tests skip when no subsetter is
registered):

| Test | Asserts |
|---|---|
| `TestSubsetEmbeddedIsSmaller` | untagged doc, `EmbeddedTTF`, `EmbeddedWholeTtf := False`, one line of Latin text: < 25 % of the same doc with `EmbeddedWholeTtf := True` |
| `TestSubsetSharedStreamOnce` | Latin + Greek in one face → exactly one `/FontFile2` in the file, and both the WinAnsi and the Type0 font point at it |
| `TestSubsetRegularBoldSameFile` | two styles resolving to one file (if the machine has such a pair; otherwise skip) → one stream holding the union |
| `TestSubsetNameTagged` | `/BaseFont /XXXXXX+` present on all three font objects |
| `TestSubsetFallbackWithoutSubsetter` | with `PdfFontSubsetter := nil` for the duration of the test, output equals the whole-face output |
| `TestTaggedStillWholeFace` | until Step 10: `Tagged := True` → no subset tag, whole face embedded |

**Verify:** all green on Linux; total assertion count recorded.

### Step 9 — Rendering and extraction check on Linux

The step that answers the roadmap's "Nothing was rendered".

```bash
for X in output_chinese output_rtl markdown_demo_untagged; do
  pdftoppm -r 110 -png $X.pdf ~/r12-after/$X
  pdftotext $X.pdf ~/r12-after/$X.txt
  pdffonts  $X.pdf > ~/r12-after/$X.fonts
done
# pixel identity per page against ~/r12-baseline (python3, PNG bytes after decode)
diff ~/r12-baseline/X.txt ~/r12-after/X.txt
```

Acceptance per document:

- every page **pixel-identical** to the baseline at 110 dpi (retained glyph IDs
  and unchanged widths mean the page cannot legitimately move. A difference is
  a missing glyph or lost hinting, and has to be understood before moving on)
- `pdftotext` output identical
- `pdffonts`: `emb=yes sub=yes`, and `uni` unchanged from the baseline
- sizes recorded in §7, including the two tuning variants from Step 3 (with and
  without dropping `GSUB/GPOS/GDEF`, with and without `NO_HINTING`)

`rtl_demo` on Linux uses Noto Naskh Arabic, so it only exercises shaping
Step 2 (`fonts.md` §10). The PUA path (shaping Step 3) is checked on macOS in
Step 11.

**Commit** after this step: the branch is now a complete, useful R-12 for
untagged documents.

### Step 10 — Decision gate: may tagged documents subset on POSIX?

**Only after Step 9 is accepted.** This is a separate commit, so it can be
reverted on its own.

Proposal: `SetTagged` stops forcing the whole face when a retain-GID
subsetter is registered:

```pascal
fEmbeddedWholeTtf := PdfFontSubsetter = nil;  // was: true
```

- Windows is unchanged (`nil` there), and so is its `CreateFontPackage` path,
  whose round-trip problem was the reason for P-6.
- A caller who wants the whole face can still set `EmbeddedWholeTtf := True`
  after `Tagged` (check U-7: nothing may reset it).
- The docs sentence "a subset breaks `/ToUnicode`" becomes platform-specific.

Verification, all required:

1. `pdftotext` round-trip of `markdown_demo.pdf` and `output_crossplat.pdf`,
   identical to the baseline, including `ä ö ü ß €`
2. `pdffonts`: `emb=yes sub=yes uni=yes` for every face
3. page renders pixel-identical to the Step 0 baseline
4. **PAC 2024 on Windows**, on the Linux-built PDFs: same result as after
   Step 13 of the roadmap (green, W-1 accepted). Also open the *Logical
   Structure* view.
5. `veraPDF --flavour ua1`, if a machine with it is available by then

If 1–4 do not all pass, **drop this commit** and document why in the roadmap.
R-12 then ships for untagged output only.

Expected effect if accepted: `markdown_demo.pdf` 1.43 MB → about 0.19 MB (the
roadmap measurement), `output_crossplat.pdf` 0.80 MB → a comparable fraction.

### Step 11 — macOS verification

After rebasing onto `main`.

- `brew install harfbuzz`, then check which dylib names Homebrew installs,
  and that the loader finds them on both `/opt/homebrew` (arm64) and
  `/usr/local` (x86_64)
- Run the full `test_runner`, and Steps 9 (and 10, if accepted) against a
  macOS baseline taken the same way as Step 0
- **`rtl_demo` with Geeza Pro**: this is the shaping Step 3 / PUA path, where
  the glyph set is the only thing carrying the shaped glyphs (F-4). The pages
  must be pixel-identical to the whole-face baseline
- `chinese_demo` with the macOS CJK face (a `.ttc`, so this also covers the
  "face already extracted" assumption)
- Any Apple face that is CFF-based must fall back to the whole face, without
  an error

### Step 12 — Windows regression

- All demos and `test_runner` build and pass
- No subsetter is registered, so output must match `main`. Compare `pdffonts`
  and file sizes of all demos, since a byte compare fails on dates and IDs
- If Step 10 was accepted: the Windows-built tagged PDFs still embed the whole
  face and stay green in PAC

### Step 13 — Documentation

| File | Change |
|---|---|
| `.claude/skills/fonts.md` | §3 and §9: POSIX subsets via hb-subset (retain-GIDs, union per source face, subset tag); the "no POSIX subsetter" lines go; §3 Tagged note per Step 10's outcome |
| `.claude/skills/call-graph.md` | 4d: pre-pass + subsetter branch before the `USE_UNISCRIBE` branch |
| `.claude/skills/platform-backends.md` | new optional interface `IPdfFontSubsetter`, its registration, library names, minimum HarfBuzz version |
| `.claude/skills/pdf-engine.md` | Font Strategy: `EmbeddedWholeTtf` is now effective on POSIX; Tagged behaviour per Step 10 |
| `CLAUDE.md` | Open Items (font subsetting entry), File Structure + Status (new unit), Dependencies: `libharfbuzz-subset0` (Debian/Ubuntu), `harfbuzz` (Fedora, brew), optional at runtime |
| `docs/DEMOS.md` | new output sizes |
| `docs/ROADMAP.md` | R-12 → **DONE** with a Result section (the §7 table), summary table, Completed Work row |
| demo `.lpr` files | add `mormot.pdf.hbsubset` to the POSIX `uses` block (U-8) |

### Step 14 — Merge

- Rebase onto `main`, full test run on Linux
- PR `feature/r12-posix-subset` → `main`, with the §7 result table in the
  description
- Merge only after Steps 9, 11 and 12 are accepted (and Step 10 either
  accepted or dropped and documented)

---

## 6. Risks

| Risk | Likelihood | Effect | Mitigation |
|---|---|---|---|
| Glyph tracking misses a glyph (shaped, fallback font, symbol font) | medium | blank or `.notdef` character | pixel comparison in Step 9/11; `NOTDEF_OUTLINE` makes a miss visible instead of blank |
| Shared-stream union incomplete (F-5) | medium | glyphs missing in the second style | pre-pass keyed by source bytes; `TestSubsetRegularBoldSameFile` |
| `libharfbuzz-subset` absent or too old on the target | high (Ubuntu 20.04, minimal containers) | no saving | falls back to the whole face; tests skip; the dependency is documented as optional |
| Dropping `GSUB` removes something a viewer needs | low | none expected, no viewer shapes PDF text | measured variant in Step 9; revert the flag if needed |
| `NO_HINTING` degrades rendering in some viewer | low | slightly different rasterisation at small sizes | measured in Step 9; flag can be dropped |
| PAC rejects the subset in tagged output | low–medium | Step 10 fails | Step 10 is its own commit; drop it, R-12 stays for untagged output |
| Non-deterministic tag or subset bytes | low | irreproducible PDFs | hash-derived tag; two-run comparison in Step 7 |

---

## 7. Result Table

Linux, Debian 13 aarch64, HarfBuzz 10.2.0. "Variant" = the demo built in a
scratch tree with `EmbeddedWholeTtf := False` (chinese, rtl) or untagged
(markdown). Every row: all pages pixel-identical to the baseline at 110 dpi,
`pdftotext` identical.

| Document | Baseline | After Step 9 | After Step 10 | macOS | Windows |
|---|---|---|---|---|---|
| `markdown_demo.pdf` (tagged) | 1,428,389 | unchanged (F-1) | **46,407 (−96.8%)** | open | open |
| `markdown_demo` untagged variant | 1,426,620 | 44,695 (−96.9%) | — | open | — |
| `output_crossplat.pdf` (tagged) | 800,923 | unchanged (F-1) | **19,256 (−97.6%)** | open | open |
| `output_chinese` variant | 2,309,640 | 10,848 (−99.5%) | — | open | — |
| `output_rtl` variant | 500,092 | 15,090 (−97.0%) | — | open | — |
| Tuning: layout tables kept (md / cjk / rtl variants) | | 46,773 / 11,413 / 17,047 | | | |
| Tuning: hinting kept (md / cjk / rtl variants) | | 83,765 / 14,724 / 29,052 | | | |

The tuning variants render identically too, so the defaults (drop both) stay.
That RTL renders identically **without** the GSUB closure confirms the glyph
set carries every shaped glyph. `pdffonts`: every face `emb=yes sub=yes`;
`uni=yes` wherever it was before, on all faces of the tagged demos.
Test suite: 156 → 196 assertions, all green.

---

## 8. Acceptance Criteria for R-12

- [x] On Linux, `EmbeddedWholeTtf = False` embeds a subset (`sub=yes`) and the
      document is pixel-identical to the whole-face output — [ ] macOS
- [x] `pdftotext` output unchanged for every demo (Linux)
- [x] One `/FontFile2` per physical face, as before (`TestSubsetUnionOfStyles`)
- [x] Without a subsetter the output equals today's, with no error
      (`TestSubsetFallbackWithoutSubsetter`; not yet tried with the library
      really absent)
- [ ] Windows output unchanged — by construction (no subsetter registered), to
      be confirmed by a Windows build and run (the merge did not wait for it)
- [x] Tagged documents subset and PAC-green — PAC 2024 on 2026-09-20 reported
      only the known W-1 figure warning, as before R-12
- [x] `test_runner` green on Linux — [ ] macOS, [ ] Windows
- [x] Skills, `CLAUDE.md`, `DEMOS.md` and `ROADMAP.md` updated

---

## 9. Deviations From the Plan

| Plan | What was done, and why |
|---|---|
| Load the library lazily on first use (Step 3) | Loaded in `initialization`, registered only when complete — like the shaper. `PdfFontSubsetter <> nil` then means "usable", which Step 10 relies on |
| Demos add `mormot.pdf.hbsubset` to their `uses` (Step 13) | `mormot.ui.pdf` uses it on POSIX, next to the FreeType backend (U-8) |
| Engine tests in `test_pdf_smoke.pas` (Step 8) | Second class `TPdfSubsetEngineTests` in `test_pdf_subset.pas`, next to the sfnt readers it needs; only the Tagged assertion in `test_pdf_smoke.pas` changed |
| Test: subset keeps `numGlyphs` | Wrong assumption: retain-gids cuts glyphs after the highest kept ID, so `numGlyphs` shrinks — IDs never move, which is what matters |
| Test: glyph-only requests get no cmap entry | Wrong assumption: hb-subset adds cmap entries for requested glyphs as well; harmless. F-4 still holds: WinAnsi glyphs are not in the glyph set, so their code points are required |
| Not planned | **PDF/A-1 keeps the whole face**: 6.3.5 requires `/CIDSet` for subset CIDFonts, which the engine does not write. Before R-12 POSIX never subset, so this avoids turning PDF/A-1 output invalid |
| Not planned | **Symbol fonts keep the whole face**: their glyphs are reached through the `(3,0)` cmap, which a unicode-set request does not describe |
| Not planned | **Crash fix** found during Step 0: `chinese_demo`/`rtl_demo` crashed on aarch64 (`fUsedWide[FindOrAddUsedWideChar(c)]` read the array address before the call reallocated it). Separate commit `48f286b` |
| Step 0 baseline for the tagged demos only | All four demos embed the whole face on purpose (two tagged, two with `EmbeddedWholeTtf := True`), so the checks ran on variants built in a scratch tree; the demos keep their settings, only their comments were corrected |

