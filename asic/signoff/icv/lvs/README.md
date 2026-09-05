# ICV LVS -- single standard cell (sky130_fd_sc_hd__inv_1)

Status 2026-09-05: `sky130_lvs_min.rs` compiles (`icv -cache-only`) but has never run --
the installed ICV T-2022.03 cannot check out a license on this server (needs the
Apex-licensed ICV >= U-2022.12). Details and the sizing of full-chip LVS: `SIV_LVS.md`.

Three commands (ICV writes into the current directory, so always `cd` into a run dir;
one Synopsys license at a time; shell state does not persist, hence `bash -lc`):

```bash
# 1. run directory + the cell's CDL (already there; regenerate like this if needed)
mkdir -p asic/signoff/icv/lvs/runs/inv_1 && cd asic/signoff/icv/lvs/runs/inv_1
{ echo "*.SCALE micron"; awk '/^\.SUBCKT sky130_fd_sc_hd__inv_1 /,/^\.ENDS sky130_fd_sc_hd__inv_1/' \
  /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/cdl/sky130_fd_sc_hd.cdl; } \
  > sky130_fd_sc_hd__inv_1.cdl

# 2. compile check (license-free)
bash -lc 'source /apps/settings && cd asic/signoff/icv/lvs/runs/inv_1 && icv -cache-only ../../sky130_lvs_min.rs'

# 3. the LVS run (blocked today: "License denied", exit 67)
bash -lc 'source /apps/settings && cd asic/signoff/icv/lvs/runs/inv_1 && \
  icv -c sky130_fd_sc_hd__inv_1 \
      -i /apps/cds/IC618/local/opdk/share/pdk/sky130A/libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds -f GDSII \
      -s sky130_fd_sc_hd__inv_1.cdl -sf SPICE ../../sky130_lvs_min.rs'
```

Result: first line of `sky130_fd_sc_hd__inv_1.LVS_ERRORS` (PASS/FAIL); per-cell detail in
`run_details/compare/*/sum.*`; layout netlist `sky130_fd_sc_hd__inv_1.net`.
For nand2_1 change `-c` and cut that subckt instead (same labels, same devices).

`runs/nettran_probe/` keeps the license-free NetTran experiments (std-cell CDL, SRAM SPICE,
P&R Verilog + macro stub) and their logs; the large `.nt` outputs were deleted.
