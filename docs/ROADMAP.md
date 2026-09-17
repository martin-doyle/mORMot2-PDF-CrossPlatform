# mORMot PDF Cross-Platform — Implementation Roadmap

This document describes all planned improvements with full technical background,
affected files, implementation steps, and verification criteria.

**Current baseline:** All previously planned features (P1-A … P3, R-1 … R-9) plus
Step 1 (B-1) are implemented. The structure tree is now properly nested, with
`Table > TR > TH|TD` and `L > LI > LBody` as real hierarchy levels. The open work
is the remaining set of correctness bugs in the tag tree plus font embedding for
tagged output.

Completed items are archived in [Completed Work](#completed-work) at the end of
this document.

### Working Method

**One fix at a time.** Each step below is implemented, then verified on Windows,
Linux and macOS, and accepted before the next step starts. B-1, B-2 and B-3 all
modify `BeginStructContent` and the structure tree — bundling them would make a
PAC error like "unbalanced marked content" unattributable.

**Platform roles.** Development stays on **Linux** (the only system with a working
`lazbuild` + mORMot2 tree; also the outlier in the B-5 line-breaking comparison,
so the defect is most visible there). macOS serves as the third verification
target, not as the development host.

| Role | System |
|---|---|
| Development, build, fast iteration | **Linux** |
| `veraPDF --flavour ua1` | Linux (Java app — `apt install verapdf` or the zip from verapdf.org; the earlier failure was an install issue, not a platform limit) |
| PAC 2024 + tag-tree inspection | **Windows** (only platform; mandatory) |
| Third-platform verification per fix | macOS |

**PAC caveats.** For B-1, the traffic-light status is not sufficient — a flat tree
of individually-valid `Table`/`TR`/`TD` elements can pass while the nesting is
still broken. Always open PAC's *Logical Structure* view and check the hierarchy.
And until Step 6 lands, **PAC will report font-embedding errors on every run**;
that is expected, not a regression.

**Baseline before Step 1.** Capture the current Windows/Linux/macOS output of
`pdf_demo` and `markdown_demo` as reference files. For Step 4, diff the
*decompressed content streams* rather than comparing visually — the 0.75 pt
quantisation is invisible to the eye but obvious in the stream.

**Font parity.** The three systems must resolve comparable faces, or the Step 4
stream diffs are meaningless. `markdown_demo` asks for Helvetica and Times; on
Linux these resolve to Nimbus Sans / Nimbus Roman (urw-base35) or Liberation.
Harmless while base-14 names stay non-embedded — but **from Step 6 on, whatever
is found locally gets embedded**, so record the font source per platform then.

---

### Evidence Base and Open Unknowns

The bug analyses below were verified against real output: the committed macOS
builds (`examples/*/bin/aarch64-darwin/*.pdf`) with their `/ObjStm` streams
decompressed, plus supplied Windows/Linux/macOS runs of `markdown_demo` and a
Linux run of `pdf_demo`. What that **confirmed**:

- B-1: the struct tree is flat — all 34 elements parented to one `Document`
- B-1: containers (`Table`, `TR`) wrongly own an MCID
- B-1: the `/ParentTree` is keyed per page, not per MCID
- B-3: one visual line (`Y=447.5`) is split into **nine** top-level `P` elements,
  MCID 18–26; even a bare `", "` separator becomes its own paragraph
- B-4: **characters are correct** on Linux — only the `TextWidth`/`TextHeight`
  bounding boxes are wrong. Cause (a), FreeType fallback, is ruled out
- B-5: Linux fits more text per line than Windows/macOS; inline advances are
  quantised to 0.75pt (1 px @ 96 DPI) and `bold` overshoots its AFM width by 1.71pt
- P-6: every tagged PDF currently produced embeds nothing (`emb=no`, `uni=no`)

What is **still not verified** and must be settled during implementation:

| Unknown | Needed for | How to settle |
|---|---|---|
| ~~Actual body of `BeginStructContent`, `SerializeStructTree`, `TPdfStructElement`~~ | ~~B-1~~, B-2, B-3 | **Settled in Step 1.** Note the naming: the serializer is `SerializeStructTree`, not `BuildStructTree`, and the class is `TPdfStructElement`. MCIDs come from the per-page counter `TPdfPage.fCurrentMCID`, not from `fStructParents * 1000` |
| Whether `TDrawCommand` can take new fields without breaking the recording array | B-2, B-3 | read `src/core/mormot.ui.report.pas` (2.7k lines) |
| ~~How `RenderPageToCanvas` currently chooses a role per command~~ | ~~B-2, B-3~~ | **Settled in Step 1.** A `case Cmd.Kind` block with the local flags `InTableRow`, `InHeaderRow` and `InListItem` |
| A wrapped paragraph's MCID pattern (B-2's premise) | B-2 | not yet isolated in a content stream — confirm before coding |
| Per-platform `FontTextHeight` / `LineHeightMM` values | B-5 | instrument and run on all three platforms |

**Toolchain on the Linux development machine:** `lazbuild` lives at
`/home/parallels/fpc-fixes/lazarus/lazbuild` (not on `PATH`) and the mORMot2
sources at `/home/parallels/synopse/mORMot2`. Compilation works; linking the
demos needs `libgtk2.0-dev`, whose development symlinks are absent, so the
runtime GTK2 libraries cannot be found by `ld`. `qpdf`, `mutool` and `veraPDF`
are still missing; only `pdffonts` and `pdfinfo` are available.

