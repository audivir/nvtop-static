#!/usr/bin/env bash
# Usage: ./build.sh [--jobs N] [--clean]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --jobs)
      JOBS="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GLIBC_VER=2.17

# terminal entries compiled into ncurses, used when the system terminfo database lacks them.
FALLBACKS=(
  ansi dumb linux vt100 vt220
  xterm xterm-256color xterm-color
  screen screen-256color screen.xterm-256color
  tmux tmux-256color
  rxvt rxvt-256color
  alacritty kitty foot wezterm
)
TERMINFO_DIRS_DEFAULT=/etc/terminfo:/lib/terminfo:/usr/share/terminfo:/usr/lib/terminfo:/usr/share/lib/terminfo

OS="$(uname -s)"
ARCH="$(uname -m)"
[ "$ARCH" = arm64 ] && ARCH=aarch64

WORK="$ROOT_DIR/build"
PREFIX="$WORK/deps"
HOST="$WORK/host"
DIST="$ROOT_DIR/dist"

# There is no fully static build: nvtop loads libnvidia-ml of the NVIDIA driver at runtime, which
# needs a dynamic libc, and musl hosts have no NVIDIA driver anyway.
case "$OS-$ARCH" in
  Linux-x86_64 | Linux-aarch64)
    ZIG_TARGET=$ARCH-linux-gnu.$GLIBC_VER
    GPUS=(-DNVIDIA_SUPPORT=ON -DAPPLE_SUPPORT=OFF)
    ;;
  Darwin-aarch64)
    ZIG_TARGET=native
    GPUS=(-DNVIDIA_SUPPORT=OFF -DAPPLE_SUPPORT=ON)
    ;;
  *)
    echo "unsupported host $OS-$ARCH" >&2
    exit 1
    ;;
esac
# the backends that need libdrm and libudev are left out, which are hard to link statically
GPUS+=(
  -DAMDGPU_SUPPORT=OFF -DINTEL_SUPPORT=OFF -DMSM_SUPPORT=OFF -DPANFROST_SUPPORT=OFF
  -DPANTHOR_SUPPORT=OFF -DV3D_SUPPORT=OFF -DASCEND_SUPPORT=OFF -DTPU_SUPPORT=OFF
  -DROCKCHIP_SUPPORT=OFF -DMETAX_SUPPORT=OFF -DENFLAME_SUPPORT=OFF
)

MAKE="${MAKE:-$(command -v gmake || command -v make)}"
"$MAKE" --version 2>/dev/null | grep -q 'GNU Make' || {
  echo "GNU make required" >&2
  exit 1
}
command -v cmake >/dev/null || {
  echo "cmake required" >&2
  exit 1
}

if [ "$ZIG_TARGET" = native ]; then
  export CC="zig cc" CXX="zig c++"
else
  export CC="zig cc -target $ZIG_TARGET" CXX="zig c++ -target $ZIG_TARGET"
fi
export AR="zig ar"
export RANLIB="zig ranlib"
[ "$OS" = Linux ] && export LD="zig ld.lld"

if [ "$CLEAN" = 1 ]; then
  echo ">>> cleaning $WORK and $DIST"
  rm -rf "$WORK" "$DIST"
fi
mkdir -p "$WORK/src" "$PREFIX/include" "$PREFIX/lib"

cd "$WORK/src"

prepare() {
  [ -d "$1" ] && return
  if [ ! -f "$ROOT_DIR/vendor/$1/.git" ] && [ ! -d "$ROOT_DIR/vendor/$1/.git" ]; then
    echo "vendor/$1 is missing, run: git submodule update --init --depth 1" >&2
    exit 1
  fi
  echo ">>> preparing $1 ($(git -C "$ROOT_DIR/vendor/$1" describe --tags 2>/dev/null || echo unknown))"
  cp -R "$ROOT_DIR/vendor/$1" "$1"
  rm -rf "$1/.git"
}

prepare ncurses
prepare nvtop

NCURSES_COMMON=(
  --without-shared --with-normal --without-debug
  --without-cxx --without-cxx-binding --without-ada
  --without-tests --without-manpages
  --enable-widec --disable-db-install
)

# builds tic and infocmp for the build machine to compile the fallback entries.
if [ ! -x "$HOST/bin/infocmp" ]; then
  echo ">>> ncurses (host tic/infocmp)"
  rm -rf ncurses-host
  cp -R ncurses ncurses-host
  (
    cd ncurses-host
    ./configure --prefix="$HOST" "${NCURSES_COMMON[@]}" --with-progs
    "$MAKE" -j"$JOBS"
    "$MAKE" install.progs
  )
fi

echo ">>> ncurses"
(
  cd ncurses
  [ -f Makefile ] && "$MAKE" distclean >/dev/null 2>&1 || true
  # the terminfo functions stay in libncursesw, as CMake finds a single curses library
  ./configure \
    --prefix="$PREFIX" \
    "${NCURSES_COMMON[@]}" \
    --without-progs \
    --with-default-terminfo-dir=/usr/share/terminfo \
    --with-terminfo-dirs="$TERMINFO_DIRS_DEFAULT" \
    --with-fallbacks="$(
      IFS=,
      echo "${FALLBACKS[*]}"
    )" \
    --with-tic-path="$HOST/bin/tic" \
    --with-infocmp-path="$HOST/bin/infocmp"
  "$MAKE" -j"$JOBS" libs
  "$MAKE" install.libs
)

echo ">>> nvtop"
(
  cd nvtop
  rm -rf build
  cmake -S . -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCURSES_INCLUDE_PATH="$PREFIX/include;$PREFIX/include/ncursesw" \
    -DCURSES_LIBRARY="$PREFIX/lib/libncursesw.a" \
    -DCURSES_CURSES_LIBRARY="$PREFIX/lib/libncursesw.a" \
    -DCURSES_NCURSES_LIBRARY="$PREFIX/lib/libncursesw.a" \
    -DCMAKE_C_FLAGS="-Os -DNCURSES_STATIC -I$PREFIX/include/ncursesw -I$PREFIX/include" \
    -DCMAKE_EXE_LINKER_FLAGS="-s" \
    "${GPUS[@]}"
  cmake --build build -j"$JOBS"
  rm -rf "$DIST"
  mkdir -p "$DIST/bin" "$DIST/share/man/man1"
  cp build/src/nvtop "$DIST/bin/nvtop"
  cp build/manpage/nvtop "$DIST/share/man/man1/nvtop.1"
)

NVTOP_BIN="$DIST/bin/nvtop"
echo
echo ">>> done: $NVTOP_BIN"
"$NVTOP_BIN" --version
if [ "$OS" = Linux ]; then
  if LC_ALL=C grep -a -q -E 'lib(ncurses|tinfo)[a-z]*\.so' "$NVTOP_BIN"; then
    echo "WARNING: nvtop links a dependency dynamically, not only glibc" >&2
  else
    echo "only glibc is dynamic"
  fi
else
  otool -L "$NVTOP_BIN"
  # only the system may supply libraries, not Homebrew or /usr/local
  if otool -L "$NVTOP_BIN" | tail -n +2 | grep -q -v -E '^[[:space:]]+(/usr/lib/|/System/)'; then
    echo "ERROR: nvtop links a library that is not part of macOS" >&2
    exit 1
  fi
fi
