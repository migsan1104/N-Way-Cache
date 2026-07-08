#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

rm -rf xcelium.d
rm -rf INCA_libs
rm -rf worklib
rm -rf .simvision
rm -rf *.shm
rm -f *.history
rm -f *.key
rm -f *.log
rm -f *.diag
rm -f *.dsn
rm -f *.trn
rm -f cds.lib
rm -f hdl.var

mkdir -p logs waves
rm -rf logs/*
rm -rf waves/*
