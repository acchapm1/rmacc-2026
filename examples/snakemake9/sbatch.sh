#!/bin/bash
#SBATCH --job-name=example-workflow
#SBATCH --partition=public
#SBATCH --time=2-00:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=2
#SBATCH --output=logs/driver.%j.out
#SBATCH --error=logs/driver.%j.err
# -----------------------------------------------------------------------------
# Production invocation — the snakemake driver itself becomes a SLURM job.
# Body is identical to run.sh; only the SBATCH header is added.
# -----------------------------------------------------------------------------
set -euo pipefail

module load mamba/latest
source activate example-env

mkdir -p logs/slurm

snakemake -p \
    --snakefile Snakefile \
    --configfile config.yaml \
    --executor slurm \
    --workflow-profile profiles/slurm \
    --slurm-partition-config profiles/slurm/public.yaml \
    --scheduler greedy \
    --jobs 100 --cores 100 \
    --latency-wait 30 --retries 3 --rerun-incomplete \
    --use-singularity
