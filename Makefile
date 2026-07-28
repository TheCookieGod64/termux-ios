# Termux for iOS -- Linux -> arm64 iOS cross build, no Xcode / no Mac needed.
#
#   make toolchain   one-time toolchain + SDK setup into .toolchain/
#   make             build the app bundle
#   make ipa         package Termux.ipa (install with TrollStore)
#   make test        run every check that works on the build host
#   make clean       remove build output
#   make distclean   also remove the downloaded toolchain

SHELL := /bin/bash

APP_NAME     := Termux
BUNDLE_ID    := dev.termux.ios
VERSION      := 0.1.0
MIN_IOS      := 14.0
SDK_VERSION  ?= 16.5

ROOT   := $(CURDIR)
TC     := $(ROOT)/.toolchain
BUILD  := $(ROOT)/build
SDK    ?= $(TC)/sdks/iPhoneOS$(SDK_VERSION).sdk
ZIG    ?= $(TC)/zig/zig
CC     := $(ZIG) cc

APPDIR := $(BUILD)/Payload/$(APP_NAME).app
BINARY := $(APPDIR)/$(APP_NAME)

SRC := $(shell find app/Termux -name '*.m' 2>/dev/null | sort)

# The built-in shell shipped inside the bundle, used until a bootstrap exists.
XSH_SRC := native/xsh/xsh.c
XSH_BIN := $(APPDIR)/xsh

FRAMEWORKS := Foundation UIKit CoreGraphics CoreText QuartzCore UniformTypeIdentifiers
FRAMEWORK_FLAGS := $(addprefix -framework ,$(FRAMEWORKS))

WARNINGS := -Wall -Wextra -Wno-unused-parameter \
            -Wno-nullability-completeness -Wno-macro-redefined \
            -Wno-unknown-warning-option -Wno-deprecated-declarations

CFLAGS := -target aarch64-ios.$(MIN_IOS) \
          -isysroot $(SDK) \
          -I$(SDK)/usr/include \
          -Iapp/Termux -Iapp/Termux/Terminal -Iapp/Termux/Session -Iapp/Termux/UI -Iapp/Termux/Bootstrap \
          -fobjc-arc \
          -O2 -g0 \
          $(WARNINGS)

LDFLAGS := -target aarch64-ios.$(MIN_IOS) \
           -isysroot $(SDK) \
           -F$(SDK)/System/Library/Frameworks \
           -L$(SDK)/usr/lib \
           $(FRAMEWORK_FLAGS) \
           -lz \
           -Wl,-headerpad,0x1000

.PHONY: all app ipa toolchain clean test check-toolchain xsh xsh-host

all: app

toolchain:
	@bash tools/setup-toolchain.sh

check-toolchain:
	@if [ ! -x "$(ZIG)" ] || [ ! -d "$(SDK)" ]; then \
		echo "Toolchain missing -- run 'make toolchain' first."; exit 1; \
	fi

app: check-toolchain $(BINARY) $(XSH_BIN)

xsh: check-toolchain $(XSH_BIN)

$(XSH_BIN): $(XSH_SRC) | $(APPDIR)
	@echo "==> compiling built-in shell (xsh)"
	@$(CC) -target aarch64-ios.$(MIN_IOS) -isysroot $(SDK) -I$(SDK)/usr/include \
		-L$(SDK)/usr/lib -Wl,-headerpad,0x1000 -O2 $(WARNINGS) -o $@ $(XSH_SRC)
	@python3 tools/fakesign.py $@ -e app/Termux/Resources/entitlements.plist -i $(BUNDLE_ID).xsh

$(BINARY): $(SRC) | $(APPDIR)
	@echo "==> compiling $(words $(SRC)) sources for arm64 iOS"
	@$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SRC)
	@echo "==> installing bundle resources"
	@python3 tools/make_info_plist.py \
		--bundle-id $(BUNDLE_ID) --name $(APP_NAME) --version $(VERSION) \
		--min-ios $(MIN_IOS) --output $(APPDIR)/Info.plist
	@# entitlements.plist is baked into the signature, not shipped as a file.
	@find app/Termux/Resources -maxdepth 1 -mindepth 1 ! -name 'entitlements.plist' \
		-exec cp -r {} $(APPDIR)/ \; 2>/dev/null || true
	@echo "==> fakesigning with TrollStore entitlements"
	@python3 tools/fakesign.py $@ \
		-e app/Termux/Resources/entitlements.plist \
		-i $(BUNDLE_ID) \
		--info $(APPDIR)/Info.plist
	@echo "==> built $@"

$(APPDIR):
	@mkdir -p $(APPDIR)

ipa: app
	@rm -f $(BUILD)/$(APP_NAME).ipa
	@cd $(BUILD) && zip -qr $(APP_NAME).ipa Payload
	@echo "==> $(BUILD)/$(APP_NAME).ipa  ($$(du -h $(BUILD)/$(APP_NAME).ipa | cut -f1))"
	@echo "    Transfer to your iPhone and open it with TrollStore."

# A host build of the shell so its behaviour can actually be executed in tests.
xsh-host: $(BUILD)/xsh-host

$(BUILD)/xsh-host: $(XSH_SRC)
	@mkdir -p $(BUILD)
	@cc -O2 -Wall -Wextra -Wno-unused-parameter -o $@ $(XSH_SRC)

test: xsh-host
	@bash tests/run-tests.sh

clean:
	@rm -rf $(BUILD)

distclean: clean
	@rm -rf $(TC)
