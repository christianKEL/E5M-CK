# TRAME D'INSTALLATION VALIDÉE
## BTT Eddy USB + Klipper Mainline + GuppyScreen
## Creality Ender 5 Max — Nebula Pad
### Christian KELHETTER — Avril 2026

---

> **Ce document est mis à jour en temps réel.**
> Chaque étape est consignée UNIQUEMENT après validation sur machine réelle.
> Ce document servira de base pour l'automatisation future.

---

## PRÉREQUIS MATÉRIELS

- Creality Ender 5 Max
- Nebula Pad d'origine
- BTT Eddy USB
- BTT Pad 7 (pour compiler le firmware Eddy — une seule fois)
- Clé USB FAT32
- PC Windows avec SSH configuré

---

## ÉTAPE 1 — FACTORY RESET ✅

**Objectif :** Remettre le Nebula dans son état d'usine.

**Procédure :**
1. Créer un fichier vide nommé `factory_reset` (sans extension) sur une clé USB FAT32
2. Éteindre le Nebula
3. Brancher la clé USB sur le Nebula
4. Allumer le Nebula
5. Attendre le redémarrage automatique

**Résultat :**
- Klipper fork Creality actif : `/usr/share/klipper/klippy/klippy.py`
- Config active : `/usr/data/printer_data/config/printer.cfg`
- Moonraker : absent
- Helper Script : absent

---

## ÉTAPE 2 — INSTALLATION HELPER SCRIPT ✅

**Objectif :** Installer Moonraker, Fluidd et les outils de base.

**Commande SSH :**
```bash
git clone --depth 1 https://github.com/Guilouz/Creality-Helper-Script.git /usr/data/helper-script
```

**Puis lancer le script :**
```bash
sh /usr/data/helper-script/helper.sh
```

**Dans le menu Helper Script, installer :**
- Moonraker + Nginx
- Fluidd (port 4408)
- Klipper Gcode Shell Command

**Résultat validé :**
- Moonraker actif sur port 7125 ✅
- Fluidd accessible sur http://[IP]:4408 ✅
- Klipper fork Creality `ready` version `09faed31-dirty` ✅

---

## ÉTAPE 3 — COMPILATION c_helper.so MIPS ✅

**Objectif :** Compiler `c_helper.so` pour MIPS XBurst2 avec le toolchain Ingenic officiel.

**Prérequis :** PC x86_64 Linux (ou GitHub Codespaces — gratuit, dans le navigateur)

**Toolchain requis :** Ingenic GCC 5.2 + nan2008 (Dafang-Hacks, disponible sur GitHub)

```bash
# Sur GitHub Codespaces (https://github.com/codespaces) — repo Klipper3d/klipper

# 1. Cloner le toolchain Ingenic GCC 5.2 x86_64
git clone --depth 1 https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1 \
  ~/ingenic-toolchain

# 2. Cloner Klipper mainline (ou utiliser le repo ouvert dans Codespaces)
# Le repo klipper est déjà disponible dans /workspaces/klipper

# 3. Compiler c_helper.so avec flags nan2008
cd /workspaces/klipper/klippy/chelper

~/ingenic-toolchain/bin/mips-linux-gnu-gcc -shared -fPIC -O2 \
    -mnan=2008 -mfp64 -mabs=2008 \
    $(ls *.c) \
    -o c_helper.so

# 4. Vérifier les flags (doit afficher 0x70001407 avec nan2008)
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -h c_helper.so | grep "Flags"
# Résultat attendu : Flags: 0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2

# 5. Vérifier les dépendances (doit afficher uniquement libc.so.6)
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -d c_helper.so | grep "NEEDED"
```

**Transfert vers le Nebula :**
```bash
# Télécharger c_helper.so depuis Codespaces → PC Windows
# (clic droit sur le fichier dans l'explorateur Codespaces → Download)

# Depuis PowerShell Windows → Pad 7
scp C:\Users\...\Downloads\c_helper.so biqu@[IP_PAD7]:/tmp/c_helper.so

# Depuis Pad 7 → Nebula
scp /tmp/c_helper.so root@[IP_NEBULA]:/usr/data/klipper/klippy/chelper/c_helper.so

# Sauvegarder dans E5M_CK
cp /usr/data/klipper/klippy/chelper/c_helper.so /usr/data/E5M_CK/c_helper.so
```

