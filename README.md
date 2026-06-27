# Cache

High-Performance Parameterized Non-Blocking Cache IP with PPA Exploration

## Overview

This project focuses on the design and implementation of a parameterized cache IP in SystemVerilog with configurable associativity, scalable architecture exploration, and non-blocking cache behavior.

The cache is being designed using ASIC-oriented RTL methodologies while leveraging FPGA implementation flows for rapid timing closure experimentation and PPA (Performance, Power, and Area) analysis.

A major focus of the project is high-frequency structural RTL design, scalable cache architecture exploration, and out-of-order cache response handling.

The cache architecture is designed to support configurable:
- Cache sizes
- Set associativity
- Read latency
- Line size
- Memory organization

Planned advanced features include:
- Non-blocking cache behavior
- Multiple outstanding misses
- Hit-under-miss support
- Miss-under-miss support
- Out-of-order cache responses

Example behavior:

If the CPU issues requests A, B, C, and D back-to-back, where A and C miss while B and D hit, the cache can continue servicing hits while outstanding misses are pending.

The cache may return responses in an order such as:

```text
B -> D -> A -> C
```

depending on downstream memory completion timing.

---

## Project Goals

- Develop reusable and technology-agnostic cache RTL
- Design a scalable non-blocking cache architecture
- Explore PPA tradeoffs across associativity configurations
- Analyze timing scalability across cache sizes and organizations
- Study the impact of associativity on timing, area, and power
- Practice ASIC-oriented RTL development methodologies
- Explore high-frequency structural RTL optimization techniques
- Build a clean and well-documented cache IP architecture

---

## Features

- Parameterized cache architecture
- Configurable set associativity
    - Direct-mapped
    - 2-way set associative
    - 4-way set associative
    - 8-way set associative
- Configurable cache sizes
- Adjustable read latency
- Structural SystemVerilog RTL
- Technology-independent module organization
- FPGA-based timing and PPA exploration flow
- Modular cache subsystem design
- Non-blocking cache architecture (planned)
- Out-of-order response support (planned)
- Multiple outstanding misses (planned)

---

## Planned Architecture

The cache design is planned to include:
- Address decode logic
- Tag array
- Data array
- Valid/dirty tracking
- Hit/miss detection
- Replacement policy logic
- Memory refill path
- MSHR (Miss Status Holding Register) structures
- CPU interface
- Downstream memory interface
- Request tracking and response ordering logic

---

## Verification

Verification will include:
- Directed testing
- Randomized testing
- Functional coverage
- Timing validation
- Corner-case testing
- Multi-request non-blocking cache validation

Simulation tools:
- Questa
- ModelSim

---

## PPA Exploration

The project analyzes:
- Fmax scalability
- Resource utilization
- Power consumption
- Associativity tradeoffs
- Cache size scaling
- Latency tradeoffs
- Non-blocking architecture overhead
- Outstanding miss scalability

Implementation sweeps are performed across multiple parameter combinations using Vivado out-of-context synthesis and implementation flows.

Future ASIC-oriented exploration may include:
- ASIC synthesis flows
- Standard-cell timing analysis
- RTL-to-GDS experimentation

---

## Tools Used

- SystemVerilog
- Vivado
- Questa / ModelSim
- TCL scripting
- Python scripting

---

## Future Work

- AXI interface support
- Full multi-MSHR architecture
- Advanced replacement policies
- Multi-level cache hierarchy
- Cache coherence experiments
- ASIC synthesis flow integration
- RTL-to-GDS exploration
- Automated architectural sweep framework
- Detailed PPA report generation

---

## Repository Structure

```text
rtl/        -> RTL source files
tb/         -> Testbenches
scripts/    -> TCL and automation scripts
reports/    -> Timing, power, and utilization reports
docs/       -> Project documentation
```