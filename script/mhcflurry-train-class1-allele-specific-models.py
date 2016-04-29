#!/usr/bin/env python

# Copyright (c) 2016. Mount Sinai School of Medicine
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Train one neural network for every allele w/ more than 50 data points in
our dataset.

Using the following hyperparameters:
    embedding_size=64,
    layer_sizes=(400,),
    activation='relu',
    loss='mse',
    init='lecun_uniform',
    n_pretrain_epochs=10,
    n_epochs=100,
    dropout_probability=0.25
...which performed well in held out average AUC across alleles in the
Nielsen 2009 dataset.
"""

from __future__ import (
    print_function,
    division,
    absolute_import,
    unicode_literals
)
from os import makedirs, remove
from os.path import exists, join
import argparse

import numpy as np

from mhcflurry.common import normalize_allele_name
from mhcflurry.data import load_allele_datasets
from mhcflurry.class1_binding_predictor import Class1BindingPredictor
from mhcflurry.class1_allele_specific_hyperparameters import (
    add_hyperparameter_arguments_to_parser
)
from mhcflurry.paths import (
    CLASS1_MODEL_DIRECTORY,
    CLASS1_DATA_DIRECTORY
)
from mhcflurry.imputation import create_imputed_datasets, imputer_from_name

CSV_FILENAME = "combined_human_class1_dataset.csv"
CSV_PATH = join(CLASS1_DATA_DIRECTORY, CSV_FILENAME)

parser = argparse.ArgumentParser()

parser.add_argument(
    "--binding-data-csv",
    default=CSV_PATH,
    help="CSV file with 'mhc', 'peptide', 'peptide_length', 'meas' columns. "
    "Default: %(default)s")

parser.add_argument(
    "--output-dir",
    default=CLASS1_MODEL_DIRECTORY,
    help="Output directory for allele-specific predictor HDF weights files. "
    "Default: %(default)s")

parser.add_argument(
    "--overwrite",
    default=False,
    action="store_true",
    help="Overwrite existing output directory")

parser.add_argument(
    "--min-samples-per-allele",
    default=5,
    metavar="N",
    help="Don't train predictors for alleles with fewer than N samples. "
    "Default: %(default)s",
    type=int)

parser.add_argument(
    "--alleles",
    metavar="ALLELE",
    help="Alleles to train",
    default=[],
    nargs="+",
    type=normalize_allele_name)

parser.add_argument(
    "--imputation-method",
    default=None,
    choices=("mice", "knn", "softimpute", "svd", "mean"),
    type=lambda s: s.strip().lower(),
    help="Use the given imputation method to generate data for pre-training models")

# add options for neural network hyperparameters
parser = add_hyperparameter_arguments_to_parser(parser)

if __name__ == "__main__":
    args = parser.parse_args()
    print(args)

    if not exists(args.output_dir):
        makedirs(args.output_dir)

    allele_data_dict = load_allele_datasets(
        filename=args.binding_data_csv,
        peptide_length=9,
        use_multiple_peptide_lengths=True,
        max_ic50=args.max_ic50,
        sep=",",
        peptide_column_name="peptide")

    # concatenate datasets from all alleles to use for pre-training of
    # allele-specific predictors
    X_all = np.vstack([group.X_index for group in allele_data_dict.values()])
    Y_all = np.concatenate([group.Y for group in allele_data_dict.values()])
    print("Total Dataset size = %d" % len(Y_all))

    if args.imputation_method is None:
        imputer = None
    else:
        imputer = imputer_from_name(args.imputation_method)

    if imputer is None:
        imputed_data_dict = {}
    else:
        imputed_data_dict = create_imputed_datasets(
            allele_data_dict,
            args.imputation_method)

    # if user didn't specify alleles then train models for all available alleles
    alleles = args.alleles

    if not alleles:
        alleles = sorted(allele_data_dict.keys())

    for allele_name in alleles:
        allele_data = allele_data_dict[allele_name]
        X = allele_data.X_index
        Y = allele_data.Y
        weights = allele_data.weights

        n_allele = len(allele_data.Y)
        assert len(X) == n_allele
        assert len(weights) == n_allele

        if allele_name in imputed_data_dict:
            imputed_data = imputed_data_dict[allele_name]
            X_pretrain = imputed_data.X_index
            Y_pretrain = imputed_data.Y
            weights_pretrain = imputed_data.weights
        else:
            X_pretrain = None
            Y_pretrain = None
            weights_pretrain = None

        # normalize allele name to check if it's just
        allele_name = normalize_allele_name(allele_name)
        if allele_name.isdigit():
            print("Skipping allele %s" % (allele_name,))
            continue

        print("\n=== Training predictor for %s: %d samples, %d unique" % (
            allele_name,
            n_allele,
            len(set(allele_data.original_peptides))))

        model = Class1BindingPredictor.from_hyperparameters(
            name=allele_name,
            peptide_length=9,
            max_ic50=args.max_ic50,
            embedding_output_dim=args.embedding_size,
            layer_sizes=(args.hidden_layer_size,),
            activation=args.activation,
            init=args.initialization,
            dropout_probability=args.dropout,
            learning_rate=args.learning_rate)

        json_filename = allele_name + ".json"
        json_path = join(args.output_dir, json_filename)

        hdf_filename = allele_name + ".hdf"
        hdf_path = join(args.output_dir, hdf_filename)

        if exists(json_path) and exists(hdf_path) and not args.overwrite:
            print("-- already exists, skipping")
            continue

        if n_allele < args.min_samples_per_allele:
            print("-- too few data points, skipping")
            continue

        if exists(json_path):
            print("-- removing old model description %s" % json_path)
            remove(json_path)

        if exists(hdf_path):
            print("-- removing old weights file %s" % hdf_path)
            remove(hdf_path)

        model.fit(
            X=allele_data.X_index,
            Y=allele_data.Y,
            sample_weights=weights,
            X_pretrain=X_pretrain,
            Y_pretrain=Y_pretrain,
            sample_weights_pretrain=weights_pretrain,
            n_training_epochs=args.training_epochs,
            verbose=True)

        model.to_disk(
            model_json_path=json_path,
            weights_hdf_path=hdf_path,
            overwrite=args.overwrite)
