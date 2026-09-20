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
bin/<target>/mormot_demo --export out.pdf   # batch, still needs a display
```

**Status:** the demo compiles on all platforms but has never been run — it
waits for a sample database (see [ROADMAP](../../docs/ROADMAP.md)).
