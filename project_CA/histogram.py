import os
import pandas as pd
import numpy as np
import plotly
import plotly.express as px
import plotly.graph_objects as go
import warnings
warnings.filterwarnings('ignore', category=pd.errors.DtypeWarning)
warnings.filterwarnings('ignore', category=pd.errors.PerformanceWarning)

folder = 'gahp_cop_1pt0_series_4'

def read_csv(csv_file_path, **kwargs) -> pd.DataFrame:
    default_na_values = pd._libs.parsers.STR_NA_VALUES
    df = pd.read_csv(csv_file_path, na_values=list(default_na_values - {'None'}), keep_default_na=False, **kwargs)
    df = df[df['completed_status'] == 'Success']
    return df

def get_min_max(x_col, y_col, min_value, max_value):
    try:
        if 0.9 * np.min([x_col.min(), y_col.min()]) < min_value:
            min_value = 0.9 * np.min([x_col.min(), y_col.min()])
    except BaseException:
        pass
    try:
        if 1.1 * np.max([x_col.max(), y_col.max()]) > max_value:
            max_value = 1.1 * np.max([x_col.max(), y_col.max()])
    except BaseException:
        pass

    return (min_value, max_value)

dfs = {
        # 'Unit models 2029': read_csv('c:/OpenStudio/{}/UnitModelBaseline/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # 'Unit models 2029 w/Gas Efficiency': read_csv('c:/OpenStudio/{}/UnitModelFeature/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # '2020': read_csv('c:/OpenStudio/{}/2020/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
        # '2023': read_csv('c:/OpenStudio/{}/2023/results_csvs/results-Baseline.csv'.format(folder), index_col=['building_id']),
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

downselect_to_boiler_baseline_and_gahp_upgrade = True
if downselect_to_boiler_baseline_and_gahp_upgrade:

    for scenario in ['2026', '2029']:
        print('{}: total buildings: {}'.format(scenario, dfs[scenario]['sample_weight_buildings'].sum()))
        bs = []
        us = []
        for baseline_boiler_eff, upgrade_boiler_eff in [[['Natural Gas Standard'], ['Natural Gas Heat Pump, Standard']],
                                                        [['Natural Gas Premium', 'Natural Gas Tankless'], ['Natural Gas Heat Pump, Premium']],
                                                        [['Natural Gas Premium, Condensing', 'Natural Gas Tankless, Condensing'], ['Natural Gas Heat Pump, Premium, Condensing']]]:
        
            b = dfs[scenario].copy()
            u = dfs['{} w/Gas Efficiency'.format(scenario)].copy()

            b = b[b['build_existing_model.water_heater_in_unit'] == 'No']
            u = u[u['build_existing_model.water_heater_in_unit'] == 'No']

            b = b[b['build_existing_model.water_heater_efficiency'].isin(baseline_boiler_eff)]
            u = u[u['build_existing_model.water_heater_efficiency'].isin(upgrade_boiler_eff)]

            b = b.loc[b.index.intersection(u.index)]
            u = u.loc[u.index.intersection(b.index)]

            print('{}: {}: {}'.format(upgrade_boiler_eff, scenario, b.shape))
            print('{}: {} w/Gas Efficiency: {}'.format(upgrade_boiler_eff, scenario, u.shape))

            bs.append(b)
            us.append(u)
        dfs[scenario] = pd.concat(bs)
        dfs['{} w/Gas Efficiency'.format(scenario)] = pd.concat(us)
        print('{}: datapoints: {}'.format(scenario, dfs[scenario].shape[0]))
        print('{}: buildings: {}'.format(scenario, dfs[scenario]['sample_weight_buildings'].sum()))

df = pd.concat(dfs.values())
df['build_existing_model.geometry_building_number_units_mf'] = df['build_existing_model.geometry_building_number_units_mf'].astype(int)
df['build_existing_model.geometry_building_number_units_mf'] = df['build_existing_model.geometry_building_number_units_mf'].astype(str)
df['build_existing_model.cec_climate_zone'] = df['build_existing_model.cec_climate_zone'].astype(int)
df['build_existing_model.cec_climate_zone'] = df['build_existing_model.cec_climate_zone'].astype(str)
df['build_existing_model.geometry_stories'] = df['build_existing_model.geometry_stories'].astype(int)
df['build_existing_model.geometry_stories'] = df['build_existing_model.geometry_stories'].astype(str)
df['build_existing_model.geometry_building_number_units_mf_bins'] = df['build_existing_model.geometry_building_number_units_mf']
df['build_existing_model.geometry_building_number_units_mf_bins'] = df['build_existing_model.geometry_building_number_units_mf_bins'].map({
    '10': '10 - 19',
    '11': '10 - 19',
    '12': '10 - 19',
    '13': '10 - 19',
    '14': '10 - 19',
    '15': '10 - 19',
    '16': '10 - 19',
    '17': '10 - 19',
    '18': '10 - 19',
    '19': '10 - 19',
    '20': '20 - 116',
    '24': '20 - 116',
    '30': '20 - 116',
    '36': '20 - 116',
    '43': '20 - 116',
    '67': '20 - 116',
    '116': '20 - 116',
    '183': '183 - 326',
    '326': '183 - 326'})

# df['report_simulation_output.end_use_natural_gas_heating_plus_hot_water_m_btu'] = df['report_simulation_output.end_use_natural_gas_heating_m_btu'] + df['report_simulation_output.end_use_natural_gas_hot_water_m_btu']
df['report_simulation_output.end_use_hot_water_m_btu'] = df['report_simulation_output.end_use_electricity_hot_water_m_btu'] + df['report_simulation_output.end_use_natural_gas_hot_water_m_btu']

columns = [
    # 'report_simulation_output.energy_use_total_m_btu',
    # 'report_simulation_output.fuel_use_electricity_total_m_btu',
    # 'report_simulation_output.fuel_use_natural_gas_total_m_btu',
    # 'report_simulation_output.end_use_electricity_hot_water_m_btu',
    # 'report_simulation_output.end_use_natural_gas_heating_m_btu',
    # 'report_simulation_output.end_use_natural_gas_hot_water_m_btu',
    'report_simulation_output.end_use_hot_water_m_btu',
    # 'report_simulation_output.load_hot_water_delivered_m_btu',
    # 'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_total_lb',
    # 'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_electricity_total_lb',
    # 'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_natural_gas_total_lb',
    # 'report_simulation_output.emissions_co_2_e_lrmer_mid_case_15_natural_gas_hot_water_lb',
    # 'report_utility_bills.bills_total_usd',
    # 'report_utility_bills.bills_electricity_total_usd',
    # 'report_utility_bills.bills_natural_gas_total_usd',
    # 'add_shared_water_heater.heat_pump_count',
    # 'sample_weight_buildings'
]
# df = df[columns].multiply(df['sample_weight'])

# df = df[df['add_shared_water_heater.shared_water_heater_fuel_type'] != 'natural gas']
# df = df[df['build_existing_model.water_heater_in_unit'] == 'Yes']

# df['All Buildings'] = 'All Buildings'
xs = [
      # 'All Buildings',
      # 'build_existing_model.geometry_stories',
      # 'build_existing_model.geometry_building_number_units_mf',
      'build_existing_model.geometry_building_number_units_mf_bins',
      # 'build_existing_model.cec_climate_zone',
      # 'build_existing_model.building_america_climate_zone',
      # 'build_existing_model.county',
      # 'build_existing_model.puma_metro_status',
      # 'build_existing_model.hot_water_fixtures'
]

xs_map = {'build_existing_model.geometry_stories': 'Number of Stories',
          'build_existing_model.geometry_building_number_units_mf': 'Number of Dwelling Units',
          'build_existing_model.geometry_building_number_units_mf_bins': 'Number of Dwelling Units',
          'build_existing_model.cec_climate_zone': 'CEC Climate Zone',
          'build_existing_model.county': 'County',
          'build_existing_model.hot_water_fixtures': 'Hot Water Fixtures',
          'All Buildings': 'All Buildings'}

histogram = False
for x in xs:
    if x == 'build_existing_model.geometry_building_number_units_mf':
        category_orders = {'build_existing_model.geometry_building_number_units_mf': ['2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '24', '30', '36', '43', '67', '116', '183', '326']}
    elif x == 'build_existing_model.geometry_building_number_units_mf_bins':
        category_orders = {'build_existing_model.geometry_building_number_units_mf_bins': ['10 - 19', '20 - 116', '183 - 326']}
    elif x == 'build_existing_model.cec_climate_zone':
        category_orders = {'build_existing_model.cec_climate_zone': ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16']}
    elif x == 'build_existing_model.geometry_stories':
        category_orders = {'build_existing_model.geometry_stories': ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16', '20', '21', '35']}
    else:
        category_orders = {}
    for col in columns:

        df2 = df.copy()
        if not 'sample_weight' in col:
            df2[col] *= df2['sample_weight']

        if histogram:
            df2 = df2.sort_values(by='scenario')
            fig = px.histogram(df2,
                x=x,
                y=col,
                color='scenario',
                barmode='group',
                category_orders=category_orders,
                template='plotly_white',
                # text_auto=True,
                labels={x: xs_map[x], 'scenario': 'Projection Scenario'})
            fig.update_layout(yaxis_title= 'End Use Hot Water (MBtu)')
            fig.update_layout(title_text=col)
            fig.update_layout(
                title={
                    'text': 'Hot Water (Electricity + Natural Gas)',
                    'y': 0.975,
                    'x': 0.5,
                    'xanchor': 'center',
                    'yanchor': 'top'})
            fig.update_layout(legend=dict(
                yanchor="top",
                y=0.99,
                xanchor="left",
                x=0.9,
                borderwidth=0.5
            ))
            fig.update_layout(
                font=dict(
                    size=18,
                )
            )
            fig.update_traces(marker_line_width=0.75, marker_line_color="black")
            plotly.offline.plot(fig, filename='c:/OpenStudio/{}/{}_{}.html'.format(folder, col, x), auto_open=False)
        else:
            for year in ['2026', '2029']:
                df3 = df2.copy()
                df3 = df3.loc[df3['scenario'].isin([year, '{} w/Gas Efficiency'.format(year)])]
                df3 = df3[['scenario', x, col]].reset_index()
                # df3 = df3[df3['building_id'] != 1726] # FIXME: outlier?
                df3 = df3.pivot(index=['building_id', x], columns='scenario', values=col).reset_index()
                # df3.to_csv('test_{}.csv'.format(year))
                fig = px.scatter(df3,
                    x=year,
                    y='{} w/Gas Efficiency'.format(year),
                    color=x, # FIXME
                    category_orders=category_orders,
                    template='plotly_white',
                    labels={year: '{} (MBtu)'.format(year), '{} w/Gas Efficiency'.format(year): '{} w/Gas Efficiency (MBtu)'.format(year), x: xs_map[x]})
                fig.update_layout(
                    title={
                        'text': 'Hot Water (Electricity + Natural Gas)',
                        'y': 0.975,
                        'x': 0.5,
                        'xanchor': 'center',
                        'yanchor': 'top'})
                fig.update_layout(legend=dict(
                    yanchor="top",
                    y=0.99,
                    xanchor="left",
                    x=0.75,
                    borderwidth=0.5
                ))
                fig.update_layout(
                    font=dict(
                        size=18,
                    )
                )
                fig.update_traces(mode='markers', marker_line_width=1, marker_size=10)
                min_value, max_value = get_min_max(df3[year], df3['{} w/Gas Efficiency'.format(year)], 0, 0)
                fig.add_trace(go.Scatter(x=[min_value, max_value], y=[min_value, max_value],
                                         line=dict(color='black', width=1), mode='lines',
                                         showlegend=True, name='0% Savings'), row=1, col=1)
                fig.add_trace(go.Scatter(x=[min_value, max_value], y=[0.8 * min_value, 0.8 * max_value],
                                         line=dict(color='black', dash='dash', width=1), mode='lines',
                                         showlegend=True, name='- 20% Savings'), row=1, col=1)
                fig.add_trace(go.Scatter(x=[min_value, max_value], y=[0.6 * min_value, 0.6 * max_value],
                                         line=dict(color='black', dash='dot', width=1), mode='lines',
                                         showlegend=True, name='- 40% Savings'), row=1, col=1)
                fig.add_trace(go.Scatter(x=[min_value, max_value], y=[0.4 * min_value, 0.4 * max_value],
                                         line=dict(color='black', dash='dashdot', width=1), mode='lines',
                                         showlegend=True, name='- 60% Savings'), row=1, col=1)
                fig.update_xaxes(constrain='domain')
                fig.update_yaxes(scaleanchor= 'x')                
                plotly.offline.plot(fig, filename='c:/OpenStudio/{}/{}_{}_{}.html'.format(folder, col, x, year), auto_open=False)

df = df.reset_index()
# df = df.sort_values(by=['building_id', 'add_shared_water_heater.shared_water_heater_type'])
df = df.sort_values(by=['building_id', 'scenario'])
df = df.set_index('building_id')
# df = df[['scenario', 'build_existing_model.hvac_heating_efficiency', 'build_existing_model.water_heater_efficiency', 'add_shared_water_heater.shared_water_heater_type'] + xs + columns]
df = df[['scenario', 'build_existing_model.hvac_heating_efficiency', 'build_existing_model.water_heater_efficiency'] + xs + columns]
df.to_csv('c:/OpenStudio/{}/results.csv'.format(folder))
