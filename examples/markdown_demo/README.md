# markdown_demo — Semantic document layout

Demo 3 of the [learning path](../../docs/DEMOS.md#demo-3--markdown_demo).

**Layer 3.** `uses mormot.pdf.report` — nothing else of this library.

Renders a markdown-style document with `TGDIPages` as a console app: headings
H1-H6, paragraphs, quotes, list items, captions, inline runs (`DrawStrong`,
`DrawEm`, `DrawCode`, `DrawLink`) and a table.

**What is special here**

- the same content is rendered twice from two `TPageConfig` records, showing
  that margins, font family, size and `LineHeightFactor` can change per section
  inside one document
- `DefineFormat` overrides the built-in formats for H1-H6, P, Code, Quote, LI
  and Caption
- `DrawHeading` writes the PDF bookmark PDF/UA expects for a heading
- the 20-row invoice table forces a page break, so the repeated header row is
  visible — and it is an artifact, not a second `THead`

**Build and run**

```bash
lazbuild markdown_demo.lpi -B
bin/<target>/markdown_demo      # -> markdown_demo_<os>_<cpu>_<compiler>.pdf, next to the executable
```

Delphi 7 (Win32), from the repository root, with `MORMOT2` set to the mORMot2
checkout:

```bat
tests\build_delphi7.bat examples\markdown_demo\markdown_demo.lpr
bin\d7\markdown_demo\markdown_demo.exe   &rem -> markdown_demo_windows_x86_delphi-7.pdf, next to it
```
