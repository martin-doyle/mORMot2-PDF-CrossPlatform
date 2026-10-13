# mormot_demo — ORM integration

Demo 4 of the [learning path](../../docs/DEMOS.md#demo-4--mormot_demo).

**Layer 3.** `uses mormot.pdf.report` — nothing else of this library; the form
adds `mormot.pdf.report.preview` for the preview window and printing.

A Lazarus GUI report whose rows come from a live SQLite database through the
mORMot ORM.

| File | Role |
|---|---|
| `data.pas` | `TOrmEmployee`, `TOrmCustomer`, `TOrmCustomerOrder` |
| `server.pas` | `TDemoServer.GetInvoiceData` returning a DTO array, `AddSampleData` for a fresh database, `ReadInvoiceData` |
| `uReport.pas` | `BuildReport` → `DrawInvoiceTable` with `TTableLayout`, `ExportReport` |
| `uMainForm.pas` | the form: passes the options its controls show |

**What is special here**

- `TRestClientDB` + `TRestServerDB` for the local database, and a service
  method that hands out DTOs — the report never touches the ORM
- an empty result set still produces a valid table, via a placeholder row
- otherwise the same `TTableLayout` and tagged export as `markdown_demo`

**Build and run**

```bash
lazbuild mormot_demo.lpi -B
bin/<target>/mormot_demo                    # GUI
bin/<target>/mormot_demo --export           # batch -> mormot_demo_<os>_<cpu>_<compiler>.pdf, next to the executable
bin/<target>/mormot_demo --export out.pdf   # batch to a file of your choice
```

Delphi 7 (Win32), with `MORMOT2` set to the mORMot2 checkout: build from the
repository root, run from this folder — the batch export only, the window
follows with roadmap R-20:

```bat
tests\build_delphi7.bat examples\mormot_demo\mormot_demo.lpr
cd examples\mormot_demo
..\..\bin\d7\mormot_demo\mormot_demo.exe --export   &rem -> mormot_demo_windows_x86_delphi-7.pdf, next to it
```

**The database** is `data/mormot_demo.db` in this folder, found two levels
above the executable, or else below the current folder (the Delphi 7 build).
It is not versioned (`.gitignore`): on the first run `TDemoServer` creates
it and adds sample data written for this project, 10 invented customers and
200 orders of the first quarter of 2026. The data is computed, not random, so
every run prints the same report. A database that already holds customers or
orders is used as it is; one with customers but no orders shows the
placeholder row "No orders available". The `data/` folder comes with the clone
(`.gitkeep`); if it is missing, the demo creates it. A failed `--export` ends
with exit code 1 and the reason on stderr, not in a dialog.

The larger database of the invoice example works too, `Project10.db` in
[mORMot2-Examples/10-InvoiceExample/Data](https://github.com/martin-doyle/mORMot2-Examples/tree/main/10-InvoiceExample/Data)
(its orders date from 1988 to 1996, not from the quarter in the title); save
it as `data/mormot_demo.db`:

```bash
mkdir -p data
curl -L -o data/mormot_demo.db \
  https://raw.githubusercontent.com/martin-doyle/mORMot2-Examples/main/10-InvoiceExample/Data/Project10.db
```

On Linux the batch mode still needs a display, because the LCL measures the
text — on a headless machine run it under `xvfb-run`. macOS needs none.

**Status:** `--export` checked on 2026-09-28 from macOS, Debian, FPC/Win64,
Delphi 7 and Delphi 2010 with the sample database: 5 pages, PAC 2024 and
veraPDF `ua1` pass. With an empty database: 1 page (Linux, 2026-09-26).
With the sample data of a fresh database: 5 pages, the same normalized PDF
on every run, Windows (Delphi 7, Delphi 13 Win32) and Linux (FPC 3.2.2) on
2026-10-12; validators not run yet.
