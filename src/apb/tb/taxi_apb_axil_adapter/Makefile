# SPDX-License-Identifier: CERN-OHL-S-2.0
#
# Copyright (c) 2020-2026 FPGA Ninja, LLC
#
# Authors:
# - Alex Forencich

TOPLEVEL_LANG = verilog

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

RTL_DIR = ../../rtl
LIB_DIR = ../../lib
TAXI_SRC_DIR = $(LIB_DIR)/taxi/src

DUT      = taxi_apb_axil_adapter
COCOTB_TEST_MODULES = test_$(DUT)
COCOTB_TOPLEVEL     = test_$(DUT)
MODULE   = $(COCOTB_TEST_MODULES)
TOPLEVEL = $(COCOTB_TOPLEVEL)
VERILOG_SOURCES += $(COCOTB_TOPLEVEL).sv
VERILOG_SOURCES += $(RTL_DIR)/$(DUT).sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_apb_if.sv
VERILOG_SOURCES += $(TAXI_SRC_DIR)/axi/rtl/taxi_axil_if.sv

# handle file list files
process_f_file = $(call process_f_files,$(addprefix $(dir $1),$(shell cat $1)))
process_f_files = $(foreach f,$1,$(if $(filter %.f,$f),$(call process_f_file,$f),$f))
uniq_base = $(if $1,$(call uniq_base,$(foreach f,$1,$(if $(filter-out $(notdir $(lastword $1)),$(notdir $f)),$f,))) $(lastword $1))
VERILOG_SOURCES := $(call uniq_base,$(call process_f_files,$(VERILOG_SOURCES)))

# module parameters
export PARAM_ADDR_W := 32
export PARAM_APB_DATA_W := 32
export PARAM_APB_STRB_W := $(shell expr $(PARAM_APB_DATA_W) / 8 )
export PARAM_AXIL_DATA_W := 32
export PARAM_AXIL_STRB_W := $(shell expr $(PARAM_AXIL_DATA_W) / 8 )
export PARAM_PAUSER_EN := 0
export PARAM_PAUSER_W := 1
export PARAM_PWUSER_EN := 0
export PARAM_PWUSER_W := 1
export PARAM_PBUSER_EN := 0
export PARAM_PBUSER_W := 1
export PARAM_PRUSER_EN := 0
export PARAM_PRUSER_W := 1

ifeq ($(SIM), icarus)
	PLUSARGS += -fst

	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P $(COCOTB_TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))
else ifeq ($(SIM), verilator)
	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))

	ifeq ($(WAVES), 1)
		COMPILE_ARGS += --trace-fst
		VERILATOR_TRACE = 1
	endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
