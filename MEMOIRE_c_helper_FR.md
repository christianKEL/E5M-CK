# MÉMOIRE TECHNIQUE — Génération de `c_helper.so`

## Klipper mainline sur Nebula Pad (Creality Ender 5 Max)

**Auteur :** Christian KELHETTER
**Projet :** E5M-CK — https://github.com/christianKEL/E5M-CK
**Date :** Avril 2026

---

## 1. Contexte et problématique

### 1.1 Le rôle de `c_helper.so`

`c_helper.so` est une bibliothèque partagée compilée par Klipper pour accélérer certains calculs critiques (cinématique, trapezoïdes de mouvement) qui seraient trop lents en pur Python. Elle est chargée dynamiquement au démarrage de Klippy par `ctypes.CDLL()` depuis le dossier `klippy/chelper/`.

Sans `c_helper.so` correctement compilé, Klipper mainline refuse de démarrer sur le Nebula Pad. Au démarrage, le processus `klippy.py` tente d'abord de **recompiler** automatiquement `c_helper.so` via GCC local, mais échoue sur le Nebula Pad car :

- Le compilateur embarqué dans la toolchain Creality ne supporte pas les flags spécifiques requis par le CPU Ingenic XBurst2.
- Le `make` du Nebula produit un binaire aux flags incompatibles avec le format attendu.

**Solution :** fournir un `c_helper.so` **précompilé** avec la bonne toolchain et les bons flags, placé directement dans `klippy/chelper/` avant le premier démarrage.

### 1.2 Architecture CPU du Nebula Pad

Le Nebula Pad embarque un SoC **Ingenic T31X** avec un CPU **MIPS XBurst2 32 bits**. Ce CPU implémente l'ISA `mips32r2` mais avec des particularités :

| Caractéristique | Valeur |
|---|---|
| Architecture | MIPS32r2 |
| Endianness | Little Endian (MIPSEL) |
| ABI | o32 |
| FPU | 64 bits (mfp64) |
| Représentation NaN | IEEE 754-2008 (`nan2008`) |
| Valeur absolue FP | `abs2008` |

Ces caractéristiques doivent apparaître dans les **flags ELF** du binaire compilé, sinon le dynamic linker du Nebula refusera de charger la bibliothèque ou produira des erreurs de calcul flottant silencieuses.

La valeur cible des flags ELF est **`0x70001407`** — correspondant à :
- `noreorder` — ne pas réorganiser les instructions
- `pic` — position-indépendant
- `cpic` — call via indirection PIC
- `nan2008` — NaN IEEE 754-2008
- `o32` — ABI 32 bits
- `mips32r2` — ISA MIPS32r2

Si les flags sont `0x70001007` (sans le bit `0x400` qui représente `nan2008`), le binaire ne sera pas compatible.

---

## 2. Toolchain requise et contrainte d'architecture

### 2.1 Toolchain Ingenic officielle

La toolchain de référence pour compiler du code natif pour Ingenic XBurst2 est celle de **Dafang-Hacks** :

```
https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1
```

Cette toolchain est basée sur **GCC 5.2** (version exacte embarquée par Ingenic dans leur BSP officiel).

### 2.2 Contrainte : hôte x86_64 obligatoire

La toolchain est distribuée sous forme de binaires **précompilés pour x86_64 Linux** :

```bash
$ file ~/ingenic-toolchain/bin/mips-linux-gnu-gcc
ELF 64-bit LSB executable, x86-64, version 1 (SYSV),
dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2,
for GNU/Linux 2.6.18, BuildID[...], stripped
```

**Conséquence :** il faut impérativement un hôte **x86_64** pour l'exécuter. Sur un hôte ARM64 (Raspberry Pi, SBC, Mac Apple Silicon, etc.), lancer la toolchain produit :

```
cannot execute binary file: Exec format error
```

Même avec `qemu-user` en émulation, les performances sont inexploitables et la stabilité n'est pas garantie.

### 2.3 Alternatives écartées

D'autres approches ont été explorées mais écartées :

