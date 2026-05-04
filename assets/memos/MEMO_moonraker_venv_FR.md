# MÉMOIRE TECHNIQUE — Génération du venv Moonraker MIPS

## Klipper mainline sur Nebula Pad (Creality Ender 5 Max)

**Auteur :** Christian KELHETTER
**Projet :** E5M-CK — <https://github.com/christianKEL/E5M-CK>
**Date :** Mai 2026

---

## 1. Contexte et problématique

### 1.1 Le rôle du venv Moonraker

Moonraker est l'API web qui sert de pont entre Klipper (le firmware) et les UI web (Fluidd, Mainsail). Comme tout projet Python sérieux, il s'exécute dans un **environnement virtuel Python** (`virtualenv`) qui contient :

* Une copie/lien vers l'interpréteur Python.
* Une vingtaine de paquets pip nécessaires (`tornado`, `jinja2`, `lmdb`, `cryptography`, `numpy`, etc.).
* Plusieurs de ces paquets contiennent des **extensions C compilées** (`.so`) — pas du Python pur.

Sur le Nebula Pad, ce venv doit donc contenir des binaires `.so` compilés pour l'architecture **MIPS little-endian**, sinon Python échoue avec `wrong ELF class` ou `cannot open shared object` au moment d'importer.

### 1.2 La contrainte clé : pas de GCC sur le Nebula

Le Nebula Pad n'embarque pas de toolchain GCC complète. Le `gcc` qui s'y trouve est limité, ne supporte pas tous les flags nécessaires, et n'a pas les en-têtes Python (`Python.h`) nécessaires à la compilation des extensions C.

**Conséquence :** un simple `pip install -r moonraker-requirements.txt` sur le Nebula échoue dès qu'un paquet doit être compilé depuis ses sources :

```
error: command 'gcc' failed with exit status 1
```

Les paquets typiquement concernés : `lmdb`, `cryptography`, `MarkupSafe`, `numpy`, `Pillow`, `cffi`, `dbus-fast`.

**Solution :** fournir un **venv précompilé** contenant tous les `.so` MIPS déjà construits, à extraire tel quel sur le Nebula.

### 1.3 Architecture CPU du Nebula Pad

Le Nebula Pad embarque un SoC **Ingenic T31X** avec un CPU **MIPS XBurst2 32 bits**. Voir `MEMO_c_helper_FR.md` pour le détail des flags ELF requis (`mips32r2`, `nan2008`, `o32`, `mfp64`, `abs2008`).

Le venv doit contenir des `.so` ayant ces mêmes flags pour être chargés par le linker dynamique du Nebula.

---

## 2. Source retenue — Helper-Script Guilouz

### 2.1 Pourquoi Helper-Script

Le projet **Creality-Helper-Script** (Guilouz) maintient depuis plusieurs années des venvs Moonraker pré-compilés pour les imprimantes Creality basées sur Buildroot/Ingenic (K1, K1 Max, Ender 5 Max, Ender 3 V3 KE...). Ces venvs sont disponibles sous forme de tar.gz dans son dépôt GitHub :

```
https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/moonraker/moonraker.tar.gz
```

Ce tar.gz contient à la fois :

