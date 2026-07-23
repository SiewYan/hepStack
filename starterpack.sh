#!/usr/bin/env bash

set -e  # Exit on any error

CWD=$(pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}ℹ INFO:${NC} $1"; }
print_success() { echo -e "${GREEN}✓ SUCCESS:${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠ WARNING:${NC} $1"; }
print_error() { echo -e "${RED}✗ ERROR:${NC} $1"; }

# Absolute directory this script lives in — used to anchor relative config paths
# so the install location is stable regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve a path to a clean, absolute path.
#   $1 = path (relative or absolute)
#   $2 = base to resolve a relative path against (default: $SCRIPT_DIR)
# Absolute inputs are kept as-is; relative inputs are joined with the base.
# When the resolved directory exists it is canonicalized via `pwd -P` (resolves
# "." "//" ".." and symlinks); otherwise a lightweight sed tidy is applied.
abspath() {
    local path=$1
    local base=${2:-$SCRIPT_DIR}
    # Drop leading "./" segments so a relative default like "./local" joins cleanly.
    while [ "${path#./}" != "$path" ]; do path="${path#./}"; done
    case "$path" in
        /*) : ;;
        *)  path="$base/$path" ;;
    esac
    if [ -d "$path" ]; then
        ( cd "$path" && pwd -P )
    else
        # Collapse duplicate slashes and strip a trailing slash (':' delimiter
        # avoids escaping the slashes). No filesystem side effects.
        printf '%s' "$path" | sed -e 's:/\{2,\}:/:g' -e 's:\(.\)/$:\1:'
    fi
}

# Configuration file
CONFIG_FILE="$SCRIPT_DIR/dependencies.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Read configuration file
read_config() {
    local section=$1
    local key=$2
    local value=""
    
    # Read the file line by line
    local in_section=0
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        line=$(echo "$line" | sed 's/^[[:space:]]*#.*$//')  # Remove comments
        line=$(echo "$line" | sed 's/^[[:space:]]*//')      # Remove leading spaces
        line=$(echo "$line" | sed 's/[[:space:]]*$//')      # Remove trailing spaces
        
        if [ -z "$line" ]; then
            continue
        fi
        
        # Check for section
        if [[ "$line" =~ ^\[(.*)\]$ ]]; then
            if [ "$in_section" -eq 1 ]; then
                break  # We've moved to another section
            fi
            if [ "${BASH_REMATCH[1]}" = "$section" ]; then
                in_section=1
            else
                in_section=0
            fi
            continue
        fi
        
        # If we're in the right section, look for the key
        if [ "$in_section" -eq 1 ] && [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local config_key=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            local config_value=$(echo "${BASH_REMATCH[2]}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | sed 's/^"//' | sed 's/"$//')
            
            if [ "$config_key" = "$key" ]; then
                value="$config_value"
                break
            fi
        fi
    done < "$CONFIG_FILE"
    
    echo "$value"
}

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin)    echo "macos" ;;
        Linux)     
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case "$ID" in
                    ubuntu|debian|pop) echo "debian" ;;
                    fedora|rhel|centos) echo "redhat" ;;
                    arch|manjaro) echo "arch" ;;
                    *) echo "linux" ;;
                esac
            else
                echo "linux"
            fi
            ;;
        *)         echo "unknown" ;;
    esac
}

PLATFORM=$(detect_platform)
ARCH=$(uname -m)

# Read default values from config
DEFAULT_PREFIX=$(read_config "build" "default_prefix")
DEFAULT_BUILD_DIR=$(read_config "build" "default_build_dir")
ROOT_VERSION=$(read_config "versions" "root")
CLHEP_VERSION=$(read_config "versions" "clhep")
GEANT4_VERSION=$(read_config "versions" "geant4")
LHAPDF_VERSION=$(read_config "versions" "lhapdf")
PYTHIA8_VERSION=$(read_config "versions" "pythia8")
DELPHES_VERSION=$(read_config "versions" "delphes")
MADGRAPH_VERSION=$(read_config "versions" "madgraph")
WHIZARD_VERSION=$(read_config "versions" "whizard")
CALCHEP_VERSION=$(read_config "versions" "calchep")
HERWIG_VERSION=$(read_config "versions" "herwig")
MADANALYSIS_VERSION=$(read_config "versions" "madanalysis")
RIVET_VERSION=$(read_config "versions" "rivet")
CHECKMATE_VERSION=$(read_config "versions" "checkmate")
CONTUR_VERSION=$(read_config "versions" "contur")
PYHF_VERSION=$(read_config "versions" "pyhf")
SPEY_VERSION=$(read_config "versions" "spey")
MAMBA_VERSION=$(read_config "python" "miniforge")
PYTHON_VERSION=$(read_config "python" "python")
PYTHON_PACKAGES=$(read_config "python" "packages")

# Default configuration
CWD=$(pwd)
# Config defaults (default_prefix / default_build_dir) are relative and anchored
# to the script directory, so `local/` and `build/` always land beside the
# installer no matter where it is invoked from. Explicit overrides via the
# INSTALL_PREFIX / BUILD_DIR environment variables are resolved against the
# caller's CWD (standard CLI convention). Either way the result is absolute,
# so every path written to the shell rc is absolute too.
if [ -n "${INSTALL_PREFIX:-}" ]; then
    INSTALL_PREFIX=$(abspath "$INSTALL_PREFIX" "$CWD")
else
    INSTALL_PREFIX=$(abspath "$DEFAULT_PREFIX" "$SCRIPT_DIR")
fi
if [ -n "${BUILD_DIR:-}" ]; then
    BUILD_DIR=$(abspath "$BUILD_DIR" "$CWD")
else
    BUILD_DIR=$(abspath "$DEFAULT_BUILD_DIR" "$SCRIPT_DIR")
fi
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Installation flags
INSTALL_ROOT="${INSTALL_ROOT:-1}"
INSTALL_CLHEP="${INSTALL_CLHEP:-1}"
INSTALL_GEANT4="${INSTALL_GEANT4:-1}"
INSTALL_LHAPDF="${INSTALL_LHAPDF:-1}"
INSTALL_PYTHIA8="${INSTALL_PYTHIA8:-1}"
INSTALL_DELPHES="${INSTALL_DELPHES:-1}"
INSTALL_MADGRAPH="${INSTALL_MADGRAPH:-1}"
INSTALL_WHIZARD="${INSTALL_WHIZARD:-1}"
INSTALL_CALCHEP="${INSTALL_CALCHEP:-1}"
INSTALL_HERWIG="${INSTALL_HERWIG:-1}"
INSTALL_MADANALYSIS="${INSTALL_MADANALYSIS:-1}"
INSTALL_RIVET="${INSTALL_RIVET:-1}"
INSTALL_CHECKMATE="${INSTALL_CHECKMATE:-1}"
INSTALL_CONTUR="${INSTALL_CONTUR:-1}"
INSTALL_PYHF="${INSTALL_PYHF:-1}"
INSTALL_SPEY="${INSTALL_SPEY:-1}"
INSTALL_MAMBA="${INSTALL_MAMBA:-1}"

# Skip the interactive menu and install per the current flags (set by -y/--all)
ASSUME_YES="${ASSUME_YES:-0}"

# Rebuild even if a package is already present (set by --force)
FORCE_REINSTALL="${FORCE_REINSTALL:-0}"

# Environment delivery method. 1 (default) = generate Lmod modulefiles and do
# NOT touch the user's shell rc; 0 = fall back to writing exports into
# ~/.bashrc / ~/.zshrc (set by --no-modules).
USE_MODULES="${USE_MODULES:-1}"

# Package registry — install order. The flag var is INSTALL_<KEY> and the
# version var is <KEY>_VERSION for every entry (bash 3.2: parallel arrays,
# no associative arrays).
PKG_KEYS=(MAMBA CLHEP ROOT GEANT4 LHAPDF PYTHIA8 DELPHES MADGRAPH WHIZARD CALCHEP HERWIG MADANALYSIS RIVET CHECKMATE PYHF SPEY CONTUR)
PKG_LABELS=("mamba/Python" "CLHEP" "ROOT" "Geant4" "LHAPDF" "Pythia8" "Delphes" "MadGraph" "WHIZARD" "CalcHEP" "Herwig7" "MadAnalysis5" "Rivet" "CheckMATE" "pyhf" "spey" "Contur")

