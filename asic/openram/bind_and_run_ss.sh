#!/usr/bin/env bash
# 2026-08-25 (night): wait for the OpenRAM 32x256 SS/1.6V/100C characterization
# to finish, rebadge its lib+LEF under the cell name the RTL instantiates
# (sram_1rw1r_32_256_8_sky130; pins are identical, wmask1/power unconnected),
# and launch Genus on the current src/ with that lib and NO derate.
set -u
REPO=/ecel/UFAD/miguel.sanchez1/Cache
OUT=$REPO/asic/openram/macros_out/32x256
LIB=$OUT/openram_sram_1rw1r_32x256_8_SS_1p6V_100C.lib
LEF=$OUT/openram_sram_1rw1r_32x256_8.lef
B=$OUT/bound_sky130name
BLIB=$B/sram_1rw1r_32_256_8_sky130_SS_1p6V_100C.lib
BLEF=$B/sram_1rw1r_32_256_8_sky130.lef

echo "$(date) waiting for OpenRAM gen_32x256 to exit"
# run_openram.sh passes "-v -v" between the two names (the 08-26 waiter
# aborted at once because the old pattern never matched).
while pgrep -f 'sram_compiler.py.*gen_32x256.py' >/dev/null; do sleep 120; done
echo "$(date) compiler exited"
if [ ! -s "$LIB" ]; then echo "NO LIB WRITTEN - aborting"; exit 1; fi
sleep 30
mkdir -p "$B"
sed 's/openram_sram_1rw1r_32x256_8/sram_1rw1r_32_256_8_sky130/g' "$LIB" > "$BLIB"
sed 's/openram_sram_1rw1r_32x256_8/sram_1rw1r_32_256_8_sky130/g' "$LEF" > "$BLEF"
grep -m1 -E '^library|cell ?\(' "$BLIB"; grep -m1 '^MACRO' "$BLEF"
echo "--- dout1 clk1 access time (cell_rise table) from the new lib:"
awk '/pin ?\(dout1/{p=1} p && /cell_rise/{c=1} c && /values/{print; n++} n>=1{exit}' "$BLIB" | head -3

STAMP=$(date +%Y%m%d_%H%M%S)_e29ao_e35abcde_ssmacro_noderate_tb16_sram
echo "$(date) launching Genus $STAMP"
source /apps/settings
cd "$REPO/asic"
ASIC_SRAM_MACRO=1 ASIC_HDL_DEFINES=TAG_BANK_DEPTH=16 ASIC_KEEP_REPLICAS=0 \
ASIC_SRAM_MACRO_LIB="$BLIB" ASIC_SRAM_MACRO_LEF="$BLEF" ASIC_SRAM_MACRO_DERATE=1.0 \
ASIC_RUN_STAMP="$STAMP" ./run_genus.sh 4
echo "EXIT=$?  $(date)"
