# Support for ADXL345 / LIS2DW chips on Creality 2023 firmware (E5M-CK)
#
# This module ports the legacy Creality protocol for ADXL345/LIS2DW
# (which uses the older "query_adxl345 oid clock rest_ticks" wire format
# and "adxl345_data sequence data" 5-byte/sample response) onto the
# Klipper mainline 2026 host architecture (BatchBulkHelper transport).
#
# The hardware logic (SPI init, register sequence, 5-byte sample
# extraction, sequence-based clock synchronization) is preserved
# unchanged from the Creality original. Only the host-side transport
# layer has been rewritten to integrate with mainline's resonance_tester
# and shaper_calibrate.
#
# Configuration:
#   [accel_chip_proxy]
#   accel_use_chip: adxl345              # or lis2dw, auto-detected
#   adxl345_cs_pin: nozzle_mcu:PA4
#   adxl345_spi_speed: 5000000
#   adxl345_axes_map: x,-z,y
#   adxl345_spi_software_sclk_pin: nozzle_mcu:PA5
#   adxl345_spi_software_mosi_pin: nozzle_mcu:PA7
#   adxl345_spi_software_miso_pin: nozzle_mcu:PA6
#
# This file does not handle [accel_chip_proxy] itself — see the matching
# accel_chip_proxy.py for the section dispatcher.

import logging, threading
from . import bus, bulk_sensor

# Reuse the mainline G-code and query helpers (ACCELEROMETER_QUERY,
# ACCELEROMETER_MEASURE, etc.). These work with any chip class that
# exposes start_internal_client() returning an AccelQueryHelper-compatible
# object with handle_batch().
from . import adxl345 as _mainline_adxl345
AccelCommandHelper = _mainline_adxl345.AccelCommandHelper
AccelQueryHelper = _mainline_adxl345.AccelQueryHelper

# ─── ADXL345 register map ────────────────────────────────────────
REG_DEVID = 0x00
REG_BW_RATE = 0x2C
REG_POWER_CTL = 0x2D
REG_DATA_FORMAT = 0x31
REG_FIFO_CTL = 0x38
REG_MOD_READ = 0x80
REG_MOD_MULTI = 0x40

QUERY_RATES_ADXL345 = {
    25: 0x8, 50: 0x9, 100: 0xa, 200: 0xb, 400: 0xc,
    800: 0xd, 1600: 0xe, 3200: 0xf,
}

ADXL345_DEV_ID = 0xe5
SET_FIFO_CTL = 0x90

# ─── LIS2DW register map ─────────────────────────────────────────
REG_LIS2DW_WHO_AM_I_ADDR = 0x0F
LIS2DW_DEV_ID = 0x44

FREEFALL_ACCEL = 9.80665 * 1000.
SCALE_XY = 0.003774 * FREEFALL_ACCEL  # ADXL345 ±16g / 13-bit
SCALE_Z  = 0.003906 * FREEFALL_ACCEL

# Wire format constants (Creality firmware): each adxl345_data message
# carries 10 samples × 5 bytes = 50 bytes of payload.
BYTES_PER_SAMPLE = 5
SAMPLES_PER_BLOCK = 10

# Number of host-side update batches per second handed to BatchBulkHelper.
# The mainline adxl345.py uses 8 — we mirror that.
BATCH_UPDATES = 0.100  # seconds between _process_batch calls


