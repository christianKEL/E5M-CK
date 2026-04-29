# MEMO — Calibration BTT Eddy USB sur Ender 5 Max + Klipper mainline

**Date :** 29 avril 2026 — version 3
**Machine :** Creality Ender 5 Max (CoreXY) + Nebula Pad (IP 192.168.1.94)
**Klipper :** mainline `v0.13.0-628-g373f200ca` (mars 2026)
**Sonde :** BTT Eddy USB (RP2040 + LDC1612)
**Serial :** `/dev/serial/by-id/usb-Klipper_rp2040_50445059303E9B1C-if00`
**Slicer :** OrcaSlicer (gcode_flavor : Marlin Legacy, arc_fitting OFF)

---

## ⚠️ RÈGLE D'OR ABSOLUE

> **AVANT TOUT TAP, ÉLOIGNER LA TÊTE DE 10 MM AU MINIMUM.**

Sans cette marge de 10 mm, le tap échoue avec `Unable to detect tap: insufficient slope delta`. Le LDC1612 a besoin d'une **baseline de fréquence stable** sur quelques millimètres avant de pouvoir détecter une variation au contact.

Cette règle est **systématiquement intégrée** dans :
- `homing.cfg` → `G1 Z10 F600` avant `SET_Z_FROM_PROBE METHOD=tap`
- Macro `SET_SCAN_FROM_TAP` → lift conditionnel `if Z<10 → G1 Z{10-current_z}`
- Macro `PROBE_ACCURACY_TAP` → setup à Z≥10 + retract de 3mm entre samples
- Toute commande manuelle `PROBE METHOD=tap` → précédée de `G0 Z10` ou `G1 Z10`

Aucune exception.

---

## 1. Contexte

L'Ender 5 Max stock utilise un fork Klipper Creality avec calibration Z par Nebula Pad propriétaire. Le projet E5M-CK migre vers **Klipper mainline pur** + sonde **BTT Eddy USB** pour bénéficier des fonctionnalités modernes : input shaper, bed mesh haute densité, fonctionnalité **TAP** thermal-independent.

### Évolution du mount Eddy

Le mount Eddy a été repositionné le 29/04/2026, passant de `(x=38, y=6)` à **`(x=22, y=0)`**. Cette modification a apporté un gain de précision majeur.

| Métrique | Mount initial (x=38, y=6) | **Mount actuel (x=22, y=0)** |
|---|---|---|
| Limite basse threshold | 26 | **14** (2× plus précis) |
| `tap_threshold` retenu | 50 | **28** |
| Z reporté à chaud | -0.121 mm | **+0.014 mm** (quasi-zéro flex) |
| Range PROBE_ACCURACY (10 samples) | 0.0089 mm | **0.0103 mm** |
| StdDev | 0.0031 mm | **0.0026 mm** |
| `tap_z_offset` requis | Oui (≈0.12) | **Non** |
| Drift scan↔tap @ chaud | ≈0.052 mm | ≈0.260 mm |

Le nouveau mount est **mécaniquement plus précis** (signal/bruit 2× meilleur, flex quasi-nul), au prix d'un drift thermique scan↔tap plus prononcé que la `drift_calibration` ne corrigeait avant. Solution adoptée : compensation dynamique à chaque print via `SET_SCAN_FROM_TAP`.

---

## 2. Découvertes critiques sur Klipper mainline

### 2.1 Bug Klipper #1 — `samp_retract_dist` hardcodé à 0 pour Eddy

Dans `klippy/extras/probe_eddy_current.py`, classe `EddyParameterHelper.get_probe_params()` (ligne 855) :

```python
if method not in ['scan', 'rapid_scan', 'tap']:
    return self._param_helper.get_probe_params(gcmd)
probe_speed = gcmd.get_float("PROBE_SPEED", 5.0, above=0.)
lift_speed = gcmd.get_float("LIFT_SPEED", 5.0, above=0.)
samples = gcmd.get_int("SAMPLES", 1, minval=1)
samp_retract_dist = 0.    # ← HARDCODÉ À 0
```

Pour les méthodes `scan`, `rapid_scan` et `tap`, `samp_retract_dist` est **hardcodé à 0**, ignorant à la fois la config et les paramètres runtime.

**Conséquence pratique** : `PROBE_ACCURACY METHOD=tap` échoue dès le 2e sample avec `Unable to detect tap: insufficient slope delta`. Le 1er tap réussit, mais le 2e démarre depuis la position de contact (sans lift), et la sonde voit une fréquence "déjà saturée" → erreur slope delta.

**Documenté officiellement** (Klipper Config_Changes 20260318) :
> *"The `[probe_eddy_current]` config options speed, lift_speed, samples, sample_retract_dist, samples_result, samples_tolerance, and samples_tolerance_retries no longer apply to probe commands using METHOD=scan, METHOD=rapid_scan, nor METHOD=tap."*

Mais même les paramètres runtime ne fonctionnent pas pour le retract sur tap. Bug de cohérence interne Klipper.

**Workaround** : macro custom `PROBE_ACCURACY_TAP` qui réimplémente la boucle multi-sample avec lift correct entre chaque tap (voir section 5).

### 2.2 Bug Klipper #2 — `SET_GCODE_OFFSET Z_ADJUST=` cumule entre appels

Le paramètre `Z_ADJUST=` est **incrémental** : il s'ajoute à `gcode_offset.z` actuel. Plusieurs appels successifs de `SET_SCAN_FROM_TAP` cumulaient les offsets :

