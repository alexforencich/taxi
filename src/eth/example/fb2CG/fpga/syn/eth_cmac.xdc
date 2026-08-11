
# CMACs
set_property LOC CMACE4_X0Y1 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[0].mac.* && REF_NAME==CMACE4}]
set_property LOC CMACE4_X0Y2 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[1].mac.* && REF_NAME==CMACE4}]