**Validation :**
```bash
/usr/share/klippy-env/bin/python3 -c \
  "import ctypes; ctypes.CDLL('/usr/data/klipper/klippy/chelper/c_helper.so'); print('OK')"
# Résultat attendu : OK
```

**Résultat validé :**
- Flags : `0x70001407` avec `nan2008` ✅
- Dépendance : `libc.so.6` uniquement ✅
- Chargement Python : `OK` ✅

---

## ÉTAPE 4 — INSTALLATION KLIPPER MAINLINE ✅

**Objectif :** Installer Klipper mainline `v0.13.0-628-g373f200ca` sur le Nebula.

```bash
# 1. Créer dossier de travail E5M_CK
mkdir -p /usr/data/E5M_CK

# 2. Backup du service Klipper Creality
cp /etc/init.d/S55klipper_service /usr/data/E5M_CK/S55klipper_service.creality.bak

# 3. Cloner Klipper mainline
git clone https://github.com/Klipper3d/klipper.git /usr/data/klipper

# 4. Placer c_helper.so compilé (voir Étape 3)
cp /usr/data/E5M_CK/c_helper.so /usr/data/klipper/klippy/chelper/

# 5. Copier modules Creality nécessaires
cp /usr/share/klipper/klippy/extras/gcode_shell_command.py /usr/data/klipper/klippy/extras/
cp /usr/share/klipper/klippy/extras/custom_macro.py /usr/data/klipper/klippy/extras/

# 6. Créer config_mainline
mkdir -p /usr/data/printer_data/config_mainline
cp /usr/data/printer_data/config/*.cfg /usr/data/printer_data/config_mainline/
cp /usr/data/printer_data/config/moonraker.conf /usr/data/printer_data/config_mainline/
```

**Patches printer.cfg :**
```bash
python3 << 'EOF'
sections_to_comment = [
    'mcu leveling_mcu', 'mcu rpi', 'bl24c16f', 'prtouch_v2',
    'hx711s', 'accel_chip_proxy', 'resonance_tester',
    'filter', 'dirzctl', 'temperature_sensor mcu_temp',
]
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'r') as f:
    lines = f.readlines()
result = []
in_section = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        section = stripped[1:-1].strip()
        in_section = any(section == s for s in sections_to_comment)
    elif stripped.startswith('['):
        in_section = False
    if in_section and stripped and not stripped.startswith('#'):
        result.append('#' + line)
    else:
        result.append(line)
content = ''.join(result)
content = content.replace('CXSAVE_CONFIG', 'SAVE_CONFIG')
content = content.replace('max_accel_to_decel: 5000', 'minimum_cruise_ratio: 0.5')
content = content.replace('[include sensorless.cfg]', '#[include sensorless.cfg]')
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'w') as f:
    f.write(content)
print("Done")
EOF
```

**Modifier stepper_z et bed_mesh :**
```bash
python3 << 'EOF'
import re
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'r') as f:
    content = f.read()
content = re.sub(
    r'(endstop_pin: tmc2209_stepper_z:virtual_endstop.*)',
    r'#\1\nendstop_pin: probe:z_virtual_endstop\nhoming_retract_dist: 0',
    content
)
content = re.sub(r'^(position_endstop: 0.*)$', r'#\1', content, flags=re.MULTILINE)
old_mesh = re.search(r'\[bed_mesh\].*?(?=\n\[)', content, re.DOTALL)
if old_mesh:
    new_mesh = """[bed_mesh]
horizontal_move_z: 2
scan_overshoot: 8
speed: 200
mesh_min: 29, 5
mesh_max: 371, 395
probe_count: 40, 40
fade_start: 1.0
fade_end: 20
fade_target: 0
mesh_pps: 4, 4
algorithm: bicubic
bicubic_tension: 0.2
"""
    content = content[:old_mesh.start()] + new_mesh + content[old_mesh.end():]
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'w') as f:
    f.write(content)
print("Done")
EOF
```

