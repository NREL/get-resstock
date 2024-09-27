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

  def self.get_storage_volumes(_model, type, num_units, boiler_backup_wh_frac, boiler_backup_sh_frac)
    # gal
    gal_per_unit = 2.6 * 4.8 / 0.7 # FIXME

    boiler_storage_tank_volume = 0.0
    heat_pump_storage_tank_volume = 0.0

    # boiler_storage_tank_volume = get_total_water_heating_tank_volume(model)
    boiler_storage_tank_volume = gal_per_unit * num_units

    if !type.include?(Constant::SpaceHeating)
      boiler_storage_tank_volume *= 1
    else
      boiler_storage_tank_volume *= 1
    end

    # boiler_storage_tank_volume = [120.0, boiler_storage_tank_volume].max # FIXME min 120 gal
    boiler_storage_tank_volume = 480.0 # FIXME

    if type.include?(Constant::HeatPumpWaterHeater)

      heat_pump_storage_tank_volume = gal_per_unit * num_units

      if !type.include?(Constant::SpaceHeating)
        heat_pump_storage_tank_volume *= 1
      else
        heat_pump_storage_tank_volume *= 1
      end

      # heat_pump_storage_tank_volume = [120.0, heat_pump_storage_tank_volume].max # FIXME min 120 gal
      heat_pump_storage_tank_volume = 120.0 # FIXME

      if type.include?(Constant::SpaceHeating)
        boiler_storage_tank_volume *= boiler_backup_sh_frac # FIXME
      else
        boiler_storage_tank_volume *= boiler_backup_wh_frac # FIXME
      end
    end

    return boiler_storage_tank_volume, heat_pump_storage_tank_volume
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

  def self.create_storage(model, demand_side_loop, supply_side_loop, volume, prev_storage_tank, name, fuel_type, setpoint)
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
    storage_tank.setTankVolume(UnitConversions.convert(volume, 'gal', 'm^3'))
    storage_tank.setTankHeight(h_tank)
    storage_tank.setMaximumTemperatureLimit(UnitConversions.convert(setpoint, 'F', 'C')) # FIXME
    storage_tank.setHeater1SetpointTemperatureSchedule(setpoint_schedule)
    storage_tank.setHeater1Capacity(capacity)
    storage_tank.setHeater2SetpointTemperatureSchedule(setpoint_schedule)
    storage_tank.setHeater2Capacity(capacity)
    storage_tank.setHeaterFuelType(EPlus.fuel_type(fuel_type))
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
    storage_tank.setSourceSideInletHeight(h_source_out / 3.0) # FIXME: apply_solar_thermal
    # storage_tank.setSourceSideOutletHeight(h_source_out)
    storage_tank.setSourceSideOutletHeight(0) # FIXME: apply_solar_thermal
    storage_tank.setUseSideInletHeight(0)
    storage_tank.setUseSideOutletHeight(h_source_out)
    storage_tank.setOffCycleParasiticFuelConsumptionRate(0.0)
    storage_tank.setOnCycleParasiticFuelConsumptionRate(0.0)
    storage_tank.setNumberofNodes(8) # FIXME: apply_solar_thermal
    storage_tank.setAdditionalDestratificationConductivity(0) # FIXME: apply_solar_thermal
    storage_tank.setUseSideDesignFlowRate(UnitConversions.convert(volume, 'gal', 'm^3') / 60.1) # Sized to ensure that E+ never autosizes the design flow rate to be larger than the tank volume getting drawn out in a hour (60 minutes)
    # storage_tank.setSourceSideDesignFlowRate(UnitConversions.convert(13.6, 'gal/min', 'm^3/s')) # FIXME
    if demand_side_loop.nil? # stratified tank on supply side of source loop (e.g., shared electric hpwh)
      storage_tank.setHeaterThermalEfficiency(1.0)
      storage_tank.setAdditionalDestratificationConductivity(0)
      storage_tank.setSourceSideDesignFlowRate(0)
      storage_tank.setSourceSideFlowControlMode('')
      storage_tank.setSourceSideInletHeight(0)
      storage_tank.setSourceSideOutletHeight(0)
    end

    if prev_storage_tank.nil?
      supply_side_loop.addSupplyBranchForComponent(storage_tank) # first one is a new supply branch
    else
      storage_tank.addToNode(prev_storage_tank.useSideOutletModelObject.get.to_Node.get) # remaining are added in series
    end
    if !supply_side_loop.nil?
      demand_side_loop.addDemandBranchForComponent(storage_tank)
    end

    return storage_tank
  end

  def self.create_swing(model, demand_side_loop, supply_side_loop, volume, capacity, name, fuel_type, setpoint)
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
    # swing_tank.setUseSideDesignFlowRate(UnitConversions.convert(volume, 'gal', 'm^3') / 60.1) # Sized to ensure that E+ never autosizes the design flow rate to be larger than the tank volume getting drawn out in a hour (60 minutes)
    # swing_tank.setSourceSideDesignFlowRate() # FIXME
    swing_tank.setEndUseSubcategory(name)
    swing_tank.setHeaterFuelType(EPlus.fuel_type(fuel_type))
    swing_tank.setMaximumTemperatureLimit(UnitConversions.convert(setpoint, 'F', 'C')) # FIXME

    supply_side_loop.addSupplyBranchForComponent(swing_tank)
    demand_side_loop.addDemandBranchForComponent(swing_tank)

    return swing_tank
  end
end
