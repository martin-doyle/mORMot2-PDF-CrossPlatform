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
   `lazbuild` warns `Duplicate unit ... orphaned ppu` then. No project
   needs the `mormot2ui` package: the projects find `mormot.ui.core` and
   `.gdiplus` in mORMot2's `src/ui` by path (`$PkgDir(mormot2)/../../src/ui`
   in the `.lpi`, `%MORMOT2%\src\ui` for Delphi), and the package would write
   the trunk's `mormot.ui.pdf` into the output folder it shares with
   `mormot2`
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
   `IFontFace` replaces the device context), then `9cf8add51` (2026-10-13,
   fonts from memory: `RegisterFontData`, the test fonts' first step), then
   `c68fc85aa` (2026-10-14, symbol faces measured by their symbol cmap), then
   `c53462a61` (2026-10-15, the fallback step: `fsoMissingGlyphs`,
   `IFontRunShaper`, HarfBuzz script runs), then `b2d659d44` (2026-10-15,
   Uniscribe keeps the missing-glyph check when its font properties fail).
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
  an optional FPC adapter feeding the same input (removed in Phase 5)
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
  `Protect` and `Encrypt` is a missing feature (ROADMAP: refused in Phase
  4's bug-fix PR, implemented after the freeze)
- **The bitmap reuse key:** on the LCL over `RawImage.Description.BytesPerLine`
  bytes per row (the VCL unchanged), and it includes the color key

**Checked by Martin** (#31, #32 and #33 merged 2026-10-11; the check session
of the phase): `test_runner` 779 on Windows (FPC 3.2.2 x64, Delphi 7, Delphi
2010), 728 on Debian 13 aarch64, 755 on macOS M2; golden files and demo PDFs
against `b2f58fa` as announced; veraPDF 1.30.2 `ua1` and `3u` pass on all
five systems, PAC 2024 OK.

**Follow-ups** (his five points on #33, one PR): Delphi 2010's W1035 on
`CreateGraphicImage` (a `raise` inside `try..finally`: Delphi 7 and 2010 lose
`result` there, a `RaiseU` call does not); the CFF test bytes built as
`RawByteString`, not through `string` literals (W1057/W1058; `$8B` is a lead
byte on cp932); `FillBitmap` fills `BytesPerLine` on the LCL, so the 32-bit
pf24bit rows of GTK2 and Cocoa are filled to the end (`images_bitmap` and
`images_jpeg` change there); FPC's "ScanLine is not portable" off in the
adapter and the image tests; `pdf_inspect` writes the offsets of an object
stream and its `/First` as 0, like those of an xref, so a grown member no
longer shows as a change of the stream header - `/First` only where the
header was read, and `ComparePdfText` compares the members' bounds when the
text is equal (two findings of Codex). Checked: `test_runner` 792/792 on
Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi 13 Win32/Win64; golden files
unchanged, no warning of Delphi 7 or 13 in our files), 741 on Linux
aarch64 and 768 on macOS M2, both with `images_bitmap` and `images_jpeg`
changed

### Phase 3 — Canvas Adapter

Gist §11. `mormot.pdf.canvas`: `TPdfDocumentVcl`, `TPdfVclCanvas` - joining
the bitmap conversion and EMF that Phase 2 moved there.

**Decided** (2026-10-12, with Sven, three alternatives each, discussed with
Codex and Fable; Fable's probes built with Delphi 7 and FPC/LCL):

- **One adapter unit:** the bridge joins `mormot.pdf.canvas` as its first
  section (bridge, bitmaps, EMF), under `USE_GRAPHICS_UNIT` like the
  bitmaps; `PDF_CANVASVIRTUAL` stays a local define of the unit (a compiler
  fact, not a project switch). Skia keeps canvas-to-PDF and bitmaps in one
  module; PDFBox-Graphics2D is an adapter apart from the engine - the cut
  this project has. EMF as a unit of its own is a Phase 5 question
- **`mormot.ui.pdfcanvas` is deleted, no wrapper:** it was never in the
  trunk, and a wrapper would have to go again before the 2.5 merge; class
  names stay, callers change their `uses` (mORMot 1 to 2 renamed units the
  same way)
- **The report takes its PDF types from `mormot.pdf`:** `mormot.ui.report`
  puts `mormot.pdf` first in its interface `uses` - later units win for
  `TRect`/`TPoint`/`Rect`/`Point`, its own `psA4` wins over any used unit -
  and its re-exports point at the engine; the adapter exports no PDF/A
  levels, page modes or Factur-X metadata (gist §14: the report depends on
  `mormot.pdf`; Phase 4 needs it anyway). A program still never puts
  `mormot.pdf` beside `mormot.ui.report` (now `mormot.pdf.report`)
- **`ScreenLogPixels` leaves the engine's platform code** (the Phase 1b
  promise): `TPdfDocument` starts at 96 on every platform, a setter keeps
  the canvas factors in step, and `TPdfDocumentVcl` and `TPdfDocumentGdi`
  set the screen's value (`GdiScreenLogPixels`) on Windows. The bridge reads
  it at the first page and keeps its scale: set it before the first page.
  Accepted difference: in a DPI-aware Windows
  process a plain `TPdfDocument` reads 96 instead of the screen's 120 or 144;
  output through the adapters, the golden files (96) and the demos unchanged
- **Moved as it is:** the bridge's measuring DC (the fallback for a face no
  backend resolves, Delphi's `PenPos`) and `PDF_CANVASVIRTUAL` are
  behaviour; changing them is a Phase 5 item
- **Formatting:** the bridge to the trunk's style in place before it moves
  (column alignment only, `git diff -w` empty); `mormot.pdf` and
  `mormot.pdf.canvas` in one formatting PR before the 2.5 merge, with
  Arnaud's list
- **Tests first,** on the unchanged bridge: golden cases for `Polyline`,
  `Polygon`, `FillRect`, fractional text and rectangles, two pages with a
  DPI set before the first, `Draw`/`StretchDraw` with reuse, the tagging
  calls and the alpha setters of `TPdfDocumentVcl`; smoke tests for the
  integer rounding of the metrics and the measuring-DC fallback
- **Order of the commits:** decisions - tests - formatting - the report's
  `uses` - `ScreenLogPixels` - the move, mechanical (removed blocks against
  added ones) - docs. The two changes of meaning come before the move, so
  that the move stays a move

**Done** (2026-10-12, branch `pr/phase3` on PR #34, one commit per step,
each Codex-reviewed): the tests first (four golden cases, `images_bridge`
with its matrices compared as numbers - their digits differ between the
32-bit and the 64-bit compilers - and smoke tests; their baselines
recorded on `3b56824`, the commit of the tests, on all five systems); the
bridge formatted in place; the
report's PDF types from `mormot.pdf`; `ScreenLogPixels`; the move - 714
lines verbatim, the old unit deleted. Checked: `test_runner` 827/827 on
Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi 13 Win32/Win64), 774 on Linux
aarch64, 801 on macOS M2, golden files unchanged after the new cases were
recorded; the 7 demo PDFs of Windows FPC equal the state before Phase 3
(`pdfcheck compare`; `mormot_demo` needs an aarch64 sqlite3). Found for the
bug-fix PR: `TGDIPages` draws bitmaps past the bridge (`report-engine.md`).
Open: Delphi 2010, Delphi 13
Linux64/Android64 (engine only, the adapter is not for them), PAC/veraPDF
at the end of the phase

**Bug fixes** (Phase 3's bug-fix PR, branch `pr/phase3-fixes`, each
Codex-reviewed): `TPdfVclCanvas.Create` without the stale comment and the
dead branch the verbatim move kept; the tests count with mORMot's
`CountOccurrences` instead of five copies of `CountOf`; Martin's two points
on #35 - `mormot_demo` without W1057, and with sample data of its own on a
fresh database (decided with Codex and Fable: computed in `server.pas`, no
binary and no DBDEMOS data in git; on the way, its server constructor was
found never called by `TRestClientDB`). The bitmaps past the bridge are
settled on `feature/invoice-demo`, whose `TGDIPages` draws them through
`Bridge.StretchDrawBounds`; they reach `main` with that branch

### Phase 4 — Reporting

Gist §12, §13. `mormot.pdf.report` and `mormot.pdf.report.preview`.

**Decided** (2026-10-12, with Sven, three alternatives each, discussed with
Codex and Fable; Fable's trial merges in a scratch worktree):

- **A clean break with the trunk's `TGdiPages`:** our engine becomes
  `mormot.pdf.report` and keeps its class name; the trunk's
  `mormot.ui.report` goes at the 2.5 merge, as Arnaud announced, with a
  migration note. No wrapper: the trunk's unit is Delphi and Windows only (an
  empty unit on FPC and POSIX), no unit, example or test of the trunk uses
  it, and of the ~130 names of its public methods and properties ~113 have
  no counterpart here - the column model, header/footer lists, groups,
  metafile pages - while shared names such as `DrawTextAt`, `PaperSize`,
  `Orientation` and `ExportPdf` differ in signature or units (millimetres
  against 1/100 mm). A wrapper would be a port. mORMot 1 to 2
  renamed `mORMotReport` the same way, without a compatibility unit;
  FastReport ships VCL and FMX as separate products
- **Moved, not formatted:** Phase 4 is `git mv` plus unit names and the
  references, the code verbatim; Martin's `feature/invoice-demo`, which
  adds ~390 lines to the report, merges cleanly over the move (git follows
  the rename; trial merge). Formatting conflicts with it (a stand-in pass:
  9 conflict hunks), and Martin starts Markdown on the same file, so it comes
  right after his branch has landed, at the latest before the 2.5 merge,
  like `mormot.pdf` and `mormot.pdf.canvas`
- **Scope as it is:** `mormot.pdf.report` keeps `Graphics` (`TColor`,
  `TFontStyles`, `RenderPageToCanvas`); the gist's boundary for the first
  merge is no `Forms` and no `Printers` (§12, §23). The preview stays
  LCL-only, a Delphi preview stays R-20 steps 7 and 8. The trunk's folder
  rule (`FOLDER-DEPENDENCIES.md`) and the Lazarus package for `src/pdf` come
  with the 2.5 merge

**Done** (2026-10-12, branch `pr/phase4`, stacked on Phase 3's bug-fix PR,
each commit Codex-reviewed): the decisions; the move - both units verbatim
but for their names, callers, docs and skills renamed, ROADMAP "To
Announce". Checked: `test_runner` 827/827 on Windows (FPC 3.3.1 aarch64,
Delphi 7, Delphi 13 Win32/Win64), 774 on Linux aarch64, 801 on macOS M2,
golden files unchanged; `pdfcheck compare` against the state before: the 7
demo PDFs of Windows FPC (`mormot_demo` needs an aarch64 sqlite3), the 8
of Linux and the four report demos of Delphi 7 unchanged. Open: Delphi 2010, PAC/veraPDF at
the end of the phase. `src/core` now holds only the copies of the trunk's
`mormot.ui.core` and `mormot.ui.gdiplus`; since no other unit of ours
shares a name with the trunk's `src/ui` any more, whether `src/ui` on the
search path can replace the copies is a Phase 5 question (it can: Phase 5
step 2 removed them)

