# container/

The Snakefile's global `container:` directive points here:

```python
container: "container/tools.sif"
```

This directory holds the Apptainer recipe (`tools.def`) for the minimal image
the example workflow uses. The built `.sif` is intentionally **not** checked
in — it's a multi-hundred-MB binary that should be rebuilt per cluster.

## Layout

```
container/
├── tools.def    # Apptainer build recipe
├── tools.sif    # Built image — produced by `apptainer build` (gitignored)
└── README.md
```

## What's in the image

`tools.def` installs exactly the three binaries the example rules invoke:

| Tool      | Version   | Used by rule    |
|-----------|-----------|-----------------|
| `bwa`     | 0.7.18    | `align`         |
| `samtools`| 1.21      | `align`         |
| `gatk`    | 4.6.2.0   | `call_variants` |

All three come from bioconda, installed into the `base` env of a
`condaforge/miniforge3` base image.

## Build

From this directory:

```bash
apptainer build tools.sif tools.def
```

This needs either root or `--fakeroot`. On a cluster that disallows both,
build on a workstation and `scp` the resulting `.sif` over.

Build time is dominated by the conda solve — expect a few minutes the first
time. The image lands at `container/tools.sif`, which is exactly where the
Snakefile's `container:` directive expects it.

## Test the image

The `%test` block in `tools.def` runs automatically at the end of the build
and prints the version of each tool. You can re-run it any time without
rebuilding:

```bash
apptainer test tools.sif
```

Expected output is three short banners — one per tool — and an exit code of
zero.

For a quick interactive sanity check:

```bash
apptainer exec tools.sif bwa 2>&1 | head -n 3
apptainer exec tools.sif samtools --version | head -n 1
apptainer exec tools.sif gatk --version
```

## Use with the workflow

Once `tools.sif` exists in this directory, the example workflow picks it up
automatically via the global `container:` directive at the top of
`../Snakefile`. Run with:

```bash
cd ..
./run.sh        # or: sbatch sbatch.sh
```

The `--use-singularity` flag in both wrappers is what tells Snakemake to
honor the `container:` directive.
