# E5M-CK v2

> **GitOps-managed mainline Klipper stack for the Creality Ender 5 Max.**

A clean, observable, fully open-source firmware overlay for the stock Ender 5 Max — built on mainline Klipper (no fork, no dirty patches) plus Moonraker, Fluidd, GuppyScreen, and a BTT Eddy probe.

The repo is the **source of truth**. A `sync.sh` script applies it to the printer over SSH. The original Creality firmware always remains recoverable (USB factory reset + SSH script).

## Status

🚧 **Active development on branch `main-v2`.** The previous v1 lives on branch `main` and remains usable.

- [`ROADMAP.md`](ROADMAP.md) — vision, scope, install order, acceptance criteria, open questions
- [`PLAN.md`](PLAN.md) — phased execution plan with prereqs / steps / rollback per phase

## Quick links

- Documentation: [`docs/`](docs/)
- Install scripts: [`installs/`](installs/)
- GitOps tooling: [`scripts/`](scripts/)
- Klipper configuration: [`klipper/config/`](klipper/config/)

## Hardware target

- **Printer:** Creality Ender 5 Max (stock board, multi-MCU: GD32 main / nozzle / leveling)
- **SoC:** Ingenic XBurst II V2 (MIPS dual-core, 200 MB RAM)
- **OS:** Buildroot 2020.02.1 (squashfs RO + overlay)
- **Probe:** BTT Eddy (replaces stock load cell)
- **Screen:** GuppyScreen (replaces stock Creality display-server)

## License

TBD — likely GPL-3 to stay compatible with Klipper. Open question on the roadmap.
