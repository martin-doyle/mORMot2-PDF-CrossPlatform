# mORMot PDF Cross-Platform — Implementation Roadmap

Open work in detail, finished work as one line each. The technical knowledge of
a finished item lives in `.claude/skills/` (that is what agents read), its
reasoning in the git history — this file repeats neither.

**State on 2026-09-20.** The engine is cross-platform, writes PDF 1.7, and its
tagged output passes PAC 2024 with one accepted warning (W-1, a Figure in
`pdf_demo`). Layout is measured with the PDF font engine on every platform, so
line breaks no longer depend on the widgetset. Fonts are embedded and, on
Linux/macOS, subset (R-12); tables carry `THead`/`TBody`/`TFoot` row groups
(R-14). Five of the six demos are verified on Linux; `mormot_demo` waits for a
sample database.

---

## Working Method

**One fix at a time.** Implement, verify, accept, then start the next. Changes
to `BeginStructContent` and the structure tree are unattributable when bundled —
a PAC error like "unbalanced marked content" then names no culprit.

| Role | System |
|---|---|
| Development, build, fast iteration | **Linux** |
| PAC 2024 + tag-tree inspection | **Windows** (only platform; mandatory) |
| Third-platform verification per change | macOS |
| `veraPDF --flavour ua1` | any; not installed on the dev machine yet |

**PAC caveat.** The traffic-light status is not enough: a flat tree of
individually valid `Table`/`TR`/`TD` elements passes while the nesting is
broken. Always open the *Logical Structure* view as well.

**Toolchain on the Linux development machine.** `lazbuild` lives at
`/home/parallels/fpc-fixes/lazarus/lazbuild` (not on `PATH`), the mORMot2
sources at `/home/parallels/synopse/mORMot2`. Linking the demos needs GTK2
development symlinks, which are absent: symlink `libgtk-x11-2.0.so`,
`libgdk-x11-2.0.so` and `libatk-1.0.so` to their `.so.0` files in a scratch
directory and build with `lazbuild --opt=-Fl<dir>`. Available for checking
output: `pdffonts`, `pdfinfo`, `pdftotext`, `pdftoppm`, `python3`. Missing:
`qpdf`, `mutool`, `veraPDF`, ImageMagick.

**Checking a change.** Build all six demos and `test_runner`, then compare the
PDFs with the previous run: file size, `pdffonts`, `pdftotext` output, and the
pages rendered with `pdftoppm -r 110 -png` compared pixel by pixel. A change
that is meant to be invisible has to come out pixel-identical.

---

## Open

### V — Verification Outstanding on Other Platforms

R-12 and R-14 are merged and accepted on Linux. Neither has been built on macOS
or Windows since, and two PDFs are waiting for PAC.

| What | Where | Why it matters |
|---|---|---|
| PAC 2024 | `report_demo/bin/aarch64-linux/report_demo_linux_r14.pdf`, `pdf_demo/bin/aarch64-linux/pdf_demo_linux_r14.pdf` | R-14 changed the table structure of both |
| macOS build, `test_runner`, demos | R-12, R-14 | Geeza Pro is the only face that exercises the PUA glyph path (`fonts.md` §10); macOS also has the `.ttc` CJK face |
| Windows build, `test_runner`, demos | R-12, R-14 | no subsetter is registered there, so output must equal the state before R-12: compare `pdffonts` and file sizes |
| `mormot_demo` run | R-14, tagged export, `--export` batch mode, table colours | needs a sample database; the demo compiles but has never run |

### R-15 — Windows: Subset by Glyph ID (`TTFCFP_FLAGS_GLYPHLIST`) — **Priority 2**

**Effort:** 0.5–1 day, on a Windows machine | **File:**
`src/core/mormot.ui.pdf.pas`

Windows subsets through `CreateFontPackage` (`FontSub.dll`, part of the OS) and
passes **code points** as the keep list (`mormot.ui.pdf.pas:7319`). Glyphs that
GSUB produced have no code point of their own, so shaped Arabic loses them, and
CJK is unreliable for the same reason. That is why `chinese_demo` and `rtl_demo`
set `EmbeddedWholeTtf := True`, and why `SetTagged` keeps the whole face on
Windows while Linux/macOS subset (R-12).

`CreateFontPackage` can take the keep list as **glyph indices** instead. The
flag is not declared in this project yet: next to `TTFCFP_FLAGS_SUBSET = 1`,
`_COMPRESS = 2` and `_TTC = 4` (`mormot.ui.pdf.pas:6371`) it is
`TTFCFP_FLAGS_GLYPHLIST = 8`. The engine already tracks exactly that list —
`fUsedWide[].Glyph`, the same input R-12 hands to hb-subset.

#### Steps

1. Declare `TTFCFP_FLAGS_GLYPHLIST = 8` and add it to `uniflags`.
2. Build the keep list from `fUsedWide[].Glyph` instead of the code points of
   `fWinAnsiUsed` + `fUsedWideChar`.
3. Verify on Windows, in this order, each rendered **and** through `pdftotext`:
   Latin (`markdown_demo`, untagged), CJK (`chinese_demo` with
   `EmbeddedWholeTtf := False`), Arabic (`rtl_demo` — the case this is for).
4. If it holds: let `SetTagged` subset on Windows too, then PAC 2024 on the
   tagged demos — the same decision R-12 took for POSIX.
5. Align the subset tag: the Windows path prefixes the font name through
   `TPdfName.AppendPrefix`, which draws from `Random32`, so two runs of one
   document produce different tags. R-12 derives the tag from a checksum of the
   subset bytes. One scheme for both platforms.

#### Two Unknowns