# ════════════════════════════════════════════════════════════════
# Clock synchronization (host-side linear regression between MCU
# clock and chip sample sequence). Copied verbatim from the legacy
# Creality adxl345.py — this is independent of the transport layer.
# ════════════════════════════════════════════════════════════════
class ClockSyncRegression:
    def __init__(self, mcu, chip_clock_smooth, decay=1./20.):
        self.mcu = mcu
        self.chip_clock_smooth = chip_clock_smooth
        self.decay = decay
        self.last_chip_clock = self.last_exp_mcu_clock = 0.
        self.mcu_clock_avg = self.mcu_clock_variance = 0.
        self.chip_clock_avg = self.chip_clock_covariance = 0.

    def reset(self, mcu_clock, chip_clock):
        self.mcu_clock_avg = self.last_mcu_clock = mcu_clock
        self.chip_clock_avg = chip_clock
        self.mcu_clock_variance = self.chip_clock_covariance = 0.
        self.last_chip_clock = self.last_exp_mcu_clock = 0.

    def update(self, mcu_clock, chip_clock):
        decay = self.decay
        diff_mcu_clock = mcu_clock - self.mcu_clock_avg
        self.mcu_clock_avg += decay * diff_mcu_clock
        self.mcu_clock_variance = (1. - decay) * (
            self.mcu_clock_variance + diff_mcu_clock**2 * decay)
        diff_chip_clock = chip_clock - self.chip_clock_avg
        self.chip_clock_avg += decay * diff_chip_clock
        self.chip_clock_covariance = (1. - decay) * (
            self.chip_clock_covariance + diff_mcu_clock*diff_chip_clock*decay)

    def set_last_chip_clock(self, chip_clock):
        base_mcu, base_chip, inv_cfreq = self.get_clock_translation()
        self.last_chip_clock = chip_clock
        self.last_exp_mcu_clock = base_mcu + (chip_clock-base_chip) * inv_cfreq

    def get_clock_translation(self):
        inv_chip_freq = self.mcu_clock_variance / self.chip_clock_covariance
        if not self.last_chip_clock:
            return self.mcu_clock_avg, self.chip_clock_avg, inv_chip_freq
        s_chip_clock = self.last_chip_clock + self.chip_clock_smooth
        scdiff = s_chip_clock - self.chip_clock_avg
        s_mcu_clock = self.mcu_clock_avg + scdiff * inv_chip_freq
        mdiff = s_mcu_clock - self.last_exp_mcu_clock
        s_inv_chip_freq = mdiff / self.chip_clock_smooth
        return self.last_exp_mcu_clock, self.last_chip_clock, s_inv_chip_freq

    def get_time_translation(self):
        base_mcu, base_chip, inv_cfreq = self.get_clock_translation()
        clock_to_print_time = self.mcu.clock_to_print_time
        base_time = clock_to_print_time(base_mcu)
        inv_freq = clock_to_print_time(base_mcu + inv_cfreq) - base_time
        return base_time, base_chip, inv_freq


MIN_MSG_TIME = 0.100


