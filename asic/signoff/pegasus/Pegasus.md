# Pegasus Verification System — side project

Goal: stand up Cadence Pegasus as a second, signoff-grade DRC/LVS engine next
to Magic + netgen — fast enough to run per P&R iteration (Magic takes ~35 min
on the full GDS), and eventually in-design from Innovus
(`Virtuoso_InDesign_Pegasus_drc` license exists). This document is the living
log: update it at every step, and record the first real use at the bottom.

## Status

| step | state |
|---|---|
| Licenses confirmed | DONE 2026-09-01 |
| Pegasus Verification binary installed | **BLOCKED — IT request needed** (draft below) |
| sky130 DRC deck | STAGED — OSU teaching deck in `decks/` (26 rules, metal width/spacing only) |
| DRC deck ported to useful coverage | not started (plan below) |
| sky130 LVS deck | none exists publicly — write or obtain (plan below) |
| Runner script | `run_pegasus_drc.sh` drafted, UNTESTED (no binary to test against) |
| First real run | — |

## Investigation findings (2026-09-01)

**Licenses: complete and idle.** `5280@ece-itop-licsvr.ece.ufl.edu` serves
`Pegasus_DRC`, `Pegasus_LVS`, `Pegasus_advdrc`, `Pegasus_advlvs`,
`Pegasus_perc`, `Pegasus_16nm`, `Pegasus_UI` / `Pegasus_RV` (results viewer,
1500 seats), and `Virtuoso_InDesign_Pegasus_drc` (Pegasus engine callable from
inside Innovus/Virtuoso). Checked with
`/apps/cds/jasper/2020/bin/lmutil lmstat -c 5280@ece-itop-licsvr.ece.ufl.edu -a`.

**Software: wrong product installed.** `/apps/cds/pegasus231` is **Pegasus DFM
23.12** (PEGASUSDFM release: LPA / CMP / CAA / CPA — lithography, CMP and
critical-area analysis, the former MVS products; see its
`PEGASUSDFM_ReadMe~23.12.000.txt`). It contains `pegasus-lpa` / `pegasus-cmp` /
`pegasus-caa` but **no `pegasus` DRC/LVS executable**. No other Cadence install
under `/apps/cds` has one either (every `*/bin` and `*/tools.lnx86/bin`
checked; `ssv231` is Tempus/Voltus, Assura 4.1 is the only Cadence PV engine
present). IT appears to have installed PEGASUSDFM but never the PEGASUS
release itself, despite holding the licenses.

**Rule decks: the PDK has none for Pegasus.** open_pdks sky130A
(`$PDK_ROOT_SKY130/libs.tech/`) ships Magic, netgen, and KLayout decks only.
Public options:

- [stineje/sky130_cds](https://github.com/stineje/sky130_cds) (Oklahoma
  State, Apache-2.0) has `DRC/sky130_drcRules.pvl` — a *teaching* deck:
  420 lines, 26 rules, min-width (`X1`) + min-spacing (`X2`) per layer only.
  No enclosure/area/density/antenna rules, and its `LVS/` directory is empty.
  It also carries Quantus PEX files (`PEX/qrcTechFile`, `sky130.ict`) — a
  possible cross-check for our own techgen output.
