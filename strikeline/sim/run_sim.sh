#!/usr/bin/env bash
# run_sim.sh - compile and run StrikeLine's self-checking testbenches with Vivado xsim.
#   bash sim/run_sim.sh tb_gesture      (one testbench)
#   bash sim/run_sim.sh all             (every sim/*/tb_*.v)
# Each testbench prints PASS / FAIL lines and ends with $finish.
# The sources are copied to a local work folder first ($TEMP/strikeline_sim):
# the project folder has spaces in its path (xvlog.bat cannot handle them)
# and is synced by OneDrive (which locks files while the simulator writes).
# Logs are copied back to sim/run/<tb>/.
set -u
VIV=${VIVADO_BIN:-/c/AMDDesignTools/2025.2/Vivado/bin}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${SIM_WORK:-$(cygpath -u "${TEMP:-/tmp}" 2>/dev/null || echo /tmp)/strikeline_sim}

sync_src() {
    rm -rf "$WORK/src" && mkdir -p "$WORK/src"
    cp -r "$ROOT/rtl" "$ROOT/sim" "$ROOT/data" "$WORK/src/"
    rm -rf "$WORK/src/sim/run"
}

run_one() {
    local tb=$1
    local file
    file=$(cd "$WORK/src" && find sim -name "$tb.v" | head -1)
    [ -z "$file" ] && { echo "no testbench $tb"; return 1; }
    local run="$WORK/run/$tb"
    rm -rf "$run" && mkdir -p "$run" && cp "$WORK"/src/data/*.mem "$run"/
    local rel="../../src"
    local extra=""
    if grep -q "My_Top_Module" "$WORK/src/$file"; then        # needs the VHDL mouse files
        ( cd "$run" && "$VIV/xvhdl.bat" "$rel/rtl/provided/Ps2Interface.vhd" \
              "$rel/rtl/provided/Mouse_Control.vhd" > vhdl.txt 2>&1 ) || {
            echo "[$tb] VHDL compile error"; grep ERROR "$run/vhdl.txt" | head; return 1; }
        extra="-L unisims_ver glbl"
        cp "$VIV/../data/verilog/src/glbl.v" "$run/" 2>/dev/null
    fi
    ( cd "$run" &&
      "$VIV/xvlog.bat" -d SIM -i "$rel/rtl/top" -i "$rel/rtl/d_game_ui" \
          $(find "$rel/rtl" -name '*.v') $(find "$rel/sim" -name '*.v' ! -name 'tb_*') "$rel/$file" $( [ -f glbl.v ] && echo glbl.v ) > compile.txt 2>&1 &&
      "$VIV/xelab.bat" -debug off -relax $extra "$tb" -s "${tb}_sim" > elab.txt 2>&1 &&
      "$VIV/xsim.bat" "${tb}_sim" -R > sim.txt 2>&1 )
    local rc=$?
    mkdir -p "$ROOT/sim/run/$tb" && cp "$run"/*.txt "$ROOT/sim/run/$tb/" 2>/dev/null
    if [ $rc -ne 0 ]; then
        echo "[$tb] build/run error, see sim/run/$tb/*.txt"
        grep -h -E "ERROR" "$run"/*.txt | head -10
        return 1
    fi
    grep -E "PASS|FAIL|ERROR" "$run/sim.txt"
    grep -q "FAIL" "$run/sim.txt" && return 1 || return 0
}

sync_src
if [ "${1:-all}" = "all" ]; then
    status=0
    for f in $(cd "$WORK/src" && find sim -name 'tb_*.v' | sort); do
        run_one "$(basename "$f" .v)" || status=1
    done
    exit $status
else
    run_one "$1"
fi
