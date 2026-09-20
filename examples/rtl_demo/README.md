# rtl_demo — Arabic RTL and shaping

Demo 6 of the [learning path](../../docs/DEMOS.md#demo-6--rtl_demo).

Draws Arabic with `TPdfDocumentVcl` twice in one PDF, unshaped and shaped, so
the two paths can be compared side by side.

**What is special here**

- section 1 draws without a shaper: isolated letters resolved through the CMAP,
  which verifies the per-glyph advance widths
- section 2 shapes — Uniscribe on Windows (`UseUniscribe := True`), HarfBuzz on
  Linux/macOS (`mormot.pdf.harfbuzz` registers `PdfTextShaper` at startup).
  Both need `RightToLeftText := True`
- the face is embedded as a subset: both subsetters are fed the shaped glyph
  IDs, so the GSUB output survives

**Font requirement**

| Platform | Face | Install |
|---|---|---|
| Windows | Tahoma | pre-installed |
| macOS | Geeza Pro | pre-installed |
| Linux | Noto Naskh Arabic | `sudo apt install fonts-noto-core` |

Without an Arabic face the fallback shows boxes. On Linux/macOS HarfBuzz is
needed for section 2: `sudo apt install libharfbuzz0b` / `brew install harfbuzz`.

**Build and run**

```bash
lazbuild rtl_demo.lpi -B
bin/<target>/rtl_demo          # -> output_rtl.pdf
```
