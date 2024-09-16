# frozen_string_literal: true

class Pumps
  def self.get_rated_head(_type)
    # Pa
    return 20000.0
  end

  def self.get_rated_power_consumption(type)
    # W
    if !type.include?(Constant::SpaceHeating)
      return 10.0
    elsif type.include?(Constant::Boiler)
      return 150.0
    else
      return 20.0
    end
  end

  def self.create_constant_speed(model, loop, pump_gpm, pump_head, pump_w, control_type = 'Intermittent')
    return if loop.nil?

    pump = OpenStudio::Model::PumpConstantSpeed.new(model)
    pump.setName("#{loop.name} Pump")
    pump.setRatedPowerConsumption(pump_w) if !pump_w.nil?
    pump.setRatedPumpHead(pump_head) if !pump_head.nil?
    if pump_gpm.nil?
      # pump.setRatedFlowRate(pump_eff * pump_w / pump_head) if !pump_w.nil? && !pump_head.nil?
    else
      pump.setRatedFlowRate(UnitConversions.convert(pump_gpm, 'gal/min', 'm^3/s')) if !pump_gpm.nil?
    end
    pump.setPumpControlType(control_type)
    pump.addToNode(loop.supplyInletNode)
    pump.additionalProperties.setFeature('ObjectType', Constant::ObjectNameSharedWaterHeater) # Used by reporting measure
  end

  def self.get_flow_rates(type)
    # gal/min
    if type == Constant::WaterHeaterTypeBoiler
      supply_pump_gpm = nil
      storage_pump_gpm = nil
    elsif type == Constant::WaterHeaterTypeHeatPump
      supply_pump_gpm = nil
      storage_pump_gpm = nil
    elsif type == Constant::WaterHeaterTypeCombiBoiler
      supply_pump_gpm = nil
      storage_pump_gpm = nil
      space_heating_pump_gpm = nil
    elsif type == Constant::WaterHeaterTypeCombiHeatPump
      supply_pump_gpm = nil
      storage_pump_gpm = nil
      space_heating_pump_gpm = nil
    end

    return supply_pump_gpm, storage_pump_gpm, space_heating_pump_gpm
  end
end
