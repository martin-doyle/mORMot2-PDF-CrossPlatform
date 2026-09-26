#!/usr/bin/env bash
#
# Run the test suite and the console demos with libharfbuzz-subset genuinely
# out of reach, to exercise the fallback that embeds the whole face.
#
# Why this is a script and not a test case: mormot.pdf.hbsubset loads the
# library and registers PdfFontSubsetter in its initialization section, which
# runs before any test code exists. A test can observe the outcome but cannot
# choose it. TestSubsetFallbackWithoutSubsetter only simulates the state by
# clearing PdfFontSubsetter; the loader itself is reached only by starting the
# process with the library missing, which is what this script arranges.
#
# How it hides the library: the loader calls dlopen("libharfbuzz-subset.so.0"),
# and dlopen searches LD_LIBRARY_PATH *in addition to* the system cache - so
# pointing LD_LIBRARY_PATH somewhere harmless does NOT hide anything. The file
# itself has to disappear. This script therefore enters an unprivileged mount
# namespace (unshare) and bind-mounts an empty file over each
# libharfbuzz-subset.so*, which is invisible to the rest of the system and
# undone when the process exits. Nothing is deleted, moved or installed.
#
# Linux only. On macOS the loader falls back to absolute Homebrew and
# /usr/local paths, so hiding the library would mean moving the real file -
# not worth the risk. See docs/ROADMAP.md.
#
# Usage:   tests/no_hbsubset.sh
# Exit:    0 = the fallback behaved, 1 = something to look at, 2 = cannot test
#
set -u

die() { echo "error: $*" >&2; exit 2; }

case "$(uname -s)" in
  Linux) ;;
  *) die "Linux only - see the note above (this is $(uname -s))" ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# FPC names the target folder after CPU and OS, e.g. aarch64-linux
RUNNER="$(ls "$ROOT"/tests/bin/*-linux/test_runner 2>/dev/null | head -1)"
[ -x "$RUNNER" ] || die "no tests/bin/*-linux/test_runner - build it first"

# ---------------------------------------------------------------------------
# Stage 2: runs inside the mount namespace, with the library masked
# ---------------------------------------------------------------------------
if [ "${NO_HBSUBSET_INNER:-}" = 1 ]; then
  masked=0
  empty="$(mktemp)"
  for so in $NO_HBSUBSET_LIBS; do
    if mount --bind "$empty" "$so" 2>/dev/null; then
      masked=$((masked + 1))
    fi
  done
  if [ "$masked" = 0 ]; then
    echo "MASK-FAILED"
    exit 3
  fi
  echo "== masked $masked libharfbuzz-subset file(s) inside the namespace"
  echo
  echo "== test_runner WITHOUT libharfbuzz-subset"
  "$RUNNER" 2>&1
  exit $?
fi

# ---------------------------------------------------------------------------
# Stage 1: find the library, take a reference run, then re-enter masked
# ---------------------------------------------------------------------------
libs=""
for d in /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu /usr/lib64 \
         /usr/lib /lib/x86_64-linux-gnu /lib; do
  [ -d "$d" ] || continue
  for so in "$d"/libharfbuzz-subset.so*; do
    [ -e "$so" ] && libs="${libs:+$libs }$so"
  done
done

if [ -z "$libs" ]; then
  echo "libharfbuzz-subset is not installed on this machine."
  echo "That is the very state this script creates, so just run the suite:"
  echo
  "$RUNNER" 2>&1 | tail -3
  echo
  echo "If it is green, the fallback holds. To test the other direction,"
  echo "install the library and run this script again."
  exit 0
fi
echo "== found: $libs"
echo

subset_count() {
  sed -nE 's/.*Total failed: [0-9]+ \/ ([0-9]+) - Pdf subset tests.*/\1/p' | head -1
}

echo "== test_runner WITH libharfbuzz-subset (reference)"
ref="$("$RUNNER" 2>&1)"
ref_n="$(printf '%s' "$ref" | subset_count)"
ref_green=$(printf '%s' "$ref" | grep -c 'Total assertions failed for all test suits:  0 /' || true)
echo "   subset suite assertions: ${ref_n:-?}"
[ "$ref_green" = 1 ] || die "the suite is not green even WITH the library - fix that first"
echo

command -v unshare >/dev/null 2>&1 || die "unshare not found (package util-linux)"

export NO_HBSUBSET_INNER=1
export NO_HBSUBSET_LIBS="$libs"
out="$(unshare --mount --map-root-user "$0" 2>&1)"
rc=$?
unset NO_HBSUBSET_INNER NO_HBSUBSET_LIBS

if printf '%s' "$out" | grep -q MASK-FAILED; then
  die "could not bind-mount over the library inside the namespace.
  Your kernel may not allow unprivileged user namespaces. Check with:
    sysctl kernel.unprivileged_userns_clone
  Then either enable it, or run this script with sudo."
fi
if [ "$rc" != 0 ] && [ -z "$out" ]; then
  die "unshare failed (exit $rc) - unprivileged user namespaces may be disabled"
fi

echo "$out" | head -2
echo "$out" | tail -3
out_n="$(printf '%s' "$out" | subset_count)"
green=$(printf '%s' "$out" | grep -c 'Total assertions failed for all test suits:  0 /' || true)
echo
echo "   subset suite assertions: ${out_n:-?}  (reference: ${ref_n:-?})"

status=0
if [ "$green" != 1 ]; then
  echo "   RESULT: FAIL - the suite did not come out green without the library"
  status=1
elif [ -n "$ref_n" ] && [ "$out_n" = "$ref_n" ]; then
  echo "   RESULT: FAIL - the subset tests still ran in full, so the loader"
  echo "           reached libharfbuzz-subset anyway"
  status=1
else
  echo "   suite green, and the subset tests stood down as they should"
fi

echo
if [ "$status" = 0 ]; then
  echo "RESULT: the fallback holds."
  echo
  echo "Rebuild the demos and run them the same way to see the size difference -"
  echo "without the subsetter the whole face is embedded, so the PDFs grow a lot"
  echo "(chinese_demo is the clearest case, a CJK face being large):"
  echo
  echo "  NO_HBSUBSET_INNER=1 NO_HBSUBSET_LIBS='$libs' \\"
  echo "    unshare --mount --map-root-user <your-demo-binary>"
  echo
  echo "Still untested: a HarfBuzz OLDER than 2.9, which loads but lacks"
  echo "hb_subset_or_fail. That needs an old distribution, e.g. Debian 11."
else
  echo "RESULT: see the FAIL line above."
fi
exit "$status"
