## constraints.xdc - polymul_top_io for Zynq-7020 (7z020clg484-1)
## 50 MHz clock (20 ns period)

create_clock -period 20.000 -name clk -waveform {0.000 10.000} [get_ports clk]

## Input / output delay (~10% clock period margin)
set_input_delay  -clock clk -max 2.0 [get_ports {rst_n start op_mode[*] ext_we ext_target ext_waddr[*] ext_wcell[*] ext_wdata[*] ext_raddr[*] ext_rcell[*]}]
set_input_delay  -clock clk -min 0.5 [get_ports {rst_n start op_mode[*] ext_we ext_target ext_waddr[*] ext_wcell[*] ext_wdata[*] ext_raddr[*] ext_rcell[*]}]
set_output_delay -clock clk -max 2.0 [get_ports {done ext_rdata[*]}]
set_output_delay -clock clk -min 0.5 [get_ports {done ext_rdata[*]}]

set_clock_uncertainty 0.250 [get_clocks clk]
