# Third-Party Material

## `factur-x.xml`

| | |
|---|---|
| **Source** | [KoSIT xrechnung-testsuite](https://github.com/itplr-kosit/xrechnung-testsuite), release `v2026-08-31` |
| **File** | `src/test/business-cases/standard/01.01a-INVOICE_uncefact.xml` (SHA-256 `727b51982a84c9b406599a7384783570910440ed405c9bb6d918b22442636886`) |
| **Last changed upstream** | commit `33cf3bdf13fb0d8443c51371ab892f25a9468d79` (2026-06-08) |
| **Publisher** | Koordinierungsstelle für IT-Standards (KoSIT) |
| **License** | Apache License 2.0; the full text is in [`factur-x.LICENSE.txt`](factur-x.LICENSE.txt), copied from the same release |
| **Result here** | SHA-256 `f44207bbcaefa61a0014f3cd4d14c738aad8b2bee3dd09dbb4f6e546284d9ed9` |

**Changes**, as Apache License 2.0 section 4(b) requires them to be stated —
the file says the same in a comment below its XML declaration:

1. the comment itself, added
2. the specification identifier (BT-24, `GuidelineSpecifiedDocumentContextParameter/ID`)
   changed from `urn:cen.eu:en16931:2017#compliant#urn:xeinkauf.de:kosit:xrechnung_3.0`
   (the XRechnung 3.0 CIUS) to `urn:cen.eu:en16931:2017`, which makes it an
   invoice of the ZUGFeRD / Factur-X profile EN 16931
3. renamed to `factur-x.xml`, the name ZUGFeRD and Factur-X prescribe

Nothing else changed. The upstream repository has no `NOTICE` file, and the
XML carries no copyright header of its own, so there is no further notice to
retain.

**Validation** with Mustang-CLI 2.26.0: valid as profile EN 16931. One
warning and two notices remain, and none of them is an error:

- `PEPPOL-EN16931-R008`, empty element: `ApplicableHeaderTradeDelivery` is empty
  upstream; it is mandatory, and filling it would mean inventing a delivery date
- `BR-DE-21`: the identifier is no longer XRechnung's, which is the point of the
  change
- `BR-DE-TMP-32`: no delivery date or invoicing period on the header, as upstream

The content is placeholder data (`[Seller name]` and the like). The demo draws
it on the page and embeds the file as it is here.

`.gitattributes` marks it `-text`, so no checkout converts its line endings
and the checksum above keeps holding.
