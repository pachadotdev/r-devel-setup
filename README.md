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

## Create a diff for BugZilla

Example for https://bugs.r-project.org/show_bug.cgi?id=18693

```bash
svn diff trunk/src/nmath/rmultinom.c > rmultinom.patch
```
