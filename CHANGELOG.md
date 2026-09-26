# Changelog

## Unreleased

PDF/A-3 verified for the first time, combined with PDF/UA-1 in one file, and a
demo that uses it for a hybrid e-invoice (roadmap R-17). The core builds and
tests green on **Delphi 7** (roadmap R-19), which found two defects in tagged
output with CJK or Arabic text that every compiler had.

### Delphi 7

Layer 1 — `TPdfDocument`/`TPdfCanvas`, the GDI backend and Uniscribe — builds
with Delphi 7 for Win32 (`tests\build_delphi7.bat`). `test_runner` passes there
with 123 assertions: the layer 1 suites, all tests shared with FPC. A tagged PDF
with Latin, CJK and shaped Arabic comes out the same from Delphi 7/Win32 and
FPC/Win64 — size, text, roles, `/ToUnicode` — and passes **PAC 2024** and
**veraPDF** `ua1` (106/106). The
TCanvas bridge and `TGDIPages` stay FPC-only for now: they override `TCanvas`
methods that Delphi 7's VCL does not declare virtual (roadmap R-20).

The one byte-level difference: the 32-bit `fontsub.dll` writes a non-zero
`language` into the format 12 `cmap` subtable of a subset, the 64-bit one zero.
It is Windows' own output, stable from run to run, and ignored by viewers.

### Verification

`zugferd_demo`, built on Windows, Linux and macOS, passes **veraPDF 1.30.2**
`3u` (148/148) and `ua1` (106/106), **Mustang-CLI 2.26.0** (valid as
ZUGFeRD / Factur-X profile EN 16931, PDF/A-3U) and **PAC 2024**. The three files
agree in structure, embedded XML and metadata. PAC keeps one quality hint, e-mail
addresses without a link element, accepted as roadmap W-2. As `pdfa3A` the same
file passes veraPDF `3a` 155/155. PDF/A-1 and PDF/A-2 remain implemented but
unverified.

Test suite green on all three platforms: 277 assertions on macOS (239 at
v0.9.0), 260 on Linux, 221 on Windows. As before, the differences are tests
standing down where a platform lacks what they need, not failures.

### Added

- **`pdfa3U`** in `TPdfALevel`, appended last so the older members keep their
  ordinal values.
- **`PdfMetadataFacturX(ConformanceLevel, DocumentFileName, Version,
  DocumentType)`** writes the `fx:` XMP properties of a ZUGFeRD / Factur-X
  invoice with their PDF/A extension schema. `PdfMetadataZugferd` stays.
- **`CreateFileAttachment(FileName, …, Relationship)`**: the file overload
  takes an `/AFRelationship` too (default `afrAlternative`, as before).
- **`zugferd_demo`** (demo 7): a tagged PDF/A-3U invoice with `factur-x.xml`
  embedded. The XML is third-party test data (KoSIT, Apache-2.0), with its
  source, one marked change and checksums in `THIRD_PARTY.md`.
- **`tests/test_pdf_pdfa.pas`**: associated files, XMP identification and
  extension schemas, `PdfMetadataFacturX`, `/ToUnicode` for every font under U,
  encryption rejected; plus `TestPdfA3Subsets`.
- **`GetPdfFonts` and `PDF_FONT_TTF_SANS/SERIF/MONO`** in `mormot.pdf.types`:
  the platform font names, usable without the report engine.
  `GetReportFonts` and `REPORT_FONT_*` in `mormot.ui.report` stay, as aliases.
- **`TestTaggedUnicode`**: tagged Latin, CJK and shaped Arabic through
  `TPdfCanvas`; the file stays in the test runner's `data` folder for PAC and
  veraPDF.
- **`tests/build_delphi7.bat`** and `tests/delphi7_core.dpr`.

### Fixed