# Miniforge lives under the prefix; its bin provides python3 for every build.
MAMBA_ROOT="$INSTALL_PREFIX/miniforge3"

# Generated Lmod (.lua) modulefiles live here; this dir is what users add to
# their MODULEPATH (via `module use`) after installation.
MODULES_DIR="$INSTALL_PREFIX/modulefiles"

# Get dependencies for platform
get_deps() {
    local platform=$1
    local deptype=$2  # packages or brew_packages
    
    local deps=$(read_config "$platform" "${deptype:-packages}")
    echo "$deps"
}

# Function to install system dependencies
install_system_deps() {
    print_info "Installing system dependencies for $PLATFORM..."
    
    local platform_name=$(read_config "$PLATFORM" "name")
    print_info "Platform: $platform_name"
    
    case $PLATFORM in
        debian)
            local deps=$(get_deps "debian")
            sudo apt update && sudo apt install -y $deps
            ;;
        redhat)
            local deps=$(get_deps "redhat")
            sudo dnf groupinstall -y "Development Tools"
            sudo dnf install -y $deps
            ;;
        macos)
            local deps=$(get_deps "macos")
            local brew_deps=$(get_deps "macos" "brew_packages")
            
            if ! command -v brew &> /dev/null; then
                print_error "Homebrew not found. Please install Homebrew first:"
                echo "  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 1
            fi
	    print_info "brew install ${deps} ${brew_deps}"
            brew install $deps $brew_deps
            ;;
        arch)
            local deps=$(get_deps "arch")
            sudo pacman -Sy --noconfirm $deps
            ;;
        *)
            print_warning "Unknown platform. Please install dependencies manually."
            ;;
    esac
}

# Utility functions
# Download a single file (no extraction) to a given path.
download_file() {
    local url=$1
    local dest=$2

    print_info "Downloading from $url..."
    if command -v curl &> /dev/null; then
        curl -L -o "$dest" "$url"
    elif command -v wget &> /dev/null; then
        wget -q -O "$dest" "$url"
    else
        print_error "Neither curl nor wget found. Please install one."
        exit 1
    fi
}

download_and_extract() {
    local url=$1
    local output_dir=$2
    
    print_info "Downloading from $url..."
    
    # Create a temporary file to store the download
    local temp_file=$(mktemp)
    
    if command -v curl &> /dev/null; then
        curl -L -o "$temp_file" "$url"
    elif command -v wget &> /dev/null; then
        wget -q -O "$temp_file" "$url"
    else
        print_error "Neither curl nor wget found. Please install one."
        exit 1
    fi
    
    # Extract the archive
    if [ -n "$output_dir" ]; then
        mkdir -p "$output_dir"
        tar xzf "$temp_file" -C "$output_dir" --strip-components=1 2>/dev/null || tar xzf "$temp_file" -C "$(dirname "$output_dir")" && mv "$(dirname "$output_dir")/$(tar tzf "$temp_file" | head -1 | cut -f1 -d'/')" "$output_dir" 2>/dev/null || true
    else
        tar xzf "$temp_file"
    fi
    
    rm -f "$temp_file"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is required but not found."
        return 1
    fi
    return 0
}

# Single source of truth for "is this package present under $INSTALL_PREFIX?".
# Returns the on-disk marker (a binary/dir that only exists after a successful
# install) for a package KEY. Empty for pip packages (detected via the venv).
pkg_marker() {
    case "$1" in
        MAMBA)       echo "$INSTALL_PREFIX/miniforge3/bin/mamba" ;;
        CLHEP)       echo "$INSTALL_PREFIX/include/CLHEP" ;;
        ROOT)        echo "$INSTALL_PREFIX/bin/root" ;;
        GEANT4)      echo "$INSTALL_PREFIX/bin/geant4-config" ;;
        LHAPDF)      echo "$INSTALL_PREFIX/bin/lhapdf-config" ;;
        PYTHIA8)     echo "$INSTALL_PREFIX/bin/pythia8-config" ;;
        DELPHES)     echo "$INSTALL_PREFIX/Delphes-$DELPHES_VERSION/DelphesHepMC3" ;;
        MADGRAPH)    echo "$INSTALL_PREFIX/MG5_aMC_v$MADGRAPH_VERSION/bin/mg5_aMC" ;;
        WHIZARD)     echo "$INSTALL_PREFIX/bin/whizard" ;;
        CALCHEP)     echo "$INSTALL_PREFIX/calchep-$CALCHEP_VERSION/calchep" ;;
        HERWIG)      echo "$INSTALL_PREFIX/herwig-$HERWIG_VERSION/bin/Herwig" ;;
        MADANALYSIS) echo "$INSTALL_PREFIX/madanalysis5-$MADANALYSIS_VERSION/bin/ma5" ;;
        RIVET)       echo "$INSTALL_PREFIX/bin/rivet" ;;
        CHECKMATE)   echo "$INSTALL_PREFIX/checkmate2-$CHECKMATE_VERSION/bin/CheckMATE" ;;
        *)           echo "" ;;
    esac
}

# Returns 0 if package KEY is already installed under $INSTALL_PREFIX.
pkg_is_installed() {
    local key=$1
    case "$key" in
        PYHF|SPEY|CONTUR)
            local pkg
            pkg=$(echo "$key" | tr '[:upper:]' '[:lower:]')
            [ -x "$PYHEP_VENV/bin/pip" ] && "$PYHEP_VENV/bin/pip" show "$pkg" >/dev/null 2>&1
            ;;
        *)
            local marker
            marker=$(pkg_marker "$key")
            [ -n "$marker" ] && [ -e "$marker" ]
            ;;
    esac
}

# Idempotency guard used by install_* functions: returns 0 (skip) when the
# package is already present and we are not forcing a rebuild.
already_installed() {
    local key=$1 label=$2
    if [ "$FORCE_REINSTALL" -eq 1 ]; then
        return 1
    fi
    if pkg_is_installed "$key"; then
        print_success "$label already installed — skipping (use --force to rebuild)."
        return 0
    fi
    return 1
}

add_to_shell() {
    # With modulefiles as the delivery method, environment comes from
    # `module load`, so we deliberately never modify the user's shell rc.
    [ "${USE_MODULES:-1}" -eq 1 ] && return 0
    local line=$1
    local shell_rc="$HOME/.bashrc"
    
    # Detect shell
    case "$SHELL" in
        *zsh) shell_rc="$HOME/.zshrc" ;;
        *bash) shell_rc="$HOME/.bashrc" ;;
    esac
    
    if [ ! -f "$shell_rc" ]; then
        touch "$shell_rc"
    fi
    
    if ! grep -qF "$line" "$shell_rc" 2>/dev/null; then
        echo "$line" >> "$shell_rc"
        print_info "Added to $shell_rc"
    fi
}

cmake_build() {
    local source_dir=$1
    shift
    local build_dir="build"
    
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    cmake -G Ninja \
          -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
          -DCMAKE_BUILD_TYPE=Release \
          "$@" \
          "$source_dir"
    
    ninja -j$NPROC
    ninja install
    cd ..
}

# Installation functions
# Miniforge (mamba) provides the Python used by every build in this stack.
# Used strictly as the Python provider: python packages come from mamba, but
# C++/Fortran compilers stay system-side to avoid conda ABI mismatches.
install_mamba() {
    already_installed MAMBA "Miniforge/mamba" && {
        export PATH="$MAMBA_ROOT/bin:$PATH"
        return 0
    }
    print_info "Installing Miniforge (mamba) ${MAMBA_VERSION:-latest}..."

    cd "$BUILD_DIR"

    # Installer name: Miniforge3-<OS>-<arch>.sh, e.g. Miniforge3-Darwin-arm64.sh
    local os arch installer url
    os=$(uname -s)
    arch=$(uname -m)
    installer="Miniforge3-$os-$arch.sh"

    if [ -z "$MAMBA_VERSION" ] || [ "$MAMBA_VERSION" = "latest" ]; then
        url="https://github.com/conda-forge/miniforge/releases/latest/download/$installer"
    else
        url="https://github.com/conda-forge/miniforge/releases/download/$MAMBA_VERSION/Miniforge3-$MAMBA_VERSION-$os-$arch.sh"
    fi

    if [ ! -f "$installer" ]; then
        download_file "$url" "$installer"
    fi

    # -b: batch (no license prompt), -p: prefix. Keep it out of ~/.bashrc's
    # conda init — we manage PATH ourselves.
    bash "$installer" -b -p "$MAMBA_ROOT"

    # Pin python and install the packages the builds need.
    print_info "Installing Python $PYTHON_VERSION + build packages into miniforge base..."
    "$MAMBA_ROOT/bin/mamba" install -y "python=$PYTHON_VERSION" $PYTHON_PACKAGES

    # Make this python the one every subsequent build finds first.
    export PATH="$MAMBA_ROOT/bin:$PATH"

    add_to_shell "# hepStack python (miniforge): "
    add_to_shell "export PATH=\"$MAMBA_ROOT/bin:\$PATH\""

    print_info "Python in use: $("$MAMBA_ROOT/bin/python3" --version 2>&1) at $MAMBA_ROOT/bin/python3"
    print_success "Miniforge/mamba installed successfully"
}

