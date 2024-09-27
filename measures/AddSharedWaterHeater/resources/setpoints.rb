# frozen_string_literal: true

class Setpoints
  def self.get_loop_designs(type)
    # deg-F
    dhw_loop_sp = 135.0
    if type == Constant::WaterHeaterTypeBoiler
      boiler_loop_sp = 140.0 # FIXME: should this just be 140 since we don't need 180?
      heat_pump_loop_sp = nil
      storage_loop_sp = 140.0
      space_heating_loop_sp = nil
    elsif type == Constant::WaterHeaterTypeHeatPump
      boiler_loop_sp = 140.0 # FIXME: should this just be 140 since we don't need 180?
      heat_pump_loop_sp = 140.0
      storage_loop_sp = 140.0
      space_heating_loop_sp = nil
    elsif type == Constant::WaterHeaterTypeCombiBoiler
      space_heat_sp = 180.0

      boiler_loop_sp = space_heat_sp
      heat_pump_loop_sp = nil
      storage_loop_sp = space_heat_sp
      space_heating_loop_sp = space_heat_sp
    elsif type == Constant::WaterHeaterTypeCombiHeatPump
      space_heat_sp = 180.0

      boiler_loop_sp = space_heat_sp
      heat_pump_loop_sp = 140.0
      storage_loop_sp = space_heat_sp
      space_heating_loop_sp = space_heat_sp
    end

    return dhw_loop_sp, boiler_loop_sp, heat_pump_loop_sp, storage_loop_sp, space_heating_loop_sp
  end

  def self.create_schedule(model, sp)
    return if sp.nil?

    schedule = OpenStudio::Model::ScheduleConstant.new(model)
    schedule.setValue(UnitConversions.convert(sp, 'F', 'C'))

    return schedule
  end

  def self.create_manager(model, loop, schedule)
    return if loop.nil?

    manager = OpenStudio::Model::SetpointManagerScheduled.new(model, schedule)
    manager.setName("#{loop.name} Setpoint Manager #{UnitConversions.convert(schedule.value, 'C', 'F').round}F")
    manager.setControlVariable('Temperature')
    manager.addToNode(loop.supplyOutletNode)
  end

  def self.create_availability(model, loop, node_1, node_2, temperature)
    if node_2.nil?
      availability_manager = OpenStudio::Model::AvailabilityManagerLowTemperatureTurnOn.new(model)
      availability_manager.setName("#{loop.name} Low Turn On #{temperature}F")
      availability_manager.setSensorNode(node_1)
      availability_manager.setTemperature(UnitConversions.convert(temperature, 'F', 'C'))
      loop.addAvailabilityManager(availability_manager)

      availability_manager = OpenStudio::Model::AvailabilityManagerHighTemperatureTurnOff.new(model)
      availability_manager.setName("#{loop.name} High Turn Off #{temperature}F")
      availability_manager.setSensorNode(node_1)
      availability_manager.setTemperature(UnitConversions.convert(temperature, 'F', 'C'))
      loop.addAvailabilityManager(availability_manager)
    else
      availability_manager = OpenStudio::Model::AvailabilityManagerDifferentialThermostat.new(model)
      availability_manager.setHotNode(node_1)
      availability_manager.setColdNode(node_2)
      availability_manager.setTemperatureDifferenceOnLimit(0)
      availability_manager.setTemperatureDifferenceOffLimit(0)
      loop.addAvailabilityManager(availability_manager)
    end

    # availability_manager = OpenStudio::Model::AvailabilityManagerHighTemperatureTurnOff.new(model)
    # availability_manager.setSensorNode(node_1)
    # availability_manager.setTemperature(60.0)
    # loop.addAvailabilityManager(availability_manager)

    # availability_manager.setName("#{loop.name} Availability Manager")
    # loop.addAvailabilityManager(availability_manager)
  end
end
