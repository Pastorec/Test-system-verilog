#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Run the REG_VDDPIX_CORE regression under Icarus Verilog.
#
# Icarus 12 does not implement user-defined nettypes, so it cannot compile
# `nettype real real_net`. This script builds a throw-away copy of the sources
# with real_net rewritten to a plain `real` and the package import dropped.
# Nothing in rtl/ or tb/ is modified.
#
# The substitution is behaviourally faithful for this testbench because every
# analog net here has exactly one driver, so the nettype's resolution function
# is never exercised.
#
# On Xcelium / VCS / Questa, compile rtl/ and tb/ directly -- no substitution.
#
#   usage: sim/run_iverilog.sh [--orig | --orig-core] [--dump]
#     --orig       build the unmodified original sources from orig/, to
#                  reproduce the VDDPIX-stays-low failure
#     --orig-core  fixed stimulus driving the ORIGINAL model, to show that
#                  fixing the stimulus alone is not enough: the model's
#                  always-block still drops SEL changes
#     --race       the real failure, against the FIXED model (both orderings
#                  settle at 0.870 V)
#     --race-orig  the real failure, against the ORIGINAL model: identical
#                  benches diverge to 0.870 V and 0.000 V on a t=0 race
#     --dump       write a VCD
# -----------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${ROOT}/sim/build"
MODE=fixed
PLUSARGS=()

for arg in "$@"; do
  case "$arg" in
    --orig)      MODE=orig ;;
    --orig-core) MODE=orig-core ;;
    --race)      MODE=race ;;
    --race-orig) MODE=race-orig ;;
    --dump)      PLUSARGS+=("+dump") ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

command -v iverilog >/dev/null || { echo "iverilog not found on PATH" >&2; exit 127; }

rm -rf "$BUILD"
mkdir -p "$BUILD"

case "$MODE" in
  orig)
    SRC=( "${ROOT}/orig/REG_VDDPIX_CORE.orig.sv" \
          "${ROOT}/orig/stim_REG_VDDPIX_TOP.orig.sv" \
          "${ROOT}/orig/tb_REG_VDDPIX_orig.sv" )
    TOP=tb_REG_VDDPIX_orig
    echo "=== ORIGINAL model + ORIGINAL stimulus -- expect VDDPIX stuck at 0 V ==="
    ;;
  orig-core)
    SRC=( "${ROOT}/orig/REG_VDDPIX_CORE.orig.sv" \
          "${ROOT}/tb/stim_REG_VDDPIX_TOP.sv" \
          "${ROOT}/tb/tb_REG_VDDPIX_CORE.sv" )
    TOP=tb_REG_VDDPIX_CORE
    echo "=== ORIGINAL model + FIXED stimulus -- expect dropped SEL changes ==="
    ;;
  race)
    SRC=( "${ROOT}/rtl/REG_VDDPIX_CORE.sv" \
          "${ROOT}/orig/stim_REG_VDDPIX_TOP.orig.sv" \
          "${ROOT}/tb/tb_REG_VDDPIX_race.sv" )
    TOP=tb_REG_VDDPIX_race
    echo "=== t=0 race bench + FIXED model -- expect both orderings at 0.870 V ==="
    ;;
  race-orig)
    SRC=( "${ROOT}/orig/REG_VDDPIX_CORE.orig.sv" \
          "${ROOT}/orig/stim_REG_VDDPIX_TOP.orig.sv" \
          "${ROOT}/tb/tb_REG_VDDPIX_race.sv" )
    TOP=tb_REG_VDDPIX_race
    echo "=== t=0 race bench + ORIGINAL model -- expect 0.870 V vs 0.000 V ==="
    ;;
  *)
    SRC=( "${ROOT}/rtl/REG_VDDPIX_CORE.sv" \
          "${ROOT}/tb/stim_REG_VDDPIX_TOP.sv" \
          "${ROOT}/tb/tb_REG_VDDPIX_CORE.sv" )
    TOP=tb_REG_VDDPIX_CORE
    echo "=== FIXED model + FIXED stimulus ==="
    ;;
esac

# Rewrite real_net -> real and drop the elec_net_pkg import for Icarus.
for f in "${SRC[@]}"; do
  sed -e 's/\breal_net\b/real/g' \
      -e 's/^\([[:space:]]*\)import[[:space:]]\+elec_net_pkg::\*;/\1\/\/ import elec_net_pkg::*;  (dropped for iverilog)/' \
      "$f" > "${BUILD}/$(basename "$f")"
done

iverilog -g2012 -gsupported-assertions \
         -o "${BUILD}/sim.vvp" -s "$TOP" \
         "${BUILD}"/*.sv

cd "$BUILD"
if [ ${#PLUSARGS[@]} -gt 0 ]; then
  vvp sim.vvp "${PLUSARGS[@]}"
else
  vvp sim.vvp
fi
