# Accessibility References — What the Engine Covers

Which published reference examples for accessible PDF this project already
meets, where it only shows them in a demo, and what is missing. The follow-up
work is ROADMAP R-30.

**State:** 2026-10-10, measured on `main` (b2f58fa) with FPC on Windows:
the eight demos run through `pdfcheck run`, their structure roles read with
`pdfcheck struct`, their normalized files searched for the keys named below.
The branch `feature/invoice-demo` (R-29) is not merged yet; what it solves
is marked as such and is not a gap. The Reference Suite: 2026-10-12, see its
section.

## Sources

| Source | What it is | Licence | Use here |
|---|---|---|---|
| [Techniques for Accessible PDF](https://github.com/pdf-association/techniques-for-accessible-pdf) (PDF Association) | Atomic example files, one technique each, a PASS file (PDF/UA-1) and FAIL files; so far fundamentals, headings and lists (42 PASS, 40 FAIL) | CC BY 4.0 | Rebuild the PASS cases as tests, the source named in the test |
| [PDF/UA-1 Reference Suite 1.1](https://pdfa.org/resource/pdfua-reference-suite/) (PDF Association, `PDFUA-Reference-Files_1-1_2024_02.zip`) | Complete documents: magazine, invoice, academic abstract, presentation, book chapters, brochure, scan, form. The ZIP holds 9 files, numbered 01–10 without 07 | CC BY 4.0 | Model for new demos, see below. Downloaded by hand (the page answers HTTP 403 to scripts), kept outside the repository |
| [BITV-PDF-Test](https://pdftest.bit-inklusiv.de/) (BIT inklusiv, v1.4, June 2025) | 44 test steps for PDF under BITV 2.0 / BFSG, EN 301 549 chapter 10 | not stated | Only where it adds to the above: language of parts (3.1.2), and the German view of `invoice_demo` |
| [veraPDF corpus](https://github.com/veraPDF/veraPDF-corpus) | Test files per PDF/A and PDF/UA rule | CC BY 4.0 | On demand, to reproduce one rule veraPDF reports |

Tables and links have no Techniques yet; the PDF Association publishes them
in batches.

## Coverage of the Techniques (PASS cases)

**Test** — a test of `test_runner` checks it. **Demo** — a demo shows it,
no test checks it. **R-29** — solved on `feature/invoice-demo`, waiting for
the merge. **Gap** — the engine cannot do it yet. **Check** — not yet
known whether the engine does it. **n/a** — not the engine's concern
(authoring, scans) or a pattern the engine never writes.

### Fundamentals

| Technique | Status | Where / what is missing |
|---|---|---|
| G1_01 Custom tag role-mapped | n/a | the engine writes standard tags only; see H_06–H_09 for where a role map would be needed |
| G2_01 Text in one container | Demo | every demo; a wrapped paragraph is one `P` (B-2) |
| G2_02 / G2_03 One container per word / character | n/a | a pattern the engine never writes |
| G2_04 Special character with Unicode mapping | Test | `TestTaggedUnicode`, `TestPdfA3UToUnicodeForEveryFont` |
| G2_05 Graphics representing text | Gap | no `/ActualText` on a structure element (also needed for shaped Arabic: ROADMAP "Shaped Text: Real `/ToUnicode`") |
| G2_06 `/ActualText` for OCR errors | n/a | scans are out of scope |
| G3_01 Real content tagged | Demo | every tagged demo |
| G3_02 Decoration as artifact | Test | `TestTaggedDecorationIsArtifact`, `TestTaggedArtifactMisuseRaises` |
| G4_01 Content order | Demo | structure order is call order; no test |
| G4_02 Order of marked content within a tag | Demo | `markdown_demo`, inline runs: `P` with `MCR` and `Span` kids (B-3); no test |
| G4_03 Content in columns | Check | `Columns2` exists; whether each column is one element in reading order is unmeasured. `invoice_demo` sets running text in columns (R-29) |
| G4_04 Sidebar in content order | R-29 | frames (`BeginFrame`/`EndFrame`): the code order is the structure order |
| G4_05 Tab order with annotations | R-29 | `/Tabs /S` with tagged links |
| G5_01 H1 tagged | Demo | every demo; no test of the role itself |
| G5_02 Similar content tagged alike | n/a | the author's part |
| G5_03 Visually separated content as one element | Demo | a block across a page break stays one element (`ResumeStructContent`); no test |
| G5_04 Multiline heading | Check | whether `DrawHeading` wraps a long heading into one `Hx` |

### Headings

| Technique | Status | Where / what is missing |
|---|---|---|
| H_01 First heading is H1 | Demo | the author's order; every demo starts with `H1` |
| H_02 Multiline heading | Check | as G5_04 |
| H_03 Heading levels | Demo | `markdown_demo`: H1–H6, with bookmarks |
| H_04 Image as heading | Check | layer 1: a `Figure` nested in `Hx` by `BeginStructGroup`; `TGDIPages` has no way to it |
| H_05 No skipped levels | n/a | the author's part; the engine does not enforce it |
| H_06 Title and subtitle | Gap | PDF/UA-1 has no `Title` tag: a custom role mapped to `P` needs a `/RoleMap`, which the engine does not write |
| H_07 Title in the page content | Gap | as H_06 |
| H_08 / H_09 Heading level 7 | Gap | `/RoleMap` as H_06; `TGDIPages` knows levels 1–6 only |

### Lists

The engine writes `L` → `LI` → `LBody`, the bullet inside `LBody`, no `Lbl`
and no `/ListNumbering` (`markdown_demo`). R-29 item 6 names the missing
`Lbl`; the Techniques add `/ListNumbering` and the cases below.

| Technique | Status | Where / what is missing |
|---|---|---|
| L_01 Unordered list | Gap | `Lbl` (R-29 item 6) and `/ListNumbering` |
| L_02 / L_03 Ordered list, `UpperRoman` / `Decimal` | Gap | `DrawListItem` takes a prefix, but writes no `/ListNumbering` |
| L_04 Decorative images as bullets | Gap | needs `Lbl` |
| L_05 / L_12 Nested list | Check | `DrawListItem` indents visually; whether a nested `L` is written |
| L_06 Semantic images as bullets | Gap | needs `Lbl` with a `Figure` |
| L_07 / L_08 Unordered lists, `/ListNumbering` unset or `None` | Gap | `/ListNumbering` |
| L_09 Caption of a list | Gap | no `Caption` role |
| L_10 Inline list | Gap | an `L` inside a `P`; low priority |
| L_11 / L_15 List (item) across two pages | Check | `LBody` is a block and resumes; whether the `L` stays one element |
| L_13 List item with substructure | Gap | an `LBody` holding `P` kids |
| L_14 Description list | Gap | needs `Lbl` for the term |

## The Reference Suite

Measured 2026-10-12: the streams of each file inflated, then the structure
roles and keys counted. Not with `pdf_inspect`: it checks the structure
before it normalizes, against what this engine writes, and rejects all nine
files (linearized files, predictors in XRef streams, an indirect `/Length`,
`DCTDecode` and `ASCII85Decode`). The demos were counted the same way, as FPC
builds of `b2f58fa`.

| File | Roles beyond what the engine writes | Keys the engine does not write |
|---|---|---|
| 01 Magazine (Danish) | `Art`, `BlockQuote`, `Caption` (38), `TOC`/`TOCI`, `Lbl`, `Link`, `Title` | `/ActualText`, element `/Lang`, `/RoleMap` |
| 02 Invoice | `Caption`, `Part`, `Sect` | `/Summary` on the `Table`. Otherwise within reach: `THead`/`TBody`, `TH` with `/Scope /Column`, two `Figure`s with `/Alt` |
| 03 Academic abstract | `Title`, `HyphenSpan`, `Lbl`, `Link` | `/RoleMap` (`Title`→`P`, `HyphenSpan`→`Span`), `/ListNumbering /Disc` (the only file with it), `/ActualText` |
| 04 Presentation | `Note`, `Lbl`, `Link`, custom roles | element `/Lang`, `/ActualText`, `/RoleMap` |
| 05 Book chapter (German) | `TOC`/`TOCI`, `Caption`, `Lbl`, `Link` (67) | **element `/Lang`: 109 × `en-GB` inside `de-DE`**, row headers (`/Scope /Row` and `/Both`), `/RowSpan`/`/ColSpan`, `/ActualText` |
| 06 Brochure | `Caption`, `Lbl`, `Link` | `/ActualText`, element `/Lang`, `/RoleMap` |
| 08 Book chapter | `Caption` (55), `TOC`/`TOCI`, `BlockQuote`, nested `L` (52), `Lbl` | row headers (`/Scope /Row`, 14) |
| 09 Scan | `Formula`, `Caption` | out of scope; `/RoleMap` for `H7`–`H9` → `P` |
| 10 Form | `Form` (9 widgets) | out of scope |

What the demos write, for comparison: `Document`, `H1`–`H6`, `P`, `Span`,
`Figure`, `L`/`LI`/`LBody`, the table roles with `/Scope` on every `TH`, and
the catalog `/Lang`. `markdown_demo` calls `DrawQuote` and `DrawCaption`;
both come out as `P`, not as `BlockQuote` and `Caption`.

What the suite adds to the gaps from the Techniques:

- **`Caption`** in 7 of 9 files, on figures and tables: a gap, and an easy
  one, as `DrawCaption` exists
- **`BlockQuote`**: `DrawQuote` exists, writes `P`
- **Element `/Lang`**: file 05 is the model for BITV-PDF-Test 3.1.2
- **Row headers** in the table body (05, 08): the gap below
- **`/Summary`** on a table (02): optional in PDF/UA-1, cheap
- **`TOC`/`TOCI`** (01, 05, 08): only if `TGDIPages` gets a table of contents
- **`Lbl`** in every file with lists; `/ListNumbering` in one only

**Use.** Licence CC BY 4.0: structure and texts may be taken over when the
source is named. The files themselves stay outside the repository. File 02 is
the reference for `invoice_demo`/`zugferd_demo`, file 05 for language of
parts and complex tables.

## Beyond the Techniques

| Requirement | Source | Status |
|---|---|---|
| Document language | BITV-PDF-Test 3.1.1 | Test: catalog `/Lang` (`test_pdf_smoke`), set by `DefaultLanguage` / `ExportPdfLanguage` |
| **Language of parts** | BITV-PDF-Test 3.1.2, Reference Suite 05 | **Gap**: no `/Lang` on a structure element or marked content. Not reported by veraPDF or PAC, therefore listed here |
| Captions | Reference Suite (7 of 9) | Gap: `DrawCaption` writes `P` |
| Block quotes | Reference Suite 01, 08 | Gap: `DrawQuote` writes `P` |
| Table summary | Reference Suite 02 | Gap: no `/Summary` |
| Multi-page tables | Reference Suite | Test: `TestTableGroupsAcrossPages`; demo `mormot_demo` |
| Complex tables (row headers in the body, spans) | Reference Suite 05, 08 | Gap: `psrTHRow` only in footer rows, no `/RowSpan`/`/ColSpan`; R-29 "Open decision" |
| Links to structure elements | Reference Suite | Check: R-29 tags URI links (`invoice_demo`: one `OBJR`); internal links (`CreateLink`) in tagged output are unmeasured |
| Table of contents | Reference Suite 01, 05, 08 | n/a until `TGDIPages` has one |
| Forms, scans | Reference Suite 09, 10 | out of scope |
