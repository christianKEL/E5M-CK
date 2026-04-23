# MÉMOIRE TECHNIQUE — Génération de `btteddy.uf2`

## Firmware Klipper mainline pour BTT Eddy USB (RP2040)

**Auteur :** Christian KELHETTER
**Projet :** E5M-CK — https://github.com/christianKEL/E5M-CK
**Date :** Avril 2026

---

## 1. Contexte et problématique

### 1.1 Qu'est-ce que `btteddy.uf2` ?

`btteddy.uf2` est le **firmware Klipper** qui tourne sur le microcontrôleur RP2040 embarqué dans le BTT Eddy USB. C'est ce firmware qui :

- Pilote le chip LDC1612 (capteur à courant de Foucault) en I2C.
- Envoie les mesures de fréquence à l'hôte via USB.
- Lit le thermistor intégré à l'Eddy (sur GPIO26).
- Applique les corrections en température au signal LDC.

### 1.2 Pourquoi compiler soi-même ?

BTT fournit un firmware précompilé sur son dépôt GitHub. Cependant :

1. **Version de Klipper** : le firmware précompilé BTT est souvent lié à une version de Klipper qui n'est pas celle installée sur le Nebula. Si les versions divergent, Klipper affiche au démarrage :

   ```
   MCU 'eddy' protocol error: command format mismatch
   ```

2. **Format binaire UF2** : BTT distribue parfois le firmware au format `.bin` (pour flash via `rp2040load` ou similaire). Sur le Nebula Pad, nous n'avons ni `rp2040load` ni `openocd` — la seule méthode de flash disponible est la méthode UF2 (copie de fichier sur le disque USB exposé par le RP2040 en mode BOOT).

3. **Cohérence avec Klipper mainline** : il est essentiel que le firmware de l'Eddy soit compilé depuis **le même commit** que le Klipper installé sur le Nebula. Sinon, les structures de message entre l'hôte et le MCU peuvent être incompatibles.

Compiler soi-même résout ces trois problèmes.

### 1.3 Le RP2040

Le **Raspberry Pi RP2040** embarqué dans le BTT Eddy est un microcontrôleur dual-core ARM Cortex-M0+ avec :
- 264 Ko de SRAM
- Pas de flash interne — le firmware réside sur un chip Flash SPI externe.
- Mode **BOOTSEL** activé par le bouton BOOT : le RP2040 s'expose alors comme un disque USB FAT16 acceptant un fichier `.uf2`.

Le format **UF2 (USB Flashing Format)** est un format de firmware conçu par Microsoft pour être simple à flasher : on copie le `.uf2` sur le disque USB exposé par le bootloader, le firmware se charge automatiquement en flash et le RP2040 redémarre.

---

## 2. Environnement de compilation

### 2.1 Architecture requise

La compilation du firmware Klipper RP2040 nécessite :
- Une chaîne de cross-compilation ARM (`arm-none-eabi-gcc`).
- Le système de build `make` + `kconfig`.
- Un hôte x86_64 ou ARM64 Linux (les deux fonctionnent pour cette cible).

Contrairement à `c_helper.so` qui nécessite obligatoirement un hôte x86_64 pour exécuter la toolchain Ingenic, la compilation RP2040 peut théoriquement se faire sur n'importe quel hôte Linux (x86_64 ou ARM64 — la toolchain `arm-none-eabi-gcc` existe pour les deux architectures).

### 2.2 Environnement retenu

Pour **cohérence avec le workflow de `c_helper.so`** et pour éviter d'installer un environnement de compilation local, nous utilisons le **même codespace GitHub** que celui utilisé pour compiler `c_helper.so` (voir mémoire `MEMOIRE_c_helper.md`).

Avantages :
- L'environnement est identique entre `c_helper.so` et `btteddy.uf2` — même commit Klipper.
- Pas d'installation à maintenir en local.
- Performances excellentes (compilation en ~30 secondes).

### 2.3 Installation des prérequis

Dans le codespace :

```bash
# La toolchain ARM est généralement pré-installée sur Codespaces Ubuntu
# Si absente :
sudo apt update
sudo apt install -y gcc-arm-none-eabi build-essential

# Vérifier
arm-none-eabi-gcc --version
# Sortie attendue : arm-none-eabi-gcc (15:...) 10.3.1 ou plus récent
```

Klipper recommande GCC 9 minimum pour le RP2040. GCC 10+ fonctionne sans souci.

### 2.4 Source Klipper

Si un codespace a déjà été utilisé pour `c_helper.so`, Klipper est déjà cloné dans `/workspaces/klipper`. Sinon :