- Appel 1 : drift=0.230 → Z_ADJUST=-0.230 → gcode_offset.z = -0.230
- Appel 2 : drift=0.235 → Z_ADJUST=-0.235 → gcode_offset.z = **-0.465** ❌ (au lieu de -0.235)

**Solution** : utiliser `Z=` (absolu) au lieu de `Z_ADJUST=` (relatif) dans `_ADJ_SCAN_FROM_TAP`. Une seule commande remplace la valeur courante.

### 2.3 Tap échoue si Z trop bas

Si on lance un tap depuis une position Z < ≈5-8 mm, Klipper ne peut pas mesurer un slope delta clair → `insufficient slope delta`. La règle d'or **lift 10mm avant tap** résout ce problème de manière définitive.

### 2.4 Calibration height map à refaire après remount

Après changement physique du mount Eddy, la calibration height map (`PROBE_EDDY_CURRENT_CALIBRATE`) doit être refaite. La table fréquence ↔ Z est spécifique à la position physique de la coil par rapport au bed.

### 2.5 PROBE_ACCURACY METHOD=tap est cassé

Pour les raisons décrites en 2.1, **`PROBE_ACCURACY METHOD=tap` ne fonctionne pas**. Klipper affiche le 1er résultat puis échoue avec `insufficient slope delta` sur les samples suivants.

→ Toujours utiliser la macro custom **`PROBE_ACCURACY_TAP`**.

### 2.6 PR Klipper référencées

- **PR #7186** (open) — `temperature_probe: use tap for calibration`
- **PR #7179** (closed) — fournit le pattern `SET_SCAN_FROM_TAP`
- **PR #7220** (mergé) — ajoute l'option `tap_z_offset` (non utilisée dans notre setup)

---

## 3. Configuration finale `eddy.cfg`

```ini
# ═══════════════════════════════════════════════════════
# BTT Eddy USB — Klipper mainline configuration
# Aligned with OFFICIAL Klipper documentation + PR #7179
# https://www.klipper3d.org/Eddy_Probe.html
# ═══════════════════════════════════════════════════════

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
x_offset: 22.0
y_offset: 0.0
# Tap parameters — populated after PROBE_EDDY_CURRENT_CALIBRATE @ hot
tap_threshold: 28
# Note Klipper Config_Changes 20260318: samples/sample_retract_dist/etc.
# en config N'APPLIQUENT PAS pour scan/rapid_scan/tap. Passer en runtime
# sur la commande PROBE.

[temperature_probe btt_eddy]
sensor_type: Generic 3950
sensor_pin: eddy:gpio26
horizontal_move_z: 2

# ─── OFFICIAL KLIPPER HOMING CORRECTION MACROS ───
# https://www.klipper3d.org/Eddy_Probe.html#homing-correction-macros

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

# ─── TAP-THEN-SCAN PATTERN (PR #7179) ───
# Allows bed_mesh in scan mode to be thermally-compensated by tap
# Usage in start G-code:
#   SET_SCAN_FROM_TAP
#   BED_MESH_CALIBRATE ADAPTIVE=1 METHOD=rapid_scan HORIZONTAL_MOVE_Z=<descend_z>

[gcode_macro _ADJ_SCAN_FROM_TAP]
description: Internal helper — applies absolute Z gcode offset = -drift
gcode:
    {% set OFFSET = printer.probe.last_probe_position.z %}
    {% set probe_temp = printer["temperature_probe btt_eddy"].temperature %}
    RESPOND TYPE=command MSG="Scan-from-tap : drift={OFFSET|round(4)} mm @ coil={probe_temp|round(1)}°C"
    # Use Z= (absolute) instead of Z_ADJUST= (relative) to avoid accumulation
    SET_GCODE_OFFSET Z={(-OFFSET)}

[gcode_macro SET_SCAN_FROM_TAP]
description: Tap-then-scan : Z précis (1 tap) + référence mesh thermiquement compensée (scan median 5x)
gcode:
    # MANDATORY: always lift Z to 10mm before tap (avoid "insufficient slope delta")
    {% set current_z = printer.toolhead.position.z|float %}
    {% if current_z < 10 %}
        G91
        G1 Z{10 - current_z} F600
        G90
    {% endif %}
    # Tap = 1 sample (multi-sample tap broken by Klipper bug)
    SET_Z_FROM_PROBE METHOD=tap
    {% set is_absolute = printer.gcode_move.absolute_coordinates %}
    G90
    {% set cf = printer.configfile.settings %}
    {% set eddy = cf["probe_eddy_current btt_eddy"] %}
    {% set amap = printer.gcode_move.axis_map %}
    {% set tpos = printer.gcode_move.position %}
    G0 Z5 F300
    G0 X{tpos[amap["X"]] - eddy.x_offset} Y{tpos[amap["Y"]] - eddy.y_offset} F3000
    M400
    G4 P200
    G0 Z{eddy.descend_z} F300
    M400
    G4 P200
    # Scan multi-sample works (no retract needed since scan stays at fixed Z)
    PROBE METHOD=scan SAMPLES=5 SAMPLES_RESULT=median
    _ADJ_SCAN_FROM_TAP
    G0 Z5 F600
    {% if not is_absolute %}
        G91
    {% endif %}
```

### Points clés de la config