**Créer eddy.cfg :**
```bash
EDDY_SERIAL=$(ls /dev/serial/by-id/ | grep rp2040)
cat > /usr/data/printer_data/config_mainline/eddy.cfg << EOF
[mcu eddy]
serial: /dev/serial/by-id/${EDDY_SERIAL}

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
z_offset: 1.0
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: 24
y_offset: 0

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2
EOF
```

**Créer homing.cfg :**
```bash
cat > /usr/data/printer_data/config_mainline/homing.cfg << 'EOF'
[homing_override]
axes: xyz
set_position_z: 0
gcode:
  G90
  {% set home_all = 'X' not in params and 'Y' not in params and 'Z' not in params %}
  G1 Z30 F600
  {% if home_all or 'X' in params or 'Y' in params %}
    G28 Y
    G1 Y400 F2400
  {% endif %}
  {% if home_all or 'X' in params %}
    G28 X
    G1 X380 F2400
  {% endif %}
  {% if home_all or 'Z' in params %}
    G0 X200 Y200 F6000
    G28 Z
    G1 Z10 F600
  {% endif %}
EOF
```

**Ajouter includes et modifier service :**
```bash
sed -i '1s/^/[include eddy.cfg]\n[include homing.cfg]\n/' \
  /usr/data/printer_data/config_mainline/printer.cfg

sed -i 's|PY_SCRIPT=/usr/share/klipper/klippy/klippy.py|PY_SCRIPT=/usr/data/klipper/klippy/klippy.py|' \
  /etc/init.d/S55klipper_service
sed -i 's|$PRINTER_CONFIG_DIR/printer.cfg|/usr/data/printer_data/config_mainline/printer.cfg|' \
  /etc/init.d/S55klipper_service
```

**Résultat validé :**
- Klipper mainline `v0.13.0-628-g373f200ca` : `ready` ✅
- Commit : `373f200ca` ✅
- Eddy USB détecté : `usb-Klipper_rp2040_50445059303E9B1C-if00` ✅

---

## ROLLBACK CREALITY

```bash
sed -i 's|/usr/data/klipper/klippy/klippy.py|/usr/share/klipper/klippy/klippy.py|' /etc/init.d/S55klipper_service
sed -i 's|config_mainline/printer.cfg|config/printer.cfg|' /etc/init.d/S55klipper_service
/etc/init.d/S55klipper_service restart
```

---

## ÉTAPE 5 — FLASH BTT EDDY USB ✅

**Objectif :** Flasher le firmware Klipper mainline sur l'Eddy.

**Compiler btteddy.uf2** (sur GitHub Codespaces, commit identique à Klipper mainline) :
```bash
# Dans Codespaces — repo klipper déjà cloné
cd /workspaces/klipper
make clean
make menuconfig
# Paramètres :
#   Micro-controller Architecture → Raspberry Pi RP2040
#   Bootloader offset             → No bootloader
#   Flash chip                    → GENERIC_03H with CLKDIV 4
#   Communication interface       → USB
make
# Résultat : out/klipper.uf2 (version v0.13.0-628-g373f200ca)
```

**Flash via méthode UF2 sur le Nebula :**
```bash
# 1. Brancher l'Eddy en mode BOOT (bouton maintenu) sur le port USB Nebula
# 2. Vérifier détection bootloader
lsusb | grep "2e8a:0003"

# 3. L'Eddy est monté automatiquement
mount | grep sda
# → /dev/sda1 on /tmp/udisk/sda1 type vfat

# 4. Copier le firmware (flash automatique)
cp /usr/data/E5M_CK/btteddy.uf2 /tmp/udisk/sda1/
sync
# L'Eddy redémarre automatiquement

# 5. Vérifier que l'Eddy est en mode Klipper
ls /dev/serial/by-id/
# → usb-Klipper_rp2040_50445059303E9B1C-if00
```