```bash
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper
cd /workspaces/klipper
```

**Important :** pour garantir la compatibilité avec l'hôte Nebula, utiliser **le même commit** que celui installé sur le Nebula. Le commit est visible dans :

```bash
# Sur le Nebula
cd /usr/data/klipper
git rev-parse HEAD
# Par exemple : 373f200ca5a8c5e0...
```

Et dans Codespace, avant compilation :

```bash
cd /workspaces/klipper
git checkout 373f200ca  # même hash que sur le Nebula
```

---

## 3. Configuration `make menuconfig`

### 3.1 Lancement

```bash
cd /workspaces/klipper
make clean
make menuconfig
```

Un menu ncurses s'affiche dans le terminal du codespace.

### 3.2 Paramètres pour le BTT Eddy USB

Les options à régler dans `menuconfig` :

| Option | Valeur | Commentaire |
|---|---|---|
| Micro-controller Architecture | **Raspberry Pi RP2040** | Le cœur du BTT Eddy USB |
| Processor model | **rp2040** | Seule option disponible dans cette branche |
| Bootloader offset | **No bootloader** | Le RP2040 a un bootloader en ROM ; pas de second bootloader requis |
| Flash chip | **GENERIC_03H with CLKDIV 4** | Correspond au chip Flash SPI soudé sur le BTT Eddy |
| Communication interface | **USB (on GPIO 19/20)** | L'Eddy communique avec l'hôte via USB uniquement (pas UART ni CAN) |
| USB ids | Laisser les valeurs par défaut | Klipper utilise ses propres VID/PID par défaut |
| CanBoot options | **(non applicable)** | Pas de CAN sur l'Eddy USB |

**Note sur le Flash chip :** l'option `GENERIC_03H with CLKDIV 4` est la configuration utilisée par BTT sur leurs produits Eddy. `GENERIC_03H` désigne la commande SPI de lecture `0x03` (Read Data) utilisée par la majorité des chips Flash. `CLKDIV 4` fixe la fréquence du bus SPI à un quart de la fréquence système, ce qui correspond à la cadence nominale du chip utilisé.

Si le firmware compilé avec `GENERIC_03H` ne démarre pas sur ton Eddy, essayer `W25Q080 with CLKDIV 2` (valeur usine RP2040 standard).

### 3.3 Validation et sortie

Dans le menu `menuconfig` :
- Touche **Y/N** pour activer/désactiver une option.
- **Entrée** pour entrer dans un sous-menu.
- **Escape** pour remonter.
- **Q** pour quitter. Si des changements ont été faits, répondre **Yes** à la question "Save configuration?".

Le fichier `.config` à la racine du projet contient maintenant la configuration.

### 3.4 Configuration alternative — `.config` direct

Plutôt que de passer par `menuconfig`, il est possible de créer directement le fichier `.config` :

```bash
cat > /workspaces/klipper/.config << 'EOF'
# Micro-controller Architecture
CONFIG_MACH_RP2040=y
CONFIG_MCU="rp2040"

# Bootloader
CONFIG_RP2040_HAVE_BOOTLOADER=n

# Flash chip
CONFIG_RP2040_FLASH_GENERIC_03H=y
CONFIG_RP2040_FLASH_CLKDIV=4

# Communication
CONFIG_USBSERIAL=y

CONFIG_CLOCK_FREQ=12000000
CONFIG_USB_VENDOR_ID=0x1d50
CONFIG_USB_DEVICE_ID=0x614e
EOF
```

Cette méthode est plus rapide pour une compilation automatisée.

---

## 4. Compilation

### 4.1 Build

```bash
cd /workspaces/klipper
make
```

Sortie typique :

```
  Building out/autoconf.h
  Compiling out/src/sched.o
  Compiling out/src/command.o
  ...
  Compiling out/src/rp2040/main.o
  Compiling out/src/rp2040/usbserial.o
  ...
  Linking out/klipper.elf
  Creating hex file out/klipper.elf.hex
  Creating bin file out/klipper.bin
  Converting to uf2 file out/klipper.uf2
```

Durée : ~20 à 40 secondes sur un codespace standard.

### 4.2 Fichiers produits

Dans le dossier `out/` :

| Fichier | Taille typique | Usage |
|---|---|---|
| `klipper.elf` | ~400 Ko | Binaire ELF avec symboles (debug) |
| `klipper.bin` | ~70 Ko | Binaire brut (pour flash direct via rp2040load) |
| `klipper.hex` | ~200 Ko | Intel HEX (autres outils de flash) |
| **`klipper.uf2`** | **~140 Ko** | **Format UF2 pour flash par copie USB** |

