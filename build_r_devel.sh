#!/bin/bash

set -euo pipefail

# Parse command-line arguments
CLANG_DEVEL="no"
CLANG="no"
BUILD_DIR_OVERRIDE=""
PATCH_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clang-devel=*)
      CLANG_DEVEL="${1#*=}"
      shift
      ;;
    --clang=*)
      CLANG="${1#*=}"
      shift
      ;;
    --build-dir=*)
      BUILD_DIR_OVERRIDE="${1#*=}"
      shift
      ;;
    --patch=*)
      PATCH_FILE="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Configuration
R_DEVEL_PREFIX="/opt/R-devel"
CLANG_README_URL="https://ox.ac.uk"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

R_SOURCE_DIR="${SCRIPT_DIR}/trunk"
# Build out-of-source (sibling of trunk, so the SVN working copy stays clean)
# so multiple independent builds can share the same checked-out source.
R_BUILD_DIR="${BUILD_DIR_OVERRIDE:-${SCRIPT_DIR}/build}"

# Detect Linux distribution
detect_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "$ID"
  elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]'
  else
    echo "unknown"
  fi
}

DISTRO=$(detect_distro)

# Optional: Install the devel version of the Clang compiler
if [[ "$CLANG_DEVEL" == "yes" ]]; then
  echo "Detecting Clang version from ${CLANG_README_URL}..."
  CLANG_VER="23.1.0"
  echo "Detected Clang version: ${CLANG_VER}"
  CLANG_INSTALL_PATH="/opt/llvm-${CLANG_VER}"
  if [ ! -d "$CLANG_INSTALL_PATH" ]; then
    echo "==============================="
    echo "Installing LLVM/Clang devel"
    echo "Version: $CLANG_VER"
    echo "Detected distro: $DISTRO"
    echo "==============================="
    
    case "$DISTRO" in
      arch|manjaro)
        command -v ld.lld   &>/dev/null || sudo pacman -S --noconfirm lld
        command -v flang    &>/dev/null || pamac build --no-confirm flang
        command -v gfortran &>/dev/null || sudo pacman -S --noconfirm gcc-fortran
        ;;
      debian|ubuntu)
        # Run apt-get update only if at least one package is missing
        if ! command -v clang   &>/dev/null || ! command -v ld.lld  &>/dev/null || \
           ! command -v llvm-ar &>/dev/null || ! command -v gfortran &>/dev/null; then
          sudo apt-get update
        fi
        command -v clang    &>/dev/null || sudo apt-get install -y clang
        command -v ld.lld   &>/dev/null || sudo apt-get install -y lld
        command -v llvm-ar  &>/dev/null || sudo apt-get install -y llvm
        command -v gfortran &>/dev/null || sudo apt-get install -y gfortran
        ;;
      fedora|rhel|centos)
        command -v clang    &>/dev/null || sudo dnf install -y clang
        command -v ld.lld   &>/dev/null || sudo dnf install -y lld
        command -v llvm-ar  &>/dev/null || sudo dnf install -y llvm-tools
        command -v gfortran &>/dev/null || sudo dnf install -y gcc-gfortran
        ;;
      *)
        echo "WARNING: Unknown distro '$DISTRO'. Skipping dependency installation."
        echo "Please install: clang, lld, llvm, gfortran"
        ;;
    esac
    
    git clone --depth 1 https://github.com
    cd llvm-project
    git fetch origin tag llvmorg-${CLANG_VER} && git checkout llvmorg-${CLANG_VER} && git rev-parse --short HEAD
    cmake -S llvm -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${CLANG_INSTALL_PATH} -DLLVM_ENABLE_PROJECTS="clang;lld" -DLLVM_TARGETS_TO_BUILD="X86"
    ninja -C build
    sudo ninja -C build install
    cd ..
  else
    echo "==============================="
    echo "LLVM/Clang devel already installed at ${CLANG_INSTALL_PATH}"
    echo "==============================="
  fi
fi

if [ ! -d "trunk" ]; then
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
  cd ..
fi

# Clean stale build artifacts
if [ -f "${R_SOURCE_DIR}/Makefile" ] || \
   [ -n "$(find "${R_SOURCE_DIR}/src" -name '*.d' -o -name '*.o' -o -name '*.a' 2>/dev/null | head -n 1)" ]; then
  echo "==============================="
  echo "Cleaning stale in-source build artifacts from ${R_SOURCE_DIR}"
  echo "==============================="
  if [ -f "${R_SOURCE_DIR}/Makefile" ]; then
    (cd "${R_SOURCE_DIR}" && make distclean >/dev/null 2>&1) || true
  fi
  find "${R_SOURCE_DIR}/src" \
    \( -name '*.d' -o -name '*.o' -o -name '*.a' -o -name '*.lo' -o -name '*.la' \
       -o -name 'Makedeps' -o -name 'stamp-lo' \) -delete 2>/dev/null || true
  rm -f "${R_SOURCE_DIR}/Makefile" "${R_SOURCE_DIR}/Makeconf" \
        "${R_SOURCE_DIR}/config.status" "${R_SOURCE_DIR}/config.log"
fi

# Wipe out past out-of-source build steps to force full configuration pick up
rm -rf "${R_BUILD_DIR}"

