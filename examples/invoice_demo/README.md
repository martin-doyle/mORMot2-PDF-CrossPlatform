# invoice_demo — Accessible invoice, PDF/A-3U + PDF/UA-1 (proposal)

**Status: for review, not part of the learning path yet.** The invoice of
[zugferd_demo](../zugferd_demo/README.md), with the same data and the same
embedded `factur-x.xml`, laid out for a screen reader user.
`zugferd_demo` stays the reference demo until this one is accepted.

**Layer 3.** `uses mormot.ui.report`, only the API `TGDIPages` has today. No
change in `src/`.

## Why

`zugferd_demo` passes veraPDF and PAC, but apart from its H1 and the item
table it is a run of paragraphs. A screen reader user gets two jump targets
and reads the rest line by line. Two accounts are split into "Bankverbindung:
…" and "oder …", and the amount due sits in the last row of the table.

This demo gives every section a heading, and with `UseOutlines` the same
headings become the bookmarks:

```
H1  Rechnung R2020-0815
P   Rechnungsbetrag 226,00 EUR, zahlbar bis 29.09.2026.    (bold, the summary)
H2  Rechnungsdaten     Table: Rechnungsnummer | Rechnungsdatum | Lieferdatum | Leistungszeitraum
                       Table: Ihre Bestellung | Ihre Referenz | Unser Auftrag | Vertrag
H2  Kunde              address lines (P each), USt-IdNr., contact
H2  Rechnungssteller   address lines, USt-IdNr., Steuernummer, register, contact
H2  Positionen         the item table (THead, TBody, TFoot with row headers),
                       the item descriptions as P
H2  Zahlung            Table: Zahlbetrag | Zahlbar bis | Verwendungszweck
                       P "Bankverbindungen, zur Wahl:" + L with one LI per account
H2  Hinweise           embedded data, sample data
Artifacts              letterhead (SetHeader), footer with page number (SetFooter)
```

- **Label above value** ("Rechnungsdaten", "Zahlung"): a table with one header
  row and one data row, drawn without grid or fill. The labels are column
  headers (`TH /Scope /Column`), so a screen reader names the label with each
  value. A pair without its value is left out.
- **Letterhead and footer are artifacts.** Every fact in them (seller,
  address, VAT ID) is tagged once in the body, under "Rechnungssteller". A
  screen reader reads them once, not again on every page.
- **The bank accounts are a list.** "List with 2 items" tells at once that
  there is a choice, and an item makes sense without the one before.
- **The order numbers are shown**: buyer's order, seller's order and contract.
  `zugferd_demo` reads none of them.

## Questions for the review

1. Should the summary line stay right after the H1, or does it duplicate the
   "Zahlung" section?
2. Are one-row tables right for label/value data? The alternatives are a
   label heading its row (`TH /Scope /Row`) or one table wrapped into two
   bands (R-29). Both need an engine change.
3. Is the address as one `P` per line acceptable, or should it be one `P`?
4. Should the IBAN stay in groups of four? Screen readers may read
   "1245" as a number; `/ActualText` would change copy and paste too.
5. Is a letter layout for a window envelope (DIN 5008) needed? Then the
   return-address line above the address would be an artifact.

## Limits of TGDIPages found on the way

Collected in [ROADMAP R-29](../../docs/ROADMAP.md), together with the two
ways to make label/value data one table. In this demo they show as follows:
`DrawSection` adds the space above an H2 itself, the labels are column
headers, there is no return-address line, the letterhead and the footer are
one line each, and each bank account must fit into one line.

## Build and run

```bash
lazbuild invoice_demo.lpi -B      # Windows: "C:\lazarus\lazbuild.exe" …
bin/<target>/invoice_demo         # -> invoice_demo_<os>_<cpu>_<compiler>.pdf
```

The switches `--no-attachment` and `--untagged` work as in `zugferd_demo`.
Check the output with veraPDF (`3u`, `ua1`), Mustang and PAC 2024, as for
`zugferd_demo`.
