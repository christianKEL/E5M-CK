# MEMO — Calibration complète BTT Eddy USB sur Ender 5 Max + Klipper mainline

**Date :** 28 avril 2026
**Machine :** Creality Ender 5 Max (CoreXY) + Nebula Pad
**Klipper :** mainline `v0.13.0-628-g373f200ca` (commit mars 2026)
**Sonde :** BTT Eddy USB (RP2040 + LDC1612) — serial `usb-Klipper_rp2040_50445059303E9B1C-if00`
**Objectif :** établir une référence Z=0 précise et thermiquement indépendante via la fonctionnalité **TAP** native de Klipper mainline, et générer des bed mesh corrects à chaud.

---

## 1. Contexte initial et problème

L'Ender 5 Max stock utilise un fork Klipper Creality avec une calibration Z par Nebula Pad propriétaire. L'objectif du projet E5M-CK est de migrer vers **Klipper mainline pur** + sonde **BTT Eddy USB** pour bénéficier des fonctionnalités modernes (input shaper, bed mesh haute densité, tap).

Le module `probe_eddy_current` de Klipper mainline souffre cependant d'une **dérive thermique non négligeable** : à chaud (bed à 65°C, plateau 45°C), la fréquence du capteur LDC1612 dérive et fausse la mesure de Z.

Trois sources de vérité concurrentes apparaissent :

| Méthode | Z mesuré (à chaud) | Sensibilité thermique |
|---|---|---|
| Paper test | 0 (référence subjective, ±0.05mm) | aucune |
| PROBE scan | +0.010 à +0.030mm | **forte** (dérive) |
| **PROBE tap** | **−0.121mm** | **aucune (théorique)** |

L'écart scan↔tap de ~0.15mm démontre l'ampleur du problème thermique. Sans tap, le bed mesh est faussé.

---

## 2. Découvertes clés via les PR Klipper

Deux PR éclairent la stratégie correcte sur Klipper mainline :

### PR #7186 — `temperature_probe: use tap for calibration` (open)

Ouvert par nefelim4ag (collaborator Klipper). Permettrait `TEMPERATURE_PROBE_CALIBRATE METHOD=tap` pour automatiser le calibrage thermique du capteur. **Pas encore mergé** au moment de ce mémo, donc inutilisable directement, mais montre la direction prise par les développeurs.

### PR #7179 — `runtime calibration curve adjustment` (closed/wontfix)

Ouvert par nefelim4ag, fermé après merge du PR #7220 qui ajoute `tap_z_offset` en config option. **L'auteur confirme** :

> *"this PR is mostly not necessary, because now the scan curve can be compensated with 1 G-Code Z Offset"*

Le PR #7179 fournit cependant **les macros `_ADJ_SCAN_FROM_TAP` et `SET_SCAN_FROM_TAP`** qui implémentent le pattern complet **tap-then-scan** : faire un tap pour Z=0 vrai, puis un scan au même point pour calibrer dynamiquement le bed mesh à la température réelle de print.

**Insight central** : le tap est le seul Z=0 fiable à chaud. Mais le bed mesh utilise le mode scan (à hauteur ~0.5mm). Sans correction, le scan voit une fréquence biaisée par la dérive thermique → mesh incorrect. La macro `SET_SCAN_FROM_TAP` calcule la différence et l'applique via `SET_GCODE_OFFSET`.

### PR #7220 — `tap_z_offset` (mergé)

Permet d'ajouter un offset constant après tap directement dans la config :

```ini
[probe_eddy_current btt_eddy]
tap_z_offset: 0.05
```

Sens vérifié expérimentalement (voir §6) : `z_reported = z_actual − tap_z_offset` (positif rend la valeur plus négative dans le rapport).

---

## 3. Architecture finale `eddy.cfg`

