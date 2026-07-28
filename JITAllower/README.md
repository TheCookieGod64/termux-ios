# JITAllower — 1-Tap Automatic JIT Enabler for iOS 15/16 (iPhone 8 | TrollStore | palera1n)

[![Platform: iOS 15.0+](https://img.shields.io/badge/Platform-iOS%2015.0%2B-blue.svg)](https://apple.com)
[![Device: iPhone 8 Compatible](https://img.shields.io/badge/Device-iPhone%208%20Compatible-green.svg)](#)
[![Jailbreak: palera1n (/var/jb)](https://img.shields.io/badge/Jailbreak-palera1n%20(%2Fvar%2Fjb)-orange.svg)](#)
[![Installer: TrollStore (.tipa)](https://img.shields.io/badge/Installer-TrollStore%20(.tipa)-red.svg)](#)

**JITAllower** is een super simpele, minimalistische tool voor je gejailbreakte iPhone 8 om met **één grote knop** direct JIT (`CS_DEBUGGED` / dynamic code execution) in te schakelen voor al je apps — **zelfs voor apps die niet uit TrollStore komen** (zoals DolphiniOS, UTM, PPSSPP, PojavLauncher of RetroArch uit de App Store of sideloading)!

---

## 🚀 Hoe werkt het?

1. **1 Grote Knop ("ALLOW JIT"):**  
   Wanneer je de app opent, zie je direct in het midden één grote, opvallende knop.  
2. **Kies All Apps of specifieke apps:**  
   - Tik op **"Enable JIT on ALL Apps"** om in één keer JIT te ontgrendelen op alle draaiende en geïnstalleerde applicaties op je iPhone 8.
   - Of kies in de lijst een specifieke app waarop je JIT wilt inschakelen.
3. **Native C-helper (`jit-helper`):**  
   Onder de motorkap roept JITAllower de C-binary `jit-helper` aan (geïnstalleerd in `/var/jb/usr/bin/jit-helper`). Dankzij jouw TrollStore-entitlements (`task_for_pid-allow`, `com.apple.private.cs.debugger`) hangt deze helper zich tijdelijk als ptrace-debugger aan het proces vast en zet de `CS_DEBUGGED` kernelvlag, waarna de app direct op volle JIT-snelheid draait zonder door iOS te worden gestopt.

---

## 🛠️ Bouwen & Installeren via TrollStore

1. **Bouw het `.tipa`-bestand (op macOS of Linux):**
   ```bash
   ./build-trollstore-ipa.sh
   ```
   *Dit genereert `dist/JITAllower.tipa` en `dist/JITAllower.ipa`.*

2. **Installeer in TrollStore:**
   - Stuur `JITAllower.tipa` naar je iPhone 8.
   - Open het bestand met **TrollStore** en kies **Install**.
   - Open JITAllower op je beginscherm en druk op **ALLOW JIT**!
