# zugferd_demo — Hybrid e-invoice, PDF/A-3U + PDF/UA-1

Demo 7 of the [learning path](../../docs/DEMOS.md#demo-7--zugferd_demo).

Draws a one-page invoice with `TPdfDocumentVcl` and embeds its machine-readable
data, `factur-x.xml`, as an associated file: a hybrid invoice of the
ZUGFeRD 2.x / Factur-X 1.x profile **EN 16931**, as exchanged between
businesses in Germany and France. The file is PDF/A-3U and PDF/UA-1 at once.

**What is special here**

- `PdfA` goes to the constructor — `TPdfDocumentVcl.Create(true, 0, pdfa3U)`.
  Setting the property later calls `NewDoc` and erases what was drawn
- `Tagged := True` right after it, before the first `AddPage`, as in every
  tagged demo; the page is `H1`, `P` and one `Table` with `THead`, `TBody`
  and `TFoot`
- `CreateFileAttachmentFrom(..., afrAlternative)` embeds the XML;
  `PdfMetadataFacturX('EN 16931')` writes the `fx:` XMP properties with their
  PDF/A extension schema. The engine adds the `pdfuaid` schema to the same list
- the page shows exactly what the XML says, so both change together

**The invoice data is third-party test data**, not written here: test case
`01.01a` of the KoSIT xrechnung-testsuite (Apache-2.0), with its specification
identifier changed from XRechnung to plain EN 16931. The placeholders such as
`[Seller name]` are the original's. Source, change and checksums:
[THIRD_PARTY.md](THIRD_PARTY.md).

**Verified** on Windows, Linux and macOS: veraPDF `3u` 148/148 and `ua1`
106/106, Mustang-CLI valid, PAC 2024 green. PAC keeps one quality hint — the
e-mail addresses are text without a link element — accepted as roadmap W-2.
The same file as `pdfa3A` passes veraPDF `3a` 155/155.

**Not for invoices to German authorities.** They take pure XML (XRechnung),
not a PDF. The engine only writes the PDF/A-3 container; it neither generates
nor validates invoice XML.

**Switches**, to tell the sources of a checker failure apart:

| Switch | Effect |
|---|---|
| `--no-attachment` | no `factur-x.xml`, no `fx:` metadata |
| `--untagged` | no structure tree: PDF/A-3U without PDF/UA |

**Build and run** — `factur-x.xml` is looked up in the current folder, then
two levels above the executable, i.e. in this folder:

```bash
lazbuild zugferd_demo.lpi -B      # Windows: "C:\lazarus\lazbuild.exe" …
bin/<target>/zugferd_demo         # -> zugferd_demo_<os>.pdf, next to the executable
```

**Checking the output**

```bash
verapdf -f 3u  zugferd_demo_<os>.pdf     # PDF/A-3U
verapdf -f ua1 zugferd_demo_<os>.pdf     # PDF/UA-1
java -jar Mustang-CLI-<version>.jar --action validate --source zugferd_demo_<os>.pdf
```

**Other files here**

| File | What it is |
|---|---|
| `factur-x.xml` | the invoice data, embedded as it is |
| `THIRD_PARTY.md` | its source, the change made, checksums, validation result |
| `factur-x.LICENSE.txt` | the Apache License 2.0 it comes under |
| `.gitattributes` | keeps the XML's line endings, so the checksum holds |
