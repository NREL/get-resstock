# frozen_string_literal: true

class Curves
  def self.get_heat_pump_air_to_water_fuel_fired_heating_curves(model, component)
    t_amb_min = 0.0 # F; from GTI report
    t_amb_max = 110.0 # F; from GTI report

    t_ret_min = 95.0 # F; from GTI report
    t_ret_max = 120.0 # F; from GTI report

    t_amb = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Site Outdoor Air Drybulb Temperature')
    t_amb.setName('TambC')
    t_amb.setKeyName('*')

    t_ret = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Fuel-fired Absorption HeatPump Inlet Temperature')
    t_ret.setName('TretC')
    t_ret.setKeyName(component.name.to_s)

    program_cm = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
    program_cm.setName('GAHP Curves PCM')
    program_cm.setCallingPoint('InsideHVACSystemIterationLoop')

    cap_func_temp = component.normalizedCapacityFunctionofTemperatureCurve.to_CurveBiquadratic.get
    # cap_func_temp = OpenStudio::Model::CurveBicubic.new(model)
    # cap_func_temp.setName('CapCurveFuncTemp')
    # cap_func_temp.setCoefficient1Constant(-53.99)
    cap_func_temp.setCoefficient1Constant(0) # FIXME: ensure we're not using this curve
    # cap_func_temp.setCoefficient2x(1.541)
    # cap_func_temp.setCoefficient4y(-0.006523)
    # cap_func_temp.setCoefficient3xPOW2(-0.01438)
    # cap_func_temp.setCoefficient6xTIMESY(0.0002626)
    # cap_func_temp.setCoefficient5yPOW2(-0.00006042)
    # cap_func_temp.setCoefficient7xPOW3(0.0000444)
    # cap_func_temp.setCoefficient9xPOW2TIMESY(-0.000001052)
    # cap_func_temp.setCoefficient10xTIMESYPOW2(0.00000006212)
    # cap_func_temp.setCoefficient8yPOW3(0.00000002424)
    # cap_func_temp.setMinimumValueofx(5)
    # cap_func_temp.setMaximumValueofx(60)
    # cap_func_temp.setMinimumValueofy(5)
    # cap_func_temp.setMaximumValueofy(60)

    actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(cap_func_temp, 'Curve', 'Curve Result')
    actuator.setName('CapCurveFuncTempAct')

    program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    program.setName('CapCurveFuncTempFixed')

    program.addLine("Set Tret = #{t_ret.name}*(9.0/5.0)+32.0")
    program.addLine("Set Tret_min = #{t_ret_min}")
    program.addLine("Set Tret_max = #{t_ret_max}")
    program.addLine('Set Tret = (@Min Tret Tret_max)')
    program.addLine('Set Tret = (@Max Tret Tret_min)')

    program.addLine("Set Tamb = #{t_amb.name}*(9.0/5.0)+32.0")
    program.addLine("Set Tamb_min = #{t_amb_min}")
    program.addLine("Set Tamb_max = #{t_amb_max}")
    program.addLine('Set Tamb = (@Min Tamb Tamb_max)')
    program.addLine('Set Tamb = (@Max Tamb Tamb_min)')

    program.addLine('Set a1 = -53.99')
    program.addLine('Set b1 = 1.541*Tret')
    program.addLine('Set c1 = -0.006523*Tamb')
    program.addLine('Set d1 = -0.01438*(Tret^2)')
    program.addLine('Set e1 = 0.0002626*Tret*Tamb')
    program.addLine('Set f1 = -0.00006042*(Tamb^2)')
    program.addLine('Set g1 = 0.0000444*(Tret^3)')
    program.addLine('Set h1 = -0.000001052*(Tret^2)*Tamb')
    program.addLine('Set i1 = 0.00000006212*Tret*(Tamb^2)')
    program.addLine('Set j1 = 0.00000002424*(Tamb^3)')
    program.addLine("Set #{actuator.name} = a1 + b1 + c1 + d1 + e1 + f1 + g1 + h1 + i1 + j1")

    program_cm.addProgram(program)

    ems_output_var = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(model, "#{actuator.name}")
    ems_output_var.setName("#{actuator.name} Output")
    ems_output_var.setTypeOfDataInVariable('Averaged')
    ems_output_var.setUpdateFrequency('SystemTimestep')
    ems_output_var.setEMSProgramOrSubroutineName(program)

    eir_func_temp = component.fuelEnergyInputRatioFunctionofTemperatureCurve.to_CurveBiquadratic.get
    # eir_func_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    # eir_func_temp.setName('EIRCurveFuncTemp')
    # eir_func_temp.setCoefficient1Constant(0.5205)
    eir_func_temp.setCoefficient1Constant(0) # FIXME: ensure we're not using this curve
    # eir_func_temp.setCoefficient2x(0.00004408)
    # eir_func_temp.setCoefficient3xPOW2(0.0000176)
    # eir_func_temp.setCoefficient4y(0.00699)
    # eir_func_temp.setCoefficient5yPOW2(-0.0001215)
    # eir_func_temp.setCoefficient6xTIMESY(0.0000005196)
    # eir_func_temp.setMinimumValueofx(5)
    # eir_func_temp.setMaximumValueofx(60)
    # eir_func_temp.setMinimumValueofy(5)
    # eir_func_temp.setMaximumValueofy(60)

    actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(eir_func_temp, 'Curve', 'Curve Result')
    actuator.setName('EIRCurveFuncTempAct')

    program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    program.setName('EIRCurveFuncTempFixed')

    program.addLine("Set Tret = #{t_ret.name}*(9.0/5.0)+32.0")
    program.addLine("Set Tret_min = #{t_ret_min}")
    program.addLine("Set Tret_max = #{t_ret_max}")
    program.addLine('Set Tret = (@Min Tret Tret_max)')
    program.addLine('Set Tret = (@Max Tret Tret_min)')

    program.addLine("Set Tamb = #{t_amb.name}*(9.0/5.0)+32.0")
    program.addLine("Set Tamb_min = #{t_amb_min}")
    program.addLine("Set Tamb_max = #{t_amb_max}")
    program.addLine('Set Tamb = (@Min Tamb Tamb_max)')
    program.addLine('Set Tamb = (@Max Tamb Tamb_min)')

    program.addLine('Set a2 = 0.5205')
    program.addLine('Set b2 = 0.00004408*Tamb')
    program.addLine('Set c2 = 0.0000176*(Tamb^2)')
    program.addLine('Set d2 = 0.00699*Tret')
    program.addLine('Set e2 = -0.0001215*Tamb*Tret')
    program.addLine('Set f2 = 0.0000005196*(Tamb^2)*Tret')
    program.addLine("Set #{actuator.name} = a2 + b2 + c2 + d2 + e2 + f2")

    program_cm.addProgram(program)

    ems_output_var = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(model, "#{actuator.name}")
    ems_output_var.setName("#{actuator.name} Output")
    ems_output_var.setTypeOfDataInVariable('Averaged')
    ems_output_var.setUpdateFrequency('SystemTimestep')
    ems_output_var.setEMSProgramOrSubroutineName(program)

    eir_func_plr = OpenStudio::Model::CurveExponent.new(model)
    eir_func_plr.setName('EIRCurveFuncPLR')
    eir_func_plr.setCoefficient1Constant(0)
    eir_func_plr.setCoefficient2Constant(0.9219)
    eir_func_plr.setCoefficient3Constant(-0.188)
    eir_func_plr.setMinimumValueofx(0)
    eir_func_plr.setMaximumValueofx(1)
    eir_func_plr.setMinimumCurveOutput(1)
    eir_func_plr.setMaximumCurveOutput(2.25)

    eir_defrost_adj = OpenStudio::Model::CurveQuadratic.new(model)
    eir_defrost_adj.setName('EIRDefrostFoTCurve')
    eir_defrost_adj.setCoefficient1Constant(1.0317)
    eir_defrost_adj.setCoefficient2x(-0.006)
    eir_defrost_adj.setCoefficient3xPOW2(-0.0011)
    eir_defrost_adj.setMinimumValueofx(-8.89)
    eir_defrost_adj.setMaximumValueofx(3.333)
    eir_defrost_adj.setMinimumCurveOutput(1.0)
    eir_defrost_adj.setMaximumCurveOutput(10.0)

    cycling_ratio_factor = OpenStudio::Model::CurveQuadratic.new(model)
    cycling_ratio_factor.setName('CRFCurve')
    cycling_ratio_factor.setCoefficient1Constant(0.5833)
    cycling_ratio_factor.setCoefficient2x(0.4167)
    cycling_ratio_factor.setCoefficient3xPOW2(0)
    cycling_ratio_factor.setMinimumValueofx(0)
    cycling_ratio_factor.setMaximumValueofx(100)
    cycling_ratio_factor.setMinimumCurveOutput(0)
    cycling_ratio_factor.setMaximumCurveOutput(10.0)

    aux_eir_func_temp = OpenStudio::Model::CurveBiquadratic.new(model)
    aux_eir_func_temp.setName('AuxElecEIRCurveFuncTempCurve')
    # aux_eir_func_temp.setCoefficient1Constant(1.102)
    aux_eir_func_temp.setCoefficient1Constant(0) # FIXME: ensure we're not using this curve
    # aux_eir_func_temp.setCoefficient2x(-0.0008714)
    # aux_eir_func_temp.setCoefficient3xPOW2(-0.000009238)
    # aux_eir_func_temp.setCoefficient4y(0.00000006487)
    # aux_eir_func_temp.setCoefficient5yPOW2(0.0006447)
    # aux_eir_func_temp.setCoefficient6xTIMESY(0.0000007846)
    # aux_eir_func_temp.setMinimumValueofx(5)
    # aux_eir_func_temp.setMaximumValueofx(60)
    # aux_eir_func_temp.setMinimumValueofy(5)
    # aux_eir_func_temp.setMaximumValueofy(60)

    actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(aux_eir_func_temp, 'Curve', 'Curve Result')
    actuator.setName('AuxElecEIRCurveFuncTempCurveAct')

    program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
    program.setName('AuxElecEIRCurveFuncTempCurveFixed')

    program.addLine("Set Tret = #{t_ret.name}*(9.0/5.0)+32.0")
    program.addLine("Set Tret_min = #{t_ret_min}")
    program.addLine("Set Tret_max = #{t_ret_max}")
    program.addLine('Set Tret = (@Min Tret Tret_max)')
    program.addLine('Set Tret = (@Max Tret Tret_min)')

    program.addLine("Set Tamb = #{t_amb.name}*(9.0/5.0)+32.0")
    program.addLine("Set Tamb_min = #{t_amb_min}")
    program.addLine("Set Tamb_max =  #{t_amb_max}")
    program.addLine('Set Tamb = (@Min Tamb Tamb_max)')
    program.addLine('Set Tamb = (@Max Tamb Tamb_min)')

    program.addLine('Set a4 = 1.102')
    program.addLine('Set b4 = -0.0008714*Tamb')
    program.addLine('Set c4 = -0.000009238*(Tamb^2)')
    program.addLine('Set d4 = 0.00000006487*(Tamb^3)')
    program.addLine('Set e4 = 0.0006447*Tret')
    program.addLine('Set f4 = 0.0000007846*Tamb*Tret')
    program.addLine("Set #{actuator.name} = a4 + b4 + c4 + d4 + e4 + f4")

    program_cm.addProgram(program)

    ems_output_var = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(model, "#{actuator.name}")
    ems_output_var.setName("#{actuator.name} Output")
    ems_output_var.setTypeOfDataInVariable('Averaged')
    ems_output_var.setUpdateFrequency('SystemTimestep')
    ems_output_var.setEMSProgramOrSubroutineName(program)

    aux_eir_func_plr = OpenStudio::Model::CurveBiquadratic.new(model)
    aux_eir_func_plr.setName('auxElecEIRForPLRCurve')
    aux_eir_func_plr.setCoefficient1Constant(1)
    aux_eir_func_plr.setCoefficient2x(0)
    aux_eir_func_plr.setCoefficient3xPOW2(0)
    aux_eir_func_plr.setCoefficient4y(0)
    aux_eir_func_plr.setCoefficient5yPOW2(0)
    aux_eir_func_plr.setCoefficient6xTIMESY(0)
    aux_eir_func_plr.setMinimumValueofx(-100)
    aux_eir_func_plr.setMaximumValueofx(100)
    aux_eir_func_plr.setMinimumValueofy(-100)
    aux_eir_func_plr.setMaximumValueofy(100)

    return cap_func_temp, eir_func_temp, eir_func_plr, eir_defrost_adj, cycling_ratio_factor, aux_eir_func_temp, aux_eir_func_plr
  end

  def self.create_curve_bicubic(model, coeff, name, min_x, max_x, min_y, max_y)
    curve = OpenStudio::Model::CurveBicubic.new(model)
    curve.setName(name)
    curve.setCoefficient1Constant(coeff[0])
    curve.setCoefficient2x(coeff[1])
    curve.setCoefficient3xPOW2(coeff[2])
    curve.setCoefficient4y(coeff[3])
    curve.setCoefficient5yPOW2(coeff[4])
    curve.setCoefficient6xTIMESY(coeff[5])
    curve.setCoefficient7xPOW3(coeff[6])
    curve.setCoefficient8yPOW3(coeff[7])
    curve.setCoefficient9xPOW2TIMESY(coeff[8])
    curve.setCoefficient10xTIMESYPOW2(coeff[9])
    curve.setMinimumValueofx(min_x)
    curve.setMaximumValueofx(max_x)
    curve.setMinimumValueofy(min_y)
    curve.setMaximumValueofy(max_y)
    return curve
  end

  def self.set_heat_pump_air_to_water_fuel_fired_heating_curves(component, cap_func_temp, eir_func_temp, _eir_func_plr, _eir_defrost_adj, cycling_ratio_factor, aux_eir_func_temp, _aux_eir_func_plr)
    component.setNormalizedCapacityFunctionofTemperatureCurve(cap_func_temp)
    component.setFuelEnergyInputRatioFunctionofTemperatureCurve(eir_func_temp)
    # component.setFuelEnergyInputRatioFunctionofPLRCurve(eir_func_plr)
    # component.setFuelEnergyInputRatioDefrostAdjustmentCurve(eir_defrost_adj)
    component.setCyclingRatioFactorCurve(cycling_ratio_factor)
    component.setAuxiliaryElectricEnergyInputRatioFunctionofTemperatureCurve(aux_eir_func_temp)
    # component.setAuxiliaryElectricEnergyInputRatioFunctionofPLRCurve(aux_eir_func_plr)
  end
end
