# chinese_demo — CJK text

Demo 5 of the [learning path](../../docs/DEMOS.md#demo-5--chinese_demo).

**Layer 2.** `uses mormot.ui.pdfcanvas, mormot.pdf` - `GetPdfFonts` comes
with `mormot.pdf`.

Draws multi-line Chinese with `TPdfDocumentVcl` and embeds the face as a
subset on every platform.

**What is special here**

- CJK has no contextual shaping, so `UseUniscribe` stays false
- subsetting is what makes the file usable: a whole CJK face costs about 24 MB
  against roughly 39 KB for the glyphs actually drawn. Both subsetters keep the
  glyph numbering, so Identity-H and `/ToUnicode` stay valid
- set `EmbeddedWholeTtf := True` if a consumer needs the complete CMAP

**macOS uses a CFF face.** `Hiragino Sans GB.ttc` is OpenType/CFF, so its
subset goes to `/FontFile3` with `/Subtype /OpenType` rather than `/FontFile2`
(roadmap R-15c). Before that was handled the file was ~10 MB; it is ~23 KB now.

```bash
grep -a -oE "/BaseFont[ ]*/[A-Za-z0-9+,#_-]+" chinese_demo_<os>_<cpu>_<compiler>.pdf | sort -u
# HFCPMT+HiraginoSansGB  <- the six-letter prefix means subset
```

**Font requirement**

| Platform | Face | Install |
|---|---|---|
| Windows | Microsoft YaHei | pre-installed on Vista+ |
| macOS | Hiragino Sans GB | pre-installed |
| Linux | Droid Sans Fallback | `sudo apt install fonts-droid-fallback` |

**Build and run**

```bash
lazbuild chinese_demo.lpi -B
bin/<target>/chinese_demo      # -> chinese_demo_<os>_<cpu>_<compiler>.pdf, next to the executable
```

Delphi 7 (Win32), from the repository root, with `MORMOT2` set to the mORMot2
checkout:

```bat
tests\build_delphi7.bat examples\chinese_demo\chinese_demo.lpr
bin\d7\chinese_demo\chinese_demo.exe   &rem -> chinese_demo_windows_x86_delphi-7.pdf, next to it
```
