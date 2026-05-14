# snakemake9/ — current patterns example

A minimal 4-rule Snakefile demonstrating the Snakemake 9 patterns the talk
recommends. **Not a runnable production workflow** — the inputs and container
are placeholders. The point is the *shape* of the Snakefile, the profile, and
the submission command.

## Layout

```
snakemake9/
├── Snakefile                       # 4 rules — same 4 as snakemake7/, no
│                                   # per-rule singularity:, no resources:
├── config.yaml                     # sample list + paths
├── run.sh                          # login-node invocation
├── sbatch.sh                       # driver-as-SLURM-job invocation
├── container/
│   └── README.md                   # where the .sif would live
└── profiles/
    └── slurm/
        ├── config.yaml             # workflow profile: executor settings,
        │                           # rate limiting, default-resources,
        │                           # set-resources (with attempt-backoff)
        └── public.yaml             # partition table for auto-selection
```

## What this example shows

Each item below corresponds to a slide in `../../rmacc-slides.md`:

| Pattern | Where |
|---|---|
| Global `container:` directive (no per-rule duplication) | `Snakefile` top |
| `get_python_executable()` resolved from `$CONDA_PREFIX` | `Snakefile` top |
| Resources moved out of the Snakefile | `profiles/slurm/config.yaml` `set-resources:` |
| `lambda wildcards, attempt: ...` backoff on heavy rules | `set-resources:` for `align`, `call_variants` |
| Integer-minute runtimes (not `'4h'`) | `set-resources:` |
| Rate limiting (`max-jobs-per-timespan`, `max-status-checks-per-second`) | `profiles/slurm/config.yaml` |
| Automatic partition selection from a partition table | `profiles/slurm/public.yaml` + `--slurm-partition-config` |
| `executor: slurm` set in profile (not on CLI) | `profiles/slurm/config.yaml` |
| `--workflow-profile` invocation | `run.sh`, `sbatch.sh` |
| Driver-as-SLURM-job pattern | `sbatch.sh` |

## How to read the diff

The cleanest way to see what changed between Snakemake 7 and Snakemake 9 is:

```bash
diff -u ../snakemake7/Snakefile Snakefile
diff -u ../snakemake7/run.sh    run.sh
```

The Snakefile gets shorter. The submission command gets shorter. The
configuration that disappeared from both moved into `profiles/slurm/`.
