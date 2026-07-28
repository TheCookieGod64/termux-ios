#
# Makefile for Termux-iOS
# Exact Termux Clone for iOS — Target: iPhone 8 | palera1n (/var/jb) | TrollStore | pacman
#

SHELL := /usr/bin/env bash
SCRIPT_DIR := $(shell pwd)

.PHONY: all clean test check build-tipa chroot-status install-bootstrap

all: build-tipa

build-tipa:
	@chmod +x build-trollstore-ipa.sh
	@./build-trollstore-ipa.sh

chroot-status:
	@make -C src/jb-chroot clean all
	@src/jb-chroot/jb-chroot --status

test check:
	@echo "=========================================================="
	@echo "Running Termux-iOS Verification & Syntax Checks..."
	@echo "=========================================================="
	@echo "1. Checking bash syntax of bootstrap & CLI tools..."
	@bash -n rootfs-bootstrap/bootstrap-pacman.sh
	@bash -n rootfs-bootstrap/pkg
	@bash -n rootfs-bootstrap/apt
	@bash -n rootfs-bootstrap/apt-get
	@bash -n termux-tools/termux-info
	@bash -n termux-tools/termux-reload-settings
	@bash -n termux-tools/termux-setup-storage
	@bash -n termux-tools/termux-clipboard-get
	@bash -n termux-tools/termux-clipboard-set
	@bash -n termux-tools/termux-open
	@bash -n termux-tools/termux-chroot
	@echo "   [✔] All shell scripts passed syntax inspection."
	@echo ""
	@echo "2. Compiling jb-chroot helper..."
	@make -C src/jb-chroot clean all
	@echo "   [✔] jb-chroot compiled successfully without errors."
	@echo ""
	@echo "3. Verifying jb-chroot --status report..."
	@src/jb-chroot/jb-chroot --status | grep -i "pacman"
	@echo "   [✔] jb-chroot pacman policy verified."
	@echo ""
	@echo "4. Checking package wrapper (pkg) help output..."
	@rootfs-bootstrap/pkg --help | grep -i "pacman"
	@echo "   [✔] pkg wrapper pacman mapping verified."
	@echo ""
	@echo "5. Checking apt guard wrappers..."
	@rootfs-bootstrap/apt 2>&1 | grep -i "pacman"
	@rootfs-bootstrap/apt-get 2>&1 | grep -i "pacman"
	@echo "   [✔] apt guard wrappers verified."
	@echo ""
	@echo "=========================================================="
	@echo " [✔] All Termux-iOS checks PASSED!"
	@echo "=========================================================="

clean:
	@make -C src/jb-chroot clean
	@rm -rf dist

install-bootstrap:
	@chmod +x rootfs-bootstrap/bootstrap-pacman.sh
	@rootfs-bootstrap/bootstrap-pacman.sh