- Production-grade Pegasus decks exist only in the **NDA SkyWater PDK**
  (per [skywater-pdk verification docs](https://github.com/google/skywater-pdk/blob/main/docs/verification.rst))
  and in the **Cadence VLSI Fundamentals Education Kit** (sky130-based, uses
  Pegasus; per [SkyWater's announcement](https://www.skywatertechnology.com/skywater-announces-availability-of-cadence-open-source-pdk-and-reference-design-for-skywaters-130-nm-process/)).
  UF is a Cadence academic member — the kit is requestable through that
  channel.

**Staged deck.** `decks/sky130_drcRules.pvl` is copied verbatim from
stineje/sky130_cds commit `0609013` (2022-09-12), Apache-2.0. Two edits will
be needed before first use (do them in a copy, keep this one pristine):
its `results_db -drc mult_seq.drc_errors.ascii` line hardcodes the demo
design's output name, and coverage must be extended (below).

## What we need, in order

1. **The binary.** Email ECE IT (draft below). Everything else is prep work
   until this lands. When it does: record the install path here, point
   `PEGASUS_VERIFY_HOME` at it in `../env.sh` (the existing `PEGASUS_HOME`
   stays on the DFM install), and shake down `run_pegasus_drc.sh` — its
   command-line flags were written from memory and MUST be checked against
   the installed release's `pegasus -help` / docs.
2. **DRC deck port.** Extend the OSU deck to the rules that matter for P&R
   signoff, using the KLayout deck
   (`$PDK_ROOT_SKY130/libs.tech/klayout/drc/`) as the numeric reference and
   Magic as the arbiter:
   - met1–met5 / via / via2–via4 / mcon / li1: width, spacing, enclosure,
     min-area (our real violations are exactly met1/met2 spacing + shorts at
     the SRAM macro corners);
   - antenna rules (Innovus reports ~7k process-antenna violations on iter14);
   - metal density windows;
   - calibrate: run Pegasus and Magic on the same GDS, diff per-rule counts,
     chase every disagreement to a rule-text reading before trusting either.
3. **LVS deck** (lowest priority — netgen already works): PVL layer
   extraction + device recognition for the sky130_fd_pr FETs the std cells
   use, blackbox the OpenRAM macros (same name-map problem `../lvs/lvs.md`
   hit: rebadged `sram_1rw1r_32_256_8_sky130` vs PDK
   `sky130_sram_1kbyte_1rw1r_32x256_8`), compare against the P&R netlist.
   Attempt only if the education-kit deck doesn't materialize first.

## IT request draft (v2, 2026-09-01)

> **Subject: Request: install Cadence PEGASUS (Verification System) — licensed but not installed**
>
> Hi,
>
> I'm a grad student in ECE (advisor cc'd) running a full RTL-to-GDSII flow
> on the SKY130 open PDK using the department's Cadence tools (Genus, Innovus,
> Tempus, Quantus on ece-lnx-10). I'd like to use Cadence's Pegasus
> Verification System for physical verification (DRC/LVS), and it looks like
> we're licensed for it but the software itself was never installed:
>
> - The license server (5280@ece-itop-licsvr.ece.ufl.edu) serves the full
>   Pegasus feature set — Pegasus_DRC, Pegasus_LVS, Pegasus_advdrc,
>   Pegasus_advlvs, Pegasus_UI/RV, and Virtuoso_InDesign_Pegasus_drc — all
>   currently at zero usage (verified with lmstat on 2026-09-01).
> - The only Pegasus product under /apps/cds is `pegasus231`, which is the
>   **PEGASUSDFM** release (Layout Pattern Analyzer / CMP / CAA — its ReadMe
>   confirms this). It contains no `pegasus` DRC/LVS executable, and no other
>   Cadence install under /apps/cds has one.
>
> **The ask:** install the **PEGASUS** release (Pegasus Verification System,
> latest 23.x ISR, lnx86 — a separate product from PEGASUSDFM on the Cadence
> download site) alongside the existing installs, e.g. to
> /apps/cds/pegasusverif231, via iscape as usual. No license changes are
> needed — the features are already served.
>
> **Optional second ask, if easy:** through the university's Cadence academic
> program, the "Cadence VLSI Fundamentals Education Kit" (the SKY130-based
> kit announced with SkyWater) includes Pegasus rule decks for SKY130. If the
> department's academic account can pull that kit, it would save every student
> using the open PDK from hand-writing rule decks.
>
> Happy to validate the install the same day it lands — I have a full-chip
> GDS ready as a test case, and I'll confirm license checkout and basic
> DRC operation so you can close the ticket. If there's anything I can do to
> make this easier (exact download links, testing an install in a temp
> location first), just say the word.
>
> Thanks!
> Miguel Sanchez

## IT request v3 (2026-09-04) - re-verified, ready to send

Re-check on 2026-09-04 12:30 (`lmutil lmstat -c 5280@ece-itop-licsvr.ece.ufl.edu -a`):
18 Pegasus features served, every one at 0 in use - Pegasus_DRC, Pegasus_LVS,
Pegasus_advdrc, Pegasus_advlvs, Pegasus_perc, Pegasus_16nm, Pegasus_int,
Pegasus_mpt, Pegasus_UI (1500), Pegasus_RV (1500), Pegasus_Quickview,
Pegasus_DesignReview{,_Layout,_Mask}, Pegasus_LPA{,_fixing}, Pegasus_dfmfill,
Virtuoso_InDesign_Pegasus_drc. `/apps/cds/pegasus231` unchanged since
2024-12-04 (root-owned, PEGASUSDFM 23.12 ReadMe: LPA / CMP / CAA / CPA). No
`pegasus` / `pegasusrv` executable anywhere under /apps (depth-4 find).
Newest Cadence install on the box is ASSURA41 (2026-09-02), so IT is actively
maintaining /apps/cds.

> **Subject: Cadence Pegasus Verification (DRC/LVS): licensed on ece-itop-licsvr but not installed**
>
> Hi,
>
> I am an ECE grad student (advisor cc'd) running an RTL-to-GDSII flow on the
> SkyWater SKY130 open PDK with the department's Cadence tools on ece-lnx-10
> (Genus, Innovus, Tempus, Quantus). I would like to use Cadence Pegasus for
> physical verification (DRC/LVS). The department already holds the licenses,
> but the software itself does not appear to be installed:
>
> - 5280@ece-itop-licsvr.ece.ufl.edu serves the full Pegasus feature set
>   (Pegasus_DRC, Pegasus_LVS, Pegasus_advdrc, Pegasus_advlvs, Pegasus_perc,
>   Pegasus_UI/RV, Virtuoso_InDesign_Pegasus_drc, 300 seats each), all at
>   zero usage as of today (lmstat, 2026-09-04).
> - The only Pegasus directory under /apps/cds is /apps/cds/pegasus231, which
>   is the PEGASUSDFM 23.12 release (Layout Pattern Analyzer / CMP / CAA /
>   CPA; its ReadMe says so). It has no `pegasus` DRC/LVS executable, and no
>   other Cadence install under /apps has one either.
>
> The ask: install the PEGASUS release (Pegasus Verification System, latest
> 23.x ISR, lnx86; it is a separate product from PEGASUSDFM on the Cadence
> download site) next to the existing installs, for example as
> /apps/cds/pegasus_verif231, through iscape as usual. No license change is
> needed; the features are already served.
>
> A second, optional ask if it is easy: the Cadence "VLSI Fundamentals
> Education Kit" (the SKY130-based kit Cadence and SkyWater announced) ships
> Pegasus rule decks for SKY130. If the department's Cadence academic account
> can pull that kit, every student on the open PDK gets signoff DRC/LVS
> without hand-writing decks. If you would rather I request that through my
> advisor, just say so.
>
> I can validate the install the same day it lands: I have a full-chip GDS and
> netlist ready as a test case and will confirm license checkout and a basic
> DRC run so the ticket can be closed. If it helps to stage it in a temporary
> location first, I am happy to test there.
>
> Thanks,
> Miguel Sanchez

Send to: ECE IT help desk (the address that handles /apps and
ece-itop-licsvr), cc advisor. When it lands: record the path here, set
`PEGASUS_VERIFY_HOME` in `../env.sh`, shake down `run_pegasus_drc.sh`.

## Running (once installed)

```bash
bash -lc 'source /apps/settings && source <repo>/asic/signoff/env.sh && \
          SIGNOFF_PNR_STAMP=<stamp> <repo>/asic/signoff/pegasus/run_pegasus_drc.sh [gds]'
```

Results land in `$SIGNOFF_RESULTS/pegasus_drc/` keyed by the P&R run stamp,
same rule as every other signoff check. Debug visually with `pegasusrv`
(results viewer, `Pegasus_RV` license).

## Major finding 2026-09-01 (late): CALIBRE is installed, licensed, and idle

A full sweep of /apps for the Pegasus binary (all top-level dirs, depth-bounded
finds) confirmed Pegasus Verification exists nowhere — but turned up
**Siemens Calibre**, the industry-standard signoff PV tool:

- Installs: `/apps/siemens/calibre/aok_cal_2026.2_15.12` (**Calibre 2026.2**,
  binary runs, version prints) and `/apps/mgc/calibre/` (2015.3/2022.3/2024.2).
- Env: `source /apps/siemens/enable` sets `MGLS_LICENSE_FILE=1717@ece-itop-licsvr`.
- Licenses on 1717@ece-itop-licsvr: `calibredrc`, `calibrelvs`, `calibrehdrc`,
  `calibrehlvs`, `calibrexrc`, `calibreperc` — 300 seats each, idle, and the
  server is demonstrably alive (a calibreqdb seat was checked out).
- **No sky130 Calibre DRC/LVS decks on the system** (only OpenRCX extraction
  rules in calibre format under the opdk's openlane dir). Same deck problem as
  Pegasus: SkyWater's Calibre decks are NDA-gated per the skywater-pdk docs.

Consequence for this side project: **Calibre needs no IT ticket** — the
missing piece is the rule deck only, versus Pegasus's binary + deck. If a
commercial-PV second opinion is the goal, the SVRF port (Calibre) strictly
dominates the PVL port (Pegasus) on effort-to-first-result. The Pegasus IT
email is still worth sending (Innovus in-design DRC integration is
Pegasus-only), but the deck-writing energy should go to SVRF first.
Deck sources to pursue: SkyWater NDA PDK via university/advisor channels
(fastest if it exists), or port metal/via rules from the KLayout deck.

## Log

- **2026-09-01** — Investigation done (findings above). Folder created, OSU
  DRC deck staged, runner drafted (untested), IT email drafted. Next action:
  send the IT request.
- **2026-09-01 (late)** — /apps sweep: Pegasus binary confirmed absent
  everywhere; Calibre 2026.2 discovered installed + licensed (section above).
- **2026-09-01 (later)** — third engine confirmed: **Synopsys IC Validator**
  T-2022.03-SP3-4 at `/apps/syn/icv/bin/icv` (runs, prints version), licensed
  on 27020@ece-itop-licsvr (`ICValidator2-GeometryEngine` ×500 for DRC,
  `ICValidator2-CompareEngine` ×100 for LVS, all idle). Same missing piece as
  Calibre: no sky130 runset on the system. Commercial-PV engine ranking for
  this project: Calibre (newest install, industry-standard name) > ICV (older
  2022 install) > Pegasus (not installed at all). All three share the
  deck/runset gap; decks are the whole side project.

- **2026-09-04** - facts re-verified (18 features idle, still DFM-only
  install, nothing new under /apps); IT request v3 written above, ready to
  send. Calibre/ICV status unchanged (installed, licensed, no sky130 decks).

## First real use

*(fill in: date, P&R run stamp, GDS, deck version, wall time, violation
count vs Magic's on the same GDS, and whether the numbers were trusted.)*
