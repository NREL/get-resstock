import os
import pandas as pd
import numpy as np
import plotly
import plotly.express as px
import warnings
warnings.filterwarnings('ignore', category=pd.errors.DtypeWarning)
warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

folder = 'gahp_cop_1pt0_series_2'

def read_csv(csv_file_path, **kwargs) -> pd.DataFrame:
    default_na_values = pd._libs.parsers.STR_NA_VALUES
    df = pd.read_csv(csv_file_path, na_values=list(default_na_values - {'None'}), keep_default_na=False, **kwargs)
    df = df[df['completed_status'] == 'Success']
    return df

dfs = {
        # 'Unit models 2029': read_csv('c:/OpenStudio/{}/UnitModelBaseline/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # 'Unit models 2029 w/Gas Efficiency': read_csv('c:/OpenStudio/{}/UnitModelFeature/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        '2020': read_csv('c:/OpenStudio/{}/2020/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # '2023': read_csv('c:/OpenStudio/{}/2023/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # '2026': read_csv('c:/OpenStudio/{}/2026/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # '2029': read_csv('c:/OpenStudio/{}/2029/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # '2026 w/Gas Efficiency': read_csv('c:/OpenStudio/{}/2026-gaseff/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # '2029 w/Gas Efficiency': read_csv('c:/OpenStudio/{}/2029-gaseff/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id'])
}

for k, v in dfs.items():
    v['scenario'] = k

df = dfs['2020'].copy()
df = df[['build_existing_model.geometry_stories', 'sample_weight', 'sample_weight_buildings']]
df = df.groupby(['build_existing_model.geometry_stories']).sum()
df.to_csv('geometry_stories.csv')

df = dfs['2020'].copy()
df = df[['build_existing_model.cec_climate_zone', 'sample_weight', 'sample_weight_buildings']]
df = df.groupby(['build_existing_model.cec_climate_zone']).sum()
df.to_csv('cec_climate_zone.csv')