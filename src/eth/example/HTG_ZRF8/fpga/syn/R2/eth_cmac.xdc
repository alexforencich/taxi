
# CMACs
set_property LOC CMACE4_X0Y0 [get_cells -hierarchical -filter {NAME =~ core_inst/gty_quad[0].mac.* && REF_NAME==CMACE4}]
set_property LOC CMACE4_X0Y1 [get_cells -hierarchical -filter {NAME =~ core_inst/gty_quad[1].mac.* && REF_NAME==CMACE4}]
