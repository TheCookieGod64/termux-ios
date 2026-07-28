# Termux-iOS & JITAllower — Exacte Termux Kloon & 1-Tap JIT Enabler voor iOS

[![Platform: iOS 15.0+](https://img.shields.io/badge/Platform-iOS%2015.0%2B-blue.svg)](https://apple.com)
[![Device: iPhone 8 Compatible](https://img.shields.io/badge/Device-iPhone%208%20Compatible-green.svg)](#)
[![Jailbreak: palera1n rootless](https://img.shields.io/badge/Jailbreak-palera1n%20(%2Fvar%2Fjb)-orange.svg)](#)
[![Package Manager: pacman](https://img.shields.io/badge/Package%20Manager-pacman%20(No%20apt)-purple.svg)](#)
[![Installer: TrollStore](https://img.shields.io/badge/Installer-TrollStore%20(.tipa)-red.svg)](#)

Welkom bij de repository voor jouw **iPhone 8** met een **palera1n** (`/var/jb`) rootless jailbreak en **TrollStore**. Deze repository bevat twee volledige projecten:
1. **`Termux-iOS/`** — Een exacte kloon van Termux voor iOS die **exclusief `pacman`** gebruikt als package manager (geen `apt`/`dpkg`).
2. **`JITAllower/`** — Een automatische **1-Tap JIT Enabler** met één grote knop die JIT (`CS_DEBUGGED`) inschakelt voor al je apps (zelfs als ze niet uit TrollStore komen!).

---

## 📦 Project 1: Termux-iOS (`Termux-iOS/`)

- **Exacte Termux UI:** Inclusief de **Extra Keys balk** (`ESC`, `TAB`, `CTRL`, `ALT`, pijltoetsen), het veegbare zijmenu (drawer), knipperende cursor en ondersteuning voor `~/.termux/termux.properties`.
- **UIKit Keyboard Bridge:** Normal iOS-toetsenbord werkt direct bij het tikken op het scherm, met pijltjes en hardwaretoetsenbord-ondersteuning.
- **Chroot in `/var/jb` (`src/jb-chroot/`):** Bevat de C-binary `jb-chroot` die `chroot("/var/jb")` uitvoert (met rootless fallback).
- **Pacman (geen APT):** Het `pkg`-commando vertaalt alle opdrachten naar `pacman -S`, `pacman -Sy`, `pacman -Syu`, etc. `apt` en `apt-get` zijn uitgeschakeld.
- **Automatische Bootstrap:** Installeert bij de eerste start automatisch de benodigde binaries en pacman-configuratie in `/var/jb`.

---

## ⚡️ Project 2: JITAllower (`JITAllower/`)

- **1 Grote Knop ("ALLOW JIT"):** Tik op de grote knop in het midden van het scherm om direct JIT toe te staan op al je applicaties.
- **Kies specifieke of alle apps:**
  - **All Apps:** Ontgrendelt JIT in één klap voor elke draaiende en geïnstalleerde user app.
  - **Specifieke apps:** Kies in de lijst bijvoorbeeld DolphiniOS, UTM, PPSSPP, PojavLauncher of RetroArch — **ook als die apps uit de App Store of via sideloading komen en niet uit TrollStore!**
- **Native C Helper (`JITAllower/src/jit-helper/`):** Gebruikt ptrace-attachment (`PT_ATTACHEXC`) om de `CS_DEBUGGED` kernelvlag te zetten zodat iOS dynamische JIT-allocatie toestaat zonder crash.

---

## 📁 Repository Structuur

```
termux-ios/
├── README.md                      # Deze hoofddocumentatie
├── DOCS.md                        # Technische architectuur
├── TROUBLESHOOTING.md             # Veelgestelde vragen
├── Makefile                       # Top-level Makefile (build-tipa, build-jitallower, check)
├── build-trollstore-ipa.sh        # Bouwscript voor Termux-iOS.tipa / .ipa
├── Termux-iOS.xcodeproj/          # Xcode-project voor Termux-iOS
├── Termux-iOS/                    # Swift/SwiftUI broncode (Termux-kloon)
├── src/jb-chroot/                 # C chroot helper voor /var/jb
├── rootfs-bootstrap/              # pacman.conf, mirrorlist, pkg-wrapper & apt-blockers
├── termux-tools/                  # termux-info, termux-reload-settings, etc.
└── JITAllower/                    # -> NIEUW: De automatische JIT Allower app
    ├── README.md                  # Specificaties voor JITAllower
    ├── build-trollstore-ipa.sh    # Bouwscript voor JITAllower.tipa / .ipa
    ├── JITAllower.xcodeproj/      # Xcode-project voor JITAllower
    ├── App/                       # JITAllowerApp & AppDelegate (bootstrap helper)
    ├── Views/                     # MainView (1 Grote Knop!) & AppSelectionView
    ├── Core/                      # JITManager & AppItem (app selector)
    └── src/jit-helper/            # Native C helper (ptrace CS_DEBUGGED en PID-lister)
```

---

## 🛠️ Bouwen & Testen

### Beide `.tipa` bestanden bouwen (voor TrollStore):
```bash
make all
```
*Dit genereert `dist/Termux-iOS.tipa` en `JITAllower/dist/JITAllower.tipa`.*

### Validatie en syntaxtest van alle scripts en C-helpers:
```bash
make check
```
