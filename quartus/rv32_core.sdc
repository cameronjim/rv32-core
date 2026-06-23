# rv32_core.sdc: timing constraints for the rv32-core DE1-SoC build.
# The 50 MHz board clock, the 25 MHz CPU clock derived from it, and false paths
# on the asynchronous board pins so the switches, buttons, LEDs and displays do
# not have to meet timing.

create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]

# The CPU domain runs at 25 MHz off the cpu_clk_div toggle register in
# de1_soc_top. The single-cycle core closed timing at only 29 MHz, so the
# divider buys the margin; the phase 5 pipeline is the path back to 50 MHz.
# Without this generated clock the divided domain would be unconstrained.
create_generated_clock -source [get_ports CLOCK_50] -divide_by 2 \
    -name cpu_clk [get_registers {cpu_clk_div}]

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
