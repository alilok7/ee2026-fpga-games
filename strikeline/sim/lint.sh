#!/usr/bin/env bash
# lint.sh - compile every StrikeLine Verilog source with xvlog (syntax + width
# warnings), without running a testbench. Usage: bash sim/lint.sh
VIV=${VIVADO_BIN:-/c/AMDDesignTools/2025.2/Vivado/bin}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(cygpath -u "${TEMP:-/tmp}" 2>/dev/null || echo /tmp)/strikeline_lint
rm -rf "$WORK" && mkdir -p "$WORK" && cp -r "$ROOT/rtl" "$WORK/"
cd "$WORK" && "$VIV/xvlog.bat" -d SIM -i rtl/top -i rtl/d_game_ui -i rtl/c_pins $(find rtl -name '*.v') > lint.txt 2>&1
grep -E "ERROR|WARNING" lint.txt | sed 's#C:/Users/[^ ]*/strikeline_lint/##' | head -${1:-40}
grep -q ERROR lint.txt && exit 1 || { echo "lint: no errors"; exit 0; }
