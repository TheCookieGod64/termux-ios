#!/usr/bin/env bash
#
# build-trollstore-ipa.sh
# Automated TrollStore IPA / TIPA Builder for JITAllower
# Target: iPhone 8 | iOS 15/16 | palera1n (/var/jb) | TrollStore
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
APP_NAME="JITAllower"
APP_BUNDLE_NAME="JITAllower.app"
APP_DIR="$DIST_DIR/Payload/$APP_BUNDLE_NAME"

echo -e "${CYAN}${BOLD}========================================================================${RESET}"
echo -e "${CYAN}${BOLD}       JITAllower TrollStore .TIPA / .IPA Builder (iPhone 8)            ${RESET}"
echo -e "${CYAN}${BOLD}========================================================================${RESET}"
echo ""

# 1. Prepare dist directory
echo -e "${GREEN}[+] Cleaning and creating build distribution directory...${RESET}"
rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR"

# 2. Compile native C helper
echo -e "${GREEN}[+] Compiling native JIT helper (jit-helper)...${RESET}"
if command -v xcrun >/dev/null 2>&1 && xcrun -find clang >/dev/null 2>&1; then
    make -C "$SCRIPT_DIR/src/jit-helper" ios
else
    make -C "$SCRIPT_DIR/src/jit-helper" clean all
fi
install -m 755 "$SCRIPT_DIR/src/jit-helper/jit-helper" "$APP_DIR/jit-helper"

# 3. Copy Info.plist and Entitlements
echo -e "${GREEN}[+] Copying Info.plist and TrollStore Entitlements...${RESET}"
cp "$SCRIPT_DIR/trollstore/Info.plist" "$APP_DIR/Info.plist"
cp "$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/Entitlements.plist"

# 4. Build iOS App binary if xcodebuild is present
if command -v xcodebuild >/dev/null 2>&1; then
    echo -e "${GREEN}[+] Building Xcode project for iPhone 8 (iOS 15.0+)...${RESET}"
    xcodebuild -project "$SCRIPT_DIR/JITAllower.xcodeproj" \
               -target "JITAllower" \
               -configuration Release \
               -sdk iphoneos \
               CONFIGURATION_BUILD_DIR="$DIST_DIR/xcode_out" \
               CODE_SIGN_IDENTITY="" \
               CODE_SIGNING_REQUIRED=NO \
               CODE_SIGNING_ALLOWED=NO \
               quiet || true
    
    if [ -f "$DIST_DIR/xcode_out/JITAllower.app/JITAllower" ]; then
        cp -a "$DIST_DIR/xcode_out/JITAllower.app/"* "$APP_DIR/"
    fi
else
    echo -e "${YELLOW}[!] Xcode not found on host. Creating TrollStore launcher script stub for inspection/testing...${RESET}"
    cat << 'EOF' > "$APP_DIR/JITAllower"
#!/usr/bin/env bash
# JITAllower Shell Launcher Stub
exec "$(dirname "$0")/jit-helper" --all
EOF
    chmod +x "$APP_DIR/JITAllower"
fi

# 5. Apply TrollStore codesigning entitlements if ldid is available
if command -v ldid >/dev/null 2>&1; then
    echo -e "${GREEN}[+] Signing application bundle with TrollStore JIT entitlements using ldid...${RESET}"
    ldid -S"$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/JITAllower" 2>/dev/null || true
    ldid -S"$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/jit-helper" 2>/dev/null || true
else
    echo -e "${YELLOW}[!] 'ldid' tool not found on host; skipping local pseudo-sign. TrollStore will automatically apply entitlements upon installation.${RESET}"
fi

# 6. Package Payload into .ipa and .tipa
echo -e "${GREEN}[+] Creating TrollStore package archives (.tipa and .ipa)...${RESET}"
cd "$DIST_DIR"
if command -v zip >/dev/null 2>&1; then
    zip -qry9 "JITAllower.ipa" "Payload"
    cp "JITAllower.ipa" "JITAllower.tipa"
elif command -v tar >/dev/null 2>&1; then
    tar -cf "JITAllower.tar" "Payload"
fi
cd "$SCRIPT_DIR"

echo ""
echo -e "${GREEN}${BOLD}[✔] JITAllower Build Complete!${RESET}"
if [ -f "$DIST_DIR/JITAllower.tipa" ]; then
    echo -e "    * TrollStore TIPA : ${BOLD}$DIST_DIR/JITAllower.tipa${RESET}"
    echo -e "    * Standard IPA    : ${BOLD}$DIST_DIR/JITAllower.ipa${RESET}"
else
    echo -e "    * App Bundle      : ${BOLD}$APP_DIR${RESET}"
fi
echo -e "${CYAN}${BOLD}========================================================================${RESET}"
