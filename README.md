# High-Frequency Parameterized Cache Architecture

## Goal / Overview

The goal of this project will be to design, verify, optimize, and eventually physically implement a high-performance parameterized cache architecture. This project aims to study cache architecture tradeoffs while following a realistic ASIC development methodology from RTL design through physical implementation.

The cache architecture will be:

- Parameterized
- N-way set associative
- Non-blocking
- Out-of-order response capable
- High-frequency oriented
- Designed using synthesizable RTL
- Fully verified before optimization

This project will use a structured engineering flow:

1. Design the cache architecture.
2. Verify functionality using both directed and constrained-random testing.
3. Perform FPGA implementation using Xilinx UltraScale Out-of-Context synthesis and implementation to collect timing, utilization, and power data.
4. Optimize the architecture based on those PPA results.
5. Select the best-performing architecture.
6. Complete a full RTL-to-GDSII ASIC implementation flow.

FPGA implementation will be used as an architectural evaluation step before ASIC implementation. The final objective will be to understand how architectural decisions affect performance, power, and area while progressing from RTL through physical implementation.

---

## Project Roadmap

The project will be divided into four major phases.

## 1. Design Specification

In this phase, we will define the cache architecture and develop a modular RTL implementation suitable for verification, optimization, and physical implementation.

We will:

- Define the cache architecture
- Develop a parameterized RTL implementation
- Support configurable cache size
- Support configurable associativity
- Implement a non-blocking cache architecture
- Support multiple outstanding misses
- Implement an out-of-order response mechanism
- Implement critical-word-first behavior for misses
- Track 8 reusable CPU request ID slots and return the corresponding request ID with each CPU response
- Model CPU-side forward pressure on request valid and CPU-side backpressure on response ready
- Assume no downstream memory backpressure at this cache boundary
- Implement replacement policies
- Implement write-back/write-allocate behavior
- Produce a modular RTL design suitable for verification and physical implementation

The cache interface will be designed for a CPU pipeline that may apply forward pressure and backpressure independently. CPU request issue will be controlled through request valid/ready behavior, and CPU responses will be allowed to stall through response ready. The cache will preserve the CPU request ID and return it with the corresponding response so an out-of-order CPU pipeline can correctly associate returned data with the original request.

The downstream memory side will assume no memory-request backpressure at this cache boundary. This assumption will match the planned RISC-V out-of-order CPU environment, where downstream flow control and memory-system pressure will be handled by a larger cache-coherence and memory hierarchy structure rather than by this local cache interface.

---

## 2. Verification

In this phase, we will verify functional correctness before beginning architectural optimization. The verification process will aim to answer a simple question first: does the cache return the right data, with the right CPU request ID, under both normal traffic and pressure?

The verification environment will use a self-checking SystemVerilog testbench. The testbench will drive CPU requests into the cache, model downstream memory, track the expected response for every request, and compare every returned read against a golden memory model.

The environment will include:

- A synthesizable cache DUT instantiated across associativity configurations
- A downstream word-addressed RAM model with tracked memory response IDs
- A golden memory model for data correctness checking
- Scoreboards for expected CPU responses
- Reusable CPU request ID slots
- Directed and randomized request streams
- Configurable CPU request-valid and CPU response-ready probability knobs
- Per-test statistics for hits, misses, reads, writes, data checks, data errors, memory traffic, evictions, and writebacks

The CPU interface will support 8 reusable request ID slots. Each request will carry a CPU request ID, and each cache response will return the matching ID along with response data and hit/miss status. This will allow the testbench to verify correctness even when responses return out of issue order.

The normal fast regression entry point will be:

```bash
./verify.sh
```

This root-level script will run four compact PASS/FAIL checks:

- QuestaSim with CPU request/response probabilities set to `1.0 / 1.0`
- QuestaSim with CPU request/response probabilities set to `0.8 / 0.8`
- Xcelium with CPU request/response probabilities set to `1.0 / 1.0`
- Xcelium with CPU request/response probabilities set to `0.8 / 0.8`

The detailed simulator logs will remain in the simulator-specific folders, but the root workflow will keep the terminal output short so it is easy to see whether the design passed.

Xcelium support will be provided through the `xcelium/` directory. This flow will use a Cadence file list, compile the same RTL and `Test_Complete.sv` testbench, elaborate the `Test_Complete` top module, and run the simulation in batch mode without launching SimVision. Before using the Xcelium flow directly, the Cadence environment should be loaded:

```bash
source /apps/settings
cd xcelium
./run.sh
```

The direct Xcelium script will also support the same probability knobs used by the root verification flow:

```bash
./run.sh 1.0 1.0
./run.sh 0.8 0.8
```

For compact automation, the root `./verify.sh` script will call Xcelium in quiet mode and pass those values into the testbench through command-line parameter overrides. Full Xcelium output will be saved in `xcelium/logs/xrun.log`, while the terminal will only report PASS or FAIL. This gives us a second simulator backend for cross-checking the same verification environment without changing RTL or testbench behavior.

