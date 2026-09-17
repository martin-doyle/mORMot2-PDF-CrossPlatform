# mORMot PDF Cross-Platform — Implementation Roadmap

This document describes all planned improvements with full technical background,
affected files, implementation steps, and verification criteria.

**Current baseline:** All previously planned features (P1-A … P3, R-1 … R-9) plus
Steps 1, 2, 3, 4 and 5 (B-1, B-2, B-3, B-5, B-4) are implemented. The structure tree is now
properly nested, with `Table > TR > TH|TD` and `L > LI > LBody` as real
hierarchy levels; a wrapped paragraph is one `P` instead of one `P` per line —
across a page break as well; and a sentence with inline styling is one `P` whose
styled runs are `Span` kids, in reading order. Layout is measured with the PDF
font engine instead of the LCL, so line breaking and inline advances no longer
depend on the widgetset, and `TPdfVclCanvas` measures text with the same font
engine, in `single` precision. The open work is font embedding for tagged
output.

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
- ~~B-3: one visual line (`Y=447.5`) is split into **nine** top-level `P`
  elements, MCID 18–26; even a bare `", "` separator becomes its own
  paragraph~~ — **fixed in Step 3**, reproduced first on a fresh Linux run
  (same nine elements at `Y=365`)
- ~~B-4: **characters are correct** on Linux — only the `TextWidth`/`TextHeight`
  bounding boxes are wrong. Cause (a), FreeType fallback, is ruled out~~
  — **fixed in Step 5**; the boxes were 19–27% too narrow and quantised to
  0.75pt, reproduced first on a fresh Linux run
- ~~B-5: Linux fits more text per line than Windows/macOS; inline advances are
  quantised to 0.75pt (1 px @ 96 DPI) and `bold` misses its AFM width by 0.72pt~~
  — **fixed in Step 4**; the `bold` figure is corrected there (the original
  1.71pt used the Helvetica *regular* widths)
- P-6: every tagged PDF currently produced embeds nothing (`emb=no`, `uni=no`)
- ~~B-6: `pdf_demo.pdf` page 2 is unparsable — `/Alt` is written as a bare
  token, so Acrobat reports a damaged page and PAC aborts with "unexpected
  token"~~ — **fixed in Step 5b**

What is **still not verified** and must be settled during implementation:

| Unknown | Needed for | How to settle |
|---|---|---|
| ~~Actual body of `BeginStructContent`, `SerializeStructTree`, `TPdfStructElement`~~ | ~~B-1~~, B-2, B-3 | **Settled in Step 1.** Note the naming: the serializer is `SerializeStructTree`, not `BuildStructTree`, and the class is `TPdfStructElement`. MCIDs come from the per-page counter `TPdfPage.fCurrentMCID`, not from `fStructParents * 1000` |
| ~~Whether `TDrawCommand` can take new fields without breaking the recording array~~ | ~~B-2~~, B-3 | **Settled in Step 2.** It can: every producer builds the record with `Default(TDrawCommand)` and `AddCommand` copies it wholesale, so `BlockId` was added without touching any other call site |
| ~~How `RenderPageToCanvas` currently chooses a role per command~~ | ~~B-2, B-3~~ | **Settled in Step 1.** A `case Cmd.Kind` block with the local flags `InTableRow`, `InHeaderRow` and `InListItem` |
| ~~A wrapped paragraph's MCID pattern (B-2's premise)~~ | ~~B-2~~ | **Confirmed in Step 2** against a freshly built `markdown_demo.pdf`: MCID 3 + 4 were two sibling `P` elements holding the two lines of one paragraph, each with a single `/MCR` |
| Per-platform `FontTextHeight` / `LineHeightMM` values | B-5 | instrument and run on all three platforms |

**Toolchain on the Linux development machine:** `lazbuild` lives at
`/home/parallels/fpc-fixes/lazarus/lazbuild` (not on `PATH`) and the mORMot2
sources at `/home/parallels/synopse/mORMot2`. Compilation works; linking the
demos needs `libgtk2.0-dev`, whose development symlinks are absent, so the
runtime GTK2 libraries cannot be found by `ld`. Workaround used in Step 2
without root: symlink `libgtk-x11-2.0.so`, `libgdk-x11-2.0.so` and
`libatk-1.0.so` to their `.so.0` files in a scratch directory and build with
`lazbuild --opt=-Fl<dir>`. `qpdf`, `mutool` and `veraPDF`
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

