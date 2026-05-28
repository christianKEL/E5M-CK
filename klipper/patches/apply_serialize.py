#!/usr/bin/env python3
"""Apply the steppersync serialize patch by surgical text substitution.

Idempotent: errors out if the file already contains the patched marker
or if the original parallel pattern isn't found.
"""
import sys
import pathlib

PATH = pathlib.Path("/workspaces/klipper/klippy/chelper/steppersync.c")

ORIGINAL = """    // Start step generation threads
    list_for_each_entry(ss, &ssm->ss_list, ssm_node) {
        uint64_t flush_clock = clock_from_time(&ss->ce, flush_time);
        uint64_t clear_clock = clock_from_time(&ss->ce, clear_history_time);
        struct syncemitter *se;
        list_for_each_entry(se, &ss->se_list, ss_node) {
            se_start_gen_steps(se, gen_steps_time, flush_clock, clear_clock);
        }
    }
    // Wait for step generation threads to complete
    struct syncemitter *failed_se = NULL;
    list_for_each_entry(ss, &ssm->ss_list, ssm_node) {
        struct syncemitter *se;
        list_for_each_entry(se, &ss->se_list, ss_node) {
            int32_t ret = se_finalize_gen_steps(se);
            if (ret)
                failed_se = se;
        }
        if (failed_se)
            continue;
        uint64_t flush_clock = clock_from_time(&ss->ce, flush_time);
        steppersync_flush(ss, flush_clock);
    }
"""

REPLACEMENT = """    // E5M-CK patch: serialize gen_steps per syncemitter so that sibling
    // steppers sharing a trapq (e.g. coreXY X/Y) never run
    // itersolve_generate_steps() concurrently. See
    // klipper/patches/0001-steppersync-serialize-gen-steps-per-steppersync.patch
    struct syncemitter *failed_se = NULL;
    list_for_each_entry(ss, &ssm->ss_list, ssm_node) {
        uint64_t flush_clock = clock_from_time(&ss->ce, flush_time);
        uint64_t clear_clock = clock_from_time(&ss->ce, clear_history_time);
        struct syncemitter *se;
        list_for_each_entry(se, &ss->se_list, ss_node) {
            se_start_gen_steps(se, gen_steps_time, flush_clock, clear_clock);
            int32_t ret = se_finalize_gen_steps(se);
            if (ret)
                failed_se = se;
        }
        if (failed_se)
            continue;
        steppersync_flush(ss, flush_clock);
    }
"""

src = PATH.read_text()
if "E5M-CK patch: serialize gen_steps" in src:
    print("ALREADY-PATCHED", file=sys.stderr)
    sys.exit(2)
if ORIGINAL not in src:
    print("ORIGINAL-NOT-FOUND", file=sys.stderr)
    sys.exit(3)
new = src.replace(ORIGINAL, REPLACEMENT, 1)
if new == src:
    print("REPLACE-FAILED", file=sys.stderr)
    sys.exit(4)
PATH.write_text(new)
print("PATCHED")
