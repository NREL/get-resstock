# frozen_string_literal: true

class HeatExchangers
  def self.create(model, demand_side_loop, supply_side_loop, name, prev_component, hp_in_series = true, boiler_on_hp_outlet = true)
    hx = OpenStudio::Model::HeatExchangerFluidToFluid.new(model)
    # hx.setControlType('OperationSchemeModulated') # FIXME: this causes a bunch of zero rows for Fuel-fired Absorption HeatPump Electricity Energy: Supply Loop 1 Water Heater
    hx.setName(name)

    Loops.add_component(hx, prev_component, hp_in_series, boiler_on_hp_outlet, supply_side_loop, demand_side_loop)

    return hx
  end
end
