## Basys 3 clock and center-button reset
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports rst]

## SW3:SW2 select Pan angle, SW1:SW0 select Tilt angle.
## 00 = 0 degrees, 01 = 60 degrees, 10 = 120 degrees, 11 = 180 degrees.
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN W17 IOSTANDARD LVCMOS33} [get_ports {sw[3]}]

## Servo PWM signal outputs
set_property -dict {PACKAGE_PIN G3 IOSTANDARD LVCMOS33} [get_ports pwm_pan];#Sch name = JA10
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports pwm_tilt];#Sch name = JA4
