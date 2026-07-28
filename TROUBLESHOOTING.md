# Termux-iOS — Veelgestelde Vragen & Probleemoplossing (Troubleshooting)

Dit document helpt bij het oplossen van veelvoorkomende vragen over **Termux-iOS** op een **iPhone 8** met **palera1n** en **TrollStore**.

---

## 1. De app meldt: "Rootfs '/var/jb' not found"
### Oorzaak
Je iPhone 8 draait geen (rootless) jailbreak via palera1n, of de symlink `/var/jb` is niet actief.
### Oplossing
1. Controleer of je toestel gejailbreaked is met palera1n (rootless of rootful).
2. Start in je terminal of via SSH en verifieer of `/var/jb` bestaat:
   ```bash
   ls -ld /var/jb
   ```
3. Als je Termux-iOS in een niet-jailbreakomgeving test, zal de app automatisch overschakelen naar een lokale sandboxmodus (`~/.termux`).

---

## 2. Waarom krijg ik de foutmelding "apt is disabled on this system"?
### Oorzaak
Je hebt geprobeerd `apt` of `apt-get` te gebruiken (bijvoorbeeld `apt install git` of `pkg install` in een oud Debian script).
### Oplossing
Termux-iOS is expliciet geconfigureerd om **`pacman`** te gebruiken. Gebruik de volgende opdrachten:
- Pakket installeren: `pacman -S <pakket>` of `pkg install <pakket>`
- Systeem upgraden: `pacman -Syu` of `pkg upgrade`
- Pakket verwijderen: `pacman -Rns <pakket>` of `pkg remove <pakket>`

---

## 3. Hoe wijzig ik mijn Extra Keys of kleurenthema?
### Oplossing
1. Open de **Sidebar** door vanaf de linkerrand van het scherm te swipen en kies **Settings**, óf bewerk het configuratiebestand direct:
   ```bash
   nano ~/.termux/termux.properties
   ```
2. Voeg je gewenste extra toetsen toe:
   ```ini
   extra-keys = [['ESC','TAB','CTRL','ALT','-','/','|','UP','DOWN','LEFT','RIGHT','HOME','END','PGUP','PGDN']]
   ```
3. Voer daarna in je terminal uit:
   ```bash
   termux-reload-settings
   ```

---

## 4. `termux-setup-storage` geeft geen toegang tot foto's / downloads
### Oorzaak
De app heeft in iOS nog geen toestemming gekregen voor Photo Library of Documents.
### Oplossing
1. Open de iOS Instellingen-app op je iPhone 8 -> scroll naar **Termux-iOS**.
2. Zet **Foto's** en **Bestanden/Mappen** aan.
3. Voer in je terminal opnieuw uit:
   ```bash
   termux-setup-storage
   ```

---

## 5. Hoe test ik of alle interne componenten en syntax correct zijn?
Voer in de hoofdmap van het project uit:
```bash
make check
```
Dit compileert de C-helper `jb-chroot`, controleert de bash syntax van alle scripts en test de pacman-instellingen.
