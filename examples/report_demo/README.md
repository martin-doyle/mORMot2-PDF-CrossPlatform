# report_demo — Report engine with GUI preview

Demo 2 of the [learning path](../../docs/DEMOS.md#demo-2--report_demo).

**Layer 3.** `uses mormot.pdf.report` — nothing else of this library; the form
adds `mormot.pdf.report.preview` for the preview window and printing.

A Lazarus GUI around `TGDIPages`: WYSIWYG preview, printing and tagged PDF
export. The report is built in `uReport.pas`, without a form; `uMainForm.pas`
only passes the options its controls show.

**What is special here**

- `TGDIPages` records draw commands rather than painting; the same report is
  rendered twice, to the preview and to the PDF
- `TTableLayout` with `DrawTableHeader` / `DrawTableRow` / `DrawTableFooter`
  yields a real `Table > THead|TBody|TFoot > TR > TH|TD` tree, the totals line
  being the `TFoot` row
- `SetHeader` / `SetFooter` repeat on the continuation pages that table
  pagination creates and are tagged as artifacts, so they are not read twice
- `ExportPdfTagged := True` before the first drawing command — it decides the
  fonts the layout is measured with

**Build and run**

```bash
lazbuild report_demo.lpi -B
bin/<target>/report_demo                    # GUI
bin/<target>/report_demo --export           # batch -> report_demo_<os>_<cpu>_<compiler>.pdf, next to the executable
bin/<target>/report_demo --export out.pdf   # batch to a file of your choice
```

On Linux the batch mode still needs a display, because the LCL measures the
text — on a headless machine run it under `xvfb-run`. macOS needs none.

Delphi 7 (Win32), from the repository root, with `MORMOT2` set to the mORMot2
checkout — the batch export only; the window follows with roadmap R-20:

```bat
tests\build_delphi7.bat examples\report_demo\report_demo.lpr
bin\d7\report_demo\report_demo.exe --export   &rem -> report_demo_windows_x86_delphi-7.pdf, next to it
```
