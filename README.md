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
- Implement critial word first behavior for misses. 
- Implement replacement policies
- Implement write-back/write-allocate behavior
- Produce a modular RTL design suitable for verification and physical implementation

---

## 2. Verification

In this phase, we will verify functional correctness before beginning architectural optimization. The verification process will aim to demonstrate that the cache behaves correctly across directed scenarios, randomized traffic, and stressful corner cases.

We will use:

- Directed testing
- Random testing
- Functional coverage
- Self-checking testbench infrastructure
- Scoreboards
- Corner-case testing
- Stress testing
- Regression testing

Optimization will only begin after functional correctness has been demonstrated.

---

## 3. FPGA PPA Characterization and Optimization

In this phase, we will synthesize and implement the design using Xilinx UltraScale devices in Out-of-Context mode. This will provide quantitative data for comparing architectural configurations before committing to an ASIC implementation path.

We will collect:

- Maximum operating frequency
- Resource utilization
- Power consumption

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

The ASIC implementation phase will connect the architectural design decisions made earlier in the project to their physical consequences in timing, power, area, and layout complexity.

---

## Project Goal

Our goal is to produce a high-performance parameterized cache architecture while studying the impact of architectural decisions on performance, power, and area throughout both FPGA and ASIC implementation flows. The project will combine architecture design, functional verification, FPGA-based PPA characterization, optimization, and full RTL-to-GDSII implementation into a complete engineering research workflow.