**Le fichier qui nous intéresse :** `out/klipper.uf2`.

On le renomme `btteddy.uf2` pour plus de clarté dans notre workflow :

```bash
cp out/klipper.uf2 ~/btteddy.uf2
ls -lh ~/btteddy.uf2
# -rw-r--r-- 1 user user 140K Apr 22 10:43 /home/user/btteddy.uf2
```

### 4.3 Validation du fichier UF2

Un fichier UF2 valide commence toujours par le magic number `UF2\n` (bytes `55 46 32 0A`).

```bash
od -t x1 ~/btteddy.uf2 | head -1
```

Sortie attendue :

```
0000000  55 46 32 0a 57 51 5d 9e 00 20 00 00 00 00 00 00
```

Les 4 premiers octets `55 46 32 0a` confirment qu'il s'agit d'un vrai UF2.

On peut aussi inspecter le header pour vérifier la famille cible :

```bash
python3 << 'EOF'
with open('/home/user/btteddy.uf2', 'rb') as f:
    header = f.read(32)
magic0 = int.from_bytes(header[0:4], 'little')
magic1 = int.from_bytes(header[4:8], 'little')
family_id = int.from_bytes(header[28:32], 'little')
print(f"Magic0: {hex(magic0)}")       # Attendu : 0x0a324655 (UF2\n little-endian)
print(f"Magic1: {hex(magic1)}")       # Attendu : 0x9e5d5157
print(f"Family: {hex(family_id)}")    # Attendu : 0xe48bff56 (RP2040)
EOF
```

La `family_id = 0xe48bff56` est le marqueur officiel RP2040 dans la spec UF2. Si la valeur diffère, le firmware ne ciblera pas le bon microcontrôleur.

---

## 5. Flash de l'Eddy sur le Nebula

### 5.1 Transfert vers le Nebula

Comme pour `c_helper.so`, le codespace ne peut pas atteindre directement le réseau local. Deux méthodes :

**Méthode A — Téléchargement puis SCP :**

