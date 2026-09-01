# Source this before any signoff tool:  source asic/signoff/env.sh
# (after `source /apps/settings`, which exports QUANTUS_HOME / VOLTUS_HOME and
# the Cadence license server).
_here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export SIGNOFF_DIR=$_here
export REPO_ROOT=$(cd -- "$_here/../.." && pwd)

export PDK_ROOT_SKY130=/apps/cds/IC618/local/opdk/share/pdk/sky130A
export STDCELL_ROOT=$PDK_ROOT_SKY130/libs.ref/sky130_fd_sc_hd
export SKY130_MAGIC_TECH=$PDK_ROOT_SKY130/libs.tech/magic/sky130A.tech
export SKY130_MAGICRC=$PDK_ROOT_SKY130/libs.tech/magic/sky130A.magicrc
export SKY130_NETGEN_SETUP=$PDK_ROOT_SKY130/libs.tech/netgen/sky130A_setup.tcl
export SKY130_GDS_MAP=$PDK_ROOT_SKY130/libs.tech/klayout/tech/sky130A.map

# Tools
export QUANTUS_HOME=${QUANTUS_HOME:-/apps/cds/quantus221}
export SSV_HOME=${VOLTUS_HOME:-/apps/cds/ssv231}          # Tempus + Voltus
export PEGASUS_HOME=/apps/cds/pegasus231
# Magic (/apps/magic) was built against Tcl/Tk 8.5, which the OS no longer
# ships; the Synopsys FPGA tree carries a complete 8.5 runtime, so borrow it.
# netgen is built from source into ~/.local (lvs/lvs.md).
# Scoped to the magic invocation ($MAGIC_RUN) so the Synopsys libraries never
# leak into the Cadence tools' LD_LIBRARY_PATH.
export MAGIC_RUN="env LD_LIBRARY_PATH=/apps/syn/fpga/linux_a_64 TCL_LIBRARY=/apps/syn/fpga/lib/tcl8.5 TK_LIBRARY=/apps/syn/fpga/lib/tk8.5 /apps/magic/bin/magic"
export PATH=$HOME/.local/bin:$QUANTUS_HOME/bin:$QUANTUS_HOME/tools/bin:$SSV_HOME/bin:$SSV_HOME/tools/bin:$PEGASUS_HOME/bin:$PEGASUS_HOME/tools/bin:$PATH

# Which P&R run to sign off. Empty = the bare asic/PnR/innovus/ tree (run 1);
# otherwise asic/PnR/innovus/runs/<stamp>/.
export SIGNOFF_PNR_STAMP=${SIGNOFF_PNR_STAMP:-}
if [ -z "$SIGNOFF_PNR_STAMP" ]; then
    export SIGNOFF_PNR_DIR=$REPO_ROOT/asic/PnR/innovus
    export SIGNOFF_RESULTS=$SIGNOFF_DIR/results/run1
else
    export SIGNOFF_PNR_DIR=$REPO_ROOT/asic/PnR/innovus/runs/$SIGNOFF_PNR_STAMP
    export SIGNOFF_RESULTS=$SIGNOFF_DIR/results/$SIGNOFF_PNR_STAMP
fi

# QRC techfiles produced by quantus/run_techgen.sh (one per RC corner)
export SKY130_QRC_TECH_DIR=$SIGNOFF_DIR/quantus/techfiles
