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
    else
      runner.registerWarning("AddSharedWaterHeater: Could not find '#{hpxml_path}'.")
      return true
    end

    # Extension properties
    hpxml_bldg = hpxml.buildings[0]
    num_stories = hpxml_bldg.header.extension_properties['geometry_num_floors_above_grade'].to_f
    has_double_loaded_corridor = hpxml_bldg.header.extension_properties['geometry_corridor_position']
    shared_water_heater_type = hpxml_bldg.header.extension_properties['shared_water_heater_type']
    shared_water_heater_fuel_type = hpxml_bldg.header.extension_properties['shared_water_heater_fuel_type']
    shared_boiler_efficiency_afue = hpxml_bldg.header.extension_properties['shared_boiler_efficiency_afue'].to_f

    # Skip measure if no shared heating system
    if shared_water_heater_type == 'none'
      runner.registerAsNotApplicable('AddSharedWaterHeater: Building does not have shared water heater. Skipping...')
      return true
    end

    # Building -level information
    unit_multipliers = hpxml.buildings.collect { |hpxml_bldg| hpxml_bldg.building_construction.number_of_units }
    num_units = unit_multipliers.sum
    num_beds = hpxml.buildings.collect { |hpxml_bldg| hpxml_bldg.building_construction.number_of_units * hpxml_bldg.building_construction.number_of_bedrooms }.sum
    # FIXME: should these be relative to the number of MODELED units? i.e., hpxml.buildings.size? sounds like maybe no?
    # num_units = hpxml.buildings.size
    # num_beds = hpxml.buildings.collect { |hpxml_bldg| hpxml_bldg.building_construction.number_of_bedrooms }.sum

    # Supply
    supply_count = Supply.get_supply_count(shared_water_heater_type, num_beds, num_units)
    supply_capacity = Supply.get_supply_capacity(model, shared_water_heater_type)

    # Tanks
    storage_tank_volume = Tanks.get_storage_volume(model, shared_water_heater_type, supply_count)
    swing_tank_volume = Tanks.get_swing_volume(shared_water_heater_type, num_units)

    supply_count_max = 10
    storage_tank_volume *= 2 if supply_count > supply_count_max # otherwise E+ error: Change over rate is too fast, increase tank volume, decrease connection flow rates or use mixed tank model
    supply_count = [supply_count, supply_count_max].min

    # Setpoints
    dhw_loop_sp, supply_loop_sp, storage_loop_sp, space_heating_loop_sp = Setpoints.get_loop_designs(shared_water_heater_type)

    # Pumps
    pump_head = Pumps.get_rated_head(shared_water_heater_type)
    pump_w = Pumps.get_rated_power_consumption(shared_water_heater_type)
    pump_head = nil # FIXME
    pump_w = nil # FIXME

    # Pipes
    supply_length, return_length = Pipes.get_recirc_supply_return_lengths(hpxml_bldg, num_units, num_stories, has_double_loaded_corridor)
    supply_ins_r, return_ins_r = Pipes.get_recirc_ins_r_value()
    indoor_pipes = Pipes.create_indoor(model, supply_length, return_length, supply_ins_r, return_ins_r, num_units)
    # indoor_pipes = nil

    # questions:
    # - dhw pump gpm autosize because of indoor pipes?
    # - capacities of:
    #   - swing tank
    #   - supplemental boiler
    # - counts of:
    #   - gahp
    # - almost like it's faster to empty/fill the swing tank than to wait on gahp
    #  - set swing capacity equal to recirc losses? we're already doing this, but i'm cutting capacity down
    #  - try using dhw_pump_gpm (or autosizing) the DHW loop pump (~1 gal/min may be reasonable)

    dhw_loop_gpm = UnitConversions.convert(0.01, 'm^3/s', 'gal/min') * num_units # OS-HPXML ###
    dhw_pump_gpm, swing_tank_capacity = Pipes.calc_recirc_flow_rate(hpxml.buildings, supply_length, supply_ins_r, swing_tank_volume)

    # Flows
    supply_loop_gpm, storage_loop_gpm, space_heating_loop_gpm = Loops.get_flow_rates(shared_water_heater_type)
    supply_pump_gpm, storage_pump_gpm, space_heating_pump_gpm = Pumps.get_flow_rates(shared_water_heater_type)

    # Add Setpoint Schedules
    dhw_loop_sp_schedule = Setpoints.create_schedule(model, dhw_loop_sp)
    supply_loop_sp_schedule = Setpoints.create_schedule(model, supply_loop_sp)
    storage_loop_sp_schedule = Setpoints.create_schedule(model, storage_loop_sp)
    space_heating_loop_sp_schedule = Setpoints.create_schedule(model, space_heating_loop_sp)

    # Add Loops
    dhw_loop = Loops.create_plant(model, 'DHW Loop', dhw_loop_sp, 10.0, dhw_loop_gpm, num_units)
    supply_loops = {}
    (1..supply_count).to_a.each do |i|
      supply_loop = Loops.create_plant(model, "Supply Loop #{i}", supply_loop_sp, 20.0, supply_loop_gpm)
      supply_loops[supply_loop] = []
    end
    storage_loop = Loops.create_plant(model, 'Storage Loop', storage_loop_sp, 20.0, storage_loop_gpm)
    space_heating_loop = Loops.create_plant(model, 'Space Heating Loop', space_heating_loop_sp, 20.0, space_heating_loop_gpm) if shared_water_heater_type.include?(Constant::SpaceHeating)

    # Add Adiabatic Pipes
    Pipes.create_adiabatic_supply(model, dhw_loop)
    # Pipes.create_adiabatic_demand(model, dhw_loop)
    supply_loops.each do |supply_loop, _|
      Pipes.create_adiabatic_supply(model, supply_loop)
      Pipes.create_adiabatic_demand(model, supply_loop)
    end
    Pipes.create_adiabatic_supply(model, storage_loop)
    Pipes.create_adiabatic_demand(model, storage_loop)
    Pipes.create_adiabatic_supply(model, space_heating_loop) if shared_water_heater_type.include?(Constant::SpaceHeating)
    Pipes.create_adiabatic_demand(model, space_heating_loop) if shared_water_heater_type.include?(Constant::SpaceHeating)

    # Add Pumps
    Pumps.create_constant_speed(model, dhw_loop, dhw_pump_gpm, pump_head, pump_w, 'Continuous')
    supply_loops.each do |supply_loop, _|
      Pumps.create_constant_speed(model, supply_loop, supply_pump_gpm, pump_head, pump_w)
    end
    Pumps.create_constant_speed(model, storage_loop, storage_pump_gpm, pump_head, pump_w)
    Pumps.create_constant_speed(model, space_heating_loop, space_heating_pump_gpm, pump_head, pump_w)

    # Add Setpoint Managers
    Setpoints.create_manager(model, dhw_loop, dhw_loop_sp_schedule)
    supply_loops.each do |supply_loop, _|
      Setpoints.create_manager(model, supply_loop, supply_loop_sp_schedule)
    end
    Setpoints.create_manager(model, storage_loop, storage_loop_sp_schedule)
    Setpoints.create_manager(model, space_heating_loop, space_heating_loop_sp_schedule)

    # Add Storage Tank(s)
    prev_storage_tank = nil
    supply_loops.each do |supply_loop, components|
      storage_tank = Tanks.create_storage(model, supply_loop, storage_loop, storage_tank_volume, prev_storage_tank, "#{supply_loop.name} Main Storage Tank", shared_water_heater_fuel_type, supply_loop_sp)
      storage_tank.additionalProperties.setFeature('ObjectType', Constant::ObjectNameSharedWaterHeater) # Used by reporting measure

      components << storage_tank
      prev_storage_tank = components[0]
    end

    # Add Swing Tank
    # swing_tank_capacity /= 3 # FIXME
    swing_tank = Tanks.create_swing(model, storage_loop, dhw_loop, swing_tank_volume, swing_tank_capacity, 'Swing Tank', shared_water_heater_fuel_type, dhw_loop_sp)
    swing_tank.additionalProperties.setFeature('ObjectType', Constant::ObjectNameSharedWaterHeater) if !swing_tank.nil? # Used by reporting measure

    # Add Heat Exchangers
    # HeatExchangers.create(model, storage_loop, dhw_loop, 'DHW Heat Exchanger') # swing and hx in parallel gives us FF use only and no swing tank use...?
    HeatExchangers.create(model, storage_loop, dhw_loop, 'DHW Heat Exchanger') if swing_tank.nil?
    space_heating_hx = HeatExchangers.create(model, storage_loop, space_heating_loop, 'Space Heating Heat Exchanger') if shared_water_heater_type.include?(Constant::SpaceHeating)

    # Add Supplemental Space Heating Boiler
    if shared_water_heater_type == Constant::WaterHeaterTypeCombiHeatPump
      supplemental_heating_capacity = Supply.get_total_space_heating_capacity(model)
      supplemental_heating_capacity /= 3 # FIXME
      component = Supply.create_component(model, Constant::Boiler, shared_water_heater_fuel_type, space_heating_loop, "#{space_heating_loop.name} Space Heater", supplemental_heating_capacity, shared_boiler_efficiency_afue, true)
      component.addToNode(space_heating_hx.supplyOutletModelObject.get.to_Node.get)
    end

    # Add Supply Components
    supply_loops.each do |supply_loop, components|
      component = Supply.create_component(model, shared_water_heater_type, shared_water_heater_fuel_type, supply_loop, "#{supply_loop.name} Water Heater", supply_capacity, shared_boiler_efficiency_afue)

      # Curves
      if component.to_HeatPumpAirToWaterFuelFiredHeating.is_initialized
        cap_func_temp, eir_func_temp, eir_func_plr, eir_defrost_adj, cycling_ratio_factor, aux_eir_func_temp, aux_eir_func_plr = Curves.get_heat_pump_air_to_water_fuel_fired_heating_curves(model, component)
      end

      components << component
    end

    # Add Availability Manager(s)
    supply_loops.each do |supply_loop, components|
      storage_tank, component = components
      if component.to_BoilerHotWater.is_initialized || component.to_HeatPumpAirToWaterFuelFiredHeating.is_initialized
        hot_node = component.outletModelObject.get.to_Node.get
      elsif component.to_WaterHeaterStratified.is_initialized
        hot_node = component.supplyOutletModelObject.get.to_Node.get
      end
      cold_node = storage_tank.demandOutletModelObject.get.to_Node.get
      Setpoints.create_availability(model, supply_loop, hot_node, cold_node)
    end

    # Re-connect WaterUseConections (in series) with PipeIndoors
    reconnected_water_heatings = Loops.reconnect_water_use_connections(model, dhw_loop, indoor_pipes)

    # Re-connect CoilHeatingWaterBaseboards (in parallel)
    reconnected_space_heatings = Loops.reconnect_space_water_coils(model, space_heating_loop)

    # Remove Existing
    remove_loops(runner, model, shared_water_heater_type)
    remove_ems(runner, model, shared_water_heater_type)
    remove_other(runner, model)

    # Register values
    runner.registerValue('shared_water_heater_type', shared_water_heater_type)
    runner.registerValue('shared_water_heater_fuel_type', shared_water_heater_fuel_type)
    runner.registerValue('unit_models', hpxml.buildings.size)
    runner.registerValue('unit_multipliers', unit_multipliers.join(','))
    runner.registerValue('num_units', num_units)
    runner.registerValue('num_beds', num_beds)
    runner.registerValue('supply_count', supply_count)
    runner.registerValue('length_ft_supply', supply_length)
    runner.registerValue('length_ft_return', return_length)
    runner.registerValue('loop_gpm_supply', supply_loop_gpm) if !supply_loop_gpm.nil?
    runner.registerValue('loop_gpm_storage', storage_loop_gpm) if !storage_loop_gpm.nil?
    runner.registerValue('loop_gpm_dhw', dhw_loop_gpm) if !dhw_loop_gpm.nil?
    runner.registerValue('loop_gpm_space_heating', space_heating_loop_gpm) if !space_heating_loop_gpm.nil?
    runner.registerValue('loop_sp_supply', supply_loop_sp) if !supply_loop_sp.nil?
    runner.registerValue('loop_sp_storage', storage_loop_sp) if !storage_loop_sp.nil?
    runner.registerValue('loop_sp_dhw', dhw_loop_sp) if !dhw_loop_sp.nil?
    runner.registerValue('loop_sp_space_heating', space_heating_loop_sp) if !space_heating_loop_sp.nil?
    runner.registerValue('tank_volume_storage', storage_tank_volume)
    runner.registerValue('tank_volume_swing', swing_tank_volume)
    runner.registerValue('tank_capacity_swing', swing_tank_capacity)
    runner.registerValue('reconnected_water_heatings', reconnected_water_heatings)
    runner.registerValue('reconnected_space_heatings', reconnected_space_heatings)

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
