# frozen_string_literal: true

class HeatExchangers
  def self.create(model, demand_side_loop, supply_side_loop, name)
    hx = OpenStudio::Model::HeatExchangerFluidToFluid.new(model)
    # hx.setControlType('OperationSchemeModulated') # FIXME: this causes a bunch of zero rows for Fuel-fired Absorption HeatPump Electricity Energy: Supply Loop 1 Water Heater
    hx.setName(name)

    supply_side_loop.addSupplyBranchForComponent(hx)
    demand_side_loop.addDemandBranchForComponent(hx)

    return hx
  end
end
