# rtl_demo — Arabic RTL and shaping

Demo 6 of the [learning path](../../docs/DEMOS.md#demo-6--rtl_demo).

**Layer 2.** `uses mormot.ui.pdfcanvas, mormot.pdf` — the latter also for
`TPdfCanvas.RightToLeftText`, one layer below the bridge, and for
`GetPdfFonts`. The shaper — Uniscribe, or HarfBuzz on
Linux/macOS — comes with `mormot.pdf`.

Draws Arabic with `TPdfDocumentVcl` twice in one PDF, unshaped and shaped, so
the two paths can be compared side by side.

**What is special here**

- section 1 draws without a shaper: isolated letters resolved through the CMAP,
  which verifies the per-glyph advance widths
- section 2 shapes with `UseUniscribe := True`, the one shaping switch —
  Uniscribe on Windows, HarfBuzz on Linux/macOS — and sets the direction with
  `RightToLeftText := True`
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
bin/<target>/rtl_demo          # -> rtl_demo_<os>_<cpu>_<compiler>.pdf, next to the executable
```

Delphi 7 (Win32), from the repository root, with `MORMOT2` set to the mORMot2
checkout:

```bat
tests\build_delphi7.bat examples\rtl_demo\rtl_demo.lpr
bin\d7\rtl_demo\rtl_demo.exe   &rem -> rtl_demo_windows_x86_delphi-7.pdf, next to it
```
