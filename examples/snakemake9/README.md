# snakemake9/ — current patterns example

A minimal 4-rule Snakefile demonstrating the Snakemake 9 patterns the talk
recommends. **Runnable on any SLURM cluster with apptainer** against a tiny
synthetic dataset (E. coli + simulated reads, <10 MB, runs in seconds). The
point is the *shape* of the Snakefile, the profile, and the submission
command — the small dataset just lets you prove the wiring works.

## Layout

```
snakemake9/
├── Snakefile                       # 4 rules — same 4 as snakemake7/, no
│                                   # per-rule singularity:, no resources:
├── config.yaml                     # sample list + paths
├── env.yml                         # mamba env (snakemake + bwa/samtools/gatk
│                                   # for the data-prep step)
├── run.sh                          # login-node invocation
├── sbatch.sh                       # driver-as-SLURM-job invocation
├── scripts/
│   ├── fetch_example_data.sh       # downloads E. coli ref + simulates reads
│   ├── split_input.py              # rule: split_input
│   └── summarize.py                # rule: summarize
├── container/
│   ├── tools.def                   # Apptainer recipe: bwa, samtools, gatk
│   └── README.md                   # build instructions
└── profiles/
    └── slurm/
        ├── config.yaml             # workflow profile: executor settings,
        │                           # rate limiting, default-resources,
        │                           # set-resources (with attempt-backoff)
        └── public.yaml             # partition table for auto-selection
```

## How to run it end-to-end

On any SLURM cluster with `apptainer` (or `singularity`) available as a
module:

```bash
# 1. Create the workflow env
module load mamba/latest
mamba env create -f env.yml
source activate sn9-example

# 2. Build the container (once)
module load apptainer
apptainer build container/tools.sif container/tools.def

# 3. Fetch and simulate the example dataset (~10 seconds, <10 MB)
bash scripts/fetch_example_data.sh

# 4. Submit
./run.sh                 # interactive: driver on login node, jobs to SLURM
# or
sbatch sbatch.sh         # production: driver itself runs as a SLURM job
```

End state: `results/sampleA.report.txt` and `results/sampleB.report.txt`,
each containing a one-line variant count. The whole workflow should clear
in under a minute on a quiet cluster.

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
