#!/bin/bash
# -----------------------------------------------------------------------------
# Snakemake 7 invocation — the legacy --cluster pattern.
#
# Everything the scheduler needs to know is jammed into a shell string that
# Snakemake interpolates per job. Times are hardcoded. No partition. No
# rate limiting. No retry logic above the rule level.
#
# This invocation does NOT work under Snakemake >= 9 — the --cluster flag
# was removed in September 2024. See ../snakemake9/run.sh for the
# replacement.
# -----------------------------------------------------------------------------
set -euo pipefail

snakemake -p \
    --snakefile Snakefile \
    --configfile config.yaml \
    --jobs 50 \
    --default-resources mem_mb=8000 \
    --use-singularity \
    --cluster 'sbatch -n {threads} --mem={resources.mem_mb} -t 01:00:00 \
               -o logs/{rule}.{jobid}.out -e logs/{rule}.{jobid}.err'
