# rv32_core.sdc: timing constraints for the rv32-core DE1-SoC build.
# The 50 MHz board clock, which is the design's only clock, and false paths on
# the asynchronous board pins so the switches, buttons, LEDs and displays do
# not have to meet timing.

create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# There is no generated clock: the five stage pipeline meets 20 ns, so the
# divide by two register the single-cycle core needed is gone and every
# register in the design is on CLOCK_50.

derive_clock_uncertainty

# KEY and SW are asynchronous to CLOCK_50. Every one of them lands in a two
# flip flop synchronizer inside de1_soc_top, so the input path itself is not a
# real timing arc.
set_false_path -from [get_ports {KEY[*]}]
set_false_path -from [get_ports {SW[*]}]

# LEDs and seven segment displays drive nothing that samples them, so their
# output paths are not real timing arcs either.
set_false_path -to [get_ports {LEDR[*]}]
set_false_path -to [get_ports {HEX0[*]}]
set_false_path -to [get_ports {HEX1[*]}]
set_false_path -to [get_ports {HEX2[*]}]
set_false_path -to [get_ports {HEX3[*]}]
set_false_path -to [get_ports {HEX4[*]}]
set_false_path -to [get_ports {HEX5[*]}]

# The uart transmit line is an asynchronous serial output: the receiver on the
# other end of the header recovers its own bit timing from the start edge and
# never samples against CLOCK_50, so this is not a real timing arc either.
set_false_path -to [get_ports {GPIO_0[*]}]
