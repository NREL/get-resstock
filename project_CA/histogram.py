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
        '2023': read_csv('c:/OpenStudio/{}/2023/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        '2026': read_csv('c:/OpenStudio/{}/2026/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        '2029': read_csv('c:/OpenStudio/{}/2029/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        '2026 w/Gas Efficiency': read_csv('c:/OpenStudio/{}/2026-gaseff/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        '2029 w/Gas Efficiency': read_csv('c:/OpenStudio/{}/2029-gaseff/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id'])
}

for k, v in dfs.items():
    v['scenario'] = k

# dfs['2029'] = dfs['2029'][dfs['2029']['add_shared_water_heater.shared_water_heater_type'].isin(['boiler with storage tanks'])]
# dfs['2029 w/Gas Efficiency'] = dfs['2029 w/Gas Efficiency'][dfs['2029 w/Gas Efficiency']['add_shared_water_heater.shared_water_heater_type'].isin(['heat pump water heater with storage tanks'])]
# dfs['2029 w/Gas Efficiency'] = dfs['2029 w/Gas Efficiency'][dfs['2029 w/Gas Efficiency']['add_shared_water_heater.shared_water_heater_type'].isin(['space-heating heat pump water heater with storage tanks'])]

# dfs['Unit models 2029'] = dfs['Unit models 2029'][dfs['Unit models 2029'].index.isin(dfs['2029 w/Gas Efficiency'].index)]
# dfs['Unit models 2029 w/Gas Efficiency'] = dfs['Unit models 2029 w/Gas Efficiency'][dfs['Unit models 2029 w/Gas Efficiency'].index.isin(dfs['2029 w/Gas Efficiency'].index)]

downselect_to_boiler_baseline_and_gahp_upgrade = False
if downselect_to_boiler_baseline_and_gahp_upgrade:
    # baseline_boiler_eff = ['Natural Gas Standard']
    # upgrade_boiler_eff = ['Natural Gas Heat Pump, Standard']

    # baseline_boiler_eff = ['Natural Gas Premium', 'Natural Gas Tankless']
    # upgrade_boiler_eff = ['Natural Gas Heat Pump, Premium']

    baseline_boiler_eff = ['Natural Gas Premium, Condensing', 'Natural Gas Tankless, Condensing']
    upgrade_boiler_eff = ['Natural Gas Heat Pump, Premium, Condensing']

    dfs['2026'] = dfs['2026'][dfs['2026']['build_existing_model.water_heater_in_unit'] == 'No']
    dfs['2026 w/Gas Efficiency'] = dfs['2026 w/Gas Efficiency'][dfs['2026 w/Gas Efficiency']['build_existing_model.water_heater_in_unit'] == 'No']
    dfs['2026'] = dfs['2026'][dfs['2026']['build_existing_model.water_heater_efficiency'].isin(baseline_boiler_eff)]
    dfs['2026 w/Gas Efficiency'] = dfs['2026 w/Gas Efficiency'][dfs['2026 w/Gas Efficiency']['build_existing_model.water_heater_efficiency'].isin(upgrade_boiler_eff)]
    dfs['2026'] = dfs['2026'].loc[dfs['2026'].index.intersection(dfs['2026 w/Gas Efficiency'].index)]
    dfs['2026 w/Gas Efficiency'] = dfs['2026 w/Gas Efficiency'].loc[dfs['2026 w/Gas Efficiency'].index.intersection(dfs['2026'].index)]
    print('2026: {}'.format(dfs['2026'].shape))
    print('2026 w/Gas Efficiency: {}'.format(dfs['2026 w/Gas Efficiency'].shape))

    dfs['2029'] = dfs['2029'][dfs['2029']['build_existing_model.water_heater_in_unit'] == 'No']
    dfs['2029 w/Gas Efficiency'] = dfs['2029 w/Gas Efficiency'][dfs['2029 w/Gas Efficiency']['build_existing_model.water_heater_in_unit'] == 'No']
    dfs['2029'] = dfs['2029'][dfs['2029']['build_existing_model.water_heater_efficiency'].isin(baseline_boiler_eff)]
    dfs['2029 w/Gas Efficiency'] = dfs['2029 w/Gas Efficiency'][dfs['2029 w/Gas Efficiency']['build_existing_model.water_heater_efficiency'].isin(upgrade_boiler_eff)]
    dfs['2029'] = dfs['2029'].loc[dfs['2029'].index.intersection(dfs['2029 w/Gas Efficiency'].index)]
    dfs['2029 w/Gas Efficiency'] = dfs['2029 w/Gas Efficiency'].loc[dfs['2029 w/Gas Efficiency'].index.intersection(dfs['2029'].index)]
    print('2029: {}'.format(dfs['2029'].shape))
    print('2029 w/Gas Efficiency: {}'.format(dfs['2029 w/Gas Efficiency'].shape))

