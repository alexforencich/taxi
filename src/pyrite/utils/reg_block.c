// SPDX-License-Identifier: GPL
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#include "reg_block.h"

#include <stdlib.h>
#include <stdio.h>

struct reg_block *enumerate_reg_block_list(struct reg_if *regs, size_t base, size_t offset, size_t size)
{
	int max_count = 8;
	struct reg_block *reg_block_list = calloc(max_count, sizeof(struct reg_block));
	int count = 0;

	size_t ptr;

	uint32_t rb_type;
	uint32_t rb_version;
	uint32_t val;

	if (!reg_block_list)
		return NULL;

	while (1) {
		reg_block_list[count].type = 0;
		reg_block_list[count].version = 0;
		reg_block_list[count].regs = NULL;

		if ((offset == 0 && count != 0) || offset >= size)
			break;

		ptr = base + offset;

		for (int k = 0; k < count; k++) {
			if (ptr == reg_block_list[k].offset) {
				fprintf(stderr, "Register blocks form a loop\n");
				goto fail;
			}
		}

		reg_if_read32(regs, ptr+0x00, &rb_type);
		reg_if_read32(regs, ptr+0x04, &rb_version);
		reg_if_read32(regs, ptr+0x08, &val);

		reg_block_list[count].type = rb_type;
		reg_block_list[count].version = rb_version;
		reg_block_list[count].offset = ptr;
		reg_block_list[count].regs = reg_if_open_offset(regs, ptr, size-offset);

		offset = val;

		count++;

		if (count >= max_count) {
			struct reg_block *tmp;
			max_count += 4;
			tmp = realloc(reg_block_list, max_count * sizeof(struct reg_block));
			if (!tmp)
				goto fail;
			reg_block_list = tmp;
		}
	}

	return reg_block_list;
fail:
	free_reg_block_list(reg_block_list);
	return NULL;
}

struct reg_block *find_reg_block(struct reg_block *list, uint32_t type, uint32_t version, int index)
{
	struct reg_block *rb = list;

	while (rb->regs) {
		if (rb->type == type && (!version || rb->version == version)) {
			if (index > 0) {
				index--;
			} else {
				return rb;
			}
		}

		rb++;
	}

	return NULL;
}

void free_reg_block_list(struct reg_block *list)
{
	struct reg_block *rb = list;

	while (rb->regs) {
		reg_if_close(rb->regs);
		rb->regs = NULL;

		rb++;
	}

	free(list);
}
