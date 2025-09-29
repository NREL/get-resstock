# frozen_string_literal: true

class Supply
  def self.get_supply_counts(type, fuel_type, num_units, include_swing_tank, water_heating_capacity, space_heating_capacity, space_htg_load_frac, heat_pump_capacity)
    boiler_count = 0
    if not include_swing_tank
      boiler_count = 1
    end

    heat_pump_count = 0
    if heat_pump_capacity > 0
      if fuel_type == HPXML::FuelTypeElectricity
        space_heating_capacity_for_hp = 0.0
        if type.include?(Constant::SpaceHeating)
          space_heating_capacity_for_hp = space_heating_capacity * space_htg_load_frac # Portion of space heating load served by HPWH
        end

        heat_pump_count = ((water_heating_capacity + space_heating_capacity_for_hp) / heat_pump_capacity).ceil
      else
        # Calculate some size parameters: number of heat pumps, storage tank volume, number of tanks, swing tank volume
        # Sizing is based on CA code requirements: https://efiling.energy.ca.gov/GetDocument.aspx?tn=234434&DocumentContentId=67301
        # FIXME: How to adjust size when used for space heating?
        # heat_pump_count = ((0.037 * num_beds + 0.106 * num_units) * (154.0 / 123.5)).ceil # ratio is assumed capacity from code / nominal capacity from Robur spec sheet
        # heat_pump_count = [1, heat_pump_count].max # FIXME: min
        heat_pump_count = [(num_units / 20.0).ceil, 5].min
      end
    end

    return boiler_count, heat_pump_count
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

  def self.get_supply_capacities(model, type, fuel_type, coil_type)
    # W
    water_heating_capacity = get_total_water_heating_capacity(model) * 0.6 # To account for approximate coincidence factor
    space_heating_capacity = get_total_space_heating_capacity(model) # Retain full capacity for boiler sizing

    boiler_capacity = water_heating_capacity
    if type.include?(Constant::SpaceHeating)
      boiler_capacity += space_heating_capacity
    end

    heat_pump_capacity = 0.0
    if type.include?(Constant::HeatPumpWaterHeater)
      if fuel_type == HPXML::FuelTypeElectricity
        if coil_type == 'spec'
          heat_pump_capacity = 20250.0 # Nominal capacity at 40F for Copeland from spec sheet
        elsif coil_type == 'lab'
          heat_pump_capacity = 20250.0 # FIXME: Real number from lab testing at ~40 F
        end
      else
        heat_pump_capacity = 36194.0
      end
    end

    return boiler_capacity, heat_pump_capacity, water_heating_capacity, space_heating_capacity
  end

  def self.create_component(model, type, fuel_type, supply_side_loop, capacity, boiler_eff_afue, t_amb, num_units, coil_type, prev_component, setpoint = nil, hp_in_series = true, boiler_on_hp_outlet = true)
    name = supply_side_loop.name

    if type.include?(Constant::Boiler)
      component = OpenStudio::Model::BoilerHotWater.new(model)
      component.setName("#{name} Water Heater")
      component.setNominalThermalEfficiency(boiler_eff_afue)
      component.setNominalCapacity(capacity)
      # component.setFuelType(EPlus.fuel_type(fuel_type))
      component.setFuelType(EPlus.fuel_type(HPXML::FuelTypeNaturalGas))
      # component.setMinimumPartLoadRatio(0.0) # FIXME: default
      component.setMinimumPartLoadRatio(0.2) # FIXME: hand calculation; this w/GAHP is pretty good, and you don't need AVM
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
    elsif type.include?(Constant::HeatPumpWaterHeater)
      if fuel_type == HPXML::FuelTypeElectricity
        coil = OpenStudio::Model::CoilWaterHeatingAirToWaterHeatPump.new(model)
        coil.setName("#{name} Coil")
        coil.setCrankcaseHeaterCapacity(0.0)

        # coil_type = 'spec' # 'spec', 'lab'
        if coil_type == 'spec' # Option 1: Copeland spec sheet
          hpwh_cap = OpenStudio::Model::CurveBiquadratic.new(model)
          hpwh_cap.setName('HPWH-Cap-fT')
          hpwh_cap.setCoefficient1Constant(2.00064)
          hpwh_cap.setCoefficient2x(0.04987)
          hpwh_cap.setCoefficient3xPOW2(0.00013004)
          hpwh_cap.setCoefficient4y(0.04114)
          hpwh_cap.setCoefficient5yPOW2(-0.00033391)
          hpwh_cap.setCoefficient6xTIMESY(0.00001336)
          hpwh_cap.setMinimumValueofx(0)
          hpwh_cap.setMaximumValueofx(100)
          hpwh_cap.setMinimumValueofy(0)
          hpwh_cap.setMaximumValueofy(100)

          hpwh_cop = OpenStudio::Model::CurveBiquadratic.new(model)
          hpwh_cop.setName('HPWH-COP-fT')
          hpwh_cop.setCoefficient1Constant(1.8849)
          hpwh_cop.setCoefficient2x(0.02497)
          hpwh_cop.setCoefficient3xPOW2(0.00003162)
          hpwh_cop.setCoefficient4y(-0.03377)
          hpwh_cop.setCoefficient5yPOW2(0.00021905)
          hpwh_cop.setCoefficient6xTIMESY(-0.00030450)
          hpwh_cop.setMinimumValueofx(0)
          hpwh_cop.setMaximumValueofx(100)
          hpwh_cop.setMinimumValueofy(0)
          hpwh_cop.setMaximumValueofy(100)

          coil.setRatedEvaporatorAirFlowRate(0.75) # FIXME: sort of arbitarily increased from autosized value of 0.293 to get around negative coil bypass factor error.
          # coil.setRatedHeatingCapacity(5834)
          coil.setRatedHeatingCapacity(capacity) # FIXME
          coil.setRatedCOP(3.26)
          coil.setRatedSensibleHeatRatio(0.98)
          coil.setRatedEvaporatorInletAirDryBulbTemperature(UnitConversions.convert(47, 'F', 'C'))
          coil.setRatedEvaporatorInletAirWetBulbTemperature(UnitConversions.convert(43, 'F', 'C'))
          coil.setRatedCondenserInletWaterTemperature(48.89)
          coil.setEvaporatorFanPowerIncludedinRatedCOP(true)
          coil.setEvaporatorAirTemperatureTypeforCurveObjects('DryBulbTemperature')
          coil.setHeatingCapacityFunctionofTemperatureCurve(hpwh_cap)
          coil.setHeatingCOPFunctionofTemperatureCurve(hpwh_cop)
          coil.setRatedEvaporatorAirFlowRate(0.18877898)
        elsif coil_type == 'lab' # Option 2: lab
          # FIXME: elsif lab data...
        end

        volume = 100.0 # FIXME
        if type.include?(Constant::SpaceHeating)
          volume *= 1.5 # Avoid "Change over rate is too fast" FIXME
        end
        tank = Tanks.get_storage_tank(model, "#{name} Storage Tank", setpoint, fuel_type, volume)

        fan = OpenStudio::Model::FanOnOff.new(model)
        fan.setName("#{name} Fan")

        compressorSetpointTemperatureSchedule = OpenStudio::Model::ScheduleRuleset.new(model)
        compressorSetpointTemperatureSchedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), setpoint)

        inletAirMixerSchedule = OpenStudio::Model::ScheduleRuleset.new(model)
        inletAirMixerSchedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.2)

        component = OpenStudio::Model::WaterHeaterHeatPump.new(model, coil, tank, fan, compressorSetpointTemperatureSchedule, inletAirMixerSchedule)
        component = component.tank.to_WaterHeaterStratified.get # the stratified tank goes on the supply side of the supply loop; the pumped condenser doesn't get attached/added anywhere (?)
      else
        component = OpenStudio::Model::HeatPumpAirToWaterFuelFiredHeating.new(model)
        component.setName("#{name} Water Heater")
        component.setFuelType(EPlus.fuel_type(fuel_type))
        # component.setEndUseSubcategory()
        component.setNominalHeatingCapacity(capacity)
        component.setNominalCOP(1.0) # FIXME: changed this from 1.293 because there's evidence when the curves were derived they didn't account for nominal COP, it's not mentioned at all in the document they sent us on the derivation
        # component.setDesignFlowRate(0.005) # FIXME
        lift = UnitConversions.convert(20.0, 'deltaF', 'deltaC')
        component.setDesignTemperatureLift(lift)
        component.setDesignSupplyTemperature(60)
        # component.setDesignSupplyTemperature(82.22)
        # component.setDesignSupplyTemperature(60 - lift) # FIXME
        # component.setFlowMode('LeavingSetpointModulated') # FIXME: this zeros out Fuel-fired Absorption HeatPump Electricity Energy: Supply Loop 1 Water Heater
        # component.setFlowMode('ConstantFlow')
        # component.setWaterTemperatureCurveInputVariable('LeavingCondenser') # FIXME
        # component.setMinimumPartLoadRatio(0.1) # FIXME: default
        if num_units < 20
          component.setMinimumPartLoadRatio(0.25)
        else # 20+
          component.setMinimumPartLoadRatio(0.456) # FIXME: hand calculation
        end
        component.setMaximumPartLoadRatio(1.0)
        component.setDefrostControlType('OnDemand')
        component.setDefrostOperationTimeFraction(0.0)
        component.setResistiveDefrostHeaterCapacity(0.0)
        component.setMaximumOutdoorDrybulbTemperatureforDefrostOperation(3.0)
        component.setNominalAuxiliaryElectricPower(900)
        # component.setNominalAuxiliaryElectricPower(0)
        component.setStandbyElectricPower(20)
        # component.setStandbyElectricPower(0)

        # Curves
        cap_func_temp, eir_func_temp, eir_func_plr, eir_defrost_adj, cycling_ratio_factor, aux_eir_func_temp, aux_eir_func_plr = Curves.get_heat_pump_air_to_water_fuel_fired_heating_curves(model, component, t_amb)
        Curves.set_heat_pump_air_to_water_fuel_fired_heating_curves(component, cap_func_temp, eir_func_temp, eir_func_plr, eir_defrost_adj, cycling_ratio_factor, aux_eir_func_temp, aux_eir_func_plr)
      end
    end

    Loops.add_component(component, prev_component, hp_in_series, boiler_on_hp_outlet, supply_side_loop, nil)

    return component
  end
end
