#!/bin/bash
# -----------------------------------------------------------------------------
# Fetch + simulate a tiny dataset for the example workflow.
#
# Downloads the E. coli K-12 MG1655 reference (~5 MB) and simulates two small
# paired-end-style read sets with wgsim. Total disk: <10 MB. Total wall time
# on a cluster login node: ~10 seconds.
#
# Outputs (idempotent — re-running is a no-op when files already exist):
#   data/ref/genome.fa             single-contig reference FASTA
#   data/ref/genome.fa.fai         samtools faidx index
#   data/ref/genome.dict           gatk sequence dictionary
#   data/ref/genome.fa.{amb,ann,bwt,pac,sa}   bwa index
#   data/reads/sampleA.fq          ~5000 simulated reads
#   data/reads/sampleB.fq          ~5000 simulated reads
#
# Prerequisites on $PATH (any one of):
#   - the example conda env activated (see ../env.yml)
#   - the example container loaded
# Specifically requires: curl, gunzip, samtools, bwa, gatk, wgsim.
# wgsim ships with samtools/htslib on bioconda.
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$EXAMPLE_DIR"

REF_URL="https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=nuccore&id=U00096.3&rettype=fasta&retmode=text"
REF_DIR="data/ref"
READS_DIR="data/reads"

mkdir -p "$REF_DIR" "$READS_DIR"

if [[ ! -s "$REF_DIR/genome.fa" ]]; then
  echo "[fetch] Downloading E. coli K-12 MG1655 reference..."
  curl -fsSL "$REF_URL" -o "$REF_DIR/genome.fa"
fi

if [[ ! -s "$REF_DIR/genome.fa.fai" ]]; then
  echo "[fetch] Indexing reference (samtools faidx)..."
  samtools faidx "$REF_DIR/genome.fa"
fi

if [[ ! -s "$REF_DIR/genome.dict" ]]; then
  echo "[fetch] Creating sequence dictionary (gatk CreateSequenceDictionary)..."
  gatk CreateSequenceDictionary -R "$REF_DIR/genome.fa" -O "$REF_DIR/genome.dict"
fi

if [[ ! -s "$REF_DIR/genome.fa.bwt" ]]; then
  echo "[fetch] Indexing reference (bwa index)..."
  bwa index "$REF_DIR/genome.fa"
fi

for sample in sampleA sampleB; do
  fq="$READS_DIR/$sample.fq"
  if [[ ! -s "$fq" ]]; then
    echo "[fetch] Simulating reads for $sample (wgsim)..."
    # -N: number of read pairs; -1/-2: read lengths; -e/-r: error/mutation rates.
    # Small N keeps each sample to ~50 KB and total runtime to seconds.
    seed=$((RANDOM))
    wgsim -N 5000 -1 100 -2 100 -e 0.001 -r 0.001 -S "$seed" \
      "$REF_DIR/genome.fa" "$fq" /dev/null > /dev/null
  fi
done

echo "[fetch] Done. Inputs ready under data/."