```ini
[mcu eddy]
serial: /dev/serial/by-id/usb-Klipper_rp2040_50445059303E9B1C-if00
restart_method: command

[temperature_sensor btt_eddy_mcu]
sensor_type: temperature_mcu
sensor_mcu: eddy
min_temp: 10
max_temp: 100

[probe_eddy_current btt_eddy]
sensor_type: ldc1612
descend_z: 0.5
i2c_mcu: eddy
i2c_bus: i2c0f
x_offset: 38.0
y_offset: 6.0
tap_threshold: 50

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2

# --- Macros officielles Klipper ---
[gcode_macro _RELOAD_Z_OFFSET_FROM_PROBE]
gcode:
  {% set Z = printer.toolhead.position.z %}
  SET_KINEMATIC_POSITION Z={Z - printer.probe.last_probe_position.z}

[gcode_macro SET_Z_FROM_PROBE]
description: Refine Z=0 with a probe (use METHOD=tap for thermal-independent reference)
gcode:
  {% set METHOD = params.METHOD | default("automatic") %}
  PROBE METHOD={METHOD}
  _RELOAD_Z_OFFSET_FROM_PROBE
  G0 Z5

# --- Pattern tap-then-scan (issu PR #7179) ---
[gcode_macro _ADJ_SCAN_FROM_TAP]
gcode:
  {% set OFFSET = printer.probe.last_probe_position.z %}
  SET_GCODE_OFFSET Z={(-OFFSET)}

[gcode_macro SET_SCAN_FROM_TAP]
description: Tap-then-scan: precise Z + thermally compensated bed mesh reference
gcode:
  SET_Z_FROM_PROBE METHOD=tap
  {% set is_absolute = printer.gcode_move.absolute_coordinates %}
  G90
  {% set cf = printer.configfile.settings %}
  {% set eddy = cf["probe_eddy_current btt_eddy"] %}
  {% set amap = printer.gcode_move.axis_map %}
  {% set tpos = printer.gcode_move.position %}
  G0 Z5 F300
  G0 Y{tpos[amap["Y"]] - eddy.y_offset} X{tpos[amap["X"]] - eddy.x_offset} F3000
  G0 Z{eddy.descend_z} F300
  PROBE METHOD=scan
  _ADJ_SCAN_FROM_TAP
  {% if not is_absolute %}
  G91
  {% endif %}
```

**Notes importantes sur les options non-supportées** :
- `tap_speed` et `tap_drive_current` n'existent **pas** comme options de section dans cette version Klipper. Ils sont passables uniquement en runtime via `PROBE METHOD=tap TAP_SPEED=5 TAP_DRIVE_CURRENT=16`.
- `tap_z_offset` est valide mais finalement non utilisé (voir §6).

---

## 4. Architecture `homing.cfg`

```ini
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
    G28 Z                          # rough Z homing via Eddy virtual_endstop
    G1 Z10 F600
    SET_Z_FROM_PROBE METHOD=tap    # precise refinement via TAP
  {% endif %}
```

Le `G28 Z` initial fait un homing rapide en mode scan (virtual_endstop), puis `SET_Z_FROM_PROBE METHOD=tap` raffine avec un tap précis. Le résultat : Z=0 = position physique réelle du contact nozzle/bed à la température courante.

---

## 5. Procédure de calibration complète (chronologique)

Ordre strict, chaque étape produit des données nécessaires à la suivante.

### Étape 1 — Calibration `LDC_CALIBRATE_DRIVE_CURRENT` (à froid, 1 fois)

Calibre l'amplitude du signal du capteur LDC1612. Peu sensible thermiquement, à faire une seule fois à froid.

```
G28
G0 X200 Y200 F6000
G1 Z20 F600
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
SAVE_CONFIG
```

**Résultat obtenu :** `reg_drive_current = 15`

### Étape 2 — Préchauffe + homogénéisation thermique

