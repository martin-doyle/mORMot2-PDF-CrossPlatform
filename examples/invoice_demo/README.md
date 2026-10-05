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
| address field: return address line, then the customer's address | 20 mm left, 45 mm down, 85 × 45 mm | return line artifact, address one `P` per line |
| information block "Rechnungsdaten" | from 125 mm left, 50 mm down | `H2`, one `P` per "label: value" |
| subject "Rechnung R2020-0815" and the amount due | 98.46 mm down | `H1`, bold `P` — **first in the tree** |
| fold marks, hole mark | 105, 210 and 148.5 mm, in the left margin | artifact |
| body: Positionen, Zahlung, Kunde / Rechnungssteller, Hinweise | below the subject | `H2` each |
| footer: company, tax data, bank accounts, three columns | bottom margin, every page | artifact |
| header of page 2 on: seller, invoice number, page | top margin, not on page 1 | artifact |

Reading order and headings, which with `UseOutlines` are the bookmarks too:

```
H1  Rechnung R2020-0815
P   Rechnungsbetrag 226,00 EUR, zahlbar bis 29.09.2026.
P   Kaeufername / Kaeuferstrasse 1 / 05678 Kaeuferstadt   (the address field)
H2  Rechnungsdaten     Rechnungsnummer, -datum, Lieferdatum, Leistungszeitraum,
                       Bestellung, Referenz, Auftrag, Vertrag, Ansprechpartner
H2  Positionen         the item table (THead, TBody, TFoot with row headers),
                       the item descriptions as P
H2  Zahlung            Table: Zahlbetrag | Zahlbar bis | Verwendungszweck,
                       L with one LI per account
H2  Kunde              frame, left: the customer in full
H2  Rechnungssteller   frame, right: the seller in full - the facts of
                       letterhead, return line and footer, tagged once
H2  Hinweise           embedded data, sample data
```

- **The structure tree follows the recording order, not the position.** The
  subject is drawn first, so a screen reader starts with it, though it stands
  below the address on paper.
- **Everything decorative is an artifact**: letterhead, logo, return address
  line, marks, running header and footer. Their facts are tagged once, under
  "Rechnungssteller", so a screen reader does not hear the seller five times.
- **Label above value** ("Zahlung"): a table with one header row and one data
  row, drawn without grid or fill; the labels are column headers.
- **The bank accounts are a list.** "List with 2 items" tells at once that
  there is a choice.
- **E-mail addresses are links** (`mailto:`), in the information block and
  under "Kunde" and "Rechnungssteller": a `Link` element with its annotation,
  which clears the PAC hint "Link in text does not have a Link element".

## Questions for the review

1. Subject first in the reading order, though it stands below the address:
   right, or should the tree follow the paper (letterhead, address,
   information block, subject)?
2. The address field and the information block have no heading of their own
   in the window; the block carries a visible "Rechnungsdaten". Enough?
3. "Kunde" repeats the address of the window. Keep, or leave the window
   address as the only one?
4. Label/value: "label: value" paragraphs in the information block, a
   one-row table under "Zahlung". Which is better for a screen reader? A
   label heading its row (`TH /Scope /Row`) or one table wrapped into bands
   would need an engine change (R-29).
5. Should the IBAN stay in groups of four? Screen readers may read "1245" as
   a number; `/ActualText` would change copy and paste too.

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
