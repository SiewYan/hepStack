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

# Configuration file
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dependencies.conf"
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

# Default configuration
CWD=$(pwd)
INSTALL_PREFIX="${INSTALL_PREFIX:-$CWD/$DEFAULT_PREFIX}"
BUILD_DIR="${BUILD_DIR:-$CWD/$DEFAULT_BUILD_DIR}"
NPROC=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Installation flags
INSTALL_ROOT="${INSTALL_ROOT:-1}"
INSTALL_CLHEP="${INSTALL_CLHEP:-1}"
INSTALL_GEANT4="${INSTALL_GEANT4:-1}"

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

add_to_shell() {
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
install_clhep() {
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
	"-DCMAKE_POLICY_DEFAULT_CMP0175=OLD"
	"-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
        "-Dbuiltin_gsl=ON"
        "-Dbuiltin_fftw3=ON"
        "-Dbuiltin_cfitsio=ON"
        "-Dbuiltin_openssl=ON"
        "-Droofit=ON"
        "-Dgdml=ON"
        "-Dminuit2=ON"
    )
    
    # Platform-specific options
    case $PLATFORM in
        macos)
            CMAKE_OPTIONS+=("-Dcocoa=ON" "-Dx11=OFF")
            ;;
        *)
            CMAKE_OPTIONS+=("-Dx11=ON")
            ;;
    esac
    
    # Join array into string and execute
    local cmake_cmd="cmake -G Ninja ${CMAKE_OPTIONS[@]} ../$root_dir"
    echo $cmake_cmd
    eval $cmake_cmd

    # patch/intervention
    # Patch VDT's CMakeLists.txt if it exists
    # CMAKE issue
    CMAKE_VDT="${BUILD_DIR}/forRoot/build/VDT-prefix/src/VDT-stamp/VDT-configure-Release.cmake"
    if [ -f "${CMAKE_VDT}" ]; then
        print_info "Patching VDT configuration..."
	
        #patch --dry-run --verbose ${CMAKE_VDT} < ${CWD}/patch/VDT-configure-Release.cmake.patch
	patch ${CMAKE_VDT} < ${CWD}/patch/VDT-configure-Release.cmake.patch
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
    print_info "Installing Geant4 v$GEANT4_VERSION..."
    
    cd "$BUILD_DIR"
    local geant4_dir="geant4-$GEANT4_VERSION"

    if [ ! -d "$geant4_dir" ]; then
        download_and_extract \
            "https://gitlab.cern.ch/geant4/geant4/-/archive/v$GEANT4_VERSION/geant4-v$GEANT4_VERSION.tar.gz" \
            "$geant4_dir"
    fi
    
    cd "$geant4_dir"
    
    # Build cmake options array
    CMAKE_OPTIONS=(
        "-DGEANT4_BUILD_MULTITHREADED=ON"
	"-DGEANT4_INSTALL_DATA=ON"
	"-DGEANT4_USE_QT=ON"
	"-DGEANT4_USE_OPENGL_X11=ON"
        "-DGEANT4_USE_SYSTEM_CLHEP=ON"
        "-DGEANT4_USE_SYSTEM_EXPAT=ON"
        "-DGEANT4_USE_SYSTEM_ZLIB=ON"
	"-DGEANT4_USE_ROOT=ON"
    )
    
    # Platform-specific options
    #case $PLATFORM in
    #    macos)
    #        CMAKE_OPTIONS+=("-DGEANT4_USE_OPENGL_X11=OFF")
    #        ;;
    #    *)
    #        CMAKE_OPTIONS+=("-DGEANT4_USE_OPENGL_X11=ON")
    #        ;;
    #esac
    
    # Join array into string and execute
    cmake_build "$BUILD_DIR/$geant4_dir" "${CMAKE_OPTIONS[@]}"
    
    add_to_shell "export GEANT4_DIR=\"$INSTALL_PREFIX\""
    add_to_shell "export GEANT4_INSTALL=\"$INSTALL_PREFIX\""
    add_to_shell "source \"\$GEANT4_DIR/bin/geant4.sh\""
    
    print_success "Geant4 installed successfully"
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

show_package_status() {
    local package_name=$1
    local package_version=$2
    local install_flag=$3
    local check_command=$4
    
    if [ "$install_flag" = "0" ]; then
        echo -e "  ${package_name}: ${package_version} \033[32m✅ (system)\033[0m"
    else
        echo -e "  ${package_name}: ${package_version} \033[31m❌ (not found)\033[0m"
    fi
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
    print_info "Package Versions:"
    show_package_status "ROOT" "$ROOT_VERSION" "$INSTALL_ROOT"
    show_package_status "CLHEP" "$CLHEP_VERSION" "$INSTALL_CLHEP"
    show_package_status "Geant4" "$GEANT4_VERSION" "$INSTALL_GEANT4"
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

# Main installation routine
main() {
    print_ascii_art
    show_config
    
    # Create directories
    mkdir -p "$INSTALL_PREFIX" "$BUILD_DIR"
    
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
    if [ "$INSTALL_CLHEP" -eq 1 ]; then
        install_clhep
    fi
    
    if [ "$INSTALL_ROOT" -eq 1 ]; then
        install_root
    fi
    
    if [ "$INSTALL_GEANT4" -eq 1 ]; then
        install_geant4
    fi
    
    # Final summary
    echo
    print_success "Installation completed!"
    echo
    echo "=========================================="
    echo "INSTALLATION SUMMARY"
    echo "=========================================="
    echo "Installation directory: $INSTALL_PREFIX"
    [ "$INSTALL_CLHEP" -eq 1 ] && echo "✓ CLHEP $CLHEP_VERSION"
    [ "$INSTALL_ROOT" -eq 1 ] && echo "✓ ROOT $ROOT_VERSION"
    [ "$INSTALL_GEANT4" -eq 1 ] && echo "✓ Geant4 $GEANT4_VERSION"
    echo
    print_info "Next steps:"
    echo "1. Restart your terminal or run: source ~/.bashrc"
    echo "2. Verify installation by running: root --version"
    echo "3. Test Geant4: geant4-config --version"
    echo
    print_warning "If you encounter issues, set DEBUG=1 and rerun for verbose output"
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        -p|--prefix)
            INSTALL_PREFIX="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  -p, --prefix DIR    Installation directory (default: $DEFAULT_PREFIX)"
            echo "  -h, --help         Show this help message"
            echo "  --no-root         Skip ROOT installation"
            echo "  --no-geant4       Skip Geant4 installation"
            echo "  --no-clhep        Skip CLHEP installation"
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
        --show-config)
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