1. Dans l'explorateur VS Code du codespace : clic droit sur `btteddy.uf2` → **Download**.
2. Depuis PowerShell Windows :
   ```powershell
   scp C:\Users\<user>\Downloads\btteddy.uf2 `
       root@<IP_NEBULA>:/usr/data/E5M_CK/btteddy.uf2
   ```

**Méthode B — GitHub Raw (utilisée par `install.sh`) :**

1. Uploader `btteddy.uf2` dans le dépôt `christianKEL/E5M-CK` sur GitHub.
2. Depuis le Nebula :
   ```bash
   wget --no-check-certificate \
     https://raw.githubusercontent.com/christianKEL/E5M-CK/main/btteddy.uf2 \
     -O /usr/data/E5M_CK/btteddy.uf2
   ```

### 5.2 Mise en mode BOOT de l'Eddy

Pour flasher le RP2040, il faut le mettre en mode BOOTSEL :

1. **Débrancher** l'Eddy du port USB du Nebula.
2. **Maintenir enfoncé** le bouton BOOT (petit bouton tactile à côté du port USB sur l'Eddy).
3. **Brancher** l'Eddy au Nebula **tout en maintenant BOOT**.
4. **Attendre 3 secondes** avant de relâcher BOOT.

### 5.3 Vérification du mode BOOT

Sur le Nebula :

```bash
lsusb | grep "2e8a:0003"
```

Si on voit :

```
Bus 001 Device 005: ID 2e8a:0003 Raspberry Pi RP2 Boot
```

Le RP2040 est en mode BOOT. Le VID `2e8a` est celui de Raspberry Pi, le PID `0003` est le bootloader RP2040.

On peut aussi vérifier le montage :

```bash
mount | grep sda
```

Sortie attendue :

```
/dev/sda1 on /tmp/udisk/sda1 type vfat (rw,relatime,fmask=0022,...)
```

Le RP2040 en mode BOOT expose un disque FAT16 contenant :
- `INDEX.HTM` — lien vers la doc Raspberry Pi.
- `INFO_UF2.TXT` — informations sur le bootloader.

### 5.4 Flash

Copie du firmware sur le disque USB :

```bash
cp /usr/data/E5M_CK/btteddy.uf2 /tmp/udisk/sda1/
sync
```

**Ce qui se passe :**

1. Le fichier est écrit sur la FAT16 du RP2040.
2. Le bootloader RP2040 détecte le fichier `.uf2`, vérifie le magic number et la family_id.
3. Il copie le firmware dans la Flash SPI externe.
4. Il **redémarre** le RP2040 automatiquement en mode applicatif.

Résultat : le disque USB disparaît et le RP2040 réapparaît comme un CDC-ACM (port série USB).

### 5.5 Validation du flash

Après ~5 secondes :

```bash
ls /dev/serial/by-id/
```

Sortie attendue :

```
usb-Klipper_rp2040_50445059303E9B1C-if00
```

Le préfixe `Klipper_rp2040_` confirme que le firmware Klipper tourne correctement. Le suffixe (`50445059303E9B1C` dans l'exemple) est le numéro de série unique du RP2040 — il **variera selon l'exemplaire** d'Eddy.

### 5.6 Erreurs courantes

**L'Eddy ne se met pas en mode BOOT :**
- Vérifier qu'on maintient bien le bouton BOOT **avant** de brancher, et qu'on relâche après.
- Essayer un autre câble USB (certains câbles sont "charge only" sans data).
- Essayer un autre port USB du Nebula.

**L'Eddy est en mode BOOT mais le flash échoue :**
```
cp: write error: No space left on device
```
- Le bootloader RP2040 accepte uniquement des fichiers `.uf2`. Vérifier qu'on copie bien `btteddy.uf2` et pas `klipper.bin` ou `.elf`.

**Après flash, pas de `/dev/serial/by-id/usb-Klipper_rp2040_...` :**
- Le firmware a été flashé mais ne démarre pas. Rééssayer le flash.
- Si persistant, essayer une configuration Flash chip différente (`W25Q080 with CLKDIV 2`).
- Vérifier les messages du kernel : `dmesg | tail -30`.

**Après flash, apparition d'un port série mais pas de communication Klipper :**
- Le firmware est flashé mais n'est pas compatible avec l'hôte. Recompiler en s'assurant que **le commit Klipper du codespace est identique** à celui du Nebula.

---

## 6. Configuration Klipper côté hôte

Une fois le firmware flashé et le port série détecté, Klipper doit être configuré pour dialoguer avec l'Eddy.

Créer `/usr/data/printer_data/config/eddy.cfg` :

```ini
[mcu eddy]
serial: /dev/serial/by-id/usb-Klipper_rp2040_50445059303E9B1C-if00

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
descend_z: 3.0
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: 38
y_offset: 6

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2
```

**Remplacer** le `serial:` par celui affiché par `ls /dev/serial/by-id/` — le numéro de série est **unique** à chaque Eddy.

**Points importants :**

- `i2c_bus: i2c0f` → bus I2C du RP2040 utilisé par le chip LDC1612. C'est la valeur par défaut du firmware Eddy BTT.
- `sensor_pin: eddy:gpio26` → pin du RP2040 sur laquelle est câblé le thermistor interne de l'Eddy.
- `x_offset` / `y_offset` → décalage physique entre la buse et le centre du capteur Eddy. À mesurer sur ta machine.
- `descend_z: 3.0` → hauteur de descente lors de la calibration initiale. Remplace l'ancien paramètre `z_offset` déprécié dans Klipper récent.

### 6.1 Include dans `printer.cfg`

Ajouter au début de `printer.cfg` :

```
[include eddy.cfg]
```

Et modifier `[stepper_z]` pour utiliser l'Eddy comme endstop virtuel :

```
[stepper_z]
# ... autres paramètres ...
endstop_pin: probe:z_virtual_endstop
homing_retract_dist: 0
# Commenter l'ancienne ligne :
# position_endstop: 0
```

### 6.2 Redémarrage et calibration

```bash
/etc/init.d/S55klipper_service restart
sleep 20
curl http://localhost:7125/printer/info | python3 -m json.tool | grep state
```

Une fois Klipper en `ready`, procéder aux calibrations Eddy dans l'ordre :

1. `CAL_EDDY_DRIVE_CURRENT` → `LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy` → `SAVE_CONFIG`.
2. `CAL_EDDY_MAPPING` → `PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy` + TESTZ + ACCEPT → `SAVE_CONFIG`.
3. `CAL_BED_MESH` → `BED_MESH_CALIBRATE METHOD=rapid_scan` → `SAVE_CONFIG`.

---

## 7. Maintenance et mises à jour

### 7.1 Quand faut-il refaire `btteddy.uf2` ?

Il faut refaire la compilation et le flash :

- Après une mise à jour importante de Klipper sur le Nebula (si l'incompatibilité de protocole apparaît).
- Si BTT publie une révision hardware de l'Eddy nécessitant un autre Flash chip.
- Pour tester un commit spécifique ou un fork de Klipper.

### 7.2 Procédure complète de mise à jour

Dans le codespace :

```bash
cd /workspaces/klipper
git pull
# ou : git checkout <commit>

