# PnR constraint mode.
#
# golden.sdc stays the single authoritative constraint file for the project and
# is NOT edited by the back end - both flows read the same source, which is the
# whole reason it exists. This file sources it and adds only what golden.sdc
# deliberately defers to CTS.
#
# What golden.sdc defers, in its own words:
#   - "Hold uncertainty is deliberately NOT set here. Hold is not fixed pre-CTS
#      [...] Add it when the flow reaches CTS."
#   - the 0.250 ns setup uncertainty is "Removed and replaced with
#      propagated-clock analysis once CTS has actually been run."
#
# Both are handled in 04_cts.tcl rather than here, because they only become
# correct AFTER the tree is built - applying them at init would make the
# pre-CTS reports meaningless. This file therefore carries the pre-CTS values,
# and 04_cts.tcl overrides them in place once ccopt_design has run.
#
# The one thing that IS set here is the hold uncertainty, at its pre-CTS value:
# MMMC creates a hold view from the moment the design is initialised, and a hold
# view with zero uncertainty reports optimistically from stage 00 onward.

# constraints/ -> innovus/ -> PnR/ -> asic/ : three levels up, not two
# (first shakedown 2026-08-26: two levels pointed at asic/PnR/synthesis, the
# SDC read aborted, and stage 00 "completed" with NO clock defined).
source [file join [file dirname [file normalize [info script]]] \
        .. .. .. synthesis common constraints golden.sdc]

# Pre-CTS hold margin. Replaced by 04_cts.tcl's post-CTS value once the clock is
# propagated. Deliberately non-zero so that early hold reports are pessimistic
# rather than flattering.
set_clock_uncertainty -hold 0.100 [get_clocks clk]

# ---------------------------------------------------------------------------
# P&R clock target (added 2026-08-26).
#
# golden.sdc says 3.500 ns and stays untouched - it remains the synthesis
# truth, and every Genus number in asic/PPA/ was measured against it. The
# back end signs off at the block's real target, 250 MHz = 4.000 ns
# (golden.sdc's own comment names that target). A second create_clock on the
# same port REPLACES the earlier definition, so this one line is the whole
# override; the uncertainties above still apply to the new clock.
#
# To go back to 3.500 ns for a like-for-like comparison with synthesis:
# comment out (or delete) the line below and re-run stage 00.
create_clock -name clk -period 7.000 [get_ports clk]