* Le **code Moonraker** (un snapshot d'une version récente du repo Arksine/moonraker).
* Le **venv Python 3.8** (`moonraker-env/`) avec tous les paquets compilés MIPS.

### 2.2 Pourquoi ne pas tout reprendre de Helper-Script

Le projet E5M-CK vise l'**indépendance maximale** vis-à-vis des projets tiers (cf. mémo `MEMO_c_helper_FR.md`). On ne veut pas que :

* Une indisponibilité temporaire du repo Guilouz casse nos installations.
* Une mise à jour cassante côté Helper-Script affecte nos utilisateurs.
* Le code Moonraker soit figé à la version snapshot de Helper-Script (qui peut avoir plusieurs mois de retard sur master).

**Solution retenue :** on n'extrait du tar.gz Helper-Script que le **strict nécessaire qu'on ne peut pas reproduire** sur le Nebula — c'est-à-dire le **venv MIPS**. Le code Moonraker, lui, est cloné directement depuis `Arksine/moonraker.git` (toujours à jour, vrai repo git, Update Manager fonctionnel).

### 2.3 Alternatives écartées

1. **Cross-compiler le venv depuis zéro sur GitHub Codespaces** (comme pour `c_helper.so`) → faisable mais beaucoup plus complexe : il faudrait cross-compiler `cryptography`, `lmdb`, `numpy`, `Pillow`, `MarkupSafe`, `dbus-fast`, `cffi` séparément, gérer leurs propres dépendances (OpenSSL, libffi, lmdb-headers, libtiff, libjpeg...), produire des wheels MIPS valides. Plusieurs jours de travail.

2. **Recompiler les paquets directement sur le Nebula** → impossible (pas de GCC complet, voir 1.2).

3. **Utiliser le venv Klippy de Creality** (`/usr/share/klippy-env`) → il ne contient que ce qu'il faut pour Klipper, pas pour Moonraker.

---

## 3. Procédure de génération

### 3.1 Étape A — Récupération du venv depuis Helper-Script (UNE fois)

**Cette étape n'est faite qu'une seule fois**, par le mainteneur du repo E5M-CK. L'utilisateur final, lui, télécharge directement le venv depuis le repo E5M-CK.

Sur une imprimante Nebula Pad fonctionnelle (n'importe laquelle), depuis SSH :

```bash
# 1. Télécharger le tar.gz Helper-Script
mkdir -p /usr/data/.tmp_install
cd /usr/data/.tmp_install
wget --no-check-certificate \
  https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/moonraker/moonraker.tar.gz \
  -O moonraker.tar.gz

# 2. Extraire le tout
tar -xzf moonraker.tar.gz

# Le contenu typique :
#   moonraker.tar.gz
#   ├── moonraker/        (code Moonraker — IGNORÉ)
#   └── moonraker-env/    (venv MIPS — CE QU'ON GARDE)
```

### 3.2 Étape B — Mise à jour des paquets pure-Python

Le venv Helper-Script peut contenir des versions de paquets pure-Python plus anciennes que ce que le master actuel d'Arksine/moonraker requiert. On peut mettre à jour ces paquets **sans recompilation** car ils sont en pur Python. Au moment de la rédaction de ce mémo, les mises à jour pertinentes étaient :

```bash
# Le venv extrait est utilisable tel quel ou à l'emplacement final.
# Adapter le chemin selon le contexte.
VENV=/usr/data/.tmp_install/moonraker-env

# paho-mqtt 1.6.1 -> 2.1.0 (master demande ==2.1.0)
$VENV/bin/pip install --upgrade paho-mqtt==2.1.0

# inotify-simple 1.3.5 -> 2.0.1 (master demande ==2.0.1)
$VENV/bin/pip install --upgrade inotify-simple==2.0.1

# jinja2 3.1.4 -> 3.1.6 (master demande ==3.1.6)
# IMPORTANT : --no-deps pour ne pas tenter d'upgrader MarkupSafe
# (MarkupSafe est une C-extension non recompilable sur le Nebula)
$VENV/bin/pip install --upgrade --no-deps jinja2==3.1.6
```

**Pourquoi `--no-deps` pour jinja2 :** la version 3.1.6 demande `MarkupSafe>=2.1.5` mais `MarkupSafe` 2.1.1 (présent dans le venv original) est **fonctionnellement compatible** avec jinja2 3.1.6. On force pip à ne pas upgrader MarkupSafe pour éviter l'échec de compilation.

**Vérification après upgrade :**

```bash
$VENV/bin/python -c "
import tornado, jinja2, paho.mqtt.client, inotify_simple, dbus_fast, lmdb
print('All critical imports OK')
"
```

### 3.3 Étape C — Tarballer juste le venv

```bash
cd /usr/data/.tmp_install
tar -czf moonraker-env.tar.gz moonraker-env/

# Vérifier la taille (~16 MB attendu) et le md5
ls -lh moonraker-env.tar.gz
md5sum moonraker-env.tar.gz
```

Capturer le md5sum — il sera référencé dans `install_moonraker.sh` pour validation côté utilisateur final.

### 3.4 Étape D — Capturer le requirements.txt actuel

Pour la traçabilité, capturer les versions exactes du venv :

```bash
$VENV/bin/pip freeze > moonraker-env-requirements.txt
```

Ce fichier doit être archivé à côté du tar.gz (dans `assets/memos/moonraker-env-requirements.txt` du repo E5M-CK).

### 3.5 Étape E — Push sur le repo E5M-CK

Via SCP du Nebula vers le PC, puis upload via interface web GitHub :

* `moonraker-env.tar.gz` → `files/moonraker-env.tar.gz`
* `moonraker-env-requirements.txt` → `assets/memos/moonraker-env-requirements.txt`

Mettre à jour la valeur `VENV_TARBALL_MD5` dans `installs/install_moonraker.sh` avec le nouveau md5sum.

---

## 4. Utilisation côté utilisateur

L'utilisateur final ne fait rien de tout ça. Il lance :

```bash
wget --no-check-certificate \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/installs/install_moonraker.sh \
  -O /tmp/install_moonraker.sh && sh /tmp/install_moonraker.sh
```

Le script :

1. Télécharge `moonraker-env.tar.gz` depuis notre repo (16 MB, signé md5).
2. L'extrait dans `/usr/data/moonraker/`.
3. Clone `Arksine/moonraker.git` dans `/usr/data/moonraker/moonraker/`.
4. Déploie `moonraker.conf` depuis notre repo.
5. Crée le service init.d `S56moonraker_service`.
6. Démarre Moonraker.

Lors d'une **réinstallation** ou exécution ultérieure, le script détecte que tout est déjà en place et fait simplement un `git pull` sur le code Moonraker — beaucoup plus rapide.

---

## 5. Compatibilité venv ↔ code

### 5.1 Pourquoi ça marche (généralement)

Moonraker utilise des paquets stables avec des API rétro-compatibles. Le master actuel demande dans son `moonraker-requirements.txt` des versions précises (par exemple `tornado==6.4.1`), mais en pratique le code fonctionne avec des versions proches.

Le venv embarque par exemple :

```
tornado==6.4.1            ← exact match
jinja2==3.1.6             ← post-upgrade
MarkupSafe==2.1.1         ← inférieur à ce que jinja2 3.1.6 préfère, mais OK
streaming-form-data==1.8.1 ← inférieur à 1.11.0 demandé par master, mais OK
Pillow==7.0.0             ← très inférieur à 9.5 demandé, mais Pillow est optionnel
numpy==1.16.4             ← très ancien, utilisé par matplotlib (lui-même optionnel)
dbus-fast==2.24.4         ← inférieur à 2.28.0 demandé, mais compatible
```

### 5.2 Quand ça pourrait casser

Si une future version master de Moonraker introduit :

* Un nouveau paquet à dépendance C qu'on n'a pas dans le venv (genre nouvelle compression, nouveau cipher).
* Une utilisation d'API qui n'existe que dans une version récente d'un paquet pure-Python (et qu'on ne peut pas upgrader car il dépend d'un paquet C).

→ Il faudra alors **régénérer le venv** depuis Helper-Script (qui suit grosso-modo l'évolution de Moonraker).

### 5.3 Symptômes de désync à surveiller

Dans les logs Moonraker (`/usr/data/printer_data/logs/moonraker.log`) :

* `ImportError: cannot import name X from Y` → API manquante, paquet trop vieux.
* `AttributeError: module X has no attribute Y` → idem.
* Crash silencieux au démarrage avec exit code non-zéro → vérifier les imports critiques manuellement.

Test rapide en cas de doute :

```bash
/usr/data/moonraker/moonraker-env/bin/python /usr/data/moonraker/moonraker/moonraker/moonraker.py \
  -d /usr/data/printer_data
```

Si Moonraker démarre et affiche son banner d'init sans planter dans les premières secondes, le venv est compatible avec le code.

---

## 6. Maintenance

### 6.1 Quand régénérer le venv

* Si une mise à jour Moonraker (`git pull` côté utilisateur ou via Update Manager) ajoute une nouvelle dépendance non présente.
* Si un paquet critique a une faille de sécurité urgente à patcher.
* Sur signalement d'un utilisateur dont l'install plante au démarrage.

### 6.2 Procédure de régénération

Refaire **étapes A à E** de la section 3 ci-dessus, sur n'importe quel Nebula fonctionnel.

Bien penser à mettre à jour :

1. Le tar.gz dans `files/moonraker-env.tar.gz` (remplacer).
2. Le `moonraker-env-requirements.txt` (remplacer).
3. La valeur `VENV_TARBALL_MD5` dans `installs/install_moonraker.sh`.

### 6.3 Backup recommandé

Avant chaque régénération, archiver l'ancien tar.gz avec un nom daté :

```
files/moonraker-env.tar.gz.YYYY-MM-DD
```

Comme ça si la nouvelle version casse quelque chose, on a un point de retour fonctionnel rapide.

---

## 7. Récapitulatif — commandes minimales

Pour régénérer le venv from scratch sur un Nebula Pad fonctionnel :

```bash
# Récupérer le venv Helper-Script
mkdir -p /usr/data/.tmp_install
cd /usr/data/.tmp_install
wget --no-check-certificate \
  https://raw.githubusercontent.com/Guilouz/Creality-Helper-Script/main/files/moonraker/moonraker.tar.gz \
  -O hs.tar.gz
tar -xzf hs.tar.gz moonraker-env/

# Mettre à jour les paquets pure-Python
VENV=/usr/data/.tmp_install/moonraker-env
$VENV/bin/pip install --upgrade paho-mqtt==2.1.0 inotify-simple==2.0.1
$VENV/bin/pip install --upgrade --no-deps jinja2==3.1.6

# Vérifier
$VENV/bin/python -c "import tornado, jinja2, paho.mqtt.client, inotify_simple, dbus_fast, lmdb; print('OK')"

# Tarballer
tar -czf moonraker-env.tar.gz moonraker-env/

# Récupérer la signature
md5sum moonraker-env.tar.gz
ls -lh moonraker-env.tar.gz

# Capturer le requirements
$VENV/bin/pip freeze > moonraker-env-requirements.txt

# SCP vers PC, push GitHub, mettre à jour VENV_TARBALL_MD5 dans install_moonraker.sh
```

---

## 8. Notes diverses

### 8.1 Pourquoi le code Moonraker est cloné séparément

Plutôt qu'utiliser le code embarqué dans le tar.gz Helper-Script, on `git clone` `Arksine/moonraker.git`. Bénéfices :

* **Update Manager fonctionne** : Moonraker détecte son propre `.git/` et propose les mises à jour automatiquement dans Fluidd.
* **Toujours à jour** : on récupère le master au moment de l'install, pas un snapshot de Helper-Script qui peut avoir des semaines.
* **Rétrocompatibilité venv** : le venv supporte une plage assez large de versions (cf. section 5.1).

### 8.2 Pourquoi `provider: none` dans moonraker.conf

Le `moonraker.conf` embarqué dans Helper-Script contient `provider: supervisord_cli`. Sur Buildroot Creality, `supervisorctl` n'existe pas (ils utilisent init.d). Sans patcher ça, le component `[machine]` de Moonraker plante en boucle et — effet de bord — Update Manager affiche `INVALIDE / Failed to detect git branch`.

La valeur correcte est `provider: none` qui désactive complètement le monitoring de services côté Moonraker.

### 8.3 Pourquoi pas un repo Python complet sur le Nebula

Une approche alternative serait d'installer `python3-dev` + `gcc` complet via Entware ou similar, et de faire un `pip install -r requirements.txt` propre. En pratique :

* Entware n'a pas de paquet `python3-dev` fiable pour MIPS XBurst2.
* La toolchain GCC nécessaire pour compiler les wheels Python est différente de celle pour `c_helper.so` (besoin de `Python.h`).
* Compiler `numpy`, `cryptography`, `Pillow` sur le Nebula prendrait des heures et saturerait la RAM (256 MB).

Le venv précompilé reste la solution la plus simple et la plus stable.

---

*Document rédigé en mai 2026 dans le cadre du projet E5M-CK.*
