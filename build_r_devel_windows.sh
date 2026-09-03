#!/bin/bash
#
# Adaptation of build_r_devel.sh for Windows, meant to be run inside the
# "Rtools45 Bash" shell (or any shell with C:\rtools45\usr\bin and the
# compiler bin directory on PATH).
#
# Unlike the Linux script, R on Windows is built in-place inside the SVN
# working copy using `make all recommended` (there is no `./configure` /
# `make install` step, no sudo, and no package-manager dependency install:
# Rtools45 already ships the full toolchain CRAN uses on Windows).
#
# This script mirrors the Linux workflow as closely as it can:
#   1. checkout/update R-devel sources via SVN
#   2. optionally apply a patch (to test a fix before submitting to BugZilla)
#   3. fetch recommended packages
#   4. build with `make all recommended`
#   5. optionally build the Windows installer (`make distribution`)

set -euo pipefail

# Parse command-line arguments
PATCH_FILE=""
JOBS=""
BUILD_INSTALLER="no"
SKIP_UPDATE="no"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --patch=*)
      PATCH_FILE="${1#*=}"
      shift
      ;;
    --jobs=*)
      JOBS="${1#*=}"
      shift
      ;;
    --installer=*)
      BUILD_INSTALLER="${1#*=}"
      shift
      ;;
    --skip-update=*)
      SKIP_UPDATE="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash build_r_devel_windows.sh [--patch=/path/to/file.patch] [--jobs=N] [--installer=yes] [--skip-update=yes]"
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R_SOURCE_DIR="${SCRIPT_DIR}/trunk"

# Sanity checks: this script must run inside an Rtools45 shell
if ! command -v make &>/dev/null; then
  echo "ERROR: 'make' was not found on PATH."
  echo "Run this script from the 'Rtools45 Bash' shell (see README.md)."
  exit 1
fi

if ! command -v svn &>/dev/null; then
  echo "ERROR: 'svn' was not found on PATH."
  echo "Install an SVN client (e.g. via Rtools45 or a standalone SVN for Windows)."
  exit 1
fi

if [[ "${SKIP_UPDATE}" != "yes" ]]; then
  if [ ! -d "${R_SOURCE_DIR}" ]; then
    echo "==============================="
    echo "Downloading R-devel from SVN"
    echo "==============================="
    svn checkout https://svn.r-project.org/R/trunk/ "${R_SOURCE_DIR}"
  else
    echo "==============================="
    echo "Updating R source code from SVN"
    echo "==============================="
    cd "${R_SOURCE_DIR}"
    svn update
    cd "${SCRIPT_DIR}"
  fi
else
  echo "Skipping SVN checkout/update (--skip-update=yes)"
fi

# Optionally apply a patch to test local changes before submitting to BugZilla
if [[ -n "${PATCH_FILE}" ]]; then
  echo "==============================="
  echo "Applying patch: ${PATCH_FILE}"
  echo "==============================="
  cd "${R_SOURCE_DIR}"
  if svn patch "${PATCH_FILE}" 2>/dev/null; then
    echo "Patch applied with 'svn patch'."
  else
    echo "'svn patch' failed or is unavailable, falling back to 'patch -p0'..."
    patch -p0 < "${PATCH_FILE}"
  fi
  cd "${SCRIPT_DIR}"
fi

echo "==============================="
echo "Fetching recommended packages"
echo "==============================="
cd "${R_SOURCE_DIR}"
./tools/rsync-recommended 2>/dev/null || ./tools/fetch-recommended 2>/dev/null || true

echo "==============================="
echo "Building R-devel from source (in-place, no configure/install step)"
echo "Source directory: ${R_SOURCE_DIR}"
echo "==============================="

if [[ -n "${JOBS}" ]]; then
  make -j"${JOBS}" all recommended
else
  make all recommended
fi

# Verify installation
if [ -x "${R_SOURCE_DIR}/bin/x64/Rterm.exe" ]; then
  echo "==============================="
  echo "R-devel built successfully!"
  echo "R version:"
  "${R_SOURCE_DIR}/bin/x64/Rterm.exe" --version | head -n 1
  echo "Run it with: ${R_SOURCE_DIR}/bin/x64/Rterm.exe (or bin/x64/Rgui.exe)"
  echo "==============================="
else
  echo "ERROR: R-devel build failed (bin/x64/Rterm.exe not found)"
  exit 1
fi

# Optionally build the Windows installer (requires Inno Setup)
if [[ "${BUILD_INSTALLER}" == "yes" ]]; then
  echo "==============================="
  echo "Building Windows installer (make distribution)"
  echo "==============================="
  make distribution
  echo "Installer created at ${R_SOURCE_DIR}/installer/R-devel-win.exe"
fi
