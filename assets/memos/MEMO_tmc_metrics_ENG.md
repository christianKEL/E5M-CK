# TECHNICAL MEMO — GuppyScreen TMC Metrics

## Klipper mainline + Creality 2023 nozzle MCU + TMC2209 drivers

**Author:** Christian KELHETTER
**Project:** E5M-CK — https://github.com/christianKEL/E5M-CK
**Date:** May 2026
**Status:** **Disabled — not viable on this stack** (see §6 for rationale)

---

## 1. Context and purpose

### 1.1 What TMC Metrics is

GuppyScreen ships a touch UI panel called **TMC Metrics** (binary string `Shake Belts` / `Input Shaper` / **`TMC Metrics`**) that displays per-driver Trinamic status in real time: motor current (`i_rms`), chopper mode (SpreadCycle/StealthChop), thermal flags (`otpw`, `ot`), stallguard value, and so on. It's a diagnostic tool — equivalent to Klipper's `DUMP_TMC` command but always-on and graphical.

The on-screen warning in the binary explicitly notes:

```
TMC Metrics is experimental and disabled by default.
Turn it on as needed. For in-depth detail, refer to the TMC driver datasheet.
```

That's the upstream-acknowledged hint that this feature is **fragile**.

### 1.2 The data path

```
GuppyScreen UI (TmcStatusPanel)
    ↓ webhooks subscribe "tmcstatus"
Moonraker (klippy_connection)
    ↓ objects/subscribe { "tmcstatus": null }
Klipper webhooks (_do_query)
    ↓ poll get_status(eventtime) ~10 Hz
tmcstatus.py (TMCStatus.get_status)
    ↓ for each driver:
    ↓   tmcobj.mcu_tmc.get_register('DRV_STATUS')   ← TMC UART read
    ↓   tmcobj.mcu_tmc.get_register('SG_RESULT')    ← TMC UART read
    ↓   tmcobj.fields.get_field(...) × ~15 fields   ← cached reads
tmc_uart.py (mcu_uart.reg_read)
    ↓ tmcuart_send_cmd.send([oid, msg, 10])
nozzle MCU (CR-NOZZLE_V21, Creality 2023 firmware)
    ↓ executes tmcuart_send / tmcuart_response
TMC2209 driver
    → returns register value
```

For 4 drivers (`stepper_x`, `stepper_y`, `stepper_z`, `extruder`), each `get_status` call performs roughly:

- 4 × `DRV_STATUS` reads (UART round-trip)
- 4 × `SG_RESULT` reads (UART round-trip)
- ~60 cached field reads (no UART, but Python overhead)

= **8 UART transactions per poll**, polled at ~10 Hz → **~80 UART round-trips per second**, shared with all other Klipper traffic (heaters, accelerometer, motion commands).

### 1.3 The wiring on the E5M-CK

```ini
[tmc2209 stepper_x]   # mainboard MCU UART
[tmc2209 stepper_y]   # mainboard MCU UART
[tmc2209 stepper_z]   # mainboard MCU UART
[tmc2209 extruder]    # nozzle_mcu UART (Creality 2023 firmware!)
```

The extruder TMC is on the **nozzle MCU**, which runs the legacy Creality 2023 firmware (`341a2c18-dirty-20230717_152940-cxsw`). This firmware has been observed in this project to have **stricter watchdog/timeout behavior** than mainline Klipper firmware (cf the ADXL345 bridge work in `MEMO_adxl345_bridge_ENG.md`).

---

## 2. The starting state — module already present

The `tmcstatus.py` module ships as part of the GuppyScreen install:

```
/usr/data/guppyscreen/k1_mods/tmcstatus.py
```

and is symlinked into Klipper's extras directory:

```
/usr/data/klipper/klippy/extras/tmcstatus.py
  → /usr/data/guppyscreen/k1_mods/tmcstatus.py
```

The companion module loader `guppy_module_loader.py` registers two G-code commands:

```python
_GUPPY_LOAD_MODULE SECTION=tmcstatus
_GUPPY_UNLOAD_MODULE SECTION=tmcstatus
```

These are designed for **lazy loading**: GuppyScreen calls `_GUPPY_LOAD_MODULE` when the user opens the TMC Metrics panel, and `_GUPPY_UNLOAD_MODULE` when they leave. The idea is to avoid the UART load when no one is looking.

The mechanism works via `printer.load_object()` / `printer.objects.pop()`.

---