We will use a mix of:

- Directed testing
- Random testing
- Functional coverage
- Self-checking testbench infrastructure
- Scoreboards
- Corner-case testing
- Stress testing
- Regression testing

Optimization will only begin after functional correctness has been demonstrated.

### Verification Test Suite

The regression will run the full test suite for each associativity configuration. With the current verification knobs, each associativity run will issue 200,500 CPU requests, and the full five-associativity sweep will issue 1,002,500 CPU requests.

| Test | Description | CPU Requests per Associativity |
| --- | --- | ---: |
| Test1 | Sequential write/read test over word addresses to verify basic fill, hit, and readback behavior. | 20,000 |
| Test2 | Cache-overflow test using unique line addresses and a fixed word offset to stress replacement, dirty evictions, and readback correctness. | 20,000 |
| Test3 | Controlled-locality randomized burst sweep using burst lengths 8, 16, 24, 32, 40, 48, 56, 64, 72, and 80. Each phase will use a unique 500-address pool and issue 10,000 requests, for 100,000 total Test3 requests. | 100,000 |
| Test4 | Read/write/read sequence over the same address set to verify old-data reads followed by updated-data reads. | 1,500 |
| Test5 | Repeated read and write traffic to selected line addresses to stress same-address reuse and cache hit behavior. | 5,000 |
| Test6 | Repeated traffic to two words within each selected cache line to verify same-line word selection and update behavior. | 40,000 |
| Test7 | Back-to-back read/write/read triples over sequential addresses without waiting between requests. | 3,000 |
| Test8 | Back-to-back read/write/read triples over line-stride addresses to stress line replacement behavior. | 3,000 |
| Test9 | Write/read/write triples followed by final readback over sequential addresses. | 4,000 |
| Test10 | Write/read/write triples followed by final readback over line-stride addresses. | 4,000 |

---

## 3. FPGA PPA Characterization and Optimization

In this phase, we will synthesize and implement the design using Xilinx UltraScale devices in Out-of-Context mode. This will give us practical timing, utilization, and power data before we choose which cache architecture is worth carrying forward into a deeper ASIC flow.

We will collect:

- Maximum operating frequency
- Resource utilization
- Power consumption

The PPA workflow will live under `openflex/`. From that directory, a single associativity run will be launched with:

```bash
./timing.sh N
```

where `N` will be one of:

```text
1, 2, 4, 8, 16
```

If no associativity is provided, the script will default to associativity 8:

```bash
./timing.sh
```

Each run will execute the existing OpenFlex/Vivado timing flow for the selected associativity and place the results in a per-associativity PPA folder:

```text
openflex/PPA/assoc_N/
  cacheN.csv
  outputs/
  power/
```

The `cacheN.csv` file will store the timing and utilization table for that associativity. The `outputs/` directory will hold the latest Vivado output reports for that associativity, replacing the previous contents each time that associativity is rerun. The `power/` directory will preserve timestamped post-route power reports so multiple power runs can be compared over time.

This structure will make it easy to compare associativity choices without overwriting results from other configurations. For example, `assoc_4` and `assoc_8` can each keep their own timing reports, utilization reports, route reports, and power history.

Current results (4 KB cache, XCU250-FIGD2104-2L-E, out-of-context, all five measured on the same RTL revision):

| Associativity (ways) | Fmax (MHz) | LUTs (Used) | FFs/REGs (Used) | Dynamic Power (W) | Static Power (W) | Total Power (W) |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 221.2 | 55,817 | 42,237 | 3.769 | 3.017 | 6.786 |
| 2 | 264.9 | 55,395 | 42,636 | 3.756 | 3.016 | 6.772 |
| 4 | **267.5** | **55,057** | 43,023 | 3.323 | 3.008 | **6.331** |
| 8 | 232.0 | 56,082 | 43,541 | 4.032 | 3.022 | 7.054 |
| 16 | 232.2 | 57,312 | 44,805 | 3.626 | 3.014 | 6.640 |

Four-way leads on frequency, LUT count, and total power simultaneously. Utilization is nearly flat
across the sweep (55.1k-57.3k LUTs, a 4% spread), so at 4 KB associativity costs very little area on
this device and the choice is driven by Fmax and power rather than by resource count.

These numbers are regenerated with `openflex/collect_ppa.py`, which reads each `cache<N>.csv` plus
the newest post-route power report, cross-checks every Fmax against the `WNS` in that same
associativity's `post_route_timing_summary.rpt`, and warns if a row's `ASSOC` field does not match
the folder it landed in.

Current PPA visualization:

![FPGA cache PPA scaling results](FPGA_Cache_PPA_Scaling_4KB_Updated.png)

Multiple cache configurations will be evaluated, including different associativities, cache sizes, and architectural optimizations. These measurements will guide architectural optimization and allow quantitative comparison of design tradeoffs.