```
M140 S65          ; bed à température print PLA
M104 S150         ; nozzle chaud mais sans oozing (recommandation Arksine)
TEMPERATURE_WAIT SENSOR=heater_bed MINIMUM=64
TEMPERATURE_WAIT SENSOR=extruder MINIMUM=148
G4 P30000         ; 30s d'homogénéisation
```

### Étape 3 — Calibration height map (à chaud)

```
G1 X200 Y200 F6000
G1 Z30 F600
SET_KINEMATIC_POSITION Z=200    ; trick pour permettre les mouvements Z manuels
```

Paper test manuel via flèches Z (pas 0.1mm), puis :

```
SET_KINEMATIC_POSITION Z=0
G1 Z1 F300
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
```

Suivre les invites interactives `TESTZ Z=-0.1` / `ACCEPT`. Klipper balaye sur ~3 minutes.

```
SAVE_CONFIG
```

**Résultat obtenu (cal à chaud) :**

```
Calibration temp:    45.53°C
Total freq range:    47268.777 Hz
Global MAD_Hz:       17.612
Per-Z noise:
  z=0.250:  MAD_Hz = 25.370
  z=0.530:  MAD_Hz = 24.114
  z=1.010:  MAD_Hz = 26.179
  z=2.010:  MAD_Hz =  9.242
  z=3.010:  MAD_Hz = 11.083
```

**Observation importante** : le bruit est ~2× plus élevé près du bed (z<1mm) que loin (z>2mm). C'est attendu — vibrations mécaniques perturbent l'inductance.

### Étape 4 — Calibration `tap_threshold`

Le `tap_threshold` détermine la sensibilité de détection du contact lors du tap.

**Méthode officielle Klipper** :
- Estimation initiale : `tap_threshold = MAD_Hz_global × 2 = 17.6 × 2 ≈ 35`
- Mais comme le bruit est plus élevé près du bed (zone de tap réelle), on prend plutôt `MAD_Hz_zone × 2 = 25.2 × 2 ≈ 50`
- Affinage par **bracketing** : commencer haut (sécurité), descendre par paliers

**Bracketing effectué** :

| Threshold | Comportement |
|---|---|
| 25 | Pas de détection (sous le bruit) |
| 26 | Détection à z=−0.083 (limite basse) |
| 50 | Détection stable à z≈−0.121 |

→ La règle de pouce **2× la limite basse** (= 26 × 2 = 52) confirme `tap_threshold = 50` comme bon compromis.

### Étape 5 — Validation `PROBE_ACCURACY METHOD=tap`

```
G28
G1 X200 Y200 F6000
G1 Z10 F600
SET_KINEMATIC_POSITION X=200 Y=200 Z=10
G0 Z5
PROBE_ACCURACY METHOD=tap
```

**Résultat obtenu (à chaud, threshold=50)** :

```
range:     0.0089 mm   (cible doc Klipper : <0.020 mm)  ← 2× mieux que requis
stddev:    0.0031 mm
average:  -0.1213 mm   (décalage stable vs paper test)
samples:   10
```

**Verdict** : précision excellente. La machine tap avec ±5 microns de répétabilité.

### Étape 6 — Test bed mesh thermiquement compensé

```
G28
G1 X200 Y200 F6000
SET_SCAN_FROM_TAP
```

**Résultat observé** :
```
probe: at 161.997,193.999 bed will contact at z=0.023446    ← TAP au point cible (corrigé via x_offset/y_offset)
Result: at 161.995,193.999 estimate contact at z=0.052404   ← SCAN au même point
```

La macro a appliqué automatiquement `SET_GCODE_OFFSET Z=-0.052` pour compenser la différence tap↔scan. Le bed mesh subséquent en mode scan est donc thermiquement correct.

---

## 6. Décision finale sur `tap_z_offset`

Le décalage systématique de **−0.121mm** (à chaud, cal coil 47°C) puis **−0.113mm** (cal coil 53°C) signifie que le tap détecte le contact ~0.1 à 0.12mm **sous** le Z=0 défini par paper test.

**Trois hypothèses** :