**Résultat validé :**
- Flash UF2 sans outil supplémentaire ✅
- Serial : `usb-Klipper_rp2040_50445059303E9B1C-if00` ✅

---

## ÉTAPE 6 — GUPPYSCREEN ✅

**Installation :** via Helper Script → Customize → GuppyScreen

**Copier les modules dans klipper mainline :**
```bash
cp /usr/data/guppyscreen/k1_mods/guppy_module_loader.py /usr/data/klipper/klippy/extras/
cp /usr/data/guppyscreen/k1_mods/calibrate_shaper_config.py /usr/data/klipper/klippy/extras/
cp /usr/data/guppyscreen/k1_mods/tmcstatus.py /usr/data/klipper/klippy/extras/

mkdir -p /usr/data/printer_data/config_mainline/GuppyScreen
cp /usr/data/guppyscreen/scripts/guppy_cmd.cfg \
   /usr/data/printer_data/config_mainline/GuppyScreen/

sed -i '1s/^/[include GuppyScreen\/*.cfg]\n/' \
   /usr/data/printer_data/config_mainline/printer.cfg
```

**Thème rouge :**
```bash
python3 -c "
import json
with open('/usr/data/guppyscreen/guppyconfig.json', 'r') as f:
    c = json.load(f)
c['theme'] = 'red'
with open('/usr/data/guppyscreen/guppyconfig.json', 'w') as f:
    json.dump(c, f, indent=4)
"
```

**Macros visibles (uniquement celles pour calibration Eddy) :**
```bash
python3 << 'EOF'
import urllib.request, json

macros_hidden = [
    "ACCURATE_G28", "AUTOTUNE_SHAPERS", "BEDPID", "CANCEL_PRINT",
    "FINISH_INIT", "FIRST_FLOOR_PAUSE", "FIRST_FLOOR_PAUSE_POSITION",
    "FIRST_FLOOR_RESUME", "G29", "GREEN_LED_OFF", "GREEN_LED_ON",
    "INPUTSHAPER", "LIGHT_LED_OFF", "LIGHT_LED_ON", "LOAD_MATERIAL",
    "M106", "M107", "M204", "M205", "M600", "M900", "PAUSE",
    "PRINTER_PARAM", "PRINT_CALIBRATION_EXT", "PRINT_FINI_ZDN",
    "QUIT_MATERIAL", "RED_LED_OFF", "RED_LED_ON", "RESUME",
    "STRUCTURE_PARAM", "TUNOFFINPUTSHAPER", "YELLOW_LED_OFF",
    "YELLOW_LED_ON", "ZZ_OFFSET_TEST", "Z_OFFSET_TEST",
    "GUPPY_SHAPERS", "GUPPY_EXCITATE_AXIS_AT_FREQ",
    "GUPPY_BELTS_SHAPER_CALIBRATION"
]
settings = {
    "SET_KINEMATIC_Z_200": {"hidden": False},
    "CENTER_TOOLHEAD": {"hidden": False}
}
for m in macros_hidden:
    settings[m] = {"hidden": True}

data = json.dumps({
    "namespace": "guppyscreen",
    "key": "macros.settings",
    "value": settings
}).encode()
req = urllib.request.Request(
    "http://localhost:7125/server/database/item",
    data=data,
    headers={"Content-Type": "application/json"},
    method="POST"
)
print("OK:", urllib.request.urlopen(req).status)
EOF
```

**Macros créées dans `GuppyScreen/macros_guppy.cfg` :**
```ini
[gcode_macro SET_KINEMATIC_Z_200]
description: SET_KINEMATIC Z 200
gcode:
  SET_KINEMATIC_POSITION Z=200

[gcode_macro CENTER_TOOLHEAD]
description: Centre la tête d'impression X=200 Y=200
gcode:
  G90
  G0 X200 Y200 F6000
```

---

## ÉTAPE 7 — CALIBRATION EDDY ✅

**Ordre des opérations :**
1. Homing XY depuis GuppyScreen
2. `CENTER_TOOLHEAD` depuis GuppyScreen
3. `SET_KINEMATIC_Z_200` depuis GuppyScreen
4. Descendre le plateau manuellement à ~20mm sous la buse (flèches Z GuppyScreen)

