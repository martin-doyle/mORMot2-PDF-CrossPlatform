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
2. **One step, one PR, one kind of change.** Never two of: move units,
   rename public API, change font metrics, change PDF serialization, change
   report layout. Each must be reviewable on its own.

**Architecture**

3. **No new dependency without justification.** Every new `uses` follows the
   gist's dependency graph (§14). Forbidden: `mormot.lib.font` →
   `mormot.pdf.*`, `mormot.pdf.core` → GUI, `mormot.pdf` → GUI.
4. **No generic abstraction without need.** An interface only when there are
   two implementations or a clear testing or injection need.
5. **Low-level units stay small.** `mormot.lib.font` and `mormot.pdf.core`
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
| `test_runner` green, same assertion count, golden files unchanged | Windows: FPC Win64, Delphi 7, Delphi 2010 |
| All eight demos rebuilt (`-B`) and run (GUI demos with `--export`) — never an executable of an earlier state | the same |
| Demo PDFs identical to the baseline after normalization | the same |
| `test_runner`, demos, PDFs against the baseline | Linux and macOS — every step that touches POSIX code, otherwise at the end of the phase |
| PAC 2024, veraPDF | only when a PDF differs, and at the end of each phase |
| Delphi 13 (Win64, Linux64, Android64) | the community; asked for at the end of each phase |

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
4. `pdfcheck run <compiler> <folder>` into the state's folder
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
     R-26, R-25) — then compared; the first differing line is shown
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
   - one report of a difference: `ComparePdfText` names the object, the byte
     and the line of each side, for the golden files and `pdfcheck` alike

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

   **Pinned:** `d60cc6e80` (2026-10-02). **Checked:** today's `main`,
   `test_runner` 259/259 on Windows (FPC Win64, Delphi 7, Delphi 2010),
   298/298 on Linux, 317/317 on macOS (fpcupdeluxe, FPC 3.2.3).
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

**Where the code lives** (agreed 2026-10-02, PR #2): here in `src/`, where
`pdfcheck`, the golden files and the check machines are, but under the
target unit names from this phase on (`mormot.lib.font*`, later the
`mormot.pdf*` units of `src/pdf`), so the final move is a plain copy. Once
this phase is done, `mormot.lib.font*` can go to the trunk on its own.

- `mormot.lib.font`, `mormot.lib.font.gdi`, `mormot.lib.font.freetype`,
  `mormot.lib.font.harfbuzz` from `mormot.pdf.types` and the four backend units
- `Pdf` dropped from names that are not PDF-specific
- **Windows shaping and subsetting behind the interfaces:** Uniscribe and
  `CreateFontPackage` are called from `mormot.ui.pdf` today; they become the
  shaper and subsetter of `mormot.lib.font.gdi` (not in the gist)
- `libharfbuzz` and `libharfbuzz-subset` stay separately loaded
- The device-context interface moves unchanged, marked transitional

### Phase 1b — Remove the Device Context

Gist §19. Its own phase: the step most likely to change metrics.

- `IPdfPlatformDC`, `SelectFont`, `CreateDC`, the screen `LOGPIXELSY`
  replaced by a face object that owns its state
- Output identical; every difference explained

### Phase 2 — Raw PDF Without VCL/LCL

Gist §7–§10. `uses mormot.pdf` builds in a console program without a GUI
framework, on every compiler.

- `mormot.pdf.core` and `mormot.pdf.image` only where the boundary is real
  (gist §23)
- `mormot.pdf.font` for the PDF side of fonts
- The `TBitmap`/`TGraphic` image API moves to an adapter — user code changes

### Phase 3 — Canvas Adapter

Gist §11. `mormot.pdf.canvas`: `TPdfDocumentVcl`, `TPdfVclCanvas`, bitmap
adapters, EMF.

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
    `mormot.lib.font*` in Phase 1 - no work on code about to be replaced

## Open Decisions

- The trunk's existing `TGdiPages` (`TScrollBox`, preview built in) — before
  Phase 4
- Golden files in `mormot2tests`: here they are per machine and not
  versioned (Phase 0 step 2) — how a baseline without files in the
  repository serves the trunk's tests
