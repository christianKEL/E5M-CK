# Accelerometer chip proxy for Creality 2023 firmware
#
# Bridges resonance_tester (mainline 2026) onto the legacy Creality
# ADXL345/LIS2DW wire protocol via adxl345_creality.py.
#
# How it works:
#   - Klipper parses [mcu nozzle_mcu] before [accel_chip_proxy] in
#     printer.cfg, so by the time we run printer.lookup_object('mcu
#     nozzle_mcu') in our __init__, the MCU object exists.
#   - We instantiate the ADXL345Creality (or LIS2DW) chip immediately,
#     which registers its add_config_cmd / register_config_callback /
#     register_response with the MCU. The MCU drains those when it
#     finalizes its config — we don't have to time anything.
#   - The proxy IS the chip from resonance_tester's point of view: it
#     exposes start_internal_client(), read_reg(), set_reg() directly
#     and forwards them to the wrapped chip object.
#
# Note on chip selection:
#   accel_use_chip must be set explicitly in printer.cfg ('adxl345' or
#   'lis2dw'). The original Creality proxy auto-detected by reading the
#   ID register at runtime, but doing so requires the MCU data dictionary
#   which isn't available during __init__. Since the wired chip is
#   stable hardware, hardcoding the choice is acceptable and simpler.

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
