# Sample output for PAC 2024

Built on Linux (aarch64, Liberation faces, subset via hb-subset) after R-14.
They are here so the PAC run on Windows can check **Linux-built** output —
Windows builds its own PDFs with its own faces, which is a different case.

| File | Built from | Expected in PAC |
|---|---|---|
| `pdf_demo_linux_r14.pdf` | `examples/pdf_demo` | green, plus the accepted W-1 warning (decorative figure) |
| `report_demo_linux_r14.pdf` | `examples/report_demo` | green; check the *Logical Structure* view for `Table > THead / TBody / TFoot` |

Regenerate:

```bash
lazbuild examples/pdf_demo/pdf_demo_crossplat.lpi -B && (cd examples/pdf_demo && ./bin/<target>/pdf_demo_crossplat)
lazbuild examples/report_demo/report_demo.lpi -B
examples/report_demo/bin/<target>/report_demo --export report_demo_linux_r14.pdf
```
