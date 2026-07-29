# Standalone Makefile for the Termux-iOS terminal app only.
.PHONY: all check build clean

all: build

build:
	@chmod +x build-trollstore-ipa.sh
	@./build-trollstore-ipa.sh

check:
	@bash -n build-trollstore-ipa.sh
	@for script in rootfs-bootstrap/*.sh rootfs-bootstrap/pkg rootfs-bootstrap/apt rootfs-bootstrap/apt-get termux-tools/*; do bash -n "$$script"; done
	@$(MAKE) -C src/jb-chroot clean all
	@src/jb-chroot/jb-chroot --status | grep -qi pacman
	@rm -f src/jb-chroot/jb-chroot
	@echo '[check] Termux-iOS checks passed'

clean:
	@$(MAKE) -C src/jb-chroot clean
	@rm -rf dist
