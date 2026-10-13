# zugferd_demo — Hybrid e-invoice, PDF/A-3U + PDF/UA-1

Demo 7 of the [learning path](../../docs/DEMOS.md#demo-7--zugferd_demo).

**Layer 3.** `uses mormot.pdf.report` — nothing else of this project; it
re-exports the PDF/A levels, `afr*` and `PdfMetadataFacturX`.

Reads the invoice data from `factur-x.xml`, draws the invoice with `TGDIPages`
and embeds the same file as an associated file: a hybrid invoice of the
ZUGFeRD 2.x / Factur-X 1.x profile **EN 16931**, as exchanged between
businesses in Germany and France. The file is PDF/A-3U and PDF/UA-1 at once.

**What is special here**

- **The page is read from the file it embeds**, so the two cannot differ.
  `ReadInvoice` fills a record `TInvoice`, the page is drawn from the record —
  that record is where data from your own database or ERP export would go in
- `ReadInvoice` is a demo reader, not an XML parser: fixed element paths, the
  prefixes `rsm:`/`ram:`/`udt:` as in the file, no entities, no validation.
  mORMot2 has no XML reader; a `PosEx` search through the nested tags is
  enough for one known file. A file that is not UTF-8, or declares another
  encoding, is refused: ZUGFeRD / Factur-X prescribe UTF-8
- **The source is pure ASCII.** The labels are German without umlauts ("Ihre
  Referenz", "Bankverbindung"); every umlaut on the page ("Verkäufername",
  "Käuferstraße 1") comes from the UTF-8 XML as `RawUtf8`. So the same source
  builds with FPC, Delphi 7 and Delphi 2010 without code-point constants.
  Amounts, dates and the IBAN are formatted for a German invoice (`226,00`,
  `30.08.2026`, groups of four); an amount keeps every decimal the XML has,
  two at least, and a label without its value is left out
- `ExportPdfLevel := pdfa3U` and `ExportPdfTagged := True` before the first
  `NewPage`; `DrawHeading`, `DrawParagraph` and a `TTableLayout` table give
  `H1`, `P` and `Table` with `THead`, `TBody` and a `TFoot` for the
  totals — no `BeginStructContent` in the demo. `FooterRowHeader` makes the
  label of each totals row its row header (`TH`, `/Scope /Row`)
- `AddExportPdfAttachment(..., afrAlternative)` embeds the XML;
  `ExportPdfMetadataExtension := PdfMetadataFacturX('EN 16931', ...)` writes
  the `fx:` XMP properties with their PDF/A extension schema;
  `ExportPdfPageMode := pmUseAttachments` opens the viewer on the attachment. The engine adds
  the `pdfuaid` schema to the same list

**The invoice data** is the sample `Gesamtbeispiel` of
[XRechnung for Delphi](https://github.com/LandrixSoftware/XRechnung-for-Delphi),
contributed by Landrix under the licence of this project: two items at 7 % and
19 % VAT, a billing period, a due date and two bank accounts. Names, numbers
and accounts are sample data.

**Verified:** the demo with its earlier invoice data passed veraPDF `3u` and
`ua1`, Mustang-CLI and PAC 2024 on Windows, Linux and macOS, with one accepted
quality hint — the e-mail addresses are text without a link element (roadmap
W-2). The current data is checked the same way.

**Not for invoices to German authorities.** They take pure XML (XRechnung),
not a PDF. The engine only writes the PDF/A-3 container; it neither generates
nor validates invoice XML.

**Switches**, to tell the sources of a checker failure apart:

| Switch | Effect |
|---|---|
| `--no-attachment` | no `factur-x.xml` in the PDF, no `fx:` metadata; the page is still read from it |
| `--untagged` | no structure tree: PDF/A-3U without PDF/UA |

**Build and run** — `factur-x.xml` is looked up in the current folder, then
two levels above the executable, i.e. in this folder:

```bash
lazbuild zugferd_demo.lpi -B      # Windows: "C:\lazarus\lazbuild.exe" …
bin/<target>/zugferd_demo         # -> zugferd_demo_<os>_<cpu>_<compiler>.pdf, next to the executable
```

Delphi 7 or Delphi 2010 (Win32), with `MORMOT2` set to the mORMot2 checkout:
build from the repository root, run from this folder — the executable lands
one level higher than the FPC one, so the second lookup misses:

```bat
tests\build_delphi7.bat examples\zugferd_demo\zugferd_demo.lpr
cd examples\zugferd_demo
..\..\bin\d7\zugferd_demo\zugferd_demo.exe   &rem -> zugferd_demo_windows_x86_delphi-7.pdf, next to it
```

**Checking the output**

```bash
verapdf -f 3u  zugferd_demo_<os>_<cpu>_<compiler>.pdf     # PDF/A-3U
verapdf -f ua1 zugferd_demo_<os>_<cpu>_<compiler>.pdf     # PDF/UA-1
java -jar Mustang-CLI-<version>.jar --action validate --source zugferd_demo_<os>_<cpu>_<compiler>.pdf
```

**Other files here**

| File | What it is |
|---|---|
| `factur-x.xml` | the invoice data, read for the page and embedded as it is |
| `.gitattributes` | keeps the XML's line endings, so every platform embeds the same bytes |
