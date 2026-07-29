#!/usr/bin/env bash
# Build Termux-iOS for TrollStore (.ipa and .tipa).
# The main executable is always a Mach-O ARM64 file.  There is intentionally
# no shell-script CFBundleExecutable fallback (that causes TrollStore 303).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
APP_DIR="$DIST_DIR/Payload/Termux.app"
XCODE_OUT="$DIST_DIR/xcode_out"

log() { printf '[Termux-iOS build] %s\n' "$*"; }
fatal() { printf '[Termux-iOS build] ERROR: %s\n' "$*" >&2; exit 1; }

is_macho_arm64() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    if command -v file >/dev/null 2>&1; then
        file -b "$file" | grep -Eq 'Mach-O.*(arm64|universal|arm64e)' || return 1
        return 0
    fi
    # A thin arm64 Mach-O starts with MH_MAGIC_64 and CPU_TYPE_ARM64.
    command -v od >/dev/null 2>&1 || return 1
    local header
    header="$(od -An -tx1 -N8 "$file" | tr -d ' \n')"
    [[ "${header:0:8}" == "cffaedfe" && "${header:8:8}" == "0c000001" ]]
}

ios_sdk_path() {
    if [[ -n "${IOS_SDK:-}" && -d "$IOS_SDK" ]]; then
        printf '%s\n' "$IOS_SDK"
    elif command -v xcrun >/dev/null 2>&1 && xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
        xcrun --sdk iphoneos --show-sdk-path
    elif [[ -n "${SDKROOT:-}" && -d "$SDKROOT" && "$SDKROOT" == *iphoneos* ]]; then
        printf '%s\n' "$SDKROOT"
    else
        return 1
    fi
}

apple_clang() {
    if [[ -n "${IOS_CLANG:-}" && -x "$IOS_CLANG" ]]; then
        printf '%s\n' "$IOS_CLANG"
    elif command -v xcrun >/dev/null 2>&1 && xcrun --sdk iphoneos --find clang >/dev/null 2>&1; then
        printf '%s\n' "xcrun --sdk iphoneos clang"
    elif command -v clang >/dev/null 2>&1 && ios_sdk_path >/dev/null 2>&1; then
        printf '%s\n' "clang"
    else
        return 1
    fi
}

compile_arm64() {
    local source="$1" output="$2" compiler sdk_path
    compiler="$(apple_clang)" || fatal "geen iPhoneOS SDK/Apple clang gevonden. Op Arch Linux: gebruik make check en laat GitHub Actions (macos-14) de IPA bouwen, of stel IOS_SDK en IOS_CLANG in."
    sdk_path="$(ios_sdk_path)" || fatal "clang zonder iPhoneOS SDK maakt geen geldige iOS Mach-O; stel IOS_SDK in of gebruik de macOS GitHub Actions workflow."
    log "compiling ARM64 Mach-O $(basename "$output") with clang -arch arm64"
    # shellcheck disable=SC2086
    $compiler -target arm64-apple-ios15.0 -arch arm64 -isysroot "$sdk_path" \
        -miphoneos-version-min=15.0 -Wall -Wextra -O2 "$source" -o "$output"
}

prepare_dirs() {
    rm -rf "$DIST_DIR"
    mkdir -p "$APP_DIR" "$XCODE_OUT"
}

build_helper() {
    local helper="$SCRIPT_DIR/src/jb-chroot/jb-chroot"
    if command -v xcrun >/dev/null 2>&1 && xcrun --sdk iphoneos --find clang >/dev/null 2>&1; then
        make -C "$SCRIPT_DIR/src/jb-chroot" ios
    else
        compile_arm64 "$SCRIPT_DIR/src/jb-chroot/jb-chroot.c" "$helper"
    fi
    is_macho_arm64 "$helper" || fatal "jb-chroot is not an ARM64 Mach-O binary"
    install -m 755 "$helper" "$APP_DIR/jb-chroot"
}

build_swift_app_or_launcher() {
    local built_app="$XCODE_OUT/Termux-iOS.app"
    local built=false
    if command -v xcodebuild >/dev/null 2>&1; then
        log "running xcodebuild with -derivedDataPath $DIST_DIR/dd"
        set +e
        xcodebuild -project "$SCRIPT_DIR/Termux-iOS.xcodeproj" \
            -target "Termux-iOS" -configuration Release -sdk iphoneos \
            -derivedDataPath "$DIST_DIR/dd" \
            CONFIGURATION_BUILD_DIR="$XCODE_OUT" \
            CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
        local status=$?
        set -e
        if [[ $status -eq 0 && -x "$built_app/Termux-iOS" ]] && is_macho_arm64 "$built_app/Termux-iOS"; then
            log "using the Xcode-built SwiftUI application"
            cp -R "$built_app/." "$APP_DIR/"
            built=true
        else
            log "xcodebuild did not produce a valid ARM64 app; using the native launcher fallback"
        fi
    else
        log "xcodebuild not found; using the native launcher fallback"
    fi

    if [[ "$built" != true ]]; then
        compile_arm64 "$SCRIPT_DIR/src/launchers/termux-launcher.c" "$APP_DIR/Termux-iOS"
    fi
    is_macho_arm64 "$APP_DIR/Termux-iOS" || fatal "CFBundleExecutable is not a valid ARM64 Mach-O"
}

package_app() {
    mkdir -p "$APP_DIR/rootfs-bootstrap" "$APP_DIR/termux-tools"
    cp -R "$SCRIPT_DIR/rootfs-bootstrap/." "$APP_DIR/rootfs-bootstrap/"
    cp -R "$SCRIPT_DIR/termux-tools/." "$APP_DIR/termux-tools/"
    chmod 755 "$APP_DIR/rootfs-bootstrap/pkg" "$APP_DIR/rootfs-bootstrap/apt" "$APP_DIR/rootfs-bootstrap/apt-get" "$APP_DIR/rootfs-bootstrap/bootstrap-pacman.sh" "$APP_DIR/termux-tools/"* 2>/dev/null || true
    cp "$SCRIPT_DIR/Termux-iOS/Info.plist" "$APP_DIR/Info.plist"
    cp "$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/Entitlements.plist"
    chmod 755 "$APP_DIR/Termux-iOS" "$APP_DIR/jb-chroot"

    if command -v ldid >/dev/null 2>&1; then
        log "applying TrollStore entitlements with ldid"
        ldid -S"$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/Termux-iOS"
        ldid -S"$SCRIPT_DIR/trollstore/Entitlements.plist" "$APP_DIR/jb-chroot"
    else
        log "ldid not found; leaving code signing to TrollStore on installation"
    fi

    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_DIR/Info.plist" 2>/dev/null || true)" == "Termux-iOS" ]] || grep -q '<string>Termux-iOS</string>' "$APP_DIR/Info.plist" || fatal "CFBundleExecutable is not Termux-iOS"
    command -v zip >/dev/null 2>&1 || fatal "zip is required to generate .ipa/.tipa"
    (cd "$DIST_DIR" && zip -X -qry9 "Termux-iOS.ipa" Payload)
    cp "$DIST_DIR/Termux-iOS.ipa" "$DIST_DIR/Termux-iOS.tipa"
}

prepare_dirs
build_helper
build_swift_app_or_launcher
package_app
log "created $DIST_DIR/Termux-iOS.ipa and $DIST_DIR/Termux-iOS.tipa"
