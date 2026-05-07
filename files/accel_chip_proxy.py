# Accelerometer chip proxy for Creality 2023 firmware
#
# Bridges resonance_tester (mainline 2026) onto the legacy Creality
# ADXL345/LIS2DW wire protocol via adxl345_creality.py.
#
# Design constraints:
#   - resonance_tester validates `accel_chip` during klippy:connect,
#     which runs BEFORE klippy:mcu_identified. So we cannot wait for
#     the MCU to come up before substituting our chip object.
#   - resonance_tester checks for the start_internal_client() method,
#     so the proxy itself must expose it (lazily instantiating the
#     real chip on first use is fine because resonance_tester only
#     calls start_internal_client() during SHAPER_CALIBRATE, well
#     after the MCU is ready).
#
# Strategy: the proxy IS the chip from resonance_tester's point of
# view. It exposes start_internal_client() / read_reg() / set_reg()
# and forwards them to a lazily-created adxl345_creality.ADXL345
# (or LIS2DW) instance.

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
        # unused parameters (we forward them lazily).
        for option in config.fileconfig.options(self.config.get_name()):
            try:
                config.get(option)
            except Exception:
                pass

        self.accel_use_chip = config.get('accel_use_chip', 'adxl345')
        self.cs_pin = config.get('%s_cs_pin' % (self.accel_use_chip,))
        self.cs_pin_mcu_name = self.cs_pin.split(':')[0]

        # Lazily instantiated on first use (must be after MCU connect).
        self._chip = None

        # Register the standard ACCELEROMETER_* G-code commands now,
        # so they're available at boot. They internally call
        # start_internal_client() which triggers lazy init.
        from . import adxl345 as _mainline_adxl345
        _mainline_adxl345.AccelCommandHelper(config, self)

        # Force chip instantiation during klippy:connect — this is the
        # narrow window where:
        #   * printer.objects is fully populated (resonance_tester has
        #     already validated us as a chip)
        #   * MCUs are connected but NOT yet finalized
        # Inside _start_measurements / register_response calls (which
        # add_config_cmd needs) this is exactly the right phase.
        self.printer.register_event_handler(
            "klippy:connect", self._handle_connect)

    def _handle_connect(self):
        # Touch _get_chip() to force adxl345_creality.ADXL345 init,
        # which will register the MCU config commands at the right time.
        try:
            self._get_chip()
        except Exception:
            logging.exception("accel_chip_proxy: _handle_connect failed")
            raise

    # ─── Lazy chip instantiation ──────────────────────────────────
    def _get_chip(self):
        if self._chip is not None:
            return self._chip

        # Look up the nozzle MCU to verify its data dictionary
        # actually supports the chip we expect.
        mcu = self.printer.lookup_object('mcu ' + self.cs_pin_mcu_name)
        commands = mcu._serial.get_msgparser().messages_by_name

        # Try the configured chip first, swap if not supported
        chosen = self.accel_use_chip
        if chosen == 'adxl345' and 'config_adxl345' not in commands:
            if 'config_lis2dw' in commands:
                logging.info(
                    "accel_chip_proxy: 'config_adxl345' not in MCU '%s', "
                    "falling back to lis2dw",
                    self.cs_pin_mcu_name)
                chosen = 'lis2dw'
        elif chosen == 'lis2dw' and 'config_lis2dw' not in commands:
            if 'config_adxl345' in commands:
                logging.info(
                    "accel_chip_proxy: 'config_lis2dw' not in MCU '%s', "
                    "falling back to adxl345",
                    self.cs_pin_mcu_name)
                chosen = 'adxl345'

        if (chosen == 'adxl345' and 'config_adxl345' not in commands) or \
           (chosen == 'lis2dw' and 'config_lis2dw' not in commands):
            raise self.printer.command_error(
                "accel_chip_proxy: MCU '%s' does not support config_%s"
                % (self.cs_pin_mcu_name, chosen))

        from . import adxl345_creality
        wrapped_config = _ConfigWrapperProxy(self.config, chosen)
        if chosen == 'adxl345':
            logging.info("accel_chip_proxy: instantiating ADXL345")
            self._chip = adxl345_creality.ADXL345(wrapped_config)
        else:
            logging.info("accel_chip_proxy: instantiating LIS2DW")
            self._chip = adxl345_creality.LIS2DW(wrapped_config)
        return self._chip

    # ─── Forwarded API (everything resonance_tester / shaper /
    # ─── ACCELEROMETER_* commands need) ────────────────────────────
    def start_internal_client(self):
        return self._get_chip().start_internal_client()

    def read_reg(self, reg):
        return self._get_chip().read_reg(reg)

    def set_reg(self, reg, val, minclock=0):
        return self._get_chip().set_reg(reg, val, minclock=minclock)


def load_config(config):
    return AccelChipProxy(config)


def load_config_prefix(config):
    return AccelChipProxy(config)
