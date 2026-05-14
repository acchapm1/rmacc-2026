# snakemake7/ — legacy patterns example

A minimal 4-rule Snakefile that illustrates the Snakemake 7 patterns the talk
contrasts against. **Runnable on any SLURM cluster with apptainer** against
the same tiny synthetic dataset (E. coli + simulated reads, <10 MB) used by
the snakemake9 example. The point is the *shape* of the Snakefile and the
submission command — the small dataset just lets you prove the legacy wiring
still works on pre-Snakemake-8 versions.

> Snakemake removed `--cluster` in version 9 (September 2024). This example
> requires Snakemake 7.x; `env.yml` pins `snakemake=7.32.4` for that reason.

## Layout

```
snakemake7/
├── Snakefile                       # 4 rules: split_input, align,
│                                   # call_variants, summarize
├── config.yaml                     # sample list + paths
├── env.yml                         # mamba env: snakemake 7.32.4 + tooling
├── run.sh                          # legacy --cluster invocation
├── scripts/
│   ├── fetch_example_data.sh       # downloads E. coli ref + simulates reads
│   ├── split_input.py              # rule: split_input
│   └── summarize.py                # rule: summarize
└── container/
    ├── tools.def                   # Apptainer recipe — bwa, samtools, gatk
    └── README.md                   # build instructions
```

The `scripts/` and `container/tools.def` files are byte-identical to the
ones in `../snakemake9/`. That is deliberate — the migration story this
talk tells is about Snakemake-level patterns (the Snakefile and the
submission command), not the underlying tools.

## How to run it end-to-end

On any SLURM cluster with `apptainer` (or `singularity`) available as a
module:

```bash
# 1. Create the workflow env (note: snakemake 7.x, separate from sn9-example)
module load mamba/latest
mamba env create -f env.yml
source activate sn7-example

# 2. Build the container (once — or symlink ../snakemake9/container/tools.sif
#    if you already built it for the sn9 example)
module load apptainer
apptainer build container/tools.sif container/tools.def

# 3. Fetch and simulate the example dataset (~10 seconds, <10 MB)
bash scripts/fetch_example_data.sh

# 4. Submit. Set PARTITION to one your cluster offers (default: public).
PARTITION=compute ./run.sh
```

End state: `results/sampleA.report.txt` and `results/sampleB.report.txt`,
matching what the snakemake9 example produces from the same inputs. The
two reports should be byte-identical given the same `wgsim` random seed —
running both examples and diffing the reports is a good sanity check that
your migration preserves behavior.

## What this example shows

Each item below corresponds to a slide in `../../rmacc-slides.md`:

| Pattern | Where in `Snakefile` |
|---|---|
| `singularity:` repeated per rule | `align`, `call_variants` |
| String-typed `runtime` (`'15m'`, `'4h'`) | every rule's `resources:` block |
| Fixed-integer `mem_mb`, no `attempt` backoff | every rule's `resources:` block |
| Bare `python` in shell rules | `split_input`, `summarize` |
| Resources live in the Snakefile, not a profile | every rule |
| Legacy `--cluster 'sbatch ...'` submission | `run.sh` |

## What's missing (deliberately)

- No `profiles/` directory. Configuration is on the command line in `run.sh`.
- No partition table. The single partition is wired into `run.sh` via the
  `PARTITION` env var; on a cluster with multiple queues you'd hand-route.
- No rate limiting. Wide fan-outs can saturate `slurmctld`.
- No automatic retry-with-more-resources on OOM/walltime kills.

The companion `../snakemake9/` example adds all of these.
