# container/

The Snakefile's per-rule `singularity:` directives point here:

```python
singularity: "container/tools.sif"   # repeated on every containerized rule
```

This directory holds the Apptainer recipe (`tools.def`) for the minimal image
the example workflow uses. The built `.sif` is intentionally **not** checked
in — it's a multi-hundred-MB binary that should be rebuilt per cluster.

The recipe is byte-for-byte identical to `../../snakemake9/container/tools.def`.
The migration story is in the Snakefile, not in the image: in Snakemake 9 the
`container:` directive moves to the top of the file once, instead of being
repeated on every rule that needs the image.

## Layout

```
container/
├── tools.def    # Apptainer build recipe
├── tools.sif    # Built image — produced by `apptainer build` (gitignored)
└── README.md
```

## What's in the image

| Tool      | Version   | Used by rule    |
|-----------|-----------|-----------------|
| `bwa`     | 0.7.18    | `align`         |
| `samtools`| 1.21      | `align`         |
| `gatk`    | 4.6.2.0   | `call_variants` |

## Build

From this directory:

```bash
apptainer build tools.sif tools.def
```

Same prerequisites and caveats as the snakemake9 container — see
`../../snakemake9/container/README.md` for the full notes.
