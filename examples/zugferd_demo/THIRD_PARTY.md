# Third-Party Material

## `xrechnung.xml`

| | |
|---|---|
| **Source** | [KoSIT xrechnung-testsuite](https://github.com/itplr-kosit/xrechnung-testsuite), release `v2026-08-31` |
| **File** | `src/test/business-cases/standard/01.01a-INVOICE_uncefact.xml` |
| **Last changed upstream** | commit `33cf3bdf13fb0d8443c51371ab892f25a9468d79` (2026-06-08) |
| **Publisher** | Koordinierungsstelle für IT-Standards (KoSIT) |
| **License** | Apache License 2.0; the full text is in [`xrechnung.LICENSE.txt`](xrechnung.LICENSE.txt), copied from the same release |
| **Changes** | none. The file is byte-identical to its source (SHA-256 `727b51982a84c9b406599a7384783570910440ed405c9bb6d918b22442636886`). It is only renamed, to the name ZUGFeRD prescribes for an embedded XRechnung |

The upstream repository has no `NOTICE` file, and the XML carries no copyright
header of its own, so there is no further notice to retain.

It is an XRechnung 3.0 invoice in UN/CEFACT CII syntax (EN 16931 compliant),
with placeholder parties such as `[Seller name]`. The demo draws its content
on the page and embeds the file unchanged.

`.gitattributes` marks it `-text`, so no checkout converts its line endings
and the checksum above keeps holding.
