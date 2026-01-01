# SPDX-License-Identifier: GPL
# Copyright (c) 2025 FPGA Ninja

ifneq ($(KERNELRELEASE),)

obj-m += cndm_proto.o
cndm_proto-y += cndm_proto_main.o
cndm_proto-y += cndm_proto_netdev.o
cndm_proto-y += cndm_proto_tx.o
cndm_proto-y += cndm_proto_rx.o

ifneq ($(DEBUG),)
ccflags-y += -DDEBUG
endif

else

ifneq ($(KERNEL_SRC),)
KDIR ?= $(KERNEL_SRC)
endif

KDIR ?= /lib/modules/$(shell uname -r)/build

all: modules

help modules modules_install clean:
	$(MAKE) -C $(KDIR) M=$(shell pwd) $@

install: modules_install

endif