install_clhep() {
    already_installed CLHEP "CLHEP" && return 0
    print_info "Installing CLHEP v$CLHEP_VERSION..."
    
    cd "$BUILD_DIR"
    local clhep_dir="clhep-$CLHEP_VERSION"
    
    if [ ! -d "$clhep_dir" ]; then
        download_and_extract \
            "https://proj-clhep.web.cern.ch/proj-clhep/dist1/clhep-$CLHEP_VERSION.tgz" \
            "$clhep_dir"
    fi
    
    cd "$clhep_dir"
    cmake_build "$BUILD_DIR/$clhep_dir/CLHEP"
    
    add_to_shell "export CLHEP_DIR=\"$INSTALL_PREFIX\""
    add_to_shell "export CLHEP_BASE=\"$INSTALL_PREFIX\""
    
    print_success "CLHEP installed successfully"
}

install_root() {
    already_installed ROOT "ROOT" && return 0
    print_info "Installing ROOT v$ROOT_VERSION..."
    
    cd "$BUILD_DIR"
    local root_dir="root-$ROOT_VERSION"

    mkdir -p forRoot
    cd forRoot
    
    if [ ! -d "$root_dir" ]; then
        download_and_extract \
            "https://root.cern/download/root_v${ROOT_VERSION}.source.tar.gz" \
            "$root_dir"
    fi
    
    #cd "$root_dir"
    mkdir -p build
    cd build
    
    # Build cmake options array
    CMAKE_OPTIONS=(
        "-DCMAKE_INSTALL_PREFIX=$INSTALL_PREFIX"
    )
    
    # is this needed?
    # -Dbuiltin_fftw3=ON -Dbuiltin_cfitsio=ON -Droofit=ON -Dgdml=ON 
    
    # Platform-specific options
    case $PLATFORM in
        macos)
            CMAKE_OPTIONS+=("-Dcocoa=ON" "-Dx11=OFF" "-Dbuiltin_openssl=ON")
            ;;
        *)
            CMAKE_OPTIONS+=("-Dx11=ON")
            ;;
    esac

    # CMAKE POLICY
    if [ "$ROOT_VERSION" == "6.32.08" ]; then
	CMAKE_OPTIONS+=( "-DCMAKE_POLICY_DEFAULT_CMP0175=OLD" "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" )
    fi
    
    # Join array into string and execute
    local cmake_cmd="cmake -G Ninja ${CMAKE_OPTIONS[@]} ../$root_dir"
    echo $cmake_cmd
    eval $cmake_cmd

    # patch/intervention
    # CMAKE issue
    if [ "$ROOT_VERSION" == "6.32.08" ]; then
	CMAKE_VDT="${BUILD_DIR}/forRoot/build/VDT-prefix/src/VDT-stamp/VDT-configure-Release.cmake"
	if [ -f "${CMAKE_VDT}" ]; then
            print_info "Patching VDT configuration..."
    
            #patch --dry-run --verbose ${CMAKE_VDT} < ${CWD}/patch/VDT-configure-Release.cmake.patch
            patch ${CMAKE_VDT} < ${CWD}/patch/VDT-configure-Release.cmake.patch
	fi
    fi
    
    ninja -j$NPROC
    ninja install
    
    add_to_shell "export ROOTSYS=\"$INSTALL_PREFIX\""
    add_to_shell "export PATH=\"\$ROOTSYS/bin:\$PATH\""
    add_to_shell "export LD_LIBRARY_PATH=\"\$ROOTSYS/lib:\$LD_LIBRARY_PATH\""
    add_to_shell "source \"\$ROOTSYS/bin/thisroot.sh\""
    
    print_success "ROOT installed successfully"
}

install_geant4() {
    already_installed GEANT4 "Geant4" && return 0
    print_info "Installing Geant4 v$GEANT4_VERSION..."
    
    cd "$BUILD_DIR"
    local geant4_dir="geant4-$GEANT4_VERSION"

    if [ ! -d "$geant4_dir" ]; then
        download_and_extract \
            "https://gitlab.cern.ch/geant4/geant4/-/archive/v$GEANT4_VERSION/geant4-v$GEANT4_VERSION.tar.gz" \
            "$geant4_dir"
    fi
    
    cd "$geant4_dir"

    
    # bug for Geant4 10.7.3
    if [ "$GEANT4_VERSION" == "10.7.3" ]; then
	COLUMNSICC=${BUILD_DIR}/${geant4_dir}/source/analysis/g4tools/include/tools/wroot/columns.icc
	if [ -f "${COLUMNSICC}" ]; then
	    print_info "Patching ${COLUMNSICC} ..."
	    patch ${COLUMNSICC} < ${CWD}/patch/columns.icc.patch
	fi
    fi
    
    # Build cmake options array
    # "-DGEANT4_USE_QT=ON"
    CMAKE_OPTIONS=(
        "-DGEANT4_BUILD_MULTITHREADED=ON"
	"-DGEANT4_INSTALL_DATA=ON"
	"-DGEANT4_USE_OPENGL_X11=ON"
        "-DGEANT4_USE_SYSTEM_CLHEP=ON"
        "-DGEANT4_USE_SYSTEM_EXPAT=ON"
        "-DGEANT4_USE_SYSTEM_ZLIB=ON"
    )

    # Platform-specific options
    #case $PLATFORM in
    #    macos)
    #        CMAKE_OPTIONS+=("-DGEANT4_USE_QT=ON" "-DQt5_DIR=\"$(brew --prefix qt@5)/lib/cmake/Qt5\"")
    #        ;;
    #*)
    #        CMAKE_OPTIONS+=("-DGEANT4_USE_QT=ON")
    #        ;;
    #esac

    
    # Join array into string and execute
    cmake_build "$BUILD_DIR/$geant4_dir" "${CMAKE_OPTIONS[@]}"
    
    add_to_shell "export GEANT4_DIR=\"$INSTALL_PREFIX\""
    add_to_shell "export GEANT4_INSTALL=\"$INSTALL_PREFIX\""
    add_to_shell "source \"\$GEANT4_DIR/bin/geant4.sh\""

    # bug for Geant4 10.7.3
    if [ "$GEANT4_VERSION" == "10.7.3" ]; then
	GEANT4PACKAGECACHE=${CWD}/local/lib/Geant4-${GEANT4_VERSION}/Geant4PackageCache.cmake
        if [ -f "${GEANT4PACKAGECACHE}" ]; then
            print_info "Patching ${GEANT4PACKAGECACHE} ..."
            patch ${GEANT4PACKAGECACHE} < ${CWD}/patch/Geant4PackageCache.cmake.patch
        fi
    fi

    
    print_success "Geant4 installed successfully"
}

# Make sure ROOT is usable in this shell (needed to build Delphes).
# ROOT may have just been installed to INSTALL_PREFIX or already live on the system.
ensure_root_env() {
    if [ -f "$INSTALL_PREFIX/bin/thisroot.sh" ]; then
        source "$INSTALL_PREFIX/bin/thisroot.sh"
    fi
    if ! command -v root-config &> /dev/null; then
        print_error "root-config not found. Delphes needs ROOT — install ROOT first (drop --no-root)."
        return 1
    fi
    return 0
}

