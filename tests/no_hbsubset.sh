#!/usr/bin/env bash
#
# Run the test suite and the console demos with libharfbuzz-subset hidden from
# the dynamic linker, to exercise the fallback that embeds the whole face.
#
# Why this is a script and not a test case: mormot.pdf.hbsubset loads the
# library and registers PdfFontSubsetter in its initialization section, which
# runs before any test code exists. A test can observe the outcome but cannot
# choose it. TestSubsetFallbackWithoutSubsetter only simulates the state by
# clearing PdfFontSubsetter; the loader itself is reached only by starting the
# process with the library out of reach, which is what this script does.
#
# Linux only. On macOS the loader falls back to absolute Homebrew and
# /usr/local paths, so hiding the library would mean moving the real file -
# not worth the risk. See docs/ROADMAP.md.
#
# Usage:   tests/no_hbsubset.sh [build-dir]
# Exit:    0 = the fallback behaved, 1 = something to look at
#
set -u

die() { echo "error: $*" >&2; exit 1; }

case "$(uname -s)" in
  Linux) ;;
  *) die "Linux only - see the note above (this is $(uname -s))" ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/tests/bin/test_runner"
[ -x "$RUNNER" ] || die "no test_runner at $RUNNER - build it first"

SHADOW="$(mktemp -d)"
trap 'rm -rf "$SHADOW"' EXIT

# Mirror every shared library the loader might need into a scratch directory,
# then remove the subset one. Symlinks, so nothing is copied and nothing on the
# system is touched.
found=0
for dir in /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu /usr/lib64 /usr/lib /lib; do
  [ -d "$dir" ] || continue
  for so in "$dir"/lib*.so*; do
    [ -e "$so" ] || continue
    ln -sf "$so" "$SHADOW/$(basename "$so")" 2>/dev/null && found=1
  done
done
[ "$found" = 1 ] || die "found no shared libraries to mirror"

hidden=0
for so in "$SHADOW"/libharfbuzz-subset.so*; do
  [ -e "$so" ] || continue
  rm -f "$so"
  hidden=1
done
if [ "$hidden" = 0 ]; then
  echo "note: libharfbuzz-subset was not installed to begin with -"
  echo "      this run still exercises the fallback, just without hiding anything"
fi

echo "== shadow lib dir: $SHADOW (libharfbuzz-subset removed)"
echo

run_hidden() { LD_LIBRARY_PATH="$SHADOW" "$@"; }

# 1. the suite must stay green, with the subset tests skipping rather than
#    failing - a skip is the whole point here.
#
# The tests mark a skip with Check(true, 'SKIP: ...'), which passes, so the
# message is never printed. The observable signal is the assertion count of the
# subset suite: every test that skips contributes 1 assertion instead of its
# usual several, so the total drops sharply. Compare against a normal run.
echo "== test_runner WITH libharfbuzz-subset (reference)"
ref="$("$RUNNER" 2>&1)"
ref_n=$(printf '%s' "$ref" | sed -nE 's/.*Total failed: 0 \/ ([0-9]+) - Pdf subset tests.*/\1/p' | head -1)
echo "   subset suite assertions: ${ref_n:-?}"
echo

echo "== test_runner WITHOUT libharfbuzz-subset"
out="$(run_hidden "$RUNNER" 2>&1)"
echo "$out" | tail -3
out_n=$(printf '%s' "$out" | sed -nE 's/.*Total failed: 0 \/ ([0-9]+) - Pdf subset tests.*/\1/p' | head -1)
green=$(printf '%s' "$out" | grep -c 'Total assertions failed for all test suits:  0 /' || true)
echo
echo "   subset suite assertions: ${out_n:-?}  (reference: ${ref_n:-?})"
if [ "$green" != 1 ]; then
  echo "   RESULT: FAIL - the suite did not come out green"
  exit 1
fi
if [ "$hidden" = 1 ] && [ -n "$ref_n" ] && [ -n "$out_n" ] && [ "$out_n" = "$ref_n" ]; then
  echo "   RESULT: FAIL - library hidden, yet the subset tests still ran in full,"
  echo "           so the loader reached libharfbuzz-subset anyway"
  exit 1
fi
echo "   suite green, and the subset tests stood down as they should"
echo

# 2. the demos must still produce readable PDFs, just bigger ones: without the
#    subsetter the whole face is embedded instead of a subset
status=0
for demo in pdf_demo:pdf_demo_crossplat chinese_demo:chinese_demo rtl_demo:rtl_demo; do
  dir="${demo%%:*}"; bin="${demo##*:}"
  for arch in x86_64-linux aarch64-linux; do
    exe="$ROOT/examples/$dir/bin/$arch/$bin"
    [ -x "$exe" ] && break
  done
  [ -x "$exe" ] || { echo "== $dir: not built, skipped"; continue; }
  work="$(dirname "$exe")"
  before=$(ls -1 "$work"/*.pdf 2>/dev/null | head -1)
  before_size=0
  [ -n "$before" ] && before_size=$(stat -c%s "$before" 2>/dev/null || echo 0)
  if ( cd "$work" && run_hidden "./$bin" >/dev/null 2>&1 ); then
    after=$(ls -1t "$work"/*.pdf 2>/dev/null | head -1)
    after_size=$(stat -c%s "$after" 2>/dev/null || echo 0)
    if [ "$after_size" -lt 1000 ]; then
      echo "== $dir: FAIL - produced only $after_size bytes"
      status=1
    else
      echo "== $dir: ok - $after_size bytes (was $before_size with subsetting)"
    fi
  else
    echo "== $dir: FAIL - the demo did not run"
    status=1
  fi
done

echo
if [ "$status" = 0 ]; then
  echo "RESULT: the fallback holds - suite green, demos still produce PDFs."
  echo "Expect the PDFs to be markedly larger than the subset ones; chinese_demo"
  echo "is the clearest case, since a CJK face is large."
  echo
  echo "Still untested by this script: a HarfBuzz OLDER than 2.9, which loads but"
  echo "lacks hb_subset_or_fail. That needs an old distribution, e.g. Debian 11."
else
  echo "RESULT: see the FAIL lines above."
fi
exit "$status"
