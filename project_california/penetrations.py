import os
import pandas as pd

n_buildings_represented = 136569411 # from yml

# load
dir = 'c:/OpenStudio/get-resstock/california_baseline'
df = pd.read_csv(os.path.join(dir, 'buildstock.csv'))
n_datapoints = df.shape[0]

# downselect states
states = df['State'].unique()
states = ['CA']
df = df[df['State'].isin(states)]
new_n_buildings_represented = df.shape[0] * (n_buildings_represented / n_datapoints)
print('\nDwelling units: {} ({}%)\n'.format(new_n_buildings_represented, round(new_n_buildings_represented * 100.0 / n_buildings_represented, 1)))

# export all column names
cols = pd.DataFrame(df.columns.to_list(), columns=["columns"])
cols_path = os.path.join(dir, 'columns.csv')
if not os.path.exists(cols_path):
  cols.to_csv(cols_path, index=False)

# print penetrations
penetrations = {
                'HVAC Heating Efficiency': [],
                'HVAC Cooling Efficiency': [],
                'Water Heater Efficiency': [],
                'Generation And Emissions Assessment Region': []
               }
for col, deps in penetrations.items():
  if deps:
    value_count = df.groupby(deps)[col].value_counts(normalize=True)
  else:
    value_count = df[col].value_counts(normalize=True)

  value_count.to_csv(os.path.join(dir, '{}.csv'.format(col)))
