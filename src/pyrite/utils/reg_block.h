/* SPDX-License-Identifier: GPL */
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#ifndef REG_BLOCK_H
#define REG_BLOCK_H

#include <stdint.h>
#include <unistd.h>

#include "reg_if.h"

struct reg_block {
	uint32_t type;
	uint32_t version;
	size_t offset;
	struct reg_if *regs;
};

struct reg_block *enumerate_reg_block_list(struct reg_if *regs, size_t base, size_t offset, size_t size);
struct reg_block *find_reg_block(struct reg_block *list, uint32_t type, uint32_t version, int index);
void free_reg_block_list(struct reg_block *list);

#endif /* REG_BLOCK_H */
