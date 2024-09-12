# frozen_string_literal: true

class Supply
  def self.get_supply_count(type, num_beds, num_units)
    if type.include?(Constant::Boiler)
      return 1
    elsif type.include?(Constant::HeatPumpWaterHeater)
      # Calculate some size parameters: number of heat pumps, storage tank volume, number of tanks, swing tank volume
      # Sizing is based on CA code requirements: https://efiling.energy.ca.gov/GetDocument.aspx?tn=234434&DocumentContentId=67301
      # FIXME: How to adjust size when used for space heating?
      supply_count = ((0.037 * num_beds + 0.106 * num_units) * (154.0 / 123.5)).ceil # ratio is assumed capacity from code / nominal capacity from Robur spec sheet
      supply_count = [2, supply_count].max # FIXME: min

      if type.include?(Constant::SpaceHeating)
        supply_count += 1 # FIXME
      end

      return supply_count
    end
  end

  def self.get_total_water_heating_capacity(model)
    # already accounts for unit multipliers
    total_water_heating_capacity = 0.0
    model.getWaterHeaterMixeds.each do |water_heater_mixed|
      total_water_heating_capacity += water_heater_mixed.heaterMaximumCapacity.get
    end
    return total_water_heating_capacity
  end

  def self.get_total_space_heating_capacity(model)
    # already accounts for unit multipliers
    total_space_heating_capacity = 0.0
    model.getBoilerHotWaters.each do |boiler_hot_water|
      total_space_heating_capacity += boiler_hot_water.nominalCapacity.get
    end
    return total_space_heating_capacity
  end

  def self.get_supply_capacity(model, type)
    # W
    supply_capacity = 0.0
    if type.include?(Constant::Boiler)
      water_heating_capacity = get_total_water_heating_capacity(model)

      if !type.include?(Constant::SpaceHeating)
        supply_capacity = water_heating_capacity
      else
        space_heating_capacity = get_total_space_heating_capacity(model)

        supply_capacity = water_heating_capacity + space_heating_capacity
        supply_capacity *= 2 # FIXME
      end
    elsif type.include?(Constant::HeatPumpWaterHeater)
      supply_capacity = 36194.0
    end

    return supply_capacity
  end

  def self.create_component(model, type, fuel_type, supply_side_loop, name, capacity, boiler_eff_afue, is_supplemental_space_heating = false)
    if type.include?(Constant::Boiler)
      component = OpenStudio::Model::BoilerHotWater.new(model)
      component.setName(name)
      component.setNominalThermalEfficiency(boiler_eff_afue)
      component.setNominalCapacity(capacity)
      component.setFuelType(EPlus.fuel_type(fuel_type))
      component.setMinimumPartLoadRatio(0.0)
      component.setMaximumPartLoadRatio(1.0)
      component.setOptimumPartLoadRatio(1.0)
      component.setBoilerFlowMode('LeavingSetpointModulated')
      component.setWaterOutletUpperTemperatureLimit(99.9)
      component.setOnCycleParasiticElectricLoad(0)
      # component.setDesignWaterFlowRate() # FIXME
      component.setEfficiencyCurveTemperatureEvaluationVariable('LeavingBoiler')
      boiler_eff_curve = Curves.create_curve_bicubic(model, [1.111720116, 0.078614078, -0.400425756, 0.0, -0.000156783, 0.009384599, 0.234257955, 1.32927e-06, -0.004446701, -1.22498e-05], 'NonCondensingBoilerEff', 0.1, 1.0, 20.0, 80.0)
      component.setNormalizedBoilerEfficiencyCurve(boiler_eff_curve)
      component.additionalProperties.setFeature('IsCombiBoiler', true) # Used by reporting measure

      supply_side_loop.addSupplyBranchForComponent(component) if !is_supplemental_space_heating
    elsif type.include?(Constant::HeatPumpWaterHeater)
      if fuel_type == HPXML::FuelTypeElectricity
        component = OpenStudio::Model::WaterHeaterHeatPump.new(model)
        tank = Tanks.create_storage(model, supply_side_loop, nil, 80.0, nil, name, fuel_type)
        tank.additionalProperties.setFeature('IsCombiBoiler', true) # Used by reporting measure
        component.setTank(tank)
        fan = component.fan
        fan.additionalProperties.setFeature('ObjectType', Constant::ObjectNameWaterHeater) # Used by reporting measure
        component = tank
      else
        component = OpenStudio::Model::HeatPumpAirToWaterFuelFiredHeating.new(model)
        component.setName(name)
        component.setFuelType(EPlus.fuel_type(fuel_type))
        # component.setEndUseSubcategory()
        component.setNominalHeatingCapacity(capacity)
        component.setNominalCOP(1.293)
        # component.setDesignFlowRate(0.005) # FIXME
        lift = UnitConversions.convert(20.0, 'deltaF', 'deltaC')
        component.setDesignTemperatureLift(lift)
        component.setDesignSupplyTemperature(60)
        # component.setDesignSupplyTemperature(82.22)
        # component.setDesignSupplyTemperature(60 - lift) # FIXME
        # component.setFlowMode('LeavingSetpointModulated') # FIXME: this zeros out Fuel-fired Absorption HeatPump Electricity Energy: Supply Loop 1 Water Heater
        # component.setFlowMode('ConstantFlow')
        # component.setWaterTemperatureCurveInputVariable('LeavingCondenser') # FIXME
        component.setMinimumPartLoadRatio(0.2)
        component.setMaximumPartLoadRatio(1.0)
        component.setDefrostControlType('OnDemand')
        component.setDefrostOperationTimeFraction(0.0)
        component.setResistiveDefrostHeaterCapacity(0.0)
        component.setMaximumOutdoorDrybulbTemperatureforDefrostOperation(3.0)
        component.setNominalAuxiliaryElectricPower(900)
        component.setStandbyElectricPower(20)

        supply_side_loop.addSupplyBranchForComponent(component)
      end
    end

    return component
  end
end
