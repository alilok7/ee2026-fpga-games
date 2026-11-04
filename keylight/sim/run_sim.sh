#!/usr/bin/env bash
# run_sim.sh - compile and run one self-checking testbench with Vivado xsim.
#   bash sim/run_sim.sh tb_input_conditioner       (one testbench)
#   bash sim/run_sim.sh all                        (every sim/*/tb_*.v)
# Each testbench prints "PASS" or "FAIL" lines and ends with $finish.
# Data files (data/*.mem) are copied next to the simulation so $readmemh finds them.
set -u
VIV=${VIVADO_BIN:-/c/AMDDesignTools/2025.2/Vivado/bin}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

run_one() {
    local tb=$1
    local file
    file=$(find "$ROOT/sim" -name "$tb.v" | head -1)
    [ -z "$file" ] && { echo "no testbench $tb"; return 1; }
    local run="$ROOT/sim/run/$tb"
    mkdir -p "$run" && cp "$ROOT"/data/*.mem "$run"/
    # The project path contains spaces, which xvlog.bat cannot handle, so
    # every path handed to the tools is relative to the run folder.
    local rel="../../.."
    local relfile="$rel/${file#$ROOT/}"
    ( cd "$run" &&
      "$VIV/xvlog.bat" -i "$rel/rtl/top" -i "$rel/rtl/d_ui_learn" \
          $(cd "$run" && find "$rel/rtl" -name '*.v') "$relfile" > compile.txt 2>&1 &&
      "$VIV/xelab.bat" -debug off -relax "$tb" -s "${tb}_sim" > elab.txt 2>&1 &&
      "$VIV/xsim.bat" "${tb}_sim" -R > sim.txt 2>&1 )
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[$tb] build/run error, see sim/run/$tb/*.txt"
        grep -h -E "ERROR" "$run"/*.txt | head -10
        return 1
    fi
    grep -E "PASS|FAIL|ERROR" "$run/sim.txt"
    grep -q "FAIL" "$run/sim.txt" && return 1 || return 0
}

if [ "${1:-all}" = "all" ]; then
    status=0
    for f in $(find "$ROOT/sim" -name 'tb_*.v' | sort); do
        run_one "$(basename "$f" .v)" || status=1
    done
    exit $status
else
    run_one "$1"
fi
