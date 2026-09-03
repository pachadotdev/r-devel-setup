# Building R-devel - R Sprint 2026

Here is how I build R-devel with optional steps to use [Clang](https://www.stats.ox.ac.uk/pub/bdr/clang23/README.txt) because
CRAN also uses a highly modern Clang compiler for additional testing.

The step to create a patch was suggested by [Ivan Krylov](https://bugs.r-project.org/show_bug.cgi?id=18693).

## Build R-devel on Linux

Default setup

```bash
bash build_r_devel.sh
```

If you wish to use Clang instead of GCC, run

```bash
bash build_r_devel.sh --clang="yes"
```

If you wish to use the development Clang compiler that CRAN uses, run

```bash
bash build_r_devel.sh --clang="yes" --clang-devel="yes"
```

After installing I see this:

```bash
R CMD config CC
# /opt/llvm-23.1.0/bin/clang -std=C23

R CMD config CC
# /opt/llvm-23.1.0/bin/clang -std=c++20

Rscript -e "tinydev::check_cpp_compiler()"
# using C++ compiler: ‘clang version 23.1.0 (https://github.com/llvm/llvm-project.git ea7d852a70e8bdfaf601d6626a760f9771b2c4b4)’
# /opt/llvm-23.1.0/bin/clang++ -std=c++20
```

## Build R-devel on Windows

`build_r_devel.sh` is written for Linux (it uses `apt-get`/`dnf`/`pacman`, `sudo`,
`make install`, symlinks in `/usr/local/bin`, etc.), so it cannot be run as-is on
Windows. Instead, use `build_r_devel_windows.sh`, an adaptation of the Linux
script for the [Rtools45](https://cran.r-project.org/bin/windows/Rtools/)
toolchain that automates the process described in the official CRAN guide,
[*Howto: Building R-devel and packages on Windows*](https://cran.r-project.org/bin/windows/base/howto-R-devel.html).
This is what I use to test a patch against R-devel on Windows.

Follow these steps in order.

### 1. Install Rtools45

Download and install [Rtools45](https://cran.r-project.org/bin/windows/Rtools/) from CRAN,
keeping the default installation path `C:\rtools45`. Rtools45 provides:

- The compiler toolchains (GCC for Intel/AMD64, LLVM for ARM64).
- An MSYS2-based Unix-like shell and build tools (`make`, `rsync`, etc.).
- Precompiled static libraries used by most CRAN packages.
- QPDF and other auxiliary tools.

No manual configuration of `Makeconf` or environment variables is normally
needed if you install Rtools45 at its default location.

> Rtools45 targets Windows 10 and newer; it will not work on older Windows
> versions.

Optional extra tools:

- **MikTeX** — only needed if you want to build the R manuals/vignettes (PDF docs).
- **Inno Setup** — only needed if you want to build the Windows installer (`make distribution`).

### 2. Open the Rtools45 shell

Use the "Rtools45 Bash" shell (or a terminal with `C:\rtools45\usr\bin` and the
compiler `bin` directory on `PATH`) for all the steps below, instead of Git Bash
or WSL. `build_r_devel_windows.sh` checks for `make` and `svn` on `PATH` and
exits early with an explanatory error if it is not run from a compatible shell.

From this shell, sync and fully upgrade the MSYS2 package set before doing
anything else:

```bash
pacman -Syu
```

MSYS2 may ask you to close and reopen the terminal partway through (it
sometimes needs to restart itself to finish updating core packages). If so,
close the window, reopen "Rtools45 Bash", and run `pacman -Syu` again until
it reports nothing left to do.

### 3. Install an SVN client

`build_r_devel_windows.sh` checks out/updates the R-devel sources via SVN,
just like `build_r_devel.sh` does on Linux, so you need `svn` on `PATH`.
Install it via `pacman`:

```bash
pacman -S --needed wget subversion
```

#### Troubleshooting: SQLite version mismatch

If you see this error the first time you run `build_r_devel_windows.sh`:

```
svn: E200029: Couldn't perform atomic initialization
svn: E200030: SQLite compiled for 3.52.0, but running with 3.51.2
```

it means MSYS2's `subversion` package (linked against a specific `sqlite`
version) and the separate `sqlite` package have drifted out of sync — `svn`
refuses to run rather than risk corrupting its working-copy database. Making
sure you have done a **full** `pacman -Syu` (step 2) before installing
`subversion`, so both packages come from the same consistent snapshot, is
the fix that reliably resolves this:

```bash
pacman -Syu
pacman -S --needed subversion sqlite
```

If it still doesn't resolve, force a clean re-download of both packages:

```bash
pacman -Sc                       # clear the package cache
pacman -Sy                       # refresh the package database
pacman -S --needed --overwrite '*' sqlite subversion
```

You can double check what `svn` is actually linked against with:

```bash
which svn
ldd "$(which svn)" | grep -i sqlite
pacman -Qi sqlite subversion
sqlite3 -version
```

(Note that Windows' `where` command only searches the Windows `PATH`, not
the MSYS2/Rtools45 shell's `PATH`, so `where sqlite3.dll` reporting nothing
does **not** mean there is no conflicting DLL — use the MSYS2 tools above
instead.)

### 4. Run build_r_devel_windows.sh

Default setup (checks out/updates `trunk` next to the script via SVN, fetches
recommended packages, then runs `make all recommended`):

```bash
bash build_r_devel_windows.sh
```

If you want to test a patch/local change against R-devel before building
(analogous to the `svn diff` step in this repo, see below), pass it with
`--patch`. The script tries `svn patch` first and falls back to `patch -p0`:

```bash
bash build_r_devel_windows.sh --patch=/path/to/your.patch
```

Other optional flags:

```bash
# Parallel build (replace N with the number of jobs)
bash build_r_devel_windows.sh --jobs=N

# Also build the Windows installer (requires Inno Setup)
bash build_r_devel_windows.sh --installer="yes"

# Skip the SVN checkout/update step (e.g. to rebuild after only editing a
# previously-applied patch by hand)
bash build_r_devel_windows.sh --skip-update="yes"
```

Flags can be combined, e.g. to update, apply a patch, and build in parallel:

```bash
bash build_r_devel_windows.sh --patch=/path/to/your.patch --jobs=4
```

Unlike the Linux script, there is no `configure` step and no `sudo make install`:
on Windows, R is built in place inside the `trunk` source tree and run directly
from `trunk/bin/x64/Rterm.exe` (or `trunk/bin/x64/Rgui.exe`), which the script
prints on success, for example:

```bash
trunk/bin/x64/Rterm.exe --version
```

If you built the installer (`--installer="yes"`), it will be created at
`trunk/installer/R-devel-win.exe`.

### Troubleshooting: `svn: E155007: None of the targets are working copies`

This happens on a *second* run of `build_r_devel_windows.sh`, right after a
previous run failed during the checkout step (for example because of the
SQLite mismatch above). The script sees that a `trunk` directory already
exists next to it and therefore tries `svn update` instead of a fresh
`svn checkout` — but since the first checkout never completed, `trunk`
exists on disk without valid SVN metadata (no `.svn` folder), so it is not a
real working copy and `svn update` fails with:

```
Skipped '.'
svn: E155007: None of the targets are working copies
```

To fix it, remove the incomplete `trunk` directory so the script performs a
full `svn checkout` again on the next run:

```bash
rm -rf trunk
bash build_r_devel_windows.sh --patch=/path/to/your.patch
```

(Only do this if `trunk` does not contain uncommitted work you care about —
it is just the checked-out R sources, so it is always safe to delete and
re-checkout from SVN.) If you had already applied a patch by hand and only
want to rebuild without redoing the checkout, use `--skip-update="yes"`
instead of deleting `trunk` — but that flag assumes `trunk` is already a
valid, up-to-date working copy.

### Notes / differences from the Linux script

- Most libraries needed by CRAN packages already ship with Rtools45, so the
  package-manager install steps (`apt-get`, `dnf`, `pacman`) in
  `build_r_devel.sh` are not applicable on Windows.
- There is no equivalent `--clang`/`--clang-devel` toggle for Windows in
  `build_r_devel_windows.sh` — Rtools45 already ships the compiler toolchain
  CRAN uses to check packages on Windows (GCC for Intel/AMD64, LLVM for
  ARM64), so no `config.site` overrides are required.
- There is no install prefix/symlink step (`/opt/R-devel`, `/usr/local/bin/R`);
  you use the built binaries directly from the source tree, or the installer
  produced with `--installer="yes"`.
- If you prefer to drive the steps manually instead of using the script, you
  can still follow the official CRAN guide directly: check out sources with
  `svn checkout https://svn.r-project.org/R/trunk R-devel` (or the read-only
  [Git mirror](https://github.com/wch/r-source.git)), apply your patch with
  `svn patch` or `patch -p0`, then run `make all recommended` from the source
  root.

## Create a diff for BugZilla

Example for https://bugs.r-project.org/show_bug.cgi?id=18693

```bash
svn diff trunk/src/nmath/rmultinom.c > rmultinom.patch
```