## 3. Initial diagnosis — module not loaded

A query before any change:

```bash
$ curl -s 'http://localhost:7125/printer/objects/query?tmcstatus'
{"result":{"eventtime":233.171192666,"status":{"tmcstatus":{}}}}
```

The object exists in Moonraker's subscription list (because GuppyScreen subscribes to it on connect) but is **empty**: there's no `[tmcstatus]` section in `printer.cfg`, so the Python module is never instantiated. GuppyScreen's TMC Metrics panel displays empty fields.

That's how the system has been running historically — silently broken, no crash, no functionality.

---

## 4. Activation attempts and observed failures

Three increasingly sophisticated patches were attempted. All three failed, in increasingly informative ways.

### 4.1 Attempt 1 — declare `[tmcstatus]` in config

The first try: add a `[tmcstatus]` section in a new file `tmcstatus.cfg` included from `printer.cfg`:

```ini
[include tmcstatus.cfg]   # line 17 of printer.cfg
```

```ini
# tmcstatus.cfg
[tmcstatus]
```

Result on FIRMWARE_RESTART:

```
Unknown config object 'tmc2209 stepper_x'
Once the underlying issue is corrected, use the "RESTART"
command to reload the config and restart the host software.
Printer is halted
```

**Root cause**: Klipper processes config sections **in their order of appearance** after `[include]` expansion. With `[include tmcstatus.cfg]` at line 17 and `[tmc2209 stepper_x]` at line 87+, the module's `__init__` runs **before** the TMC drivers are instantiated. The direct call `self.handle_connect()` in `__init__` then fails:

```python
def __init__(self, config):
    ...
    for driver in TRINAMIC_DRIVERS:
        self.configured_steppers.extend(
            [n.get_name() for n in self.config.get_prefix_sections(driver)])
    self.handle_connect()   # ← too early

def handle_connect(self):
    for s in self.configured_steppers:
        tmc = self.printer.lookup_object(s)   # → "Unknown config object"
```

### 4.2 Attempt 2 — defer to `klippy:connect`

Standard Klipper idiom: register an event handler for `klippy:connect`, which fires **after** all sections have been instantiated.

```python
# Patch
self.printer.register_event_handler("klippy:connect", self.handle_connect)
```

Result on FIRMWARE_RESTART:

```
File "tmcstatus.py", line 19, in __init__
File "tmcstatus.py", line 23, in handle_connect
  self.printer.register_event_handler("klippy:connect", ...)
File "klippy.py", line 79, in lookup_object
  raise self.config_error("Unknown config object '%s'" % (name,))
configparser.Error: Unknown config object 'tmc2209 stepper_x'
```

**Root cause**: the traceback is deceptive. The handler **was** registered, but Klipper called it **immediately** because the `klippy:connect` event had already fired by the time `[tmcstatus]` (loaded as last config section) finished its `__init__`. When Klipper sees a handler registered for an event that has already happened, it dispatches it synchronously. The handler then runs in the same context as `__init__`, before TMC drivers exist.

### 4.3 Attempt 3 — force-load TMC sections from `handle_connect`

If `lookup_object` fails, try `load_object` to force creation of the section:

```python
def handle_connect(self):
    for s in self.configured_steppers:
        tmc = self.printer.lookup_object(s, None)
        if tmc is None:
            try:
                tmc = self.printer.load_object(self.config, s)
            except Exception as e:
                logging.info("tmcstatus: failed to load %s: %s", s, e)
                continue
        self.tmcs[s] = tmc
```

Result on FIRMWARE_RESTART: Klipper started cleanly. The `[tmcstatus]` module loaded, populated `self.tmcs` correctly. Then `_GUPPY_LOAD_MODULE` was triggered to enable the lazy-load path. Within 2 seconds:

```
Receive: ... shutdown clock=1325715900 static_string_id=Command request
gcode state: ...
Repeat unhandled exception during run
Traceback (most recent call last):
  File "/usr/data/klipper/klippy/reactor.py", line 153, in update_timer
    if timer_handler.timer_is_running:
AttributeError: 'NoneType' object has no attribute 'timer_is_running'
```

**Root cause**: this is **not** a tmcstatus.py bug. The MCU sent a `shutdown` signal (`Command request` is a Creality 2023 firmware watchdog timeout). During Klipper's shutdown propagation, `reactor.py:153` tried to update a timer that had already been cleared — leading to the `AttributeError` on `timer_is_running`.

