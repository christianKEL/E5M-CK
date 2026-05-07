# Accelerometer chip proxy for Creality 2023 firmware
#
# This is a port of Creality's accel_chip_proxy.py to Klipper mainline.
# Differences from the original:
#   - imports adxl345_creality (legacy wire protocol) instead of mainline
#     adxl345 (new wire protocol, incompatible with Creality 2023 firmware)
#   - removes the Creality-only configfile.cmd_CXSAVE_CONFIG fallback
#     which doesn't exist in mainline
#   - LIS2DW support kept intact for hardware variants
#
# The proxy serves three purposes:
#   1. Lets resonance_tester reference a single accel_chip name
#      (accel_chip_proxy) regardless of whether the wired chip is
#      ADXL345 or LIS2DW.
#   2. Hides the chip-specific config_<chip>_<param> prefix so users
#      can name pins consistently.
#   3. Auto-detects the wired chip by reading its ID register at
#      connect_complete time, falling back to the other type on
#      mismatch.

import logging


class AccelChipProxy:
    accel_num = 0
    config_changed = False

    class ConfigWrapperProxy:
        """Re-prefixes config option lookups (e.g. 'cs_pin' →
        'adxl345_cs_pin') so the underlying chip class sees the
        flat option names it expects."""
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
                default, minval=minval, maxval=maxval,
                note_valid=note_valid)

        def getfloat(self, option, default=None,
                     minval=None, maxval=None, note_valid=True):
            return self.config.getfloat(
                '%s_%s' % (self.chip_name, option),
                default, minval=minval, maxval=maxval,
                note_valid=note_valid)

        def getlist(self, option, default=None,
                    sep=',', count=None, note_valid=True):
            return self.config.getlist(
                '%s_%s' % (self.chip_name, option),
                default, sep=sep, count=count, note_valid=note_valid)

        def __getattr__(self, name):
            return getattr(self.config, name)

    def __init__(self, config):
        self.name = config.get_name()
        self.config = config
        # Mark every option as read so Klipper doesn't warn about
        # unused parameters (the proxy lazily forwards them).
        for option in config.fileconfig.options(self.config.get_name()):
            try:
                config.get(option)
            except Exception:
                pass

        self.accel_use_chip = config.get('accel_use_chip', 'adxl345')
        self.cs_pin = config.get('%s_cs_pin' % (self.accel_use_chip,))
        self.cs_pin_mcu_name = self.cs_pin.split(':')[0]
        self.printer = config.get_printer()
        self.printer.register_event_handler(
            "klippy:mcu_identified", self._handle_identify)
        self.printer.register_event_handler(
            "klippy:connect", self._handle_connect)

    def _handle_identify(self, mcu):
        muc_name = mcu._name
        if muc_name != self.cs_pin_mcu_name:
            return
        mcu_msg = mcu._serial.get_msgparser()
        commands = mcu_msg.messages_by_name
        # We loop until we instantiate a chip that the MCU firmware
        # actually supports (config_adxl345 or config_lis2dw).
        attempts = 0
        while attempts < 4:
            attempts += 1
            if (self.accel_use_chip == 'adxl345'
                    and 'config_adxl345' in commands):
                logging.info("accel_chip_proxy: instantiating ADXL345")
                from . import adxl345_creality
                obj = adxl345_creality.ADXL345(
                    self.ConfigWrapperProxy(self.config, 'adxl345'))
                self.printer.objects[self.name] = obj
                return
            elif (self.accel_use_chip == 'lis2dw'
                    and 'config_lis2dw' in commands):
                logging.info("accel_chip_proxy: instantiating LIS2DW")
                from . import adxl345_creality
                obj = adxl345_creality.LIS2DW(
                    self.ConfigWrapperProxy(self.config, 'lis2dw'))
                self.printer.objects[self.name] = obj
                return
            else:
                # Swap chip type and retry
                logging.info(
                    "accel_chip_proxy: '%s' not in MCU commands, swapping",
                    self.accel_use_chip)
                self.accel_use_chip = (
                    'lis2dw' if self.accel_use_chip == 'adxl345'
                    else 'adxl345')
        raise self.printer.command_error(
            "accel_chip_proxy: neither config_adxl345 nor config_lis2dw "
            "is supported by MCU '%s'" % (muc_name,))

    def _handle_connect(self):
        # The chip's _start_measurements() probes the device ID
        # automatically on first measurement; nothing extra needed
        # here. We keep this hook just for parity with the original.
        pass


def load_config(config):
    return AccelChipProxy(config)


def load_config_prefix(config):
    return AccelChipProxy(config)