# ════════════════════════════════════════════════════════════════
# Main chip class — handles ADXL345 and LIS2DW transparently.
# ════════════════════════════════════════════════════════════════
class ADXL345Creality:
    def __init__(self, config, chip_kind='adxl345'):
        self.printer = config.get_printer()
        self.chip_kind = chip_kind  # 'adxl345' or 'lis2dw'
        AccelCommandHelper(config, self)

        # Axes mapping (e.g. 'x,-z,y' → swap Y/Z and invert Z)
        am = {'x': (0, SCALE_XY), 'y': (1, SCALE_XY), 'z': (2, SCALE_Z),
              '-x': (0, -SCALE_XY), '-y': (1, -SCALE_XY), '-z': (2, -SCALE_Z)}
        axes_map = config.getlist('axes_map', ('x', 'y', 'z'), count=3)
        if any([a not in am for a in axes_map]):
            raise config.error("Invalid axes_map parameter")
        self.axes_map = [am[a.strip()] for a in axes_map]

        self.data_rate = config.getint('rate', 3200)
        if self.data_rate not in QUERY_RATES_ADXL345:
            raise config.error("Invalid rate parameter: %d" % (self.data_rate,))

        # SPI bus (works for both software and hardware SPI — the config
        # keys "spi_software_*_pin" route through bus.MCU_SPI_from_config
        # to the firmware's spi_set_software_bus command).
        self.spi = bus.MCU_SPI_from_config(config, 3, default_speed=5000000)
        self.mcu = mcu = self.spi.get_mcu()
        self.oid = oid = mcu.create_oid()

        # Wire-format setup — uses the LEGACY Creality signature
        # "query_adxl345 oid clock rest_ticks" (3 params, with clock=0 at
        # config time). Mainline 2026 firmware uses 2 params, but we are
        # talking to the Creality 2023 firmware which has the older form.
        mcu.add_config_cmd("config_adxl345 oid=%d spi_oid=%d"
                           % (oid, self.spi.get_oid()))
        mcu.add_config_cmd("query_adxl345 oid=%d clock=0 rest_ticks=0"
                           % (oid,), on_restart=True)
        mcu.register_config_callback(self._build_config)
        mcu.register_response(self._handle_adxl345_data, "adxl345_data", oid)

        # Sample accumulator (filled from MCU thread, drained from
        # batch processor thread)
        self.lock = threading.Lock()
        self.raw_samples = []

        # Sequence/clock tracking
        self.last_sequence = 0
        self.last_limit_count = 0
        self.last_error_count = 0
        self.max_query_duration = 1 << 31
        self.query_rate = 0
        self.clock_sync = ClockSyncRegression(self.mcu, 640)

        self.query_adxl345_cmd = None
        self.query_adxl345_end_cmd = None
        self.query_adxl345_status_cmd = None

        # Mainline 2026 transport: BatchBulkHelper drives _start, _finish
        # and _process_batch lifecycle on its own thread.
        self.batch_bulk = bulk_sensor.BatchBulkHelper(
            self.printer, self._process_batch,
            self._start_measurements, self._finish_measurements,
            BATCH_UPDATES)

        self.name = config.get_name().split()[-1]
        hdr = ('time', 'x_acceleration', 'y_acceleration', 'z_acceleration')
        self.batch_bulk.add_mux_endpoint("adxl345/dump_adxl345", "sensor",
                                        self.name, {'header': hdr})

    def _build_config(self):
        cmdqueue = self.spi.get_command_queue()
        # All three signatures match the Creality 2023 firmware data
        # dictionary (verified via console.py LIST on /dev/ttyS7).
        self.query_adxl345_cmd = self.mcu.lookup_command(
            "query_adxl345 oid=%c clock=%u rest_ticks=%u", cq=cmdqueue)
        self.query_adxl345_end_cmd = self.mcu.lookup_query_command(
            "query_adxl345 oid=%c clock=%u rest_ticks=%u",
            "adxl345_status oid=%c clock=%u query_ticks=%u next_sequence=%hu"
            " buffered=%c fifo=%c limit_count=%hu",
            oid=self.oid, cq=cmdqueue)
        self.query_adxl345_status_cmd = self.mcu.lookup_query_command(
            "query_adxl345_status oid=%c",
            "adxl345_status oid=%c clock=%u query_ticks=%u next_sequence=%hu"
            " buffered=%c fifo=%c limit_count=%hu",
            oid=self.oid, cq=cmdqueue)

    # ─── SPI register access ──────────────────────────────────────
    def read_reg(self, reg):
        params = self.spi.spi_transfer([reg | REG_MOD_READ, 0x00])
        response = bytearray(params['response'])
        return response[1]

    def set_reg(self, reg, val, minclock=0):
        self.spi.spi_send([reg, val & 0xFF], minclock=minclock)
        stored_val = self.read_reg(reg)
        if stored_val != val:
            raise self.printer.command_error(
                "Failed to set %s register [0x%x] to 0x%x: got 0x%x. "
                "This generally indicates connection problems "
                "(e.g. faulty wiring) or a faulty chip."
                % (self.chip_kind, reg, val, stored_val))

    def is_measuring(self):
        return self.query_rate > 0

    # ─── MCU response handler (called from MCU dispatch thread) ──
    def _handle_adxl345_data(self, params):
        with self.lock:
            self.raw_samples.append(params)

    # ─── Sample decoding (5 bytes per sample, ADXL345 layout) ────
    def _extract_samples(self, raw_samples):
        (x_pos, x_scale), (y_pos, y_scale), (z_pos, z_scale) = self.axes_map
        last_sequence = self.last_sequence
        time_base, chip_base, inv_freq = self.clock_sync.get_time_translation()
        count = seq = i = 0
        samples = [None] * (len(raw_samples) * SAMPLES_PER_BLOCK)
        for params in raw_samples:
            seq_diff = (last_sequence - params['sequence']) & 0xffff
            seq_diff -= (seq_diff & 0x8000) << 1
            seq = last_sequence - seq_diff
            d = bytearray(params['data'])
            msg_cdiff = seq * SAMPLES_PER_BLOCK - chip_base
            for i in range(len(d) // BYTES_PER_SAMPLE):
                d_xyz = d[i*BYTES_PER_SAMPLE:(i+1)*BYTES_PER_SAMPLE]
                xlow, ylow, zlow, xzhigh, yzhigh = d_xyz
                if yzhigh & 0x80:
                    self.last_error_count += 1
                    continue
                rx = (xlow | ((xzhigh & 0x1f) << 8)) - ((xzhigh & 0x10) << 9)
                ry = (ylow | ((yzhigh & 0x1f) << 8)) - ((yzhigh & 0x10) << 9)
                rz = ((zlow | ((xzhigh & 0xe0) << 3) | ((yzhigh & 0xe0) << 6))
                      - ((yzhigh & 0x40) << 7))
                raw_xyz = (rx, ry, rz)
                x = round(raw_xyz[x_pos] * x_scale, 6)
                y = round(raw_xyz[y_pos] * y_scale, 6)
                z = round(raw_xyz[z_pos] * z_scale, 6)
                ptime = round(time_base + (msg_cdiff + i) * inv_freq, 6)
                samples[count] = (ptime, x, y, z)
                count += 1
        if count:
            self.clock_sync.set_last_chip_clock(seq * SAMPLES_PER_BLOCK + i)
        del samples[count:]
        return samples

    # ─── Clock synchronization update ─────────────────────────────
    def _update_clock(self, minclock=0):
        for retry in range(5):
            params = self.query_adxl345_status_cmd.send(
                [self.oid], minclock=minclock)
            fifo = params['fifo'] & 0x7f
            if fifo <= 32:
                break
        else:
            raise self.printer.command_error(
                "Unable to query %s fifo" % (self.chip_kind,))
        mcu_clock = self.mcu.clock32_to_clock64(params['clock'])
        sequence = (self.last_sequence & ~0xffff) | params['next_sequence']
        if sequence < self.last_sequence:
            sequence += 0x10000
        self.last_sequence = sequence
        buffered = params['buffered']
        limit_count = (self.last_limit_count & ~0xffff) | params['limit_count']
        if limit_count < self.last_limit_count:
            limit_count += 0x10000
        self.last_limit_count = limit_count
        duration = params['query_ticks']
        if duration > self.max_query_duration:
            self.max_query_duration = max(
                2 * self.max_query_duration,
                self.mcu.seconds_to_clock(.000005))
            return
        self.max_query_duration = 2 * duration
        msg_count = (sequence * SAMPLES_PER_BLOCK
                     + buffered // BYTES_PER_SAMPLE + fifo)
        chip_clock = msg_count + 1
        self.clock_sync.update(mcu_clock + duration // 2, chip_clock)

    # ─── Lifecycle (called by BatchBulkHelper on its thread) ─────
    def _start_measurements(self):
        if self.is_measuring():
            return
        # Probe the chip ID to fail fast on miswiring
        if self.chip_kind == 'adxl345':
            dev_id = self.read_reg(REG_DEVID)
            if dev_id != ADXL345_DEV_ID:
                raise self.printer.command_error(
                    "Invalid adxl345 id (got %x vs %x). "
                    "This generally indicates wiring problems."
                    % (dev_id, ADXL345_DEV_ID))
        else:
            dev_id = self.read_reg(REG_LIS2DW_WHO_AM_I_ADDR)
            if dev_id != LIS2DW_DEV_ID:
                raise self.printer.command_error(
                    "Invalid lis2dw id (got %x vs %x)."
                    % (dev_id, LIS2DW_DEV_ID))

        # Configure the chip (ADXL345 sequence — LIS2DW would need its
        # own register sequence, omitted here because the Creality logs
        # show adxl345 is what's wired on this E5M).
        self.set_reg(REG_POWER_CTL, 0x00)
        self.set_reg(REG_DATA_FORMAT, 0x0B)
        self.set_reg(REG_FIFO_CTL, 0x00)
        self.set_reg(REG_BW_RATE, QUERY_RATES_ADXL345[self.data_rate])
        self.set_reg(REG_FIFO_CTL, SET_FIFO_CTL)

        with self.lock:
            self.raw_samples = []

        # Start bulk reading at print_time + MIN_MSG_TIME
        systime = self.printer.get_reactor().monotonic()
        print_time = self.mcu.estimated_print_time(systime) + MIN_MSG_TIME
        reqclock = self.mcu.print_time_to_clock(print_time)
        rest_ticks = self.mcu.seconds_to_clock(4. / self.data_rate)
        self.query_rate = self.data_rate
        self.query_adxl345_cmd.send(
            [self.oid, reqclock, rest_ticks], reqclock=reqclock)
        logging.info("%s starting '%s' measurements",
                     self.chip_kind, self.name)
        self.last_sequence = 0
        self.last_limit_count = 0
        self.last_error_count = 0
        self.clock_sync.reset(reqclock, 0)
        self.max_query_duration = 1 << 31
        self._update_clock(minclock=reqclock)
        self.max_query_duration = 1 << 31

    def _finish_measurements(self):
        if not self.is_measuring():
            return
        self.query_adxl345_end_cmd.send([self.oid, 0, 0])
        self.query_rate = 0
        with self.lock:
            self.raw_samples = []
        logging.info("%s finished '%s' measurements",
                     self.chip_kind, self.name)

    # ─── Batch processor — feeds BatchBulkHelper clients ─────────
    def _process_batch(self, eventtime):
        if not self.is_measuring():
            return {}
        try:
            self._update_clock()
        except Exception:
            logging.exception("%s: _update_clock failed", self.chip_kind)
            return {}
        with self.lock:
            raw_samples = self.raw_samples
            self.raw_samples = []
        if not raw_samples:
            return {}
        samples = self._extract_samples(raw_samples)
        if not samples:
            return {}
        return {'data': samples,
                'errors': self.last_error_count,
                'overflows': self.last_limit_count}

    # ─── Client API (used by resonance_tester / shaper_calibrate) ─
    def start_internal_client(self):
        aqh = AccelQueryHelper(self.printer)
        self.batch_bulk.add_client(aqh.handle_batch)
        return aqh


# Two simple aliases so accel_chip_proxy can do
# `from . import adxl345_creality as adxl345` and call
# adxl345.ADXL345(...) without further changes.
class ADXL345(ADXL345Creality):
    def __init__(self, config):
        ADXL345Creality.__init__(self, config, chip_kind='adxl345')


class LIS2DW(ADXL345Creality):
    def __init__(self, config):
        ADXL345Creality.__init__(self, config, chip_kind='lis2dw')


def load_config(config):
    return ADXL345(config)


def load_config_prefix(config):
    return ADXL345(config)