## Step 2 — B-2: Tags at Line Breaks — **DONE (2026-09-17)**

**Effort:** 1–2 days | **Files:** `src/core/mormot.ui.report.pas`,
`src/core/mormot.ui.pdf.pas`, `src/core/mormot.ui.pdfcanvas.pas` |
**Demos:** `pdf_demo`, `markdown_demo`

Implemented and verified on Linux. The analysis below is kept for the record;
what was actually built is in [Result](#result-step-2) at the end of this step.

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

### Result (Step 2)

Implemented on 2026-09-17, built and run on Linux. Windows (PAC 2024) and macOS
verification is still outstanding; the cross-platform gate above is therefore
not yet closed. `veraPDF` is still not installed on the development machine.

What was built, against the plan above:

| Plan | Implementation |
|---|---|
| 1. Logical block id | `TDrawCommand.BlockId: Integer` (0 = standalone). The id is not assigned per public `Draw*` entry point but once in `RecordWrappedText`, the single place where wrapping happens — which covers `DrawTextWrapped`, `DrawParagraph`, `DrawQuote`, `Columns2` and `DrawListItem` in one stroke. The previous value is restored in the `finally`, so nested use stays correct. |
| 2. Open on block change | `RenderPageToCanvas` tracks `fRenderBlockId`/`fRenderBlockElem`/`fRenderBlockOpen` — fields, not locals, because a block outlives one call. Any command other than `dckDrawText` closes the open block, so BDC never wraps graphics or a table container. |
| 3. Multiple MCIDs per element | `TPdfStructElement.MCID` became `MCIDs`/`MCIDPages` + `MCIDCount`. A leaf writes `/K <</Type/MCR /MCID n>>` for one region and an MCR array for several, each entry carrying `/Pg` when it differs from the element's own `/Pg`. `/ParentTree` is now built per (page, MCID) pair, so a continued element is listed in both pages' arrays. |
| 4. Page-break continuation | New `TPdfCanvas.LastStructContent` + `ResumeStructContent(Index)` (delegated by `TPdfDocumentVcl`): the element is pushed back onto `fStructStack` and gets a fresh MCID on the current page. Parent and kids stay untouched. |
| 5. Balanced BDC/EMC per page | The block is closed at the end of the command loop with the id kept, so the next page reopens the same element instead of starting a new one. `ExportPdfStream` resets the block state before the page loop, and `RenderPageToCanvas` resets it whenever `fActivePdfDoc = nil`, so preview and printing never inherit it. |

**Deviation from the verification list.** Step 2 asks for the region to stay
open across lines, while the verification bullet below asks for one MCID per
line; the two contradict each other. The implementation follows the step: a
paragraph owns **one MCID per page**, not one per line. ISO 32000-1 §14.7 allows
a marked-content region to contain any number of text objects, and fewer regions
means fewer `/ParentTree` entries.

Measured on the regenerated `markdown_demo.pdf`: the two-line paragraphs of
page 1 (`… structured content.` and `… headings with | automatic PDF bookmarks …`)
are now one `P` with one MCID each; the nesting from B-1 is unchanged. A
dedicated page-break test produced
`/K [<</Type/MCR /MCID 22>> <</Type/MCR /Pg 10 0 R /MCID 0>>]` with the element
listed in the `/ParentTree` arrays of both pages, and BDC/EMC balanced per
content stream (23/23 and 1/1). Test suite: 115/115 assertions, all six demos
build.

**Note for Step 3.** `BlockId` is in place and B-3 can reuse it: the inline runs
of one line (`Inline styles like | bold | , | italic …`, still nine `P` elements)
need a shared block id plus `psrSpan` leaves inside one `P`, which is a
container-with-leaves shape the B-1 stack already supports.

---

## Step 3 — B-3: Tags on Inline Text — **DONE (2026-09-17)**

Implemented and verified on Linux. The analysis below is kept for the record;
what was actually built is in [Result](#result-step-3) at the end of this step.

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

### Result (Step 3)

Implemented on 2026-09-17, built and run on Linux, and **accepted on Linux**.
Windows (PAC 2024) and macOS verification is still outstanding; the
cross-platform gate above is therefore not yet closed. `veraPDF` is still not
installed on the development machine.

What was built, against the plan above:

| Plan | Implementation |
|---|---|
| 1. Mark inline commands | `TDrawCommand.IsInline: boolean` plus `InlineStyle: TInlineStyle` (`isPlain`, `isStrong`, `isEm`, `isCode`, `isLink`). Both are stamped in `EmitTextCmd` from the transient fields `fEmitInline`/`fEmitInlineStyle`. As predicted, all five coordinate-less overloads funnel through `DrawText(const S)`, so the shared `BlockId` (`fInlineBlockId`, allocated lazily from `fNextBlockId`) is assigned in that one place. The line is closed — and the next run gets a fresh id — in `MoveToNextLine`, in `NewPage` and at the start of `RecordWrappedText`. |
| 2. Map inline runs to `psrSpan` | `RenderPageToCanvas` opens the enclosing element for an inline line with the new `BeginStructGroup` instead of `BeginStructContent`, i.e. **without** a marked-content region. A styled run then calls `SuspendStructContent` + `BeginStructContent(psrSpan)`; the role of the enclosing element is unchanged (`P`, or `TH`/`TD`/`LBody`/`Hx` in context) and was factored out into the local `TextStructRole`. |
| 3. Plain runs untagged | Achieved as specified: a plain run calls `ContinueStructContent`, which adds one more MCID to the enclosing element rather than creating an element. This needed the `/K` of a struct element to mix its own `/MCR` dicts with kid references **in reading order**, so `TPdfStructElement` gained `MCIDSeqs`/`KidSeqs`/`SeqNext` and `SerializeStructTree` merges both by rank. A leaf without kids keeps its previous single-`/MCR` or `/MCR`-array form. |
| 4. Richer roles than `Span` | Not implemented. ISO 32000-1 has no `Code` role, and a bare `Span` is the correct representation; adding `/ActualText` or `/Alt` holding the very same string the run already draws would be pure duplication. Revisit only if a reader is shown to need it. |

**Why a plain `Span` per run was rejected.** Wrapping every run — plain ones
included — in a `Span` would have been a two-line change, but keeping one
single region for all plain runs of the line destroys the reading order: the
plain text would be one MCID listed before all `Span` kids, so a reader
announces *"Inline styles like , , and can be mixed inline."* followed by
*"bold italic code links"*. Hence the suspend/continue primitives and the
ordered `/K`.

Measured on the regenerated `markdown_demo.pdf`, page 1:

```
/P    <</MCID 15>> BDC (Inline styles like )   Tj ET EMC
/Span <</MCID 16>> BDC (bold)                  Tj ET EMC
/P    <</MCID 17>> BDC (, )                    Tj ET EMC
/Span <</MCID 18>> BDC (italic)                Tj ET EMC
…
/P    <</MCID 23>> BDC ( can be mixed inline.) Tj ET EMC
```

`63 0 obj <</Type/StructElem/S/P … /K[<</MCR/MCID 15>> 64 0 R <</MCR/MCID 17>>
65 0 R <</MCR/MCID 19>> 66 0 R <</MCR/MCID 21>> 67 0 R <</MCR/MCID 23>>]>>` —
the nine top-level `P` elements of MCID 15–23 are **one** `P` with four `Span`
kids, and `/ParentTree` maps MCID 15/17/19/21/23 back to that `P` and 16/18/20/22
to their `Span`. Across the whole file: `P` 68 → 52, `Span` 0 → 8, BDC/EMC
balanced per page (45/45, 89/89, 46/46, 88/88).

**Regression evidence.** A HEAD worktree was built and run in the same
environment for a like-for-like baseline: the drawing operators of
`markdown_demo.pdf` are identical with the tagging operators stripped, and
`pdf_demo`'s content stream *and* struct tree are byte-identical (it drives
`BeginStructContent` directly and never takes the new path). Test suite
115/115 assertions, all six demos build.

**Note on the environment.** Font measurement differs without an X display, so
this machine produces a 4-page `markdown_demo.pdf` where the committed
reference files have 5. Only compare runs made in the same environment.

---

## Step 4 — B-5: Divergent Line and Inline Spacing Across Platforms — **DONE (2026-09-17)**

Implemented and verified on Linux. The analysis below is kept for the record;
what was actually built is in [Result](#result-step-4) at the end of this step.

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
| `'bold'` (Helv-Bold 11) | 22.50 | 23.22 | **−0.72** |
| `', '` | 6.00 | 6.12 | −0.12 |
| `'italic'` | 22.50 | 22.00 | +0.50 |

Every advance is quantised to a multiple of 0.75pt (= 1 px at 96 DPI), and
`bold` is measured 0.72pt *short* of its true width. The X positions are
therefore **LCL integer pixel measurements scaled to points**, not font
advances — accumulating visible gaps across a nine-run sentence.

> Correction (Step 4 implementation): the 20.79 originally recorded here as the
> nominal width of `'bold'` is the **Helvetica regular** sum (556+556+222+556);
> Helvetica-**Bold** is 611+611+278+611 = 2111, i.e. 23.22pt at 11pt. The
> defect is real either way — the emitted advance matched neither — but the
> direction of the `bold` error was the opposite of what was written.

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
- Inline advances match the AFM widths: `'bold'` ≈ 23.22 pt, not 22.50 pt
- Content-stream diff across the three platforms: `Td` positions agree
- Preview still renders sensibly (LCL fallback path intact)
- Gate: accept the deliberate layout change (all reference PDFs are regenerated
  at this step) before Step 5

### Result (Step 4)

Implemented on 2026-09-17, built and run on Linux, and **accepted on Linux on
2026-09-17** — including the deliberate layout change, so every reference PDF is
regenerated from this step on. Windows and macOS verification is still
outstanding, so the cross-platform gate above is not yet closed — but note that
the layout is now computed from font data alone, with no widgetset value
anywhere in the path, so the three streams are expected to agree by
construction rather than by luck.

What was built, against the plan above:

| Plan | Implementation |
|---|---|
| 1. Reproduce and quantify | Done before any change, on a fresh Linux build. Baseline deltas were all multiples of 0.75pt; 11pt body text with `LineHeightFactor=1.1` advanced by **16.5pt = 22px** (macOS: 14.25pt = 19px — the divergence is exactly one screen pixel). Inline advances matched neither AFM nor each other. |
| 1b. `LineHeightFactor` base | Decided: **`FontSize × LineHeightFactor`**, in PDF points. This is what the verification gate below asks for and what the property has always claimed to be (`report-engine.md`: "line spacing multiplier"). The alternative in step 3 of the plan — `(Ascender+Descender+LineGap) × FontSize / 1000 × Factor` — was rejected: it would give 13.5pt for 11pt Helvetica, contradicting the gate, and `otmLineGap` is not a line gap in the FreeType backend (it returns `ascent − descent`). **Consequence:** a face whose ascender+descender exceeds 1.1 em is now set slightly tight at the default factor; raise `LineHeightFactor` per format rather than reintroducing a platform-dependent base. |
| 2. Measure through the PDF font backend | New `TPdfFontMeasurer` / `TPdfFaceMetrics` in `mormot.ui.pdf.pas` — document-independent access to the very widths the output will use. It repeats `TPdfCanvas.SetFont`'s resolution order: the base-14 AFM tables (`STANDARDFONTS`) when `ExportPdfStandardFonts` is set and the name is Helvetica/Times/Courier or an alias, otherwise `PdfPlatformFont.CreateFont` + `GetCharABCWidths(32,255)` on a `lfHeight = -1000` DC, i.e. 1000-per-em units. Faces are cached per (name, bold, italic, standard-flag); one font creation per style per report. |
| 3. Derive line height from metrics | `LineHeightMM` is now `PointsToMM100(fFontSize * fLineHeightFactor)` — see 1b. `LineHeightPx` was reduced to `MMToPixels(LineHeightMM, 96)` so nothing reads the LCL height any more. |
| 4. LCL path for the preview only | Kept and made explicit: `MeasureTextWidthPt` returns −1 when no face resolves, and every caller then falls back to `fMeasureBitmap.Canvas`. In practice both backends always resolve something (FreeType falls back to DejaVu, GDI substitutes), so the fallback fires only when no platform backend is registered at all. |
| 5. Round once, late | `RecordWrappedText` now accumulates word and space widths as unrounded `single` PDF points and compares against `MaxWidthMM × 72/2540`; only the emitted Y is converted to 1/100 mm. The old code round-tripped every word through `PixelsToMM`/`MMToPixels`. |
| 6. Guard test | `TestPlatformIndependentMetrics` in `tests/test_report_crossplatform.pas`: asserts that Helvetica 10pt measures `'Hello'` at its AFM width (2278/1000 em, derived in the test from the Adobe AFM, not from our code), that `'Hello Hello'` wraps at exactly its own width, and that two wrapped lines sit exactly `FontSize × Factor` apart. |

**One thing the plan did not foresee.** Measuring correctly was not enough: the
`TGDIPages → TPdfVclCanvas` bridge went through `TCanvas.TextOut(X, Y: integer)`,
so every position was snapped back to the 1 px @ 96 DPI grid *after* the layout
had computed it. `TPdfVclCanvas.TextOutFrac(X, Y: single)` was added and
`RenderPageToCanvas` uses it when the target canvas is the PDF bridge; the
preview keeps the integer path, which draws on a pixel grid anyway. Without
this, the 0.75pt quantisation in the verification list below survives the fix.

Measured on the regenerated `markdown_demo.pdf`, page 1:

| Quantity | Before | After | Expected |
|---|---|---|---|
| Body baseline delta (11pt, factor 1.1) | 16.50 | **12.11** | 12.10 |
| `'Inline styles like '` advance | 80.25 | **80.11** | 80.08 |
| `'bold'` advance (Helv-Bold 11) | 22.50 | **23.22** | 23.22 |
| Baseline deltas that are multiples of 0.75 | all | none | — |
| Page count | 4 | 4 | unchanged |

The residual 0.03pt on the first run is the 1/100 mm coordinate grid of
`TGDIPages` itself — deterministic, identical on every platform, and it does
not accumulate because each X is re-derived from the recorded command.

**Regression evidence.** `pdf_demo`'s text positions are byte-identical to the
previous build: it drives `TPdfDocumentVcl` directly and never enters the
`TGDIPages` measurement path. All six demos build; `chinese_demo` and
`rtl_demo` run unchanged. Test suite 121/121 assertions (was 115, +6 from the
new guard test).

**Open for the cross-platform gate.** Run `markdown_demo` on Windows and macOS
and diff the decompressed content streams against the Linux one; all `Td`
positions should now agree. PDFs are gitignored, so the Linux reference has to
be regenerated from this commit rather than pulled from the repository. The
layout change itself is already accepted, so Step 5 is not blocked on it.

**Unrelated defect noticed while working here, fixed separately.**
`TGDIPages.AddVerticalSpace(mm)` computed `MMToPixels(mm * 100, 96)`, converting
an already-correct 1/100 mm value into pixels — `AddVerticalSpace(5)` advanced
by 18 units instead of 500. It is platform-neutral, so it was never part of
B-5. Nothing in the repository called it, so no layout changed; it is now
`mm * 100`, with an assertion in `TestMoveToNextLine`.

---

## Step 5 — B-4: Wrong Text Bounding Boxes in Graphics (Linux/macOS) — **DONE (2026-09-17)**

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

### Result (Step 5)

Implemented on 2026-09-17, built and run on Linux, and **accepted on Linux on
2026-09-17**. Windows and macOS verification is still outstanding, but as in
Step 4 the metrics now come from font data alone, with no widgetset value in
the path, so the three streams are expected to agree by construction.

**Reproduced first, on a fresh Linux build.** Page 2 of `output_crossplat.pdf`,
before the change — every box width is a multiple of 0.75pt (1 px @ 96 DPI),
i.e. an integer LCL pixel measurement, and every one of them is too narrow:

| Size | Text | Box width | AFM width | too narrow by |
|---|---|---|---|---|
| 10pt | 1 | 4.50 | 5.56 | 19.1% |
| 16pt | 4 | 6.75 | 8.90 | 24.1% |
| 22pt | 7 | 9.00 | 12.23 | 26.4% |
| 26pt | 9 | 10.50 | 14.46 | 27.4% |
| 28pt | 10 | 24.00 | 31.14 | 22.9% |

`pdffonts` confirms the demo draws with the non-embedded base-14 `/Helvetica`,
so the viewer places the glyphs with the AFM widths while `TCanvas.TextWidth`
measured with the widgetset's own resolution of the name — cause (b), as the
analysis above concluded.

What was built, against the plan above:

| Plan | Implementation |
|---|---|
| 1. Measure through the same backend that renders | `TPdfVclCanvas.TextWidthFrac` delegates to `TPdfFontMeasurer`, selected with `Font.Name`, the bold/italic flags and `TPdfDocumentVcl.StandardFontsReplace` — the same rule `TGDIPages.SetupPdfMeasureFont` uses, so both layers resolve the same face. Points are converted to canvas pixels with the canvas' own scale |
| 2. LCL path as fallback | Kept: when `TPdfFontMeasurer.SetFont` resolves nothing (no platform backend registered), the frac methods return `inherited TextWidth`/`TextHeight` |
| 3. `TextHeight` from ascender/descender | `TextHeightFrac` is `Font.Size + Descent` of the face. Not `Ascent + Descent`: `TextOutFrac` puts the baseline `Font.Size` below the requested top, so that — not the ascender — is the distance the caller's box has to span above the baseline. Using the ascender would cut descenders off |
| 4. Thin adapter over B-5's abstraction | No new measurement code: `TPdfFaceMetrics` already exposes `Ascent`/`Descent`, so `mormot.ui.pdf.pas` was not touched at all |
| — (new) | `TextWidth`, `TextHeight` and `TextExtent` are now overridden and round the exact value, so existing integer callers improve without changing their code; `RectangleFrac(X1, Y1, X2, Y2: single)` was added, because an integer `Rectangle` would snap the measured edge straight back to the 1 px grid |

Page 2 of the regenerated `output_crossplat.pdf` — every box is now exactly the
AFM advance width, at every size:

| Size | Text | Box width | AFM width |
|---|---|---|---|
| 10pt | 1 | 5.56 | 5.56 |
| 16pt | 4 | 8.90 | 8.90 |
| 22pt | 7 | 12.23 | 12.23 |
| 26pt | 9 | 14.46 | 14.46 |
| 28pt | 10 | 31.14 | 31.14 |

The heights follow the same rule: for the 10pt digit the box runs from 7.50pt
above the baseline (the `Font.Size` offset `TextOutFrac` uses) to 2.12pt below
it (Helvetica's descender), enclosing a glyph whose cap height is 7.17pt.

**Regression evidence.** `markdown_demo.pdf` is **byte-identical** to the build
from the previous commit (content streams diffed after decompression):
`TGDIPages` measures through `TPdfFontMeasurer` since Step 4 and never asked
the canvas. All six demos build; `chinese_demo` and `rtl_demo` run unchanged.
Test suite 128/128 assertions (was 122, +6 from the new guard test
`TestVclCanvasTextMetrics` in `tests/test_pdf_smoke.pas`, which pins the width
*ratio* of `'Hello'` to `'l'` to the Adobe AFM ratio — a ratio cancels the
pixels-per-point factor, so the assertion holds at any screen DPI).

**One caveat for callers.** `RenderPageToCanvas` measures its header and footer
text with `ACanvas.TextHeight`; on the PDF bridge that value now comes from the
font metrics instead of the LCL, so a report **with** `HeaderText`/`FooterText`
set shifts those two lines by a fraction of a line. No demo sets them, hence
the byte-identical output above.

---

## Step 5b — B-6: `/Alt` Written as a Bare Token — **DONE (2026-09-17)**

**Effort:** < 0.5 day | **Files:** `src/core/mormot.ui.pdf.pas` | **Demos:** `pdf_demo`

### Symptom

Page 2 of `pdf_demo.pdf` fails to open in Acrobat Reader (Windows) and makes
PAC 26.1.0.0 abort before any check runs:

```
Stacktrace 1:
unexpected token (29)
```

Found while reviewing the Step 5 content stream, reported independently from a
Windows run. Unrelated to B-4 — the same page was already broken before.

### Cause

`TPdfCanvas.BeginStructContent` wrote the alternative text into the
marked-content dictionary **unquoted**:

```
/Figure <</MCID 0 /Alt Vector graphics: rectangles, lines, text bounds>> BDC
```

`/Alt` holds a PDF string (ISO 32000-1 14.9.3), so the value has to be a
literal in parenthesis. A parser reads `Vector` as a keyword instead and stops —
that is PAC's "unexpected token". `AddEscapeText` escapes the characters but
does not write the delimiters; its other caller, `ShowText`, adds them itself.

Both `ContinueStructContent` and `ResumeStructContent` write `/MCID` only, so
this was the only inline dictionary string in the unit.

### Result (Step 5b)

```
/Figure <</MCID 0 /Alt (Vector graphics: rectangles, lines, text bounds)>> BDC
```

- The value is escaped and parenthesized, following `TPdfTextUtf8`: a WinAnsi
  literal, or `<FEFF…>` UTF-16BE for text outside WinAnsi — so a non-Latin
  `/Alt` is no longer written as raw UTF-8 bytes either
- `AddEscape`, not `AddEscapeContent`: a content stream is encrypted as a whole,
  and its strings must not be encrypted a second time
- **Second defect, found while fixing this one:** the `/Alt` never reached the
  structure tree. The `Figure` `StructElem` was serialized without it, which no
  screen reader can use and which PDF/UA 7.3 rejects. `TPdfStructElement.AltText`
  now carries the text and `SerializeStructTree` writes it:
  `<</Type/StructElem/S/Figure/…/Alt(Vector graphics: …)>>`
- Guard test `TestTaggedAltTextIsPdfString` in `tests/test_pdf_smoke.pas` pins
  the escaping of `(`, `)` and `\`; test suite 130/130
- `pdftotext`/`pdfinfo` parse the regenerated file; `markdown_demo.pdf` is
  unchanged (it has no figure, hence no `/Alt`)

**Accepted on Linux on 2026-09-17.** Still open for this file: PAC and Acrobat
have to be re-run on Windows — both for the parse error, which was reported
from there, and for the PDF/UA checks PAC could never reach before.

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
| ~~2~~ | ~~B-2~~ | **Done** — one tag per paragraph; multi-MCID leaves and `BlockId` now exist for B-3 |
| ~~3~~ | ~~B-3~~ | **Done** — one tag per sentence, styled runs as `Span` kids |
| ~~4~~ | ~~B-5~~ | **Done** — layout now measured with the PDF font engine; `LineHeightFactor` multiplies the font size |
| ~~5~~ | ~~B-4~~ | **Done** — `TextWidthFrac`/`TextHeightFrac` measure with the PDF font engine; a thin adapter over `TPdfFontMeasurer`, as planned |
| ~~5b~~ | ~~B-6~~ | **Done** — unscheduled: `/Alt` is a PDF string; written bare it broke the page for every parser, and it never reached the `StructElem` |
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
| B-2 | One tag per paragraph, not per line — see [Result (Step 2)](#result-step-2) | mormot.ui.pdf.pas, mormot.ui.pdfcanvas.pas, mormot.ui.report.pas |
| B-5 | Layout measured with the PDF font engine, not the LCL — see [Result (Step 4)](#result-step-4) | mormot.ui.pdf.pas, mormot.ui.pdfcanvas.pas, mormot.ui.report.pas |
| B-4 | Text bounding boxes measured with the PDF font engine, in `single` — see [Result (Step 5)](#result-step-5) | mormot.ui.pdfcanvas.pas, pdf_demo, tests |
| B-6 | `/Alt` written as a PDF string, and onto the `StructElem` — see [Result (Step 5b)](#result-step-5b) | mormot.ui.pdf.pas, tests |

Note on R-5/R-6: table and figure tags were *emitted* but landed flat in the
structure tree; B-1 completed them.