The TMC UART polling **triggered the MCU watchdog**. The crash that followed is a separate Klipper mainline bug exposed by the shutdown path, but the root cause is the polling load itself.

### 4.4 Attempt 4 — rate-limit the polling

Added a 1-second cache to `get_status`:

```python
TMC_READ_INTERVAL = 1.0

def get_status(self, eventtime):
    if eventtime - self.last_read_time < TMC_READ_INTERVAL:
        return self.cached_data
    # ... read UART ...
    self.cached_data = data
    self.last_read_time = eventtime
    return data
```

Result: identical crash. The rate-limit doesn't help because the crash happens on the **first** poll after `_GUPPY_LOAD_MODULE`. The polling reduction from ~10 Hz to 1 Hz is moot if the very first read triggers the MCU shutdown.

---

## 5. Root cause analysis

After four attempts, the failure pattern is consistent:

1. The module loads cleanly (with the right deferral).
2. The first TMC UART read triggered by Moonraker's status query causes the nozzle MCU to issue a `shutdown` ("Command request" timeout).
3. During Klipper's shutdown propagation, `reactor.update_timer` is called on an already-cleared timer object, causing `AttributeError`.

Three contributing factors, none of which can be fixed in `tmcstatus.py` alone:

### 5.1 Nozzle MCU firmware (Creality 2023)

The CR-NOZZLE_V21 firmware (`341a2c18-dirty-20230717_152940-cxsw`) has a **strict command-request timeout**. When the Klipper host sends an unexpected `tmcuart_send` command while the MCU is busy with something else (heater control, fan PWM, etc.), the firmware treats it as a protocol violation and shuts down.

This is the same firmware that requires the ADXL345 bridge (`MEMO_adxl345_bridge_ENG.md`) — it's just not designed for the access patterns mainline Klipper expects.

### 5.2 Klipper mainline reactor bug

`reactor.py` line 153:

```python
def update_timer(self, timer_handler, waketime):
    if timer_handler.timer_is_running:
        ...
```

If `timer_handler` is `None` (which happens when a `ReactorCompletion` is cleaned up early during shutdown), this raises `AttributeError`. The proper code would be:

```python
if timer_handler is not None and timer_handler.timer_is_running:
    ...
```

This is a real Klipper bug, present in the version we're running (~v0.13.0-642). Patching it would require either:

- Submitting a PR upstream and waiting for release
- Patching the local copy at every Klipper update

Either way, this only **masks** the crash. The MCU shutdown is still real — it just wouldn't crash Klipper afterward.

### 5.3 Shared UART contention

The TMC drivers share their UART bus with all other Klipper traffic to the same MCU. On the nozzle MCU specifically:

- TMC2209 extruder reg reads (when tmcstatus is active)
- TMC drive current updates
- Heater PWM control commands
- Fan PWM commands
- ADXL345 SPI commands (via the bridge)

The 2023 firmware's UART buffer is small and its command-handling loop strict. Adding a regular flood of TMC reg reads disrupts the timing the firmware expects.

---

## 6. Decision — disable, document, move on

After all four attempts and the root-cause analysis, the conclusion:

**TMC Metrics is not viable on the E5M-CK stack as currently configured.**

The only paths forward are:

| Path | Estimated effort | Risk | Reversible? |
|---|---|---|---|
| Patch Klipper `reactor.py` line 153 | 1 hour | Low | Yes (every update) |
| Fork nozzle MCU firmware to relax watchdog | 8+ hours | **High** (bricks the toolhead heater control) | Hard |
| Move extruder TMC off nozzle MCU | Hardware mod | **High** | No |
| Implement async TMC polling via custom Klipper module | 4 hours | Medium | Yes |
| Accept the limitation | 0 hours | None | N/A |

**Selected path: accept the limitation.** TMC Metrics is informational, not operational. Running prints without it works exactly as before; the GuppyScreen panel simply remains empty.

### 6.1 Final configuration state

```bash
# Module file restored to original (in case of future re-attempt)
$ md5sum /usr/data/guppyscreen/k1_mods/tmcstatus.py
<original md5>

# Include disabled
$ grep tmcstatus /usr/data/printer_data/config/printer.cfg
#[include tmcstatus.cfg]

# Klipper running normally
$ curl -s http://localhost:7125/printer/info | grep state_message
"state_message": "Printer is ready"
```

### 6.2 What works without TMC Metrics

Everything else, completely unaffected:

- Heater control, motion, accelerometer (via ADXL345 bridge), Belts, Input Shaper
- Sensorless homing on X/Y (which uses TMC `diag_pin` directly, no UART polling)
- TMC driver current/sensitivity tuning via `printer.cfg` parameters (no runtime introspection needed)
- Manual one-shot `DUMP_TMC` command (Klipper native, single read, no continuous polling)

If you ever need to inspect TMC state for a specific issue, use `DUMP_TMC STEPPER=stepper_x` from Fluidd console. It performs one read, prints to log, no polling involved.

---

## 7. Future work — paths not pursued

### 7.1 Patch Klipper reactor.py

The cleanest one-line fix to mask the crash:

```python
# /usr/data/klipper/klippy/reactor.py line ~153
def update_timer(self, timer_handler, waketime):
    if timer_handler is not None and timer_handler.timer_is_running:
        ...
```

This wouldn't make TMC Metrics work; it would just prevent Klipper from crashing when the MCU shuts down. The MCU shutdown would still require a `FIRMWARE_RESTART` to recover, so the user experience is "TMC Metrics works for ~2 seconds, then the printer halts and needs restart" — not much improvement.

Worth doing if you're patching `reactor.py` for other reasons anyway. Tag this section for a future revision if such a patch ever happens.

### 7.2 Submit the reactor bug upstream

The bug is real and not E5M-specific. A PR to the Klipper repo with a small test case (any module triggering an MCU shutdown during a webhooks query) would benefit the community. Out of scope for E5M-CK.

### 7.3 Async TMC polling

A custom Klipper module that:

- Reads TMC registers in a **dedicated reactor timer** (not during webhooks `get_status`)
- Schedules reads at a slow, predictable rate (e.g., once per 5 seconds)
- Spaces individual driver reads by 100 ms each to give the MCU breathing room
- Caches values aggressively

Would probably work. Estimated 4 hours of design + coding + testing. The benefit is marginal (a partially-working diagnostic panel) versus the cost. Not done.

### 7.4 Replace nozzle MCU firmware

The 2023 firmware is the strict element. If the firmware were rebuilt from Klipper mainline sources for the GD32F303CBT6 (the chip on CR-NOZZLE_V21), it would presumably tolerate parallel UART reads. But that's the whole "flash a custom firmware to the toolhead MCU" path — high risk, and the project has explicitly chosen to **avoid** that route (cf `MEMO_adxl345_bridge_ENG.md` §1.1).

---

## 8. Recap — minimum commands for reference

If a future maintainer wants to try again, the starting state should be:

```bash
# Verify module is original
md5sum /usr/data/guppyscreen/k1_mods/tmcstatus.py

# Verify Klipper is healthy
curl -s http://localhost:7125/printer/info | python3 -m json.tool | grep state_message
# Expected: "Printer is ready"

# Confirm include is disabled
grep tmcstatus /usr/data/printer_data/config/printer.cfg
# Expected: "#[include tmcstatus.cfg]" (commented)
```

To re-attempt activation (NOT RECOMMENDED without a strategy from §7):

```bash
# Enable
sed -i 's|^#\[include tmcstatus.cfg\]|[include tmcstatus.cfg]|' \
    /usr/data/printer_data/config/printer.cfg

curl -X POST http://localhost:7125/printer/firmware_restart
```

To disable urgently (e.g. if the printer halts on activation):

```bash
sed -i 's|^\[include tmcstatus.cfg\]|#[include tmcstatus.cfg]|' \
    /usr/data/printer_data/config/printer.cfg

/etc/init.d/S55klipper_service restart
```

---

## 9. Repository layout

```
E5M-CK/
├── files/
│   └── (no TMC files — module is upstream, not modified)
├── installs/
│   └── (no TMC installer — feature disabled)
└── docs/
    ├── MEMO_c_helper_ENG.md
    ├── MEMO_adxl345_bridge_ENG.md
    ├── MEMO_guppyscreen_belts_ENG.md
    └── MEMO_tmc_metrics_ENG.md   ← this file
```

The `tmcstatus.cfg` activation file remains in `/usr/data/printer_data/config/` on the printer as a documentation artifact (with its `[tmcstatus]` section), but the `[include]` in `printer.cfg` is commented out.

---

*Document written in May 2026 as part of the E5M-CK project. Companion to `MEMO_c_helper_ENG.md`, `MEMO_adxl345_bridge_ENG.md`, and `MEMO_guppyscreen_belts_ENG.md`.*