- **Tagged PDF/A crashed on `Free`.** At every level, PDF/A with `Tagged := True`
  freed its `StructTreeRoot` twice: `NewDoc` made it a direct object, which the
  structure tree then added to a second dictionary. The same early object made
  the Tagged setup skip `/Lang` and `DisplayDocTitle`. Untagged PDF/A no longer
  claims `/MarkInfo /Marked true` over an empty tree.
- **`pdfuaid` without an extension schema.** PDF/A does not predefine it, so
  every tagged PDF/A failed ISO 19005 6.6.2.3.1. The engine now describes it,
  inside the caller's list of extension schemas when there is one.
- **`/Params /Size 0` for attachments read from a file.** The size came from
  the empty buffer while the content arrived through a stream.
- **PAC 2024 stopped on tagged output with CJK or Arabic text.** The WinAnsi
  peer of a face that draws only such text shows no character, and was written
  without `/FirstChar`, `/LastChar` and `/Widths`, which a simple TrueType font
  requires. It now carries the space. Removing the peer altogether is on the
  roadmap.
- **`/CIDToGIDMap` was written for PDF/A only.** PDF/UA-1 (7.21.3.2) wants it
  for every `CIDFontType2` as well, and PAC failed the font without it.
- **A `.ttc` face could be embedded as the whole collection** on Linux and
  macOS: the FreeType backend left one flag of its font context to the heap,
  and a stale value skipped the extraction of the face. The raw collection went
  to `/FontFile2` unsubset — 23 MB for Hiragino Sans GB, failing veraPDF `ua1`
  7.21.4.1 — at random, by heap layout, since the first version.
- **`GetCharABCWidthsI` was imported without `stdcall`**: a wrong calling
  convention on any Win32 build. Win64 has only one, so it never showed.

### Changed

- **The PDF test suites draw through `TPdfDocument`/`TPdfCanvas`** instead of
  the TCanvas bridge: they test the output, so they now run on Delphi too. The
  two tests of the bridge itself need `PDF_HASVCLCANVAS`
  (`tests/test_defines.inc`), defined for FPC.
- Test suite: 227 assertions on Windows with FPC (221 before), 123 with
  Delphi 7, 288 on macOS, 268 on Linux (260 before).
- **The demos write `<demo>_<os>.pdf` next to their executable**, whatever the
  current folder — `<os>` is mORMot2's `OS_NAME[OS_KIND]` in lower case:
  `windows`, `osx`, on Linux the distribution. Formerly `output_crossplat.pdf`,
  `output_chinese.pdf`, `output_rtl.pdf`, `markdown_demo.pdf` and
  `zugferd_invoice.pdf` in the current folder. The GUI demos use the name for
  `--export` without a file name.

### Known limitations

- **Links in tagged output** (R-18): `CreateHyperLink` in a tagged document
  fails PDF/UA (veraPDF `ua1`, four rules of 7.18), because the engine has no
  `Link` structure element for annotations. `TGDIPages.DrawLink` stays
  conformant by drawing styled text only — its URL is dropped, nothing is
  clickable.
- **Invoices to German authorities** take pure XML (XRechnung) and are out of
  scope; the engine never generates or validates invoice XML.
- **PDF/A-1 accepts attachments** although it forbids them; the engine does not
  check.
- **Delphi: layer 1 only** (R-20), and Delphi 7 is the only version built.

## v0.9.0 — 2026-09-23

First tagged release. Cross-platform PDF and report generation for Windows,
Linux and macOS, with tagged (PDF/UA-style) output verified by two independent
checkers on all three platforms.

### Verification

The four tagged demos — `pdf_demo`, `markdown_demo`, `report_demo`,
`mormot_demo` — pass **veraPDF 1.30.2** (`ua1` profile, 106/106 rules) and
**PAC 2024** on Windows, Linux and macOS. `chinese_demo` and `rtl_demo` are
untagged by design, but satisfy the glyph-width rule everywhere as well.

`mormot_demo` renders a 206-row table from an SQLite database across 5 pages and
produces **one** `Table` element: 207 `TR` (1 header + 206 data rows), 1030 `TD`
(206 × 5 columns), 5 `TH`. The header repeated on continuation pages is marked
as an artifact and opens no second `THead`.

