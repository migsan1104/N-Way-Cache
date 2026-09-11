# rc_correlate - is the pre-route RC estimator honest? (2026-09-07)

Measures what placement/CTS timing believes about wires against what the
routed design extracts, per net, without trusting `generateRCFactor`.

1. `estimator_spef.tcl` (edit the run stamp / output path at the top): restores
   a ROUTED checkpoint in a scratch session, deletes the signal routing,
   runs `earlyGlobalRoute` (the trial route pre-CTS timing uses), extracts
   with the pre-route engine and writes the estimator's SPEF. Nothing is saved.
2. `compare_spef.sh <estimator.spef> <outputs/*_pnr.spef>` joins both by net
   name (NAME_MAP resolved, PORTS section ignored - it reuses the *N prefix)
   and prints total R and C ratios, ratios bucketed by the reference net R,
   the largest nets, and the largest per-net ratios. `RC_CORR_WORK` sets the
   scratch dir.

Reading it: a total R ratio near the rc corner's preRoute_res factor means the
tables are right; a bucket trend (short nets over, long nets under) is shape
error that no global factor fixes. 19b, 2026-09-07: 1.137 total with the
1.1 factor in; <20 ohm nets 1.74, 20-100 1.27, 100-500 1.11, >500 0.90.