**A — Drive Current :**
```
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
SAVE_CONFIG
# Résultat : reg_drive_current: 15
```

**B — Mapping hauteurs :**
```
G28 X Y → CENTER_TOOLHEAD → SET_KINEMATIC_Z_200
Descendre plateau au contact papier
SET_KINEMATIC_POSITION Z=0
G1 Z1 F300
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
SAVE_CONFIG
```

**C — Vérification Z=0 :**
```
G28 → vérifier papier → babystepping si besoin → Save
```

**D — Bed Mesh :**
```
BED_MESH_CALIBRATE METHOD=rapid_scan
SAVE_CONFIG
```

**Résultat validé :**
- `reg_drive_current: 15` ✅
- Z=0 correct au papier ✅
- Bed mesh 40x40 points ✅

---

## ÉTAPE 8 — CORRECTIONS ET PATCHES ✅

**Supprimer avertissement `z_offset` deprecated dans `eddy.cfg` :**
```bash
# Remplacer z_offset par descend_z (nouveau paramètre Klipper mainline)
# Supprimer la ligne z_offset et ajouter descend_z: 3.0
```

**Corriger `max_accel` trop élevé (100000 → 10000) :**
```bash
sed -i 's/max_accel: 100000/max_accel: 10000/' \
  /usr/data/printer_data/config_mainline/printer.cfg
```

**Corriger `mesh_max` Y pour éviter sondage hors plateau :**
```bash
sed -i 's/mesh_max: 371, 395/mesh_max: 371, 385/' \
  /usr/data/printer_data/config_mainline/printer.cfg
```

**Supprimer avertissement MCU deprecated (STEPPER_STEP_BOTH_EDGE) :**
```bash
sed -i '105s/^/# /' /usr/data/klipper/klippy/stepper.py
rm /usr/data/klipper/klippy/stepper.pyc
```

**Supprimer avertissement Moonraker config folder :**
```bash
# Renommer config Creality et créer symlink
mv /usr/data/printer_data/config /usr/data/printer_data/config_creality_bak
ln -sf /usr/data/printer_data/config_mainline /usr/data/printer_data/config

# Supprimer config_path deprecated dans moonraker.conf si présent
sed -i '/config_path: \/usr\/data\/printer_data\/config_mainline/d' \
  /usr/data/printer_data/config_mainline/moonraker.conf
```

**Rollback Creality mis à jour :**
```bash
sed -i 's|/usr/data/klipper/klippy/klippy.py|/usr/share/klipper/klippy/klippy.py|' /etc/init.d/S55klipper_service
sed -i 's|config_mainline/printer.cfg|config/printer.cfg|' /etc/init.d/S55klipper_service
rm /usr/data/printer_data/config
mv /usr/data/printer_data/config_creality_bak /usr/data/printer_data/config
/etc/init.d/S55klipper_service restart
```

**Switch mainline :**
```bash
sed -i 's|/usr/share/klipper/klippy/klippy.py|/usr/data/klipper/klippy/klippy.py|' /etc/init.d/S55klipper_service
sed -i 's|config/printer.cfg|config_mainline/printer.cfg|' /etc/init.d/S55klipper_service
mv /usr/data/printer_data/config /usr/data/printer_data/config_creality_bak
ln -sf /usr/data/printer_data/config_mainline /usr/data/printer_data/config
/etc/init.d/S55klipper_service restart
```

---

## ÉTAPE 9 — START G-CODE ORCA (à faire)

---

## NOTES TECHNIQUES VALIDÉES

