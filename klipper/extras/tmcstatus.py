# tmcstatus.py — Klipper-master-safe rewrite of GuppyScreen's k1_mods extra.
#
# Provides the `tmcstatus` Klipper object that GuppyScreen's TMC Metrics
# panel subscribes to via Moonraker (`printer.tmcstatus.*`). Per stepper:
# parsed DRV_STATUS bits, SG_RESULT (if supported), and cached config
# register fields.
#
# Why this is a vendored rewrite vs. the upstream version shipped in
# /usr/data/guppyscreen/k1_mods/tmcstatus.py:
#
# Upstream was written for the Creality K1 Klipper fork. It reads
# DRV_STATUS and SG_RESULT directly from inside get_status(), which on
# Klipper master crashes the system: get_status is called by Moonraker
# objects/subscribe up to ~4 Hz on the reactor thread, and each call did
# 8 blocking UART transactions (2 registers × 4 drivers, ~80 ms total
# at 40 kbps bitbang while holding the per-MCU mutex). That stalls the
# reactor and overflows the gd32f303's command pipeline, triggering an
# MCU shutdown with "Command request" and a secondary reactor crash
# (`'NoneType' object has no attribute 'timer_is_running'` in
# reactor.py:153 — Klippy tearing down timers mid-exception).
#
# Master-safe pattern (mirrors klippy/extras/tmc.py TMCErrorCheck,
# lines 88-222):
#   1. Look up TMC objects on `klippy:connect`, not in __init__ —
#      at __init__ time the [tmc2209 stepper_x] objects don't exist yet.
#   2. Register a reactor timer that polls live registers at 1 Hz and
#      writes the result into self._cache.
#   3. get_status() returns self._cache only. Zero UART traffic in the
#      hot callback.
#   4. Every get_register() is wrapped in try/except so a UART hiccup
#      cannot escape into invoke_shutdown.
#   5. SG_RESULT is read only if mcu_tmc.name_to_reg has it (TMC2209
#      only — TMC2208/2130/etc. don't, and an unconditional read would
#      raise KeyError on those drivers).
#
# Config registers (CHOPCONF/PWMCONF/COOLCONF/TPWMTHRS/TCOOLTHRS) are
# read once at connect time and cached in self._static_fields. They
# don't change during a print so no polling is needed.

import logging

TRINAMIC_DRIVERS = ["tmc2130", "tmc2208", "tmc2209", "tmc2240", "tmc2660", "tmc5160"]

# RDSON values for current calculation (cs_actual → i_rms in mA).
# Only filled for the driver families we actually use; if a future
# E5M variant adds e.g. a TMC5160 board, add its rsense here.
RSENSES = {
    "tmc2209": 0.11,
}

POLL_INTERVAL = 1.0   # seconds — matches TMCErrorCheck cadence


