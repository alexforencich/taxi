
# CMACs
set_property LOC CMACE4_X0Y7 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[0].mac.mac_inst/cmac.cmac_inst/inst/i_taxi_eth_mac_100g_us_cmac_top/* && REF_NAME==CMACE4}]
set_property LOC CMACE4_X0Y8 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[1].mac.mac_inst/cmac.cmac_inst/inst/i_taxi_eth_mac_100g_us_cmac_top/* && REF_NAME==CMACE4}]
