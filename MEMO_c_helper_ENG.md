# TECHNICAL MEMO — Building `c_helper.so`

## Klipper mainline on Nebula Pad (Creality Ender 5 Max)

**Author:** Christian KELHETTER
**Project:** E5M-CK — https://github.com/christianKEL/E5M-CK
**Date:** April 2026

---

## 1. Context and problem statement

### 1.1 The role of `c_helper.so`

`c_helper.so` is a shared library built by Klipper to speed up performance-critical computations (kinematics, motion trapezoids) that would be too slow in pure Python. It is loaded dynamically at Klippy startup via `ctypes.CDLL()` from the `klippy/chelper/` directory.

Without a correctly built `c_helper.so`, Klipper mainline refuses to start on the Nebula Pad. At startup, the `klippy.py` process first tries to **rebuild** `c_helper.so` automatically through the local GCC, but this fails on the Nebula Pad because:

- The GCC shipped in Creality's toolchain does not support the flags required by the Ingenic XBurst2 CPU.
- The Nebula's `make` produces a binary whose flags are incompatible with the expected format.

**Solution:** ship a **pre-built** `c_helper.so` compiled with the right toolchain and flags, placed directly in `klippy/chelper/` before the first startup.

### 1.2 Nebula Pad CPU architecture

The Nebula Pad uses an **Ingenic T31X** SoC with a **32-bit MIPS XBurst2** CPU. This CPU implements the `mips32r2` ISA with the following specifics:

| Feature | Value |
|---|---|
| Architecture | MIPS32r2 |
| Endianness | Little Endian (MIPSEL) |
| ABI | o32 |
| FPU | 64 bits (mfp64) |
| NaN representation | IEEE 754-2008 (`nan2008`) |
| FP absolute value | `abs2008` |

These characteristics must appear in the **ELF flags** of the built binary, otherwise the Nebula's dynamic linker will refuse to load the library or will silently produce incorrect floating-point results.

The expected ELF flags value is **`0x70001407`** — corresponding to:
- `noreorder` — do not reorder instructions
- `pic` — position-independent
- `cpic` — call via PIC indirection
- `nan2008` — IEEE 754-2008 NaN representation
- `o32` — 32-bit ABI
- `mips32r2` — MIPS32r2 ISA

If the flags are `0x70001007` (without the `0x400` bit that represents `nan2008`), the binary will not be compatible.

---

## 2. Required toolchain and architecture constraint

### 2.1 Official Ingenic toolchain

The reference toolchain to compile native code for Ingenic XBurst2 is the **Dafang-Hacks** one:

```
https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1
```

This toolchain is based on **GCC 5.2** (exact version embedded by Ingenic in their official BSP).

### 2.2 Constraint: x86_64 host required

The toolchain is distributed as binaries **pre-built for x86_64 Linux**:

```bash
$ file ~/ingenic-toolchain/bin/mips-linux-gnu-gcc
ELF 64-bit LSB executable, x86-64, version 1 (SYSV),
dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2,
for GNU/Linux 2.6.18, BuildID[...], stripped
```

**Implication:** an **x86_64** host is mandatory to run it. On an ARM64 host (Raspberry Pi, SBC, Apple Silicon Mac, etc.), trying to launch the toolchain produces:

```
cannot execute binary file: Exec format error
```

Even with `qemu-user` emulation, performance is unusable and stability is not guaranteed.

### 2.3 Rejected alternatives

Other approaches were considered but rejected:

