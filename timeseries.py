import os
import pandas as pd
import numpy as np
import plotly
import plotly.express as px
from pathlib import Path

csv_file_paths = [
    'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_60_default/run1/run/results_timeseries.csv',
    'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_15_default/run1/run/results_timeseries.csv',
    'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_60_SSI_half/run1/run/results_timeseries.csv',
    'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_15_SSI_half/run1/run/results_timeseries.csv',
    # 'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_60_auto/run1/run/results_timeseries.csv',
    # 'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_15_auto/run1/run/results_timeseries.csv'
]

day = '2007-01-01'
x = 'Time'
ys = ['Water Heater Source Side Inlet Temperature: Supply Boiler Loop 1 Main Storage Tank',
      'Water Heater Source Side Outlet Temperature: Supply Boiler Loop 1 Main Storage Tank',
      'Water Heater Use Side Inlet Temperature: Supply Boiler Loop 1 Main Storage Tank',
      'Water Heater Use Side Outlet Temperature: Supply Boiler Loop 1 Main Storage Tank',
      'Water Heater Source Side Inlet Temperature: Storage Loop Storage Tank',
      'Water Heater Source Side Outlet Temperature: Storage Loop Storage Tank',
      'Water Heater Use Side Inlet Temperature: Storage Loop Storage Tank',
      'Water Heater Use Side Outlet Temperature: Storage Loop Storage Tank']

def read_csv(csv_file_path, **kwargs) -> pd.DataFrame:
    default_na_values = pd._libs.parsers.STR_NA_VALUES
    df = pd.read_csv(csv_file_path, na_values=list(default_na_values - {'None'}), keep_default_na=False, **kwargs)
    return df

dfs = {}
for csv_file_path in csv_file_paths:
    scenario = Path(csv_file_path).parent.parent.parent.name
    df = read_csv(csv_file_path, index_col=[x], skiprows=[1])
    dfs[scenario] = df.copy()
    df = df[ys]    
    df = df.loc[df.index.str.contains(day)]    

    df = pd.melt(df.reset_index(), id_vars=[x], value_vars=ys)
    df['value'] = df['value'].astype(float)

    fig = px.line(df, x=x, y='value', color='variable')

    filename = 'c:/OpenStudio/get-resstock/plots/{}.html'.format(scenario)
    plotly.offline.plot(fig, filename=filename, auto_open=False)

ys = ['Energy Use: Total',
      'Fuel Use: Electricity: Total',
      'Fuel Use: Natural Gas: Total',
      'End Use: Electricity: Hot Water',
      'End Use: Natural Gas: Hot Water']

for scenario, df in dfs.items():
    for col in ys:
        if not col in df.columns:
            df[col] = 0.0
    df = df.reset_index()
    df = df[ys]
    df = df.sum().to_frame().T
    df['scenario'] = scenario
    dfs[scenario] = df

df = pd.concat(dfs.values())
df = pd.melt(df, id_vars=['scenario'], value_vars=ys)
fig = px.histogram(df, x='variable', y='value', color='scenario', barmode='group', template='plotly_white')

filename = 'c:/OpenStudio/get-resstock/plots/results_annual.html'
plotly.offline.plot(fig, filename=filename, auto_open=False)
    