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

To test a suggested patch run:

```bash
bash build_r_devel.sh --patch=/path/to/your.patch
```

## Build R-devel on Windows

I found diverging answers on Google. Here is a "curious" mashup of Google and Copilot answers that I edited to get a working setup.

`build_r_devel_windows.sh` is an adaptation of the Linux script for the [Rtools45](https://cran.r-project.org/bin/windows/Rtools/)
toolchain that automates the process described in the official CRAN guide,
[*Howto: Building R-devel and packages on Windows*](https://cran.r-project.org/bin/windows/base/howto-R-devel.html).

This is what I use to test a patch against R-devel on Windows.

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

You also need an SVN client on `PATH` (`svn`), since `build_r_devel_windows.sh`
checks out/updates the R-devel sources via SVN, just like `build_r_devel.sh`
does on Linux. **Before installing it, sync the full package database and
upgrade the whole system first** (not just `subversion`), so that `svn` and
the `sqlite3` library it links against come from the same, consistent set of
packages — installing `subversion` on top of a stale package database is the
main cause of the SQLite version-mismatch error described below:

```bash
pacman -Syu
```

MSYS2 may ask you to close and reopen the terminal partway through (it
sometimes needs to restart itself to finish updating core packages). If so,
close the window, reopen "Rtools45 Bash", and run `pacman -Syu` again until
it reports nothing left to do. Only then install `wget` and `subversion`:

```bash
pacman -S --needed wget subversion
```

### 2. Install Tcl/Tk (needed for the `tcltk` base package)

R's `tcltk` package requires the Tcl/Tk headers and DLLs to compile, but
**Rtools45 does not bundle these for building R itself** (this is different
from Rtools' bundled static libraries used when building *other* CRAN
packages). If you skip this step, `make all`/`make all recommended` will
fail while compiling `tcltk` with:

```
fatal error: tcl.h: No such file or directory
```

To install it:

1. Open the official CRAN guide,
   [*Howto: Building R-devel and packages on Windows*](https://cran.r-project.org/bin/windows/base/howto-R-devel.html),
   and find its **"Tcl/Tk"** section. It links to the current pre-built
   Tcl/Tk bundle for Windows (a `.zip` hosted under
   `https://cran.r-project.org/bin/windows/Rtools/`). **Always get the URL
   from that page rather than reusing an old link/filename from here** — the
   exact filename changes between R/Rtools releases, and hardcoding a
   specific version in this README would go stale.
2. Download that zip and extract it so its contents end up at
   `trunk/Tcl` (i.e. a sibling of `trunk/src`, `trunk/COPYING`, etc. — **not**
   inside `src` or `src/gnuwin32`). After extracting, you should have:

   ```bash
   ls trunk/Tcl/include/tcl.h   # must exist
   ls trunk/Tcl/bin             # should contain the Tcl/Tk DLLs
   ```

   If your zip extracts into a subfolder instead of directly giving you
   `include`/`bin`/`lib`, move those subfolders up so they sit directly
   under `trunk/Tcl`.
3. No extra flags are needed after this — `build_r_devel_windows.sh` and the
   R build system look for Tcl/Tk at `trunk/Tcl` (the `TCL_HOME` variable
   used in `etc/x64/Makeconf` and `src/library/tcltk/src/Makefile.win`
   defaults to `R_HOME/Tcl`, i.e. `trunk/Tcl`) automatically. Just re-run:

   ```bash
   bash build_r_devel_windows.sh --skip-update="yes"
   ```

If you don't care about the `tcltk` package for what you're testing (e.g. an
unrelated patch to `src/gnuwin32/shext.c`), you can skip installing Tcl/Tk
entirely and instead build without `tcltk` — see the
"Troubleshooting" section below.

### 3. Open the Rtools45 shell

Use the "Rtools45 Bash" shell for all the steps below, instead of Git Bash
or WSL. `build_r_devel_windows.sh` checks for `make` and `svn` on `PATH` and
exits early with an explanatory error if it is not run from a compatible shell.

### 4. Run build_r_devel_windows.sh

Default setup (checks out/updates `trunk` next to the script via SVN, fetches
recommended packages, then runs `make all recommended`):

```bash
bash build_r_devel_windows.sh
```

To test a patch:

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

### Troubleshooting

#### `svn` fails with "Couldn't perform atomic initialization" / SQLite version mismatch

If `build_r_devel_windows.sh` fails during the SVN checkout/update step with:

```
svn: E200029: Couldn't perform atomic initialization
svn: E200030: SQLite compiled for 3.52.0, but running with 3.51.2
```

this means the `svn` binary was linked against one version of the SQLite
library, but MSYS2/Rtools45 has a different, ABI-incompatible version of
`sqlite3` installed (or on `PATH`) at runtime. `svn` refuses to run rather
than risk corrupting its working-copy metadata database. This is normally
caused by installing/updating `subversion` without first syncing and
upgrading the *whole* MSYS2 package set (see step 1 above), leaving `svn` and
`sqlite3` out of sync.

Note that Windows' `where` command only searches the Windows `PATH`, not the
MSYS2/Rtools45 shell's `PATH`, so `where sqlite3.dll` reporting nothing is
expected and does **not** mean there is no conflicting DLL — use the MSYS2
tools below instead. To fix the mismatch:

1. **Sync and fully upgrade the MSYS2 package set, then restart the shell.**
   This is the fix in almost all cases, since it brings `subversion` and its
   `sqlite3` dependency back in sync:

   ```bash
   pacman -Syu
   ```

   If asked to close and reopen the terminal partway through, do so, reopen
   "Rtools45 Bash", and run `pacman -Syu` again until it reports nothing left
   to do.

2. **Explicitly reinstall `subversion` and `sqlite3`** so their versions are
   guaranteed to be back in sync (useful if `pacman -Syu` reported nothing to
   do, but the error persists):

   ```bash
   pacman -S --needed subversion sqlite3
   ```

3. **Re-run the build script:**

   ```bash
   bash build_r_devel_windows.sh --patch=/path/to/your.patch
   ```

4. **If the error still persists**, confirm which `svn` is being used and
   which `sqlite3` library it is actually linked against (from inside the
   Rtools45/MSYS2 shell — `where.exe` won't show this):

   ```bash
   which svn
   ldd "$(which svn)" | grep -i sqlite
   pacman -Qi sqlite3 subversion
   ```

   If `ldd` points to a `sqlite3.dll` outside `/usr/bin` (e.g. from an
   unrelated MSYS2/MinGW install, or a Python/Anaconda environment earlier on
   `PATH`), remove that installation from `PATH` or rename/remove the
   conflicting DLL, then reopen the shell and try again.

5. **As a last resort**, delete and reinstall Rtools45 to get a clean,
   internally-consistent set of packages.

#### `svn: E155007: None of the targets are working copies`

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

#### `fatal error: tcl.h: No such file or directory` while compiling the `tcltk` package

If the build gets past `Rpwd.exe` and the base packages, but fails while
compiling the `tcltk` package (`src/library/tcltk/src/init.c` or similar)
with:

```
tcltk.h:25:10: fatal error: tcl.h: No such file or directory
   25 | #include <tcl.h>
      |          ^~~~~~~
compilation terminated.
make[4]: *** [../../../../etc/x64/Makeconf:297: init.o] Error 1
```

this means step 2 above (installing Tcl/Tk) was skipped, or the bundle
wasn't extracted to the right place. Fix by either:

1. **Doing step 2** — download the Tcl/Tk bundle linked from the "Tcl/Tk"
   section of the
   [official CRAN Windows build guide](https://cran.r-project.org/bin/windows/base/howto-R-devel.html)
   and extract it to `trunk/Tcl`, then confirm `trunk/Tcl/include/tcl.h`
   exists before re-running the build.

2. **Skipping `tcltk` entirely**, if you only need to test an unrelated
   patch (like a change to `src/gnuwin32/shext.c`) and don't care about the
   `tcltk` package being built. Check `src/gnuwin32/Makefile.win`/`MkRules`
   in your checkout for the flag that gates it (naming has changed across R
   versions — look for something like `MAKE_TCLTK`/`USE_TCLTK`), or simply
   remove `tcltk` from `R_PKGS_BASE` in `share/make/vars.mk` for a one-off
   local build. This avoids needing the Tcl/Tk dependency at all when it
   isn't relevant to what you're testing.

### Notes / differences from the Linux script

- Most libraries needed by CRAN packages already ship with Rtools45, so the
  package-manager install steps (`apt-get`, `dnf`, `pacman`) in
  `build_r_devel.sh` are not applicable on Windows. Tcl/Tk (needed only for
  the `tcltk` base package) is the one exception — see step 2 above.
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
