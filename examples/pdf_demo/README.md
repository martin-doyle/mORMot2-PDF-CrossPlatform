# pdf_demo — Direct TCanvas API

Demo 1 of the [learning path](../../docs/DEMOS.md#demo-1--pdf_demo_crossplat).

Produces a 3-page tagged PDF from plain `TCanvas` calls with `TPdfDocumentVcl`
— no report engine, no GUI: fonts and text, vector graphics, and a table built
by hand from header and data rows.

**What is special here**

- the drawing code is identical on every platform and compiler
- with the low-level API the caller owns the structure tree: this demo opens
  the struct roles (`psrH1`, `psrP`, `psrFigure`, `psrTable`…) and the
  `THead`/`TBody` row groups itself, which `TGDIPages` would do for you
- `Tagged := True` before the first `AddPage`: it raises the file format to
  PDF 1.7 and selects the PDF/UA font mode, so ask for the font names after it
- PAC 2024 reports one accepted warning on this file, "possibly inappropriate
  use of figure" (roadmap W-1) — the figure is decorative by design

**Build and run**

```bash
lazbuild pdf_demo_crossplat.lpi -B      # Windows: "C:\lazarus\lazbuild.exe" …
bin/<target>/pdf_demo_crossplat         # -> pdf_demo_<os>.pdf, next to the executable
```

**Other files here**

| File | What it is |
|---|---|
| `pdf_demo_windows.dpr` | Delphi 7 golden master on `TPdfDocumentGDI`, the reference the cross-platform output is compared against — do not change it |
| `peekpdf.pas`, `peekpdf2.pas` | console tools that dump a PDF's uncompressed content streams, for comparing the two outputs: `peekpdf <file.pdf>` |
