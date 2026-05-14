# examples/

Self-contained, side-by-side examples for the RMACC talk on migrating a
Snakemake workflow from version 7 to version 9. Each subdirectory implements
the **same 4-rule workflow shape** (`split_input` → `align` → `call_variants`
→ `summarize`) so the differences between them are *patterns*, not workload.

These examples exist because the production workflow the talk is built around
contains private research data and cannot be distributed. The Snakefiles,
profiles, container recipe, and env files here mirror every Snakemake-level
pattern referenced in the slides without leaking that workflow.

## Layout

```
examples/
├── README.md                       # this file
├── snakemake7/                     # legacy patterns — what we migrated FROM
│   ├── README.md
│   ├── Snakefile                   # 4 rules; per-rule singularity:, inline resources:
│   ├── config.yaml                 # sample list + paths
│   ├── env.yml                     # mamba env: snakemake 7.32.4
│   └── run.sh                      # legacy --cluster 'sbatch ...' invocation
│
└── snakemake9/                     # current patterns — what we migrated TO
    ├── README.md
    ├── Snakefile                   # 4 rules; global container:, no resources: blocks,
    │                               # python_exec resolved from $CONDA_PREFIX
    ├── config.yaml                 # sample list + paths
    ├── env.yml                     # mamba env: snakemake 9.5.1 + slurm executor plugin
    ├── run.sh                      # login-node invocation
    ├── sbatch.sh                   # driver-as-SLURM-job invocation
    ├── scripts/
    │   ├── fetch_example_data.sh   # downloads E. coli ref + simulates reads
    │   ├── split_input.py          # rule: split_input
    │   └── summarize.py            # rule: summarize
    ├── container/
    │   ├── README.md               # build / test instructions
    │   └── tools.def               # Apptainer recipe — bwa, samtools, gatk
    └── profiles/
        └── slurm/
            ├── config.yaml         # executor settings, rate limits,
            │                       # default-resources, set-resources (with
            │                       # attempt-based backoff lambdas)
            └── public.yaml         # partition table for auto-selection
```

## What each example demonstrates

The two subdirectories are deliberately paired so a `diff` between matching
files tells the migration story:

```bash
diff -u snakemake7/Snakefile snakemake9/Snakefile
diff -u snakemake7/run.sh    snakemake9/run.sh
```

### `snakemake7/` — the legacy patterns

| Pattern | Where |
|---|---|
| `singularity:` repeated per rule | `Snakefile` (`align`, `call_variants`) |
| String-typed `runtime` (`'15m'`, `'4h'`) | every rule's `resources:` block |
| Fixed-integer `mem_mb`, no retry backoff | every rule's `resources:` block |
| Bare `python` in shell rules | `Snakefile` (`split_input`, `summarize`) |
| Resources live in the Snakefile, not a profile | every rule |
| Legacy `--cluster 'sbatch ...'` submission | `run.sh` |

### `snakemake9/` — the current patterns

| Pattern | Where |
|---|---|
| Global `container:` directive | `Snakefile` top |
| `get_python_executable()` resolved from `$CONDA_PREFIX` | `Snakefile` top |
| Resources moved out of the Snakefile | `profiles/slurm/config.yaml` `set-resources:` |
| `lambda wildcards, attempt: ...` backoff on heavy rules | `set-resources:` for `align`, `call_variants` |
| Integer-minute runtimes (not `'4h'`) | `set-resources:` |
| Rate limiting (`max-jobs-per-timespan`, `max-status-checks-per-second`) | `profiles/slurm/config.yaml` |
| Automatic partition selection from a partition table | `profiles/slurm/public.yaml` + `--slurm-partition-config` |
| `executor: slurm` set in profile (not on CLI) | `profiles/slurm/config.yaml` |
| `--workflow-profile` invocation | `run.sh`, `sbatch.sh` |
| Driver-as-SLURM-job pattern | `sbatch.sh` |
| Apptainer container recipe | `container/tools.def` |

## How to use these examples

`snakemake9/` is **runnable end-to-end** on any SLURM cluster with apptainer —
it ships a `scripts/fetch_example_data.sh` that builds a tiny synthetic dataset
(E. coli + simulated reads, <10 MB total). See `snakemake9/README.md` for the
exact steps.

`snakemake7/` is **illustrative only** — it intentionally has no container
build and the legacy `--cluster` submission would need cluster-specific
sbatch flags filled in. Read it as an archive of patterns to compare against,
not a thing to run.

1. Read the per-directory `README.md` for the patterns being demonstrated.
2. `diff` matching files between `snakemake7/` and `snakemake9/` to see the
   migration mechanically.
3. Run `snakemake9/` end-to-end if you want to prove the wiring works on
   your cluster.

## Related files in the repo root

- `../rmacc-slides.md` — the talk these examples support
