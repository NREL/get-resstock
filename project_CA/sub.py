import os
import pandas as pd
import warnings
warnings.filterwarnings('ignore', category=pd.errors.DtypeWarning)

n_samples = 5000

def read_csv(csv_file_path, **kwargs) -> pd.DataFrame:
    default_na_values = pd._libs.parsers.STR_NA_VALUES
    df = pd.read_csv(csv_file_path, na_values=list(default_na_values - {'None'}), keep_default_na=False, **kwargs)
    return df

files = {'1': '2020.csv', '2': '2023.csv', '3': '2026.csv', '4': '2029.csv', '5': '2026-gaseff.csv', '6': '2029-gaseff.csv'}

for scenario, file in files.items():
    df = read_csv(os.path.join('project_CA', file), index_col=['Building'])
    df = df.sample(n_samples)
    df.to_csv(os.path.join('project_CA', 'sub_{}'.format(file)))