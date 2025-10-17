# Physics Software Stack Installer

A comprehensive bash script to install ROOT, Geant4, and CLHEP for particle physics simulation and data analysis.

## 🚀 Quick Start

```bash
# Download the installer and configuration file
# Make the script executable
chmod +x starterpack.sh
```

## 📋 Platform

## macOS
- Homebrew (automatically installed if missing)
- Xcode Command Line Tools

## Linux
- Basic build tools (gcc, g++, make)

## 🛠️  Features

- Cross-Platform: macOS, Ubuntu, Debian, RedHat, CentOS, Fedora, Arch
- Auto-Dependency Management: Installs system dependencies automatically
- Parallel Builds: Uses all CPU cores
- Error Handling: Comprehensive error checking
- Smart Detection: Uses system libraries when available

## 📦 Pinned Software Versions

- ROOT: 6.32.08 (Data analysis framework)
- Geant4: 11.3.2 (Particle physics simulation)
- CLHEP: 2.4.7.1 (High Energy Physics library)

# Run the installer

## One dragon installation

```bash
./starterpack.sh
```

## Individual installation
The script can install each component separately:
```bash
# Install only ROOT
INSTALL_GEANT4=0 INSTALL_CLHEP=0 ./starterpack.sh

# Install only Geant4 (requires ROOT and CLHEP)
INSTALL_ROOT=0 ./starterpack.sh
```

## ⚙️  Installation Options

### Command Line Arguments

```bash
./starterpack.sh --prefix /custom/path
./starterpack.sh --no-root          # Skip ROOT
./starterpack.sh --no-geant4        # Skip Geant4
./starterpack.sh --no-clhep         # Skip CLHEP
./starterpack.sh --show-config      # Show config only
```

### Environment Variables

```bash
export INSTALL_PREFIX="/custom/path"
export INSTALL_ROOT=0           # Use system version, else specify your favourite version
export INSTALL_GEANT4=0         # Use system version, else specify your favourite version
export INSTALL_CLHEP=0          # Use system version, else specify your favourite version
./starterpack.sh
```


## 📁 Directory Structure

```text
MuonToolKits/
├── starterpack.sh             # Main installer
├── dependencies.conf          # Configuration
└── patch/                     # Optional patches
```

## 🧪 Verification

```bash
source ~/.bashrc
root --version
geant4-config --version
```

## 🔄 Updates

Edit ```dependencies.conf``` with new versions and rerun the installer.

## 📚 Documentation

- [ROOT Documentation](https://root.cern/install/build_from_source/)
- [Geant4 Documentation](https://geant4.web.cern.ch)
- [CLHEP](https://proj-clhep.web.cern.ch/proj-clhep/)

## 🤝 Contributing
To contribute to this installer:

1. Fork the repository
2. Make your changes
3. Test on multiple platforms
4. Submit a pull request

## 📞 Support

1. Run with debug: ```DEBUG=1 ./install_physics_stack.sh```
2. Check individual software documentation 📚 :
  - [ROOT Documentation](https://root.cern/install/build_from_source/)
  - [Geant4 Documentation](https://geant4.web.cern.ch)
  - [CLHEP](https://proj-clhep.web.cern.ch/proj-clhep/)
    
#
Note: This installer is designed for research and educational use. Always verify installations in your specific environment before using for production work.


