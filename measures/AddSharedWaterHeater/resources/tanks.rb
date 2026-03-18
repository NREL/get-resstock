# frozen_string_literal: true

class Tanks
  def self.get_total_water_heating_tank_volume(model)
    # already accounts for unit multipliers
    total_water_heating_tank_volume = 0.0
    model.getWaterHeaterMixeds.each do |water_heater_mixed|
      total_water_heating_tank_volume += water_heater_mixed.tankVolume.get
    end
    return UnitConversions.convert(total_water_heating_tank_volume, 'm^3', 'gal')
  end

  def self.min_tank_size_by_cec_climate_zone(cec_climate_zone)
    if ['1'].include?(cec_climate_zone)
      return 214
    elsif ['16'].include?(cec_climate_zone)
      return 220
    elsif ['2', '3', '5'].include?(cec_climate_zone)
      return 238
    elsif ['4', '12'].include?(cec_climate_zone)
      return 255
    elsif ['6', '7', '11', '14'].include?(cec_climate_zone)
      return 264
    elsif ['9'].include?(cec_climate_zone)
      return 268
    elsif ['8', '10', '13'].include?(cec_climate_zone)
      return 273
    elsif ['15'].include?(cec_climate_zone)
      return 336
    end
  end

  def self.min_tank_size_by_tmains(t_mains)
    # Calc based on curve fit to CEC climate zone method
    vol = 4.7429 * t_mains - 34.965
    vol = [vol, 80].max # ensure reasonable minimum if super cold mains temp
    return vol
  end

  def self.get_boiler_storage_volume(num_units, num_occs)
    # gal

    # Assuming medium usage (ASHRAE Handbook of HVAC and Applications Chapter 50 Table 7)
    gal_per_person = 4.8 # Assuming Medium usage and 60 minutes of peak usage (ASHRAE Handbook of HVAC Applications Chapter 50 Table 7)
    if num_occs == 0
      num_occs = 2.6 * num_units
    end
    cumulative_hw_volume = gal_per_person * num_occs
    boiler_storage_tank_volume = cumulative_hw_volume / 0.7

    return boiler_storage_tank_volume
  end

  def self.get_heat_pump_storage_volume(type, t_mains)
    # gal

    heat_pump_storage_tank_volume = 0.0
    if type.include?(Constant::HeatPumpWaterHeater)
      heat_pump_storage_tank_volume = min_tank_size_by_tmains(t_mains)
    end

    return heat_pump_storage_tank_volume
  end

  def self.get_swing_volume(include_swing_tank, num_units)
    # gal
    return 0.0 if !include_swing_tank

    if num_units < 8
      swing_tank_volume = 40.0
    elsif num_units < 12
      swing_tank_volume = 80.0
    elsif num_units < 24
      swing_tank_volume = 96.0
    elsif num_units < 48
      swing_tank_volume = 168.0
    elsif num_units < 96
      swing_tank_volume = 288.0
    else
      swing_tank_volume = 480.0
    end
    return swing_tank_volume
  end

  def self.get_storage_tank(model, name, setpoint, fuel_type, volume)
    h_tank = 2.0 # m, assumed
    h_source_in = 0.01 * h_tank
    h_source_out = 0.99 * h_tank

    tank_r = UnitConversions.convert(22.0, 'hr*ft^2*f/btu', 'm^2*k/w') # From code
    tank_u = 1.0 / tank_r

    storage_tank = OpenStudio::Model::WaterHeaterStratified.new(model)
    storage_tank.setName(name)

    # TODO: set volume, height, deadband, control
    capacity = 0

    setpoint_schedule = OpenStudio::Model::ScheduleConstant.new(model)
    setpoint_schedule.setName("#{name} Temperature #{setpoint.round}F")
    setpoint_schedule.setValue(UnitConversions.convert(setpoint, 'F', 'C'))

    storage_tank.setEndUseSubcategory(name)
    volume = [0.0001, volume].max # FIXME: this will set 0.1893 m^3/s (50 gal) if we try to set 0 volume
    storage_tank.setTankVolume(UnitConversions.convert(volume, 'gal', 'm^3'))
    storage_tank.setTankHeight(h_tank)
    # storage_tank.setMaximumTemperatureLimit(UnitConversions.convert(setpoint, 'F', 'C')) # FIXME: set this to 90C?
    # storage_tank.setMaximumTemperatureLimit(99)
    storage_tank.setHeater1SetpointTemperatureSchedule(setpoint_schedule)
    storage_tank.setHeater1Capacity(capacity)
    storage_tank.setHeater2SetpointTemperatureSchedule(setpoint_schedule)
    storage_tank.setHeater2Capacity(capacity)
    storage_tank.setHeaterFuelType(EPlus.fuel_type(fuel_type))
    # storage_tank.setHeaterFuelType(EPlus.fuel_type(HPXML::FuelTypeNaturalGas))
    storage_tank.setHeaterThermalEfficiency(1) # FIXME: apply_solar_thermal

    # amb = 40 # C
    # loc_schedule = OpenStudio::Model::ScheduleConstant.new(model)
    # loc_schedule.setName("#{name} Ambient #{amb}F")
    # loc_schedule.setValue(UnitConversions.convert(amb, 'F', 'C'))
    # storage_tank.setAmbientTemperatureSchedule(loc_schedule)
    # storage_tank.setAmbientTemperatureZone # FIXME: What zone do we want to assume the tanks are in?

    storage_tank.setUniformSkinLossCoefficientperUnitAreatoAmbientTemperature(tank_u) # FIXME: typical loss values?
    # storage_tank.setUniformSkinLossCoefficientperUnitAreatoAmbientTemperature(0) # FIXME: apply_solar_thermal
    # storage_tank.setSkinLossFractiontoZone(1.0 / unit_multiplier) # Tank losses are multiplied by E+ zone multiplier, so need to compensate here
    # storage_tank.setSkinLossFractiontoZone(0.0714285714285714) # FIXME: apply_solar_thermal
    storage_tank.setOffCycleFlueLossCoefficienttoAmbientTemperature(0)
    # storage_tank.setOffCycleFlueLossFractiontoZone(1.0 / unit_multiplier)
    # storage_tank.setOffCycleFlueLossFractiontoZone(0.0714285714285714) # FIXME: apply_solar_thermal

    # storage_tank.setSourceSideInletHeight(h_source_in)
    # storage_tank.setSourceSideInletHeight(h_source_out / 3.0) # FIXME: apply_solar_thermal
    storage_tank.setSourceSideInletHeight(h_source_out)
    storage_tank.setSourceSideOutletHeight(0) # FIXME: apply_solar_thermal
    # storage_tank.setSourceSideOutletHeight(h_source_out)

    storage_tank.setUseSideInletHeight(0)
    storage_tank.setUseSideOutletHeight(h_source_out)

    storage_tank.setOffCycleParasiticFuelConsumptionRate(0.0)
    storage_tank.setOnCycleParasiticFuelConsumptionRate(0.0)
    storage_tank.setNumberofNodes(12) # FIXME: apply_solar_thermal
    storage_tank.setNode1AdditionalLossCoefficient(0.0) # These don't default to 0, I guess assuming a 6 node tank?
    storage_tank.setNode6AdditionalLossCoefficient(0.0)
    storage_tank.setAdditionalDestratificationConductivity(0) # FIXME: apply_solar_thermal
    storage_tank.setUseSideDesignFlowRate(UnitConversions.convert(volume, 'gal', 'm^3') / 60.1) # Sized to ensure that E+ never autosizes the design flow rate to be larger than the tank volume getting drawn out in a hour (60 minutes)
    # storage_tank.setSourceSideDesignFlowRate(UnitConversions.convert(13.6, 'gal/min', 'm^3/s')) # FIXME

    # storage_tank.setSourceSideFlowControlMode('IndirectHeatAlternateSetpoint')
    # storage_tank.setIndirectAlternateSetpointTemperatureSchedule(setpoint_schedule)

    return storage_tank
  end

  def self.create_storage(model, demand_side_loop, supply_side_loop, volume, prev_component, name, fuel_type, setpoint, hp_in_series = true, boiler_on_hp_outlet = true)
    storage_tank = get_storage_tank(model, name, setpoint, fuel_type, volume)

    Loops.add_component(storage_tank, prev_component, hp_in_series, boiler_on_hp_outlet, supply_side_loop, demand_side_loop)

    return storage_tank
  end

  def self.create_swing(model, supply_side_loop, volume, prev_hx, name, capacity, setpoint, hp_in_series = true, boiler_on_hp_outlet = true)
    return if volume == 0

    # this would be in series with the main storage tanks, downstream of it
    # this does not go on the demand side of the supply loop, like the main storage tank does
    swing_tank = OpenStudio::Model::WaterHeaterStratified.new(model)
    swing_tank.setName(name)

    tank_r = UnitConversions.convert(22.0, 'hr*ft^2*f/btu', 'm^2*k/w') # From code
    tank_u = 1.0 / tank_r
    h_tank = 2.0 # m
    h_ue = 0.8 * h_tank
    h_le = 0.2 * h_tank
    h_source_in = 0.01 * h_tank
    h_source_out = 0.99 * h_tank

    swing_tank.setTankHeight(h_tank)
    swing_tank.setTankVolume(UnitConversions.convert(volume, 'gal', 'm^3'))
    swing_tank.setHeaterPriorityControl('MasterSlave')
    swing_tank.setHeater1Capacity(capacity)
    swing_tank.setHeater1Height(h_ue)
    swing_tank.setHeater1DeadbandTemperatureDifference(5.56) # 10 F
    swing_tank.setHeater2Capacity(capacity)
    swing_tank.setHeater2Height(h_le)
    swing_tank.setHeater2DeadbandTemperatureDifference(5.56)
    setpoint_schedule = OpenStudio::Model::ScheduleConstant.new(model)
    setpoint_schedule.setName("#{name} Temperature #{setpoint.round}F")
    setpoint_schedule.setValue(UnitConversions.convert(setpoint, 'F', 'C'))
    swing_tank.setHeater1SetpointTemperatureSchedule(setpoint_schedule)
    swing_tank.setHeater2SetpointTemperatureSchedule(setpoint_schedule)
    # swing_tank.setAmbientTemperatureZone # FIXME: What zone do we want to assume the tanks are in?
    swing_tank.setUniformSkinLossCoefficientperUnitAreatoAmbientTemperature(tank_u) # FIXME: typical loss values?
    swing_tank.setSourceSideInletHeight(h_source_in)
    swing_tank.setSourceSideOutletHeight(h_source_out)
    swing_tank.setOffCycleParasiticFuelConsumptionRate(0.0)
    swing_tank.setOnCycleParasiticFuelConsumptionRate(0.0)
    swing_tank.setNumberofNodes(6)
    swing_tank.setNode1AdditionalLossCoefficient(0.0) # These don't default to 0, I guess assuming a 6 node tank?
    swing_tank.setNode6AdditionalLossCoefficient(0.0)
    # swing_tank.setUseSideDesignFlowRate(UnitConversions.convert(volume, 'gal', 'm^3') / 60.1) # Sized to ensure that E+ never autosizes the design flow rate to be larger than the tank volume getting drawn out in a hour (60 minutes)
    # swing_tank.setSourceSideDesignFlowRate() # FIXME
    swing_tank.setEndUseSubcategory(name)
    swing_tank.setHeaterFuelType(EPlus.fuel_type(HPXML::FuelTypeElectricity))
    swing_tank.setMaximumTemperatureLimit(UnitConversions.convert(setpoint, 'F', 'C')) # FIXME

    if prev_hx.nil? || !hp_in_series
      supply_side_loop.addSupplyBranchForComponent(swing_tank) # first one is a new supply branch
    else
      if boiler_on_hp_outlet
        swing_tank.addToNode(prev_hx.supplyOutletModelObject.get.to_Node.get) # remaining are added in series
      else
        swing_tank.addToNode(supply_side_loop.supplyOutletNode)
      end
    end

    return swing_tank
  end
end
