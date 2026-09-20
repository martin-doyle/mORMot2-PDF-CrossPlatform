# chinese_demo — CJK text

Demo 5 of the [learning path](../../docs/DEMOS.md#demo-5--chinese_demo).

Draws multi-line Chinese with `TPdfDocumentVcl` and embeds the face as a
subset — on Windows and Linux; see the macOS note below.

**What is special here**

- CJK has no contextual shaping, so `UseUniscribe` stays false
- subsetting is what makes the file usable: a whole CJK face costs about 24 MB
  against roughly 39 KB for the glyphs actually drawn. Both subsetters keep the
  glyph numbering, so Identity-H and `/ToUnicode` stay valid
- set `EmbeddedWholeTtf := True` if a consumer needs the complete CMAP

**macOS produces a ~10 MB file, and that is expected.** `Hiragino Sans GB.ttc`
is CFF OpenType (`OTTO`), and a CFF subset is not valid in `/FontFile2`, so the
engine falls back to the whole face — twice, since Regular and Bold are separate
faces of the collection. The Latin header font still subsets, which is how you
can see the subsetter itself is working:

```bash
grep -a -oE "/BaseFont[ ]*/[A-Za-z0-9+,#_-]+" output_chinese.pdf | sort -u
# YKURIC+TrebuchetMS,Bold  <- subset
# HiraginoSansGB           <- whole face
```

Roadmap [R-15c](../../docs/ROADMAP.md) tracks this. Pointing `CJK_FONT` at an
installed `glyf` face (for example Noto Sans CJK) gives a small file on macOS
too.

**Font requirement**

| Platform | Face | Install |
|---|---|---|
| Windows | Microsoft YaHei | pre-installed on Vista+ |
| macOS | Hiragino Sans GB | pre-installed |
| Linux | Droid Sans Fallback | `sudo apt install fonts-droid-fallback` |

**Build and run**

```bash
lazbuild chinese_demo.lpi -B
bin/<target>/chinese_demo      # -> output_chinese.pdf
```
