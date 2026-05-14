# snakemake7/ — legacy patterns example

A minimal 4-rule Snakefile that illustrates the Snakemake 7 patterns the talk
contrasts against. **Not a runnable production workflow** — the inputs and
container are placeholders. The point is the *shape* of the Snakefile and the
submission command.

## Layout

```
snakemake7/
├── Snakefile        # 4 rules: split_input, align, call_variants, summarize
├── config.yaml      # sample list + paths
└── run.sh           # legacy --cluster invocation (removed in Snakemake 9)
```

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
- No partition selection. Every job lands on the cluster default queue.
- No rate limiting. Wide fan-outs can saturate `slurmctld`.
- No automatic retry-with-more-resources on OOM/walltime kills.

The companion `../snakemake9/` example adds all of these.
