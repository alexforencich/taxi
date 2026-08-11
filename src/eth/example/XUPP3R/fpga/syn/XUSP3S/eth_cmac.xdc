
# CMACs
set_property LOC CMAC_SITE_X0Y0 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[0].mac.* && REF_NAME==CMAC}]
set_property LOC CMAC_SITE_X0Y1 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[1].mac.* && REF_NAME==CMAC}]
set_property LOC CMAC_SITE_X0Y2 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[2].mac.* && REF_NAME==CMAC}]
set_property LOC CMAC_SITE_X0Y3 [get_cells -hierarchical -filter {NAME =~ core_inst/gt_quad[3].mac.* && REF_NAME==CMAC}]
