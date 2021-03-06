#!/bin/bash
#
# Create allele sequences (sometimes referred to as pseudosequences) by
# performing a global alignment across all MHC amino acid sequences we can get
# our hands on.
#
# Requires: clustalo, wget
#
set -e
set -x

DOWNLOAD_NAME=allele_sequences
SCRATCH_DIR=${TMPDIR-/tmp}/mhcflurry-downloads-generation
SCRIPT_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR=$(dirname "$SCRIPT_ABSOLUTE_PATH")
export PYTHONUNBUFFERED=1

mkdir -p "$SCRATCH_DIR"
rm -rf "$SCRATCH_DIR/$DOWNLOAD_NAME"
mkdir "$SCRATCH_DIR/$DOWNLOAD_NAME"

# Send stdout and stderr to a logfile included with the archive.
exec >  >(tee -ia "$SCRATCH_DIR/$DOWNLOAD_NAME/LOG.txt")
exec 2> >(tee -ia "$SCRATCH_DIR/$DOWNLOAD_NAME/LOG.txt" >&2)

# Log some environment info
date
pip freeze
git status
which clustalo
clustalo --version

cd $SCRATCH_DIR/$DOWNLOAD_NAME
cp $SCRIPT_DIR/make_allele_sequences.py .
cp $SCRIPT_DIR/filter_sequences.py .
cp $SCRIPT_DIR/class1_pseudosequences.csv .
cp $SCRIPT_ABSOLUTE_PATH .

# Generate sequences
# Training data is used to decide which additional positions to include in the
# allele sequences to differentiate alleles that have identical traditional
# pseudosequences but have associated training data
TRAINING_DATA="$(mhcflurry-downloads path data_curated)/curated_training_data.with_mass_spec.csv.bz2"

bzcat "$(mhcflurry-downloads path data_curated)/curated_training_data.with_mass_spec.csv.bz2" \
    | cut -f 1 -d , | uniq | sort | uniq | grep -v allele > training_data.alleles.txt

# Human
wget -q ftp://ftp.ebi.ac.uk/pub/databases/ipd/imgt/hla/fasta/A_prot.fasta
wget -q ftp://ftp.ebi.ac.uk/pub/databases/ipd/imgt/hla/fasta/B_prot.fasta
wget -q ftp://ftp.ebi.ac.uk/pub/databases/ipd/imgt/hla/fasta/C_prot.fasta
wget -q ftp://ftp.ebi.ac.uk/pub/databases/ipd/imgt/hla/fasta/E_prot.fasta
wget -q ftp://ftp.ebi.ac.uk/pub/databases/ipd/imgt/hla/fasta/F_prot.fasta
wget -q ftp://ftp.ebi.ac.uk/pub/databases/ipd/imgt/hla/fasta/G_prot.fasta

# Mouse
wget -q https://www.uniprot.org/uniprot/P01899.fasta  # H-2 Db
wget -q https://www.uniprot.org/uniprot/P01900.fasta  # H-2 Dd
wget -q https://www.uniprot.org/uniprot/P14427.fasta  # H-2 Dp
wget -q https://www.uniprot.org/uniprot/P14426.fasta  # H-2 Dk
wget -q https://www.uniprot.org/uniprot/Q31145.fasta  # H-2 Dq

wget -q https://www.uniprot.org/uniprot/P01901.fasta  # H-2 Kb
wget -q https://www.uniprot.org/uniprot/P01902.fasta  # H-2 Kd
wget -q https://www.uniprot.org/uniprot/P04223.fasta  # H-2 Kk
wget -q https://www.uniprot.org/uniprot/P14428.fasta  # H-2 Kq

wget -q https://www.uniprot.org/uniprot/P01897.fasta  # H-2 Ld
wget -q https://www.uniprot.org/uniprot/Q31151.fasta  # H-2 Lq

# Various
wget -q ftp://ftp.ebi.ac.uk/pub/databases/ipd/mhc/MHC_prot.fasta

python filter_sequences.py *.fasta --out class1.fasta

time clustalo -i class1.fasta -o class1.aligned.fasta

time python make_allele_sequences.py \
    class1.aligned.fasta \
    --recapitulate-sequences class1_pseudosequences.csv \
    --differentiate-alleles training_data.alleles.txt \
    --out-csv allele_sequences.csv

# Cleanup
gzip -f class1.fasta
gzip -f class1.aligned.fasta
rm *.fasta

cp $SCRIPT_ABSOLUTE_PATH .
bzip2 LOG.txt
tar -cjf "../${DOWNLOAD_NAME}.tar.bz2" *

echo "Created archive: $SCRATCH_DIR/$DOWNLOAD_NAME.tar.bz2"