1. Paper test trop haut (épaisseur papier ~0.1mm + sensation subjective)
2. Compression mécanique sous le tap (~0.02-0.05mm)
3. Combinaison des deux

**Test du sens de `tap_z_offset`** :

Avec `tap_z_offset: 0.100`, mesures successives :

```
Sans offset : z = -0.121 (référence)
Avec offset : z = -0.213 (shift de -0.092 ≈ -0.100)
```

**Conclusion** : `tap_z_offset` **positif rend la valeur reportée plus négative**. Formule : `z_reported = z_actual − tap_z_offset`.

**Décision finale : NE PAS utiliser `tap_z_offset`**. Le tap devient la **vraie référence Z=0 physique**. Conséquences :
- La machine imprimera **0.1mm plus bas** que ce que faisait le paper test
- La première couche sera plus écrasée que par le passé
- Compensation à appliquer dans Orca via `SET_GCODE_OFFSET Z=+0.05` ou `Z=+0.10` selon préférence

**Validation expérimentale** : `G1 Z0` après `G28` écrase fortement le papier — confirme que le tap est plus précis que le paper test, qui était systématiquement trop haut de ~0.1mm.

---

## 7. Bug stepcompress Klipper et correctif O'Connor

**Symptôme** : crash après ~2h47 de print avec :

```
Error in syncemitter 'stepper_x' step generation
stepcompress o=5 i=-1034346 c=1 a=0: Invalid sequence
mcu.error: Internal error in stepcompress
```

**Cause racine** : optimisation "step on both edges" trop agressive sur Klipper mainline récent (commits autour de `b7c243db`, avril 2025).

**Correctif Kevin O'Connor** (créateur de Klipper, source : [Discourse #23304](https://klipper.discourse.group/t/issues-with-stepper-drift-on-latest-klipper/23304)) :

> *"set `step_pulse_duration: 0.000000501` in all stepper config sections (the 501ns is just enough to turn off "step on both edges" optimization)"*

**Application** : ajouté à `[stepper_x]`, `[stepper_y]`, `[stepper_z]`, `[extruder]` :

```ini
step_pulse_duration: 0.000000501
```

**Effet** : ~0.4µs de plus par pas, vitesse max théorique baisse de ~5% (négligeable en usage normal), mais step generation devient robuste face aux changements rapides de paramètres.

**Note importante** : Orca avec `gcode_flavor = klipper` génère ~35k `SET_VELOCITY_LIMIT` sur un print de 2h. Avec `gcode_flavor = marlin (Legacy)` c'est ~80k `M204 + M205`. Le bug stepcompress est sensible à la fréquence de ces commandes. La solution `step_pulse_duration: 501ns` rend Klipper tolérant indépendamment du nombre de commandes — le problème est résolu côté firmware, pas côté slicer.

---

## 8. Bed mesh : configuration finale

```ini
[bed_mesh]
horizontal_move_z: 2
scan_overshoot: 8
speed: 200
mesh_min: 46.0, 15.0
mesh_max: 391.0, 386.0
probe_count: 25, 25
fade_start: 1.0
fade_end: 20
fade_target: 0
mesh_pps: 4, 4
algorithm: bicubic
bicubic_tension: 0.2
```

**Choix `horizontal_move_z = 2`** : sécurise contre les collisions en cas de bed warp ou objet sur le plateau. La doc PR #7179 recommande 0.5mm pour la précision maximale, mais 2mm est un compromis sécurité acceptable. La compensation `SET_SCAN_FROM_TAP` reste partiellement valide à 2mm (la dérive thermique à 2mm est différente qu'à 0.5mm, mais le tap reste la référence Z=0 absolue).

