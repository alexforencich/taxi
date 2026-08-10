# SPDX-License-Identifier: CERN-OHL-S-2.0
#
# Copyright (c) 2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

set base_name {taxi_eth_mac_100g_us_cmac}

create_ip -name cmac_usplus -vendor xilinx.com -library ip -module_name $base_name

set_property -dict [list \
    CONFIG.CMAC_CAUI4_MODE {1} \
    CONFIG.NUM_LANES {4x25} \
    CONFIG.USER_INTERFACE {AXIS} \
    CONFIG.GT_DRP_CLK {125} \
    CONFIG.GT_LOCATION {0} \
    CONFIG.TX_FLOW_CONTROL {1} \
    CONFIG.RX_FLOW_CONTROL {1} \
    CONFIG.RX_FORWARD_CONTROL_FRAMES {0} \
    CONFIG.RX_CHECK_ACK {1} \
    CONFIG.INCLUDE_RS_FEC {1} \
    CONFIG.ENABLE_TIME_STAMPING {1} \
    CONFIG.PTP_TRANSPCLK_MODE {1}
] [get_ips $base_name]

# disable LOC constraint
set_property generate_synth_checkpoint false [get_files [get_property IP_FILE [get_ips $base_name]]]
generate_target synthesis [get_files [get_property IP_FILE [get_ips $base_name]]]
set_property is_enabled false [get_files -of_objects [get_files [get_property IP_FILE [get_ips $base_name]]] $base_name.xdc]
