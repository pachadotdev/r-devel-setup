#!/bin/bash

set -euo pipefail

# Parse command-line arguments
CLANG_DEVEL="no"
CLANG="no"
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
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Configuration
R_DEVEL_PREFIX="/opt/R-devel"
CLANG_README_URL="https://www.stats.ox.ac.uk/pub/bdr/clang23/README.txt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

R_SOURCE_DIR="${SCRIPT_DIR}/trunk"
R_TARBALL_URL="https://cran.r-project.org/src/base-prerelease/R-devel.tar.gz"
R_TARBALL="${SCRIPT_DIR}/R-devel.tar.gz"
R_RECOMMENDED_TAR="${SCRIPT_DIR}/R-devel-recommended.tar.gz"

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
  CLANG_VER=$(curl -fsSL "${CLANG_README_URL}" | head -1 | grep -oP 'LLVM \K[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+)?')
  if [[ -z "$CLANG_VER" ]]; then
    echo "ERROR: Could not detect Clang version from ${CLANG_README_URL}"
    exit 1
  fi
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
    
    git clone --depth 1 https://github.com/llvm/llvm-project.git
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

# Download recommended packages from tarball and extract only those
echo "==============================="
echo "Downloading recommended packages from tarball"
echo "==============================="
curl -L -o "${R_TARBALL}" "${R_TARBALL_URL}"

# Verify tarball was downloaded
if [ ! -f "${R_TARBALL}" ] || [ ! -s "${R_TARBALL}" ]; then
  echo "ERROR: Failed to download R-devel tarball"
  exit 1
fi
echo "Tarball downloaded: $(ls -lh ${R_TARBALL} | awk '{print $5}')"

# Extract only the Recommended directory from the tarball
echo "Extracting recommended packages..."
mkdir -p "${R_SOURCE_DIR}/src/library"

# strip-components=3 removes "R-devel/src/library/" leaving "Recommended/..." → goes into src/library/
tar -xzf "${R_TARBALL}" \
  -C "${R_SOURCE_DIR}/src/library/" \
  "R-devel/src/library/Recommended/" \
  --strip-components=3

# Verify packages were extracted (both .tar.gz and .tgz)
PACKAGE_COUNT=$(ls -1 "${R_SOURCE_DIR}/src/library/Recommended"/*.tar.gz "${R_SOURCE_DIR}/src/library/Recommended"/*.tgz 2>/dev/null | wc -l)
if [ "$PACKAGE_COUNT" -eq 0 ]; then
  echo "ERROR: No recommended packages found in ${R_SOURCE_DIR}/src/library/Recommended/"
  echo "Contents:"
  ls -la "${R_SOURCE_DIR}/src/library/Recommended/" || true
  exit 1
else
  echo "Successfully extracted $PACKAGE_COUNT recommended packages"
fi

# Cleanup tarball
rm -f "${R_TARBALL}"

# Configure ~/.R/Makevars based on compiler flags
MAKEVARS_DIR="${HOME}/.R"
MAKEVARS_FILE="${MAKEVARS_DIR}/Makevars"

mkdir -p "${MAKEVARS_DIR}"

if [[ "$CLANG_DEVEL" == "yes" && "$CLANG" == "yes" ]]; then
  echo "Setting up Makevars for LLVM/Clang devel..."
  if [ -f "${MAKEVARS_FILE}" ]; then
    cp "${MAKEVARS_FILE}" "${MAKEVARS_FILE}.old"
    echo "Backed up existing Makevars to ${MAKEVARS_FILE}.old"
  fi
  cat > "${MAKEVARS_FILE}" <<EOF
CC=${CLANG_INSTALL_PATH}/bin/clang
CXX=${CLANG_INSTALL_PATH}/bin/clang++
CXX11=${CLANG_INSTALL_PATH}/bin/clang++
CXX14=${CLANG_INSTALL_PATH}/bin/clang++
CXX17=${CLANG_INSTALL_PATH}/bin/clang++
CXX20=${CLANG_INSTALL_PATH}/bin/clang++
SHLIB_CXXLD=${CLANG_INSTALL_PATH}/bin/clang++
AR=${CLANG_INSTALL_PATH}/bin/llvm-ar
RANLIB=${CLANG_INSTALL_PATH}/bin/llvm-ranlib
LDFLAGS=-fuse-ld=${CLANG_INSTALL_PATH}/bin/ld.lld
FC=/usr/bin/gfortran
F77=/usr/bin/gfortran
CXX11STD=-std=c++11
CXX14STD=-std=c++14
CXX17STD=-std=c++17
CXX20STD=-std=c++20
EOF
elif [[ "$CLANG_DEVEL" != "yes" && "$CLANG" == "yes" ]]; then
  echo "Setting up Makevars for system Clang..."
  if [ -f "${MAKEVARS_FILE}" ]; then
    cp "${MAKEVARS_FILE}" "${MAKEVARS_FILE}.old"
    echo "Backed up existing Makevars to ${MAKEVARS_FILE}.old"
  fi
  cat > "${MAKEVARS_FILE}" <<'EOF'
CC=clang
CXX=clang++
CXX11=clang++
CXX14=clang++
CXX17=clang++
CXX20=clang++
CXX17STD=-std=c++17
CXX20STD=-std=c++20
FC=gfortran
F77=gfortran
AR=llvm-ar
NM=llvm-nm
RANLIB=llvm-ranlib
LDFLAGS=-fuse-ld=lld
EOF
else
  echo "Using default system compilers (no Makevars changes)"
fi

if [ -f "${MAKEVARS_FILE}" ]; then
  echo "Makevars written to ${MAKEVARS_FILE}"
fi

echo "==============================="
echo "Building R-devel from source"
echo "Installation prefix: ${R_DEVEL_PREFIX}"
echo "==============================="

cd "${R_SOURCE_DIR}"

# Configure R
echo "Configuring R..."
if [[ "$CLANG" == "yes" ]]; then
  CC="clang" \
  CXX="clang++" \
  CXX17="clang++" \
  CXX20="clang++" \
  FC="gfortran" \
  F77="gfortran" \
  AR="llvm-ar" \
  NM="llvm-nm" \
  RANLIB="llvm-ranlib" \
  LDFLAGS="-fuse-ld=lld" \
  ./configure \
    --prefix="${R_DEVEL_PREFIX}" \
    --enable-R-shlib \
    --with-blas \
    --with-lapack \
    --with-readline \
    --with-x=no
else
  ./configure \
    --prefix="${R_DEVEL_PREFIX}" \
    --enable-R-shlib \
    --with-blas \
    --with-lapack \
    --with-readline \
    --with-x=no
fi

# Build R
echo "Building R (this may take a while)..."
make -j$(nproc)

# Install R (requires sudo for /opt)
echo "Installing R to ${R_DEVEL_PREFIX}..."
sudo make install

# Verify installation
if [ -x "${R_DEVEL_PREFIX}/bin/R" ]; then
  echo "==============================="
  echo "R-devel installed successfully!"
  echo "R version:"
  "${R_DEVEL_PREFIX}/bin/R" --version | head -n 1
  echo "==============================="
else
  echo "ERROR: R-devel installation failed"
  exit 1
fi

# Link Rdevel executable (overwrite if already exists)
sudo ln -sf "${R_DEVEL_PREFIX}/bin/R" /usr/local/bin/Rdevel