**Choix `mesh_min/max`** : calculés pour respecter la formule officielle Klipper :
- `mesh_min_x = max(15, x_offset + scan_overshoot) = max(15, 38 + 8) = 46`
- `mesh_min_y = max(15, y_offset + scan_overshoot) = max(15, 6 + 8) = 15`
- `mesh_max_x = bed_max - scan_overshoot - margin = 400 - 8 - 1 = 391`
- `mesh_max_y = bed_max - scan_overshoot - margin = 400 - 8 - 6 = 386`

---

## 9. Macro NOZZLE_CLEAR_ON_BRUSH (cohérence avec le tap)

**Pourquoi indispensable** : un blob de plastique au bout du nozzle fausse complètement la mesure tap (la sonde détecte le contact avec le blob, pas avec le nozzle réel).

**Architecture en 4 phases** :
1. Brush à 180°C (5 passes zigzag) — extraction du plastique fluide
2. **Cooldown actif** : passes zigzag continues + part fans à 100% pendant la descente 180→140°C
3. Stabilisation `M109 S140` (fans coupés)
4. Brush final à 140°C (5 passes) — finition à plastique solide

**Avantages du cooldown actif** :
- Plus efficace : le plastique passe par sa phase semi-solide (160°C) où il s'arrache mieux
- Plus rapide : ~50s total au lieu de ~60-65s en cooldown statique
- Garantit nozzle parfaitement propre à 140°C — température idéale pour tap (pas d'oozing)

**Important sur les fans Creality** :
- L'Ender 5 Max stock utilise `[output_pin fan0]` et `[output_pin fan1]` (PWM via `SET_PIN`), pas le `[fan]` standard Klipper
- `scale: 255` dans la config — donc `VALUE=255` pour 100%, **pas** `VALUE=1.0`
- Alternative : `M106 S255` (la macro custom dans `gcode_macro.cfg` redirige vers les deux fans)

---

## 10. Start G-code Orca final

```gcode
; ═══════════════════════════════════════════════════════════
; E5M-CK Start G-code — TAP-based Z reference + clean nozzle
; ═══════════════════════════════════════════════════════════

; --- Reset state ---
PRINT_FLAG_CLEAR
BED_MESH_CLEAR
G92 E0
M220 S100
M221 S100

; --- Heat bed first ---
M140 S{first_layer_bed_temperature[0]}
M190 S{first_layer_bed_temperature[0]}
G4 P300000                                         ; 5min thermal homogenization

; --- Pre-heat nozzle just enough to clean ---
M104 S140                                          ; raised to 180 by NOZZLE_CLEAR_ON_BRUSH

; --- Initial home (uses TAP refinement automatically) ---
G28

; --- Clean nozzle on brush, ends at 140°C ---
NOZZLE_CLEAR_ON_BRUSH

; --- Re-home Z with clean nozzle for accurate tap ---
G1 X200 Y200 F6000
G1 Z25 F600
SET_Z_FROM_PROBE METHOD=tap

; --- Bed mesh (thermally compensated via tap-then-scan) ---
G1 Z25 F600
SET_SCAN_FROM_TAP
BED_MESH_CALIBRATE METHOD=rapid_scan

; --- Final nozzle heat to print temperature ---
M104 S{first_layer_temperature[0]}
M109 S{first_layer_temperature[0]}

; --- Optional first-layer Z compensation (tune if needed) ---
; SET_GCODE_OFFSET Z=0.05 MOVE=1

; --- Prime line ---
G92 E0
G1 Z2.0 F3000
G1 X-1.0 Y120 Z0.28 F5000.0
G1 X-1.0 Y245.0 Z0.28 F1500.0 E7
G1 X-0.6 Y245.0 Z0.28 F5000.0
G1 X-0.6 Y120 Z0.28 F1500.0 E15
G92 E0
G1 E-1.0000 F1800
G1 Z2.0 F3000
G1 E0.0000 F1800
```

**Séquence chronologique** :
1. Bed à temp → 5min homogénéisation
2. Nozzle à 140°C → G28 (avec tap au cours, possiblement avec nozzle un peu sale)
3. NOZZLE_CLEAR_ON_BRUSH → nozzle propre à 140°C
4. Tap final propre → Z=0 précis
5. SET_SCAN_FROM_TAP → calcule l'offset thermique scan↔tap
6. BED_MESH_CALIBRATE rapid_scan → mesh thermiquement compensé
7. Chauffe finale nozzle à temp print
8. Prime line + impression

---

## 11. Points d'attention et règles d'or

### À retenir
1. **Le tap est la seule référence Z=0 fiable à chaud.** Le scan dérive thermiquement, le paper test est subjectif.
2. **Toujours tapper avec un nozzle propre.** Sinon mesure faussée.
3. **Tapper à nozzle 140°C.** Pas plus chaud (oozing), pas plus froid (filament durci peut faire faux contact).
4. **`tap_threshold` se calibre par bracketing** : 2× la limite basse de détection est un bon point de départ.
5. **`PROBE_ACCURACY METHOD=tap` doit donner range < 0.02mm** (cible doc Klipper). Si plus, threshold à ajuster.
6. **`step_pulse_duration: 0.000000501` est obligatoire** sur Klipper mainline récent pour éviter les crashes stepcompress.

### Pièges connus
- `tap_speed` et `tap_drive_current` ne sont **pas** des options de section, seulement des paramètres runtime de `PROBE METHOD=tap`.
- `tap_z_offset` agit dans le sens contre-intuitif (positif → valeur reportée plus négative).
- Les fans Creality ont `scale: 255`, donc `SET_PIN VALUE=255` pour 100% (pas 1.0).
- L'Eddy USB peut figer après un crash MCU — le power cycle complet de l'imprimante remet en ordre.
- Klipper bloqué en init `mcu 'eddy': Starting serial connect` avec rafale de `webhooks shakehands` = Eddy ne répond pas → débrancher/rebrancher câble USB ou power cycle.

### Bonnes pratiques workflow
- **Calibration drive_current** : 1 fois à froid, jamais à refaire
- **Calibration height map** : 1 fois **à chaud** (température print typique), à refaire si changement de plaque/nozzle/configuration thermique
- **Calibration `tap_threshold`** : 1 fois après la calibration height map, à refaire si bruit de sonde change significativement
- **Bed mesh à chaud avant chaque print** : automatique via `SET_SCAN_FROM_TAP + BED_MESH_CALIBRATE METHOD=rapid_scan ADAPTIVE=1` dans le start G-code

---

## 12. État final validé

| Élément | Valeur |
|---|---|
| `reg_drive_current` | 15 |
| Calibration temp probe | 45.53°C |
| MAD_Hz global (chaud) | 17.612 |
| **`tap_threshold`** | **50** |
| `tap_z_offset` | non utilisé (tap = vraie référence Z=0) |
| Range PROBE_ACCURACY tap | 0.0089mm |
| StdDev PROBE_ACCURACY tap | 0.0031mm |
| Décalage tap vs paper test | -0.113mm (paper test trop haut) |
| `step_pulse_duration` | 0.000000501 (501ns) sur tous steppers |
| Input shaper X | zv 50.6 Hz |
| Input shaper Y | mzv 41.8 Hz |
| Bed mesh | 25×25, scan_overshoot=8, mesh_min=46/15, mesh_max=391/386 |

**Date de validation :** 28 avril 2026
**Validation :** PROBE_ACCURACY METHOD=tap → range 0.009mm < cible 0.020mm ✅

---

## Références

- Documentation officielle Klipper Eddy : https://www.klipper3d.org/Eddy_Probe.html
- PR #7186 (open) : `temperature_probe: use tap for calibration`
- PR #7179 (closed) : `runtime calibration curve adjustment` — fournit pattern SET_SCAN_FROM_TAP
- PR #7220 (mergé) : ajoute `tap_z_offset` config option
- Discourse Klipper #23304 : recommandation O'Connor `step_pulse_duration: 0.000000501`
