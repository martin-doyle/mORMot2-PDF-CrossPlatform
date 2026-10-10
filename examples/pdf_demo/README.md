# pdf_demo — Direct TCanvas API

Demo 1 of the [learning path](../../docs/DEMOS.md#demo-1--pdf_demo_crossplat).

**Layer 2.** `uses mormot.ui.pdfcanvas, mormot.pdf` - the structure roles
(`psrH1`, `psrP`, …) and `GetPdfFonts` come with `mormot.pdf`.

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
- PAC 2024 passes and keeps one hint, "possibly inappropriate use of
  figure". It comes with every Figure, path or image, and is accepted
  (roadmap W-1)

**Build and run**

```bash
lazbuild pdf_demo_crossplat.lpi -B      # Windows: "C:\lazarus\lazbuild.exe" …
bin/<target>/pdf_demo_crossplat         # -> pdf_demo_<os>_<cpu>_<compiler>.pdf, next to the executable
```

Delphi 7 (Win32), from the repository root, with `MORMOT2` set to the mORMot2
checkout:

```bat
tests\build_delphi7.bat examples\pdf_demo\pdf_demo_crossplat.lpr
bin\d7\pdf_demo_crossplat\pdf_demo_crossplat.exe   &rem -> pdf_demo_windows_x86_delphi-7.pdf, next to it
```
