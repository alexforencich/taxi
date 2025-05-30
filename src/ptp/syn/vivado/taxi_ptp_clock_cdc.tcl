# SPDX-License-Identifier: CERN-OHL-S-2.0
#
# Copyright (c) 2019-2025 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# PTP timestamp capture module

foreach inst [get_cells -hier -regexp -filter {(ORIG_REF_NAME =~ "taxi_ptp_clock_cdc(__\w+__\d+)?" ||
        REF_NAME =~ "taxi_ptp_clock_cdc(__\w+__\d+)?")}] {
    puts "Inserting timing constraints for taxi_ptp_clock_cdc instance $inst"

    # get clock periods
    set input_clk [get_clocks -of_objects [get_pins "$inst/src_sync_reg_reg/C"]]
    set output_clk [get_clocks -of_objects [get_pins "$inst/dest_sync_reg_reg/C"]]

    set input_clk_period [if {[llength $input_clk]} {get_property -min PERIOD $input_clk} {expr 1.0}]
    set output_clk_period [if {[llength $output_clk]} {get_property -min PERIOD $output_clk} {expr 1.0}]

    # timestamp synchronization
    set_property ASYNC_REG TRUE [get_cells -hier -regexp ".*/src_ts_(s|ns|step)_sync_reg_reg(\\\[\\d+\\\])?" -filter "PARENT == $inst"]

    if {[llength [get_cells "$inst/src_ts_s_capt_reg_reg[*]"]]} {
        set_max_delay -from [get_cells "$inst/src_ts_s_capt_reg_reg[*]"] -to [get_cells "$inst/src_ts_s_sync_reg_reg[*]"] -datapath_only $output_clk_period
        set_bus_skew  -from [get_cells "$inst/src_ts_s_capt_reg_reg[*]"] -to [get_cells "$inst/src_ts_s_sync_reg_reg[*]"] $input_clk_period
    }

    set_max_delay -from [get_cells "$inst/src_ts_ns_capt_reg_reg[*]"] -to [get_cells "$inst/src_ts_ns_sync_reg_reg[*]"] -datapath_only $output_clk_period
    set_bus_skew  -from [get_cells "$inst/src_ts_ns_capt_reg_reg[*]"] -to [get_cells "$inst/src_ts_ns_sync_reg_reg[*]"] $input_clk_period

    if {[llength [get_cells "$inst/src_ts_step_capt_reg_reg"]]} {
        set_max_delay -from [get_cells "$inst/src_ts_step_capt_reg_reg"] -to [get_cells "$inst/src_ts_step_sync_reg_reg"] -datapath_only $output_clk_period
        set_bus_skew  -from [get_cells "$inst/src_ts_step_capt_reg_reg"] -to [get_cells "$inst/src_ts_step_sync_reg_reg"] $input_clk_period
    }

    # sample clock
    set sync_ffs [get_cells -quiet -hier -regexp ".*/src_sync_sample_sync\[12\]_reg_reg" -filter "PARENT == $inst"]

    if {[llength $sync_ffs]} {
        set_property ASYNC_REG TRUE $sync_ffs

        set_max_delay -from [get_cells "$inst/src_sync_reg_reg"] -to [get_cells "$inst/src_sync_sample_sync1_reg_reg"] -datapath_only $input_clk_period
    }

    set sync_ffs [get_cells -quiet -hier -regexp ".*/dest_sync_sample_sync\[12\]_reg_reg" -filter "PARENT == $inst"]

    if {[llength $sync_ffs]} {
        set_property ASYNC_REG TRUE $sync_ffs

        set_max_delay -from [get_cells "$inst/dest_sync_reg_reg"] -to [get_cells "$inst/dest_sync_sample_sync1_reg_reg"] -datapath_only $output_clk_period
    }

    # sample update sync
    set sync_ffs [get_cells -quiet -hier -regexp ".*/sample_update_sync\[123\]_reg_reg" -filter "PARENT == $inst"]

    if {[llength $sync_ffs]} {
        set_property ASYNC_REG TRUE $sync_ffs

        set src_clk [get_clocks -of_objects [get_pins "$inst/sample_update_reg_reg/C"]]

        set src_clk_period [if {[llength $src_clk]} {get_property -min PERIOD $src_clk} {expr 1.0}]

        set_max_delay -from [get_cells "$inst/sample_update_reg_reg"] -to [get_cells "$inst/sample_update_sync1_reg_reg"] -datapath_only $src_clk_period

        set_max_delay -from [get_cells "$inst/sample_acc_out_reg_reg[*]"] -to [get_cells $inst/sample_acc_sync_reg_reg[*]] -datapath_only $src_clk_period
        set_bus_skew  -from [get_cells "$inst/sample_acc_out_reg_reg[*]"] -to [get_cells $inst/sample_acc_sync_reg_reg[*]] $output_clk_period
    }

    # timestamp transfer sync
    set sync_ffs [get_cells -quiet -hier -regexp ".*/src_sync_sync\[12\]_reg_reg" -filter "PARENT == $inst"]

    if {[llength $sync_ffs]} {
        set_property ASYNC_REG TRUE $sync_ffs

        set_max_delay -from [get_cells "$inst/src_sync_reg_reg"] -to [get_cells "$inst/src_sync_sync1_reg_reg"] -datapath_only $input_clk_period
    }

    # phase sync
    set sync_ffs [get_cells -quiet -hier -regexp ".*/src_phase_sync_sync\[12\]_reg_reg" -filter "PARENT == $inst"]

    if {[llength $sync_ffs]} {
        set_property ASYNC_REG TRUE $sync_ffs

        # hunt down source
        set dest_pins [get_pins -of_objects [get_cells "$inst/src_phase_sync_sync1_reg_reg"] -filter {REF_PIN_NAME == "D"}]
        set nets [get_nets -segments -of_objects $dest_pins]
        set source_pins [get_pins -of_objects $nets -filter {IS_LEAF && DIRECTION == "OUT"}]
        set source [get_cells -of_objects $source_pins]

        if {[llength $source]} {
            set_max_delay -from $source -to [get_cells "$inst/src_phase_sync_sync1_reg_reg"] -datapath_only $input_clk_period
        }
    }
}
