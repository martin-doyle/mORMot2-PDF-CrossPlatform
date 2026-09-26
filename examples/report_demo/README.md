# report_demo — Report engine with GUI preview

Demo 2 of the [learning path](../../docs/DEMOS.md#demo-2--report_demo).

A Lazarus GUI around `TGDIPages`: WYSIWYG preview, printing and tagged PDF
export from the form in `uMainForm.pas`.

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
lazbuild mormot_report_demo.lpi -B
bin/<target>/report_demo_crossplat                    # GUI
bin/<target>/report_demo_crossplat --export           # batch -> report_demo_<os>.pdf, next to the executable
bin/<target>/report_demo_crossplat --export out.pdf   # batch to a file of your choice
```

The batch mode still needs a display, because `TGDIPages` is an LCL control —
on a headless machine run it under `xvfb-run`.
