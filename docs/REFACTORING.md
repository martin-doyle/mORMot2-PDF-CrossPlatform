# mORMot Refactoring — Plan

The integration of this project into the mORMot2 trunk as `src/pdf` (ROADMAP
R-28). The architecture is Arnaud's proposal; this file plans the work in
steps and records what each step was checked with.

- **Architecture:** https://gist.github.com/synopse/9e31d8808ed2575ad5ad23da6fe41e4f
  — the phase numbers below are the gist's (§21); Phases 0 and 1b are ours
- **Discussion:** the gist's comments (architecture), the mORMot forum (process)
- **Feature freeze** while the refactoring runs: bug fixes only

---

## Rules for Every Step

The gist's §22 (as of 2026-10-01) merged with ROADMAP's Working Method, so
that no step needs the gist at hand. When the gist changes, update this
section.

**Behaviour**

1. **Behaviour first.** Unless a step says otherwise, the demo PDFs come out
   identical to the baseline after normalization (Phase 0); existing tests
   stay valid. A difference is a defect until it is explained and accepted
   in this file. For the refactoring this replaces ROADMAP's pixel check.
2. **One step, one commit, one kind of change.** Never two of: move units,
   rename public API, change font metrics, change PDF serialization, change
   report layout. Each must be reviewable on its own. PRs (agreed with
   Martin, 2026-10-09): per phase one PR with the complete implementation
   and one with the bug fixes found on the way; the commits inside keep
   the steps apart. Sven runs the check session on Windows (FPC, Delphi 7,
   Delphi 13), Linux and macOS, Martin adds Delphi 2010.

**Architecture**

3. **No new dependency without justification.** Every new `uses` follows the
   gist's dependency graph (§14). Forbidden: `mormot.lib.core` →
   `mormot.pdf.*`, `mormot.pdf.core` → GUI, `mormot.pdf` → GUI.
4. **No generic abstraction without need.** An interface only when there are
   two implementations or a clear testing or injection need.
5. **Low-level units stay small.** `mormot.lib.core` and `mormot.pdf.core`
   depend on little.
6. **Capabilities, not platform emulation.** No Unix equivalent of a Windows
   handle to keep the old internal model when a direct abstraction is possible.
7. **Public convenience.** `uses mormot.pdf` or `uses mormot.pdf.report` is
   enough; a user never picks the font backend.

**Ours**

8. **Documentation moves with the code.** A step that renames or moves
   something updates `CLAUDE.md` and the affected skills in the same PR.
9. **Shaping changes** are checked with a font without Arabic presentation
   forms (`.claude/skills/fonts.md` §10).
10. **PAC and veraPDF** are run by Martin (PAC on Windows, veraPDF on macOS).
11. **Access to `src/` stays restricted** (`CLAUDE.md`), also for refactoring
    steps: each file is asked for with its reason. Martin follows every step
    and must not lose track; no standing permission.

**Checked after every step:**

| Check | Where |
|---|---|
| `test_runner` green, same assertion count, golden files unchanged | Windows: FPC, Delphi 7, Delphi 13 Win32/Win64 (Sven), Delphi 2010 (Martin) - since 2026-10-09, rule 2 |
| All eight demos rebuilt (`-B`) and run (GUI demos with `--export`) — never an executable of an earlier state | the same |
| Demo PDFs identical to the baseline after normalization | the same |
| `test_runner`, demos, PDFs against the baseline | Linux and macOS (Sven, every PR since 2026-10-09) — every step that touches POSIX code, otherwise at the end of the phase |
| PAC 2024, veraPDF | only when a PDF differs, and at the end of each phase |
| Delphi 13 (Linux64, Android64) | the community; asked for at the end of each phase |

---

## A Check Session — the Same on Every Platform

For a baseline and for every step checked against one. Each platform's
session (Windows: per compiler) does exactly this:

1. `git pull`; the mORMot2 clone at the pinned commit (Phase 0 step 3)
2. `test_runner`, `pdfcheck` and the eight demos rebuilt — `lazbuild -B`, the
   Delphi build scripts; never an executable of an earlier state. When a
   step removed or moved a unit, its compiled leftovers go first (`.ppu`,
   `.o` in the projects' `lib/<cpu-os>/`, `.dcu` in `bin/d7|d2010/*/dcu/`):
   `-B` keeps them, and a stale one can be linked instead of the new unit.
   `lazbuild` warns `Duplicate unit ... orphaned ppu` then. Never compile
   the `mormot2ui` package while `src/core` holds our own `mormot.ui.*`: no
   project needs it, and it writes `mormot.ui.pdf`, `.core` and `.gdiplus`
   into the output folder it shares with `mormot2`
3. `test_runner`: the expected count, no failure. At a baseline also
   `test_runner --golden-record`; at a step, the plain run compares
4. `pdfcheck run <compiler> <folder>` into the state's folder. It sets
   `SOURCE_DATE_EPOCH` to 2026-01-01 unless it is set, and `report_demo` and
   `mormot_demo` print that date: with the same valid value, unchanged demo
   output compares equal across days. A folder made before (Phase 1b) differs
   in the printed date, and possibly in what it moves (the text after it, the
   subset) - look at every difference
5. `tagged_unicode_<system>.pdf` from `test_runner`'s folder copied into it
6. Reported: the count, the golden result, `pdfcheck`'s output

**The folder** is on the Mac's drive (path in `CLAUDE.local.md`), one per
state, named `<date>_<state>` (`2026-10-02_phase0-baseline`,
`2026-10-xx_phase0-pr2`). It holds **nine PDFs per system and nothing
else**: the eight demos and `tagged_unicode`. Their names carry demo, OS,
CPU and compiler, so the systems sit flat side by side, `pdfcheck compare
<old> <new>` pairs them in one run, and Martin checks the folder in one go —
veraPDF `ua1` on the seven tagged files (six demos and `tagged_unicode`),
`3u` on `zugferd_demo`, PAC; `chinese_demo` and `rtl_demo` are untagged.

**The golden files never leave `golden/` beside `test_runner`:** not
copied to the folder, not given to veraPDF or PAC. They are compared there
automatically; their names lack the system; five are untagged on purpose,
so a validator reports them as failures that are none; and they are
recorded again from the baseline commit if lost

---

## Phases

### Phase 0 — Baseline

Before anything moves. In this order — the check tools first, then the
mORMot2 trunk pinned, then today's `main` recorded; Sven's merge can change
output (the trunk's `mormot.lib.uniscribe`, ported trunk commits), so it is
checked against that record:

1. ~~The check tool~~ done: `tests/pdfcheck`, in Pascal (no Python,
   `pdffonts` or `pdftoppm` on the Windows machine), on all three platforms:
   - `run <fpc|d7|d2010> <dir>`: run the eight demos of one compiler and
     collect their PDFs — in the tool rather than a `.bat` and a `.sh`, so it
     is written once. On Linux without a display: `xvfb-run pdfcheck run ...`
   - `compare <dirA> <dirB>`: both sides normalized — streams inflated;
     dates, `/ID`, XMP uuids, subset prefixes, stream lengths and the
     cross-reference offsets masked (the method used by hand so far, ROADMAP
     R-26, R-25) — then compared: up to ten differences across the objects
     (members of object streams included) and the text outside them are
     shown, the rest counted
   - `fonts <file>`: the fonts as `pdffonts` lists them — type, font file
     key, subset, `/ToUnicode`
   - `struct <file>`: the roles of the structure tree and their counts
   - `normalize <file> <out>`: one file normalized, to look at a difference

   The reading code is `tests/pdf_inspect.pas`, shared with the tests. A test
   tool, not the draft of the PDF reader (gist §1, after the migration).
   Within one platform `compare` decides; across platforms, where the fonts
   differ, `pdftotext`, `fonts`, `struct` and the page count must match
   (ROADMAP V).

   **Checked:** two runs per compiler compare equal — Windows (FPC, Delphi 7,
   Delphi 2010), Linux, macOS; a changed file is reported with its line, a
   missing one as such. `fonts` gives the font dictionaries a text search
   counts in all eight demos; a hand-written file covers a non-embedded
   Type1 and a CFF `FontFile3` (Windows; on Linux and macOS still to run).
   `struct` gives `zugferd_demo`'s roles as
   ROADMAP R-26 records them. `test_runner` unchanged, 259/259 on all three
   Windows compilers
2. ~~**Golden files**~~ done (Sven, PR #3): nine small documents, layers 1–3,
   recorded per machine and compiler by `test_runner --golden-record` and
   compared by every `test_runner` run. They complement `pdfcheck`, which
   covers the real demos and compares the compilers with each other.
   Merged unchanged, then ours:
   - **one normalizer:** Sven's `GoldenNormalize` — a tokenizer that checks
     each `/Length` and offset before blanking it — moves to
     `pdf_inspect.pas`; `pdfcheck compare` and `normalize` use it,
     `NormalizePdf` goes. Pattern matching over the whole file can hide a
     real difference
   - the same assertion count with and without a recorded baseline: two per
     case, a difference by `Check(false)`, not `TestFailed()`
   - one report of a difference: `ComparePdfText` shows up to ten
     differences across the objects (members of object streams included) and
     the text outside them, the rest counted - an added or removed object by
     number and generation, a changed one with the byte and the line of each
     side - for the golden files and `pdfcheck` alike

   **Checked** on Windows (FPC Win64, Delphi 7, Delphi 2010): `test_runner`
   279/279 without a baseline, while recording and comparing; a changed
   golden file fails the run (exit code 1). `pdfcheck`: two demo runs per
   compiler compare equal; all eight demos normalize without an error; a
   `/Length` 7 bytes too long is reported as broken, one byte too long (the
   end of line before `endstream`) as a difference; `fonts` and `struct` give
   the same output as before for all eight demos (`DictValue` is now the
   normalizer's). Linux 318/318 and macOS 337/337 in the same four states,
   nine cases recorded; two demo runs compare equal, none broken
3. **mORMot2 trunk.** From here on the project builds against the trunk
   only: release 2.4-stable lacks functions the ported commits of step 5 use
   (`TTemp512`, `UINT_999`, `bswap16array`, `StrIEqual`, `SameTextS`,
   `SameExt`). v0.10.0 stays the last version for 2.4-stable.
   - a checkout of its own on each machine, beside the project (paths in
     `CLAUDE.local.md`), with `static/` from the `mormot2static.7z` matching
     it, checked against `static/dev.sha256`. Windows: the existing Lazarus
     points to it; Linux and macOS: a separate fpcupdeluxe installation,
     with the FPC version used so far
   - **pinned per baseline:** the trunk is updated right before a baseline
     and its commit recorded here — never between two baselines, or a
     difference cannot be told from the change under test

   **Pinned:** `d60cc6e80` (2026-10-02); from Phase 1 on a commit of the
   `pdf-font-layer` branch of `landrix/mORMot2`, which is `d60cc6e80` plus
   the new `mormot.lib.*` units (see Phase 1, "Where the code lives"):
   `89d652a77` (2026-10-04, `mormot.lib.core` added, no other change), then
   `5a1fb60fc` (2026-10-04, `mormot.lib.freetype` and `mormot.lib.harfbuzz`
   added, unused here until the old POSIX backends are replaced; in
   `mormot.lib.core` the out parameter of `IFontSubsetter.Subset` renamed
   `Output` and two comments corrected), then `2dce8feb6` (2026-10-07, the
   GDI services in `mormot.lib.uniscribe`, replacing `mormot.pdf.gdi`), then
   `0da9d7adc` (2026-10-08, `TFontShapedRun.YOffsets` and `Outcome`, filled
   by `mormot.lib.harfbuzz`, not used by the engine yet), then `54f47c547`
   (2026-10-08, the zero values of `TFontShapeKind` and `TFontShapeOutcome`
   are the safe ones: `fskPlain`, and the new `fsoUnknown`), then `2f8bf3d76`
   (2026-10-08, step W2: the Uniscribe shaper and the FontSub subsetter in
   `mormot.lib.uniscribe`, `NeedsShaping` in the HarfBuzz shaper,
   `IFontSubsetter.SupportsSymbolic`), then `0e40ec95c` (2026-10-09:
   `IFontProvider.GetFaceFile`, the face of a `.ttc` as one font file;
   `ExtractSfntFromTtc` and `TtcFaceIndex` in `mormot.lib.core`; new GUIDs
   for `IFontProvider` and `IFontSubsetter`), then `84012287b` (2026-10-09, step
   W3: `IFontProvider.GetGlyphAdvance`), then `2f0e02243` (2026-10-09, the
   bounds of `ExtractSfntFromTtc`), then `681bbe2a1` (2026-10-09, Phase 1b:
   `IFontFace` replaces the device context).
   **Checked:** against `d60cc6e80`, today's `main`,
   `test_runner` 259/259 on Windows (FPC Win64, Delphi 7, Delphi 2010),
   298/298 on Linux, 317/317 on macOS (fpcupdeluxe, FPC 3.2.3). Against
   `89d652a77` (PR #12): 296/296 on Windows aarch64 (FPC 3.3.1), 347/347 on
   Linux aarch64 (WSL, FPC 3.2.2), golden files unchanged. Against
   `5a1fb60fc` (PR #13): 296/296 on Windows x64 (FPC 3.2.2), Windows x86
   (Delphi 7, Delphi 2010), Windows aarch64 (FPC 3.3.1) and with Delphi 13
   Win32/Win64, 335/335 on Debian 13 aarch64 and 354/354 on macOS aarch64
   (FPC 3.2.3), 347/347 on Linux aarch64 (WSL, FPC 3.2.2); golden files
   unchanged, the 45 demo PDFs identical to `2026-10-04_pr9` but for the
   date in two footers. Still against `5a1fb60fc`, PR #14 (HarfBuzz guard)
   and PR #15 (the old POSIX backends replaced by `mormot.lib.freetype` and
   `mormot.lib.harfbuzz`): 296/296 on Windows x64 (FPC 3.2.2) and Windows x86
   (Delphi 7, Delphi 2010), 335/335 on Debian 13 aarch64, 354/354 on macOS
   aarch64 (FPC 3.2.3), 347/347 on Linux aarch64 (WSL, FPC 3.2.2), 296/296
   on Windows aarch64 (FPC 3.3.1); golden files unchanged, the 45 demo PDFs
   of `2026-10-07_pr15` identical to `2026-10-07_pr13` after normalization,
   veraPDF 1.30.2 `ua1` 35/35 and `3u` 5/5. Against `2dce8feb6` and
   `0da9d7adc`, PRs #19 to #21 as one block (checked on #21): 306/306 on
   Windows x64 (FPC 3.2.2) and Windows x86 (Delphi 7, Delphi 2010), 360/360
   on Linux aarch64 (FPC 3.2.3, with fonts-noto-cjk; 348 without), 363/363
   on macOS aarch64 (FPC 3.2.3); golden files unchanged, `pdfcheck` 9/9,
   veraPDF `ua1` and `3u` pass. Against `2f8bf3d76`, PRs #23 to #25 as one
   block (Martin, checked on #25): 368/368 on Windows x64 (FPC 3.2.2) and
   Windows x86 (Delphi 7, Delphi 2010), 366/366 on Linux aarch64, 373/373
   on macOS aarch64; golden files unchanged; `pdfcheck` 9/9 on Linux and
   macOS, 8/9 on Windows - `rtl_demo`, explained in Phase 1 (W2); veraPDF
   `ua1` 35/35, `3u` 5/5.
   `mormot_demo` (SQLite from `static/`) builds and exports on all three
   Windows compilers, the PDFs identical after normalization. FPC warns of
   a duplicate `mormot.lib.uniscribe` (the package's and our copy) — gone
   with step 5
4. ~~**Baseline:**~~ done 2026-10-02: a check session (above) with `--golden-record`, into
   `2026-10-02_phase0-baseline`; Windows (FPC Win64, Delphi 7, Delphi 2010),
   Linux, macOS

   **Windows done** (2026-10-02, `418e85e`, mORMot2 `d60cc6e80`): all
   rebuilt; `test_runner` 279/279 on all three compilers, nine golden files
   each; 24 demo PDFs and three `tagged_unicode` in
   `2026-10-02_phase0-baseline`. Across the compilers
   seven demos are identical after normalization; `chinese_demo` differs
   between FPC and Delphi (Delphi 7 = Delphi 2010) in the subset `cmap` only —
   the 32-bit `fontsub.dll` (`.claude/skills/fonts.md` §3), not a defect.
   Linux and macOS: rebuilt, `test_runner` 318/318 and 337/337, golden files recorded,
   nine PDFs each. The folder: 45 PDFs, five systems. veraPDF on all of them
   (macOS): no errors, the known warnings only; PAC 2024 (Windows): passed
5. ~~**Sven's merge**~~ done (PR #2): the trunk commits to `mormot.ui.pdf`; the
   trunk's `mormot.ui.core` and `mormot.ui.gdiplus` replace the content of
   the copies in `src/core/`, which stay — identical to `d60cc6e80` but for
   `{$I mormot.defines.inc}`, since `src/ui` (`..\mormot.defines.inc`, the
   original `mormot.ui.pdf`/`report`) must not be on the search path; the
   copy of `mormot.lib.uniscribe` dropped (the `mormot2` package ships it).
   Checked against step 4 on all three platforms — it touches `TPdfWrite` and
   the POSIX `GetTtfData`: `test_runner` against the golden files,
   `pdfcheck run` and `compare`; every difference explained (the EMF fixes
   touch no demo). Then README, CHANGELOG (via ROADMAP "To Announce") and
   `CLAUDE.md` Dependencies: trunk only, v0.10.0 the last version for
   2.4-stable

   **Windows done** (merged as `a5dab31`): the compiled leftovers of the
   removed `mormot.lib.uniscribe` copy deleted (38 files; `lazbuild` had
   warned of an orphaned ppu), all rebuilt with FPC Win64, Delphi 7 and
   Delphi 2010, no duplicate-unit warning left. `test_runner` 279/279 on
   all three, every golden file unchanged; 27 PDFs in
   `2026-10-02_phase0-pr2`, `pdfcheck compare` against the baseline: all 27
   identical — PR #2 changes no Windows output. README, ROADMAP "To
   Announce" and `CLAUDE.md`: trunk only. The `mormot2` package folder holds
   no `mormot.ui.*` ppu (`mormot2ui` never compiled here).

   **Linux done** (`d411886`): no `mormot.lib.uniscribe` leftovers — Windows
   only, never compiled there. `lazbuild` warned of orphaned `mormot.ui.pdf`,
   `.core` and `.gdiplus` ppus: `mormot2ui`, compiled once in the
   fpcupdeluxe IDE, had put them into the `mormot2` package folder. Deleted,
   rebuilt with `-B`, no warning left. `test_runner` 318/318, every golden
   file unchanged; nine PDFs in `2026-10-02_phase0-pr2`, `pdfcheck compare`
   against the baseline: all nine identical, before and after the deletion.

   **macOS done** (`43ec3a3`): no `mormot.lib.uniscribe` leftovers. The same
   orphaned `mormot.ui.pdf`, `.core` and `.gdiplus` ppus — `mormot2ui`,
   compiled in the fpcupdeluxe setup; its whole output deleted (15 files,
   with `.controls`, `.grid.orm` and `mormot2ui.ppu`), all rebuilt with
   `-B`, no warning left. `test_runner` 337/337 before and after, every
   golden file unchanged; nine PDFs in `2026-10-02_phase0-pr2`, `pdfcheck
   compare` against the baseline: all 45 identical — PR #2 changes no
   output on any platform
6. The run of step 5, once accepted, is the reference for Phase 1 — no
   session of its own

### Phase 1 — Generic Font Layer

Gist §4–§6, §16. Behaviour unchanged.

**Unit names** (Arnaud, gist, 2026-10-03 - replacing the gist's
`mormot.lib.font*`): the contracts in one unit, the implementations in the
units of their libraries:

| Unit | Content | From |
|---|---|---|
| `mormot.lib.core` | abstract font types and interfaces, registration; later other contracts (UI, printers) | the generic part of `mormot.pdf.types` |
| `mormot.lib.uniscribe` | the GDI font part, the Uniscribe shaper, the FontSub subsetter | `mormot.pdf.gdi`, the Uniscribe and `CreateFontPackage` code of `mormot.ui.pdf` |
| `mormot.lib.freetype` | FreeType bindings and backend | `mormot.pdf.freetype` |
| `mormot.lib.harfbuzz` | HarfBuzz shaping and subsetting | `mormot.pdf.harfbuzz`, `mormot.pdf.hbsubset` |

**Where the code lives** (agreed with Martin 2026-10-04, replacing the plan
of PR #2): the `mormot.lib.*` units in the branch `pdf-font-layer` of
`landrix/mORMot2`, at their final place `src/lib` - `mormot.lib.uniscribe` is
extended in place, where a copy here would shadow the package's unit, as
before PR #2. This repository keeps the PDF units, the tests, the golden
files, `pdfcheck`, the demos and the CI, and builds against a pinned commit
of that branch (Phase 0 step 3); it gets PRs only where it has to follow -
the pin, the PDF units switching to the new interfaces. The branch starts
from the pinned trunk commit and is synchronized with the trunk per
baseline - by merging the trunk in, never by rebasing or force-pushing, so
that every commit pinned here (CI, baselines) stays reachable; the end of
Phase 1 is one PR to `synopse/mORMot2`.

- `Pdf` dropped from names that are not PDF-specific; the PDF types
  (`TPdfFileFormat`, `TPdfStructRole`, the font name constants) stay on the
  PDF side (gist §17)
- **Windows shaping and subsetting behind the interfaces** (done in step W2,
  2026-10-08): Uniscribe and `CreateFontPackage` were called from
  `mormot.ui.pdf`; they are the shaper and the subsetter of
  `mormot.lib.uniscribe` now (not in the gist), and the engine has one path
  for both platforms. The two paths differed in shape, not only in library -
  see `.claude/skills/platform-backends.md`, "Phase 1 Notes"
- **The engine's direct GDI calls behind the interfaces** (done in step W3,
  2026-10-09): the document DC (`FontDC`), font creation and release, metrics,
  character widths, tables and glyph advances by index (the new
  `IFontProvider.GetGlyphAdvance`) go through `mormot.lib.core` on every
  platform; `TPdfFontTrueType` holds a `TFontRequest`, `TFontMetrics` and
  `TFontOutlineMetrics` everywhere. The `TLogFontW` API stays as Windows
  adapters (decided with Sven, three alternatives, as cairo keeps its
  LOGFONT constructors beside the generic ones); the `TLogFontW` constructor
  still creates its font from the whole LOGFONT (`lfWidth`, found by Codex),
  whether it should ignore it as cairo does is left to Phase 5. The EMF code
  casts the DC back to a `HDC`. Output identical (golden files on every platform).
  Intended difference: `GetAndMarkGlyphAsUsed` step 3 - a glyph no character
  maps to, from the public `ShowGlyph` or a shaper giving no advances - now
  gets its width on Linux/macOS too, where it stayed out of `/W` before
  (`/DW` and overlap); HarfBuzz runs, which bring their advances, never went
  there
  - **Accepted difference (rule 1), found by Martin on #25:** `rtl_demo` on
    Windows, line `EXPECTED_2A` (`Expected: U+0628 BA - ...`, shaped because
    Uniscribe calls the em dash complex): the space after `0628` moved from
    the start of one `Tj` to the end of the one before - same glyphs, same
    font, no positioning between them, the same page. W2 itemizes exactly
    the text: `ScriptItemize` on the text with the `#0` gave `0628` at bidi
    level 2 and ` BA ` as items, without it `0628 ` at level 0 and `BA `
    (measured 2026-10-09, Windows 11). The trailing `#0` changed the level
    of the digits, and with it where the space went. PR #23 said "the same
    items": that held for the 15,000 Arabic and Hebrew strings Codex
    probed, which had no digits, not for this line
- **The whole face of a `.ttc` on Windows** (bug fix, 2026-10-09): the
  whole-face embedding read the collection with `'ttcf'`, computed an index
  with `GetTtcIndex` and never used it - the whole collection went to
  `/FontFile2` (9 to 21 MB, no font program; from the trunk original). Now
  `IFontProvider.GetFaceFile` gives the face as one font file on every
  platform (GDI: `TtcFaceIndex` and `ExtractSfntFromTtc`; FreeType: the
  face it loaded), and `GetTtcIndex` is gone
- `libharfbuzz` and `libharfbuzz-subset` stay separately loaded
- The device-context interface moves unchanged, marked transitional

### Phase 1b — Remove the Device Context

Gist §19. Its own phase: the step most likely to change metrics.

- `IFontDC`, `SelectFont`, `CreateDC`, the screen `LOGPIXELSY`
  replaced by a face object that owns its state
- Output identical; every difference explained

**Done** (2026-10-09; design decided with Sven, three alternatives each,
discussed with Codex against Skia `SkTypeface`, DirectWrite
`IDWriteFontFace`, FreeType `FT_Face`, HarfBuzz `hb_face`, cairo, PDFium and
Qt `QRawFont`):

- **`IFontFace`**, reference counted, from `IFontProvider.CreateFace`:
  metrics, character widths, glyph advances, tables and the face file are
  its methods, without a selection. The GDI face owns its HFONT and a
  compatible DC made when first needed; the FreeType face its
  `PFreeTypeFont`. The WinAnsi and the Unicode instance of a font share one
  face. The shaper and the subsetter keep their signatures and get the
  face's `Handle`. The `TLogFontW` constructor takes its face from
  `GdiCreateFace` of `mormot.lib.uniscribe`, from the whole LOGFONT
- `IFontDC`, `TFontDC`, the `FontDC` global, the DC parameter of
  `RegisterFontPlatform` and of `IFontEnumerator.EnumTrueTypeFonts`,
  `IFontProvider.CreateFont`/`DeleteFont`/`SelectFont`/`FontDataError`
  (now the constant `FONT_DATA_ERROR`) and the aliases
  `TPdfPlatformDC`/`IPdfPlatformDC` are gone - the contract was never
  released. New GUIDs for `IFontProvider` and `IFontEnumerator`
- **`ScreenLogPixels`:** `GdiScreenLogPixels` on Windows (the same
  `GetDeviceCaps(LOGPIXELSY)` of a compatible DC), 96 on POSIX - outside
  `mormot.lib.core`; Phase 3 moves it to the canvas adapter. It follows the
  process's DPI awareness: compare demo PDFs only between builds with the
  same `.res` (a Lazarus-made one carries the DPI-aware manifest; 144 at
  150 % scaling where an empty one gives 96 - found while checking this step)
- **EMF** (Windows): `TPdfDocument.EmfDC`, made when first needed; the text
  measure selects the face's HFONT for that call only
- `TPdfTtf.Create` read four tables relying on the font its caller had
  selected: it reads the face now
- A font no backend resolves gives `TPdfNoFace`, whose queries fail, as the
  nil font of the FreeType backend did
- Output identical: golden files on every platform, the Windows demo PDFs
  (same `.res`) against `main`

**Bug fixes** (one PR with the implementation PR, rule 2):

- from Martin's review of #26: when embedding is required and neither a
  subset nor the whole face is available, the save fails
  (`EPdfInvalidOperation`) instead of writing the font without a font file -
  and `Tagged` forces embedding as PDF/A does; the
  bounds of `ExtractSfntFromTtc` cannot wrap on 32-bit; the FreeType side of
  `GetFaceFile` is tested on a `.ttc` (Noto Sans CJK JP on Linux, Hiragino
  Sans GB and Helvetica on macOS); `report_demo` and `mormot_demo` print the
  date of `SOURCE_DATE_EPOCH`, which `pdfcheck run` sets, and `pdfcheck
  compare` names up to ten changed, added or removed objects - paired by
  number, also inside object streams - and counts the rest
- **CFF - a PR of its own after Phase 2's bug-fix PR, done** (decided with
  Sven 2026-10-09/10, branch `pr/cff`): all text of a CFF face through its
  Type0 font, the CIDs of a CID-keyed face as codes, a CID-keyed face as its
  bare CFF (`CIDFontType0C`, PDF 1.3), a name-keyed one as `/OpenType` (PDF
  1.6, refused under PDF/A-1) - no name-keyed-to-CID-keyed rewriter (cairo
  and LuaTeX have one: a project of its own). After the Fable review of the
  whole branch, decided with Sven 2026-10-10 (three alternatives, discussed
  with Codex against iText/OpenPDF, PDFium, LibreOffice, cairo, pdfTeX): a
  name-keyed face first known after the header (`TPdfDocumentGdi`,
  `TGDIPages` stream from the start) sets `/Version /1.6` in the catalog,
  which is written last, instead of raising; an unembedded name-keyed face
  keeps its Latin text in the simple font. How it works: `fonts.md` "CFF
  Faces: Type0 Only". Every commit Codex-reviewed, each test shown to fail
  on the engine before it. Left open: CFF faces the reader refuses, word
  spacing in shaped runs (ROADMAP); veraPDF and PAC on the macOS output (no
  veraPDF here). Checked: `test_runner` 779/779 on Windows (FPC 3.3.1
  aarch64, Delphi 7, Delphi 13 Win32/Win64 - now with a golden baseline of
  their own), 755/755 on macOS M2, 728/728 on Linux aarch64; golden files:
  `cjk_subset` and `arabic_shaped` on every platform (`/W` and `/ToUnicode`
  sorted), `cjk_subset` on macOS three times more (four in all); U+9FA6 of
  Hiragino rendered by PDFKit as CoreText draws it

**Checked** (#28, #29): `test_runner` 506/506 on Windows (FPC 3.3.1 aarch64
and 3.2.2 x64, Delphi 7, Delphi 13 Win32/Win64, Delphi 2010), 477/477 on
macOS M2, 453/453 on Linux aarch64; golden files unchanged; `pdfcheck
compare`: only `report_demo` and `mormot_demo`, by the printed date

### Phase 2 — Raw PDF Without VCL/LCL

Gist §7–§10. `uses mormot.pdf` builds in a console program without a GUI
framework, on every compiler.

- `mormot.pdf.core` and `mormot.pdf.image` only where the boundary is real
  (gist §23)
- ~~`mormot.pdf.font` for the PDF side of fonts~~ deferred, see below
- The `TBitmap`/`TGraphic` image API moves to an adapter — user code changes

**Decided** (2026-10-10, with Sven, three alternatives each, discussed with
Codex against fpPDF, PDFium, Skia, LuaTeX, libHaru, PoDoFo, Ghostscript and
cairo):

- **One engine unit, `mormot.pdf`** (`src/pdf/mormot.pdf.pas`): only the GUI
  parts leave it. No `mormot.pdf.core` or `mormot.pdf.font` in this phase -
  the boundary is not real yet: the font classes use twelve members of
  `TPdfDocument` and the document theirs, `TPdfWrite` shapes text and creates
  the Unicode font, and the objects reach the document's encryption and
  xref. A core/font split would redistribute roughly 4-5k existing lines
  and first needs that coupling removed (gist §7, §23: not for naming
  symmetry). fpPDF keeps writer, objects and fonts in one unit; PDFium and
  LuaTeX tie their fonts to the document as well. The split is reconsidered
  once the coupling is gone (Phase 5 at the latest)
- **Images:** `mormot.pdf` takes raw pixels and encoded JPEG, as libHaru,
  PoDoFo and PDFium take buffers. The contract: width, height, format (RGB24,
  Indexed8 with its palette), row stride and order, buffer length, an
  optional color key - all checked, without overflow. The
  `TBitmap`/`TGraphic` conversion moves to the adapter: JPEG compression
  (GDI+ `SaveInternalToStream` versus recompression, as today) and the
  128-bit reuse hash over the padded rows and the palette, which the adapter
  computes as today, while the lookup and registration stay in the engine.
  Output unchanged: the palette stays indexed, a 24-bit color key stays
  `/Mask`, 32-bit input still drops alpha (`/SMask` would be a new feature),
  the objects keep their order. `mormot.pdf.fpimage` (no caller today) stays
  an optional FPC adapter feeding the same input
- **EMF moves now:** `TPdfDocumentGdi`, `RenderMetaFile`, the EMF form and the
  printer helpers (with `winspool`) go to a new unit `mormot.pdf.canvas`,
  with the bitmap conversion; Phase 3 adds the rest of the `TCanvas` bridge.
  EMF reaches protected state of the document, page and canvas: narrow
  access methods first, then the move
- **Tests first:** images (indexed, RGB, 32-bit, `/Mask`, reuse, both JPEG
  paths, object order) and EMF (recording and rendering) have no tests
  today; they get them before anything moves
- **System colors:** the engine resolves them natively on Windows as today
  (`GetSysColor`); the fixed-value fallback that Delphi on Linux/Android uses
  is not switched on for Windows by removing the graphics units. Colors of a
  framework are resolved in the adapter
- **Renamed now, no wrapper:** the trunk has a different `mormot.ui.pdf`, so
  a compatibility unit of that name would be ambiguous on a search path.
  Class names stay; callers change their `uses` (and the image calls)
- `mormot.pdf.types` stays for this phase; `mormot.pdf` re-exports what a
  caller needs from it - type aliases, the enum values and constants (same
  ordinals), `GetPdfFonts` - so `uses mormot.pdf` alone is enough. The
  security switch and its global exclusion stay
- **Proof:** a console probe with only `uses mormot.pdf` that creates a
  document, draws text and shapes, saves and checks the file; built clean,
  without any LCL/VCL path (FPC), and with its unit list checked (Delphi)

**Done** (2026-10-10, branch `pr/phase2`, one commit per kind of change):

- **Tests first:** `tests/test_pdf_images.pas` - `TBitmap` in every pixel
  format, reuse (palette and row padding in the key, on the VCL), the color
  key, a clipped draw, both JPEG ways, `TPdfDocumentGdi` with the comments,
  `RenderMetaFile` - as golden files, recorded on the commit before anything
  moved; `pdf_inspect` keeps `/DCTDecode` image data as it is
- **Raw input in the engine:** `TPdfImagePixels` (`ipfRgb24`, `ipfBgr24`,
  `ipfBgrx32`, `ipfIndexed8` with its palette; stride, also negative; buffer
  size; color key), `TPdfImage.CreatePixels`/`CreateJpeg`/`Hash`,
  `TPdfDocument.CreateOrGetImage(Pixels)`/`RegisterImage`/`DrawImage`, the
  input checked before anything reaches the xref; `TPdfImageRawTests` on
  every compiler
- **The changed API:** `CreateOrGetBitmapImage(Doc, Bitmap, ..)` replaces
  `Doc.CreateOrGetImage(Bitmap, ..)`, `CreateGraphicImage(Doc, Graphic, ..)`
  replaces `TPdfImage.Create(Doc, Graphic, ..)` - functions of
  `mormot.pdf.canvas`
- **The move:** `mormot.pdf.defines.inc` (the switches, shared);
  `TPdfFormXObject`, the engine's side of `TPdfForm` (a page lists the fonts
  of a form it draws - `FormFonts` tests it); then the EMF code reaching the
  engine through implementation-local access classes, as `TORHook` in
  `mormot.core.json` - **not the "narrow access methods" planned above**:
  the members were protected already, so no engine member changed its
  visibility and no public accessor was added (Codex, three alternatives;
  the EMF state leaving `TPdfCanvas` for `TPdfEnum` is a later step); then
  `mormot.pdf.canvas` by a pure move, every removed block verbatim
- **No GUI import left:** `MM_TEXT` and `GetSysColor` from the windows unit
  on Windows, fixed Windows defaults on POSIX - on FPC POSIX they came from
  the LCL theme before; `TPdfVclCanvas` resolves its colors with
  `ColorToRGB` first, so only a program that hands the engine a system color
  directly sees it (ROADMAP "To Announce")
- **Renamed:** `src/pdf/mormot.pdf.pas`, with `mormot.pdf.canvas`, `.types`,
  `.fpimage` and `defines.inc` beside it; `mormot.ui.*` stay in `src/core`.
  The XMP toolkit name `x:xmptk="mormot.ui.pdf"` is output and stays - a
  change for later, with its golden files
- **`uses mormot.pdf` is enough:** it re-exports `TPdfFileFormat`,
  `TPdfStructRole`, `TPdfFontEnumCallback`, every `pdf1x` and `psr*` value,
  the `PDF_FONT_*` constants and `GetPdfFonts`; the demos dropped
  `mormot.pdf.types`
- **Proof:** `layer1_demo` - `uses mormot.pdf` alone, no `Interfaces`, no LCL
  package - built with `fpc -n` (RTL and mORMot paths only) on Windows and
  Linux: no LCL unit loaded, its PDF equal to `main`'s; with Delphi 7 too.
  A console probe (create, draw, save) the same way
- **Found** (bug-fix PR): `TPdfForm.Create(DocGdi, MetaFile)` raises an access
  violation (its page has no MediaBox), and raising without a current page
  leaves the canvas on the page it frees; with the LCL, pf1bit/pf4bit/pf8bit
  bitmaps raise `EPdfInvalidValue` where the VCL indexes them; by the Fable
  review: `TPdfDocumentVcl.Create` never has its `AEncryption` parameter
  (`mormot.ui.pdfcanvas` does not see `USE_PDFSECURITY`), and `BitmapHash`
  reads each row as a DIB pads it, past the last row's end on an LCL that
  aligns rows less. An empty `TBitmap` gives no image now (`''`), where a
  0 x 0 image was written (ROADMAP "To Announce")
- **Checked:** `test_runner` 584/584 on Windows (FPC 3.3.1, Delphi 7, Delphi
  13 Win32/Win64), 531/531 on Linux, 555/555 on macOS, golden files
  unchanged after every commit - except Delphi 13 from the access classes to
  the fixes after the Fable review: the inline getters of `TPdfDocumentGdi`
  used the implementation-local `TPdfCanvasAccess` (E2441), and the build
  script ran a stale executable; the 7 runnable demo PDFs of Windows FPC
  equal `main`'s (`pdfcheck compare`; `mormot_demo` lacks an aarch64 sqlite3
  library). Reviewed by Codex commit by commit and by Fable on the whole
  branch. Open: Delphi 2010 (Martin), PAC/veraPDF at the end of the phase,
  Delphi 13 Linux64/Android64 (the community)

**Bug fixes** (Phase 2's bug-fix PR; the CFF series (see Phase 1b) follows
as a PR of its own - decided with Sven 2026-10-10, so that Martin gets the
smaller fixes first): the
message of a face that cannot be embedded names its style, the cause and,
for plain `EmbeddedTtf`, the way out (Martin on #29)

Decided for them (2026-10-10, with Sven; discussed with Fable and Codex,
the LCL measured by Fable on win32, GTK2 and Cocoa):

- **LCL bitmaps of 1, 4 and 8 bits:** on the measured win32, GTK2 and
  Cocoa paths a bitmap set to pf4bit or pf8bit is 8-bit gray, pf1bit 1-bit
  mono, and `GetPaletteEntries` returns 0 - no palette to read. The adapter writes the gray bytes as `ipfIndexed8` with a
  gray ramp (pf1bit expanded to 0/255): the structure the VCL writes, no
  engine change. `/DeviceGray`, as PDFium, cairo, Qt and Skia write it, is a
  feature for later
- **LCL colors:** GTK2 and Cocoa hold pf24bit in 32 bits and pf32bit as
  R,G,B,A (GTK2) or A,R,G,B (Cocoa), where the adapter reads Windows' B,G,R -
  the pixels of such bitmaps in a Linux or macOS PDF are misread (JPEG
  passthrough is not affected); older than Phase 2.
  The adapter reads `RawImage.Description`: the layouts of a Windows DIB go
  through as they are, the others are repacked to RGB through
  `TLazIntfImage`; to be tested against `TLazIntfImage.Colors`, not against
  the adapter's own assumption
- **`TPdfForm`:** a page without a document gets a MediaBox (in the engine:
  `TPdfFormWithCanvas` has the same fault), the form `/Resources` with
  `/XObject`, and the canvas state is saved and restored field by field, also
  without a current page; outlines, bookmarks and links of the metafile are left out in
  a form
- **`TPdfDocumentVcl`'s encryption parameter:** `mormot.ui.pdfcanvas`
  includes `mormot.pdf.defines.inc`. That `TGDIPages.ExportPDF` ignores
  `Protect` and `Encrypt` is a missing feature (ROADMAP, Phase 4)
- **The bitmap reuse key:** on the LCL over `RawImage.Description.BytesPerLine`
  bytes per row (the VCL unchanged), and it includes the color key

### Phase 3 — Canvas Adapter

Gist §11. `mormot.pdf.canvas`: `TPdfDocumentVcl`, `TPdfVclCanvas` - joining
the bitmap conversion and EMF that Phase 2 moved there.

### Phase 4 — Reporting

Gist §12, §13. `mormot.pdf.report` and `mormot.pdf.report.preview`.
Needs the decision on the trunk's existing `TGdiPages` first.

### Phase 5 — Cleanup

Gist §20. Transitional names and aliases removed, unit splits reviewed.

---

## Outside the Phases

Process, agreed in the forum:

- Tests into `mormot2tests` as `test.pdf.*.pas`
- Demos: place in the trunk (`ex/`?)
- ~~`zugferd_demo`: the KoSIT invoice XML (Apache-2.0) replaced by a sample
  under the mORMot licence (Sven)~~ done: `Gesamtbeispiel` of XRechnung for
  Delphi; the demo reads several VAT rates, billing period, due date and
  bank accounts now
- ~~Licence headers, `OSWINDOWS`/`OSDARWIN`, ASCII-only sources, roadmap
  references out of the comments (Sven)~~ done before Phase 1: every own
  unit has the mORMot header and description block, comments are English
  ASCII without roadmap references; code unchanged (compared without
  comments, the define names normalized). One effect for Delphi: mORMot2
  defines `OSDARWIN` from Delphi's `MACOS` too, while FPC's `DARWIN` was
  never set there - Delphi on macOS (untested, not a target) now takes the
  macOS branches: font names, `.dylib` names, font folders. Still open,
  each at its own time:
  - **the defines include** by relative path (`..\mormot.defines.inc`)
    once the units sit in the trunk's `src/pdf`; by name until then
  - **formatting** to the trunk's style (`result`/`exit`/`integer`, no
    column alignment, `begin`/`else` layout) as a PR of its own right
    before the phase that moves the unit: `mormot.ui.pdf` and
    `mormot.ui.pdfcanvas` before Phase 2, `mormot.ui.report` before
    Phase 4. `mormot.pdf.types` and the backends get it as they become
    `mormot.lib.core` and the library units in Phase 1 - no work on code
    about to be replaced

## Open Decisions

- The trunk's existing `TGdiPages` (`TScrollBox`, preview built in) — before
  Phase 4
- Golden files in `mormot2tests`: here they are per machine and not
  versioned (Phase 0 step 2) — how a baseline without files in the
  repository serves the trunk's tests