| Observation | Détail |
|---|---|
| Direction Z | Z+ descend le plateau (inverse convention habituelle) |
| Ordre homing CoreXY | Y en premier, puis X — obligatoire |
| Endstops X/Y | Physiques au MAXIMUM (X≈400, Y≈401) |
| `homing_positive_dir` | `true` obligatoire sur X et Y |
| Klipper mainline sur Nebula | Commit `373f200ca` (v0.13.0-628), Python 3.8.2, MIPS 32-bit |
| `c_helper.so` compilation | Toolchain Ingenic GCC 5.2 (Dafang-Hacks GitHub) sur x86_64 |
| `c_helper.so` flags requis | `-mnan=2008 -mfp64 -mabs=2008` → flags `0x70001407` |
| `c_helper.so` plateforme compilation | GitHub Codespaces (x86_64) — Pad 7 est ARM64, incompatible |
| `temperature_mcu` GD32F303 | Non supporté en mainline → commenter |
| z_offset Eddy | Deprecated → remplacer par `descend_z: 3.0` |
| MCU deprecated warning | Commenté dans `stepper.py` ligne 105 |
| Moonraker config folder | Symlink `/config` → `config_mainline` |
| GuppyScreen macros cachées | Via API Moonraker namespace `guppyscreen` |
| GuppyScreen thème | `guppyconfig.json` → `"theme": "red"` |
| `max_accel` Creality | 100000 par défaut → corriger à 10000 |
| `mesh_min/max` calcul | Coordonnées SONDE (Eddy), pas buse. Klipper ne convertit PAS automatiquement |
| `reg_drive_current` Eddy | 15 (valeur nominale validée) |
| Offsets Eddy validés | `x_offset: 38`, `y_offset: 6` (mesurés physiquement + rayon capteur) |

---

## FORMULE CALCUL AUTOMATIQUE mesh_min / mesh_max

**À recalculer si les offsets Eddy changent.**

Variables :
- `X_OFFSET` = x_offset dans eddy.cfg
- `Y_OFFSET` = y_offset dans eddy.cfg  
- `SCAN_OVERSHOOT` = scan_overshoot dans printer.cfg (défaut: 8)
- `POS_MAX_X` = position_max du stepper_x
- `POS_MAX_Y` = position_max du stepper_y

Formule :
```
mesh_min_x = X_OFFSET + SCAN_OVERSHOOT
mesh_min_y = Y_OFFSET
mesh_max_x = POS_MAX_X - X_OFFSET - SCAN_OVERSHOOT
mesh_max_y = POS_MAX_Y - Y_OFFSET
```

**Script de calcul automatique :**
```bash
python3 << 'EOF'
X_OFFSET = 38
Y_OFFSET = 6
SCAN_OVERSHOOT = 8
POS_MAX_X = 406
POS_MAX_Y = 401

mesh_min_x = X_OFFSET + SCAN_OVERSHOOT
mesh_min_y = Y_OFFSET
mesh_max_x = POS_MAX_X - X_OFFSET - SCAN_OVERSHOOT
mesh_max_y = POS_MAX_Y - Y_OFFSET

print(f"mesh_min: {mesh_min_x}, {mesh_min_y}")
print(f"mesh_max: {mesh_max_x}, {mesh_max_y}")

import re
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'r') as f:
    content = f.read()
content = re.sub(r'mesh_min:.*', f'mesh_min: {mesh_min_x}, {mesh_min_y}', content)
content = re.sub(r'mesh_max:.*', f'mesh_max: {mesh_max_x}, {mesh_max_y}', content)
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'w') as f:
    f.write(content)
print("printer.cfg mis à jour.")
EOF
```

**Valeurs validées sur l'Ender 5 Max :**
```
mesh_min: 46, 6
mesh_max: 360, 395
```

---

*Document mis à jour au fil des étapes validées.*

---

## ÉTAPE 9 — MACROS DE CALIBRATION ✅

**Fichier :** `/usr/data/printer_data/config_mainline/macros_calibration.cfg`

**Include dans printer.cfg :**
```bash
sed -i '1s/^/[include macros_calibration.cfg]\n/' \
  /usr/data/printer_data/config_mainline/printer.cfg
```

**Règles de rédaction :**
- Code et commentaires en anglais
- Messages RESPOND en anglais
- Emojis : ✅ confirmation, 🔄 attente, ℹ️ information
- Paramètres optionnels avec valeurs par défaut

**CAL_BED_Z_TILT** — Nivellement mécanique du bed (G28 + FORCE_MOVE x8 + G28 final)

