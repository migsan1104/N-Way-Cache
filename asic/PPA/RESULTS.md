# ASIC synthesis PPA results

The project's capacity target moved to 16KB (2026-08-20); the previous 4KB
tables were retired with it (they survive in git history). The 16KB five-way
Genus + DC sweep and the first SRAM-macro run are in flight; this file is
regenerated from their reports by:

```bash
cd asic && ./collect_ppa.py --markdown PPA/RESULTS.md --png ..
```