FPGA implementation will serve as an intermediate architectural evaluation step, not as the final implementation target.

---

## 4. RTL-to-GDSII Flow

Once the architecture has been verified and optimized, we will transition to a complete ASIC implementation flow. This phase will demonstrate the complete digital IC implementation process from synthesizable RTL through manufacturable layout. We will go through the whole RTL -> GDSII flow with the best design implemented on the FPGA in terms of PPA tradeoffs. 

This flow will include:

- Logic synthesis
- Static Timing Analysis (STA)
- Floorplanning
- Placement
- Clock Tree Synthesis (CTS)
- Routing
- Timing closure
- Power analysis
- Physical verification
- GDSII generation

### Logical synthesis results

Logic synthesis is run ahead of the physical flow so the architectural comparison can be repeated on
a real standard-cell library rather than on FPGA primitives. Both tools target SKY130 HD at the
typical corner (`tt_025C_1v80`, 1.80 V, 25 C) with a 2.000 ns clock, using the same RTL revision as
the FPGA sweep. From `asic/`:

```bash
./run_genus.sh N        # Cadence Genus
./run_dc.sh N           # Synopsys Design Compiler
./sweep.sh -j 2         # several configurations
```

Results land in `asic/PPA/<genus|dc>/assoc_N/`.

Current results (4 KB cache, SKY130 HD, TT 1.80 V 25 C, 2.000 ns target):

**Cadence Genus**

| Associativity (ways) | Fmax (MHz) | WNS (ns) | Cell Area (um^2) | Cells | Sequential Cells | Total Power (W) | Violating Paths |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 295.7 | -1.381 | **2,287,635** | **282,515** | **46,585** | **1.212** | **43,864** |
| 2 | 305.6 | -1.272 | 2,423,165 | 286,570 | 47,334 | 1.239 | 45,566 |
| 4 | 305.3 | -1.276 | 2,361,137 | 288,242 | 48,342 | 1.270 | 46,629 |
| 8 | **328.8** | **-1.041** | 2,443,901 | 298,673 | 49,625 | 1.312 | 46,628 |
| 16 | 307.2 | -1.255 | 2,709,735 | 336,337 | 52,874 | 1.447 | 49,380 |

**Synopsys Design Compiler**

| Associativity (ways) | Fmax (MHz) | WNS (ns) | Cell Area (um^2) | Cells | Sequential Cells | Total Power (W) | Violating Paths |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 278.6 | -1.590 | 2,129,487 | 249,795 | **50,078** | **1.043** | **44,851** |
| 2 | 297.6 | -1.360 | **2,094,878** | **247,704** | 50,849 | 1.059 | 45,684 |
| 4 | 305.8 | -1.270 | 2,248,449 | 262,572 | 51,907 | 1.086 | 46,360 |
| 8 | **312.5** | **-1.200** | 2,222,607 | 263,482 | 53,048 | 1.113 | 47,577 |
| 16 | 308.6 | -1.240 | 2,390,762 | 290,586 | 55,038 | 1.158 | 48,908 |

No configuration closes timing at the 2.000 ns target, so the Fmax column is what each critical path
would support rather than a met constraint. Both tools independently rank eight-way fastest
(328.8 MHz on Genus, 312.5 MHz on DC), which disagrees with the FPGA sweep, where four-way led.
The disagreement is informative rather than contradictory: LUT-based logic absorbs the wide way
comparison differently than standard cells do, so the FPGA result should not be assumed to carry
into the ASIC flow.

Unlike the FPGA sweep, where utilization was nearly flat across associativity, ASIC area and power
scale monotonically with way count. On Genus, moving from one way to eight costs 6.8% cell area and
8.3% power to buy 11.2% frequency; sixteen ways costs 18.4% area over one way and gives back
frequency. That makes eight-way the cost-effective stopping point on both tools.

These tables are regenerated with `asic/collect_ppa.py`, which parses each tool's QoR, area, and
power reports into a common column set, writes `asic/PPA/RESULTS.md`, and with `--png` renders the
charts below:

```bash
./collect_ppa.py --markdown PPA/RESULTS.md --png ..
```

Current synthesis PPA visualization:

![Cadence Genus synthesis PPA scaling](ASIC_Genus_Synthesis_PPA_4KB.png)

![Synopsys Design Compiler synthesis PPA scaling](ASIC_DC_Synthesis_PPA_4KB.png)

The ASIC implementation phase will connect the architectural design decisions made earlier in the project to their physical consequences in timing, power, area, and layout complexity.

---

## Project Goal

Our goal is to produce a high-performance parameterized cache architecture while studying the impact of architectural decisions on performance, power, and area throughout both FPGA and ASIC implementation flows. The project will combine architecture design, functional verification, FPGA-based PPA characterization, optimization, and full RTL-to-GDSII implementation into a complete engineering research workflow.
