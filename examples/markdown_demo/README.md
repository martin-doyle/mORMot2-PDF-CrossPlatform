# markdown_demo — Semantic document layout

Demo 3 of the [learning path](../../docs/DEMOS.md#demo-3--markdown_demo).

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
bin/<target>/markdown_demo      # -> markdown_demo_<os>.pdf, next to the executable
```