1. **Trouver une toolchain Ingenic GCC 5.2 pour ARM64** → aucune disponible publiquement (Ingenic ne distribue que les hôtes x86_64).
2. **Recompiler la toolchain soi-même depuis ses sources** → plusieurs heures de compilation + chaîne `binutils` + `gcc` + `glibc` à reconstruire. Risque élevé de divergence vs. la toolchain officielle.
3. **Utiliser le cross-compilateur Debian `gcc-mipsel-linux-gnu`** → c'est un GCC 10.x ; les flags `-mnan=2008 -mfp64 -mabs=2008` sont acceptés mais le binaire produit n'a pas la bonne signature (incompatibilités ABI mineures avec le linker du Nebula).

**La seule voie fiable est donc : toolchain Ingenic officielle, sur un hôte x86_64.**

---

## 3. Solution retenue — GitHub Codespaces

### 3.1 Principe

**GitHub Codespaces** est un service gratuit (60 h/mois sur compte GitHub perso) qui provisionne à la demande un environnement Linux **x86_64** accessible directement dans le navigateur, via VS Code web.

Avantages pour ce cas :
- Architecture **x86_64** — compatible avec la toolchain Ingenic.
- Environnement Debian/Ubuntu récent — pas de soucis de glibc.
- Accès terminal complet, droits root via `sudo`.
- Téléchargement du binaire produit via l'explorateur de fichiers VS Code (clic droit → Download).
- Pas d'installation locale requise.

### 3.2 Workflow complet

#### Étape 1 — Créer un codespace

1. Se connecter à GitHub.
2. Ouvrir https://github.com/codespaces.
3. **New codespace** → choisir un repo quelconque (par ex. `Klipper3d/klipper` directement).
4. Attendre le provisionnement (~30 secondes).
5. Un terminal bash s'ouvre sur `/workspaces/<repo>`.

Vérification de l'architecture :

```bash
uname -m
# Sortie attendue : x86_64
```

#### Étape 2 — Cloner la toolchain Ingenic

```bash
git clone --depth 1 \
  https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1 \
  ~/ingenic-toolchain
```

La toolchain fait ~250 Mo et se clone en ~30 secondes depuis les datacenters GitHub.

Vérification :

```bash
~/ingenic-toolchain/bin/mips-linux-gnu-gcc --version
```

Sortie attendue :

```
mips-linux-gnu-gcc (Ingenic r3.2.1-gcc520 2017.12-15) 5.2.0
Copyright (C) 2015 Free Software Foundation, Inc.
```

#### Étape 3 — Cloner Klipper mainline (si nécessaire)

Si le codespace n'a pas été créé depuis le repo Klipper directement :

```bash
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper
```

#### Étape 4 — Compilation de `c_helper.so`

```bash
cd /workspaces/klipper/klippy/chelper

~/ingenic-toolchain/bin/mips-linux-gnu-gcc \
    -shared -fPIC -O2 \
    -mnan=2008 -mfp64 -mabs=2008 \
    $(ls *.c) \
    -o c_helper.so
```

**Points importants :**

- `-shared -fPIC` → bibliothèque partagée position-indépendante (requis pour `ctypes.CDLL`).
- `-O2` → optimisation standard (niveau utilisé par Klipper officiel).
- `-mnan=2008` → indispensable pour obtenir le flag `0x400` dans l'en-tête ELF.
- `-mfp64` → FPU 64 bits (correspond au CPU XBurst2).
- `-mabs=2008` → comportement des opérations de valeur absolue en flottant selon IEEE 754-2008.
- `$(ls *.c)` → compile tous les `.c` présents dans `chelper/` (actuellement `itersolve.c`, `kin_*.c`, `trapq.c`, etc.).
- **Pas de `-lm`** → l'édition de liens avec `libm` produit une dépendance `libm.so.6` qui n'existe pas sur le Nebula. Sans `-lm`, les symboles `math.h` utilisés par `c_helper.so` sont résolus via `libc` uniquement.

#### Étape 5 — Validation des flags ELF

```bash
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -h c_helper.so | grep "Flags"
```

Sortie attendue :

```
Flags: 0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2
```

Si les flags sont `0x70001007` (sans `nan2008`), **refaire la compilation** — le flag `-mnan=2008` n'a pas été pris en compte.

#### Étape 6 — Validation des dépendances

```bash
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -d c_helper.so | grep "NEEDED"
```

Sortie attendue (et uniquement ça) :

```
0x00000001 (NEEDED)     Shared library: [libc.so.6]
```

Si `libm.so.6` apparaît, recompiler **sans** `-lm`.

#### Étape 7 — Validation du format ELF

```bash
od -t x1 c_helper.so | head -1
```

