
# CMACs
set_property LOC CMACE4_X0Y1 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[0].mac.* && REF_NAME==CMACE4}]
set_property LOC CMACE4_X0Y2 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[1].mac.* && REF_NAME==CMACE4}]
set_property LOC CMACE4_X0Y4 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[2].mac.* && REF_NAME==CMACE4}]
set_property LOC CMACE4_X0Y5 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[3].mac.* && REF_NAME==CMACE4}]