Test suite green on all three platforms: 239 assertions on macOS, 222 on Linux.
The difference is skips, not failures — tests stand down when the machine lacks
what they need (no `.ttc` collections on Linux, no Arabic face there that
applies a GPOS offset) and say so rather than reporting a green they did not
earn. Linux runs two assertions macOS cannot, having Droid Sans Fallback
installed, so the platforms complement each other rather than one covering a
subset of the other.

**The fallback without `libharfbuzz-subset` is measured, not simulated.**
`tests/no_hbsubset.sh` masks the library inside a mount namespace and runs the
suite again: it stays green at 197 assertions, with the two subset suites
standing down (19 → 7, 22 → 9) instead of failing. The nine that remain include
the tests for the whole-face path itself.

### Fixed in this release

- **U-1 — glyph widths disagreed with the embedded font program on POSIX**
  (ISO 14289-1 7.21.5). Two independent causes in the FreeType backend's
  `GetCharABCWidths`. First, an ANSI/Unicode mix-up: the engine passes WinAnsi
  *byte* values, matching the Windows `GetCharABCWidthsA` it mirrors, but the
  byte was handed to `FT_Load_Char`, which expects a Unicode code point. Bytes
  128–159 are printable punctuation in WinAnsi and unassigned C1 controls in
  Unicode, so the bullet (`#$95`) and em dash (`#$97`) missed the CMAP and were
  written with the `.notdef` advance. Second, the three ABC members were scaled
  separately although every consumer sums them, accumulating three roundings
  where the rule allows one unit. Failure counts on the tagged demos went
  5 → 0, 64 → 0, 63 → 0 and 99 → 0 on Linux, and 11 → 0 and 83 → 0 on macOS.

- **U-2 — a shaped Arabic glyph carried the shaper's advance in `/W`.**
  HarfBuzz returns the *positioned* advance, so a cursively attached glyph comes
  back shortened by exactly the amount it is offset. `/W` must state the
  unpositioned advance from `hmtx`. Both errors cancelled out on screen, which
  is why the defect was invisible in viewers and in PAC. The width now comes
  from the font's own `hmtx` table, and the emitted `TJ` array compensates any
  difference so the rendered text is unchanged — verified by recomputing the pen
  movement, not only by re-running the checker.

Both fixes are in POSIX code; Windows was already correct and served as the
reference for the expected values.

One test was fixed too, and it is worth naming because it was wrong in an
instructive way. `TestWinAnsiHighRangeWidths` asserted that the bullet's advance
differs from the `.notdef` advance, treating equality as proof of a failed
lookup. Nothing stops a font from giving `.notdef` the same advance as a real
glyph, and the face picked on Linux does exactly that — so a correct lookup
failed the check. It now compares two *unmapped* WinAnsi codes with each other
instead, which assumes nothing about the face's metrics.

### Known limitations

Documented in `docs/ROADMAP.md`, and none of them blocks normal use:

- The **U-2 fix is exercised on macOS only.** No Linux Arabic face reaches the
  code path it repairs — Noto Naskh Arabic resolves shaped glyphs through the
  CMAP — so the regression test skips itself there rather than reporting a
  false green.
- The **fallback without `libharfbuzz-subset`** is verified for a *missing*
  library (`tests/no_hbsubset.sh`, see Verification above), but not for a **HarfBuzz older
  than 2.9**, which loads and then turns out to lack `hb_subset_or_fail`. That
  needs an old distribution to test. Without a usable subsetter the whole face
  is embedded, which is correct but produces much larger files.
- **Symbolic fonts are not subset on POSIX** (R-15b), **table rows do not split
  across pages** (R-10), and **only face index 0 of a `.ttc` is reachable**
  (R-11).
- **EMF/metafile input and GDI+ gradients remain Windows-only** by nature.
