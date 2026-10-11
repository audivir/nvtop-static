# nvtop-static

Portable builds of [nvtop](https://github.com/Syllo/nvtop), a task monitor for GPUs, with ncurses
linked in statically, built with [zig](https://ziglang.org) as the C toolchain.

- Linux glibc: only glibc is linked dynamically, and only symbols up to glibc 2.17, so the
  binaries run on anything from CentOS 7 onwards
- macOS: only libSystem and the system frameworks are dynamic

Supported GPUs: NVIDIA on Linux, which nvtop reaches by loading `libnvidia-ml.so` of the driver
at runtime, and Apple silicon on macOS. The backends that need libdrm and libudev (AMD, Intel,
Adreno, Mali, Raspberry Pi) are left out, as are TPUs and NPUs; use the nvtop of your
distribution for those. There is no musl build, which could not load the library of the driver.

Common terminal descriptions (xterm, xterm-256color, screen, screen-256color, tmux, tmux-256color,
linux, vt100, vt220, rxvt, alacritty, kitty, foot, wezterm, ...) are compiled into ncurses, so
nvtop works even on systems without a terminfo database. The system database is still used
first, from `/etc/terminfo`, `/lib/terminfo`, `/usr/share/terminfo`, and `/usr/lib/terminfo`, or
from `$TERMINFO`, `$TERMINFO_DIRS`, and `~/.terminfo`.

## Prerequisites

- `zig`, GNU make (the `make` 3.81 of macOS is enough), `cmake`, `perl`, `git`
- On macOS: Xcode Command Line Tools (SDK)

## Installation

Clone the repo with submodules (shallow, the history of the vendored projects is not needed):

```shell
git clone --recurse-submodules --shallow-submodules https://github.com/zshsetup/nvtop-static
cd nvtop-static
```

## Usage

```shell
./build.sh
```

This builds ncurses from `vendor/` as static libraries, then builds nvtop against them. Output is
installed under `dist/`:

- `dist/bin/nvtop`: the binary; copy it anywhere on your `PATH`
- `dist/share/man/man1/nvtop.1`: the man page

Pass `--clean` to remove previous build output first, and `--jobs N` to control parallelism.

To run the smoke tests against the build:

```shell
./tests/run_smoke_tests.sh
```

## Releases

Publishing a GitHub release tagged with the nvtop version (e.g. `3.3.2`, matching the tag checked
out in `vendor/nvtop`) builds and attaches `nvtop-static-<platform>.tar.gz` for `macos-arm64`,
`linux-amd64`, and `linux-arm64`, together with the sources they were built from
(`nvtop-static-sources.tar.gz`).

To update a vendored project, check out a new release tag in its submodule and commit it, e.g.
`git -C vendor/nvtop fetch --depth 1 origin tag 3.3.3 && git -C vendor/nvtop checkout 3.3.3`.

## Acknowledgments

This repository builds and vendors the following upstream projects, unmodified, as git
submodules under `vendor/`. Credit goes to their respective authors:

- [nvtop](https://github.com/Syllo/nvtop) by Maxime Schmitt and contributors
- [ncurses](https://invisible-island.net/ncurses/) by Thomas E. Dickey and the Free Software
  Foundation

## License

MIT for the code in this repository. See `NOTICE` for the licenses of the upstream projects and the
resulting binaries, which are GPL-3.0-or-later (nvtop).