Sortie attendue :

```
0000000  7f 45 4c 46 01 01 01 00 03 00 00 00 00 00 00 00
```

Les octets clés :
- `7f 45 4c 46` → magic number ELF (`.ELF`).
- Octet 4 (`01`) → classe 32 bits.
- Octet 5 (`01`) → little endian.
- Octet 8 (`03`) → OS/ABI = Linux.

Comparé octet par octet avec un `c_helper.so` extrait d'un firmware Creality de référence, les en-têtes sont identiques. Le binaire compilé est donc bien compatible.

---

## 4. Transfert du binaire vers le Nebula

### 4.1 Contrainte réseau

Le codespace tourne dans le cloud GitHub (Azure East US). Il **ne peut pas** atteindre une IP locale du type `192.168.x.x`. Un `scp codespace → nebula` échoue systématiquement :

```
ssh: Could not resolve hostname 192.168.x.x: Name or service not known
```

### 4.2 Méthode retenue

**Flux** : Codespace → PC Windows (local) → Nebula.

**Étape A — Téléchargement Codespace → PC Windows :**

Dans l'explorateur de fichiers VS Code web (panneau gauche du codespace) :
- Naviguer vers `/workspaces/klipper/klippy/chelper/`.
- Clic droit sur `c_helper.so` → **Download**.
- Le navigateur enregistre le fichier dans `Téléchargements`.

**Étape B — Transfert PC → Nebula via SCP :**

PowerShell Windows :

```powershell
scp C:\Users\<user>\Downloads\c_helper.so `
    root@<IP_NEBULA>:/usr/data/klipper/klippy/chelper/c_helper.so
```

**Attention :** le Nebula n'embarque pas `sftp-server`. Les clients SCP récents qui exigent SFTP (OpenSSH 9+) peuvent échouer avec :

```
sh: /usr/libexec/sftp-server: not found
```

Solutions :
- Utiliser `scp -O` pour forcer le protocole legacy.
- Utiliser un client Windows plus ancien (`pscp.exe` de PuTTY).
- Passer par un intermédiaire qui accepte SCP legacy (Raspberry Pi, autre SBC).

### 4.3 Méthode alternative — GitHub Raw

Une fois `c_helper.so` validé, il peut être uploadé dans un dépôt public GitHub. Le Nebula peut alors le récupérer directement :

```bash
wget --no-check-certificate \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/c_helper.so \
  -O /usr/data/klipper/klippy/chelper/c_helper.so
```

**Important :** le Nebula utilise un `wget` busybox compilé sans SSL moderne. L'option `--no-check-certificate` est obligatoire.

C'est la méthode utilisée par l'installateur `install.sh` du projet E5M-CK.

---

## 5. Validation sur le Nebula

### 5.1 Test de chargement Python

```bash
/usr/share/klippy-env/bin/python3 -c \
  "import ctypes; ctypes.CDLL('/usr/data/klipper/klippy/chelper/c_helper.so'); print('OK')"