df = pd.concat(dfs.values())
df['build_existing_model.geometry_building_number_units_mf'] = df['build_existing_model.geometry_building_number_units_mf'].astype(int)
df['build_existing_model.geometry_building_number_units_mf'] = df['build_existing_model.geometry_building_number_units_mf'].astype(str)

# df['report_simulation_output.end_use_natural_gas_heating_plus_hot_water_m_btu'] = df['report_simulation_output.end_use_natural_gas_heating_m_btu'] + df['report_simulation_output.end_use_natural_gas_hot_water_m_btu']

columns = [
    'report_simulation_output.energy_use_total_m_btu',
    'report_simulation_output.fuel_use_electricity_total_m_btu',
    'report_simulation_output.fuel_use_natural_gas_total_m_btu',
    'report_simulation_output.end_use_electricity_hot_water_m_btu',
    'report_simulation_output.end_use_natural_gas_heating_m_btu',
    'report_simulation_output.end_use_natural_gas_hot_water_m_btu',
    'report_simulation_output.load_hot_water_delivered_m_btu',
    'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_total_lb',
    'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_electricity_total_lb',
    'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_natural_gas_total_lb',
    'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_natural_gas_hot_water_lb',
    'report_utility_bills.bills_total_usd',
    'report_utility_bills.bills_electricity_total_usd',
    'report_utility_bills.bills_natural_gas_total_usd',
    'add_shared_water_heater.heat_pump_count',
    'sample_weight_buildings'
]
# df = df[columns].multiply(df['sample_weight'])

# df = df[df['add_shared_water_heater.shared_water_heater_fuel_type'] != 'natural gas']
# df = df[df['build_existing_model.water_heater_in_unit'] == 'Yes']

df['All Buildings'] = 'All Buildings'
xs = ['All Buildings',
      'build_existing_model.geometry_stories',
      'build_existing_model.geometry_building_number_units_mf',
      'build_existing_model.cec_climate_zone',
      'build_existing_model.building_america_climate_zone',
      'build_existing_model.county',
      'build_existing_model.puma_metro_status',
      'build_existing_model.hot_water_fixtures']
for x in xs:
    if x == 'build_existing_model.geometry_building_number_units_mf':
        category_orders = {'build_existing_model.geometry_building_number_units_mf': ['2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '24', '30', '36', '43', '67', '116', '183', '326']}
    else:
        category_orders = {}
    for col in columns:

        df2 = df.copy()
        if not 'sample_weight' in col:
            df2[col] *= df2['sample_weight']

        fig = px.histogram(df2,
            x=x,
            y=col,
            color='scenario',
            barmode='group',
            category_orders=category_orders,
            text_auto=True)
        fig.update_layout(title_text=col)
        plotly.offline.plot(fig, filename='c:/OpenStudio/{}/{}_{}.html'.format(folder, col, x), auto_open=False)

df = df.reset_index()
# df = df.sort_values(by=['building_id', 'add_shared_water_heater.shared_water_heater_type'])
df = df.sort_values(by=['building_id', 'scenario'])
df = df.set_index('building_id')
# df = df[['scenario', 'build_existing_model.hvac_heating_efficiency', 'build_existing_model.water_heater_efficiency', 'add_shared_water_heater.shared_water_heater_type'] + xs + columns]
df = df[['scenario', 'build_existing_model.hvac_heating_efficiency', 'build_existing_model.water_heater_efficiency'] + xs + columns]
df.to_csv('c:/OpenStudio/{}/results.csv'.format(folder))