**CAL_BED_PID** — Calibration PID du bed (paramètre TEMP, défaut 65°C)
```
CAL_BED_PID           # → 65°C
CAL_BED_PID TEMP=80   # → 80°C
```

**Correction heater_bed :**
```
pwm_cycle_time: 0.3   # ajouté dans [heater_bed]
```

**Rendre visibles dans GuppyScreen :**
```python
current["CAL_BED_Z_TILT"] = {"hidden": False}
current["CAL_BED_PID"] = {"hidden": False}
```

---

## ÉTAPE 10 — START G-CODE ORCA (à faire)

---

## ÉTAPE 3b — PATCH CREALITY SERVERS ✅

**Objectif :** Neutraliser `app-server` et `master-server` pour éviter les interférences avec Klipper mainline.

**Problème :** Ces deux processus Creality tournent en parallèle de Klipper mainline et peuvent :
- `app-server` : se connecter au socket Klipper et envoyer des commandes non sollicitées
- `master-server` : envoyer `SET_HEATER_TEMPERATURE HEATER=heater_bed` de façon autonome

**Solution :** Patch binaire (même longueur pour éviter de corrompre les offsets) :
- `app-server` : `/tmp/klippy_uds` → `/tmp/klippy_udx` (connexion au socket impossible)
- `master-server` : `SET_HEATER_TEMPERATURE` → `NOP_HEATER_TEMPERATURE` (commandes bed ignorées)

**Script :** `/usr/data/E5M_CK/patch_servers.sh`
```bash
sh /usr/data/E5M_CK/patch_servers.sh
reboot
```

**Notes :**
- Backup automatique des binaires originaux (`.orig`) avant patch
- `wifi-server`, `audio-server`, `upgrade-server` non affectés
- Rollback : `cp /usr/bin/app-server.orig /usr/bin/app-server && cp /usr/bin/master-server.orig /usr/bin/master-server`

---

## CONTENU COMPLET — macros_calibration.cfg

```ini
# ═══════════════════════════════════════════════════════
# CALIBRATION MACROS — Ender 5 Max
# ═══════════════════════════════════════════════════════

# ─── MECHANICAL BED LEVELING ───
# Synchronizes the 4 Z motors by forcing movement
# Ends with a full G28 ready to print
[gcode_macro CAL_BED_Z_TILT]
description: Mechanical bed Z tilt leveling via FORCE_MOVE
gcode:
  RESPOND TYPE=command MSG="🔄 Starting mechanical bed leveling..."
  RESPOND TYPE=command MSG="🔄 Homing all axes..."
  G28
  RESPOND TYPE=command MSG="✅ Homing complete"
  RESPOND TYPE=command MSG="🔄 Moving bed to lowest position..."
  G1 Z400 F300
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 1/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 2/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 3/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 4/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 5/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 6/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 7/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Synchronizing Z motors - step 8/8..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=5 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Raising bed..."
  FORCE_MOVE STEPPER=stepper_z DISTANCE=-200 VELOCITY=5
  RESPOND TYPE=command MSG="🔄 Final homing..."
  G28
  RESPOND TYPE=command MSG="✅ Mechanical leveling complete - Printer is ready"

# ─── BED PID CALIBRATION ───
# Calibrates PID parameters for the heated bed
# Optional parameter: TEMP (default: 65°C)
# Usage: CAL_BED_PID or CAL_BED_PID TEMP=80
[gcode_macro CAL_BED_PID]
description: Bed PID calibration (default 65C, usage: CAL_BED_PID TEMP=80)
gcode:
  {% set temp = params.TEMP|default(65)|int %}
  RESPOND TYPE=command MSG="🔄 Starting bed PID calibration at {temp}°C..."
  RESPOND TYPE=command MSG="ℹ️ This may take several minutes"
  PID_CALIBRATE HEATER=heater_bed TARGET={temp}
  RESPOND TYPE=command MSG="✅ Bed PID calibration complete - Run SAVE_CONFIG to save"
```

