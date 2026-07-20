# Particle Physics Software Stack Installer

A comprehensive bash script to install ROOT, Geant4, and CLHEP for particle physics simulation and data analysis.

For now.

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

Core stack:
- ROOT: 6.38.06 (Data analysis framework)
- Geant4: 11.3.2 (Particle physics simulation)
- CLHEP: 2.4.7.1 (High Energy Physics library)

Phenomenology / generator chain (built in this order):
- LHAPDF: 6.5.4 (PDF sets — used by Pythia8, MadGraph, WHIZARD)
- Pythia8: 8312 (parton shower + hadronization; links LHAPDF)
- Delphes: 3.5.1 (fast detector simulation; needs ROOT, links Pythia8)
- MadGraph5_aMC@NLO: 3.7.2 (matrix-element event generator)
- WHIZARD: 3.1.5 (lepton-collider event generator; needs OCaml + gfortran)
- CalcHEP: 3.8.10 (matrix-element generator; CompHEP successor)
- Herwig7: 7.3.0 (angular-ordered shower generator; built via herwig-bootstrap — slow)

Analysis, recasting & limits:
- MadAnalysis5: 1.10.12 (cut-flow analysis + LHC recasting)
- Rivet: 3.1.10 (analysis preservation; built via rivet-bootstrap with HepMC3/YODA/fastjet)
- CheckMATE: 2.0.37 (recast against existing LHC searches; wires ROOT+Delphes+Pythia8+MadGraph)
- pyhf, spey, Contur (statistics/limits — installed into a Python venv at `local/pyhep-venv`)

# Run the installer

## One dragon installation

```bash
./starterpack.sh
```

By default this opens an **interactive package selector**. Every package starts
selected `[x]`; toggle any of them by number, then install:

```text
ℹ INFO: Select packages to install — toggle by number:
==================================================
   1) [x] CLHEP          2.4.7.1
   2) [x] ROOT           6.38.06
   3) [x] Geant4         11.3.2
   ...
  16) [x] Contur         3.0.0
--------------------------------------------------
  a) select all      d) deselect all
  i) install selected      q) quit

Toggle number(s) [e.g. 3 7 12], or a/d/i/q:
```

- Type one or more numbers (space- or comma-separated) to flip those packages on/off.
- `a` selects all, `d` deselects all, `i` installs the current selection, `q` quits.
- To skip the menu and install everything non-interactively, pass `-y` / `--all`.
- The menu is auto-skipped in a non-interactive shell (piped/CI); use `-y` or the
  `--no-<pkg>` flags / `INSTALL_<PKG>=0` env vars there.

**Idempotent installs:** a selected package that is already installed is detected
and skipped (no re-download, no rebuild) — so re-running the installer only builds
what is missing. Pass `-f` / `--force` to rebuild everything selected regardless.

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
./starterpack.sh --no-lhapdf        # Skip LHAPDF
./starterpack.sh --no-pythia8       # Skip Pythia8
./starterpack.sh --no-delphes       # Skip Delphes
./starterpack.sh --no-madgraph      # Skip MadGraph
./starterpack.sh --no-whizard       # Skip WHIZARD
./starterpack.sh --no-calchep       # Skip CalcHEP
./starterpack.sh --no-herwig        # Skip Herwig7
./starterpack.sh --no-madanalysis   # Skip MadAnalysis5
./starterpack.sh --no-rivet         # Skip Rivet
./starterpack.sh --no-checkmate     # Skip CheckMATE
./starterpack.sh --no-pyhf          # Skip pyhf
./starterpack.sh --no-spey          # Skip spey
./starterpack.sh --no-contur        # Skip Contur
./starterpack.sh --show-config      # Show config only
```

Example — build only the generator chain (assumes ROOT is already installed):

```bash
INSTALL_ROOT=0 INSTALL_CLHEP=0 INSTALL_GEANT4=0 ./starterpack.sh
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


