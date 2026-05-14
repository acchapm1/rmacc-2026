#!/bin/bash
# -----------------------------------------------------------------------------
# Snakemake 9 invocation — runs on the login node for testing.
#
# Compare to ../snakemake7/run.sh:
#   - No --cluster string.
#   - No embedded sbatch template.
#   - No walltimes, memory, or output paths on the command line.
# Everything that used to be in the --cluster string now lives in:
#   profiles/slurm/config.yaml   (executor settings, defaults, set-resources)
#   profiles/slurm/public.yaml   (partition table)
# -----------------------------------------------------------------------------
set -euo pipefail

mkdir -p logs/slurm

snakemake -p \
  --snakefile Snakefile \
  --configfile config.yaml \
  --workflow-profile profiles/slurm \
  --slurm-partition-config profiles/slurm/public.yaml \
  2>&1 | tee logs/output.log