**Bug fixes** (Phase 4's bug-fix PR, branch `pr/phase4-fixes`, decided
with Sven after Codex and Fable, three alternatives each):
`TGDIPages.ExportPDF` raises when `Protect` or `Encrypt` is true instead of
writing an unprotected file - encryption itself after the freeze, with the
trunk's `ExportPdfEncryption*` properties; it raises on any export error and
on no page, and writes the file only after the export succeeded in memory
(a temporary file renamed over the target was tried first: it lost the
file's permissions on POSIX, among other cases); `ExportPdfStream` keeps
returning false and gets the trunk's `aRaiseException`; a failed export no
longer leaves `fActivePdfDoc` on the freed document. iText, PDFBox and ReportLab raise as well where a
requested protection cannot be applied

### Phase 5 — Cleanup

Gist §20. Transitional names and aliases removed, unit splits reviewed.

**Decided 2026-10-17** (Sven, after an inventory by Codex and Fable; each
step its own PR, output byte-equal):

1. **`mormot.pdf.types` merged into `mormot.pdf`** - done: its PDF types
   (`TPdfFileFormat`, `TPdfStructRole`, `PDF_FONT_*`, `GetPdfFonts`, same
   ordinals) are declared in `mormot.pdf`, which re-exported them; the nine
   former font type names (no user in this repository, its tests, demos or
   XRechnung for Delphi) and the unused `TPdfFontEnumCallback` are gone
   with the unit
2. **The copies `src/core/mormot.ui.core` and `mormot.ui.gdiplus` removed**
   - done: they differed from the fork's `src/ui` only by the defines
   include; the `.lpi` take `$PkgDir(mormot2)/../../src/ui` (checked with
   `lazbuild` on Linux by a project that compiles `mormot.ui.core` through
   it - our projects compile the two units on Windows only; `lazbuild` on
   Windows not run, the local one reads a stale configuration), the Delphi
   scripts `%MORMOT2%\src\ui` and `test_runner.dproj` `$(MORMOT2)\src\ui`;
   no unit of ours is named `mormot.ui.pdf` any more, so the trunk's
   originals there are never taken; `layer1_demo` needs neither
3. **`mormot.pdf.fpimage` removed** - done: no caller in this repository,
   its tests and demos, the fork or XRechnung for Delphi; shipped in v0.10.0
   (as `src/core/mormot.pdf.fpimage.pas`), so "To Announce" says what
   replaces it: FPImage in the program, `TPdfImagePixels` for the pixels
4. **The review recorded here** - done: what stays and why (below);
   `reference/` deleted - its `mormot.ui.pdf.pas` was the trunk's at
   63d06371a (2026-03-08) with two local edits (`MilliSecsPerDay`, a
   commented-out `EMR_ALPHABLEND` branch) and trailing blanks, its
   `mormot.ui.report.pas` the trunk's from a931cdbdc until 7f330f690
   changed it; the skills and ROADMAP cite the trunk commit instead; the
   migration note for users of the trunk's units is `docs/MIGRATION.md`

**What stays, and why** (the inventory of Codex and Fable, 2026-10-17):

- **The unit split:** `mormot.pdf` (no VCL/LCL), `mormot.pdf.canvas` (the
  `TCanvas` bridge, bitmaps, EMF), `mormot.pdf.report` (no `Forms`, no
  `Printers`) and `mormot.pdf.report.preview` (both) - each cut is a GUI
  dependency, the gist's boundary (§12, §23). EMF stays in
  `mormot.pdf.canvas`; the EMF state the engine still holds (`fEmfDC`, the
  mapping and world transform, `EmfDC`) and the core/font split of
  `mormot.pdf` are reconsidered together after the merge, once that
  coupling is gone - code changes, not a cleanup
- **The switches:** `mormot.pdf.defines.inc` (constructor signatures,
  security, Uniscribe, GDI+, metafiles); `PDF_CANVASVIRTUAL` (`override`
  against `reintroduce`, a compiler fact) and `PDF_HASVCLCANVAS` (the
  tests: is there a VCL/LCL). None is a migration flag. The include's
  redundant POSIX `undef` block goes with the relative include at the move
- **Names that are real classes, not aliases:** `TPdfDocumentGdi` (the EMF
  path, with tests), `TGDIPages`
- **Caller contracts, cheap to keep:** `UseUniscribe` (the one shaping
  switch, HarfBuzz too), `GeneratePdf15File` (wraps `FileFormat`),
  `PdfAMetadaExtension` (the trunk's spelling), the `TLogFontW` constructor
  that keeps `lfWidth` and the other native fields (dropping them changes
  behaviour), `FindOrAddUsedWideChar` (until R-32 step 2)
- **The re-exports of `mormot.pdf.report`:** PDF/A levels,
  `TPdfFileFormat`, `afr*`, page modes, `PdfMetadataFacturX` - one unit
  per layer (CLAUDE.md)
- **The report's older API:** the positioned overloads, the table API
  beside `TTableLayout`, `REPORT_FONT_*`/`GetReportFonts`, `DrawTextAt` -
  callers use them; "older" alone is no reason
- **`mormot.lib.*`:** the agreed final names; the Windows-shaped `tm*`,
  `otm*` and `abc*` fields of its records stay - renaming them costs every
  backend and gains nothing now
- **Left for the formatting PRs** (source, no output): a stale
  `UseSetTextJustification` in a comment of `mormot.pdf.canvas` (in the
  trunk's original too), the unused POSIX `LOGPIXELSY` of `mormot.pdf`,
  and `IFontProvider.GetFaceFile` in a comment of `mormot.lib.core`, which
  is `IFontFace` now

**At the move, not now:** `x:xmptk="mormot.ui.pdf"` becomes `mormot.pdf`
(the only change of output, one new baseline on every machine), the
defines include by relative path, the formatting of tests and demos.

---

## Outside the Phases

- **R-32 step 1 during the freeze** (decided 2026-10-17 with Sven, Codex
  and Fable): the used characters keyed by code point instead of UTF-16
  unit (ROADMAP R-32). An internal change, no feature: golden files on
  every system and the demo PDFs (pdfcheck, Windows) identical, the public
  methods kept. Steps 2 and 3 (supplementary characters drawn, shaped
  source text) wait for the end of R-28 as planned.

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
    column alignment, `begin`/`else` layout): `mormot.pdf.types` and the
    backends got it as they became `mormot.lib.core` and the library units
    in Phase 1; Phase 2 moved `mormot.ui.pdf` verbatim. Now: the bridge in place
    before Phase 3 moves it, `mormot.pdf` and `mormot.pdf.canvas` in one PR
    before the 2.5 merge (Arnaud expects more formatting), the report
    (`mormot.pdf.report` since Phase 4) after `feature/invoice-demo` has
    landed, at the latest before the 2.5 merge (decided for Phase 4).
    These PRs also bring the existing code to the source form of
    `CLAUDE.md` (binding since 2026-10-14), measured that day: banners
    missing in `mormot.pdf.fpimage`, `.report`, `.report.preview`,
    `.types` (`.fpimage` and `.types` gone in Phase 5), and written `{****` without the space in `mormot.pdf` (8) and
    `mormot.pdf.canvas` (4); `///` missing on 2 of 16 unit-level routines
    of `mormot.pdf`; `raise Exception.Create` 10 times in
    `mormot.pdf.report`, once in `mormot.pdf` (the PDF/A font fallback,
    gone with the fallback step: `EPdfInvalidOperation` since 2026-10-15) and
    once in `zugferd_demo` (`EPdfReport` in the report, `aRaiseException`
    in the demo: "Exceptions, done" below - a change for callers
    that catch by class, so "To Announce"); `with` outside comments and
    strings 57 times in `mormot.pdf`, 64 in `mormot.pdf.canvas` (mostly
    from the trunk's original), twice in `mormot.pdf.report`, 10 times in
    the tests, twice in `mormot.lib.harfbuzz`; no licence line in any unit or program of
    `tests` and `examples`, no overview block or banner in the test units,
    no `///` head in six demo units (both `uReport`, both main forms,
    `server`, `data`). Fields without `f`: `TPdfWrite.B`, `BEnd`, `BEnd4`
    (from the original) and `TPdfEnum.Canvas`, `Obj`, `nDC`, `DC`
    (`mormot.pdf.canvas`)

    **Decided** (2026-10-15, with Sven, three alternatives each, discussed
    with Codex and Fable; Martin: one PR with several commits): all six
    units of `src/pdf` in one PR, the report included now that
    `feature/invoice-demo` no longer holds it back; one commit per kind of
    change; alignment removed where the trunk does not keep it (record and
    class fields, the `:=` blocks of our own units) and kept where it does
    (const tables, the short `:=` blocks of the trunk's original in
    `mormot.pdf` and `mormot.pdf.canvas`); `with` and the field renames
    are code, not form: a PR of their own after this one, and the
    exceptions another; the tests and the demos when they move to
    `mormot2tests` and `ex/` (Martin, 2026-10-17: the source must be
    formatted, the tests should, the demos could; at the move is fine,
    priority 2).

    **Done** (branch `pr/format`, from main after #53): four commits
    generated by a formatter kept outside the repository, so that a change
    of main is formatted again rather than merged by hand - whitespace,
    the trunk's spelling (`result`, `integer`, `true`, `inc`, `length`,
    `SizeOf`..., the RTL and LCL units of `uses` in lower case; never a
    name the unit declares, whose spelling may be RTTI), one statement per
    line, and the comments: banners, overview blocks naming them, `///` on
    every public declaration but what the trunk leaves undocumented too
    (forward declarations, helper pointer and array types, re-exports,
    overrides), the development-phase labels out of the report's
    comments. Each of the four commits is proven against its parent, not
    only tested: a Pascal lexer compares the token streams of every
    `{$ifdef}` branch - equal for whitespace and layout; for the case
    commit but the respelled names, for the comment commit but a `type`
    after a new banner - and FPC compiles the same object code from it:
    every unit equal but for the COFF timestamp on Windows aarch64 (FPC
    3.3.1; `mormot.pdf.fpimage` is POSIX-only, empty there), byte-equal on
    Linux aarch64 (FPC 3.2.2) - built `-O1 -Sa-` without debug
    information, the default defines. The `{$ifndef FPC}` branches have
    the token comparison and the Delphi builds behind them: `test_runner`
    1135/1135 with Delphi 7 and Delphi 13 Win32/Win64 on the result, as
    with FPC on Windows (1135), Linux (1137) and macOS (1170), golden
    files compared equal. The tools stay outside the repository.
    `.git-blame-ignore-revs` lists the four commits: merged as they are,
    not squashed or rebased, or the list must follow. Left for their own
    PRs: `with` (122) and the fields without `f`; `raise Exception` in the
    report (10) and `zugferd_demo` (1)

    **No `with`, done** (branch `pr/no-with`, one commit per unit, on the
    fallback step's bug-fix PR): the 122 `with` of the report (2),
    `mormot.pdf` (56) and `mormot.pdf.canvas` (64) written out, then the
    seven fields renamed: `TPdfWrite.fB`, `fBEnd`, `fBEnd4`, `TPdfEnum.fCanvas`,
    `fObj`, `fDC`, `fDCIndex`. A scanner listed for each `with` the names
    bound to its object - from the type declarations of the unit, of
    `mormot.pdf`, `mormot.lib.core`, `mormot.core.data` and FPC's Windows
    records - and those a member of Self, a local or a parameter shadows;
    the canvas unit was rewritten by a token-aware tool from those lists,
    function results as locals. The renames went through the compiler:
    the declaration first, then each use FPC reported. Object code is no
    proof here (a `with` evaluates its object once): tests and golden
    files unchanged on every compiler, the EMF ones on Windows. Found on
    the way, kept as it was: `TPdfWrite.AddGlyphFromChar` selects the
    fallback font on `TPdfDocument.Canvas`, the page canvas, not on the
    canvas it draws on - they differ for a form XObject; a fix of its own
    (done, below).

    The eight `with` left in the test units (Martin, #57) are written out
    in the follow-up to #57 and #58, by hand: record copies and prefixes.
    The two of the Android host form `tests/delphi13/android` followed;
    not built for Android64 here. The unit does not compile for Win64
    (`LoadFreeType` is POSIX-only; E2250 on its `Synchronize` and `Queue`
    calls): Delphi 13 Win64 stops on the same three errors before
    and after, none in the changed lines. The six `with` of the trunk
    copies in `src/core` stay, as the trunk has them.

    **Exceptions, done** (branch `pr/exceptions`, on `pr/no-with`): the
    report's 10 `raise Exception.Create` and 4 `ESynException` raises are
    `EPdfReport.RaiseUtf8('%.Method: reason', [self])`, the trunk's form;
    `EPdfReport = class(ESynException)` is new in `mormot.pdf.report` -
    decided with Codex and Fable: the trunk's `mormot.ui.report` has
    `EReport`, but both units exist until the 2.5 merge, and a caller
    catching the old unit's class would not catch the new one. Each misuse
    has a `CheckRaised` in `TestMisuseRaises`. `zugferd_demo` passes
    `aRaiseException` instead of raising `Exception` itself. The two
    `{$IFDEF DEBUG}` asserts of `NormalizeX`/`NormalizeY` are gone (they
    never ran in a release build, through the RTL's `Format`; the two
    functions followed in the follow-up to #57 and #58); the two
    `Assert` in `TPdfEnum` (`mormot.pdf.canvas`) are the trunk's code and
    stay - the rule covers the errors a caller sees, not internal checks.
    `on E: Exception` handlers only catch and stay as they are

    **`AddGlyphFromChar` on its own canvas, done** (branch
    `pr/glyph-canvas`, on `pr/exceptions`): the finding of the `with`
    removal. It chose the fallback font and flushed through
    `TPdfDocument.Canvas`; `SetFont` with a font index only returns the
    font, so the output did not depend on it, but it read
    `doc.Canvas.fPage.FontSize` - nil before the first `AddPage`, so
    fallback text in a form XObject drawn before the first page raised an
    access violation (`TestFormFallback`). The drawing canvas now, as
    `AddShapedFallback` already did
- **Into the trunk after mORMot 2.5** (Arnaud, gist, 2026-10-11): the trunk
  is in its 2.5 release cycle, so the work stays in the branches until 2.5
  is out and merges then; the trunk's old `mormot.ui.pdf` and
  `mormot.ui.report` are removed at that point
- **Test fonts, then a subsetter of our own** (proposed to Arnaud
  2026-10-12, discussed with Codex and Fable): before the merge, faces
  loaded from a file or from memory (`FT_New_Memory_Face`,
  `AddFontMemResourceEx`) and small open-licensed or synthetic test fonts,
  so that the font tests run alike everywhere. After the merge, as the
  first follow-up: a pure-pascal `glyf` subsetter that keeps glyph IDs and
  copies glyphs verbatim (as iText does, and Skia through HarfBuzz), the
  default on every platform; hb-subset stays for CFF. FPC's
  `fpttfsubsetter` does not fit: FPC-only, `glyf` only, code points in and
  renumbered glyphs out

  **Decided** (2026-10-13, with Sven, three alternatives each, discussed
  with Codex and Fable):
  - **Registration in `mormot.lib.core`:** `RegisterFontData(Data,
    FaceIndex)` keeps the bytes and reads family and style from the face's
    `name` and `OS/2` tables, and the enumerators list the registered names.
    FreeType's `CreateFace` asks the registry first and opens a registered
    face with `FT_New_Memory_Face`, the bytes kept alive with the face. GDI
    installs the face when it is registered (`AddFontMemResourceEx`,
    through a hook `mormot.lib.uniscribe` sets): Uniscribe and FontSub need
    a real GDI font, and `GdiCreateFace` reaches `CreateFontIndirectW`
    without the provider. System fonts stay the default; in the backends a
    registered name comes first (a test provider such as `TFakeProvider`
    answers its own names before it). Register before a document exists:
    the document reads the font list once. No decorator swapped into the
    `FontProvider` global - `UnregisterFreeType` clears only its own
    provider, so a wrapper would stay there after FreeType is unloaded, and
    it would miss `GdiCreateFace`; no method added to `IFontProvider`, which
    every provider, the test fakes too, would have to implement; not per
    document, since `TGDIPages` measures before export. As QuestPDF's `FontManager.RegisterFont`, ReportLab's
    `registerFont`, Skia's `makeFromData`. A file is read by the caller
    (`StringFromFile`): `mormot.lib.core` keeps to `mormot.core.base`
  - **Test fonts, a mix:** synthetic faces built in code, as the CFF tests
    do, for cmap formats, symbol, `.ttc`, CFF and broken input; real
    OFL fonts only where layout tables matter - a Latin `glyf` face, an
    Arabic face without presentation forms, a CID-keyed CFF CJK subset -
    renamed subsets of Noto (OFL allows bundling with software of any
    licence; a subset is a Modified Version, renamed so that it is never
    taken for the original), the licence, the
    source and its sha256 beside them, some hundred KB in all. Arnaud
    decides between committed files and a download with sha256, as the
    trunk's tests fetch their data
  - **Golden files compared by structure:** with the test fonts the skips
    for missing fonts go (those for a missing shaper or subsetter library
    stay), the baselines stay per machine; the
    trunk's tests check normalized structure, text, roles and font mapping,
    not bytes. Byte-equal, versioned golden files only with a face read in
    pascal (head, hhea, OS/2, hmtx) and with shaping and subsetting alike:
    GDI and FreeType give different `/Ascent`, `/FontBBox` and `/Widths`
    for the same file today; that reader is also the base of the own
    subsetter, after the merge

  **Step 1** (branch `pr/test-fonts`, mORMot2 `pdf-font-layer` at `9cf8add51`):
  `RegisterFontData` with both backends, the first test font (`mORMot Test
  Sans`, a Latin subset of Noto Sans) and `TestRegisteredFont`: family and
  style from the bytes, enumerated, the face created from the registered
  bytes (`GetFaceFile` returns them - no substitute), embedded in a PDF,
  forgotten again; truncated and broken data refused. `test_runner` 868/868
  on Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi 13 Win32/Win64), 815 on
  Linux, 842 on macOS. Next: the
  Arabic and the CJK test font, then the font tests moved onto them

  **Step 2** (branch `pr/test-fonts-2`, on step 1): `mORMot Test Arabic`
  (Noto Sans Arabic without the presentation forms, so the joined forms
  are reached through GSUB only) and `mORMot Test CJK` (face 0 of Noto Sans
  CJK, CID-keyed CFF; after the subset 454 of its 550 glyph indexes differ
  from their CIDs), the generator now byte-reproducible. `TestRegisteredArabic`
  shapes 'marhaba' into the joined forms and finds them drawn with their
  `hmtx` widths; `RegisteredFaceCids` draws U+5B57 as CID 15364, not glyph
  257 - both on every platform, where before only macOS had a face with CIDs
  that differ. Found: a registered font without Latin must be asked for
  with `DEFAULT_CHARSET` on Windows, or GDI substitutes (platform-backends
  skill); the characters of a shaped run stay in `/W` and the subset under
  their unused cmap glyphs (fonts skill). `test_runner` 908/908 on Windows
  (FPC 3.3.1 aarch64, Delphi 7, Delphi 13 Win32/Win64), 855 on Linux,
  882 on macOS. Next: the font tests moved onto the test fonts

  **Step 3 decided** (2026-10-14, with Sven, three alternatives, discussed
  with Codex and Fable): **the test font first, the system face as a silent
  extra.** Each font test asserts on a registered test font, everywhere; a
  system face stays only where it covers what no test font can - the
  measured faces (Hiragino's CIDs, Geeza Pro, the Nirmala UI fallback) and
  the installed collections, whose file path memory registration does not
  take - and adds no SKIP where it is missing. Rejected: replacing every
  system face (the regressions behind those tests were found on real
  fonts), and test-font twins beside the system tests (the skips stay, the
  code doubles). As HarfBuzz (`test/shape` fonts), Skia (`resources/fonts`),
  pdfium (`test_fonts`) and iText test: bundled small fonts carry the tests,
  system fonts carry none. Three PRs, one kind of change each: (a) the test
  fonts the moved tests need - Greek in Test Sans (a Type0 character), a
  made-up `curs` lookup in Test Arabic (U-2), a symbol font, a collection of
  two faces; (b) the tests, no golden file; (c) the golden cases, re-recorded
  once on every machine. Left for later: a fake face of more than 4096
  glyphs for `TestShapedGlyphKeys`, and `tests/fonts` on Android

  **Step 3a** (branch `pr/test-fonts-3a`): the four additions above and
  `TestTestFontFiles`, which registers each file under its family. The
  Arabic glyph IDs are those of step 2: the lookup is appended after the
  subset, and its anchors skip init hah, whose advance a `kern` pair
  changes too (HarfBuzz 14.6.0 through uharfbuzz 0.56.3: x offset -40
  and advance 40 below `hmtx` on meem and beh). `test_runner` 921/921 on
  Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi 13 Win32/Win64), 868 on
  Linux, 895 on macOS. Found for 3b (Fable, then Codex, FreeType 2.13.2):
  FreeType selects no charmap for a face whose only cmap is (3,0) - Test
  Symbol, as Wingdings - and `FT_Load_Char` then takes the code for a
  glyph index: `GetCharAbcWidths` (`mormot.lib.freetype`) measures 'a' as
  glyph 97 (350 units) instead of glyph 66 at U+F061 (561)

  **Step 3 bug fixes** (branch `pr/test-fonts-3-fixes`, on 3a; mORMot2
  `pdf-font-layer` at `c68fc85aa`): the symbol charmap selected, a byte looked up at
  U+00xx, then F0xx, F1xx and F2xx (Codex: a cmap may hold the bytes in
  any of the ranges ISO 32000-1 9.6.6.4 names); `mORMot Test Symbol Low`,
  the test symbol font with its cmap at U+0020, and `TestRegisteredSymbol`
  (the widths of ' ', 'A', 'a'; the U+0020 variant on POSIX only - GDI
  gives `.notdef` there, measured). Without the fix the
  macOS run fails exactly the three widths. `test_runner` 932/932 on
  Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi 13 Win32/Win64), 888 on
  Linux, 915 on macOS

  **Step 3b** (branch `pr/test-fonts-3b`, on the bug fixes): the font tests
  on the test fonts, no golden file touched. `EnsureTestFonts` and
  `TestFace` (`test_pdf_crossplatform`) register what is missing - again
  after a test that called `UnregisterFontData` - before a document reads
  its font list. Moved: metrics, WinAnsi widths, font data, enumeration,
  faces keeping their state, the shaper's advances and y offsets, U-2
  (`TestShapedGlyphWidthFromHmtx`, Geeza Pro an extra where installed), the
  `.ttc` extraction (the test collection, an installed one an extra), the
  subsetter suites (`SansFont` is Test Sans; `TestSubsetUnionOfStyles` on
  it), `CheckTtcFaces` (the two test faces first), the symbol subset, the
  CFF face, `SystemFaces`, the smoke CJK and Arabic faces. A system face
  stays as a silent extra: Hiragino Sans GB (`SystemFaces`,
  `SystemFaceCids`, published on macOS only), Noto Sans CJK on Linux, the
  installed collections, Nirmala UI (`TestShapedAfterFallback`). Size
  checks compare the `glyf` table: FontSub keeps the layout tables whole,
  so Test Sans shrinks from 42 KB to 18 KB as a file while its outlines
  shrink far more; hb-subset passes the old file ratios too. Uniscribe
  gives no y offsets (glyphs only): `TestTextShaperYOffsets` expects none
  from a shaper without advances. Left: `TestShapedGlyphKeys` (a face of
  more than 4096 glyphs); the skips for a missing shaper or subsetter
  library stay. Found for the bug-fix PR: with `UseUniscribe`, a Latin
  item in a face that lacks Latin - the Arabic test font - is drawn as
  `.notdef` without the fallback font on Windows (Uniscribe shapes it with
  default glyphs; only an item it cannot shape falls back), and with
  HarfBuzz (measured on macOS) the same mixed line falls back neither and
  leaves the Arabic unshaped: `THarfBuzzShaper.Shape` makes one run of the
  whole text, its script guessed from the first strong character - no
  per-script runs on POSIX (Fable, from the code).
  The two faces of the test collection are pinned ('H' glyph 41 and 34,
  233 and 226 glyphs - Codex: the provider must not be its own reference).
  `test_runner` 1024/1024 on Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi
  13 Win32/Win64), 1018 on Linux, 1051 on macOS

  **Step 3c** (branch `pr/test-fonts-3c`, on 3b): the golden cases
  `cjk_subset` and `arabic_shaped` draw with Test CJK and Test Arabic
  instead of a face per OS (Microsoft YaHei and Tahoma, Hiragino Sans GB
  and Geeza Pro, Droid Sans Fallback and Noto Naskh Arabic). Compared
  against the old baselines first: on every machine exactly these two
  differed, nothing else; their new files then became the baseline,
  replaced on each machine (Windows FPC 3.3.1 aarch64, Delphi 7, Delphi 13
  Win32/Win64, Linux, macOS). On Windows `cjk_subset` now embeds Test CJK
  whole, without a subset tag: FontSub takes TrueType outlines only
  (`TestSubsetAcceptsCff`), so the case no longer covers FontSub on a CJK
  face there - Test Sans and Test Arabic (`arabic_shaped` itself) still
  go through it. On POSIX hb-subset subsets the CFF. The other golden cases
  keep the OS faces of `GetPdfFonts` and the report's export fonts
  (`tagged_embedded`, `pdfa3u_attachment`, `canvas_bridge_tagged`,
  `report_tagged`, `report_pdfa3u`): they test the library's own platform
  mapping, which always resolves, and need bold, serif and mono faces that
  Test Sans does not have. Fable: a failed `EnsureTestFonts` ends the case,
  so `--golden-record` never writes a baseline from a substitute face.
  `test_runner` 1026/1026 on
  Windows, 1020 on Linux, 1053 on macOS

  **Step 3 bug fixes, part 2** (branch `pr/step3-fixes`, from main after
  3c): the engine looks a symbol font's byte up at U+F000, F100 and F200
  (`FindOrAddUsedWideChar`; F0xx only before), the byte now the WinAnsi
  one (`WideCharToWinAnsi`) - Fable: `Engine.UnicodeBufferToAnsi` wrote the
  system code page into a one-byte local, up to three UTF-8 bytes on POSIX,
  and on Windows turned a character out of cp1252 into '?', drawn as the
  symbol font's '?' glyph instead of the fallback font. `mORMot Test Symbol F2`
  (cmap at U+F220) and `TestSymbolFontGlyphs` - without the fix exactly
  its three F2 glyphs fail. The lookup matters once the font has its
  Unicode instance: from then on its WinAnsi text is drawn by glyph, and a
  missed range gave glyph 0 and the fallback font. `make_test_fonts.py`
  packs GSUB/GPOS with fontTools' own packer: with `uharfbuzz` installed it
  used HarfBuzz's repacker, the same tables in other bytes (found when the
  new font was added - every existing file differed). The fallback finding
  of 3b, corrected by Codex and Fable from the code: on Windows any item
  Uniscribe shapes with S_OK keeps its `.notdef` (Microsoft: the caller
  must scan for `wgDefault`; `fskPlain` also comes from `E_OUTOFMEMORY` and
  failed retries, not only `USP_E_SCRIPT_NOT_IN_FONT`); with HarfBuzz the
  one run takes the first script other than Common/Inherited, so
  `<Arabic> Ab` is shaped as Arabic with the Latin as `.notdef`, and only
  `Ab <Arabic>` leaves the Arabic unshaped; and the simple path falls back
  only for characters out of WinAnsi - WinAnsi text such as `Ab` goes out
  in the main font unchecked, with or without `UseUniscribe` (in a `glyf`
  face that is not symbolic; a CFF face and a symbol font with its Unicode
  instance draw WinAnsi text by glyph and do fall back). So a
  `.notdef` run turned `fskPlain` would not fix the case: the fix is a
  step of its own (item analysis, coverage, HarfBuzz script runs).
  `test_runner` 1052/1052 on Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi
  13 Win32/Win64), 1053 on Linux, 1086 on macOS

  **Test fonts and system faces, decided 2026-10-15** (Martin leaned to the
  typical faces of each system; Codex and Fable, then Sven - option C of
  three): the test fonts stay the core, no SKIP; the system faces are tested
  visibly beside them. Rejected: the status quo (an extra that stops running
  goes unnoticed), and system faces first (the skips return, CI and other
  machines test what they happen to have - the trap of `docs/CI.md`). As
  Skia (`--nativeFonts` default, a portable font manager beside it),
  LibreOffice (bundled fonts, a check against others) and PDFBox (bundled
  fonts, an installed SimHei test that skips) do it. The package (branch
  `pr/test-fonts-c`, on #51): `SystemFaceExtra` and `REQUIRED_SYSTEM_FACES`
  (`test_pdf_crossplatform`) - one assertion either way, a missing face of
  this OS's list reported, a failure with `test_runner --require-fonts`
  (for a check session; off in CI); the golden cases `cjk_system` and
  `arabic_system` (YaHei/Tahoma, Hiragino Sans GB/Geeza Pro, Droid Sans
  Fallback/Noto Naskh Arabic); `mORMot Test CJK Glyf`, a 31 KB subset of
  Droid Sans Fallback (Apache 2.0) with TrueType outlines and 4200 empty
  glyphs before the ones drawn, for the golden case `cjk_glyf_subset`
  (FontSub on a CJK face again), `TestSubsetCjkGlyf`, and
  `TestShapedGlyphKeys` without an installed face. A subset with retained
  glyph IDs was 404 KB (hmtx, vmtx and loca up to glyph 39783, which the
  glyf closure kept); the padding gives the same high IDs. Fable: the
  composites kept their pre-padding component IDs (glyphs still raw bytes
  when the order changed), so they addressed the empty pads - 2 of the 6
  golden characters blank; `pad_glyphs` expands every glyph first, and the
  generator now refuses a composite whose component has no outline.
  `test_runner` 1106/1106 on Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi
  13 Win32/Win64), 1108 on Linux (also with `--require-fonts`), 1141 on
  macOS

  **The fallback step** (branch `pr/fallback`, on #52; variant 2, decided
  2026-10-15 after Codex and Fable - the engine owns the policy, the
  shapers report missing coverage and reshape a part in its context, as
  Blink, LibreOffice, Pango and Skia separate them). Sven decided: PDF/A
  raises for every glyph left unresolved (ISO 19005-2 6.2.11.8 forbids
  .notdef; iText and veraPDF see it so), and the WinAnsi coverage comes
  from the engine's own cmap reader, not a new `IFontFace` method. Commit
  1, the plain path: `TPdfTtf.LoadCmap`/`CreateCmap`/`GlyphOf` (the cmap
  part of `TPdfTtf.Create` on its own), `TPdfFontTrueType.WinAnsiMissing`
  (a set read once per WinAnsi font, only where a missing character has a
  way out), the simple path and `ShowText(PdfString)` send such a
  character the glyph way, `GetWideCharWidth` measures it in the fallback
  face, `AddGlyphFromChar` raises under PDF/A for every glyph left 0
  (`EPdfInvalidOperation`). `TestPlainFallback` (Test Arabic + Test Sans):
  six checks fail without it. No golden file changed; `test_runner`
  1115/1115 on Windows (FPC 3.3.1 aarch64, Delphi 7, Delphi 13
  Win32/Win64), 1117 on Linux, 1150 on macOS. Commits 2-5, the fork:
  `fsoMissingGlyphs` appended, `TFontShapedRun.Analysis` and `Rtl` (not
  `RightToLeft`, which a `with` would shadow), the optional
  `IFontRunShaper`; Uniscribe's per-item shaping in `UspShapeItem` (shared
  by `ShapeRun`), `wgDefault` from `ScriptGetFontProperties`; HarfBuzz
  script runs with the whole text as context, a two-level order,
  `RightToLeft` the base direction only (Codex: forcing every run RTL
  reversed Latin), `ShapeRun`. Codex: Uniscribe's `ShapeRun` took
  `fskSkip` + `fsoFailed` for a success. Commit 6, the engine:
  `AddShapedFallback` shapes a `fsoMissingGlyphs` or `fskPlain` +
  `fsoFailed` run again in the fallback face (Fable: the second is the
  common case, Arabic in a Latin font), a missing-glyph run raises under
  PDF/A; `TestShapedFallback` (both orders, both base directions, fallback
  off, PDF/A) - nine checks fail without it; the golden case
  `mixed_fallback`. No other golden file changed. mORMot2 pin
  `c53462a61`. `test_runner` 1133/1133 on Windows (FPC 3.3.1 aarch64,
  Delphi 7, Delphi 13 Win32/Win64), 1135 on Linux, 1168 on macOS. Not
  done: per-cluster fallback, full bidi. Fable's branch review: a
  default-ignorable code point (ZWNJ, ZWJ, the bidi controls, a variation
  selector) no font has raised under PDF/A on the plain path while both
  shapers drop it - it is not drawn now (`IsDefaultIgnorable`);
  `TextWidth(PdfString)` measured a missing WinAnsi character in the main
  font while `TextOut` drew it from the fallback; Uniscribe's check is kept
  (wgDefault 0) when `ScriptGetFontProperties` fails. Left: an
  `hb_font_t` per `ShapeRun` call, and the cmap read twice per font once its
  Unicode instance exists. `test_runner` 1135/1135 on Windows, 1137 on
  Linux, 1170 on macOS

  **Bug fixes** (the fallback step's bug-fix PR, branch
  `pr/fallback-fixes`, on the formatting PR): Martin's two notes on #53.
  `TPdfTtf.GlyphOf` bounds `length(fcmap) * 2`: right, `fcmap` is a
  `TWordDynArray`. `GetWideCharWidth` gives 0 for a character the font
  lacks; its callers measure such a character where it is drawn
  (`FallbackCharWidth`): in the fallback font, or - lacking there too -
  as glyph 0, whose advance is the `/DW` of the font drawing it, since
  `/W` leaves glyph 0 out. Before, `GetAnsiCharWidth` (`TextWidth` of a
  `PdfString`) kept the 0 for a CFF face (`Type0Only`, found by Fable)
  and for a character the fallback lacks too, and `UnicodeTextWidth`
  took `DEFAULT_PDF_WIDTH` (600) where the viewer advanced the `/DW` (the
  space: 260 in the test fonts). `TestPlainFallback` (U+2122, in neither
  test font) and `Type0Routing` (a WinAnsi letter the fake CFF face
  lacks) fail without the fix; no golden file changed

## Open Decisions

- ~~Golden files in `mormot2tests`~~ decided 2026-10-13: compared by
  structure, see "Test fonts, then a subsetter of our own"
