# invoice_demo — Accessible invoice, PDF/A-3U + PDF/UA-1 (proposal)

**Status: for review, not part of the learning path yet.** The invoice of
[zugferd_demo](../zugferd_demo/README.md), with the same data and the same
embedded `factur-x.xml`, laid out for a screen reader user.
`zugferd_demo` stays the reference demo until this one is accepted.

**Layer 3.** `uses mormot.ui.report`. Besides the existing API it uses what
R-29 added on this branch: frames, artifacts, paper coordinates, images,
running texts in columns and tagged links.

## Why

`zugferd_demo` passes veraPDF and PAC, but apart from its H1 and the item
table it is a run of paragraphs. A screen reader user gets two jump targets
and reads the rest line by line. Two accounts are split into "Bankverbindung:
…" and "oder …", and the amount due sits in the last row of the table.

## The page: a business letter after DIN 5008, form B

| Part | Position (from the paper edge) | In the structure tree |
|---|---|---|
| letterhead: company name, address line, logo | above 45 mm | artifact |
| address field: return address line, then the customer's address | 20 mm left, 45 mm down, 85 × 45 mm | artifact |
| information block "Rechnungsdaten" | from 125 mm left, 50 mm down | `H2`, one `P` per "label: value" |
| subject "Rechnung R2020-0815" | 98.46 mm down | `H1` — **first in the tree** |
| fold marks, hole mark | 105, 210 and 148.5 mm, in the left margin | artifact |
| body: Positionen, Zahlung, Kunde / Rechnungssteller, Hinweise | below the subject | `H2` each |
| footer: company, tax data, bank accounts, three columns | bottom margin, every page | artifact |
| header of page 2 on: seller, invoice number, page | top margin, not on page 1 | artifact |

Reading order and headings, which with `UseOutlines` are the bookmarks too:

```
H1  Rechnung R2020-0815
H2  Rechnungsdaten     Rechnungsnummer, -datum, Kundennummer, Bestellung,
                       Referenz, Auftrag, Vertrag, Ansprechpartner
H2  Positionen         Lieferdatum, Leistungszeitraum, the item table (THead,
                       TBody, TFoot with row headers), then a P per item:
                       description, classification, period, order line
H2  Zahlung            Table: Zahlbetrag | Zahlbar bis | Verwendungszweck,
                       L with one LI per account
H2  Kunde              frame, left: name, address, USt-IdNr.
H2  Rechnungssteller   frame, right: name, address, USt-IdNr. (else the tax
                       number), the register note - the facts of letterhead,
                       address field and footer, tagged once
H2  Hinweise           embedded data, sample data
```

- **The structure tree follows the recording order, not the position.** The
  subject is drawn first, so a screen reader starts with it, though it stands
  below the address on paper.
- **Everything decorative is an artifact**: letterhead, logo, the whole
  address field, marks, running header and footer - as Word exports
  letterhead, header and footer. Their facts are tagged once, under "Kunde"
  and "Rechnungssteller", so a screen reader hears each party once and under
  a heading that says who it is. On paper a party may stand twice.
- **Only what the paper needs**: the parties with name, address (the country
  only when it is not the seller's, DIN 5008) and VAT ID; contacts, phone
  numbers and further e-mail addresses are in the embedded XML.
- **The register note is tagged** under "Rechnungssteller", though the
  footer shows it too: it is information, not decoration, and the footer
  is its only other place (Matterhorn 01-002, WCAG 1.3.1).
- **Label above value** ("Zahlung"): a table with one header row and one data
  row, drawn without grid or fill; the labels are column headers.
- **The bank accounts are a list.** "List with 2 items" tells at once that
  there is a choice.
- **The e-mail address is a link** (`mailto:`), in the information block: a
  `Link` element with its annotation, which clears the PAC hint "Link in text
  does not have a Link element".

## Review (2026-10-06)

An accessibility expert checked the version of 2026-10-05 and accepted the
sender as an artifact (PAC warns about artifact text, Word does the same),
the tables, the blocks and the IBAN in groups of four. Liked: the facts of
the artifacts come once more as text. The one finding - the customer stood
twice, and the name of the address field was read right after the subject,
without context - led to this version: the address field is an artifact,
"Kunde" and "Rechnungssteller" are cut to what the paper needs, Lieferdatum
and Leistungszeitraum moved from the information block to "Positionen".
Afterwards, on the same review: the amount due below the subject went (it
stands under "Zahlung"), and the item descriptions stand close together,
a line per item, as Lieferdatum and Leistungszeitraum.
The parties stay at the end of the reading order; the headings make them
reachable.

## Limits of TGDIPages found on the way

Collected in [ROADMAP R-29](../../docs/ROADMAP.md), together with the two
ways to make label/value data one table. In this demo they show as follows:
`DrawSection` adds the space above an H2 itself and moves a heading to the
next page when less than two lines fit below it ("keep with next" is open);
a pair of frames is moved the same way, since a frame does not break the
page; each bank account must fit into one line.

## Build and run

```bash
lazbuild invoice_demo.lpi -B      # Windows: "C:\lazarus\lazbuild.exe" …
bin/<target>/invoice_demo         # -> invoice_demo_<os>_<cpu>_<compiler>.pdf
```

The switches `--no-attachment` and `--untagged` work as in `zugferd_demo`.
Check the output with veraPDF (`3u`, `ua1`), Mustang and PAC 2024, as for
`zugferd_demo`.
