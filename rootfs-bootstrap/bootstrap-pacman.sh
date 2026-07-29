#!/usr/bin/env bash
# Idempotent /var/jb bootstrap for Termux-iOS.
# Pacman is exclusive; apt/apt-get/dpkg are guarded.
set -euo pipefail

JB_ROOT="${JB_ROOT:-/var/jb}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '[termux-ios] %s\n' "$*"; }
install_if_missing() {
    local mode="$1" source="$2" destination="$3"
    if [[ ! -e "$destination" ]]; then
        install -D -m "$mode" "$source" "$destination"
    fi
}

if [[ ! -d "$JB_ROOT" ]]; then
    mkdir -p "$JB_ROOT"
fi

mkdir -p \
    "$JB_ROOT/etc/pacman.d/gnupg" \
    "$JB_ROOT/etc/pacman.d/hooks" \
    "$JB_ROOT/var/lib/pacman/local" \
    "$JB_ROOT/var/lib/pacman/sync" \
    "$JB_ROOT/var/cache/pacman/pkg" \
    "$JB_ROOT/var/log" \
    "$JB_ROOT/usr/bin" \
    "$JB_ROOT/usr/sbin" \
    "$JB_ROOT/usr/local/bin" \
    "$JB_ROOT/var/mobile/.termux" \
    "$JB_ROOT/root/.termux"

install_if_missing 0644 "$SCRIPT_DIR/pacman.conf" "$JB_ROOT/etc/pacman.conf"
install_if_missing 0644 "$SCRIPT_DIR/mirrorlist" "$JB_ROOT/etc/pacman.d/mirrorlist"
install_if_missing 0755 "$SCRIPT_DIR/pkg" "$JB_ROOT/usr/bin/pkg"
install_if_missing 0755 "$SCRIPT_DIR/apt" "$JB_ROOT/usr/bin/apt"
install_if_missing 0755 "$SCRIPT_DIR/apt-get" "$JB_ROOT/usr/bin/apt-get"

# Optional native binaries may be supplied beside this script (for example a
# pacman build). Install them only when the target is still absent.
for layout in "usr/bin:usr/bin" "usr/sbin:usr/sbin" "usr/local/bin:usr/local/bin"; do
    source_relative="${layout%%:*}"
    target_relative="${layout##*:}"
    source_directory="$SCRIPT_DIR/$source_relative"
    target_directory="$JB_ROOT/$target_relative"
    [[ -d "$source_directory" ]] || continue
    mkdir -p "$target_directory"
    for source in "$source_directory"/*; do
        [[ -f "$source" ]] || continue
        install_if_missing 0755 "$source" "$target_directory/$(basename "$source")"
    done
done

# A pre-existing apt tree is never deleted: it is moved out of the active
# configuration so rollback/debugging remains possible.
if [[ -d "$JB_ROOT/etc/apt" && ! -e "$JB_ROOT/etc/apt.disabled.by.termux-ios" ]]; then
    mv "$JB_ROOT/etc/apt" "$JB_ROOT/etc/apt.disabled.by.termux-ios"
fi

properties="$JB_ROOT/var/mobile/.termux/termux.properties"
if [[ ! -e "$properties" ]]; then
    cat >"$properties" <<'EOF'
# Termux-iOS defaults; edit ~/.termux/termux.properties.
extra-keys = [['ESC','TAB','CTRL','ALT','-','/','|','UP','DOWN','LEFT','RIGHT','HOME','END','PGUP','PGDN']]
cursor-style = block
cursor-blink = true
bell-character = ignore
pkg-manager = pacman
EOF
    chmod 0644 "$properties"
fi
install_if_missing 0644 "$properties" "$JB_ROOT/root/.termux/termux.properties"

say "bootstrap complete: $JB_ROOT"
say "package manager: pacman (pkg wrapper installed; apt/apt-get/dpkg blocked)"
say "pacman binary is expected at $JB_ROOT/usr/bin/pacman or supplied by the active jailbreak rootfs"
