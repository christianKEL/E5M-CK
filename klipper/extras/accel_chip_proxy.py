# accel_chip_proxy — synthetic accelerometer chip for the E5M nozzle MCU.
#
# Purpose
# -------
# The Ender 5 Max's ADXL345 accelerometer is wired into the SPI bus of the
# stock Creality 2023 nozzle-MCU firmware. Mainline Klipper's [adxl345]
# driver cannot talk to that firmware because the on-wire protocol differs:
#   - query_adxl345 arity (3 args vs 2)
#   - sample packing (5 bytes/sample, Z high-bits masked with 0x60)
#   - callback registration moved between MCU and MCU_serial layers
# See docs/operations/input_shaper.md ("Why a proxy?") for the full account.
#
# Reflashing the nozzle MCU would break our factory_reset rollback path
# (see installs/creality_kill.sh + docs/operations/factory_reset.md), so
# the fix lives on the host: this proxy registers a synthetic accel chip
# named "accel_chip_proxy" that [resonance_tester] can target.
#
# Source code references this code wraps
# --------------------------------------
#   klippy/extras/adxl345.py        upstream ADXL driver (incompatible
#                                   with the stock firmware's wire format)
#   klippy/extras/adxl345_creality  sibling module in this directory
#                                   that ports the stock dialect
#
# Klipper master compatibility (verified on commit bd09e0170, May 2026):
#   - AccelCommandHelper(config, chip) signature: unchanged
#   - BatchBulkHelper(printer, batch_cb, ...): unchanged
#   - resonance_tester now requires start_internal_client (added 2025-09):
#     this module exposes it on AccelChipProxy.
#   - mcu._serial.register_response: this module handles the post-2026
#     location of the callback registration (see adxl345_creality.py).
#
# Deployed by installs/install_klipper.sh via the /tmp/klipper_extras_*.py
# staging mechanism — see "Custom klippy/extras/ Python modules" in
# docs/operations/klipper_install.md.
#
# Rollback: remove [accel_chip_proxy] from the active config (it lives in
# klipper/config/input_shaper.cfg) and restart Klipper. The .py file
# remains on disk but Klipper only loads modules with active sections.
#
# === Body below preserved verbatim from v1 ===========================
import logging


class _ConfigWrapperProxy:
    """Re-prefixes config option lookups (e.g. 'cs_pin' ->
    'adxl345_cs_pin') so the underlying chip class sees the flat
    option names it expects."""

    def __init__(self, config, chip_name):
        self.config = config
        self.chip_name = chip_name

    def get(self, option, default=None, note_valid=True):
        return self.config.get(
            '%s_%s' % (self.chip_name, option),
            default, note_valid=note_valid)

    def getint(self, option, default=None,
               minval=None, maxval=None, note_valid=True):
        return self.config.getint(
            '%s_%s' % (self.chip_name, option),
            default, minval=minval, maxval=maxval, note_valid=note_valid)

    def getfloat(self, option, default=None,
                 minval=None, maxval=None, note_valid=True):
        return self.config.getfloat(
            '%s_%s' % (self.chip_name, option),
            default, minval=minval, maxval=maxval, note_valid=note_valid)

    def getlist(self, option, default=None,
                sep=',', count=None, note_valid=True):
        return self.config.getlist(
            '%s_%s' % (self.chip_name, option),
            default, sep=sep, count=count, note_valid=note_valid)

    def __getattr__(self, name):
        return getattr(self.config, name)


class AccelChipProxy:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.config = config
        self.name = config.get_name()

        # Mark every option as read so Klipper doesn't warn about
        # unused parameters (the wrapped chip only reads its own prefix).
        for option in config.fileconfig.options(self.config.get_name()):
            try:
                config.get(option)
            except Exception:
                pass

        chip_kind = config.get('accel_use_chip', 'adxl345').strip().lower()
        if chip_kind not in ('adxl345', 'lis2dw'):
            raise config.error(
                "accel_use_chip must be 'adxl345' or 'lis2dw', got '%s'"
                % (chip_kind,))

        # Register the standard ACCELEROMETER_* G-code commands so
        # they're available at boot. They internally call
        # start_internal_client() on us, which forwards to self._chip.
        from . import adxl345 as _mainline_adxl345
        _mainline_adxl345.AccelCommandHelper(config, self)

        # Instantiate the wrapped chip immediately. Its __init__
        # registers add_config_cmd + register_config_callback with the
        # MCU; both are legal during printer.cfg parsing.
        from . import adxl345_creality
        wrapped_config = _ConfigWrapperProxy(config, chip_kind)
        if chip_kind == 'adxl345':
            logging.info("accel_chip_proxy: instantiating ADXL345")
            self._chip = adxl345_creality.ADXL345(wrapped_config)
        else:
            logging.info("accel_chip_proxy: instantiating LIS2DW")
            self._chip = adxl345_creality.LIS2DW(wrapped_config)

    # ─── Forwarded API used by resonance_tester / shaper /
    # ─── ACCELEROMETER_* commands ──────────────────────────────────
    def start_internal_client(self):
        return self._chip.start_internal_client()

    def read_reg(self, reg):
        return self._chip.read_reg(reg)

    def set_reg(self, reg, val, minclock=0):
        return self._chip.set_reg(reg, val, minclock=minclock)


def load_config(config):
    return AccelChipProxy(config)


def load_config_prefix(config):
    return AccelChipProxy(config)
