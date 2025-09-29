# frozen_string_literal: true

require_relative 'resources/constants.rb'
require_relative 'resources/curves.rb'
require_relative 'resources/hxs.rb'
require_relative 'resources/loops.rb'
require_relative 'resources/pipes.rb'
require_relative 'resources/pumps.rb'
require_relative 'resources/setpoints.rb'
require_relative 'resources/supply.rb'
require_relative 'resources/tanks.rb'

# start the measure
class AddSharedWaterHeater < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return 'AddSharedWaterHeater'
  end

  # human readable description
  def description
    return "Replace in-unit water heaters and boilers with shared '#{Constant::WaterHeaterTypeHeatPump}', '#{Constant::WaterHeaterTypeBoiler}', '#{Constant::WaterHeaterTypeCombiHeatPump}', or '#{Constant::WaterHeaterTypeCombiBoiler}'. This measure assumes that water use connections (and optionally baseboards) already exist in the model."
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Replace existing in-unit hot water loops and associated EMS objects. Add new shared plant loop(s) with water heating (and optionally space-heating) components, including storage and swing tanks.'
  end

  # define the arguments that the user will input
  def arguments(model) # rubocop:disable Lint/UnusedMethodArgument
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Get defaulted hpxml
    hpxml_path = File.expand_path('../home.xml') # this is the defaulted hpxml
    if File.exist?(hpxml_path)
      hpxml = HPXML.new(hpxml_path: hpxml_path)
      hpxml_bldgs = hpxml.buildings
      hpxml_bldg = hpxml_bldgs[0]
    else
      runner.registerWarning("AddSharedWaterHeater: Could not find '#{hpxml_path}'.")
      return true
    end
    # return true # FIXME

    # Shared water heater properties
    shared_water_heater_type = hpxml_bldg.header.extension_properties['shared_water_heater_type']
    shared_water_heater_fuel_type = hpxml_bldg.header.extension_properties['shared_water_heater_fuel_type']
    shared_boiler_efficiency_afue = hpxml_bldg.header.extension_properties['shared_boiler_efficiency_afue'].to_f

    # Other properties
    num_stories = hpxml_bldg.header.extension_properties['geometry_num_floors_above_grade'].to_f
    has_double_loaded_corridor = hpxml_bldg.header.extension_properties['geometry_corridor_position']
    cec_climate_zone = hpxml_bldg.header.extension_properties['cec_climate_zone']
    coil_type = hpxml_bldg.header.extension_properties['coil_type']
    dhw_loop_sp = hpxml_bldg.header.extension_properties['dhw_loop_sp'].to_f
    space_htg_load_frac = hpxml_bldg.header.extension_properties['space_htg_load_frac'].to_f

    # Include Swing Tank
    include_swing_tank = false
    if shared_water_heater_type.include?(Constant::HeatPumpWaterHeater) &&
       shared_water_heater_fuel_type == HPXML::FuelTypeElectricity
      include_swing_tank = true
      if shared_boiler_efficiency_afue > 0
        include_swing_tank = false
      end
    end

    # Skip measure if no shared heating system
    if shared_water_heater_type == 'none'
      runner.registerAsNotApplicable('AddSharedWaterHeater: Shared water heater type not indicated. Skipping the measure...')
      return true
    end

    # Building -level information
    unit_multipliers = hpxml_bldgs.collect { |hpxml_bldg| hpxml_bldg.building_construction.number_of_units }
    num_units = unit_multipliers.sum
    num_beds = hpxml_bldgs.collect { |hpxml_bldg| hpxml_bldg.building_construction.number_of_units * hpxml_bldg.building_construction.number_of_bedrooms }.sum
    num_occs = hpxml_bldgs.collect { |hpxml_bldg| hpxml_bldg.building_construction.number_of_units * hpxml_bldg.building_occupancy.number_of_residents }.sum

    # Capacities
    boiler_capacity, heat_pump_capacity, water_heating_capacity, space_heating_capacity = Supply.get_supply_capacities(model, shared_water_heater_type, shared_water_heater_fuel_type, coil_type)

    # Counts
    boiler_count, heat_pump_count = Supply.get_supply_counts(shared_water_heater_type, shared_water_heater_fuel_type, num_units, include_swing_tank, water_heating_capacity, space_heating_capacity, space_htg_load_frac, heat_pump_capacity)

    # Mains Temp
    site_water_mains_temperature = model.getSiteWaterMainsTemperature
    temperature_schedule = site_water_mains_temperature.temperatureSchedule.get
    avg_tmains = UnitConversions.convert(temperature_schedule.to_ScheduleInterval.get.timeSeries.averageValue, 'C', 'F')
    t_cold = avg_tmains

    # Tanks
    boiler_storage_tank_volume = Tanks.get_boiler_storage_volume(num_units, num_occs)
    heat_pump_storage_tank_volume = Tanks.get_heat_pump_storage_volume(shared_water_heater_type, avg_tmains)
    swing_tank_volume = Tanks.get_swing_volume(include_swing_tank, num_units)

    # Setpoints
    dhw_loop_des, boiler_loop_des, heat_pump_loop_des, storage_loop_des, space_heating_loop_des = Setpoints.get_loop_designs(shared_water_heater_type)
    boiler_loop_sp, heat_pump_loop_sp, storage_loop_sp, space_heating_loop_sp = Setpoints.get_loop_setpoints(shared_water_heater_type, dhw_loop_sp)

    # Water heating rate = m_dot * cp * deltaT / efficiency (to be compared with burner capacity later)
    t_hot = boiler_loop_sp
    cumulative_hw_volume = boiler_storage_tank_volume * 0.7
    average_hw_flow = cumulative_hw_volume / 60.0
    q_hw = 0
    if shared_boiler_efficiency_afue > 0
      q_hw = average_hw_flow * 60.0 * 8.4 * (t_hot - t_cold) / shared_boiler_efficiency_afue
    end
    boiler_capacity = q_hw # FIXME: set this? looks to be about half our current approach

    # Pumps
    # pump_head = Pumps.get_rated_head(shared_water_heater_type)
    # pump_w = Pumps.get_rated_power_consumption(shared_water_heater_type)
    pump_head = nil # FIXME
    pump_w = nil # FIXME

    # Pipes
    supply_length, return_length = Pipes.get_recirc_supply_return_lengths(hpxml_bldg, num_units, num_stories, has_double_loaded_corridor)
    supply_ins_r, return_ins_r = Pipes.get_recirc_ins_r_value()

    # Flows
    dhw_loop_gpm = UnitConversions.convert(0.01, 'm^3/s', 'gal/min') * num_units # FIXME: this is what OS-HPXML has for this loop
    dhw_pump_gpm, swing_tank_capacity = Pipes.calc_recirc_flow_rate(hpxml_bldgs, supply_length, supply_ins_r, swing_tank_volume)

    supply_loop_gpm, storage_loop_gpm, space_heating_loop_gpm = Loops.get_flow_rates(shared_water_heater_type)
    supply_pump_gpm, storage_pump_gpm, space_heating_pump_gpm = Pumps.get_flow_rates(shared_water_heater_type)

    # Add Setpoint Schedules
    dhw_loop_sp_schedule = Setpoints.create_schedule(model, dhw_loop_sp)
    boiler_loop_sp_schedule = Setpoints.create_schedule(model, boiler_loop_sp)
    heat_pump_loop_sp_schedule = Setpoints.create_schedule(model, heat_pump_loop_sp)
    storage_loop_sp_schedule = Setpoints.create_schedule(model, storage_loop_sp)
    space_heating_loop_sp_schedule = Setpoints.create_schedule(model, space_heating_loop_sp)

    # Add Loops
    dhw_loop = Loops.create_plant(model, 'DHW Loop', dhw_loop_des, 10.0, dhw_loop_gpm, num_units)
    boiler_loops = {}
    (1..boiler_count).to_a.each do |i|
      boiler_loop = Loops.create_plant(model, "Supply Boiler Loop #{i}", boiler_loop_des, 20.0, supply_loop_gpm)
      boiler_loops[boiler_loop] = []
    end
    heat_pump_loops = {}
    if shared_water_heater_fuel_type != HPXML::FuelTypeElectricity
      (1..heat_pump_count).to_a.each do |i|
        heat_pump_loop = Loops.create_plant(model, "Supply Heat Pump Loop #{i}", heat_pump_loop_des, 20.0, supply_loop_gpm)
        heat_pump_loops[heat_pump_loop] = []
      end
    end
    storage_loop = Loops.create_plant(model, 'Storage Loop', storage_loop_des, 20.0, storage_loop_gpm)
    if shared_water_heater_type.include?(Constant::SpaceHeating)
      space_heating_loop = Loops.create_plant(model, 'Space Heating Loop', space_heating_loop_des, 20.0, space_heating_loop_gpm)
    end

    supply_loops = heat_pump_loops.merge(boiler_loops)

    hp_in_series = true # false means in parallel
    boiler_on_hp_outlet = hp_in_series

    # Add Adiabatic Pipes
    Pipes.create_adiabatic_supply(model, dhw_loop)
    # Pipes.create_adiabatic_demand(model, dhw_loop)
    boiler_loops.each do |supply_loop, _|
      Pipes.create_adiabatic_supply(model, supply_loop)
      Pipes.create_adiabatic_demand(model, supply_loop)
    end
    heat_pump_loops.each do |supply_loop, _|
      Pipes.create_adiabatic_supply(model, supply_loop)
      Pipes.create_adiabatic_demand(model, supply_loop)
    end
    if boiler_on_hp_outlet
      Pipes.create_adiabatic_supply(model, storage_loop)
      Pipes.create_adiabatic_demand(model, storage_loop)
    end
    if shared_water_heater_type.include?(Constant::SpaceHeating)
      Pipes.create_adiabatic_supply(model, space_heating_loop)
      Pipes.create_adiabatic_demand(model, space_heating_loop)
    end

    # Add Non-Adiabatic Pipes
    Pipes.create_indoor(model, dhw_loop, supply_length, return_length, supply_ins_r, return_ins_r, num_units)

    # Add Pumps
    dhw_pump_w = pump_w
    Pumps.create_constant_speed(model, dhw_loop, dhw_pump_gpm, pump_head, pump_w, 'Continuous')
    supply_pump_w = pump_w
    supply_loops.each do |supply_loop, _|
      Pumps.create_constant_speed(model, supply_loop, supply_pump_gpm, pump_head, supply_pump_w)
    end
    storage_pump_w = 0.0
    Pumps.create_constant_speed(model, storage_loop, storage_pump_gpm, pump_head, storage_pump_w)
    space_heating_pump_w = pump_w
    Pumps.create_constant_speed(model, space_heating_loop, space_heating_pump_gpm, pump_head, pump_w)

    # Add Setpoint Managers
    Setpoints.create_manager(model, dhw_loop, dhw_loop_sp_schedule)
    boiler_loops.each do |supply_loop, _|
      Setpoints.create_manager(model, supply_loop, boiler_loop_sp_schedule)
    end
    heat_pump_loops.each do |supply_loop, _|
      Setpoints.create_manager(model, supply_loop, heat_pump_loop_sp_schedule)
    end
    if boiler_on_hp_outlet
      Setpoints.create_manager(model, storage_loop, storage_loop_sp_schedule)
    end
    Setpoints.create_manager(model, space_heating_loop, space_heating_loop_sp_schedule)

    # Add Tank(s) or HX(s)
    prev_component = nil

    heat_pump_loops.each_with_index do |(supply_loop, components), _i|
      component = Tanks.create_storage(model, supply_loop, storage_loop, heat_pump_storage_tank_volume, prev_component, "#{supply_loop.name} Main Storage Tank", shared_water_heater_fuel_type, heat_pump_loop_sp, hp_in_series)
      components << component
      prev_component = components[0]
    end

    t_amb = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Site Outdoor Air Drybulb Temperature')
    t_amb.setName('TambC')
    t_amb.setKeyName('*')

    if heat_pump_loops.empty? # we only have HP loops when HP is gas-fired
      (1..heat_pump_count).to_a.each do |_i|
        component = Supply.create_component(model, shared_water_heater_type, shared_water_heater_fuel_type, storage_loop, heat_pump_capacity, shared_boiler_efficiency_afue, t_amb, num_units, coil_type, prev_component, heat_pump_loop_sp)
        prev_component = component
      end
    end

    boiler_loops.each do |supply_loop, components|
      storage_tank = Tanks.create_storage(model, supply_loop, storage_loop, boiler_storage_tank_volume, prev_component, "#{supply_loop.name} Main Storage Tank", shared_water_heater_fuel_type, boiler_loop_sp, true, boiler_on_hp_outlet)
      storage_tank.additionalProperties.setFeature('ObjectType', Constant::ObjectNameSharedWaterHeater) # Used by reporting measure

      components << storage_tank
      prev_component = components[0]
    end

    if !boiler_on_hp_outlet
      Pipes.create_adiabatic_supply(model, storage_loop)
      Pipes.create_adiabatic_demand(model, storage_loop)
      Setpoints.create_manager(model, storage_loop, storage_loop_sp_schedule)
    end

    # Add Swing Tank
    swing_tank_capacity /= 2 # FIXME
    swing_tank = Tanks.create_swing(model, storage_loop, swing_tank_volume, prev_component, "#{storage_loop.name} Main Swing Tank", swing_tank_capacity, heat_pump_loop_sp, hp_in_series)
    swing_tank.additionalProperties.setFeature('ObjectType', Constant::ObjectNameSharedWaterHeater) if !swing_tank.nil? # Used by reporting measure

    # Add Heat Exchangers
    HeatExchangers.create(model, storage_loop, dhw_loop, 'DHW Heat Exchanger', nil)
    if shared_water_heater_type.include?(Constant::SpaceHeating)
      space_heating_hx = HeatExchangers.create(model, storage_loop, space_heating_loop, 'Space Heating Heat Exchanger', nil)
    end

    # Add Supply Components
    boiler_loops.each do |supply_loop, components|
      component = Supply.create_component(model, Constant::Boiler, shared_water_heater_fuel_type, supply_loop, boiler_capacity, shared_boiler_efficiency_afue, t_amb, num_units, coil_type, nil)
      components << component
    end

    heat_pump_loops.each do |supply_loop, components|
      component = Supply.create_component(model, shared_water_heater_type, shared_water_heater_fuel_type, supply_loop, heat_pump_capacity, shared_boiler_efficiency_afue, t_amb, num_units, coil_type, heat_pump_loop_sp, nil)
      components << component
    end

    # Re-connect WaterUseConections (in series) with PipeIndoors
    reconnected_water_heatings = Loops.reconnect_water_use_connections(model, dhw_loop)

    # Re-connect CoilHeatingWaterBaseboards (in parallel)
    reconnected_space_heatings = Loops.reconnect_space_water_coils(model, space_heating_loop)

    # Remove Existing
    remove_loops(runner, model, shared_water_heater_type)
    remove_ems(runner, model, shared_water_heater_type)
    remove_other(runner, model)

    # Register values
    runner.registerValue('shared_water_heater_type', shared_water_heater_type)
    runner.registerValue('shared_water_heater_fuel_type', shared_water_heater_fuel_type)
    runner.registerValue('unit_models', hpxml_bldgs.size)
    runner.registerValue('unit_multipliers', unit_multipliers.join(','))
    runner.registerValue('num_units', num_units)
    runner.registerValue('num_beds', num_beds)
    runner.registerValue('boiler_count', boiler_count)
    runner.registerValue('boiler_capacity_w', boiler_capacity)
    runner.registerValue('boiler_capacity_q_hw_w', q_hw)
    runner.registerValue('heat_pump_count', heat_pump_count)
    runner.registerValue('heat_pump_capacity', heat_pump_capacity)
    runner.registerValue('length_ft_supply', supply_length)
    runner.registerValue('length_ft_return', return_length)
    runner.registerValue('loop_gpm_supply', supply_loop_gpm) if !supply_loop_gpm.nil?
    runner.registerValue('loop_gpm_storage', storage_loop_gpm) if !storage_loop_gpm.nil?
    runner.registerValue('loop_gpm_dhw', dhw_loop_gpm) if !dhw_loop_gpm.nil?
    runner.registerValue('loop_gpm_space_heating', space_heating_loop_gpm) if !space_heating_loop_gpm.nil?
    runner.registerValue('loop_sp_boiler', boiler_loop_sp) if !boiler_loop_sp.nil?
    runner.registerValue('loop_sp_heat_pump', heat_pump_loop_sp) if !heat_pump_loop_sp.nil?
    runner.registerValue('loop_sp_storage', storage_loop_sp) if !storage_loop_sp.nil?
    runner.registerValue('loop_sp_dhw', dhw_loop_sp) if !dhw_loop_sp.nil?
    runner.registerValue('loop_sp_space_heating', space_heating_loop_sp) if !space_heating_loop_sp.nil?
    runner.registerValue('mains_average_f', avg_tmains)
    runner.registerValue('pump_gpm_supply', supply_pump_gpm) if !supply_pump_gpm.nil?
    runner.registerValue('pump_gpm_storage', storage_pump_gpm) if !storage_pump_gpm.nil?
    runner.registerValue('pump_gpm_dhw', dhw_pump_gpm) if !dhw_pump_gpm.nil?
    runner.registerValue('pump_gpm_space_heating', space_heating_pump_gpm) if !space_heating_pump_gpm.nil?
    runner.registerValue('tank_volume_storage_boiler', boiler_storage_tank_volume)
    runner.registerValue('tank_volume_storage_heat_pump', heat_pump_storage_tank_volume)
    runner.registerValue('tank_volume_swing', swing_tank_volume)
    runner.registerValue('tank_capacity_swing', swing_tank_capacity)
    runner.registerValue('reconnected_water_heatings', reconnected_water_heatings)
    runner.registerValue('reconnected_space_heatings', reconnected_space_heatings)
    runner.registerValue('coil_type', coil_type)
    runner.registerValue('space_htg_load_frac', space_htg_load_frac)
    runner.registerValue('water_heating_capacity', water_heating_capacity)
    runner.registerValue('space_heating_capacity', space_heating_capacity)

    return true
  end

  def remove_loops(runner, model, shared_water_heater_type)
    plant_loop_to_remove = [
      'dhw loop',
      'solar hot water loop'
    ]
    plant_loop_to_remove += ['boiler hydronic heat loop'] if shared_water_heater_type.include?(Constant::SpaceHeating)
    plant_loop_to_remove += plant_loop_to_remove.map { |p| p.gsub(' ', '_') }
    model.getPlantLoops.each do |plant_loop|
      next if plant_loop_to_remove.select { |p| plant_loop.name.to_s.include?(p) }.size == 0

      runner.registerInfo("#{plant_loop.class} '#{plant_loop.name}' removed.")
      plant_loop.remove
    end
  end

  def remove_ems(runner, model, shared_water_heater_type)
    # ProgramCallingManagers / Programs
    ems_pcm_to_remove = [
      'water heater EC_adj ProgramManager',
      'water heater ProgramManager',
      'water heater hpwh EC_adj ProgramManager',
      'solar hot water Control'
    ]
    ems_pcm_to_remove += [
      'boiler hydronic pump power program calling manager',
      'boiler hydronic pump disaggregate program calling manager'
    ] if shared_water_heater_type.include?(Constant::SpaceHeating)
    ems_pcm_to_remove += ems_pcm_to_remove.map { |e| e.gsub(' ', '_') }
    model.getEnergyManagementSystemProgramCallingManagers.each do |ems_pcm|
      next if ems_pcm_to_remove.select { |e| ems_pcm.name.to_s.include?(e) }.size == 0

      ems_pcm.programs.each do |program|
        runner.registerInfo("#{program.class} '#{program.name}' removed.")
        program.remove
      end
      runner.registerInfo("#{ems_pcm.class} '#{ems_pcm.name}' removed.")
      ems_pcm.remove
    end

    # Sensors
    ems_sensor_to_remove = [
      'water heater energy',
      'water heater fan',
      'water heater off cycle',
      'water heater on cycle',
      'water heater tank',
      'water heater lat',
      'water heater sens',
      'water heater coil',
      'water heater tl',
      'water heater hpwh',
      'solar hot water Collector',
      'solar hot water Tank'
    ]
    ems_sensor_to_remove += [
      'boiler hydronic pump',
      'boiler plr'
    ] if shared_water_heater_type.include?(Constant::SpaceHeating)
    ems_sensor_to_remove += ems_sensor_to_remove.map { |e| e.gsub(' ', '_') }
    model.getEnergyManagementSystemSensors.each do |ems_sensor|
      next if ems_sensor_to_remove.select { |e| ems_sensor.name.to_s.include?(e) }.size == 0

      runner.registerInfo("#{ems_sensor.class} '#{ems_sensor.name}' removed.")
      ems_sensor.remove
    end

    # Actuators
    ems_actuator_to_remove = [
      'water heater ec adj',
      'water heater hpwh ec adj',
      'solar hot water pump'
    ]
    ems_actuator_to_remove += [
      'boiler hydronic pump'
    ] if shared_water_heater_type.include?(Constant::SpaceHeating)
    ems_actuator_to_remove += ems_actuator_to_remove.map { |e| e.gsub(' ', '_') }
    model.getEnergyManagementSystemActuators.each do |ems_actuator|
      next if ems_actuator_to_remove.select { |e| ems_actuator.name.to_s.include?(e) }.size == 0

      runner.registerInfo("#{ems_actuator.class} '#{ems_actuator.name}' removed.")
      ems_actuator.remove
    end

    # OutputVariables
    ems_outvar_to_remove = []
    ems_outvar_to_remove += [
      'boiler hydronic pump disaggregate htg primary'
    ] if shared_water_heater_type.include?(Constant::SpaceHeating)
    ems_outvar_to_remove += ems_outvar_to_remove.map { |e| e.gsub(' ', '_') } if !ems_outvar_to_remove.empty?
    model.getEnergyManagementSystemOutputVariables.each do |ems_output_variable|
      next if ems_outvar_to_remove.select { |e| ems_output_variable.name.to_s.include?(e) }.size == 0

      runner.registerInfo("#{ems_output_variable.class} '#{ems_output_variable.name}' removed.")
      ems_output_variable.remove
    end

    # InternalVariables
    ems_intvar_to_remove = []
    ems_intvar_to_remove += [
      'boiler hydronic pump rated mfr'
    ] if shared_water_heater_type.include?(Constant::SpaceHeating)
    ems_intvar_to_remove += ems_intvar_to_remove.map { |e| e.gsub(' ', '_') } if !ems_intvar_to_remove.empty?
    model.getEnergyManagementSystemInternalVariables.each do |ems_internal_variable|
      next if ems_intvar_to_remove.select { |e| ems_internal_variable.name.to_s.include?(e) }.size == 0

      runner.registerInfo("#{ems_internal_variable.class} '#{ems_internal_variable.name}' removed.")
      ems_internal_variable.remove
    end
  end

  def remove_other(runner, model)
    other_equip_to_remove = [
      'water heater energy adjustment'
    ]
    other_equip_to_remove += other_equip_to_remove.map { |p| p.gsub(' ', '_') }
    model.getOtherEquipments.each do |other_equip|
      next if other_equip_to_remove.select { |e| other_equip.name.to_s.include?(e) }.size == 0

      runner.registerInfo("#{other_equip.class} '#{other_equip.name}' removed.")
      other_equip.remove
    end
  end
end

# register the measure to be used by the application
AddSharedWaterHeater.new.registerWithApplication
