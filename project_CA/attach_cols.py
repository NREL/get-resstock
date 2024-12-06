import os
import pandas as pd
import warnings
warnings.filterwarnings('ignore', category=pd.errors.DtypeWarning)
import math

def read_csv(csv_file_path, **kwargs) -> pd.DataFrame:
    default_na_values = pd._libs.parsers.STR_NA_VALUES
    df = pd.read_csv(csv_file_path, na_values=list(default_na_values - {'None'}), keep_default_na=False, **kwargs)
    return df

sample_weight_cols = ['add_shared_water_heater.heat_pump_count', 'sample_weight', 'sample_weight_elec_iou', 'sample_weight_elec_non_iou', 'sample_weight_elec', 'sample_weight_gas', 'sample_weight_gas_iou', 'sample_weight_buildings']

# results_csv_file = 'results_up00_COP1pt0_scenario'
results_csv_file = 'results_up00_COP1pt293_scenario'
sample_weight_files = ['2020_sample_weight.csv', '2023_sample_weight.csv', '2026_sample_weight.csv', '2029_sample_weight.csv', '2026-gaseff_sample_weight.csv', '2029-gaseff_sample_weight.csv']

for i, sample_weight_file in enumerate(sample_weight_files):
    df_results = read_csv(os.path.join('project_CA', results_csv_file + '{}.csv'.format(i+1)), index_col=['building_id'])
    df_samples = read_csv(os.path.join('project_CA', sample_weight_file), index_col=['Building'])
    df_samples['add_shared_water_heater.heat_pump_count'] = df_samples['Geometry Building Number Units MF'].apply(lambda x: min(math.ceil(x / 20.0), 5))
    df_samples = df_samples[sample_weight_cols]

    df = df_results.join(df_samples)
    df.to_csv(os.path.join('project_CA', results_csv_file + '{}_wt.csv'.format(i+1)))