install_lhapdf() {
    already_installed LHAPDF "LHAPDF" && return 0
    print_info "Installing LHAPDF v$LHAPDF_VERSION..."

    cd "$BUILD_DIR"
    local lhapdf_dir="LHAPDF-$LHAPDF_VERSION"

    if [ ! -d "$lhapdf_dir" ]; then
        download_and_extract \
            "https://lhapdf.hepforge.org/downloads/?f=LHAPDF-$LHAPDF_VERSION.tar.gz" \
            "$lhapdf_dir"
    fi

    cd "$lhapdf_dir"
    ./configure --prefix="$INSTALL_PREFIX"
    make -j$NPROC
    make install

    add_to_shell "export LHAPDF_DIR=\"$INSTALL_PREFIX\""
    add_to_shell "export LHAPDF_DATA_PATH=\"$INSTALL_PREFIX/share/LHAPDF\""
    add_to_shell "export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
    add_to_shell "export LD_LIBRARY_PATH=\"$INSTALL_PREFIX/lib:\$LD_LIBRARY_PATH\""

    # expose the just-built lib/headers to Pythia8/WHIZARD builds in this run
    export LHAPDF_DIR="$INSTALL_PREFIX"
    export LHAPDF_DATA_PATH="$INSTALL_PREFIX/share/LHAPDF"

    print_success "LHAPDF installed successfully"
}

install_pythia8() {
    already_installed PYTHIA8 "Pythia8" && return 0
    print_info "Installing Pythia8 v$PYTHIA8_VERSION..."

    cd "$BUILD_DIR"
    local pythia_dir="pythia$PYTHIA8_VERSION"

    if [ ! -d "$pythia_dir" ]; then
        download_and_extract \
            "https://pythia.org/releases/pythia83/pythia$PYTHIA8_VERSION.tgz" \
            "$pythia_dir"
    fi

    cd "$pythia_dir"

    # Pythia8 ships its own configure (not GNU autotools)
    local py_opts=("--prefix=$INSTALL_PREFIX")
    if [ -f "$INSTALL_PREFIX/bin/lhapdf-config" ]; then
        py_opts+=("--with-lhapdf6=$INSTALL_PREFIX")
    fi

    ./configure "${py_opts[@]}"
    make -j$NPROC
    make install

    add_to_shell "export PYTHIA8=\"$INSTALL_PREFIX\""
    add_to_shell "export PYTHIA8DATA=\"$INSTALL_PREFIX/share/Pythia8/xmldoc\""
    add_to_shell "export LD_LIBRARY_PATH=\"$INSTALL_PREFIX/lib:\$LD_LIBRARY_PATH\""

    export PYTHIA8="$INSTALL_PREFIX"
    export PYTHIA8DATA="$INSTALL_PREFIX/share/Pythia8/xmldoc"

    print_success "Pythia8 installed successfully"
}

install_delphes() {
    already_installed DELPHES "Delphes" && return 0
    print_info "Installing Delphes v$DELPHES_VERSION..."

    ensure_root_env || return 1

    # Delphes is used in place; keep the built tree under the install prefix.
    local delphes_dir="$INSTALL_PREFIX/Delphes-$DELPHES_VERSION"

    if [ ! -d "$delphes_dir" ]; then
        download_and_extract \
            "http://cp3.irmp.ucl.ac.be/downloads/Delphes-$DELPHES_VERSION.tar.gz" \
            "$delphes_dir"
    fi

    cd "$delphes_dir"

    # Build core executables; link against Pythia8 if we built it.
    if [ -f "$INSTALL_PREFIX/bin/pythia8-config" ] || [ -d "$INSTALL_PREFIX/include/Pythia8" ]; then
        export PYTHIA8="$INSTALL_PREFIX"
        make -j$NPROC HAS_PYTHIA8=true
        make -j$NPROC HAS_PYTHIA8=true display 2>/dev/null || true
    else
        make -j$NPROC
    fi

    add_to_shell "export DELPHES_DIR=\"$delphes_dir\""
    add_to_shell "export PATH=\"$delphes_dir:\$PATH\""
    add_to_shell "export LD_LIBRARY_PATH=\"$delphes_dir:\$LD_LIBRARY_PATH\""
    add_to_shell "export ROOT_INCLUDE_PATH=\"$delphes_dir/external:\$ROOT_INCLUDE_PATH\""

    print_success "Delphes installed successfully"
}

install_madgraph() {
    already_installed MADGRAPH "MadGraph" && return 0
    print_info "Installing MadGraph5_aMC@NLO v$MADGRAPH_VERSION..."

    # MadGraph is a Python application — no compilation, used in place.
    local mg_dir="$INSTALL_PREFIX/MG5_aMC_v$MADGRAPH_VERSION"
    
    if [ ! -d "$mg_dir" ]; then
        download_and_extract \
            "https://github.com/mg5amcnlo/mg5amcnlo/archive/refs/tags/v$MADGRAPH_VERSION.tar.gz" \
            "$mg_dir"
    fi

    if [ ! -f "$mg_dir/bin/mg5_aMC" ]; then
        print_error "MadGraph executable not found at $mg_dir/bin/mg5_aMC"
        return 1
    fi
    chmod +x "$mg_dir/bin/mg5_aMC" 2>/dev/null || true

    add_to_shell "export MG5_DIR=\"$mg_dir\""
    add_to_shell "export PATH=\"$mg_dir/bin:\$PATH\""

    print_info "Tip: inside mg5_aMC use 'install pythia8 lhapdf6' or point to the ones built here."
    print_success "MadGraph installed successfully"
}

install_whizard() {
    already_installed WHIZARD "WHIZARD" && return 0
    print_info "Installing WHIZARD v$WHIZARD_VERSION..."

    if ! command -v ocaml &> /dev/null; then
        print_error "OCaml not found. WHIZARD needs OCaml (>=4.05) — install system deps first."
        return 1
    fi

    cd "$BUILD_DIR"
    local whizard_dir="whizard-$WHIZARD_VERSION"

    if [ ! -d "$whizard_dir" ]; then
        download_and_extract \
            "https://whizard.hepforge.org/downloads/?f=whizard-$WHIZARD_VERSION.tar.gz" \
            "$whizard_dir"
    fi

    cd "$whizard_dir"

    local wz_opts=("--prefix=$INSTALL_PREFIX")
    [ -f "$INSTALL_PREFIX/bin/lhapdf-config" ]  && wz_opts+=("--enable-lhapdf")
    [ -f "$INSTALL_PREFIX/bin/pythia8-config" ] && wz_opts+=("--enable-pythia8" "--with-pythia8=$INSTALL_PREFIX")
    if command -v root-config &> /dev/null; then
        wz_opts+=("--enable-hepmc" "HEPMC_DIR=$INSTALL_PREFIX")
    fi

    print_info "WHIZARD configure: ${wz_opts[*]}"
    ./configure "${wz_opts[@]}"
    make -j$NPROC
    make install

    add_to_shell "export WHIZARD_DIR=\"$INSTALL_PREFIX\""
    add_to_shell "export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
    add_to_shell "export LD_LIBRARY_PATH=\"$INSTALL_PREFIX/lib:\$LD_LIBRARY_PATH\""

    print_success "WHIZARD installed successfully"
}

install_calchep() {
    already_installed CALCHEP "CalcHEP" && return 0
    print_info "Installing CalcHEP v$CALCHEP_VERSION..."

    # CalcHEP is used in place from its own working directory.
    local calchep_dir="$INSTALL_PREFIX/calchep-$CALCHEP_VERSION"

    if [ ! -d "$calchep_dir" ]; then
        download_and_extract \
            "https://theory.sinp.msu.ru/~pukhov/CALCHEP/calchep_$CALCHEP_VERSION.tgz" \
            "$calchep_dir"
    fi

    cd "$calchep_dir"
    make

    add_to_shell "export CALCHEP_DIR=\"$calchep_dir\""
    add_to_shell "export PATH=\"$calchep_dir:\$PATH\""

    print_info "Tip: run '$calchep_dir/mkUsrDir <workdir>' to create a CalcHEP working area."
    print_success "CalcHEP installed successfully"
    print_warning "CompHEP is the legacy predecessor of CalcHEP and is not maintained; CalcHEP supersedes it."
}

