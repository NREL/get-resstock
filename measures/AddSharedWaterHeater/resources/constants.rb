# frozen_string_literal: true

module Constant
  ObjectNameSharedWaterHeater = 'shared water heater' # Used by reporting measure

  HeatPumpWaterHeater = 'heat pump water heater'
  Boiler = 'boiler'
  SpaceHeating = 'space-heating'

  WaterHeaterTypeHeatPump = "#{HeatPumpWaterHeater} with storage tanks"
  WaterHeaterTypeBoiler = "#{Boiler} with storage tanks"
  WaterHeaterTypeCombiHeatPump = "#{SpaceHeating} #{HeatPumpWaterHeater} with storage tanks"
  WaterHeaterTypeCombiBoiler = "#{SpaceHeating} #{Boiler} with storage tanks"
end
