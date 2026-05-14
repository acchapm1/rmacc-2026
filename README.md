# rmacc-2026

Talk materials for **RMACC 2026** on migrating a production Snakemake workflow
from Snakemake 7 to Snakemake 9 on a SLURM cluster.

## Contents

- `rmacc-slides.md` — talk slides (Markdown source)
- `rmacc-slides.html` — rendered HTML slide deck
- `examples/` — side-by-side `snakemake7/` and `snakemake9/` example workflows
  demonstrating every pattern referenced in the talk. See
  [`examples/README.md`](examples/README.md) for the full pattern-by-pattern
  breakdown.
- `img/` — figures used in the slides

## What the talk covers

The two example workflows implement the same 4-rule shape
(`split_input` → `align` → `call_variants` → `summarize`) so that diffs between
matching files surface the migration mechanically:

```bash
diff -u examples/snakemake7/Snakefile examples/snakemake9/Snakefile
diff -u examples/snakemake7/run.sh    examples/snakemake9/run.sh
```

Patterns highlighted include the move from `--cluster` to `--executor slurm`,
per-rule `resources:` blocks to profile-level `set-resources:` with
attempt-based backoff, repeated `singularity:` directives to a global
`container:`, and the driver-as-SLURM-job submission pattern.
