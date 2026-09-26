# layer1_demo — TPdfDocument and TPdfCanvas alone

Demo 8 of the [learning path](../../docs/DEMOS.md#demo-8--layer1_demo).

Draws a one-page tagged PDF with the low-level API only: no TCanvas bridge and
no report engine. That makes it the one demo that builds with Delphi 7 as well
as with FPC.

**What is special here**

- coordinates are PDF points, with Y counted from the **bottom** of the page;
  the Y of a text line is its baseline
- text goes in as UTF-8 and is drawn with `TextOutW`, so both compilers draw
  the same characters. A Delphi 7 `string` literal would be in the ANSI code
  page and an FPC one in UTF-8, which is why the non-ASCII line is a `RawUtf8`
  constant of UTF-8 bytes
- the caller builds the structure: `H1`, `H2`, `P` and a `Figure` with
  alternate text. Each heading also gets its outline entry, which PDF/UA
  requires and which the low-level API does not create by itself
- a path outside any element is written as an artifact automatically, like
  the rule under the title. Text needs `BeginArtifact`/`EndArtifact`, like
  the footer
- no image: `mormot.pdf.fpimage` is FPC-only, and the demo keeps to what both
  compilers share

**Build and run**

```bash
lazbuild layer1_demo.lpi -B              # Windows: "C:\lazarus\lazbuild.exe" …
bin/<target>/layer1_demo                 # -> layer1_demo_<os>.pdf, next to the executable
```

Delphi 7 (Win32), from the repository root, with `MORMOT2` set to the mORMot2
checkout:

```bat
tests\build_delphi7.bat examples\layer1_demo\layer1_demo.dpr
bin\d7\layer1_demo\layer1_demo.exe       &rem -> bin\d7\layer1_demo\layer1_demo_windows.pdf
```

**One source for both IDEs.** `layer1_demo.dpr` is the program Lazarus opens
through `layer1_demo.lpi` and Delphi opens directly. In the Delphi IDE, set
the project's search path to this repository's `src\core`,
`src\platform\windows` and `src\lib`, plus mORMot2's `src\core`, `src\lib`
and `src\crypt`, and add mORMot2's `src` for `mormot.defines.inc`. Leave
mORMot2's `src\ui` out: it holds the original `mormot.ui.pdf`, which Delphi
would take instead of this project's without a word.
