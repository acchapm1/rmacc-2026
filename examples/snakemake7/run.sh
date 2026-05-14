#!/bin/bash
# -----------------------------------------------------------------------------
# Snakemake 7 invocation — the legacy --cluster pattern.
#
# Everything the scheduler needs to know is jammed into a shell string that
# Snakemake interpolates per job. Times are hardcoded to the longest rule's
# walltime (4h) because string-typed runtime values can't be passed to sbatch.
# No partition selection. No rate limiting. No retry logic above the rule
# level.
#
# This invocation does NOT work under Snakemake >= 9 — the --cluster flag
# was removed in September 2024. See ../snakemake9/run.sh for the
# replacement.
#
# Edit PARTITION below to match your cluster (e.g. compute, public, normal).
# -----------------------------------------------------------------------------
set -euo pipefail

PARTITION="${PARTITION:-public}"

mkdir -p logs

snakemake -p \
    --snakefile Snakefile \
    --configfile config.yaml \
    --jobs 50 \
    --use-singularity \
    --cluster "sbatch --partition=$PARTITION -n {threads} \
               --mem={resources.mem_mb} -t 04:00:00 \
               -o logs/{rule}.{jobid}.out -e logs/{rule}.{jobid}.err" \
    2>&1 | tee logs/output.log