- **Does the `cmap` survive?** The WinAnsi instance reaches its glyphs through
  the `(3,1)` cmap. hb-subset rebuilds it for the retained glyphs; whether
  `CreateFontPackage` does the same from a glyph list is unverified. If it does
  not, Latin text comes out blank, and the fix is to keep code points for the
  WinAnsi instance and use glyph IDs only for the CID instance.
- **Are glyph IDs retained?** The engine writes glyph IDs of the full font into
  the content stream and embeds the subset, so today's Windows path must already
  retain them. That is an inference from the fact that Windows PDFs with CID
  fonts work, not something this project measured. With a glyph list the
  behaviour could differ; a mismatch shows up as wrong characters, not as an
  error.

If neither holds, the fallback is shipping `libharfbuzz-subset.dll` and
registering the same `IPdfFontSubsetter` as POSIX — the interface is
platform-neutral, only its loader unit is POSIX-gated. That would add the only
runtime dependency Windows has, which is why the native route comes first.

### R-10 — Table Row Pagination — unprioritised

**Effort:** 2–3 days | **File:** `src/core/mormot.ui.report.pas`

A table row taller than the remaining page space forces a page break before the
row. Let the row split: partial cell content on the current page, the rest on
the next. The split row's cells have to stay inside **one** `TR` element
referencing both pages — `TPdfDocumentVcl.ResumeStructContent` does this for
text blocks (B-2) and is the model to follow.

### R-11 — TTC Face Index — unprioritised

**Effort:** 1 day | **Files:** `src/platform/unix/mormot.pdf.freetype.pas`,
`src/core/mormot.pdf.types.pas`

Only face index 0 of a `.ttc` is reachable, because `TPdfFontMap` carries no
face index. Add one so the remaining faces can be selected by name. The
FreeType backend already extracts a single face as a standalone sfnt
(`ExtractSfntFromTtc`), so the embedding side needs no change.

### R-13 — RTL Shaper Advance Test — unprioritised

**Effort:** 0.5 day | **File:** `tests/`

Linux fonts (Noto Naskh Arabic) resolve shaped glyphs through the CMAP, so the
shaper's own advance path never runs there — a bug in it is invisible on Linux
and fatal on macOS. Add a test against a font **without** Arabic presentation
forms. Background: `.claude/skills/fonts.md` §10.

### EMF/MetaFile and GDI+ Gradients — no work planned

Windows-only (`TPdfDocumentGdi`), not portable.

---

## Completed

Details are in the git history and in `.claude/skills/`; the note below is what
still constrains new work.

| ID | What | Note that still applies |
|---|---|---|
| P1-A…P1-C | CJK fonts per platform, PDF 1.7 output | PDF/A and Tagged raise `FileFormat` on their own |
| P2-A | HarfBuzz RTL shaping (Linux/macOS) | the FT face must be sized before shaping, or every advance comes back 0 — `fonts.md` §10 |
| P2-C | Font zoom in the preview (`FontScale`) | |
| P3 | Tagged PDF — text structure tags | |
| R-1…R-4 | AES-128, xref streams, object streams, XMP | object streams hide dictionaries from a plain text search in tests |
| R-5, R-6 | Table and figure tags | emitted flat; B-1 gave them their nesting |
| R-7…R-9 | Transparency, `LineHeightFactor`, repeated table header | a repeated header row is an artifact, never a second `THead` |
| B-1 | Nested struct tags for tables and lists | containers own no marked-content region |
| B-2 | One tag per paragraph instead of one per line | a block interrupted by a page break is reopened, not restarted |
| B-3 | One tag per sentence, styled runs as `Span` | only the coordinate-less overloads share a line and a tag |
| B-4, B-5 | Layout and text metrics from the PDF font engine, not the LCL | the font flags decide the metrics, so they must be set before the first draw command |
| B-6 | `/Alt` as a PDF string, on the `StructElem` | |
| P-6 | Tagged output selects the PDF/UA font mode | `Tagged` raises when set after the first page |
| B-7…B-11 | PAC findings: `DisplayDocTitle`, XMP stream and title, `/Scope` on `TH`, tagged path objects | |
| B-12…B-14 | Graphics state inside a path object, `Figure` without `/BBox`, headings without bookmarks | `DrawHeading` writes the bookmark; a centred text does not |
| W-1 | "Possibly inappropriate use of figure" (`pdf_demo`) | accepted, documented in the demo |
| R-12 | Font subsetting on POSIX via hb-subset — [R12_PLAN.md](R12_PLAN.md) | PDF/A-1, symbol fonts and CFF faces keep the whole face |
| R-14 | Table row groups `THead`/`TBody`/`TFoot`, `DrawTableFooter` | `TGDIPages` emits the groups itself; the low-level API leaves them to the caller |
| — | `report_demo`, `mormot_demo`: tagged export, `TTableLayout`, `--export` batch mode | the batch mode still needs a display (`TGDIPages` is an LCL control) |
| — | Crash fix: stale `fUsedWide[]` address in `GetWideCharWidth` | found on aarch64: the call that indexes the array also reallocates it |

### Measured Effect of R-12 (Linux)

| PDF | Before | After |
|---|---|---|
| `markdown_demo.pdf` (tagged) | 1,428,389 B | 46,407 B |
| `output_crossplat.pdf` (tagged) | 800,923 B | 19,256 B |
| CJK, `EmbeddedWholeTtf := False` | 2,309,640 B | 10,848 B |
| Arabic, `EmbeddedWholeTtf := False` | 500,092 B | 15,090 B |

Every page pixel-identical, `pdftotext` unchanged, every face `emb=yes sub=yes`.
Windows is unaffected until R-15.
