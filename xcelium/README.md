# Xcelium Simulation Workflow

This directory contains the Cadence Xcelium command-line simulation flow for the cache verification environment.

The flow is intended to mirror the OpenFlex verification workflow while keeping the first Xcelium target simple: compile, elaborate, and run `Test_Complete.sv` in batch mode without launching SimVision.

## Run

Before running any Xcelium command, source the Cadence environment:

```bash
source /apps/settings
cd xcelium
./run.sh
```

The run script will:

- Clean previous Xcelium-generated files.
- Create `logs/` and `waves/` if needed.
- Compile and elaborate the RTL and verification sources listed in `filelist.f`.
- Run `Test_Complete` in batch mode.
- Write simulator output to `logs/xrun.log`.
- Print a clear pass/fail message based on the `xrun` exit status.

## Clean

To remove generated simulator files:

```bash
./clean.sh
```

The clean script removes only Xcelium-generated outputs such as `xcelium.d`, `INCA_libs`, `worklib`, log/key/history files, SHM databases, and files under `logs/` and `waves/`.

## GUI Support

GUI and SimVision support will be added later after the batch command-line flow is stable.
