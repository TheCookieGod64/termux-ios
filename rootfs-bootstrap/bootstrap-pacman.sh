#!/usr/bin/env bash
#
# bootstrap-pacman.sh - Termux-iOS Pacman & /var/jb Rootfs Bootstrap
# Target: iPhone 8 | iOS 15/16 | palera1n Rootless | TrollStore
#
# Sets up /var/jb as an Arch-compatible pacman environment,
# replaces apt, and configures default Termux-iOS directories.
#

set -e

JB_ROOT="${JB_ROOT:-/var/jb}"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}========================================================================${RESET}"
echo -e "${CYAN}${BOLD}     Termux-iOS Pacman & /var/jb Bootstrap for iPhone 8 (palera1n)      ${RESET}"
echo -e "${CYAN}${BOLD}========================================================================${RESET}"
echo ""

# Ensure we have permission or are running in an appropriate rootfs
if [ ! -d "$JB_ROOT" ]; then
    echo -e "${YELLOW}[!] Directory $JB_ROOT not found. Creating target root directory...${RESET}"
    mkdir -p "$JB_ROOT"
fi

echo -e "${GREEN}[+] Setting up Pacman filesystem structure in ${BOLD}$JB_ROOT${RESET}..."
mkdir -p "$JB_ROOT/etc/pacman.d/gnupg"
mkdir -p "$JB_ROOT/etc/pacman.d/hooks"
mkdir -p "$JB_ROOT/var/lib/pacman/local"
mkdir -p "$JB_ROOT/var/lib/pacman/sync"
mkdir -p "$JB_ROOT/var/cache/pacman/pkg"
mkdir -p "$JB_ROOT/var/log"
mkdir -p "$JB_ROOT/usr/bin"
mkdir -p "$JB_ROOT/usr/lib"
mkdir -p "$JB_ROOT/usr/share"
mkdir -p "$JB_ROOT/var/mobile"
mkdir -p "$JB_ROOT/root"

# Copy pacman configuration files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${GREEN}[+] Installing pacman.conf and mirrorlist...${RESET}"
install -m 644 "$SCRIPT_DIR/pacman.conf" "$JB_ROOT/etc/pacman.conf"
install -m 644 "$SCRIPT_DIR/mirrorlist" "$JB_ROOT/etc/pacman.d/mirrorlist"

# Install pkg wrapper and apt guards
echo -e "${GREEN}[+] Installing Termux 'pkg' CLI wrapper...${RESET}"
install -m 755 "$SCRIPT_DIR/pkg" "$JB_ROOT/usr/bin/pkg"

echo -e "${GREEN}[+] Installing protective 'apt' & 'apt-get' wrappers (no-apt policy)...${RESET}"
install -m 755 "$SCRIPT_DIR/apt" "$JB_ROOT/usr/bin/apt"
install -m 755 "$SCRIPT_DIR/apt-get" "$JB_ROOT/usr/bin/apt-get"

# Disarm any existing apt sources if present
if [ -d "$JB_ROOT/etc/apt" ]; then
    echo -e "${YELLOW}[!] Existing apt directory detected in $JB_ROOT/etc/apt. Renaming to disable apt...${RESET}"
    mv -f "$JB_ROOT/etc/apt" "$JB_ROOT/etc/apt.disabled.by.termux-ios" 2>/dev/null || true
fi

# Initialize default mobile user .termux configuration
TERMUX_DIR="$JB_ROOT/var/mobile/.termux"
echo -e "${GREEN}[+] Creating default Termux-iOS user configuration in $TERMUX_DIR...${RESET}"
mkdir -p "$TERMUX_DIR"

cat << 'EOF' > "$TERMUX_DIR/termux.properties"
# Termux-iOS Configuration File (~/.termux/termux.properties)
# Target: iPhone 8 | iOS 15/16 | palera1n | TrollStore

# Extra keys toolbar over the iOS keyboard
extra-keys = [['ESC','TAB','CTRL','ALT','-','/','|','UP','DOWN','LEFT','RIGHT','HOME','END','PGUP','PGDN']]

# Terminal cursor styling: block, underline, bar
cursor-style = block
cursor-blink = true

# Terminal audio bell
bell-character = ignore

# Default package manager inside /var/jb chroot
pkg-manager = pacman
EOF

chmod 644 "$TERMUX_DIR/termux.properties"

# Also link into /root/.termux for root login sessions
mkdir -p "$JB_ROOT/root/.termux"
cp -f "$TERMUX_DIR/termux.properties" "$JB_ROOT/root/.termux/termux.properties"

echo ""
echo -e "${GREEN}${BOLD}[✔] Termux-iOS Pacman bootstrap completed successfully in $JB_ROOT!${RESET}"
echo -e "    - Package manager : ${BOLD}pacman${RESET} (apt disabled)"
echo -e "    - Package wrapper : ${BOLD}$JB_ROOT/usr/bin/pkg${RESET}"
echo -e "    - Config file     : ${BOLD}$TERMUX_DIR/termux.properties${RESET}"
echo -e "${CYAN}${BOLD}========================================================================${RESET}"
