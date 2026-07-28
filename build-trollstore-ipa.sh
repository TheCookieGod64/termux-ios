#!/usr/bin/env bash
#
# build-trollstore-ipa.sh
# Automated TrollStore IPA / TIPA Builder for Termux-iOS
# Target: iPhone 8 | iOS 15/16 | palera1n (/var/jb) | pacman
#

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="Termux-iOS"
APP_BUNDLE_NAME="Termux.app"
APP_DIR="$DIST_DIR/Payload/$APP_BUNDLE_NAME"

echo -e "${CYAN}${BOLD}========================================================================${RESET}"
echo -e "${CYAN}${BOLD}       Termux-iOS TrollStore .TIPA / .IPA Builder (iPhone 8)            ${RESET}"
echo -e "${CYAN}${BOLD}========================================================================${RESET}"
echo ""

# 1. Prepare dist directory
echo -e "${GREEN}[+] Cleaning and creating build distribution directory...${RESET}"
rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/rootfs-bootstrap"
mkdir -p "$APP_DIR/termux-tools"

# 2. Compile jb-chroot C binary
echo -e "${GREEN}[+] Compiling native /var/jb chroot helper (jb-chroot)...${RESET}"
if command -v xcrun >/dev/null 2>&1 && xcrun -find clang >/dev/null 2>&1; then
    echo -e "    -> Using iOS SDK cross-compiler..."
    make -C "$SCRIPT_DIR/src/jb-chroot" ios
else
    echo -e "    -> Using default C compiler (host/fallback)..."
    make -C "$SCRIPT_DIR/src/jb-chroot" clean all
fi
install -m 755 "$SCRIPT_DIR/src/jb-chroot/jb-chroot" "$APP_DIR/jb-chroot"

# 3. Bundle Pacman bootstrap and Termux CLI utilities
echo -e "${GREEN}[+] Bundling Pacman bootstrap scripts and protective apt wrappers...${RESET}"
cp -a "$SCRIPT_DIR/rootfs-bootstrap/"* "$APP_DIR/rootfs-bootstrap/"
chmod +x "$APP_DIR/rootfs-bootstrap/bootstrap-pacman.sh"
chmod +x "$APP_DIR/rootfs-bootstrap/pkg"
chmod +x "$APP_DIR/rootfs-bootstrap/apt"
chmod +x "$APP_DIR/rootfs-bootstrap/apt-get"

echo -e "${GREEN}[+] Bundling Termux-iOS CLI tools (termux-info, termux-reload-settings, etc.)...${RESET}"
cp -a "$SCRIPT_DIR/termux-tools/"* "$APP_DIR/termux-tools/"
chmod +x "$APP_DIR/termux-tools/"*

# 4. Copy Info.plist and Entitlements
echo -e "${GREEN}[+] Copying Info.plist and TrollStore Entitlements...${RESET}"
cp "$SCRIPT_DIR/trollstore/Info.plist" "$APP_DIR/Info.plist"
cp "$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/Entitlements.plist"

# 5. Build iOS App binary if xcodebuild is present
if command -v xcodebuild >/dev/null 2>&1; then
    echo -e "${GREEN}[+] Building Xcode project for iPhone 8 (iOS 15.0+)...${RESET}"
    xcodebuild -project "$SCRIPT_DIR/Termux-iOS.xcodeproj" \
               -target "Termux-iOS" \
               -configuration Release \
               -sdk iphoneos \
               CONFIGURATION_BUILD_DIR="$DIST_DIR/xcode_out" \
               CODE_SIGN_IDENTITY="" \
               CODE_SIGNING_REQUIRED=NO \
               CODE_SIGNING_ALLOWED=NO \
               quiet || true
    
    if [ -f "$DIST_DIR/xcode_out/Termux-iOS.app/Termux-iOS" ]; then
        cp -a "$DIST_DIR/xcode_out/Termux-iOS.app/"* "$APP_DIR/"
    fi
else
    echo -e "${YELLOW}[!] Xcode not found on host. Creating TrollStore launcher script stub for inspection/testing...${RESET}"
    cat << 'EOF' > "$APP_DIR/Termux-iOS"
#!/usr/bin/env bash
# Termux-iOS Shell Launcher Stub
exec "$(dirname "$0")/jb-chroot"
EOF
    chmod +x "$APP_DIR/Termux-iOS"
fi

# 6. Apply TrollStore codesigning entitlements if ldid is available
if command -v ldid >/dev/null 2>&1; then
    echo -e "${GREEN}[+] Signing application bundle with TrollStore entitlements using ldid...${RESET}"
    ldid -S"$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/Termux-iOS" 2>/dev/null || true
    ldid -S"$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/jb-chroot" 2>/dev/null || true
else
    echo -e "${YELLOW}[!] 'ldid' tool not found on host; skipping local pseudo-sign. TrollStore will automatically apply entitlements upon installation.${RESET}"
fi

# 7. Package Payload into .ipa and .tipa
echo -e "${GREEN}[+] Creating TrollStore package archives (.tipa and .ipa)...${RESET}"
cd "$DIST_DIR"
if command -v zip >/dev/null 2>&1; then
    zip -qry9 "Termux-iOS.ipa" "Payload"
    cp "Termux-iOS.ipa" "Termux-iOS.tipa"
elif command -v tar >/dev/null 2>&1; then
    # Fallback if zip is not present
    tar -cf "Termux-iOS.tar" "Payload"
fi
cd "$SCRIPT_DIR"

echo ""
echo -e "${GREEN}${BOLD}[✔] Build Complete!${RESET}"
if [ -f "$DIST_DIR/Termux-iOS.tipa" ]; then
    echo -e "    * TrollStore TIPA : ${BOLD}$DIST_DIR/Termux-iOS.tipa${RESET}"
    echo -e "    * Standard IPA    : ${BOLD}$DIST_DIR/Termux-iOS.ipa${RESET}"
else
    echo -e "    * App Bundle      : ${BOLD}$APP_DIR${RESET}"
fi
echo -e "${CYAN}${BOLD}========================================================================${RESET}"
echo -e "Installation Instructions for iPhone 8 (palera1n):"
echo -e "  1. Transfer ${BOLD}Termux-iOS.tipa${RESET} to your iPhone 8."
echo -e "  2. Open with ${BOLD}TrollStore${RESET} and tap 'Install'."
echo -e "  3. Open Termux on your homescreen to launch into /var/jb with pacman!"
echo -e "${CYAN}${BOLD}========================================================================${RESET}"