class TMCStatus:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.configured_steppers = []
        for driver in TRINAMIC_DRIVERS:
            self.configured_steppers.extend(
                [n.get_name() for n in config.get_prefix_sections(driver)])
        self.tmcs = {}            # filled at connect time
        self._cache = {}          # live registers, refreshed by _poll
        self._static_fields = {}  # config registers, captured once
        self._timer = None
        # Two ways this extra reaches us:
        #   1. Declared as [tmcstatus] in printer.cfg → load at config-parse,
        #      before steppers exist. Must defer to klippy:connect.
        #   2. Loaded at runtime via _GUPPY_LOAD_MODULE → klippy:connect
        #      already fired; register_event_handler would never call us.
        #      Steppers exist; we can connect now.
        # Detect mode by probing for the toolhead (created last during
        # config parse, present any time after config-parse completes).
        if self.printer.lookup_object('toolhead', None) is None:
            self.printer.register_event_handler(
                "klippy:connect", self._handle_connect)
        else:
            self._handle_connect()

    def _handle_connect(self):
        for name in self.configured_steppers:
            try:
                self.tmcs[name] = self.printer.lookup_object(name)
            except self.printer.config_error:
                logging.warning("tmcstatus: %s not found at connect", name)
                continue
        for name, tmcobj in self.tmcs.items():
            self._static_fields[name] = self._capture_static(tmcobj)
        reactor = self.printer.get_reactor()
        self._timer = reactor.register_timer(self._poll, reactor.NOW)

    def _capture_static(self, tmcobj):
        # Write-only config registers — Klipper holds the last-written
        # value in fields.set_field(), which is exactly the cache we
        # want. No UART traffic. Some fields may not exist on every
        # driver family (en_pwm_mode is TMC2208/TMC2209 only, etc.).
        keys = ['hstrt', 'hend',
                'pwm_autoscale', 'pwm_autograd', 'pwm_grad', 'pwm_ofs',
                'pwm_reg', 'pwm_lim', 'tpwmthrs',
                'en_spreadcycle', 'tbl', 'toff',
                'tcoolthrs',
                'semin', 'semax', 'seup', 'sedn', 'seimin']
        out = {}
        for k in keys:
            try:
                if tmcobj.fields.lookup_register(k, None) is not None:
                    out[k] = tmcobj.fields.get_field(k)
            except Exception:
                pass
        # en_pwm_mode (TMC2208 family) — only if the field exists.
        try:
            if tmcobj.fields.lookup_register('en_pwm_mode', None) is not None:
                out['en_pwm_mode'] = tmcobj.fields.get_field('en_pwm_mode')
        except Exception:
            pass
        return out

    def _poll(self, eventtime):
        # 1 Hz timer. Reads DRV_STATUS (+ SG_RESULT if available) per
        # stepper, parses fields, and replaces self._cache atomically.
        # Every read is guarded — a UART error here must NOT escape to
        # invoke_shutdown, because we're not in a user-initiated context.
        #
        # _GUPPY_UNLOAD_MODULE pops us from printer.objects but doesn't
        # cancel reactor timers. Detect that and self-terminate, otherwise
        # each panel open/close cycle leaves an orphan timer behind.
        if self.printer.lookup_object('tmcstatus', None) is not self:
            return self.printer.get_reactor().NEVER
        snapshot = {}
        for name, tmcobj in self.tmcs.items():
            entry = dict(self._static_fields.get(name, {}))
            try:
                drv_val = tmcobj.mcu_tmc.get_register('DRV_STATUS')
                drv_fields = tmcobj.fields.get_reg_fields('DRV_STATUS', drv_val)
                # Mimic upstream: only emit truthy bits to keep the
                # JSON payload small (the panel only cares about active
                # warnings/errors).
                entry['drv_status'] = {n: v for n, v in drv_fields.items() if v}
                if 'cs_actual' in drv_fields:
                    fam = name.split()[0] if ' ' in name else name
                    rms = self._cs_to_rms(drv_fields['cs_actual'], fam, tmcobj)
                    if rms is not None:
                        entry['i_rms'] = rms
            except Exception as e:
                logging.debug("tmcstatus: DRV_STATUS read failed on %s: %s", name, e)
            # SG_RESULT only exists on TMC2209 — gate by name_to_reg.
            if 'SG_RESULT' in tmcobj.mcu_tmc.name_to_reg:
                try:
                    entry['sg_result'] = tmcobj.mcu_tmc.get_register('SG_RESULT')
                except Exception as e:
                    logging.debug("tmcstatus: SG_RESULT read failed on %s: %s", name, e)
            snapshot[name] = entry
        self._cache = snapshot
        return eventtime + POLL_INTERVAL

    def _cs_to_rms(self, cs, family, tmcobj):
        rsense = RSENSES.get(family)
        if rsense is None:
            return None
        try:
            vsense = tmcobj.fields.get_field('vsense')
        except Exception:
            vsense = 0
        return (cs + 1) / 32.0 * (0.180 if vsense == 1 else 0.325) \
            / (rsense + 0.02) / 1.41421 * 1000

    def get_status(self, eventtime):
        # Pure cache lookup. No UART, no blocking — safe at any rate.
        return self._cache


def load_config(config):
    return TMCStatus(config)
