#!/bin/bash
#
# Train standard MHCflurry Class I models.
# Calls mhcflurry-class1-train-allele-specific-models on curated training data
# using the hyperparameters in "hyperparameters.yaml".
#
set -e
set -x

DOWNLOAD_NAME=models_class1_unselected
SCRATCH_DIR=${TMPDIR-/tmp}/mhcflurry-downloads-generation
SCRIPT_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR=$(dirname "$SCRIPT_ABSOLUTE_PATH")

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

cd $SCRATCH_DIR/$DOWNLOAD_NAME

mkdir models

python $SCRIPT_DIR/generate_hyperparameters.py > hyperparameters.yaml

GPUS=$(nvidia-smi -L 2> /dev/null | wc -l) || GPUS=0
echo "Detected GPUS: $GPUS"

PROCESSORS=$(getconf _NPROCESSORS_ONLN)
echo "Detected processors: $PROCESSORS"

time mhcflurry-class1-train-allele-specific-models \
    --allele HLA-A*02:01 HLA-A*01:01 HLA-A*03:01 HLA-A*11:01 HLA-A*24:02 HLA-B*07:02 HLA-B*15:01 \
    --data "$(mhcflurry-downloads path data_curated)/curated_training_data.no_mass_spec.csv.bz2" \
    --hyperparameters hyperparameters.yaml \
    --out-models-dir models \
    --percent-rank-calibration-num-peptides-per-length 0 \
    --min-measurements-per-allele 75 \
    --num-jobs $(expr $PROCESSORS \* 2) --gpus $GPUS --max-workers-per-gpu 2 --max-tasks-per-worker 20

cp $SCRIPT_ABSOLUTE_PATH .
bzip2 LOG.txt
tar -cjf "../${DOWNLOAD_NAME}.tar.bz2" *

echo "Created archive: $SCRATCH_DIR/$DOWNLOAD_NAME.tar.bz2"
