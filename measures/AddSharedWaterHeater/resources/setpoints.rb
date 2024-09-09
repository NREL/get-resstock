# frozen_string_literal: true

class Setpoints
  def self.get_loop_designs(type)
    # deg-F
    if type == Constant::WaterHeaterTypeBoiler
      dhw_loop_sp = 135.0
      supply_loop_sp = 180.0
      storage_loop_sp = 180.0
      space_heating_loop_sp = nil
    elsif type == Constant::WaterHeaterTypeHeatPump
      dhw_loop_sp = 135.0
      supply_loop_sp = 140.0
      storage_loop_sp = 140.0
      space_heating_loop_sp = nil
    elsif type == Constant::WaterHeaterTypeCombiBoiler
      dhw_loop_sp = 135.0
      supply_loop_sp = 180.0
      storage_loop_sp = 180.0
      space_heating_loop_sp = 180.0
    elsif type == Constant::WaterHeaterTypeCombiHeatPump
      dhw_loop_sp = 135.0
      supply_loop_sp = 140.0
      storage_loop_sp = 140.0
      space_heating_loop_sp = 180.0 # this has a boiler on it
    end

    return dhw_loop_sp, supply_loop_sp, storage_loop_sp, space_heating_loop_sp
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

  def self.create_availability(model, loop, hot_node, cold_node)
    availability_manager = OpenStudio::Model::AvailabilityManagerDifferentialThermostat.new(model)
    availability_manager.setName("#{loop.name} Availability Manager")
    availability_manager.setHotNode(hot_node)
    availability_manager.setColdNode(cold_node)
    availability_manager.setTemperatureDifferenceOnLimit(0)
    availability_manager.setTemperatureDifferenceOffLimit(0)
    loop.addAvailabilityManager(availability_manager)
  end
end