```

Sortie attendue :

```
OK
```

Si erreur `cannot open shared object file: No such file or directory`, vérifier le chemin.

Si erreur `wrong ELF class: ELFCLASS64` ou `unsupported ELF format`, le binaire a été compilé avec les mauvais flags ou pour la mauvaise architecture.

### 5.2 Test démarrage Klippy complet

```bash
/etc/init.d/S55klipper_service restart
sleep 30
curl http://localhost:7125/printer/info 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  print(d['result']['state'], '-', d['result']['software_version'])"
```

Sortie attendue :

```
ready - v0.13.0-628-g373f200ca
```

Si `state = startup` pendant plus d'une minute ou `state = error`, consulter :

```bash
tail -100 /usr/data/printer_data/logs/klippy.log
```

Messages d'erreur typiques liés à `c_helper.so` :

- `Unable to load chelper: ... undefined symbol ...` → binaire compilé pour une autre version de Klipper. Refaire depuis un clone récent.
- `Unable to open chelper ... c_helper.so: cannot open shared object` → chemin incorrect.
- `chelper signature mismatch` → les `.c` compilés ne correspondent pas à la version de `klippy.py` qui tente de les charger.

---

## 6. Maintenance et mises à jour

### 6.1 Quand faut-il recompiler ?

Il faut refaire la compilation dès que :

- Le code source `klippy/chelper/*.c` change dans Klipper mainline (mises à jour upstream).
- Un fichier `.c` est ajouté ou supprimé.
- La version de Klipper est mise à jour via `git pull` et que `chelper/` est impacté.

### 6.2 Procédure de mise à jour

Dans le codespace existant (ou nouveau) :

```bash
cd /workspaces/klipper
git pull

cd klippy/chelper

~/ingenic-toolchain/bin/mips-linux-gnu-gcc \
    -shared -fPIC -O2 \
    -mnan=2008 -mfp64 -mabs=2008 \
    $(ls *.c) \
    -o c_helper.so

~/ingenic-toolchain/bin/mips-linux-gnu-readelf -h c_helper.so | grep "Flags"
# Vérifier que le résultat contient "nan2008"
```

Puis redistribuer via GitHub Raw ou SCP comme en section 4.

### 6.3 Backup

Il est conseillé de conserver :
- La dernière version fonctionnelle de `c_helper.so` (dans `/usr/data/E5M_CK/c_helper.so` sur le Nebula).
- Le hash du commit Klipper correspondant (`git rev-parse HEAD` dans le codespace au moment de la compilation).

Cela permet de revenir à une version connue en cas de régression upstream.

---

## 7. Récapitulatif — commandes minimales

Pour une génération complète **from scratch** sur un codespace vierge :

```bash
# Toolchain
git clone --depth 1 \
  https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1 \
  ~/ingenic-toolchain

# Klipper mainline (si codespace vierge)
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper

# Compilation
cd /workspaces/klipper/klippy/chelper
~/ingenic-toolchain/bin/mips-linux-gnu-gcc \
    -shared -fPIC -O2 \
    -mnan=2008 -mfp64 -mabs=2008 \
    $(ls *.c) \
    -o c_helper.so

# Validation
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -h c_helper.so | grep "Flags"
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -d c_helper.so | grep "NEEDED"
```

Flags attendus : `0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2`
Dépendance attendue : `libc.so.6` uniquement

---

## 8. Notes diverses

### 8.1 Pourquoi pas le cross-compilateur Debian ?

Le paquet `gcc-mipsel-linux-gnu` (Debian 11, GCC 10.2) compile techniquement avec les mêmes flags, mais :
- Produit un binaire lié à `ld-linux.so.3` plutôt qu'à `ld.so.1` (emplacement du linker dynamique sur Ingenic).
- La version de glibc utilisée pour le link n'est pas celle embarquée sur le Nebula — symboles de versions différentes.
- L'ABI par défaut est `n32` alors qu'il faut `o32`.

Techniquement faisable avec beaucoup de flags supplémentaires (`-Wl,--dynamic-linker=...`), mais beaucoup plus fragile que la toolchain Ingenic officielle.

### 8.2 Pourquoi Klipper ne compile pas `c_helper.so` à la volée sur le Nebula ?

Au démarrage, Klippy tente effectivement d'exécuter `make` dans `klippy/chelper/`. Sur le Nebula :

- GCC est présent (`/usr/bin/gcc` → toolchain Creality MIPS).
- Mais cette toolchain ne supporte **pas** les options `-mnan=2008 -mfp64 -mabs=2008` — erreur de compilation.
- Le Makefile du projet Klipper n'ajoute pas ces flags spécifiques (il suppose une toolchain générique).

La solution propre serait de patcher `klippy/chelper/Makefile` pour détecter l'environnement Ingenic et ajouter les flags — mais cela demande de maintenir un fork de Klipper.

Fournir un `c_helper.so` précompilé et bloquer la recompilation (en s'assurant que le fichier existe au démarrage) est la solution la plus simple et la plus stable.

### 8.3 Référence — `c_helper.so` de Creality Klipper fork

Le binaire `c_helper.so` fourni dans le fork Creality de Klipper (dans `/usr/share/klipper/klippy/chelper/c_helper.so` avant factory reset) a les caractéristiques suivantes :

- Flags : `0x70001407` (avec `nan2008`)
- Dépendances : `libc.so.6` uniquement
- OS/ABI : `03` (Linux)

Notre binaire compilé via la procédure décrite ici est **strictement identique** en termes de format — seuls les symboles internes diffèrent car les versions de Klipper ne sont pas les mêmes.

---

*Document rédigé en avril 2026 dans le cadre du projet E5M-CK.*