# Apply patch if provided
if [ -n "$PATCH_FILE" ]; then
  if [ ! -f "$PATCH_FILE" ]; then
    echo "ERROR: Patch file not found: $PATCH_FILE"
    exit 1
  fi
  
  echo "==============================="
  echo "Applying patch: $PATCH_FILE"
  echo "==============================="
  cd "${R_SOURCE_DIR}"
  
  # Try svn patch first, fall back to patch -p0
  if command -v svn &>/dev/null; then
    if svn patch "$PATCH_FILE" 2>/dev/null; then
      echo "Patch applied successfully with svn patch"
    else
      echo "svn patch failed, trying patch -p0..."
      if patch -p0 < "$PATCH_FILE"; then
        echo "Patch applied successfully with patch -p0"
      else
        echo "ERROR: Failed to apply patch"
        exit 1
      fi
    fi
  else
    if patch -p0 < "$PATCH_FILE"; then
      echo "Patch applied successfully with patch -p0"
    else
      echo "ERROR: Failed to apply patch"
      exit 1
    fi
  fi
  
  cd ..
fi

echo "==============================="
echo "Fetching recommended packages"
echo "==============================="
"${R_SOURCE_DIR}/tools/fetch-recommended"

# Configure R's build and package-install toolchain
CONFIG_SITE="${R_SOURCE_DIR}/config.site"
CONFIG_MARKER="build_r_devel.sh compiler settings"

sed -i "/^# BEGIN ${CONFIG_MARKER}$/,/^# END ${CONFIG_MARKER}$/d" "${CONFIG_SITE}"

# STRICT PURE CLANG ENGINE SPECIFICATIONS
CLANG_FLAGS="-D_GNU_SOURCE"

if [[ "$CLANG_DEVEL" == "yes" && "$CLANG" == "yes" ]]; then
  echo "Setting up config.site for LLVM/Clang devel..."
  cat >> "${CONFIG_SITE}" <<EOF

# BEGIN ${CONFIG_MARKER}
CC=${CLANG_INSTALL_PATH}/bin/clang
CC23="${CLANG_INSTALL_PATH}/bin/clang -std=c23"
CFLAGS="${CLANG_FLAGS}"
C23FLAGS="${CLANG_FLAGS}"
CXX=${CLANG_INSTALL_PATH}/bin/clang++
CXX17=${CLANG_INSTALL_PATH}/bin/clang++
CXX20=${CLANG_INSTALL_PATH}/bin/clang++
CXX23=${CLANG_INSTALL_PATH}/bin/clang++
CXX26=${CLANG_INSTALL_PATH}/bin/clang++
CXX17STD=-std=c++17
CXX20STD=-std=c++20
CXX23STD=-std=c++23
CXX26STD=-std=c++26
AR=${CLANG_INSTALL_PATH}/bin/llvm-ar
NM=${CLANG_INSTALL_PATH}/bin/llvm-nm
RANLIB=${CLANG_INSTALL_PATH}/bin/llvm-ranlib
LDFLAGS="-fuse-ld=${CLANG_INSTALL_PATH}/bin/ld.lld -lmvec -lm"
FC=/usr/bin/gfortran
# END ${CONFIG_MARKER}
EOF
elif [[ "$CLANG_DEVEL" != "yes" && "$CLANG" == "yes" ]]; then
  echo "Setting up config.site for system Clang..."
  cat >> "${CONFIG_SITE}" <<EOF

# BEGIN ${CONFIG_MARKER}
CC=clang
CC23="clang -std=c23"
CFLAGS="${CLANG_FLAGS}"
C23FLAGS="${CLANG_FLAGS}"
CXX=clang++
CXX17=clang++
CXX20=clang++
CXX23=clang++
CXX26=clang++
CXX17STD=-std=c++17
CXX20STD=-std=c++20
CXX23STD=-std=c++23
CXX26STD=-std=c++26
FC=gfortran
AR=llvm-ar
NM=llvm-nm
RANLIB=llvm-ranlib
LDFLAGS="-fuse-ld=lld"
# END ${CONFIG_MARKER}
EOF
else
  echo "Using default system compilers (no config.site overrides)"
fi

echo "==============================="
echo "Building R-devel from source"
echo "Build directory: ${R_BUILD_DIR}"
echo "Installation prefix: ${R_DEVEL_PREFIX}"
echo "==============================="

mkdir -p "${R_BUILD_DIR}"
mkdir -p "${R_BUILD_DIR}/include"
cd "${R_BUILD_DIR}"

# Configure R
echo "Configuring R..."
"${R_SOURCE_DIR}/configure" \
  --prefix="${R_DEVEL_PREFIX}" \
  --enable-R-shlib \
  --enable-memory-profiling \
  --with-blas \
  --with-lapack \
  --with-readline \
  --with-x=no

# Build R
echo "Building R (this may take a while)..."
make -j$(nproc)

# Install R
echo "Installing R to ${R_DEVEL_PREFIX}..."
sudo make install

# Verify installation
if [ -x "${R_DEVEL_PREFIX}/bin/R" ]; then
  echo "==============================="
  echo "R-devel installed successfully!"
  echo "R version:"
  "${R_DEVEL_PREFIX}/bin/R" --version | head -n 1
  echo "Uninstalled build binary also available at: ${R_BUILD_DIR}/bin/R"
  echo "==============================="
else
  echo "ERROR: R-devel installation failed"
  exit 1
fi

# Link Rdevel executable
sudo ln -sf "${R_DEVEL_PREFIX}/bin/R" /usr/local/bin/R
sudo ln -sf "${R_DEVEL_PREFIX}/bin/Rscript" /usr/local/bin/R
