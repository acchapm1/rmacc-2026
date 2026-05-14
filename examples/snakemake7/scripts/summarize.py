#!/usr/bin/env python3
"""Summarize a VCF into a one-line report.

Used by the example workflow's `summarize` rule. Counts records and lists the
chromosomes touched. Deliberately stdlib-only.
"""

import argparse
from collections import Counter


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--vcf", required=True, help="Input VCF.")
    p.add_argument("--out", required=True, help="Output report.")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    chrom_counts: Counter[str] = Counter()
    with open(args.vcf) as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            chrom = line.split("\t", 1)[0]
            chrom_counts[chrom] += 1

    total = sum(chrom_counts.values())
    with open(args.out, "w") as out:
        out.write(f"variants: {total}\n")
        for chrom, n in chrom_counts.most_common():
            out.write(f"  {chrom}: {n}\n")


if __name__ == "__main__":
    main()
