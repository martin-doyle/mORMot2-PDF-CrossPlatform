# mormot_demo — ORM integration

Demo 4 of the [learning path](../../docs/DEMOS.md#demo-4--mormot_demo).

A Lazarus GUI report whose rows come from a live SQLite database through the
mORMot ORM.

| File | Role |
|---|---|
| `data.pas` | `TOrmEmployee`, `TOrmCustomer`, `TOrmCustomerOrder` |
| `server.pas` | `TDemoServer.GetInvoiceData` returning a DTO array |
| `uMainForm.pas` | `BuildReport` → `DrawInvoiceTable` with `TTableLayout` |

**What is special here**

- `TRestClientDB` + `TRestServerDB` for the local database, and a service
  method that hands out DTOs — the report never touches the ORM
- an empty result set still produces a valid table, via a placeholder row
- otherwise the same `TTableLayout` and tagged export as `markdown_demo`

**Build and run**

```bash
lazbuild mormot_demo.lpi -B
bin/<target>/mormot_demo                    # GUI
bin/<target>/mormot_demo --export           # batch -> mormot_demo_<os>.pdf, next to the executable
bin/<target>/mormot_demo --export out.pdf   # batch to a file of your choice; both need a display
```

**The database** is `data/mormot_demo.db` in this folder, found two levels
above the executable. The sample database with the orders is not versioned
(`.gitignore`); without it SQLite creates an empty one, and the table shows its
placeholder row "No orders available". The `data/` folder itself has to exist:
a fresh clone has none, and the demo then stops with runtime error 217.

**Status:** runs; checked on Linux with `--export` (2026-09-26), both with the
sample database (5 pages) and with an empty one (1 page).
