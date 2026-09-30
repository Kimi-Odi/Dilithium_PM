## ============================================================
## syn.tcl - DC synthesis for polymul_top  (TSMC 0.13 um, CIC CBDK)
## 把所有 .v / .vh / .sdc 跟此 syn.tcl 放同一目錄
## 然後在此目錄下跑: dc_shell -no_gui -f syn.tcl
## ============================================================

## ---------- Library setup ----------
set company "CIC"
set designer "Student"
set search_path      ". $search_path"
set target_library   "slow.db"
set link_library     "* $target_library dw_foundation.sldb"
set symbol_library   "generic.sdb"
set synthetic_library "dw_foundation.sldb"

set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only          "TRUE"
set verilogout_no_tri             true
set hdlin_enable_presto_for_vhdl  "TRUE"

set sh_enable_line_editing true
set sh_line_editing_mode   emacs
history keep 100
alias h history

set bus_inference_style    {%s[%d]}
set bus_naming_style       {%s[%d]}
set hdlout_internal_busses true
define_name_rules name_rule -allowed "a-z A-Z 0-9 _"      -max_length 255 -type cell
define_name_rules name_rule -allowed "a-z A-Z 0-9 _\[\]"  -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*" "cell"}}

## ---------- Read All Files (current dir) ----------
read_file -format verilog [list \
    mod_add.v       \
    mod_sub.v       \
    mod_mult.v      \
    mod_div4.v      \
    pe0.v           \
    pe1.v           \
    pe2.v           \
    pe3.v           \
    interconnector.v \
    fau.v           \
    tw_addr_gen.v   \
    twiddle_rom.v   \
    fau_top.v       \
    addr_resolver.v \
    poly_mem_4bank.v \
    ctu.v           \
    polymul_top.v   \
]

current_design polymul_top
link

## ---------- Setting Clock Constraints ----------
source -echo -verbose polymul_top.sdc

set_fix_hold [all_clocks]
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

## ---------- Synthesis ----------
compile_ultra

## ---------- Write outputs ----------
write -format ddc     -hierarchy -output "polymul_top_syn.ddc"
write_sdf -version 1.0           "polymul_top_syn.sdf"
write -format verilog -hierarchy -output "polymul_top_syn.v"

report_area              > area.log
report_timing            > timing.log
report_qor               > polymul_top_syn.qor
report_power -hierarchy  > power.log
report_register          > register.log
report_reference         > reference.log
report_constraint -all_violators > constraint.log

puts "===== DC synthesis done ====="