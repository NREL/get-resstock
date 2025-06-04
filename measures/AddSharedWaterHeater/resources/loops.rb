# frozen_string_literal: true

class Loops
  def self.create_plant(model, name, design_temp, deltaF, max_gpm = nil, num_units = nil)
    loop = OpenStudio::Model::PlantLoop.new(model)
    loop.setName(name)
    # loop.setMaximumLoopTemperature(UnitConversions.convert(design_temp, 'F', 'C'))
    loop.setMaximumLoopFlowRate(UnitConversions.convert(max_gpm, 'gal/min', 'm^3/s')) if !max_gpm.nil?
    loop.setPlantLoopVolume(0.003 * num_units) if !num_units.nil? # ~1 gal

    loop_sizing = loop.sizingPlant
    loop_sizing.setLoopType('Heating')
    loop_sizing.setDesignLoopExitTemperature(UnitConversions.convert(design_temp, 'F', 'C'))
    loop_sizing.setLoopDesignTemperatureDifference(UnitConversions.convert(deltaF, 'deltaF', 'deltaC'))

    return loop
  end

  def self.get_flow_rates(type)
    # gal/min
    if type == Constant::WaterHeaterTypeBoiler
      supply_loop_gpm = nil
      storage_loop_gpm = nil
    elsif type == Constant::WaterHeaterTypeHeatPump
      supply_loop_gpm = nil
      storage_loop_gpm = nil
    elsif type == Constant::WaterHeaterTypeCombiBoiler
      supply_loop_gpm = nil
      storage_loop_gpm = nil
      space_heating_loop_gpm = nil
    elsif type == Constant::WaterHeaterTypeCombiHeatPump
      supply_loop_gpm = nil
      storage_loop_gpm = nil
      space_heating_loop_gpm = nil
    end

    return supply_loop_gpm, storage_loop_gpm, space_heating_loop_gpm
  end

  def self.reconnect_water_use_connections(model, dhw_loop)
    # connections_in_series = true # otherwise parallel
    connections_in_series = false # FIXME

    prev_wuc = nil

    reconnected_water_heatings = 0
    water_use_connections = model.getWaterUseConnectionss.sort_by { |wuc| wuc.name.to_s }
    water_use_connections.each_with_index do |wuc, _i|
      wuc.setName("#{wuc.name}_reconnected")

      if prev_wuc.nil?
        dhw_loop.addDemandBranchForComponent(wuc)
      else
        wuc.addToNode(prev_wuc.outletModelObject.get.to_Node.get)
      end
      prev_wuc = wuc if connections_in_series

      reconnected_water_heatings += 1
    end
    return reconnected_water_heatings
  end

  def self.reconnect_space_water_coils(model, space_heating_loop)
    reconnected_space_heatings = 0
    return reconnected_space_heatings if space_heating_loop.nil?

    coil_heating_water_baseboards = model.getCoilHeatingWaterBaseboards.sort_by { |chwb| chwb.name.to_s }
    coil_heating_waters = model.getCoilHeatingWaters.sort_by { |chw| chw.name.to_s }
    coil_cooling_waters = model.getCoilCoolingWaters.sort_by { |ccw| ccw.name.to_s }

    coil_heating_water_baseboards.each do |chwb|
      chwb.setName("#{chwb.name}_reconnected")
      space_heating_loop.addDemandBranchForComponent(chwb)
      reconnected_space_heatings += 1
    end

    coil_heating_waters.each do |chw|
      chw.setName("#{chw.name}_reconnected")
      space_heating_loop.addDemandBranchForComponent(chw)
      reconnected_space_heatings += 1
    end

    coil_cooling_waters.each do |ccw|
      ccw.setName("#{ccw.name}_reconnected")
      space_heating_loop.addDemandBranchForComponent(ccw)
    end

    return reconnected_space_heatings
  end
end