1. **Find an ARM64 port of the Ingenic GCC 5.2 toolchain** → none is publicly available (Ingenic only ships x86_64 hosts).
2. **Rebuild the toolchain from source** → several hours of compilation + `binutils` + `gcc` + `glibc` chain to rebuild. High risk of divergence from the official toolchain.
3. **Use the Debian `gcc-mipsel-linux-gnu` cross-compiler** → this is GCC 10.x; the `-mnan=2008 -mfp64 -mabs=2008` flags are accepted but the produced binary does not have the right signature (minor ABI incompatibilities with the Nebula's linker).

**The only reliable path is therefore: official Ingenic toolchain, on an x86_64 host.**

---

## 3. Adopted solution — GitHub Codespaces

### 3.1 Why Codespaces

**GitHub Codespaces** is a free service (60 hours/month on a personal GitHub account) that provisions on-demand Linux **x86_64** environments accessible directly in the browser via VS Code web.

Benefits for this use case:
- **x86_64** architecture — compatible with the Ingenic toolchain.
- Recent Debian/Ubuntu environment — no glibc issues.
- Full terminal access, root via `sudo`.
- Easy download of the produced binary through the VS Code file explorer (right-click → Download).
- No local installation required.

### 3.2 Full workflow

#### Step 1 — Create a codespace

1. Log in to GitHub.
2. Open https://github.com/codespaces.
3. **New codespace** → pick any repo (e.g. `Klipper3d/klipper` directly).
4. Wait for provisioning (~30 seconds).
5. A bash terminal opens at `/workspaces/<repo>`.

Architecture check:

```bash
uname -m
# Expected output: x86_64
```

#### Step 2 — Clone the Ingenic toolchain

```bash
git clone --depth 1 \
  https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1 \
  ~/ingenic-toolchain
```

The toolchain is ~250 MB and clones in ~30 seconds from GitHub datacenters.

Verification:

```bash
~/ingenic-toolchain/bin/mips-linux-gnu-gcc --version
```

Expected output:

```
mips-linux-gnu-gcc (Ingenic r3.2.1-gcc520 2017.12-15) 5.2.0
Copyright (C) 2015 Free Software Foundation, Inc.
```

#### Step 3 — Clone Klipper mainline (if needed)

If the codespace was not created from the Klipper repo directly:

```bash
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper
```

#### Step 4 — Build `c_helper.so`

```bash
cd /workspaces/klipper/klippy/chelper

~/ingenic-toolchain/bin/mips-linux-gnu-gcc \
    -shared -fPIC -O2 \
    -mnan=2008 -mfp64 -mabs=2008 \
    $(ls *.c) \
    -o c_helper.so
```

**Key points:**

- `-shared -fPIC` → position-independent shared library (required by `ctypes.CDLL`).
- `-O2` → standard optimization (same level as upstream Klipper).
- `-mnan=2008` → mandatory to get the `0x400` flag bit in the ELF header.
- `-mfp64` → 64-bit FPU (matches XBurst2 CPU).
- `-mabs=2008` → FP absolute value behavior compliant with IEEE 754-2008.
- `$(ls *.c)` → compile every `.c` file in `chelper/` (currently `itersolve.c`, `kin_*.c`, `trapq.c`, etc.).
- **No `-lm`** → linking against `libm` introduces a `libm.so.6` dependency that does not exist on the Nebula. Without `-lm`, the `math.h` symbols used in `c_helper.so` are resolved via `libc` only.

#### Step 5 — Validate ELF flags

```bash
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -h c_helper.so | grep "Flags"
```

Expected output:

```
Flags: 0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2
```

If flags are `0x70001007` (without `nan2008`), **rebuild** — the `-mnan=2008` flag did not take effect.

#### Step 6 — Validate dependencies

```bash
~/ingenic-toolchain/bin/mips-linux-gnu-readelf -d c_helper.so | grep "NEEDED"
```

Expected output (and nothing else):

```
0x00000001 (NEEDED)     Shared library: [libc.so.6]
```

If `libm.so.6` appears, rebuild **without** `-lm`.

#### Step 7 — Validate ELF format

```bash
od -t x1 c_helper.so | head -1
```

Expected output:

```
0000000  7f 45 4c 46 01 01 01 00 03 00 00 00 00 00 00 00
```

Key bytes:
- `7f 45 4c 46` → ELF magic number (`.ELF`).
- Byte 4 (`01`) → 32-bit class.
- Byte 5 (`01`) → little endian.
- Byte 8 (`03`) → OS/ABI = Linux.

When compared byte-by-byte with a `c_helper.so` extracted from a reference Creality firmware, the headers are identical. Our built binary is therefore format-compatible.

---

## 4. Transferring the binary to the Nebula

### 4.1 Network constraint

The codespace runs in GitHub's cloud (Azure East US). It **cannot** reach a local IP like `192.168.x.x`. A `scp codespace → nebula` call always fails:

```
ssh: Could not resolve hostname 192.168.x.x: Name or service not known
```

### 4.2 Recommended method

**Flow:** Codespace → local Windows PC → Nebula.

**Step A — Download Codespace → Windows PC:**

In VS Code web's file explorer (left pane of the codespace):
- Navigate to `/workspaces/klipper/klippy/chelper/`.
- Right-click on `c_helper.so` → **Download**.
- The browser saves the file into the `Downloads` folder.

**Step B — Transfer PC → Nebula via SCP:**

Windows PowerShell:

```powershell
scp C:\Users\<user>\Downloads\c_helper.so `
    root@<NEBULA_IP>:/usr/data/klipper/klippy/chelper/c_helper.so
```

**Caveat:** the Nebula does not ship with `sftp-server`. Recent SCP clients that require SFTP (OpenSSH 9+) may fail with:

```
sh: /usr/libexec/sftp-server: not found
```

Workarounds:
- Use `scp -O` to force the legacy protocol.
- Use an older Windows client (`pscp.exe` from PuTTY).
- Go through an intermediate host that supports legacy SCP (Raspberry Pi, another SBC).

### 4.3 Alternative — GitHub Raw

Once `c_helper.so` has been validated, it can be uploaded to a public GitHub repository. The Nebula can then fetch it directly:

```bash
wget --no-check-certificate \
  https://raw.githubusercontent.com/christianKEL/E5M-CK/main/c_helper.so \
  -O /usr/data/klipper/klippy/chelper/c_helper.so
```

**Important:** the Nebula uses a BusyBox `wget` built without modern SSL. The `--no-check-certificate` option is mandatory.

This is the method used by the E5M-CK project's `install.sh`.

---

## 5. Validation on the Nebula

### 5.1 Python load test

```bash
/usr/share/klippy-env/bin/python3 -c \
  "import ctypes; ctypes.CDLL('/usr/data/klipper/klippy/chelper/c_helper.so'); print('OK')"
```

Expected output:

```
OK
```

If the error is `cannot open shared object file: No such file or directory`, check the path.

If the error is `wrong ELF class: ELFCLASS64` or `unsupported ELF format`, the binary was built with the wrong flags or for the wrong architecture.

### 5.2 Full Klippy startup test

```bash
/etc/init.d/S55klipper_service restart
sleep 30
curl http://localhost:7125/printer/info 2>/dev/null | \
  python3 -c "import sys,json; d=json.load(sys.stdin); \
  print(d['result']['state'], '-', d['result']['software_version'])"
```

Expected output:

```
ready - v0.13.0-628-g373f200ca
```

If `state = startup` for more than a minute or `state = error`, check:

```bash
tail -100 /usr/data/printer_data/logs/klippy.log
```

Typical error messages tied to `c_helper.so`:

- `Unable to load chelper: ... undefined symbol ...` → binary built for a different Klipper version. Rebuild from a recent clone.
- `Unable to open chelper ... c_helper.so: cannot open shared object` → wrong path.
- `chelper signature mismatch` → the compiled `.c` files do not match the `klippy.py` version trying to load them.

---

## 6. Maintenance and updates

### 6.1 When should you rebuild?

Rebuild is required whenever:

- The `klippy/chelper/*.c` source files change in Klipper mainline (upstream updates).
- A `.c` file is added or removed.
- Klipper is updated via `git pull` and `chelper/` is affected.

### 6.2 Update procedure

In the existing (or a new) codespace:

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
# Ensure the result still contains "nan2008"
```

Then redistribute via GitHub Raw or SCP as in Section 4.

### 6.3 Backup

It is recommended to keep:
- The last known-good `c_helper.so` (in `/usr/data/E5M_CK/c_helper.so` on the Nebula).
- The Klipper commit hash used to build it (`git rev-parse HEAD` in the codespace at build time).

This makes it possible to roll back to a known version in case of upstream regression.

---

## 7. Recap — minimal commands

For a full build **from scratch** on a blank codespace:

```bash
# Toolchain
git clone --depth 1 \
  https://github.com/Dafang-Hacks/mips-gcc520-glibc222-64bit-r3.2.1 \
  ~/ingenic-toolchain

# Klipper mainline (if codespace is blank)
git clone https://github.com/Klipper3d/klipper.git /workspaces/klipper

# Build
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

Expected flags: `0x70001407, noreorder, pic, cpic, nan2008, o32, mips32r2`
Expected dependency: `libc.so.6` only

---

## 8. Additional notes

### 8.1 Why not the Debian cross-compiler?

The `gcc-mipsel-linux-gnu` package (Debian 11, GCC 10.2) can technically build with the same flags, but:
- Produces a binary linked against `ld-linux.so.3` rather than `ld.so.1` (the dynamic linker location on Ingenic).
- The glibc version used for linking does not match the one shipped on the Nebula — different symbol versions.
- Default ABI is `n32` whereas we need `o32`.

Technically feasible with many extra flags (`-Wl,--dynamic-linker=...`), but far more fragile than the official Ingenic toolchain.

### 8.2 Why doesn't Klipper build `c_helper.so` on the fly on the Nebula?

At startup, Klippy does try to run `make` in `klippy/chelper/`. On the Nebula:

- GCC is present (`/usr/bin/gcc` → Creality's MIPS toolchain).
- But that toolchain does **not** support `-mnan=2008 -mfp64 -mabs=2008` — compile error.
- The Klipper project's Makefile does not add those specific flags (it assumes a generic toolchain).

The clean fix would be to patch `klippy/chelper/Makefile` to detect the Ingenic environment and add the flags — but that means maintaining a Klipper fork.

Shipping a pre-built `c_helper.so` and preventing the rebuild (by making sure the file exists at startup) is the simplest and most stable solution.

### 8.3 Reference — Creality's `c_helper.so`

The `c_helper.so` shipped with the Creality fork of Klipper (at `/usr/share/klipper/klippy/chelper/c_helper.so` before factory reset) has the following properties:

- Flags: `0x70001407` (with `nan2008`)
- Dependencies: `libc.so.6` only
- OS/ABI: `03` (Linux)

Our binary built using the procedure above is **strictly identical** in format — only the internal symbols differ because the Klipper versions are not the same.

---

*Document written in April 2026 as part of the E5M-CK project.*