install_herwig() {
    already_installed HERWIG "Herwig7" && return 0
    print_info "Installing Herwig7 v$HERWIG_VERSION (via herwig-bootstrap — this is slow)..."

    # Herwig7 pulls a deep tree (ThePEG, fastjet, HepMC, gsl, boost, LHAPDF...).
    # The upstream bootstrap script builds and wires all of it together.
    local herwig_dir="$INSTALL_PREFIX/herwig-$HERWIG_VERSION"
    mkdir -p "$herwig_dir"

    cd "$BUILD_DIR"
    if [ ! -f "herwig-bootstrap" ]; then
        download_file \
            "https://herwig.hepforge.org/downloads/herwig-bootstrap" \
            "herwig-bootstrap"
    fi
    chmod +x herwig-bootstrap

    # Reuse the LHAPDF we already built rather than rebuilding it.
    local hw_opts=("-j" "$NPROC")
    if [ -f "$INSTALL_PREFIX/bin/lhapdf-config" ]; then
        hw_opts+=("--with-lhapdf=$INSTALL_PREFIX")
    fi

    ./herwig-bootstrap "${hw_opts[@]}" "$herwig_dir"

    add_to_shell "export HERWIG_DIR=\"$herwig_dir\""
    add_to_shell "export PATH=\"$herwig_dir/bin:\$PATH\""
    add_to_shell "export LD_LIBRARY_PATH=\"$herwig_dir/lib:\$LD_LIBRARY_PATH\""
    add_to_shell "source \"$herwig_dir/bin/activate\" 2>/dev/null || true"

    print_success "Herwig7 installed successfully"
}

install_madanalysis5() {
    already_installed MADANALYSIS "MadAnalysis5" && return 0
    print_info "Installing MadAnalysis5 v$MADANALYSIS_VERSION..."

    # MadAnalysis5 is a Python application, used in place.
    local ma5_dir="$INSTALL_PREFIX/madanalysis5-$MADANALYSIS_VERSION"

    if [ ! -d "$ma5_dir" ]; then
        download_and_extract \
            "https://github.com/MadAnalysis/madanalysis5/archive/refs/tags/v$MADANALYSIS_VERSION.tar.gz" \
            "$ma5_dir"
    fi

    if [ ! -f "$ma5_dir/bin/ma5" ]; then
        print_error "MadAnalysis5 launcher not found at $ma5_dir/bin/ma5"
        return 1
    fi
    chmod +x "$ma5_dir/bin/ma5" 2>/dev/null || true

    add_to_shell "export MA5_DIR=\"$ma5_dir\""
    add_to_shell "export PATH=\"$ma5_dir/bin:\$PATH\""

    print_info "Tip: first launch of 'ma5' installs its own dependencies (fastjet, etc.) on demand."
    print_success "MadAnalysis5 installed successfully"
}

install_rivet() {
    already_installed RIVET "Rivet" && return 0
    print_info "Installing Rivet v$RIVET_VERSION (via rivet-bootstrap — builds HepMC3/YODA/fastjet)..."

    cd "$BUILD_DIR"
    if [ ! -f "rivet-bootstrap" ]; then
        download_file \
            "https://gitlab.com/hepcedar/rivetbootstrap/-/raw/$RIVET_VERSION/rivet-bootstrap" \
            "rivet-bootstrap"
    fi
    chmod +x rivet-bootstrap

    # The bootstrap installs everything under INSTALL_PREFIX.
    INSTALL_PREFIX="$INSTALL_PREFIX" MAKE="make -j$NPROC" ./rivet-bootstrap

    add_to_shell "export RIVET_DIR=\"$INSTALL_PREFIX\""
    add_to_shell "export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
    add_to_shell "export LD_LIBRARY_PATH=\"$INSTALL_PREFIX/lib:\$LD_LIBRARY_PATH\""
    add_to_shell "source \"$INSTALL_PREFIX/rivetenv.sh\" 2>/dev/null || true"

    print_success "Rivet installed successfully"
}

install_checkmate() {
    already_installed CHECKMATE "CheckMATE" && return 0
    print_info "Installing CheckMATE v$CHECKMATE_VERSION..."

    ensure_root_env || return 1

    local cm_dir="$INSTALL_PREFIX/checkmate2-$CHECKMATE_VERSION"

    if [ ! -d "$cm_dir" ]; then
        download_and_extract \
            "https://github.com/CheckMATE2/checkmate2/archive/refs/tags/v$CHECKMATE_VERSION.tar.gz" \
            "$cm_dir"
    fi

    cd "$cm_dir"

    # CheckMATE ties together ROOT, Delphes, Pythia8 and MadGraph.
    local cm_opts=("--with-rootsys=$ROOTSYS")
    local delphes_dir="$INSTALL_PREFIX/Delphes-$DELPHES_VERSION"
    local mg_dir="$INSTALL_PREFIX/MG5_aMC_v$MADGRAPH_VERSION"
    [ -d "$delphes_dir" ]                  && cm_opts+=("--with-delphes=$delphes_dir")
    [ -f "$INSTALL_PREFIX/bin/pythia8-config" ] && cm_opts+=("--with-pythia=$INSTALL_PREFIX")
    [ -d "$mg_dir" ]                       && cm_opts+=("--with-madgraph=$mg_dir")

    print_info "CheckMATE configure: ${cm_opts[*]}"
    ./configure "${cm_opts[@]}"
    make -j$NPROC

    add_to_shell "export CHECKMATE_DIR=\"$cm_dir\""
    add_to_shell "export PATH=\"$cm_dir/bin:\$PATH\""

    print_success "CheckMATE installed successfully"
}

# Shared Python venv for pip-installed analysis tools (pyhf, spey, contur)
PYHEP_VENV="$INSTALL_PREFIX/pyhep-venv"
ensure_pyvenv() {
    # Prefer the miniforge python so the analysis tools share the stack's python.
    local py="python3"
    if [ -x "$MAMBA_ROOT/bin/python3" ]; then
        py="$MAMBA_ROOT/bin/python3"
    else
        check_command python3 || return 1
    fi
    if [ ! -d "$PYHEP_VENV" ]; then
        print_info "Creating Python venv at $PYHEP_VENV (using $py)..."
        "$py" -m venv "$PYHEP_VENV"
        "$PYHEP_VENV/bin/pip" install --upgrade pip wheel setuptools
        add_to_shell "# hepStack analysis Python tools: source \"$PYHEP_VENV/bin/activate\""
    fi
    return 0
}

# Build a "pkg==version" spec, or just "pkg" when the version is blank
pip_spec() {
    local pkg=$1 ver=$2
    if [ -n "$ver" ]; then echo "$pkg==$ver"; else echo "$pkg"; fi
}

# Idempotency guard for pip packages: skip if already present in the venv
# (and, when a version is pinned, only skip if that version matches).
pip_already_installed() {
    local pkg=$1 ver=$2 have
    [ "$FORCE_REINSTALL" -eq 1 ] && return 1
    [ -x "$PYHEP_VENV/bin/pip" ] || return 1
    have=$("$PYHEP_VENV/bin/pip" show "$pkg" 2>/dev/null | awk -F': ' '/^Version:/{print $2}')
    [ -z "$have" ] && return 1
    [ -n "$ver" ] && [ "$have" != "$ver" ] && return 1
    print_success "$pkg $have already installed — skipping (use --force to reinstall)."
    return 0
}

install_pyhf() {
    ensure_pyvenv || return 1
    pip_already_installed pyhf "$PYHF_VERSION" && return 0
    print_info "Installing pyhf ${PYHF_VERSION:-(latest)}..."
    "$PYHEP_VENV/bin/pip" install "$(pip_spec pyhf "$PYHF_VERSION")"
    print_success "pyhf installed successfully (in $PYHEP_VENV)"
}

install_spey() {
    ensure_pyvenv || return 1
    pip_already_installed spey "$SPEY_VERSION" && return 0
    print_info "Installing spey ${SPEY_VERSION:-(latest)}..."
    "$PYHEP_VENV/bin/pip" install "$(pip_spec spey "$SPEY_VERSION")"
    print_success "spey installed successfully (in $PYHEP_VENV)"
}

install_contur() {
    ensure_pyvenv || return 1
    pip_already_installed contur "$CONTUR_VERSION" && return 0
    print_info "Installing Contur ${CONTUR_VERSION:-(latest)}..."
    "$PYHEP_VENV/bin/pip" install "$(pip_spec contur "$CONTUR_VERSION")"
    print_warning "Contur needs Rivet/YODA at runtime — make sure Rivet is installed and sourced."
    print_success "Contur installed successfully (in $PYHEP_VENV)"
}

