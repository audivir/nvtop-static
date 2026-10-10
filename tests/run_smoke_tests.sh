#!/usr/bin/env bash
# Usage: ./tests/run_smoke_tests.sh [--dist DIR]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT_DIR/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dist)
      DIST="$(cd "$2" && pwd)"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

NVTOP="$DIST/bin/nvtop"

pass() { echo "ok: $*"; }
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

version="$("$NVTOP" --version)"
echo "$version" | grep -q '^nvtop version ' || fail "nvtop --version: $version"
pass "$version"

"$NVTOP" --help | grep -q -i 'usage' || fail "nvtop --help"
pass "usage"

# runners have no GPU, where nvtop draws nothing but says so and exits, which also shows that
# ncurses starts up with the entries compiled in
if [ "$(uname -s)" = Linux ]; then
  out="$(TERM=xterm-256color TERMINFO=/nonexistent TERMINFO_DIRS=/nonexistent "$NVTOP" 2>&1 </dev/null || true)"
  echo "$out" | grep -q 'No GPU to monitor' || fail "nvtop without a GPU: $out"
  pass "no GPU message"

  max="$(LC_ALL=C grep -aoh 'GLIBC_2\.[0-9]*' "$NVTOP" | sort -uV | tail -n 1)" || true
  if [ -n "$max" ]; then
    [ "$(printf '%s\n' "$max" GLIBC_2.17 | sort -V | tail -n 1)" = GLIBC_2.17 ] \
      || fail "needs $max, newer than GLIBC_2.17"
    pass "glibc floor ($max)"
  fi
fi

echo "all smoke tests passed"
