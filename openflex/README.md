# Cache OpenFLEX

Run the cache verification testbench from this directory:

```bash
cd /home/UFAD/miguel.sanchez1/Cache/openflex
./verify.sh
```

`verify.sh` sets up the Questa/OpenFLEX environment, runs:

```bash
openflex Cache_verification.yml
```

and overwrites `transcript` with only the latest run output. It also copies the same output to `run.log`.

The verification config uses `../Verification/Test_Complete.sv` as the top testbench and compiles the RTL from `../src/*.sv`. The only OpenFLEX verification sweep parameter is `CACHE_BYTES`; associativity is not swept in the YAML because `Test_Complete.sv` runs all supported associativities internally.

The expected passing summary is:

```text
Congrats all associativity tests passed
```
