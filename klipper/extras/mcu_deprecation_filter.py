# mcu_deprecation_filter — silence specific deprecated_mcu_code warnings.
#
# Purpose
# -------
# Klipper master emits a Fluidd-visible deprecation warning every time a
# stepper, bus, or sensor module finds that an MCU's firmware is missing
# a "modern" build flag. The warning is hardcoded in klippy/configfile.py
# (`deprecate_mcu_code`); there is no native config-side mechanism to
# acknowledge a known-deprecated MCU as intentionally kept.
#
# On the Ender 5 Max we run host Klipper at master (for BTT Eddy tap
# support) against the stock Creality MCU firmware (mainboard + nozzle
# board). The stock firmware predates several `STEPPER_*` constants the
# master host now expects. We CANNOT recompile/reflash those MCUs because
# doing so would break our `factory_reset` rollback path (the stock
# firmware is a precondition for restoring the original Creality
# experience). The missing features are optimizations, not regressions:
# steppers, heaters, fans, GPIO all keep working unchanged.
#
# This module monkey-patches `configfile.deprecate_mcu_code` at load
# time so that any (mcu, feature) pair with `feature` in our configured
# allowlist is silently dropped. All other deprecation warnings
# (including any feature we did NOT explicitly list) continue to fire
# normally.
#
# Usage
# -----
# In printer.cfg, BEFORE any [stepper_*]/[*_mcu]/[probe_*] section that
# may trigger a warning at config time:
#
#   [mcu_deprecation_filter]
#   features: STEPPER_STEP_BOTH_EDGE
#   reason: stock Creality MCU firmware preserved for factory_reset rollback
#
# `features` is a comma-separated list of feature names exactly as
# Klipper prints them (case-sensitive). `reason` is required and is
# logged once at startup, so that anyone reading klippy.log months from
# now sees WHY this filter exists.
#
# Suppressing nothing (no `features` value or an empty string) is a
# no-op — the filter is installed but lets every warning through.
#
# Rollback
# --------
# Remove the `[mcu_deprecation_filter]` section from printer.cfg and
# restart Klipper. Original behavior is restored (warnings re-appear).
#
# Source-code references this code wraps:
#   klippy/configfile.py  ConfigWrapper / PrinterConfig.deprecate_mcu_code
#   klippy/stepper.py:105 (STEPPER_STEP_BOTH_EDGE call site)

import logging


class McuDeprecationFilter:
    def __init__(self, config):
        printer = config.get_printer()

        # Parse the comma-separated allowlist of features to suppress.
        raw_features = config.get('features', '').strip()
        self._suppressed = set()
        for token in raw_features.split(','):
            token = token.strip()
            if token:
                self._suppressed.add(token)

        # `reason` is required to force the user to justify each
        # suppression in writing. We default to a placeholder rather than
        # raising, so a half-configured printer still boots — but the
        # placeholder is loud in the log.
        reason = config.get('reason', '').strip()
        if not reason:
            reason = ('<NO REASON GIVEN — please add a reason: ... line '
                      'to [mcu_deprecation_filter] in printer.cfg>')

        logging.info(
            "mcu_deprecation_filter: suppressing features=[%s] (reason: %s)",
            ', '.join(sorted(self._suppressed)) if self._suppressed
            else '<empty allowlist — passthrough>',
            reason)

        # Monkey-patch configfile.deprecate_mcu_code.
        # The configfile object exists by the time our [mcu_deprecation_filter]
        # section is processed (configfile is a core Klipper object loaded
        # at startup, before any user-defined sections).
        self._configfile = printer.lookup_object('configfile')
        self._orig_deprecate_mcu_code = self._configfile.deprecate_mcu_code
        self._configfile.deprecate_mcu_code = self._filtered_deprecate_mcu_code

    def _filtered_deprecate_mcu_code(self, mcu, feature, msg=None):
        if feature in self._suppressed:
            # Silently drop. The MCU's missing feature flag is intentional.
            logging.debug(
                "mcu_deprecation_filter: silently dropped warning "
                "for MCU '%s' feature '%s'",
                mcu.get_name(), feature)
            return
        # Anything not in the allowlist passes through to the real handler.
        return self._orig_deprecate_mcu_code(mcu, feature, msg)


def load_config(config):
    return McuDeprecationFilter(config)
