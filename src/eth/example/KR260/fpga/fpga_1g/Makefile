# SPDX-License-Identifier: MIT
#
# Copyright (c) 2025 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich
#

# FPGA settings
FPGA_PART = xck26-sfvc784-2LV-c
FPGA_TOP = fpga
FPGA_ARCH = zynquplus

RTL_DIR = ../rtl
LIB_DIR = ../lib
TAXI_SRC_DIR = $(LIB_DIR)/taxi/src

# Files for synthesis
SYN_FILES = $(RTL_DIR)/fpga.sv
SYN_FILES += $(RTL_DIR)/fpga_core.sv
SYN_FILES += $(TAXI_SRC_DIR)/eth/rtl/us/taxi_eth_mac_1g_basex_us.f
SYN_FILES += $(TAXI_SRC_DIR)/eth/rtl/taxi_eth_mac_1g_rgmii_fifo.f
SYN_FILES += $(TAXI_SRC_DIR)/sync/rtl/taxi_sync_reset.sv
SYN_FILES += $(TAXI_SRC_DIR)/sync/rtl/taxi_sync_signal.sv

# XDC files
XDC_FILES += ../syn/fpga.xdc
XDC_FILES += ../syn/gpio.xdc
XDC_FILES += ../syn/phy2.xdc
XDC_FILES += ../syn/phy3.xdc
XDC_FILES += ../syn/sfp.xdc
XDC_FILES += ../syn/eth_rgmii.xdc
XDC_FILES += $(TAXI_SRC_DIR)/eth/syn/vivado/taxi_rgmii_phy_if.tcl
XDC_FILES += $(TAXI_SRC_DIR)/eth/syn/vivado/taxi_eth_mac_fifo.tcl
XDC_FILES += $(TAXI_SRC_DIR)/axis/syn/vivado/taxi_axis_async_fifo.tcl
XDC_FILES += $(TAXI_SRC_DIR)/sync/syn/vivado/taxi_sync_reset.tcl
XDC_FILES += $(TAXI_SRC_DIR)/sync/syn/vivado/taxi_sync_signal.tcl

# IP
IP_TCL_FILES += $(TAXI_SRC_DIR)/eth/rtl/us/taxi_eth_phy_1g_basex_us_gth_156.tcl

# Configuration
CONFIG_TCL_FILES = ./config.tcl

include ../common/vivado.mk

program: $(PROJECT).bit
	echo "open_hw_manager" > program.tcl
	echo "connect_hw_server" >> program.tcl
	echo "open_hw_target" >> program.tcl
	echo "current_hw_device [lindex [get_hw_devices] 0]" >> program.tcl
	echo "refresh_hw_device -update_hw_probes false [current_hw_device]" >> program.tcl
	echo "set_property PROGRAM.FILE {$(PROJECT).bit} [current_hw_device]" >> program.tcl
	echo "program_hw_devices [current_hw_device]" >> program.tcl
	echo "exit" >> program.tcl
	vivado -nojournal -nolog -mode batch -source program.tcl
