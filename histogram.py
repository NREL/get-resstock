import os
import pandas as pd
import numpy as np
import plotly
import plotly.express as px

# csv_file_path = 'c:/OpenStudio/get-resstock/proposed_scope_cap_cnt/results-Baseline.csv'
# csv_file_path = 'c:/OpenStudio/get-resstock/proposed_scope_cap_vol/results-Baseline.csv'
# csv_file_path = 'c:/OpenStudio/get-resstock/proposed_scope_cap_vol2/results-Baseline.csv'
# csv_file_path = 'c:/OpenStudio/get-resstock/proposed_scope_offset_vol/results-Baseline.csv'
# csv_file_path = 'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr/results-Baseline.csv'
# csv_file_path = 'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_compplus1/results-Baseline.csv'
csv_file_path = 'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_cap75perc/results-Baseline.csv'

county = 'CO, Denver County'
# county = 'AZ, Maricopa County'

# xs = ['add_shared_water_heater.heat_pump_capacity']
# xs = ['add_shared_water_heater.loop_sp_boiler']
xs = ['add_shared_water_heater.min_plr_boiler']
colors = { 'c:/OpenStudio/get-resstock/proposed_scope_cap_cnt/results-Baseline.csv': ['add_shared_water_heater.heat_pump_count'],
           'c:/OpenStudio/get-resstock/proposed_scope_cap_vol/results-Baseline.csv': ['add_shared_water_heater.tank_volume_storage_heat_pump'],
           'c:/OpenStudio/get-resstock/proposed_scope_cap_vol2/results-Baseline.csv': ['add_shared_water_heater.tank_volume_storage_heat_pump'],
           'c:/OpenStudio/get-resstock/proposed_scope_offset_vol/results-Baseline.csv': ['add_shared_water_heater.tank_volume_storage_heat_pump'],
           'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr/results-Baseline.csv': ['add_shared_water_heater.deadband_heat_pump'],
           'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_compplus1/results-Baseline.csv': ['add_shared_water_heater.deadband_heat_pump'],
           'c:/OpenStudio/get-resstock/proposed_scope_sp_db_plr_cap75perc/results-Baseline.csv': ['add_shared_water_heater.deadband_heat_pump'] }[csv_file_path]
ys = ['report_simulation_output.energy_use_total_m_btu',
      'report_simulation_output.fuel_use_electricity_total_m_btu',
      'report_simulation_output.fuel_use_natural_gas_total_m_btu']
filters = ['build_existing_model.county']
# other_var = None
other_var = 'add_shared_water_heater.tank_setpoint_storage_heat_pump'

def read_csv(csv_file_path, **kwargs) -> pd.DataFrame:
    default_na_values = pd._libs.parsers.STR_NA_VALUES
    df = pd.read_csv(csv_file_path, na_values=list(default_na_values - {'None'}), keep_default_na=False, **kwargs)
    df = df[df['completed_status'] == 'Success']
    return df

df = read_csv(csv_file_path, index_col=['building_id'])
df = df[xs + ys + colors + filters + [other_var]]
df = df[df['build_existing_model.county'] == county]

zs = [None]
if not other_var is None:
    zs = df[other_var].unique()

for z in zs:
    tmp_df = df.copy()
    if not z is None:
        tmp_df = tmp_df[tmp_df[other_var]==z]
    for y in ys:
        fig = px.histogram(tmp_df,
            x=xs[0],
            y=y,
            color=colors[0],
            barmode='group',
            template='plotly_white')
        fig.update_xaxes(type='category')
        fig.update_layout(title_text=y)

        filename = 'c:/OpenStudio/get-resstock/plots/{}.html'.format(y)
        if not z is None:
            os.makedirs('c:/OpenStudio/get-resstock/plots/{}'.format(z), exist_ok=True)
            filename = 'c:/OpenStudio/get-resstock/plots/{}/{}.html'.format(z, y)
        plotly.offline.plot(fig, filename=filename, auto_open=False)