---

## Step 1 — B-1: Nested Structure Tags (Tables and Lists) — **DONE (2026-09-17)**

**Effort:** 2–3 days | **Files:** `src/core/mormot.pdf.types.pas`,
`src/core/mormot.ui.pdf.pas`, `src/core/mormot.ui.report.pas` |
**Demos:** `pdf_demo`, `markdown_demo`

Implemented and verified on Linux. The analysis below is kept for the record;
what was actually built is in [Result](#result-step-1) at the end of this step.

### Symptom

In `pdf_demo` the table is emitted with correctly nested `BeginStructContent`
calls (`psrTable` → `psrTR` → `psrTH`/`psrTD`), and `markdown_demo` emits lists
via `DrawListItem`. In the resulting PDF the structure tree shows all elements as
**siblings** under `/Document` — `TR` is not a child of `Table`, `TD` is not a
child of `TR`, and list items have no `L`/`LI`/`LBody` grouping at all.
Screen readers therefore announce a table as a flat run of cells, and
PDF/UA validation fails on the table and list rules.

### Root Cause

**Confirmed against real output** — decompressing the `/ObjStm` of
`examples/pdf_demo/bin/aarch64-darwin/output_crossplat.pdf` (macOS build,
2026-09-06) shows every element parented to the single `Document` element `50 0 R`:

```
<</Type/StructElem/S/Table/P 50 0 R/Pg 14 0 R/K<</Type/MCR/MCID 0>>>>
<</Type/StructElem/S/TR   /P 50 0 R/Pg 14 0 R/K<</Type/MCR/MCID 1>>>>
<</Type/StructElem/S/TH   /P 50 0 R/Pg 14 0 R/K<</Type/MCR/MCID 2>>>>
...
<</Type/StructElem/S/Document/P 6 0 R/K[16 0 R 17 0 R ... 49 0 R]>>
```

`Table`, `TR`, `TH` and `TD` are all siblings in one flat 34-element `/K` array.
`TPdfCanvas.BeginStructContent` appends to a flat list and records no parent
(see `.claude/skills/call-graph.md` Path 10):

```
mcid := fPage.fStructParents * 1000 + fPage content index
elem: TPdfStructElem := (Role, PageIndex, MCID)
fDoc.fStructElems.Add(elem)          <- flat, no parent link
```

Nesting depth is discarded at the moment the element is created, so it cannot be
recovered at serialization time. A second consequence: `EndStructContent` writes
`EMC` unconditionally, so it cannot detect unbalanced Begin/End pairs.

Two further observations from the same file, which change the plan below:

- **Containers already consume an MCID.** `Table` has `/MCID 0` and `TR` has
  `/MCID 1` although neither draws content. So the MCID sequence is already
  polluted with empty regions today — step 3 is a real fix, not a precaution.
- **The `/ParentTree` is keyed by page, not by MCID.** The emitted number tree is
  `/Nums[0[16 0 R 17 0 R] 1[18 0 R] 2[19 0 R ...]]` — one entry per
  `/StructParents` page index holding every element of that page in order. That
  form is only valid because each element has exactly one MCID and they are
  numbered per page from 0; it breaks as soon as an element owns several MCIDs
  (Bugfix 2). The rewrite must keep the array index aligned with the MCID value.

Additionally, `TPdfStructRole` has no list roles, so lists cannot be tagged even
once nesting works.

### Steps

1. **Add parent tracking to `TPdfStructElem`** (`mormot.ui.pdf.pas`):
   ```pascal
   TPdfStructElem = class
     Role: TPdfStructRole;
     PageIndex: integer;
     MCID: integer;           // -1 when the element is a pure container
     ObjNum: integer;         // assigned in BuildStructTree
     Parent: TPdfStructElem;
     Kids: array of TPdfStructElem;
   end;
   ```
   A container element (`Table`, `TR`, `L`, `LI`) has **no** MCID of its own — it
   only has kids. A leaf element (`P`, `H1`, `TD`, `Figure`, `LBody`) carries the
   MCID of its marked-content region.

2. **Maintain an open-element stack on the canvas:**
   ```pascal
   fStructStack: array of TPdfStructElem;   // in TPdfCanvas or TPdfPage
   ```
   `BeginStructContent` pushes the new element and links it to the current stack
   top (or to the `Document` root when the stack is empty);
   `EndStructContent` pops.

3. **Emit BDC/EMC only for leaf elements.** A container must not open a
   marked-content region, otherwise the MCID sequence contains regions with no
   content. Decide by role, or by whether any content operator was written
   between Begin and End.

4. **Raise on unbalanced nesting.** In `EndStructContent`, if the stack is empty,
   raise `ESynException` — this turns a silently corrupt tag tree into a build-time
   error. At `SaveToStreamDirectEnd`, a non-empty stack is likewise an error.

5. **Add list roles to `TPdfStructRole`** (`mormot.pdf.types.pas`):
   ```pascal
   psrL, psrLI, psrLbl, psrLBody   // List, ListItem, Label, ListBody
   ```
   Append them at the **end** of the enum — `TPdfStructRole(Level)` is used for
   heading levels 1..6 and `dckBeginTR` logic depends on the existing ordinals.

6. **Tag lists in `TGDIPages`** (`mormot.ui.report.pas`): `DrawListItem` currently
   emits a single `dckDrawText`. Add `dckBeginList`/`dckEndList` commands
   (mirroring the existing `dckBeginTR`/`dckEndTR` pattern) so consecutive list
   items are wrapped in one `psrL`, each item in `psrLI`, the bullet prefix in
   `psrLbl` and the item text in `psrLBody`.

7. **Rewrite `BuildStructTree`** to walk the tree recursively instead of grouping
   by page: write each element with `/P` pointing at its parent, `/K` holding
   either kid references (container) or an MCID entry (leaf), and keep the
   `/ParentTree` mapping MCID → owning leaf StructElem.

### Verification

```bash
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B && ./examples/pdf_demo/bin/pdf_demo_crossplat
lazbuild examples/markdown_demo/markdown_demo.lpi -B && ./examples/markdown_demo/bin/markdown_demo
veraPDF --flavour ua1 pdf_demo.pdf
```

- **PAC 2024 → Logical Structure** (not just the traffic light) shows
  `Table > TR > TH|TD` and `L > LI > Lbl|LBody` as real nesting levels
- No MCID appears twice, and no MCID region is empty
- Table announced as a table (with row/column context) by a screen reader
- Gate: identical tag hierarchy on Windows, Linux and macOS before Step 2
- Expected until Step 6: PAC still flags non-embedded fonts

### Result (Step 1)

Implemented on 2026-09-17, built and run on Linux. Windows and macOS
verification is still outstanding; the cross-platform gate above is therefore
not yet closed.

What was built, against the plan above:

| Plan | Implementation |
|---|---|
| 1. Parent tracking | `TPdfStructElement` gained `Parent`, `Kids: TSynList` and `Dic: TPdfDictionary`. `Kids` is freed with the element; `fStructElems` stays the owner of all elements. |
| 2. Open-element stack | `TPdfDocument.fStructStack: TSynList` — **document level, not page level**, because `dckBeginTable` and `dckEndTable` land on different pages when a table paginates. |
| 3. BDC/EMC for leaves only | Decided by role through the new `PDF_STRUCT_CONTAINER` table: `Document`, `Table`, `TR`, `L` and `LI` are containers and carry `MCID = -1`. |
| 4. Raise on unbalanced nesting | `EndStructContent` raises `EPdfInvalidOperation` on an empty stack; `SaveToStreamDirectEnd` raises when the stack is not empty. |
| 5. List roles | `psrL`, `psrLI`, `psrLbl`, `psrLBody` appended at the end of `TPdfStructRole`. |
| 6. Tag lists in `TGDIPages` | New commands `dckBeginList`, `dckEndList`, `dckBeginLI`, `dckEndLI`. `DrawListItem` opens the list on its first call; `AddCommand` closes it on the first foreign command, `NewPage` and `EndDoc` likewise. |
| 7. Rewrite `SerializeStructTree` | Walks the tree recursively, `/P` points at the real parent, `/K` holds kid references for containers and an `MCR` dict for leaves. The `/ParentTree` stays keyed per page with the array index equal to the MCID — valid now that containers consume no MCID. |

**Deviation from step 6 of the plan.** The list structure is `L > LI > LBody`
with the bullet left inside the item text, not `L > LI > Lbl + LBody`. A real
`Lbl` needs the bullet and the text as two separate `TextOut` calls, and their
gap is computed from the text-width measurement that B-4 and B-5 are still
about to fix. Splitting them now would change the rendered output in a step
that is supposed to touch only the tag tree. `psrLbl` exists in the enum and
can be wired up once Step 5 has landed. PDF/UA is satisfied either way, since
`Lbl` is optional inside `LI`.

**Note for later steps.** A `Table` element now legitimately spans pages: its
`/Pg` names the page it started on, while each leaf carries its own `/Pg`.
Step 2 must not assume that an element and its kids share a page.

---

## Step 2 — B-2: Tags at Line Breaks

**Effort:** 1–2 days | **Files:** `src/core/mormot.ui.report.pas`,
`src/core/mormot.ui.pdf.pas` | **Demos:** `pdf_demo`, `markdown_demo`

### Symptom

Wrapped and multi-line text produces one structure element **per visual line**
instead of one per logical paragraph. A three-line wrapped paragraph appears in
the tag tree as three sibling `P` elements, so a screen reader inserts a
paragraph break at every line break and reading order becomes choppy. The same
happens where a paragraph is split by a page break: the continuation starts a new
`P` rather than continuing the existing one.

### Root Cause

Tagging is driven per draw command, not per logical block. `DrawTextWrapped` and
the internal wrapping in `DrawText` emit one `dckDrawText` command per output
line, and `RenderPageToCanvas` wraps each `dckDrawText` in its own
`BeginStructContent(psrP)`/`EndStructContent` pair. There is no notion of "this
command continues the previous paragraph".

### Steps

1. **Add a logical block id to `TDrawCommand`:**
   ```pascal
   BlockId: integer;   // 0 = standalone; >0 = all commands of one logical block
   ```
   Assign a fresh id in each public `Draw*` entry point, and copy the **same** id
   into every line-level command that the wrapping loop generates.

2. **Open a struct element on block change, not per command.** In
   `RenderPageToCanvas`, track `fLastBlockId`:
   - `Cmd.BlockId <> fLastBlockId` → `EndStructContent` (if open), then
     `BeginStructContent` for the new block
   - same `BlockId` → emit the content only; the marked-content region stays open

   Multiple lines then share one `P` with several MCIDs in its `/K` array — which
   the ISO 32000-1 §14.7 model explicitly allows.

3. **Support multiple MCIDs per element.** This depends on Bugfix 1 step 1: a leaf
   element needs `MCIDs: TIntegerDynArray` rather than a single `MCID`, and
   `/ParentTree` must map every one of them to the same StructElem.

4. **Handle page-break continuation.** A block whose lines span two pages produces
   MCIDs on different pages. Per spec a single StructElem may reference content on
   several pages, but each MCID entry then needs an explicit `/Pg`. Emit
   `/K [ <</Type/MCR /Pg p1 /MCID n>> <</Type/MCR /Pg p2 /MCID m>> ]` instead of
   relying on the element-level `/Pg`.

5. Close any open block at `EndPage`/`AddPage` boundaries so BDC/EMC stay balanced
   inside each content stream — an EMC may never cross a page.

### Verification

- `markdown_demo` wrapped paragraph → exactly **one** `P` in the tag tree,
  containing as many MCIDs as it has lines
- A paragraph split across a page break → one `P` whose `/K` references both pages
- `veraPDF --flavour ua1` reports no unbalanced marked content
- PAC → Logical Structure: one `P` node per paragraph, not one per line
- Acrobat "Read Out Loud" reads the paragraph without pauses at line ends
- Gate: same paragraph/MCID counts on all three platforms before Step 3

---

## Step 3 — B-3: Tags on Inline Text

**Effort:** 1–2 days | **File:** `src/core/mormot.ui.report.pas` |
**Demos:** `pdf_demo`, `markdown_demo`

### Symptom

Inline runs — `DrawStrong` (bold), `DrawEm` (italic), `DrawCode` (monospace) —
each become a separate top-level `P` element even though they are visually part
of one sentence. A sentence such as `plain **bold** plain` yields three sibling
`P` elements, so the sentence is read as three paragraphs and the emphasis
carries no semantics.

### Root Cause

**Confirmed in the content stream.** The macOS `markdown_demo.pdf` emits the
single sentence *"Inline styles like bold, italic, code and links can be mixed
inline."* as **nine** separate `P` elements, MCID 18–26:

```
/P <</MCID 18>> BDC  /F1 11 Tf  BT 42.75  447.5 Td (Inline styles like ) Tj ET EMC
/P <</MCID 19>> BDC  /F0 11 Tf  BT 123.00 447.5 Td (bold)                Tj ET EMC
/P <</MCID 20>> BDC  /F1 11 Tf  BT 145.50 447.5 Td (, )                  Tj ET EMC
/P <</MCID 21>> BDC  /F2 11 Tf  BT 151.50 447.5 Td (italic)              Tj ET EMC
...
/P <</MCID 26>> BDC  /F1 11 Tf  BT 247.50 447.5 Td ( can be mixed inline.) Tj ET EMC
```

All nine share the same baseline `Y=447.5`, so they are provably one visual line,
yet each is a top-level `P`. Even the bare separator `", "` becomes its own
paragraph. `psrSpan` — which exists in `TPdfStructRole` — is never emitted.

The coordinate-less inline overloads (`DrawStrong('bold')` etc.) advance X on the
current line and emit an independent `dckDrawText`. `RenderPageToCanvas` maps
every `dckDrawText` to `psrP`.

Note this also makes the **`psrSpan` target concrete**: the fix is to keep one `P`
open for the whole `Y=447.5` run and emit the nine MCIDs into it, with `Span` only
for the styled sub-runs (`bold`, `italic`, `code`, `links`).

### Steps

1. **Mark inline commands.** Add to `TDrawCommand`:
   ```pascal
   Inline: boolean;   // true = continues the current line, not a new block
   ```
   Set it in the no-coordinate `DrawStrong`/`DrawEm`/`DrawCode`/`DrawText`
   overloads. These already share a line, so they can reuse the `BlockId`
   introduced in Bugfix 2 — the two fixes are deliberately complementary.

2. **Map inline runs to `psrSpan` inside the enclosing `P`:**
   ```
   P
    ├─ Span (plain)
    ├─ Span (bold)      <- DrawStrong
    └─ Span (plain)
   ```
   The enclosing `P` opens on the first command of the line and closes when a
   block-level command or an explicit `MoveToNextLine` arrives.

3. **Keep unstyled inline text untagged where possible.** A `Span` that carries no
   semantics beyond its parent `P` adds tree noise; emit `Span` only where the run
   differs in style, and let plain runs contribute their MCID directly to the
   parent `P`.

4. **Consider richer roles than `Span`** for code: ISO 32000-1 has no `Code` role,
   so `Span` with `/ActualText` is the correct representation for
   `DrawCode`. Emphasis may additionally carry `/Alt` where the styling is
   meaning-bearing.

### Verification

- `markdown_demo` inline section → one `P` per sentence, with `Span` children for
  the styled runs
- The nine-element MCID 18–26 run collapses into **one** `P` (see Root Cause)
- No `P` element contains only a single bold word or a bare `", "`
- Screen reader reads each sentence as one continuous sentence
- Gate: same structure on all three platforms before Step 4

---

## Step 4 — B-5: Divergent Line and Inline Spacing Across Platforms

**Effort:** 2–3 days | **Files:** `src/core/mormot.ui.report.pas`,
`src/core/mormot.ui.pdfcanvas.pas` | **Demo:** `markdown_demo`

### Symptom — Confirmed Across All Three Platforms

The supplied `markdown_demo_windows.pdf`, `markdown_demo_linux.pdf` and
`markdown_demo_mac.pdf` (4 pages each, same source) show the divergence directly:

| Observation | Windows | Linux | macOS |
|---|---|---|---|
| Intro paragraph (p1) wraps after | "structured" | "structured content." (fits) | "structured" |
| "All headings **become**" (p1) | wraps to line 2 | stays on line 1 | wraps to line 2 |
| Inline run gaps | wide, uneven (`italic , code   and`) | tight (`italic, code and`) | even (`italic, code and`) |
| Page-1 content ends at | Custom Format block | Custom Format block | Custom Format block |
| Page-3 (Compact/Times) intro wraps after | "inline" | "inline" | "inline" |

So **Linux fits more text per line than Windows/macOS**, and the inline gap
defect is worst on Windows — visible as stray whitespace around `code` and after
`italic` in `markdown_demo_windows.pdf` page 1 ("`italic , code   and links`"),
where Linux renders "`italic, code and links`" with no such gaps.

Page count happens to stay at 4 on all three here, so the drift has not yet
crossed a page boundary in this demo — but the per-line differences are the same
mechanism that would cause it in a longer document.

**Measured proof of the inline defect** (from the macOS content stream, base-14
Helvetica, whose AFM widths are authoritative because the viewer draws with them):

| Run | Advance emitted | Nominal AFM width | Error |
|---|---|---|---|
| `'Inline styles like '` | 80.25 | 80.08 | +0.17 |
| `'bold'` (Helv-Bold 11) | 22.50 | 20.79 | **+1.71** |
| `', '` | 6.00 | 6.12 | −0.12 |
| `'italic'` | 22.50 | 22.00 | +0.50 |

Every advance is quantised to a multiple of 0.75pt (= 1 px at 96 DPI), and `bold`
overshoots its true width by 1.71pt. The X positions are therefore **LCL integer
pixel measurements scaled to points**, not font advances — accumulating visible
gaps across a nine-run sentence.

### Root Cause

Layout is measured with the **LCL**, but rendered with the **PDF font backend** —
two different font engines that disagree on metrics.

**Line spacing is pixel-quantised too, and `LineHeightFactor` is not reaching the
output.** Every baseline delta in the macOS content stream is an exact multiple of
0.75pt (= 1 px @ 96 DPI). For 11pt body text on page 1 the delta is **14.25pt =
19 integer pixels**, i.e. a factor of 1.2955 relative to the font size — but the
demo's page-1 format specifies `LineHeight=1.1`, which should give
`11 × 1.1 = 12.1pt`. So the advance is not `FontSize × LineHeightFactor` at all;
it is an LCL pixel height that happens to absorb the platform's own leading, then
gets multiplied. This is why the three platforms disagree: each widgetset returns
a different integer pixel height for the same nominal font.

Both affected quantities come from `fMeasureBitmap.Canvas`:

- **Line spacing:** `LineHeightMM` calls `SetupMeasureFont` to sync
  `fMeasureBitmap.Canvas.Font` to `fFontName`/`fFontSize`/`fFontStyle`, then the
  per-line advance is `Round(FontTextHeight * LineHeightFactor)`
  (`.claude/skills/report-engine.md` — Measurement, and R-8 `LineHeightFactor`).
  `FontTextHeight` is an LCL text height, which is computed by the platform
  widgetset: GDI on Windows, and the gtk/Qt or Cocoa backend on Linux/macOS.
  These differ in how they round, and in whether they include internal leading.
- **Inline advance:** the no-coordinate `DrawText`/`DrawStrong`/`DrawEm`/`DrawCode`
  overloads advance `CurrentX` by a measured text width from the same LCL canvas,
  while the glyphs are actually placed using the PDF font's widths.

So the error is not a single wrong constant — the measuring engine and the
rendering engine are different per platform. This is the **same class of defect
as B-4 (Step 5)**; this step builds the shared measurement abstraction that
B-4 then reuses, which is why it runs first.

Note that `CELL_PADDING = 200` (2 mm) and similar constants are platform-neutral
and are *not* the problem; only the measured components drift.

### Steps

1. **Reproduce and quantify first.** Run `markdown_demo` on all three platforms
   and dump the measured metrics before changing anything:
   ```pascal
   WriteLn('font=', fFontName, ' size=', fFontSize,
           ' textheight=', FontTextHeight, ' lineheight=', LineHeightMM);
   ```
   This shows whether the divergence is a constant factor (a rounding or
   internal-leading difference, fixable by normalisation) or font-dependent (the
   platforms resolved different physical faces — then it is a font-resolution
   problem, though the Linux `pdf_demo` output makes that unlikely).

1b. **Check whether `LineHeightFactor` is applied to the right base.** The measured
   14.25pt for 11pt/1.1 text suggests the factor multiplies an LCL pixel height
   rather than the font size. Decide the intended definition and document it —
   changing the base will change every existing layout, so this is a deliberate
   behaviour change, not a silent fix.

2. **Measure through the PDF font backend, not the LCL.** Route
   `FontTextHeight`/text width through `IPdfPlatformFont` metrics
   (`GetTextMetrics` / `GetOutlineMetrics` / `GetCharABCWidths`, see
   `.claude/skills/platform-backends.md`) so measurement and rendering use one
   engine. The backend is already per-platform, but it is the *same* engine that
   places the glyphs — which is what makes the layout consistent.

3. **Derive line height from font metrics, not a widgetset text height:**
   ```pascal
   // ascender + descender + lineGap from the font, in 1000/em units,
   // scaled by font size — identical on every platform for the same face
   LineHeight := Round((Ascender + Descender + LineGap) * FontSize / 1000
                       * LineHeightFactor);
   ```
   `TPdfCanvas` already exposes `TextWidth` in PDF points; prefer it over the
   LCL path.

4. **Keep the LCL path only for the on-screen preview** where no PDF font is
   active, and make the fallback explicit rather than implicit. The preview may
   legitimately differ slightly from the PDF; the three *PDF* outputs may not.

5. **Round once, late.** Convert to 1/100 mm at the end of the calculation
   instead of rounding each intermediate step — per-line rounding is what lets a
   sub-pixel difference accumulate into a whole extra page.

6. **Guard with a test.** Add a test to `tests/test_report_crossplatform.pas`
   asserting expected line count and total text block height for a fixed font and
   string, so a platform metric change is caught rather than discovered visually.

### Verification

```bash
lazbuild examples/markdown_demo/markdown_demo.lpi -B
# Run on Windows, Linux and macOS, then compare:
pdfinfo markdown_demo.pdf | grep Pages        # identical page count
qpdf --qdf --object-streams=disable markdown_demo.pdf - | grep -E "Td|TD|Tj"
```

- Same page count and same number of lines per paragraph on all three platforms
- Baseline deltas are no longer all multiples of 0.75 pt (the 1 px @ 96 DPI
  quantisation is gone), and 11 pt body text with `LineHeightFactor = 1.1`
  advances by ~12.1 pt rather than the current 14.25 pt
- Inline advances match the AFM widths: `'bold'` ≈ 20.79 pt, not 22.50 pt
- Content-stream diff across the three platforms: `Td` positions agree
- Preview still renders sensibly (LCL fallback path intact)
- Gate: accept the deliberate layout change (all reference PDFs are regenerated
  at this step) before Step 5

---

## Step 5 — B-4: Wrong Text Bounding Boxes in Graphics (Linux/macOS)

**Effort:** 1–2 days | **Files:** `src/core/mormot.ui.pdfcanvas.pas`,
`src/platform/unix/mormot.pdf.freetype.pas` | **Demos:** `pdf_demo`,
`markdown_demo`

### Symptom — Corrected After Reviewing `pdf_demo_linux.pdf`

**The characters are not corrupt.** Page 2 of the supplied `pdf_demo_linux.pdf`
renders the digits 1–10 correctly as digits — no boxes, no wrong glyphs, no
missing characters. What is wrong is the **bounding box around each digit**: the
rectangles are far too narrow and too short, hugging the glyph and clipping it,
and the mismatch grows with each font-size increment through the loop.

This **resolves the (a)/(b) question below in favour of (b)** — a measurement
defect, not a font-resolution defect. The roadmap's earlier "corrupted
characters" framing was wrong and is kept here only to explain the correction.

The affected block is the digit loop that draws each label together with a
bounding box derived from `TextWidth`/`TextHeight`:

```pascal
for MyX := 1 to 10 do
begin
  MyString := IntToStr(MyX);
  C.TextOut(MyXLoc, MyY, MyString);
  C.Rectangle(MyXLoc, MyY,
    MyXLoc + C.TextWidth(MyString),
    MyY + C.TextHeight(MyString));
  C.Font.Size := C.Font.Size + 2;
end;
```

### Cause Confirmed: (b) Measurement

Retained for the record — (a) is now ruled out by the Linux output:

**(a) Wrong glyphs / boxes — a font path problem.** RULED OUT: glyphs are correct. The character codes written to
the content stream do not resolve through the embedded font's CMAP. Likely where
the FreeType backend selected a fallback face (DejaVu Sans) while the font
dictionary still describes the requested face, so code → glyph mapping is
inconsistent.

**(b) Right glyphs, wrong boxes — a measurement problem.** `TPdfVclCanvas.TextWidth`
/`TextHeight` delegate to the LCL via `fMeasureDC`. On Linux/macOS that measures
with the **LCL's** font resolution, while the PDF text is set with the FreeType
face — so the rectangles do not match the drawn text, which reads as "broken"
even though the glyphs are correct.

**Evidence so far points to (b).** `pdffonts` on the existing macOS build
`examples/pdf_demo/bin/aarch64-darwin/output_crossplat.pdf` shows only the
non-embedded base-14 Type1 faces:

```
Helvetica-Bold  Type 1  WinAnsi  emb=no sub=no uni=no
Helvetica       Type 1  WinAnsi  emb=no sub=no uni=no
Times-Roman     Type 1  WinAnsi  emb=no sub=no uni=no
Courier         Type 1  WinAnsi  emb=no sub=no uni=no
```

No FreeType face is embedded at all, so there is no DejaVu substitution and no
custom CMAP in play — cause (a) is unlikely for *this* demo. With base-14 fonts
the glyphs are drawn by the **viewer's** Helvetica, while `TextWidth`/`TextHeight`
measure with the **LCL's** resolved Helvetica. That is exactly cause (b).

Remaining diagnostic, to confirm before coding:
```bash
# Which codes and font are actually used per text run:
mutool draw -F txt output_crossplat.pdf     # or: qpdf --qdf --object-streams=disable
pdffonts output_crossplat.pdf
```
Note `qpdf`, `mutool` and `veraPDF` are **not installed** on this machine
(`pdffonts`/`pdfinfo` from poppler are) — install via
`brew install qpdf mupdf-tools` before relying on the commands above.

### Steps — Measurement Path

Cause (a) is ruled out, so the FreeType-fallback logging work is dropped. Note the
demo uses **non-embedded base-14 Helvetica**, so the correct reference widths are
the standard AFM widths — which the PDF viewer uses to draw, and which the LCL
does *not* reproduce.

1. Make `TextWidth`/`TextHeight` measure through the **same** font backend that
   renders the text. `TPdfCanvas` already exposes `TextWidth` in PDF points
   (`.claude/skills/pdf-engine.md`); prefer delegating to it over `fMeasureDC`
   when a PDF font is active.
2. Keep the LCL path only as a fallback for when no PDF font is selected yet.
3. Check `TextHeight` against the FreeType ascender/descender rather than the LCL
   line height — these differ per platform.
4. Reuse the measurement abstraction built in **B-5 (Step 4)** rather than adding a
   second one here. B-5 runs first precisely so this step becomes a thin adapter
   over `IPdfPlatformFont` instead of a parallel implementation.

### Verification

```bash
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B
# Run on Linux, macOS and Windows; compare page 2 of the three PDFs
pdffonts pdf_demo.pdf   # requested face embedded, no unexpected fallback
```

- Each bounding box encloses its digit correctly at every font size — the
  clipping visible in `pdf_demo_linux.pdf` page 2 is gone
- Boxes are identical across the three platforms (content-stream diff)
- Digits still render correctly (they already did — guard against regression)

---

## Step 6 — P-6: Font Embedding for Tagged PDF

**Effort:** 1–2 days | **Files:** `src/core/mormot.ui.pdf.pas`,
`src/core/mormot.ui.report.pas` | **Demos:** `pdf_demo`, `markdown_demo`

### Technical Background

Tagged PDF targets accessibility, and PDF/UA-1 requires that all glyphs be mapped
back to Unicode — which in practice requires embedded fonts with a correct
`/ToUnicode` CMap. The two font modes documented in `CLAUDE.md` are today
independent of `Tagged`:

| Mode | Property | Embedding |
|---|---|---|
| Type1 | `StandardFontsReplace := True` | none (Helvetica/Times/Courier) |
| TrueType | `EmbeddedTTF := True` | yes |

With `StandardFontsReplace := True` a tagged document relies on the viewer's
non-embedded base-14 fonts, which PDF/UA does not permit. `Tagged := true`
already auto-raises `FileFormat` to `pdf17` via `SetTagged`; embedding should
follow the same pattern.

**Confirmed against real output.** Both existing macOS builds are tagged
(`pdfinfo` → `Tagged: yes`) yet embed nothing —
`output_crossplat.pdf` carries Helvetica/Helvetica-Bold/Times-Roman/Courier and
`markdown_demo.pdf` carries seven base-14 faces, every one
`emb=no sub=no uni=no`. So this is not a latent risk: **every tagged PDF the
project currently produces would fail PDF/UA** on the embedding and
Unicode-mapping rules. `uni=no` also means text extraction has no reliable
`/ToUnicode` round-trip, which is why step 2 matters as much as step 1.

### Steps

1. **Couple embedding to `Tagged` in `SetTagged`** (`mormot.ui.pdf.pas`):
   ```pascal
   procedure TPdfDocument.SetTagged(Value: boolean);
   begin
     fTagged := Value;
     if Value then
     begin
       if fFileFormat < pdf17 then
         fFileFormat := pdf17;         // existing behaviour
       fEmbeddedTtf := true;           // PDF/UA needs embedded fonts
     end;
   end;
   ```
   Do **not** silently clear `StandardFontsReplace` — instead raise
   `ESynException` if both `Tagged` and `StandardFontsReplace` are set, so the
   conflict surfaces at development time rather than at validation time.

2. **Guarantee `/ToUnicode` for every embedded font.** Verify it is written for
   both the WinAnsi and the Unicode instance of the dual-instance model
   (`.claude/skills/fonts.md` §1) — a missing `/ToUnicode` on either makes text
   unextractable and fails PDF/UA.

3. **Use whole-TTF embedding while `Tagged` is on.** Subsetting is documented as
   unreliable for RTL and unsafe for CJK (`fonts.md` §9–10); a subset that drops
   glyphs also breaks the Unicode round-trip that tagging depends on. Set
   `EmbeddedWholeTtf := true` when `Tagged` is enabled, and document the file-size
   trade-off.

4. **Pass it through `TGDIPages`** (`mormot.ui.report.pas`): when
   `ExportPdfTagged = true`, set embedding on the created `TPdfDocument` so
   `markdown_demo` inherits it without demo-side changes.

5. **Update the demos** to drop any now-redundant manual embedding flags, and note
   in `docs/DEMOS.md` that tagged export implies embedded fonts.

### Verification

```bash
lazbuild examples/markdown_demo/markdown_demo.lpi -B && ./examples/markdown_demo/bin/markdown_demo
pdffonts markdown_demo.pdf
# Every font: "emb" = yes, "uni" = yes
veraPDF --flavour ua1 markdown_demo.pdf
```

- No non-embedded font in any tagged PDF
- Copy/paste out of the PDF returns the original text (proves `/ToUnicode`)
- `Tagged := true` together with `StandardFontsReplace := true` raises a clear error

---

## Rest — Remaining Items

Lower priority than the bugfixes above.

### Table Row Pagination

**Effort:** 2–3 days | **File:** `src/core/mormot.ui.report.pas`

A table row taller than the remaining page space currently forces a full page
break before the row. Allow the row to split: emit partial cell content on the
current page and continue on the next. Interacts with Bugfix 2 — a split row's
cells must stay inside one `TR` element referencing both pages.

### TTC Font Collections

**Effort:** 1 day | **Files:** `src/platform/unix/mormot.pdf.freetype.pas`,
`src/core/mormot.pdf.types.pas`

Only face index 0 of a `.ttc` is reachable because `TPdfFontMap` has no face
index. Add one so the remaining faces can be selected by name.

### Font Subsetting for RTL and CJK

**Effort:** 3–5 days | **File:** `src/core/mormot.ui.pdf.pas`

`EmbeddedWholeTtf := False` is opt-in and unreliable for RTL (GSUB-substituted
glyph IDs are not tracked) and unsafe for CJK — see `.claude/skills/fonts.md`
§9–10. Tracking shaped glyph IDs through the HarfBuzz/Uniscribe path would make
subsetting safe and remove the file-size cost of Priority 6 step 3.

### RTL Shaper Advance Path — Test Coverage

**Effort:** 0.5 day | **File:** `tests/`

Linux fonts (Noto Naskh Arabic) resolve shaped glyphs through the CMAP, so the
shaper's own advance path is never exercised. Add a test against a font without
Arabic presentation forms — see `.claude/skills/fonts.md` §10.

### EMF/MetaFile and GDI+ Gradients

Windows-only (`TPdfDocumentGdi`), not portable. No work planned.

---

## Summary Table

### Open

| ID | Item | Effort | Files |
|---|---|---|---|
| B-2 | Tags at line breaks | 1–2 days | mormot.ui.report.pas, mormot.ui.pdf.pas |
| B-3 | Tags on inline text | 1–2 days | mormot.ui.report.pas |
| B-4 | Wrong text bounding boxes in graphics (Linux/macOS) | 1–2 days | mormot.ui.pdfcanvas.pas |
| B-5 | Divergent line/inline spacing across platforms | 2–3 days | mormot.ui.report.pas, mormot.ui.pdfcanvas.pas |
| P-6 | Font embedding for Tagged PDF | 1–2 days | mormot.ui.pdf.pas, mormot.ui.report.pas |
| R-10 | Table row pagination | 2–3 days | mormot.ui.report.pas |
| R-11 | TTC face index | 1 day | mormot.pdf.freetype.pas, mormot.pdf.types.pas |
| R-12 | Subsetting for RTL/CJK | 3–5 days | mormot.ui.pdf.pas |
| R-13 | RTL shaper advance test | 0.5 day | tests/ |

**Execution order** (agreed): one fix at a time, each verified on all three
platforms before the next begins — see [Working Method](#working-method).

| Step | ID | Rationale for this position |
|---|---|---|
| ~~1~~ | ~~B-1~~ | **Done** — built the element tree that B-2 and B-3 need |
| 2 | B-2 | Needs B-1's tree; introduces multi-MCID leaves |
| 3 | B-3 | Needs B-1's tree; reuses B-2's `BlockId` |
| 4 | B-5 | **Before B-4**: decides what `LineHeightFactor` multiplies, which changes every existing layout and would invalidate any B-4 verification done earlier |
| 5 | B-4 | Thin adapter over the measurement abstraction B-5 builds |
| 6 | P-6 | Last: until it lands, PAC reports font-embedding errors on every run |

The remaining R-items are independent and unscheduled.

### Completed Work

| ID | Feature | Files |
|---|---|---|
| P1-A | fonts.md §10b status corrected | .claude/skills/fonts.md |
| P1-B | CJK on Linux/macOS (per-platform `CJK_FONT`) | chinese_demo, freetype.pas |
| P1-C | PDF 1.7 output (`FileFormat`, PDF/A + Tagged auto-upgrade) | mormot.ui.pdf.pas, mormot.pdf.types.pas, report.pas |
| P2-A | HarfBuzz RTL shaping on Linux/macOS | harfbuzz.pas (new), types.pas, pdf.pas |
| P2-C | Font zoom in preview (`FontScale`) | mormot.ui.report.pas |
| P3 | Tagged PDF — text structure tags | mormot.ui.pdf.pas, mormot.ui.report.pas |
| R-1 | AES-128 encryption (`TPdfEncryptionAES128`) | mormot.ui.pdf.pas |
| R-2 | Cross-reference streams (pdf15+) | mormot.ui.pdf.pas |
| R-3 | Object streams (pdf15+) | mormot.ui.pdf.pas |
| R-4 | XMP metadata | mormot.ui.pdf.pas |
| R-5 | Table structure tags (`dckBeginTR`/`dckEndTR`) | mormot.ui.pdf.pas, mormot.ui.report.pas |
| R-6 | Figure tags + `/Alt` | mormot.ui.pdf.pas, report.pas |
| R-7 | Transparency (`SetFillAlpha`/`SetStrokeAlpha`) | mormot.ui.pdf.pas |
| R-8 | `LineHeightFactor` property | mormot.ui.report.pas |
| R-9 | Table header repeat on page break | mormot.ui.report.pas |
| B-1 | Nested struct tags (tables, lists) — see [Result (Step 1)](#result-step-1) | mormot.pdf.types.pas, mormot.ui.pdf.pas, mormot.ui.report.pas |

Note on R-5/R-6: table and figure tags were *emitted* but landed flat in the
structure tree; B-1 completed them.
