# Termux-iOS — Exacte Termux Kloon voor iOS (iPhone 8 | palera1n | TrollStore | Pacman)

[![Platform: iOS 15.0+](https://img.shields.io/badge/Platform-iOS%2015.0%2B-blue.svg)](https://apple.com)
[![Device: iPhone 8 Compatible](https://img.shields.io/badge/Device-iPhone%208%20Compatible-green.svg)](#)
[![Jailbreak: palera1n rootless](https://img.shields.io/badge/Jailbreak-palera1n%20(%2Fvar%2Fjb)-orange.svg)](#)
[![Package Manager: pacman](https://img.shields.io/badge/Package%20Manager-pacman%20(No%20apt)-purple.svg)](#)
[![Installer: TrollStore](https://img.shields.io/badge/Installer-TrollStore%20(.tipa)-red.svg)](#)

**Termux-iOS** is een exacte, op iOS afgestemde kloon van de iconische [Termux](https://termux.dev) terminal-omgeving. Dit project is speciaal geoptimaliseerd voor de **iPhone 8** (iOS 15 / 16) met een rootless jailbreak via **palera1n** (`/var/jb`) en wordt geïnstalleerd via **TrollStore**. 

In tegenstelling tot standaard Procursus/Debian-opzetjes gebruikt deze Termux-omgeving **exclusief `pacman`** als pakketbeheerder en is **`apt` volledig uitgeschakeld**.

---

## 🚀 Kenmerken & Functionaliteiten

### 1. Exacte Termux-gebruikerservaring
- **Extra Keys Balk (`ExtraKeysView`):** Configureerbare extra rij boven het iOS-toetsenbord met `ESC`, `TAB`, `CTRL`, `ALT`, `-`, `/`, `|` en de pijltoetsen `UP`, `DOWN`, `LEFT`, `RIGHT`, `HOME`, `END`, `PGUP` en `PGDN`.
- **Veegbaar Zijmenu (Sidebar):** Swipe vanaf de linkerrand om terminal-sessies te beheren, nieuwe sessies (`+ New Session`) te starten, het toetsenbord te schakelen of thema's aan te passen.
- **Pinch-to-Zoom & Contextmenu:** Pas de lettergrootte vloeiend aan met twee vingers of houd ingedrukt voor opties om te kopiëren, plakken, het scherm te resetten of sessies te stoppen.
- **`termux.properties` Ondersteuning:** Pas `extra-keys`, cursor-stijl (`block`, `underline`, `bar`), belsignaal en kleuren aan in `~/.termux/termux.properties` (of via `/var/jb/var/mobile/.termux/`).

### 2. iPhone 8, palera1n & TrollStore Integratie
- **TrollStore Entitlements (`trollstore/Entitlements.plist`):** Volledig voorzien van `platform-application`, `com.apple.private.posix_spawn-allow`, `com.apple.private.security.no-sandbox` en filesystem entitlements. Hierdoor kan de app zonder iOS-sandboxbeperkingen processen starten en het `/var/jb` root-bestandssysteem benaderen.
- **Native `/var/jb` Chroot-helper (`src/jb-chroot/`):** Bevat de C-helper `jb-chroot.c` die direct `chroot("/var/jb")` uitvoert en de terminal-omgeving klaarzert met `HOME=/home/mobile`, `PREFIX=/usr` en `PATH=/usr/bin:...`. Bij onvoldoende rechten schakelt `jb-chroot` automatisch over naar rootless prefix-modus.

### 3. Pacman-Exclusieve Pakketbeheerder (Geen APT!)
- **`pacman` in `/var/jb`:** Termux-iOS is geconfigureerd met een geoptimaliseerde `pacman.conf` en spiegelservers voor aarch64 Arch Linux ARM en Termux-iOS.
- **`pkg` Wrapper op basis van pacman:** Het vertrouwde `pkg`-commando vertaalt alle opdrachten naadloos naar `pacman`:
  - `pkg install <package>` ➔ `pacman -S <package>`
  - `pkg update` ➔ `pacman -Sy`
  - `pkg upgrade` ➔ `pacman -Syu`
  - `pkg remove <package>` ➔ `pacman -Rns <package>`
  - `pkg search <naam>` ➔ `pacman -Ss <naam>`
- **Apt-bescherming:** De commando's `apt` en `apt-get` in `/var/jb/usr/bin/` verwijzen naar een wrapper die `apt` blokkeert en uitlegt hoe je `pacman` of `pkg` gebruikt.

---

## 📁 Structuur van de Repository

```
termux-ios/
├── README.md                      # Deze hoofddocumentatie
├── DOCS.md                        # Technische architectuur & TrollStore-handleiding
├── TROUBLESHOOTING.md             # Veelgestelde vragen en probleemoplossing
├── Makefile                       # Top-level Makefile voor IPA/TIPA en helper-tools
├── build-trollstore-ipa.sh        # Geautomatiseerd script voor TrollStore .tipa / .ipa
├── Termux-iOS.xcodeproj/          # Volledig iOS 15+ Xcode project
├── Termux-iOS/                    # SwiftUI & UIKit applicatiebroncode
│   ├── App/                       # TermuxApp & AppDelegate (bootstrap checks)
│   ├── Views/                     # TerminalView, ExtraKeysView, SidebarView & Settings
│   ├── TerminalCore/              # VT100 parser, ANSI 256-kleuren, PTY process spawner
│   └── Config/                    # TermuxProperties (~/.termux/termux.properties) & IPC
├── src/jb-chroot/                 # Native C-helper voor chroot("/var/jb")
├── rootfs-bootstrap/              # Pacman configuraties, pkg en apt blockers
└── termux-tools/                  # Ingebouwde termux-* commando's (termux-info, etc.)
```

---

## 🛠️ Installatie via TrollStore (iPhone 8)

1. **Bouw het `.tipa` installatiebestand (of download uit releases):**
   Run op macOS of in je bouwomgeving:
   ```bash
   make all
   ```
   *Dit genereert `dist/Termux-iOS.tipa` en `dist/Termux-iOS.ipa`.*

2. **Zet het bestand over naar je iPhone 8:**
   - Stuur `Termux-iOS.tipa` via AirDrop, Finder of SSH naar je toestel.

3. **Installeer met TrollStore:**
   - Open **TrollStore** op je iPhone 8.
   - Tik op het **`+`** icoon rechtsboven of open het `.tipa` bestand vanuit Bestanden en kies **Install**.
   - TrollStore installeert de app en past automatisch alle noodzakelijke entitlements toe.

4. **Start Termux & Bootstrap Pacman:**
   - Open **Termux** vanaf je beginscherm.
   - Voor de eerste setup kun je in de terminal het bootstrap-script aanroepen via:
     ```bash
     make install-bootstrap
     ```
   - Controleer je installatie met `termux-info`.

---

## 💻 Belangrijkste Termux-commando's

| Commando | Beschrijving |
| :--- | :--- |
| `termux-info` | Toont iPhone 8 model, iOS versie, `/var/jb` jailbreak status en pacman versie. |
| `termux-reload-settings` | Herlaadt de instellingen uit `~/.termux/termux.properties` direct. |
| `termux-setup-storage` | Maakt symlinks aan in `~/storage/` naar de iOS-mediamappen (`DCIM`, `Downloads`). |
| `termux-clipboard-get` | Leest de inhoud van het iOS-klembord. |
| `termux-clipboard-set` | Schrijft tekst of data naar het iOS-klembord. |
| `termux-open <file/url>` | Opent een bestand of URL via het standaard iOS-systeem. |
| `termux-chroot` | Opent direct een interactieve chroot shell in `/var/jb`. |

---

## 🧪 Validatie & Testen

Je kunt op elk moment de geldigheid van alle scripts en de werking van de C-helper `jb-chroot` controleren via:

```bash
make check
```

*Alle scripts, bash syntax en C-compilatie worden hiermee gevalideerd.*