# Simple yes/no prompt
yes_no_prompt() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Report one package's real on-disk state plus what the installer will do with it.
show_package_status() {
    local key=$1 name=$2 version=$3
    local flagvar="INSTALL_$key"
    local selected="${!flagvar}"
    local status action

    if pkg_is_installed "$key"; then
        status="\033[32m✅ installed\033[0m"
        if [ "$selected" = "1" ]; then
            if [ "$FORCE_REINSTALL" -eq 1 ]; then
                action="\033[33m→ rebuild (--force)\033[0m"
            else
                action="→ skip (already installed)"
            fi
        else
            action="→ not selected"
        fi
    else
        status="\033[31m❌ not installed\033[0m"
        if [ "$selected" = "1" ]; then
            action="\033[34m→ will install\033[0m"
        else
            action="→ not selected"
        fi
    fi

    printf "  %-14s %-10s " "$name" "${version:-latest}"
    echo -e "${status}  ${action}"
}

# Show configuration
show_config() {
    echo
    print_info "Configuration Summary"
    echo "=========================================="
    print_info "Platform: $PLATFORM ($(read_config "$PLATFORM" "name"))"
    print_info "Architecture: $ARCH"
    print_info "Installation directory: $INSTALL_PREFIX"
    print_info "Build directory: $BUILD_DIR"
    print_info "Using $NPROC parallel jobs"
    echo
    print_info "Package status (checked against $INSTALL_PREFIX):"
    local i=0
    while [ "$i" -lt "${#PKG_KEYS[@]}" ]; do
        local key="${PKG_KEYS[$i]}"
        local vervar="${key}_VERSION"
        show_package_status "$key" "${PKG_LABELS[$i]}" "${!vervar}"
        i=$((i + 1))
    done
    echo
}

print_ascii_art() {
    echo
    echo "    ╭──────────────────────────────────────╮"
    echo "    │      🧪 PARTICLE PHYSICS STACK 🚀    │"
    echo "    │      ────────────────────────────    │"
    echo "    │        • ROOT Data Analysis          │"
    echo "    │        • Geant4 Simulation           │"
    echo "    │        • CLHEP Libraries             │"
    echo "    ╰──────────────────────────────────────╯"
    echo
}

# Interactive package selector — toggle INSTALL_<KEY> flags by number.
select_packages() {
    # Bypass when -y/--all was given, or when there is no interactive terminal.
    if [ "$ASSUME_YES" -eq 1 ]; then
        return
    fi
    if [ ! -t 0 ]; then
        print_warning "Non-interactive shell detected — installing per current flags."
        print_warning "Use -y/--all or the --no-<pkg> flags to control the selection."
        return
    fi

    local n=${#PKG_KEYS[@]}
    while true; do
        echo
        print_info "Select packages to install — toggle by number:"
        echo "=================================================="
        local i=0
        while [ "$i" -lt "$n" ]; do
            local key="${PKG_KEYS[$i]}"
            local flagvar="INSTALL_$key"
            local vervar="${key}_VERSION"
            local state="${!flagvar}"
            local ver="${!vervar}"
            local mark=" "
            [ "$state" = "1" ] && mark="x"
            printf "  %2d) [%s] %-14s %s\n" "$((i + 1))" "$mark" "${PKG_LABELS[$i]}" "${ver:-latest}"
            i=$((i + 1))
        done
        echo "--------------------------------------------------"
        echo "  a) select all      d) deselect all"
        echo "  i) install selected      q) quit"
        echo
        read -p "Toggle number(s) [e.g. 3 7 12], or a/d/i/q: " reply

        case "$reply" in
            "")            ;;                                   # just redisplay
            a|A)           for key in "${PKG_KEYS[@]}"; do eval "INSTALL_$key=1"; done ;;
            d|D|n|N)       for key in "${PKG_KEYS[@]}"; do eval "INSTALL_$key=0"; done ;;
            i|I|c|C|go|GO) break ;;
            q|Q)           print_info "Aborted by user — nothing installed."; exit 0 ;;
            *)
                local tok
                for tok in $(echo "$reply" | tr ',' ' '); do
                    if echo "$tok" | grep -qE '^[0-9]+$' && [ "$tok" -ge 1 ] && [ "$tok" -le "$n" ]; then
                        local key="${PKG_KEYS[$((tok - 1))]}"
                        local flagvar="INSTALL_$key"
                        if [ "${!flagvar}" = "1" ]; then
                            eval "INSTALL_$key=0"
                        else
                            eval "INSTALL_$key=1"
                        fi
                    else
                        print_warning "Ignoring invalid entry: $tok"
                    fi
                done
                ;;
        esac
    done

    # Nothing selected? Offer a graceful out.
    local any=0
    for key in "${PKG_KEYS[@]}"; do
        local flagvar="INSTALL_$key"
        [ "${!flagvar}" = "1" ] && any=1
    done
    if [ "$any" -eq 0 ]; then
        print_warning "No packages selected — nothing to install."
        exit 0
    fi
}

# ---------------------------------------------------------------------------
# Lmod modulefile generation
# ---------------------------------------------------------------------------

# Module name for a package KEY (a couple differ from the lowercased key).
module_name() {
    case "$1" in
        MAMBA)       echo "python-hepstack" ;;
        MADANALYSIS) echo "madanalysis5" ;;
        PYHF|SPEY|CONTUR) echo "hep-stats" ;;   # share one venv module
        *)           echo "$1" | tr '[:upper:]' '[:lower:]' ;;
    esac
}

# Write one Lua modulefile: $INSTALL_PREFIX/modulefiles/<name>/<version>.lua
# Uses Lmod's source_sh() to wrap the packages that ship a setup script
# (thisroot.sh, geant4.sh, rivetenv.sh, herwig activate).
write_modulefile() {
    local key=$1 label=$2 version=$3
    local name; name=$(module_name "$key")
    local dir="$MODULES_DIR/$name"
    mkdir -p "$dir"
    local mf="$dir/$version.lua"

    {
        echo "help([[${label} ${version} — hepStack]])"
        echo "whatis(\"${label} ${version} (hepStack)\")"
        echo "local root = \"${INSTALL_PREFIX}\""
    } > "$mf"

    case "$key" in
        MAMBA)
            echo 'prepend_path("PATH", pathJoin(root, "miniforge3/bin"))' >> "$mf" ;;
        CLHEP)
            cat >> "$mf" <<'LUA'
setenv("CLHEP_DIR", root)
setenv("CLHEP_BASE", root)
prepend_path("LD_LIBRARY_PATH", pathJoin(root, "lib"))
prepend_path("CMAKE_PREFIX_PATH", root)
LUA
            ;;
        ROOT)
            cat >> "$mf" <<'LUA'
source_sh("bash", pathJoin(root, "bin/thisroot.sh"))
prepend_path("CMAKE_PREFIX_PATH", root)
LUA
            ;;
        GEANT4)
            cat >> "$mf" <<'LUA'
setenv("GEANT4_DIR", root)
source_sh("bash", pathJoin(root, "bin/geant4.sh"))
prepend_path("CMAKE_PREFIX_PATH", root)
LUA
            ;;
        LHAPDF)
            cat >> "$mf" <<'LUA'
setenv("LHAPDF_DIR", root)
setenv("LHAPDF_DATA_PATH", pathJoin(root, "share/LHAPDF"))
prepend_path("PATH", pathJoin(root, "bin"))
prepend_path("LD_LIBRARY_PATH", pathJoin(root, "lib"))
prepend_path("PYTHONPATH", pathJoin(root, "lib"))
LUA
            ;;
        PYTHIA8)
            cat >> "$mf" <<'LUA'
setenv("PYTHIA8", root)
setenv("PYTHIA8DATA", pathJoin(root, "share/Pythia8/xmldoc"))
prepend_path("PATH", pathJoin(root, "bin"))
prepend_path("LD_LIBRARY_PATH", pathJoin(root, "lib"))
prepend_path("PYTHONPATH", pathJoin(root, "lib"))
LUA
            ;;
        DELPHES)
            cat >> "$mf" <<LUA
