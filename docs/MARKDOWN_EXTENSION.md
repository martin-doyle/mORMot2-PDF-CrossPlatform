# Markdown Extension — What to Build On, What to Decide

Markdown as an input of the report engine, suggested by Arnaud on the
refactoring gist (2026-10-11, [comment 6420218](https://gist.github.com/synopse/9e31d8808ed2575ad5ad23da6fe41e4f?permalink_comment_id=6420218#gistcomment-6420218)):
"some minimal markdown rendering: it is a simple format, probably better than
individual methods calls. Even simple tables could be generated." Answered
"a good fit … we'll look into it" ([6420868](https://gist.github.com/synopse/9e31d8808ed2575ad5ad23da6fe41e4f?permalink_comment_id=6420868#gistcomment-6420868)).
The work is ROADMAP R-31; this file collects what is known before a plan.

**State:** 2026-10-13. mORMot2 read at `681bbe2a1` (the trunk clone of
`CLAUDE.local.md`); the engine side from the skills and
`docs/ACCESSIBILITY_REFERENCES.md`, not measured anew. Libraries and
specifications from their published pages; what was not checked is marked
**Check**.

## Questions

1. What does mORMot2 bring for Markdown already? — [mORMot2 Today](#mormot2-today)
2. Which references define the minimum scope? — [Reference Documents](#reference-documents)
3. Which extensions are common, which make sense here? — [Extensions](#extensions)
4. Which variants make sense: a whole document, subsets in code? — [Variants](#variants)

What is still to decide: [Open Decisions](#open-decisions).

## Sources

| Source | What it is | Licence | Use here |
|---|---|---|---|
| [CommonMark Spec 0.31.2](https://spec.commonmark.org/0.31.2/) (2024-01-28) | The unambiguous specification of Markdown, with ~650 numbered examples (`spec.json`) | CC BY-SA 4.0 | The minimum scope, and its examples as a test corpus for the subset taken |
| [GitHub Flavored Markdown Spec 0.29-gfm](https://github.github.com/gfm/) (2019-04-06) | CommonMark plus five marked extensions: tables, task list items, strikethrough, extended autolinks, disallowed raw HTML | CC BY-SA 4.0 | Tables — the one extension Arnaud names |
| [GitHub: Basic writing and formatting syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax) | What github.com renders beyond the GFM spec: footnotes, alerts, emoji, `<sub>`/`<sup>`/`<ins>` | — | What users expect, not a specification |
| [GitHub: Creating diagrams](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams) | Fenced blocks `mermaid`, `geojson`, `topojson`, `stl` | — | Shows that diagrams are a renderer's job, see Extensions |
| [RFC 7763](https://www.rfc-editor.org/rfc/rfc7763) / [RFC 7764](https://www.rfc-editor.org/rfc/rfc7764) (2016, Informational) | `text/markdown` with a `variant` parameter; registry of variants: `CommonMark`, `GFM`, `pandoc`, `MultiMarkdown`, `Extra`, `Fountain`, `kramdown-rfc2629`, `rfc7328` | — | Naming the dialect the engine accepts; no syntax |
| [Deriving HTML from PDF](https://pdfa.org/resource/deriving-html-from-pdf/) (PDF Association, 1.0, 2019) | Tagged PDF 2.0 roles to HTML elements | CC BY 4.0 | The reverse of what is needed here — Markdown is defined through HTML, so its mapping read backwards gives the tags. **Check**: its table not read yet |
| [Techniques for Accessible PDF](https://github.com/pdf-association/techniques-for-accessible-pdf) | PASS/FAIL files per technique (headings, lists) | CC BY 4.0 | What the tags of a Markdown document must look like; already mapped in `docs/ACCESSIBILITY_REFERENCES.md` |

## mORMot2 Today

`mormot.core.fmt`, section "Markup (e.g. Markdown or Emoji) process":

| What | Where | Notes |
|---|---|---|
| `HtmlEscapeMarkdown(md, esc)` / `AddHtmlEscapeMarkdown(W, P, esc)` | `mormot.core.fmt` | Markdown → HTML in one pass into a `TTextWriter`; the parser is the private object `TTextWriterEscape` |
| `HtmlEscapeWiki` / `AddHtmlEscapeWiki` | same | a wiki dialect: `*em*`, `+strong+`, `` `code` `` |
| `{{{MarkdownToHtml …}}}`, `{{{SimpleToHtml …}}}` | `mormot.core.mustache` | Mustache helpers on top; `SimpleToHtml` = Markdown without HTML pass-through |
| Emoji | `mormot.core.fmt` | `:joy:` and `:)` → UTF-8 (U+1F600–U+1F64F), `heEmojiToUtf8` |
| Tests | `test/test.core.data.pas` (from line 4986) | 38 `CheckEqual` of `HtmlEscapeMarkdown`, 9 of `HtmlEscapeWiki`: emphasis, escapes, paragraphs |

What it parses (read from `TTextWriterEscape.NewMarkdownLine` and
`AddHtmlEscapeMarkdown`):

- **Blocks:** paragraphs (blank line), unordered list (`*`/`+`/`-` + space),
  ordered list (must start with `1.`), blockquote (`>` + space), indented
  code (4 spaces), fenced code (```` ``` ````, no info string)
- **Inline:** `*em*`/`_em_`, `**strong**`/`__strong__`, `` `code` ``,
  backslash escapes, `[text](url)`, `![alt](src)`, bare `http(s)://`
- **Not:** headings (`#` is not recognised at all), tables, nested lists
  ("don't implement nested levels yet"), reference links, setext headings,
  horizontal rules, hard line breaks, HTML escaping by default
- **Differs from CommonMark:** `t_e_st` gives `<em>` (CommonMark: no
  intraword `_` emphasis); delimiters are toggled, not matched, so
  `**a *b** c*` nests wrongly; a third blank line leaks a space
  (`'<p> toto</p>'` is the expected value of one test)

So it is a writer of HTML, not a parser: no element tree, no events, no
place to hook a PDF renderer in. What can be reused is its approach (one
pass over `PUtf8Char`, no allocations) and its tests; its scope is below the
engine's present API (headings, tables).

**Mustache as the template side — Check.** `TSynMustache` could produce the
Markdown from data, so that Markdown is the input of the report and Mustache
fills it in: ORM or JSON data in, a template with
`{{#rows}}| {{Name}} | {{Total}} |{{/rows}}` out, then the renderer — the
report itself a text file instead of code. Read so far only from the
declarations at `681bbe2a1`; to check:

- **Escaping:** `{{value}}` escapes HTML, `{{{value}}}` nothing;
  `EscapeInvert` swaps the two. There is no Markdown escaping, so a `*`, `|`,
  `#` or `_` in the data turns into markup (a `|` breaks a table row). Is
  a helper (e.g. `{{MdEscape Name}}`) needed, or a third escaping mode?
- **Helpers:** the standard list (`DateFmt`, `Upper`, `#if` …) and
  `HelperAdd` for own ones — enough for number and date formats in a
  report, or does the report need its own?
- **Partials:** `TSynMustachePartials` for a shared header, footer or
  address block
- **Where it sits:** an example or a helper in `mormot.core.mustache` (a
  `MarkdownToPdf` beside `MarkdownToHtml` makes no sense — a helper returns
  text), or a convenience in the report unit taking template and data

**Elsewhere for Pascal** — none fits as it is:

| Library | Licence | Fit |
|---|---|---|
| FPC `fcl-md` (`Markdown.Parser`, `.Elements`, `.HtmlRender`, `.PDFRender`, …) | FPC (modified LGPL) | An element tree, options for GFM, alerts, footnotes, definition lists, heading IDs. Only in FPC main — not in 3.2.2 (checked here: `C:\lazarus\fpc\3.2.2` has no `fcl-md`); FPC-only and built on `Classes`, so no Delphi 7. Its `PDFRender` uses `fcl-pdf`, not this engine. A model for the element set |
| [delphi-markdown](https://github.com/grahamegrieve/delphi-markdown) (Grahame Grieve) and its fork [MarkdownProcessor](https://github.com/EtheaDev/MarkdownProcessor) (Ethea) | Apache-2.0 (**Check**: from directory listings, not the LICENSE file) | HTML output only; CommonMark 0.28 incomplete; Ethea from Delphi XE3. Apache-2.0 against mORMot's tri-licence: compatible with GPL-3, not with GPL-2 — **Check** |
| [md4c](https://github.com/mity/md4c) (C) | MIT | Passes all CommonMark 0.31.2 tests; SAX-like: `md_parse()` calls back on enter/leave block, enter/leave span, text — exactly the shape a report renderer needs; flags for tables, task lists, strikethrough, footnotes, LaTeX math, admonitions, wiki links. One `.c` file: would go to `static/` as the other C libraries of mORMot. Versions as git tags only, no GitHub releases |
| [cmark](https://github.com/commonmark/cmark) / cmark-gfm (C) | BSD-2 | The reference implementation; a tree API. Larger than md4c |

## Reference Documents

There is no "minimal Markdown" standard; the scope is a subset of
CommonMark, named by its sections, plus GFM tables. A proposal for the
minimum, with what each needs from the engine (status as in
`docs/ACCESSIBILITY_REFERENCES.md`: **Exists**, **Gap**, **Check**, **R-29**
= solved on `feature/invoice-demo`, waiting for its merge):

| CommonMark / GFM | Element | Tag | `TGDIPages` | Status |
|---|---|---|---|---|
| 4.2 ATX headings, 4.3 setext | `#`…`######`, `===`/`---` underlined | `H1`–`H6` | `DrawHeading` (bookmark) | Exists |
| 4.8 Paragraphs | text, wrapped | `P` | `DrawParagraph` | Exists |
| 6.2 Emphasis | `*em*`, `**strong**` | `Span` (`Em`/`Strong` in PDF 2.0) | `DrawEm`, `DrawStrong` | Exists |
| 6.1 Code spans | `` `code` `` | `Span` / `Code` | `DrawCode` | Exists. **Check** which role |
| 4.5 Fenced, 4.4 indented code | code block | `P` or `Code` inside it, monospace, no wrap | none for a block | Gap: needs a block method (keeps line breaks, may split across pages) |
| 5.1 Block quotes | `> …` | `BlockQuote` | `DrawQuote` | Gap: writes `P` (R-30) |
| 5.2/5.3 Lists | `-`, `1.` | `L`/`LI`/`Lbl`/`LBody`, `/ListNumbering` | `DrawListItem` | Gap: no `Lbl`, no `/ListNumbering` (R-29 item 6, R-30); nested `L` **Check** |
| 4.10 Tables (GFM) | `\| a \| b \|`, alignment row | `Table`/`THead`/`TBody`/`TH` `/Scope /Column`/`TD` | `TTableLayout`, `DrawTableHeader`/`Row` | Exists; column widths must be computed (GFM gives none), alignment maps to the column format |
| 6.3 Links | `[text](url)`, `<url>` | `Link` + `OBJR` | `DrawLink` | R-29 (today a `Span`, URL dropped) |
| 6.4 Images | `![alt](src)` | `Figure` with `/Alt` | none: `dckDrawBitmap` has no recording method (report skill) | Gap, plus: where `src` is read from (file, resource, callback) |
| 4.1 Thematic breaks | `---` | artifact | `DrawLine` | Exists (as artifact: **Check**) |
| 6.7/6.8 Hard / soft line breaks | two spaces / newline | — | `MoveToNextLine` | Exists |
| 4.6/6.6 HTML blocks, raw HTML | `<div>`, `<b>` | — | — | Not supported: no HTML engine; dropped or written as text (GFM 6.11 allows filtering) |
| 4.7 Link reference definitions | `[x]: url` | — | — | Parser only, no engine work |

Conformance can then be stated as "the CommonMark examples of sections …
pass", measured with `spec.json` the way md4c and cmark do.

## Extensions

| Extension | Defined by | Common? | Tag / engine | Recommendation |
|---|---|---|---|---|
| Tables | GFM 4.10 | everywhere | see above | **Minimum** — Arnaud names it |
| Strikethrough `~~x~~` | GFM 6.5 | everywhere | `Span` with `/TextDecorationType /LineThrough` | Yes, after the bug "Underline and Strike-Out Are Not Drawn" (ROADMAP): today the line is not drawn at all |
| Task lists `- [x]` | GFM 5.3 | GitHub, GitLab | `Lbl` with a check glyph (not a form field) | Yes, once `Lbl` exists |
| Extended autolinks | GFM 6.9 | GitHub | `Link` | With R-29 |
| Footnotes `[^1]` | github.com, pandoc, MultiMarkdown, PHP Extra | common | `Note` with `/ID` (PDF/UA-1 7.9), reference as `Lbl`/`Link` | Later: needs a page-bottom area in `TGDIPages` or end notes |
| Alerts `> [!NOTE]` | github.com (5 types) | GitHub only, 2023 | `BlockQuote` or `Aside` (PDF 2.0) with a visible label | Cheap once `BlockQuote` exists; label text per language |
| Heading IDs `{#id}`, auto anchors | pandoc, Extra; github.com auto | common | named destination for internal links | With internal links (R-30 "links to structure elements") |
| Definition lists | pandoc, Extra | moderate | `L` with `Lbl` = term (Technique L_14) | Later |
| Front matter (YAML) | pandoc, Jekyll, Hugo | common in docs | `/Title`, `/Lang`, author → document info / XMP | Worth it: PDF/UA needs `/Title` and `/Lang`; mORMot2 writes YAML (`WriteYamlVariant`), reading **Check** |
| Math `$…$`, `$$…$$` | github.com (2022), pandoc, md4c flag | science | `Formula` with `/Alt` (PDF/UA-1 7.7) | Out of scope: needs a TeX layout engine. At most the source as code with `/Alt` |
| Mermaid, GeoJSON, STL | github.com fenced blocks | GitHub | `Figure` | Out of scope, as charts (`CLAUDE.md` "Charts"): Mermaid is a JavaScript renderer. Fall back to a code block, or let the caller hand in a pre-rendered image per block |
| Emoji `:joy:` | github.com | common | text | mORMot2 has it (`heEmojiToUtf8`); needs a colour or symbol face in the PDF — **Check** |
| `<sub>`/`<sup>`/`<ins>` | github.com via raw HTML | GitHub | `Span` | No (raw HTML) |
| Highlight `==x==`, sub/superscript `~x~`/`^x^` | md4c, pandoc, MultiMarkdown | rare | `Span` | No |

## Variants

Three ways to offer it; they do not exclude each other, (C) is the base of
the other two.

| | What the caller writes | Fits | Cost |
|---|---|---|---|
| **(A) Whole document** | `Report.AppendMarkdown(Text)` (or `MarkdownToReport(Report, Text, Options)`): blocks and inlines → recorded commands, page breaks by the engine | Arnaud's "better than individual methods calls"; documents from templates, generated texts, `README`-like content; servers without UI (the new UI-free `mormot.ui.report`) | Block parser, all mappings above; images need a resolver |
| **(B) Inline subset in code** | `Report.DrawParagraphMd('Total **excl.** VAT, see `note`')` — only spans inside one existing call; blocks, tables and images still by method | Mixed reports: the invoice keeps its `TTableLayout`, a remark field from the database carries `**bold**` | Inline parser only; small, but a second entry per text method |
| **(C) Parser with events** | an interface (e.g. `IMarkdownSink`: `BlockStart(kind, info)`, `BlockEnd`, `SpanStart`, `SpanEnd`, `Text`) that `TGDIPages` implements; the caller may wrap it to override one element | One parser for every target: the report, layer 1, and HTML — `HtmlEscapeMarkdown` could become one more sink, which may interest Arnaud for `mormot.core.fmt` | The design work; md4c has exactly this shape |

**Where the parser comes from** (decides the unit and the licence):

1. Own Pascal parser in mORMot style (`PUtf8Char`, no `Classes`), events as
   (C), in `mormot.core.*` beside the present one — runs on every compiler of
   this project, Delphi 7 included; the CommonMark examples of the chosen
   sections as tests. Most work, no dependency.
2. md4c as a static object (`static/`, as mORMot links other C libraries) or
   loaded at run time (`mormot.lib.md4c`) — full CommonMark at once, MIT;
   one more C object per target (Android, aarch64, Delphi Linux64).
   **Check**: whether Arnaud wants another static library.
3. Extend `TTextWriterEscape` — smallest change, but it has no element tree
   and its rules differ from CommonMark (above); headings and tables would
   be added to a design that cannot nest.

`fcl-md` is ruled out by the compilers, delphi-markdown and
MarkdownProcessor by their HTML-only output and an open licence question
(above).

## Open Decisions

- **Scope of the first step:** the minimum table above, or less (headings,
  paragraphs, emphasis, lists, tables — what Arnaud named, without code
  blocks and images)?
- **Variant:** (A) only, (A)+(B), and whether (C) is public API or internal
- **Parser:** own (1) or md4c (2) — ask Arnaud, it is a trunk decision
- **Unit:** the parser in `mormot.core.*` (shared with HTML) or beside the
  report (`mormot.ui.report.markdown`?); the renderer against the UI-free
  report engine of Phase 4, so not before its interface is settled
- **Dialect name:** CommonMark subset plus GFM tables — state it with the
  RFC 7764 identifiers (`CommonMark`, `GFM`) in the documentation
- **Images:** how `![alt](src)` finds its bytes — callback, file path
  relative to a base folder, resources; an empty `alt` = decorative →
  artifact
- **Raw HTML:** dropped, written as text, or an error
- **Dependencies on the engine gaps:** `BlockQuote`, `Caption`, `Lbl`,
  `/ListNumbering`, nested lists (R-30), `Link` (R-29), drawn strike-out
  (ROADMAP bug), an image recording method — Markdown makes them visible,
  so they come first or the Markdown output is not conformant PDF/UA
- **Mustache:** whether templates are part of the first step, and how values
  are escaped for Markdown (see "Mustache as the template side")
- **Tests:** the CommonMark examples against the event stream (no PDF),
  then golden files and veraPDF/PAC for the rendered document;
  `markdown_demo` would then read real Markdown, which its name promises