make clean
make menuconfig
# (vérifier qu'aucune option n'a changé — sauvegarder)

make
cp out/klipper.uf2 ~/btteddy.uf2
```

Puis flash comme en section 5.

### 7.3 Rollback

Si la nouvelle version pose problème, repasser sur l'ancienne version de `btteddy.uf2` et re-flasher via le bouton BOOT.

Toujours conserver une copie fonctionnelle de `btteddy.uf2` dans `/usr/data/E5M_CK/` sur le Nebula et dans un endroit sûr.

---

## 8. Récapitulatif — commandes minimales

Sur un codespace GitHub Ubuntu vierge :

```bash
# Prérequis
sudo apt update
sudo apt install -y gcc-arm-none-eabi build-essential

# Source Klipper (si pas déjà là)
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper
cd /workspaces/klipper

# Configuration
cat > .config << 'EOF'
CONFIG_MACH_RP2040=y
CONFIG_MCU="rp2040"
CONFIG_RP2040_HAVE_BOOTLOADER=n
CONFIG_RP2040_FLASH_GENERIC_03H=y
CONFIG_RP2040_FLASH_CLKDIV=4
CONFIG_USBSERIAL=y
CONFIG_CLOCK_FREQ=12000000
CONFIG_USB_VENDOR_ID=0x1d50
CONFIG_USB_DEVICE_ID=0x614e
EOF

# Build
make clean
make

# Le firmware est dans out/klipper.uf2
cp out/klipper.uf2 ~/btteddy.uf2
ls -lh ~/btteddy.uf2
```

Puis télécharger `~/btteddy.uf2` via l'explorateur VS Code, flasher comme en section 5.

---

## 9. Notes diverses

### 9.1 Différence avec le firmware officiel BTT

Le dépôt officiel `bigtreetech/Eddy` fournit des `.uf2` précompilés dans un dossier `firmware/`. Ces fichiers sont identiques à ce qu'on compile via la procédure décrite ici, **à la version de Klipper près**.

Si le firmware BTT officiel correspond exactement à la version de Klipper installée sur le Nebula, on peut l'utiliser tel quel sans recompiler. Mais cette situation est rare en pratique : Klipper upstream progresse vite, et BTT publie ses firmwares à intervalles plus espacés.

### 9.2 Reconditionnement en USB serial vs. CAN

Certains produits Eddy plus récents (Eddy Coil, Eddy NG) supportent CAN Bus. Notre configuration est strictement **USB**. Ne pas confondre les options `menuconfig` :

- **Eddy USB** → `CONFIG_USBSERIAL=y`.
- **Eddy Coil** (connecté à un toolhead board via CAN) → `CONFIG_CAN=y` avec configuration CAN spécifique.

Pour le BTT Eddy USB, **toujours** choisir USB.

### 9.3 Flash chip — comment connaître le bon ?

Le chip Flash est marqué sur le PCB du BTT Eddy — un petit boîtier SOIC-8 près du RP2040. Les marquages courants :

| Marquage | Option menuconfig |
|---|---|
| `W25Q080` ou `25Q08xxx` | `W25Q080 with CLKDIV 2` |
| `W25Q16JV` | `W25Q080 with CLKDIV 2` (compatible) |
| Boîtier sans marquage clair | `GENERIC_03H with CLKDIV 4` (plus lent mais universel) |

Sur les Eddy USB BTT actuels (2024-2026), `GENERIC_03H with CLKDIV 4` fonctionne dans 100 % des cas.

### 9.4 UF2 vs BIN — pourquoi UF2 ?

Le format `.bin` est le binaire brut à flasher via un outil tel que `rp2040load`, `openocd`, ou `picotool`. Il nécessite :
- Soit l'accès aux pins SWD du RP2040 (sur le BTT Eddy, ces pins existent mais ne sont pas exposés sur un header).
- Soit un outil logiciel qui parle au protocole de bootloader RP2040.

Le format `.uf2` est conçu pour le flash **par copie de fichier** : pas d'outil requis, juste un `cp`. C'est la méthode idéale sur le Nebula qui n'a pas `rp2040load` installé et ne peut pas facilement l'installer (toolchain limitée).

**`.uf2` = flash par copie. C'est notre unique méthode viable sur le Nebula.**

---

*Document rédigé en avril 2026 dans le cadre du projet E5M-CK.*