| Paramètre | Valeur | Justification |
|---|---|---|
| `descend_z` | 0.5 | Hauteur scan référence (PR #7179 recommandation) |
| `x_offset` / `y_offset` | 22.0 / 0.0 | Mount actuel |
| `tap_threshold` | 28 | Calibré : limite basse 14 × 2 |
| `tap_z_offset` | absent | Mount précis = pas de flex à compenser |
| `temperature_probe.horizontal_move_z` | 2 | Hauteur sécurité pour mesh, non critique |
| `samples`, `sample_retract_dist` | absents de config | Ignorés depuis Klipper 20260318 |
| `M400 + G4 P200` autour de Z | présents | Stabilise le sensor avant lecture |

---

## 4. Configuration `homing.cfg`

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
        G1 Z10 F600                    # MANDATORY: lift to 10mm before tap
        SET_Z_FROM_PROBE METHOD=tap    # precise Z=0 refinement via TAP
    {% endif %}
```

Le `G1 Z10 F600` **avant** le tap est obligatoire. Sans cette montée, le tap échoue.

---

## 5. Macro `PROBE_ACCURACY_TAP` (workaround bug Klipper)

Cette macro custom contourne le bug Klipper qui rend `PROBE_ACCURACY METHOD=tap` inutilisable. Elle réimplémente la boucle multi-sample avec lift correct entre chaque tap, et calcule les statistiques.

### Localisation

`/usr/data/printer_data/config/macros_E5M_CK.cfg`

### Code

```ini
[gcode_macro PROBE_ACCURACY_TAP]
description: Wrapper around PROBE METHOD=tap with proper retract between samples (workaround Klipper bug ligne 855 probe_eddy_current.py)
variable_samples_data: []
variable_samples_sq_sum: 0.0
gcode:
    {% set samples = params.SAMPLES|default(10)|int %}
    {% set retract = params.SAMPLE_RETRACT_DIST|default(3)|float %}
    {% set tap_threshold = params.TAP_THRESHOLD|default(0)|int %}
    {% set lift_speed = params.LIFT_SPEED|default(5)|float %}

    {% set xpos = printer.toolhead.position.x|float %}
    {% set ypos = printer.toolhead.position.y|float %}
    {% set zpos = printer.toolhead.position.z|float %}

    RESPOND TYPE=command MSG="PROBE_ACCURACY_TAP at X:{xpos|round(3)} Y:{ypos|round(3)} Z:{zpos|round(3)}"
    RESPOND TYPE=command MSG="  (samples={samples} retract={retract} threshold={tap_threshold if tap_threshold > 0 else 'config'})"

    SET_GCODE_VARIABLE MACRO=PROBE_ACCURACY_TAP VARIABLE=samples_data VALUE="[]"
    SET_GCODE_VARIABLE MACRO=PROBE_ACCURACY_TAP VARIABLE=samples_sq_sum VALUE=0.0

    {% for i in range(samples) %}
        G91
        G0 Z{retract} F{lift_speed * 60}
        G90
        {% if tap_threshold > 0 %}
            PROBE METHOD=tap TAP_THRESHOLD={tap_threshold}
        {% else %}
            PROBE METHOD=tap
        {% endif %}
        _PROBE_ACCURACY_TAP_RECORD
    {% endfor %}

    G91
    G0 Z{retract} F{lift_speed * 60}
    G90

    _PROBE_ACCURACY_TAP_REPORT


[gcode_macro _PROBE_ACCURACY_TAP_RECORD]
description: Internal helper for PROBE_ACCURACY_TAP - records last z and accumulates squared sum
gcode:
    {% set last_z = printer.probe.last_z_result|float %}
    {% set existing = printer["gcode_macro PROBE_ACCURACY_TAP"].samples_data %}
    {% set new_data = existing + [last_z] %}
    {% set old_sq = printer["gcode_macro PROBE_ACCURACY_TAP"].samples_sq_sum|float %}
    {% set new_sq = old_sq + last_z * last_z %}
    SET_GCODE_VARIABLE MACRO=PROBE_ACCURACY_TAP VARIABLE=samples_data VALUE="{new_data}"
    SET_GCODE_VARIABLE MACRO=PROBE_ACCURACY_TAP VARIABLE=samples_sq_sum VALUE={new_sq}


[gcode_macro _PROBE_ACCURACY_TAP_REPORT]
description: Internal helper for PROBE_ACCURACY_TAP - computes and reports stats
gcode:
    {% set data = printer["gcode_macro PROBE_ACCURACY_TAP"].samples_data %}
    {% set sum_sq = printer["gcode_macro PROBE_ACCURACY_TAP"].samples_sq_sum|float %}
    {% set n = data|length %}
    {% if n < 1 %}
        RESPOND TYPE=error MSG="PROBE_ACCURACY_TAP: no samples collected"
    {% else %}
        {% set mn = data|min %}
        {% set mx = data|max %}
        {% set rng = mx - mn %}
        {% set avg = (data|sum) / n %}
        {% set variance = (sum_sq / n) - (avg * avg) %}
        {% set stddev = variance ** 0.5 if variance > 0 else 0 %}
        {% set sorted_data = data|sort %}
        {% if n % 2 == 1 %}
            {% set median = sorted_data[(n - 1) // 2] %}
        {% else %}
            {% set median = (sorted_data[n // 2 - 1] + sorted_data[n // 2]) / 2 %}
        {% endif %}
        RESPOND TYPE=command MSG="probe accuracy results: maximum {'%.6f' % mx}, minimum {'%.6f' % mn}, range {'%.6f' % rng}, average {'%.6f' % avg}, median {'%.6f' % median}, standard deviation {'%.6f' % stddev}"
    {% endif %}
```

### Notes d'implémentation

- **Variance via formule à une passe** : `Var = E[X²] - E[X]²`. Évite le besoin d'une boucle accumulator (le `namespace` Jinja n'est pas disponible dans Klipper sandbox).
- **`SET_GCODE_VARIABLE`** pour stocker `samples_data` (liste) et `samples_sq_sum` (somme des carrés). Permet d'accumuler à chaque sample sans namespace.
- **Compatible PROBE_ACCURACY** : même format de sortie pour interopérabilité.

### Usage

```
# Setup obligatoire avant
G28
G1 X200 Y200 F6000
G1 Z10 F600                                  # ← LIFT 10mm AVANT TAP
SET_KINEMATIC_POSITION X=200 Y=200 Z=10

# Lancement
PROBE_ACCURACY_TAP                           # défaut: SAMPLES=10
PROBE_ACCURACY_TAP SAMPLES=5                 # plus rapide
PROBE_ACCURACY_TAP SAMPLES=20 TAP_THRESHOLD=30   # paramètres runtime
```

### Sortie type

```
PROBE_ACCURACY_TAP at X:200.000 Y:200.000 Z:5.000
  (samples=10 retract=3.0 threshold=config)
probe: at 200.000,200.000 bed will contact at z=0.001
... (10 lignes similaires)
probe accuracy results: maximum 0.001817, minimum -0.005905, range 0.007722, average -0.001651, median -0.001786, standard deviation 0.002766
```

---

## 6. Procédure de calibration complète

### Pré-requis avant chaque calibration

- Bed et nozzle propres (pas de plastique)
- `NOZZLE_CLEAR_ON_BRUSH` exécuté si possible
- Stable thermiquement (5 min d'homogénéisation après cible atteinte)
- **Tête au moins à 10 mm avant chaque tap**

### Étape 1 — `LDC_CALIBRATE_DRIVE_CURRENT` (à froid, 1 fois après remount)

Calibre l'amplitude du signal du capteur LDC1612.

```
G28
G0 X200 Y200 F6000
G1 Z20 F600
LDC_CALIBRATE_DRIVE_CURRENT CHIP=btt_eddy
SAVE_CONFIG
```

Klipper redémarre. Résultat actuel : `reg_drive_current = 15`.

### Étape 2 — Préchauffe + homogénéisation thermique

```
M140 S65
M104 S150
TEMPERATURE_WAIT SENSOR=heater_bed MINIMUM=64
TEMPERATURE_WAIT SENSOR=extruder MINIMUM=148
G4 P30000        # 30s minimum, 5min recommandé pour grand bed
```

### Étape 3 — Calibration height map à chaud (`PROBE_EDDY_CURRENT_CALIBRATE`)

```
G1 X200 Y200 F6000
G1 Z30 F600
SET_KINEMATIC_POSITION Z=200    # trick pour mouvements Z manuels
```

Paper test manuel via Fluidd (flèches Z par pas de 0.1 mm) jusqu'au drag léger du papier. Puis :

```
SET_KINEMATIC_POSITION Z=0
G1 Z1 F300
PROBE_EDDY_CURRENT_CALIBRATE CHIP=btt_eddy
```

Suivre les invites interactives (`TESTZ Z=-0.1`, `ACCEPT` quand drag OK). Klipper balaye sur ~3 minutes.

```
SAVE_CONFIG
```

Résultat actuel à 45.5°C coil : `Total freq range: 47268.777 Hz`, `Global MAD_Hz: 17.612`.

### Étape 4 — Calibration `tap_threshold` par bracketing

C'est la méthode officielle Klipper. On commence haut, on descend par paliers, et on identifie la **limite basse** où le tap commence à échouer (sous le bruit).

#### Setup obligatoire

```
G28
G1 X200 Y200 F6000
G1 Z10 F600                              # ← LIFT 10mm OBLIGATOIRE
SET_KINEMATIC_POSITION X=200 Y=200 Z=10
G0 Z5
```

#### Bracketing (entre chaque test, lift Z à 5mm minimum)

```
PROBE METHOD=tap TAP_THRESHOLD=80
G0 Z5
PROBE METHOD=tap TAP_THRESHOLD=50
G0 Z5
PROBE METHOD=tap TAP_THRESHOLD=30
G0 Z5
PROBE METHOD=tap TAP_THRESHOLD=20
G0 Z5
PROBE METHOD=tap TAP_THRESHOLD=15
G0 Z5
PROBE METHOD=tap TAP_THRESHOLD=12
```

⚠️ Le `G0 Z5` entre chaque PROBE est essentiel : sans lift, le 2e PROBE part de la position de contact et échoue avec `insufficient slope delta` (même bug que PROBE_ACCURACY).

#### Identifier la limite basse

À un moment, le tap arrête de détecter avec `Unable to detect tap: insufficient slope delta`. La **valeur juste au-dessus** du fail est la limite basse.

**Bracketing actuel (mount x=22, y=0)** :
- Threshold 12 → fail
- Threshold 13 → fail
- **Threshold 14 → détecte z=+0.014** ← limite basse

#### Choisir tap_threshold

**Règle de pouce officielle Klipper** : `tap_threshold = limite_basse × 2`.

→ `14 × 2 = 28` → **`tap_threshold = 28`** retenu.

### Étape 5 — Validation par `PROBE_ACCURACY_TAP`

```
G28
G1 X200 Y200 F6000
G1 Z10 F600                              # ← LIFT 10mm OBLIGATOIRE
SET_KINEMATIC_POSITION X=200 Y=200 Z=10
G0 Z5
PROBE_ACCURACY_TAP SAMPLES=10
```

Résultats actuels (mount x=22 y=0, threshold=28, à froid) :

```
samples=10  retract=3.0  threshold=config
range:    0.0103 mm    ← cible Klipper <0.020 mm, 2× mieux
stddev:   0.0026 mm    ← excellent (2.6 microns)
average:  +0.0554 mm
median:   +0.0548 mm
```

Verdict : **précision ±5 microns tap-à-tap**. Calibration validée.

### Étape 6 — Persister `tap_threshold` dans `eddy.cfg`

```bash
sed -i 's|^tap_threshold:.*|tap_threshold: 28|' /usr/data/printer_data/config/eddy.cfg
/etc/init.d/S55klipper_service restart
```

### Étape 7 — Test `SET_SCAN_FROM_TAP`

```
G28
G1 X200 Y200 F6000
SET_SCAN_FROM_TAP
```

La macro lift automatiquement à 10mm si nécessaire (règle d'or intégrée).

Résultat type (à froid, coil ≈35°C) :

```
probe: at 200.000,200.000 bed will contact at z=-0.001332    ← TAP @ centre
Result: at 200.003,200.001 estimate contact at z=0.260722    ← SCAN au point corrigé via x/y_offset
Scan-from-tap : drift=0.2607 mm @ coil=34.6°C
```

→ Macro applique automatiquement `SET_GCODE_OFFSET Z=-0.2607` pour compenser le drift thermique scan↔tap.

### Étape 8 — Validation non-cumul de l'offset

```
SET_SCAN_FROM_TAP
SET_SCAN_FROM_TAP
```

Les 2 appels successifs doivent reporter un drift **similaire** (≈0.26mm) et l'offset gcode appliqué doit rester ≈-0.26mm (pas se cumuler à -0.52mm).

Vérifier avec :

```
GET_POSITION
```

Cherche la ligne `gcode:` dans la sortie. Le Z affiché reflète l'offset gcode courant.

---

## 7. Stratégie de compensation thermique

### Choix d'architecture

`temperature_probe.drift_calibration` a été **supprimée** (c'était une calibration de l'ancien mount, devenue obsolète). Elle n'a pas été refaite après le remount.

**Stratégie adoptée** : compensation dynamique à chaque print via `SET_SCAN_FROM_TAP` dans le start G-code.

### Workflow par print

1. `SET_Z_FROM_PROBE METHOD=tap` (via G28 ou explicite) → Z=0 = position physique du tap
2. `SET_SCAN_FROM_TAP` → calcule le delta scan↔tap à la température courante, applique `SET_GCODE_OFFSET Z=` correspondant
3. `BED_MESH_CALIBRATE METHOD=rapid_scan` → mesh à `descend_z=0.5mm`, thermiquement compensé via l'offset

### Avantages

- Compensation **toujours actuelle** (à la température exacte du print)
- Pas dépendant d'une calibration drift figée qui peut dériver
- Robuste face aux changements de mount, plaque, filament
- Le drift de 0.26mm à 35°C n'est **pas un problème** : il est compensé en live

### Contreparties

- Un peu plus long au start G-code (+5s)
- Si la coil chauffe encore pendant le print (bed rayonne), le drift change → le mesh appliqué au début peut dériver. Mitigation : `bed_mesh fade_start: 1.0 / fade_end: 20 / fade_target: 0` permet à l'effet du mesh de s'estomper en altitude.

### À long terme

Si le drift résiduel devient gênant, refaire `temperature_probe drift_calibration` à chaud :

```
TEMPERATURE_PROBE_CALIBRATE PROBE=btt_eddy TARGET=55
```

Procédure interactive ~30 min. À considérer si la qualité dévie sur les hauteurs élevées (Z > 20 mm).

---

## 8. Bed mesh — configuration finale

```ini
[bed_mesh]
horizontal_move_z: 2
scan_overshoot: 8
speed: 200
mesh_min: 30.0, 15.0
mesh_max: 391.0, 391.0
probe_count: 25, 25
fade_start: 1.0
fade_end: 20
fade_target: 0
mesh_pps: 4, 4
algorithm: bicubic
bicubic_tension: 0.2
```

### Calcul des limites mesh (formule officielle Klipper)

Avec `x_offset=22, y_offset=0` et `scan_overshoot=8` :

| Limite | Formule | Résultat |
|---|---|---|
| `mesh_min_x` | `max(15, x_offset + scan_overshoot) = max(15, 30)` | **30** |
| `mesh_min_y` | `max(15, y_offset + scan_overshoot) = max(15, 8)` | **15** |
| `mesh_max_x` | `bed_max - scan_overshoot - margin = 400 - 8 - 1` | **391** |
| `mesh_max_y` | idem | **391** (gain en Y vs ancien mount) |

### Choix `horizontal_move_z = 2`

Sécurité contre collisions (bed warp, objet sur plateau). PR #7179 recommande 0.5mm pour précision max, mais 2mm est un compromis sécurité acceptable. Le tap reste la référence Z=0 absolue.

### Méthode pour bed mesh pendant un print

`BED_MESH_CALIBRATE METHOD=rapid_scan ADAPTIVE=1` est recommandé :
- `rapid_scan` : balayage continu, ~30s pour un mesh complet (vs ~3 min en `scan` point-par-point)
- `ADAPTIVE=1` : ne mesh que la zone d'impression effective, encore plus rapide

⚠️ Toujours appeler `SET_SCAN_FROM_TAP` **avant** le mesh pour compensation thermique.

---

## 9. Crashes stepcompress — diagnostic et résolution

### Symptômes

```
b'stepcompress o=8 i=-26264 c=1 a=0: Invalid sequence'
b"Error in syncemitter 'stepper_y' step generation"
Exception in flush_handler
Internal error in stepcompress
Transition to shutdown state
```

Crashe pendant un print, parfois après plusieurs heures, sur stepper_x ou stepper_y (CoreXY). Indépendant du MCU (qui n'est pas saturé).

### Cause #1 (majeure) — `arc_fitting` activé dans Orca

Avec `arc_fitting = 1` dans Orca, le slicer génère des G2/G3 partout, y compris **micro-arcs** sur les courbes de support et bridges. Sur un G-code de 3h17 analysé :

| Métrique | Valeur |
|---|---|
| Total arcs G2+G3 | 49 816 |
| Arcs avec rayon < 1 mm | **3 105** |
| Arcs avec rayon 1-2 mm | 5 661 |
| Plus petit rayon | **0.020 mm** (20 microns) |

Klipper a `[gcode_arcs] resolution: 1.0` par défaut. Pour un arc de rayon 0.02mm, la formule `segments = floor(flat_mm / resolution)` donne 0 → fallback à 1 segment droit dégénéré → mouvement pathologique pour stepcompress + input_shaper.

**Position officielle Klipper** (article Knowledge Base "The Myth of G2/G3 Arc Commands", juillet 2025, par Sineos) :

> *"Using arc commands (G2 / G3) in Klipper provides no significant real-world benefit for print quality, motion smoothness, or printer performance. Instead, it adds two further approximation steps, increasing the potential error."*

→ **Solution : désactiver `arc_fitting` dans Orca.**

### Cause #2 (aggravante) — `gcode_flavor = klipper` dans Orca

Avec ce flavor, Orca génère **44 431 `SET_VELOCITY_LIMIT`** par print (vs 0 avec Marlin Legacy). Les transitions rapides ACCEL=15000↔3000 saturent stepcompress.

→ **Solution : passer Orca en `gcode_flavor = Marlin (Legacy)`.**

### Filets de sécurité Klipper-side

```ini
[gcode_arcs]
resolution: 0.1               # filet de sécurité : segments fins même sur micro-arcs

[stepper_x]
step_pulse_duration: 0.000000501   # filet O'Connor (anti-bug "step on both edges")
[stepper_y]
step_pulse_duration: 0.000000501
[stepper_z]
step_pulse_duration: 0.000000501
[extruder]
step_pulse_duration: 0.000000501
```

Référence O'Connor : [Discourse #23304](https://klipper.discourse.group/t/issues-with-stepper-drift-on-latest-klipper/23304).

### Procédure de prévention

1. **Orca** : Print Settings → Others → décocher `Enable arc fitting`
2. **Orca** : Printer Settings → Machine G-code → `G-code flavor = Marlin (Legacy)`
3. **Klipper** : `[gcode_arcs] resolution: 0.1` + `step_pulse_duration: 0.000000501` partout

### Vérification sur G-code généré

```bash
F=/path/to/file.gcode
echo "G2: $(grep -c '^G2 ' "$F")"            # doit être 0
echo "G3: $(grep -c '^G3 ' "$F")"            # doit être 0
echo "SET_VELOCITY_LIMIT: $(grep -c 'SET_VELOCITY_LIMIT' "$F")"   # doit être 0
echo "M204: $(grep -c '^M204' "$F")"         # plusieurs centaines (normal)
```

---

## 10. Démarrage Klipper bloqué — `webhooks shakehands` en boucle

### Symptôme

Klipper bloque au démarrage, `klippy.log` montre :

```
mcu 'mcu': Starting serial connect
Loaded MCU 'mcu' 116 commands
mcu 'eddy': Starting serial connect
webhooks: No registered callback for path 'shakehands'
webhooks: No registered callback for path 'shakehands'
... (en boucle infinie)
```

État Klipper bloqué, Moonraker ne répond pas, `state` jamais `ready`.

### Cause

Un MCU (généralement l'Eddy USB ou le main MCU) est **figé** dans un état incohérent. Cela arrive :
- Après un crash stepcompress brutal
- Après une erreur USB
- Après un reflashage incomplet
- Après plusieurs restart Klipper rapprochés

`/etc/init.d/S55klipper_service restart` **ne résout pas** le problème car il ne réinitialise pas le firmware MCU, juste le host Klipper.

### Solution

**Power cycle physique de l'imprimante** :
1. Couper l'alimentation (interrupteur ou prise)
2. Attendre 10 secondes
3. Rebrancher
4. Attendre ≈30s que tout boote
5. `state: ready` doit apparaître

→ **À retenir** : après modifications majeures de config ou après tout problème suspect, faire un power cycle complet est la solution propre. Ne pas s'acharner sur des restart Klipper.

### Diagnostic préliminaire

Avant power cycle, vérifier la nature du problème :

```bash
ls -la /dev/serial/by-id/                                # Eddy USB doit apparaître
ps aux | grep klippy | grep -v grep                      # Klipper tourne ?
tail -30 /usr/data/printer_data/logs/klippy.log          # erreur exacte
```

- Erreur `Option 'X' is not valid` → problème de config, pas MCU. Corriger la config.
- Erreur `Serial connection closed` ou `webhooks shakehands` en boucle → MCU figé, **power cycle**.

---

## 11. NOZZLE_CLEAR_ON_BRUSH — cohérence avec le tap

### Pourquoi indispensable

Un blob de plastique au bout du nozzle fausse complètement la mesure tap (la sonde détecte le contact avec le blob, pas avec le nozzle réel). Une bonne calibration tap **nécessite un nozzle propre**.

### Architecture en 4 phases

1. Brush à 180°C (5 passes zigzag) — extraction du plastique fluide
2. **Cooldown actif** : passes zigzag continues + part fans à 100% pendant la descente 180→140°C
3. Stabilisation `M109 S140` (fans coupés)
4. Brush final à 140°C (5 passes) — finition à plastique solide

### Avantages du cooldown actif

- Plus efficace : plastique passe par sa phase semi-solide (≈160°C) où il s'arrache mieux
- Plus rapide : ≈50s total au lieu de ≈60-65s en cooldown statique
- Garantit nozzle parfaitement propre à 140°C — température idéale pour tap (pas d'oozing)

### Notes sur les fans Creality E5M

- L'Ender 5 Max stock utilise `[output_pin fan0]` et `[output_pin fan1]` (PWM via `SET_PIN`), pas le `[fan]` standard Klipper
- `scale: 255` dans la config — donc `VALUE=255` pour 100%, pas `VALUE=1.0`
- Alternative : `M106 S255` (la macro custom dans `gcode_macro.cfg` redirige vers les deux fans)

---

## 12. Start G-code Orca recommandé

```gcode
; ═══════════════════════════════════════════════════════════
; E5M-CK Start G-code — TAP-based Z reference + clean nozzle
; ═══════════════════════════════════════════════════════════

; --- Reset state ---
PRINT_FLAG_CLEAR
BED_MESH_CLEAR
SET_GCODE_OFFSET Z=0                         ; reset offset orphelin
G92 E0
M220 S100
M221 S100

; --- Heat bed first (le bed prend du temps, on le démarre tôt) ---
M140 S{first_layer_bed_temperature[0]}
M190 S{first_layer_bed_temperature[0]}
G4 P300000                                   ; 5min thermal homogenization

; --- Pre-heat nozzle just enough to clean ---
M104 S140                                    ; raised to 180 by NOZZLE_CLEAR_ON_BRUSH

; --- Initial home (uses TAP refinement automatically via homing.cfg) ---
G28

; --- Clean nozzle on brush, ends at 140°C ---
NOZZLE_CLEAR_ON_BRUSH

; --- TAP-based Z=0 + thermally compensated bed mesh reference ---
G1 X200 Y200 F6000
SET_SCAN_FROM_TAP                            ; lift Z>=10 auto, tap, scan, gcode_offset
BED_MESH_CALIBRATE METHOD=rapid_scan ADAPTIVE=1

; --- Final nozzle heat to print temperature ---
M104 S{first_layer_temperature[0]}
M109 S{first_layer_temperature[0]}

; --- Optional first-layer Z compensation (tune if needed) ---
; SET_GCODE_OFFSET Z_ADJUST=0.05 MOVE=1

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

### Séquence chronologique

1. Bed à temp → 5min homogénéisation
2. Nozzle à 140°C → G28 (avec tap intégré, possiblement avec nozzle un peu sale)
3. NOZZLE_CLEAR_ON_BRUSH → nozzle propre à 140°C
4. SET_SCAN_FROM_TAP → tap propre + scan + gcode_offset thermique-compensé
5. BED_MESH_CALIBRATE rapid_scan adaptive → mesh thermiquement correct
6. Chauffe finale nozzle à temp print
7. Prime line + impression

### Importance du `SET_GCODE_OFFSET Z=0` initial

Au cas où un offset orphelin d'un print précédent (par exemple un baby-step `Z_ADJUST=+0.05` non sauvegardé) traînerait. Reset propre garantit un démarrage prévisible.

---

## 13. Règles d'or (golden rules)

### Calibration

1. **Tap est la seule référence Z=0 fiable à chaud.** Le scan dérive thermiquement, le paper test est subjectif.
2. **Toujours tapper avec un nozzle propre.** Sinon mesure faussée.
3. **Tapper à nozzle 140°C.** Pas plus chaud (oozing), pas plus froid (filament durci peut fausser).
4. **`tap_threshold` se calibre par bracketing.** 2× la limite basse de détection est le bon point de départ.
5. **Validation cible : range < 0.020 mm sur PROBE_ACCURACY_TAP** (cible Klipper).
6. **Refaire la calibration height map après tout changement de mount, plaque ou nozzle.**

### Workflow

7. **TOUJOURS lift Z à 10 mm avant un tap.** Sans exception. Sinon `insufficient slope delta`.
8. **Utiliser `SET_GCODE_OFFSET Z=` (absolu)** plutôt que `Z_ADJUST=` sauf babystepping intentionnel.
9. **Reset `SET_GCODE_OFFSET Z=0` au début du start G-code** pour éviter l'orphelin.
10. **`SET_SCAN_FROM_TAP` avant tout bed_mesh** pour compensation thermique dynamique.

### Crashes & dépannage

11. **`step_pulse_duration: 0.000000501`** sur tous steppers (filet O'Connor).
12. **arc_fitting OFF dans Orca** + `gcode_flavor = Marlin (Legacy)`.
13. **`[gcode_arcs] resolution: 0.1`** comme filet de sécurité résiduel.
14. **Power cycle physique** si Klipper bloqué `webhooks shakehands` en boucle.
15. **Lire klippy.log** avant d'agir : la cause est presque toujours dedans.

### Pièges Klipper version actuelle (mars 2026)

16. **`PROBE_ACCURACY METHOD=tap` est cassé** → utiliser `PROBE_ACCURACY_TAP` custom.
17. **`SAMPLES>1` + `METHOD=tap` casse la 2e mesure** → utiliser SAMPLES=1 (default) pour tap.
18. **`SAMPLES>1` + `METHOD=scan` fonctionne** (pas de descente entre samples).
19. **Options `samples`/`sample_retract_dist` en config `[probe_eddy_current]` sont ignorées** depuis 20260318. Les passer en runtime sur la commande PROBE.
20. **Multi-tap consécutifs sans G0 Z5 entre chaque échouent** → toujours lift entre 2 PROBE METHOD=tap.

---

## 14. État final validé (29 avril 2026)

| Élément | Valeur |
|---|---|
| Mount Eddy | x=22.0, y=0.0 |
| `reg_drive_current` | 15 |
| Calibration temp probe | 45.5°C (à refaire après remount idéalement) |
| Global MAD_Hz (chaud) | 17.612 |
| **`tap_threshold`** | **28** |
| `tap_z_offset` | non utilisé (pas nécessaire avec ce mount) |
| Range PROBE_ACCURACY_TAP (10 samples, à froid) | **0.0103 mm** |
| StdDev PROBE_ACCURACY_TAP | **0.0026 mm** |
| Average tap | proche de 0 (variable selon coil temp) |
| Drift scan↔tap @ ≈35°C | ≈0.260 mm (compensé live) |
| `temperature_probe drift_calibration` | supprimée (compensation via SET_SCAN_FROM_TAP) |
| `step_pulse_duration` | 0.000000501 (501ns) sur tous steppers |
| Input shaper X | zv 50.6 Hz |
| Input shaper Y | mzv 41.8 Hz |
| Bed mesh | 25×25, scan_overshoot=8, mesh_min=30/15, mesh_max=391/391 |
| `[gcode_arcs] resolution` | 0.1 |
| Orca `arc_fitting` | OFF |
| Orca `gcode_flavor` | Marlin (Legacy) |

**Validation finale** : `PROBE_ACCURACY_TAP SAMPLES=10` → range 0.0103 mm < cible 0.020 mm ✅

---

## 15. Maintenance — quand refaire quoi

| Événement | Recalibration nécessaire |
|---|---|
| Changement de mount Eddy | LDC_CALIBRATE_DRIVE_CURRENT + PROBE_EDDY_CURRENT_CALIBRATE + bracketing tap_threshold |
| Changement de plaque (PEI, PEI texturée, verre) | PROBE_EDDY_CURRENT_CALIBRATE (paper test) — la surface change la fréquence baseline |
| Changement de nozzle (taille, matériau) | PROBE_EDDY_CURRENT_CALIBRATE recommandé |
| Reflash firmware Eddy | Toutes les calibrations à refaire |
| Update Klipper mainline | Vérifier Config_Changes pour breaking changes sur `[probe_eddy_current]` |
| Drift résiduel gênant à hauteur élevée | TEMPERATURE_PROBE_CALIBRATE TARGET=55 |
| Range PROBE_ACCURACY_TAP > 0.020 mm | Vérifier nozzle propre, machine stable, refaire bracketing tap_threshold |

---

## Références

- Documentation officielle Klipper Eddy : https://www.klipper3d.org/Eddy_Probe.html
- Klipper G-Codes reference : https://www.klipper3d.org/G-Codes.html
- Klipper Config_Changes : https://www.klipper3d.org/Config_Changes.html (entrée 20260318)
- PR #7186 (open) : `temperature_probe: use tap for calibration`
- PR #7179 (closed) : pattern SET_SCAN_FROM_TAP
- PR #7220 (mergé) : option `tap_z_offset`
- Article officiel "The Myth of G2/G3 Arc Commands" : https://klipper.discourse.group/t/the-myth-of-g2-g3-arc-commands/24335
- Discourse Klipper #23304 : recommandation O'Connor `step_pulse_duration: 0.000000501`
- BTT Eddy GitHub : https://github.com/bigtreetech/Eddy

---

## Annexe — Glossaire des règles d'or

| Règle | Source | Conséquence si non respectée |
|---|---|---|
| Lift 10mm avant tap | Empirique + LDC1612 design | `insufficient slope delta` |
| G0 Z5 entre 2 PROBE METHOD=tap consécutifs | Bug Klipper samp_retract_dist=0 | 2e tap échoue |
| SET_GCODE_OFFSET Z= (absolu) au lieu de Z_ADJUST= | Comportement Klipper documenté | Accumulation entre appels |
| Refaire height map après remount | Géométrie coil-bed change | Z reportés faux |
| Nozzle propre avant tap | Physique du contact | Mesure faussée |
| arc_fitting OFF dans Orca | Article Sineos juillet 2025 | Crash stepcompress |
| Power cycle si MCU figé | Reset firmware nécessaire | Restart Klipper inefficace |