depends_on("root")
local dir = pathJoin(root, "Delphes-${version}")
setenv("DELPHES_DIR", dir)
prepend_path("PATH", dir)
prepend_path("LD_LIBRARY_PATH", dir)
prepend_path("ROOT_INCLUDE_PATH", pathJoin(dir, "external"))
LUA
            ;;
        MADGRAPH)
            cat >> "$mf" <<LUA
local dir = pathJoin(root, "MG5_aMC_v${version}")
setenv("MG5_DIR", dir)
prepend_path("PATH", pathJoin(dir, "bin"))
LUA
            ;;
        WHIZARD)
            cat >> "$mf" <<'LUA'
setenv("WHIZARD_DIR", root)
prepend_path("PATH", pathJoin(root, "bin"))
prepend_path("LD_LIBRARY_PATH", pathJoin(root, "lib"))
LUA
            ;;
        CALCHEP)
            cat >> "$mf" <<LUA
local dir = pathJoin(root, "calchep-${version}")
setenv("CALCHEP_DIR", dir)
prepend_path("PATH", dir)
LUA
            ;;
        HERWIG)
            cat >> "$mf" <<LUA
local dir = pathJoin(root, "herwig-${version}")
setenv("HERWIG_DIR", dir)
source_sh("bash", pathJoin(dir, "bin/activate"))
LUA
            ;;
        MADANALYSIS)
            cat >> "$mf" <<LUA
depends_on("root")
local dir = pathJoin(root, "madanalysis5-${version}")
setenv("MA5_DIR", dir)
prepend_path("PATH", pathJoin(dir, "bin"))
LUA
            ;;
        RIVET)
            echo 'source_sh("bash", pathJoin(root, "rivetenv.sh"))' >> "$mf" ;;
        CHECKMATE)
            cat >> "$mf" <<LUA
depends_on("root")
local dir = pathJoin(root, "checkmate2-${version}")
setenv("CHECKMATE_DIR", dir)
prepend_path("PATH", pathJoin(dir, "bin"))
LUA
            ;;
        PYHF|SPEY|CONTUR)
            echo 'prepend_path("PATH", pathJoin(root, "pyhep-venv/bin"))' >> "$mf" ;;
    esac
    print_success "modulefile: $mf"
}

# Generate modulefiles for every installed package + a `hepstack` meta-module.
generate_modulefiles() {
    print_info "Generating Lmod modulefiles under $MODULES_DIR ..."
    mkdir -p "$MODULES_DIR"

    local i=0 written=""
    while [ "$i" -lt "${#PKG_KEYS[@]}" ]; do
        local key="${PKG_KEYS[$i]}"
        local vervar="${key}_VERSION"
        if pkg_is_installed "$key"; then
            # hep-stats is shared by pyhf/spey/contur — only write it once.
            local name; name=$(module_name "$key")
            case " $written " in
                *" $name "*) : ;;
                *) write_modulefile "$key" "${PKG_LABELS[$i]}" "${!vervar:-latest}"
                   written="$written $name" ;;
            esac
        fi
        i=$((i + 1))
    done

    # Meta-module: `module load hepstack` pulls in the whole installed stack.
    mkdir -p "$MODULES_DIR/hepstack"
    {
        echo 'help([[hepStack — full phenomenology stack]])'
        echo 'whatis("hepStack meta-module: loads the full installed stack")'
        local seen=""
        for key in "${PKG_KEYS[@]}"; do
            if pkg_is_installed "$key"; then
                local n; n=$(module_name "$key")
                case " $seen " in *" $n "*) : ;; *) echo "depends_on(\"$n\")"; seen="$seen $n";; esac
            fi
        done
    } > "$MODULES_DIR/hepstack/1.0.lua"
    print_success "meta-module: $MODULES_DIR/hepstack/1.0.lua"

    register_modulepath
}

# Make MODULEPATH discoverable. For a standalone/user install we append a
# `module use` line to the shell rc; for a system-wide install use the
# /etc/profile.d snippet printed by the post-install summary instead.
register_modulepath() {
    local line="module use \"$MODULES_DIR\""
    local shell_rc="$HOME/.bashrc"
    case "$SHELL" in *zsh) shell_rc="$HOME/.zshrc" ;; esac
    [ -f "$shell_rc" ] || touch "$shell_rc"
    if ! grep -qF "$line" "$shell_rc" 2>/dev/null; then
        echo "$line" >> "$shell_rc"
        print_info "Added to $shell_rc: $line"
    fi
}

