#!/usr/bin/env python3
"""Split a FASTQ read file into N chunks of FASTA records.

Used by the example workflow's `split_input` rule. Deliberately minimal so the
example doesn't pull in biopython for what is essentially line counting.

Each FASTQ record becomes one FASTA record. Output filenames are chunk_001.fa,
chunk_002.fa, ... — bwa mem reads any of them by glob.
"""

import argparse
import os
import sys


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--in", dest="infile", required=True, help="Input FASTQ.")
    p.add_argument("--outdir", required=True, help="Output directory for chunks.")
    p.add_argument(
        "--chunks", type=int, default=4, help="Number of chunks (default: 4)."
    )
    return p.parse_args()


def fastq_records(path: str):
    """Yield (header, sequence) tuples from a FASTQ file."""
    with open(path) as fh:
        while True:
            header = fh.readline()
            if not header:
                return
            seq = fh.readline().rstrip("\n")
            plus = fh.readline()
            _qual = fh.readline()
            if not (header.startswith("@") and plus.startswith("+")):
                sys.exit(f"Malformed FASTQ near: {header!r}")
            yield header[1:].rstrip("\n"), seq


def main() -> None:
    args = parse_args()
    os.makedirs(args.outdir, exist_ok=True)

    records = list(fastq_records(args.infile))
    if not records:
        sys.exit(f"No records in {args.infile}")

    # Even-ish distribution across chunks.
    n_chunks = max(1, args.chunks)
    per_chunk = (len(records) + n_chunks - 1) // n_chunks

    for i in range(n_chunks):
        chunk = records[i * per_chunk : (i + 1) * per_chunk]
        if not chunk:
            break
        outpath = os.path.join(args.outdir, f"chunk_{i + 1:03d}.fa")
        with open(outpath, "w") as out:
            for name, seq in chunk:
                out.write(f">{name}\n{seq}\n")


if __name__ == "__main__":
    main()
