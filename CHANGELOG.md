# Changelog

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

Test suite: 239 assertions across 7 suites, green on all three platforms.

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

### Known limitations

Documented in `docs/ROADMAP.md`, and none of them blocks normal use:

- The **U-2 fix is exercised on macOS only.** No Linux Arabic face reaches the
  code path it repairs — Noto Naskh Arabic resolves shaped glyphs through the
  CMAP — so the regression test skips itself there rather than reporting a
  false green.
- The **fallback without `libharfbuzz-subset`** has never run on a machine that
  actually lacks the library; it is only simulated in the test suite. Without
  the library the whole face is embedded instead of a subset, which is correct
  but produces much larger files.
- **Symbolic fonts are not subset on POSIX** (R-15b), **table rows do not split
  across pages** (R-10), and **only face index 0 of a `.ttc` is reachable**
  (R-11).
- **EMF/metafile input and GDI+ gradients remain Windows-only** by nature.
