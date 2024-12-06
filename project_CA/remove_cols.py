import os
import pandas as pd
import warnings
warnings.filterwarnings('ignore', category=pd.errors.DtypeWarning)
import math

def read_csv(csv_file_path, **kwargs) -> pd.DataFrame:
    default_na_values = pd._libs.parsers.STR_NA_VALUES
    df = pd.read_csv(csv_file_path, na_values=list(default_na_values - {'None'}), keep_default_na=False, **kwargs)
    return df

sample_weight_cols = ['sample_weight', 'sample_weight_elec_iou', 'sample_weight_elec_non_iou', 'sample_weight_elec', 'sample_weight_gas', 'sample_weight_gas_iou', 'sample_weight_buildings']

sample_weight_files = ['2020.csv', '2023.csv', '2026.csv', '2029.csv', '2026-gaseff.csv', '2029-gaseff.csv']

for sample_weight_file in sample_weight_files:
    df = read_csv(os.path.join('project_CA', 'sample_weights', sample_weight_file), index_col=['Building'])
    df = df.loc[:, ~df.columns.isin(sample_weight_cols)]

    df.to_csv(os.path.join('project_CA', sample_weight_file))