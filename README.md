# Building R-devel - R Sprint 2026

Here is how I build R-devel with optional steps to use [Clang](https://www.stats.ox.ac.uk/pub/bdr/clang23/README.txt) because
CRAN also uses a highly modern Clang compiler for additional testing.

The step to create a patch was suggested by [Ivan Krylov](https://bugs.r-project.org/show_bug.cgi?id=18693).

## Build R-devel

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

## Create a diff for BugZilla

Example for https://bugs.r-project.org/show_bug.cgi?id=18693

```bash
svn diff trunk/src/nmath/rmultinom.c > rmultinom.patch
```
