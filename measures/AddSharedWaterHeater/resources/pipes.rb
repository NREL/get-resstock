# frozen_string_literal: true

class Pipes
  def self.get_recirc_supply_return_lengths(hpxml_bldg, num_units, num_stories, has_double_loaded_corridor)
    l_mech = 8 # ft, Horizontal pipe length in mech room (Per T-24 ACM: 2013 Residential Alternative Calculation Method Reference Manual, June 2013, CEC-400-2013-003-CMF-REV)
    unit_type = hpxml_bldg.building_construction.residential_facility_type
    footprint = hpxml_bldg.building_construction.conditioned_floor_area
    h_floor = hpxml_bldg.building_construction.average_ceiling_height

    n_units_per_floor = num_units / num_stories
    if [HPXML::ResidentialTypeSFD, HPXML::ResidentialTypeManufactured].include?(unit_type)
      aspect_ratio = 1.8
    elsif [HPXML::ResidentialTypeSFA, HPXML::ResidentialTypeApartment].include?(unit_type)
      aspect_ratio = 0.5556
    end
    fb = Math.sqrt(footprint * aspect_ratio)
    lr = footprint / fb
    l_bldg = [fb, lr].max * n_units_per_floor

    supply_length = (l_mech + h_floor * (num_stories / 2.0).ceil + l_bldg) # ft

    if has_double_loaded_corridor
      return_length = (l_mech + h_floor * (num_stories / 2.0).ceil) # ft
    else
      return_length = supply_length
    end

    # supply_length and return_length are per building (?)
    # therefore, we'd expect these lengths to not scale with num_units linearly
    # meaning, more building units equals less per unit distribution loss
    return supply_length, return_length
  end

  def self.get_recirc_ins_r_value()
    supply_pipe_ins_r_value = 6.0
    return_pipe_ins_r_value = 4.0

    return supply_pipe_ins_r_value, return_pipe_ins_r_value
  end

  def self.create_adiabatic_supply(model, loop)
    return if loop.nil?

    supply_bypass = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_bypass.setName('Supply Bypass Pipe')
    supply_outlet = OpenStudio::Model::PipeAdiabatic.new(model)
    supply_outlet.setName('Supply Outlet Pipe')

    loop.addSupplyBranchForComponent(supply_bypass)
    supply_outlet.addToNode(loop.supplyOutletNode)
  end

  def self.create_adiabatic_demand(model, loop)
    return if loop.nil?

    demand_inlet = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_inlet.setName('Demand Inlet Pipe')
    demand_bypass = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_bypass.setName('Demand Bypass Pipe')
    demand_outlet = OpenStudio::Model::PipeAdiabatic.new(model)
    demand_outlet.setName('Demand Outlet Pipe')

    demand_inlet.addToNode(loop.demandInletNode)
    loop.addDemandBranchForComponent(demand_bypass)
    demand_outlet.addToNode(loop.demandOutletNode)
  end

  def self.calc_recirc_flow_rate(_hpxml_buildings, supply_length, supply_pipe_ins_r_value, volume)
    # ASHRAE calculation of the recirculation loop flow rate
    # Based on Equation 9 on p50.7 in 2011 ASHRAE Handbook--HVAC Applications

    # avg_num_bath = 0
    # avg_ffa = 0
    len_ins = 0
    len_unins = 0
    # hpxml_buildings.each do |hpxml_bldg|
    # avg_num_bath += hpxml_bldg.building_construction.number_of_bathrooms / hpxml_buildings.size
    # avg_ffa += hpxml_bldg.building_construction.conditioned_floor_area / hpxml_buildings.size
    # end

    if supply_pipe_ins_r_value > 0
      len_ins += supply_length
    else
      len_unins += supply_length
    end

    q_loss = 30 * len_ins + 60 * len_unins

    # Assume a 5 degree temperature drop is acceptable
    delta_T = 5 # degrees F

    gpm = q_loss / (60 * 8.25 * delta_T)
    cap = q_loss

    cap = 0 if volume == 0

    return gpm, cap
  end

  def self.calc_recirc_supply_return_diameters()
    # supply_diameter = ((-7.525e-9 * n_units**4 + 2.82e-6 * n_units**3 + -4.207e-4 * n_units**2 + 0.04378 * n_units + 1.232) / 0.5 + 1).round * 0.5 # in    Diameter of supply recirc pipe (Per T-24 ACM* which is based on 2009 UPC pipe sizing)
    supply_diameter = 2.0 # in
    return_diameter = 0.75 # in

    return supply_diameter, return_diameter
  end

  def self.lambert(x)
    # Lambert W function using Newton's method
    eps = 0.00000001 # max error allowed
    w = x
    while true
      ew = Math.exp(w)
      wNew = w - (w * ew - x) / (w * ew + ew)
      break if (w - wNew).abs <= eps

      w = wNew
    end
    return x
  end

  def self.calc_recirc_pipe_ins_thicknesses(supply_pipe_ins_r_value, return_pipe_ins_r_value, supply_diameter, return_diameter, conductivity)
    # Calculate thickness (in.) from nominal R-value, pipe outer diamter (in.), and insulation conductivity

    r1 = supply_diameter
    t_eq = supply_pipe_ins_r_value * conductivity * 12 # (hr-ft2-F / Btu) *  (Btu/ht-ft-F) * (in/ft)
    supply_thickness = r1 * (Math.exp(lambert(t_eq / r1)) - 1) # http://www.wolframalpha.com/input/?i=solve+%28r%2Bt%29*ln%28%28r%2Bt%29%2Fr%29%3DL+for+t%2C+L%3E0%2C+t%3E0%2C+r%3E0

    r1 = return_diameter
    t_eq = return_pipe_ins_r_value * conductivity * 12 # (hr-ft2-F / Btu) *  (Btu/ht-ft-F) * (in/ft)
    return_thickness = r1 * (Math.exp(lambert(t_eq / r1)) - 1) # http://www.wolframalpha.com/input/?i=solve+%28r%2Bt%29*ln%28%28r%2Bt%29%2Fr%29%3DL+for+t%2C+L%3E0%2C+t%3E0%2C+r%3E0

    return UnitConversions.convert(supply_thickness, 'in', 'm'), UnitConversions.convert(return_thickness, 'in', 'm')
  end

  def self.create_indoor(model, supply_length, return_length, supply_pipe_ins_r_value, return_pipe_ins_r_value, num_units)
    # Copper Pipe
    roughness = 'Smooth'
    thickness = 0.003
    conductivity = 401
    density = 8940
    specific_heat = 390

    copper_pipe_material = OpenStudio::Model::StandardOpaqueMaterial.new(model, roughness, thickness, conductivity, density, specific_heat)
    copper_pipe_material.setName('Return Pipe')
    copper_pipe_material.setThermalAbsorptance(0.9)
    copper_pipe_material.setSolarAbsorptance(0.5)
    copper_pipe_material.setVisibleAbsorptance(0.5)

    # Pipe Diameters
    supply_diameter, return_diameter = calc_recirc_supply_return_diameters()

    # Pipe Insulation
    roughness = 'VeryRough'
    conductivity = 0.021
    density = 63.66
    specific_heat = 1297.66

    supply_thickness, return_thickness = calc_recirc_pipe_ins_thicknesses(supply_pipe_ins_r_value, return_pipe_ins_r_value, supply_diameter, return_diameter, conductivity)

    pipe_ins_r_value_derate = 0.3
    effective_pipe_ins_conductivity = conductivity / (1.0 - pipe_ins_r_value_derate)

    # Supply
    supply_pipe_insulation_material = OpenStudio::Model::StandardOpaqueMaterial.new(model, roughness, supply_thickness, effective_pipe_ins_conductivity, density, specific_heat) # R-6
    supply_pipe_insulation_material.setName('Supply Pipe Insulation')
    supply_pipe_insulation_material.setThermalAbsorptance(0.9)
    supply_pipe_insulation_material.setSolarAbsorptance(0.5)
    supply_pipe_insulation_material.setVisibleAbsorptance(0.5)

    supply_pipe_materials = []
    supply_pipe_materials << supply_pipe_insulation_material
    supply_pipe_materials << copper_pipe_material

    insulated_supply_pipe_construction = OpenStudio::Model::Construction.new(model)
    insulated_supply_pipe_construction.setName('Insulated Supply Pipe')
    insulated_supply_pipe_construction.setLayers(supply_pipe_materials)

    # Return
    return_pipe_insulation_material = OpenStudio::Model::StandardOpaqueMaterial.new(model, roughness, return_thickness, effective_pipe_ins_conductivity, density, specific_heat) # R-4
    return_pipe_insulation_material.setName('Return Pipe Insulation')
    return_pipe_insulation_material.setThermalAbsorptance(0.9)
    return_pipe_insulation_material.setSolarAbsorptance(0.5)
    return_pipe_insulation_material.setVisibleAbsorptance(0.5)

    return_pipe_materials = []
    return_pipe_materials << return_pipe_insulation_material
    return_pipe_materials << copper_pipe_material

    insulated_return_pipe_construction = OpenStudio::Model::Construction.new(model)
    insulated_return_pipe_construction.setName('Insulated Return Pipe')
    insulated_return_pipe_construction.setLayers(return_pipe_materials)

    # Thermal Zones
    indoor_pipes = {}
    model.getWaterUseConnectionss.each do |wuc|
      thermal_zone = get_thermal_zone_from_water_use_connections(wuc)

      # Supply
      supply_pipe_indoor = OpenStudio::Model::PipeIndoor.new(model)
      supply_pipe_indoor.setName("Supply Pipe - #{thermal_zone.name}")
      supply_pipe_indoor.setAmbientTemperatureZone(thermal_zone)
      supply_pipe_indoor.setConstruction(insulated_supply_pipe_construction)
      supply_pipe_indoor.setPipeInsideDiameter(UnitConversions.convert(supply_diameter, 'in', 'm'))
      # supply_pipe_indoor.setPipeLength(UnitConversions.convert(supply_length / num_units, 'ft', 'm')) # FIXME: if unit multiplier DOES account for this
      supply_pipe_indoor.setPipeLength(UnitConversions.convert((supply_length / num_units) * thermal_zone.multiplier, 'ft', 'm')) # FIXME: if unit multiplier DOES NOT account for this

      # supply_pipe_indoor.addToNode(demand_inlet.outletModelObject.get.to_Node.get)

      # Return
      return_pipe_indoor = OpenStudio::Model::PipeIndoor.new(model)
      return_pipe_indoor.setName("Return Pipe - #{thermal_zone.name}")
      return_pipe_indoor.setAmbientTemperatureZone(thermal_zone)
      return_pipe_indoor.setConstruction(insulated_return_pipe_construction)
      return_pipe_indoor.setPipeInsideDiameter(UnitConversions.convert(return_diameter, 'in', 'm'))
      # return_pipe_indoor.setPipeLength(UnitConversions.convert(return_length / num_units, 'ft', 'm')) # FIXME: if unit multiplier DOES account for this
      return_pipe_indoor.setPipeLength(UnitConversions.convert((return_length / num_units) * thermal_zone.multiplier, 'ft', 'm')) # FIXME: if unit multiplier DOES NOT account for this

      # return_pipe_indoor.addToNode(demand_bypass.outletModelObject.get.to_Node.get)

      indoor_pipes[wuc] = [supply_pipe_indoor, return_pipe_indoor]
    end

    return indoor_pipes
  end

  def self.get_thermal_zone_from_water_use_connections(wuc)
    plant_loop = wuc.plantLoop.get
    plant_loop.supplyComponents.each do |supply_component|
      next unless supply_component.to_WaterHeaterMixed.is_initialized
      if supply_component.to_WaterHeaterMixed.get.ambientTemperatureThermalZone.is_initialized
        return supply_component.to_WaterHeaterMixed.get.ambientTemperatureThermalZone.get
      end
    end
  end
end