# Main installation routine
main() {
    # Recompute prefix-derived paths: -p/--prefix may have changed INSTALL_PREFIX
    # after the top-level assignments ran.
    MAMBA_ROOT="$INSTALL_PREFIX/miniforge3"
    PYHEP_VENV="$INSTALL_PREFIX/pyhep-venv"
    MODULES_DIR="$INSTALL_PREFIX/modulefiles"

    print_ascii_art
    select_packages
    show_config

    # Confirm before doing any heavy work
    if [ "$ASSUME_YES" -ne 1 ] && [ -t 0 ]; then
        yes_no_prompt "Proceed with the selection above?" || { print_info "Aborted."; exit 0; }
    fi

    # Create directories
    mkdir -p "$INSTALL_PREFIX" "$BUILD_DIR"

    # Now that the dirs exist, lock in fully canonical (symlink-resolved)
    # absolute paths, so every export written to the shell rc points at the real
    # physical location rather than a symlink that could later move or vanish.
    INSTALL_PREFIX=$(cd "$INSTALL_PREFIX" && pwd -P)
    BUILD_DIR=$(cd "$BUILD_DIR" && pwd -P)
    MAMBA_ROOT="$INSTALL_PREFIX/miniforge3"
    PYHEP_VENV="$INSTALL_PREFIX/pyhep-venv"
    MODULES_DIR="$INSTALL_PREFIX/modulefiles"

    # Make freshly-installed tools discoverable to later builds in this same run
    # (root-config, lhapdf-config, pythia8 headers, etc.). Persistent environment
    # is delivered afterwards via generated modulefiles (or ~/.bashrc when
    # --no-modules is given).
    export PATH="$INSTALL_PREFIX/bin:$PATH"
    export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:${LD_LIBRARY_PATH:-}"
    export DYLD_LIBRARY_PATH="$INSTALL_PREFIX/lib:${DYLD_LIBRARY_PATH:-}"

    # Install system dependencies
    if yes_no_prompt "Install system dependencies?"; then
        install_system_deps
    fi
    
    # Check required commands
    check_command cmake || exit 1
    check_command ninja || {
        print_warning "Ninja not found, using make instead"
        NPROC=1  # Reduce parallel jobs for make
    }
    
    # Install packages
    # Python first: ROOT (PyROOT), LHAPDF bindings, MadGraph, MadAnalysis5 and
    # the pip tools all pick up whichever python3 is first on PATH.
    if [ "$INSTALL_MAMBA" -eq 1 ]; then
        install_mamba
    fi

    if [ "$INSTALL_CLHEP" -eq 1 ]; then
        install_clhep
    fi
    
    if [ "$INSTALL_ROOT" -eq 1 ]; then
        install_root
    fi
    
    if [ "$INSTALL_GEANT4" -eq 1 ]; then
        install_geant4
    fi

    # --- Phenomenology / generator chain (order matters) ---
    if [ "$INSTALL_LHAPDF" -eq 1 ]; then
        install_lhapdf
    fi

    if [ "$INSTALL_PYTHIA8" -eq 1 ]; then
        install_pythia8
    fi

    if [ "$INSTALL_DELPHES" -eq 1 ]; then
        install_delphes
    fi

    if [ "$INSTALL_MADGRAPH" -eq 1 ]; then
        install_madgraph
    fi

    if [ "$INSTALL_WHIZARD" -eq 1 ]; then
        install_whizard
    fi

    if [ "$INSTALL_CALCHEP" -eq 1 ]; then
        install_calchep
    fi

    if [ "$INSTALL_HERWIG" -eq 1 ]; then
        install_herwig
    fi

    # --- Analysis, recasting & limits ---
    if [ "$INSTALL_MADANALYSIS" -eq 1 ]; then
        install_madanalysis5
    fi

    if [ "$INSTALL_RIVET" -eq 1 ]; then
        install_rivet
    fi

    if [ "$INSTALL_CHECKMATE" -eq 1 ]; then
        install_checkmate
    fi

    if [ "$INSTALL_PYHF" -eq 1 ]; then
        install_pyhf
    fi

    if [ "$INSTALL_SPEY" -eq 1 ]; then
        install_spey
    fi

    if [ "$INSTALL_CONTUR" -eq 1 ]; then
        install_contur
    fi

    # Deliver the environment: modulefiles (default) or shell rc (--no-modules).
    if [ "$USE_MODULES" -eq 1 ]; then
        generate_modulefiles
    fi

    # Final summary
    echo
    print_success "Installation completed!"
    echo
    echo "=========================================="
    echo "INSTALLATION SUMMARY"
    echo "=========================================="
    echo "Installation directory: $INSTALL_PREFIX"
    [ "$INSTALL_MAMBA" -eq 1 ] && echo "✓ Miniforge/mamba ${MAMBA_VERSION:-latest} (python $PYTHON_VERSION)"
    [ "$INSTALL_CLHEP" -eq 1 ] && echo "✓ CLHEP $CLHEP_VERSION"
    [ "$INSTALL_ROOT" -eq 1 ] && echo "✓ ROOT $ROOT_VERSION"
    [ "$INSTALL_GEANT4" -eq 1 ] && echo "✓ Geant4 $GEANT4_VERSION"
    [ "$INSTALL_LHAPDF" -eq 1 ] && echo "✓ LHAPDF $LHAPDF_VERSION"
    [ "$INSTALL_PYTHIA8" -eq 1 ] && echo "✓ Pythia8 $PYTHIA8_VERSION"
    [ "$INSTALL_DELPHES" -eq 1 ] && echo "✓ Delphes $DELPHES_VERSION"
    [ "$INSTALL_MADGRAPH" -eq 1 ] && echo "✓ MadGraph $MADGRAPH_VERSION"
    [ "$INSTALL_WHIZARD" -eq 1 ] && echo "✓ WHIZARD $WHIZARD_VERSION"
    [ "$INSTALL_CALCHEP" -eq 1 ] && echo "✓ CalcHEP $CALCHEP_VERSION"
    [ "$INSTALL_HERWIG" -eq 1 ] && echo "✓ Herwig7 $HERWIG_VERSION"
    [ "$INSTALL_MADANALYSIS" -eq 1 ] && echo "✓ MadAnalysis5 $MADANALYSIS_VERSION"
    [ "$INSTALL_RIVET" -eq 1 ] && echo "✓ Rivet $RIVET_VERSION"
    [ "$INSTALL_CHECKMATE" -eq 1 ] && echo "✓ CheckMATE $CHECKMATE_VERSION"
    [ "$INSTALL_PYHF" -eq 1 ] && echo "✓ pyhf ${PYHF_VERSION:-latest}"
    [ "$INSTALL_SPEY" -eq 1 ] && echo "✓ spey ${SPEY_VERSION:-latest}"
    [ "$INSTALL_CONTUR" -eq 1 ] && echo "✓ Contur ${CONTUR_VERSION:-latest}"
    echo
    print_info "Next steps:"
    if [ "$USE_MODULES" -eq 1 ]; then
        echo "Environment is delivered via Lmod modulefiles in:"
        echo "    $MODULES_DIR"
        echo
        echo "1. Make sure Lmod is installed (module command available):"
        echo "     Debian/Ubuntu: sudo apt install lmod   |   RHEL/Fedora: sudo dnf install Lmod"
        echo "     macOS: brew install lmod"
        echo "2. Expose the modules (a 'module use' line was added to your shell rc):"
        echo "     module use \"$MODULES_DIR\""
        echo "   System-wide instead: create /etc/profile.d/z00-hepstack.sh containing that line."
        echo "3. Load and verify:"
        echo "     module avail"
        echo "     module load hepstack        # or: module load root pythia8 delphes"
        echo "     root --version ; geant4-config --version"
        echo
        echo "Users can add their own software under \$HOME/hepstack/modulefiles and run"
        echo "  'module use \$HOME/hepstack/modulefiles' to layer it on top of this stack."
    else
        echo "1. Restart your terminal or run: source ~/.bashrc"
        echo "2. Verify installation by running: root --version"
        echo "3. Test Geant4: geant4-config --version"
    fi
    echo
    print_warning "If you encounter issues, set DEBUG=1 and rerun for verbose output"
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        -p|--prefix)
            INSTALL_PREFIX=$(abspath "$2" "$CWD")
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -p, --prefix DIR    Installation directory (default: $DEFAULT_PREFIX)"
            echo "  -h, --help         Show this help message"
            echo "  -y, --yes, --all   Skip the interactive menu; install everything selected"
            echo "  -f, --force        Rebuild even if a package is already installed"
            echo "  --no-modules       Deliver env via ~/.bashrc instead of Lmod modulefiles"
            echo "  --gen-modules      (Re)generate modulefiles for what's installed, then exit"
            echo "  --no-mamba        Skip Miniforge/mamba (use system python3 instead)"
            echo "  --no-root         Skip ROOT installation"
            echo "  --no-geant4       Skip Geant4 installation"
            echo "  --no-clhep        Skip CLHEP installation"
            echo "  --no-lhapdf       Skip LHAPDF installation"
            echo "  --no-pythia8      Skip Pythia8 installation"
            echo "  --no-delphes      Skip Delphes installation"
            echo "  --no-madgraph     Skip MadGraph installation"
            echo "  --no-whizard      Skip WHIZARD installation"
            echo "  --no-calchep      Skip CalcHEP installation"
            echo "  --no-herwig       Skip Herwig7 installation"
            echo "  --no-madanalysis  Skip MadAnalysis5 installation"
            echo "  --no-rivet        Skip Rivet installation"
            echo "  --no-checkmate    Skip CheckMATE installation"
            echo "  --no-pyhf         Skip pyhf installation"
            echo "  --no-spey         Skip spey installation"
            echo "  --no-contur       Skip Contur installation"
            echo "  --show-config     Show current configuration"
            echo
            echo "Environment variables:"
            echo "  INSTALL_PREFIX    Set installation directory"
            echo "  ROOT_VERSION      Set ROOT version"
            echo "  GEANT4_VERSION    Set Geant4 version"
            echo
            echo "Configuration file: $CONFIG_FILE"
            exit 0
            ;;
        -y|--yes|--all)
            ASSUME_YES=1
            shift
            ;;
        -f|--force)
            FORCE_REINSTALL=1
            shift
            ;;
        --no-modules)
            USE_MODULES=0
            shift
            ;;
        --gen-modules)
            MAMBA_ROOT="$INSTALL_PREFIX/miniforge3"
            PYHEP_VENV="$INSTALL_PREFIX/pyhep-venv"
            MODULES_DIR="$INSTALL_PREFIX/modulefiles"
            generate_modulefiles
            exit 0
            ;;
        --no-root)
            INSTALL_ROOT=0
            shift
            ;;
        --no-geant4)
            INSTALL_GEANT4=0
            shift
            ;;
        --no-clhep)
            INSTALL_CLHEP=0
            shift
            ;;
        --no-mamba)
            INSTALL_MAMBA=0
            shift
            ;;
        --no-lhapdf)
            INSTALL_LHAPDF=0
            shift
            ;;
        --no-pythia8)
            INSTALL_PYTHIA8=0
            shift
            ;;
        --no-delphes)
            INSTALL_DELPHES=0
            shift
            ;;
        --no-madgraph)
            INSTALL_MADGRAPH=0
            shift
            ;;
        --no-whizard)
            INSTALL_WHIZARD=0
            shift
            ;;
        --no-calchep)
            INSTALL_CALCHEP=0
            shift
            ;;
        --no-herwig)
            INSTALL_HERWIG=0
            shift
            ;;
        --no-madanalysis)
            INSTALL_MADANALYSIS=0
            shift
            ;;
        --no-rivet)
            INSTALL_RIVET=0
            shift
            ;;
        --no-checkmate)
            INSTALL_CHECKMATE=0
            shift
            ;;
        --no-pyhf)
            INSTALL_PYHF=0
            shift
            ;;
        --no-spey)
            INSTALL_SPEY=0
            shift
            ;;
        --no-contur)
            INSTALL_CONTUR=0
            shift
            ;;
        --show-config)
            MAMBA_ROOT="$INSTALL_PREFIX/miniforge3"
            PYHEP_VENV="$INSTALL_PREFIX/pyhep-venv"
            show_config
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"