> Note : `POPUP_TEST` macro présente dans le fichier — à supprimer en production.

---

## CONFIGURATION FLUIDD — Axe Z inversé ✅

Sur l'Ender 5 Max, Z+ descend le plateau. Fluidd doit être configuré en conséquence.

**Commande à exécuter après installation de Fluidd :**
```bash
python3 << 'EOF'
import urllib.request, json

data = json.dumps({
    "namespace": "fluidd",
    "key": "uiSettings.general.axis",
    "value": {"z": {"inverted": True}}
}).encode()

req = urllib.request.Request(
    "http://localhost:7125/server/database/item",
    data=data,
    headers={"Content-Type": "application/json"},
    method="POST"
)
print("OK:", urllib.request.urlopen(req).status)
EOF
```

---

## MACROS CALIBRATION — Eddy et Bed Mesh

**Ajoutées dans `macros_calibration.cfg` :**

**`CAL_EDDY_DRIVE_CURRENT`** — Recalibration drive current Eddy
```
G28 X Y → CENTER_TOOLHEAD → SET_KINEMATIC_Z_200
Descendre manuellement à ~20mm → LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy → SAVE_CONFIG
```

**`CAL_EDDY_MAPPING`** — Recalibration mapping hauteurs Eddy
```
G28 X Y → CENTER_TOOLHEAD → SET_KINEMATIC_Z_200
Descendre au contact papier → SET_KINEMATIC_POSITION Z=0 → G1 Z1 F300
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy → SAVE_CONFIG
```

**`CAL_BED_MESH`** — Bed mesh complet 40x40 points
```
G28 → BED_MESH_CLEAR → BED_MESH_CALIBRATE METHOD=rapid_scan → SAVE_CONFIG
```

**PID validés :**
```
Bed  : pid_Kp=53.200  pid_Ki=0.414  pid_Kd=1707.722
Nozzle: pid_Kp=32.043 pid_Ki=2.967  pid_Kd=86.514
```

---

## PATCH CRITIQUE — heater_bed et extruder control

**Problème :** Dans la config Creality, `control` est commenté dans `[heater_bed]` et `[extruder]`.
Klipper mainline exige que ce paramètre soit présent et non commenté.
Après un `SAVE_CONFIG` suite à une calibration PID, Klipper peut se retrouver en erreur.

**Fix :**
```bash
sed -i 's/#control = pid/control = pid/' \
  /usr/data/printer_data/config_mainline/printer.cfg
sed -i 's/#control = watermark/control = watermark/' \
  /usr/data/printer_data/config_mainline/printer.cfg
```

**À intégrer dans le script d'installation** lors du patch de `printer.cfg`,
avant tout démarrage de Klipper mainline.

---

## RÈGLE CRITIQUE — Ne jamais écrire après #*# SAVE_CONFIG

**La section `#*# <--- SAVE_CONFIG --->` doit TOUJOURS être en toute fin de `printer.cfg`.**

Klipper écrit et lit exclusivement depuis la fin du fichier. Toute ligne ajoutée après `#*#` corrompt la lecture des paramètres sauvegardés (PID, z_offset, bed_mesh, etc.).

**Règles :**
- ❌ Ne jamais utiliser `cat >>` ou `echo >>` sur `printer.cfg`
- ✅ Toujours insérer avant le bloc `#*#` via `sed` ou `python3`
- ✅ Vérifier après chaque modification : `tail -5 printer.cfg` → `#*#` doit être en dernier

**Méthode d'insertion correcte :**
```bash
python3 << 'EOF'
with open('/usr/data/printer_data/config_mainline/printer.cfg', 'r') as f:
    content = f.read()

new_section = """
[ma_nouvelle_section]
parametre: valeur

"""

# Insérer AVANT le bloc SAVE_CONFIG
content = content.replace(
    '#*# <---------------------- SAVE_CONFIG ---------------------->',
    new_section + '#*# <---------------------- SAVE_CONFIG ---------------------->'
)

with open('/usr/data/printer_data/config_mainline/printer.cfg', 'w') as f:
    f.write(content)
print("Done")
EOF
```
