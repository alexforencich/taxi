/* SPDX-License-Identifier: GPL */
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#ifndef REG_IF_H
#define REG_IF_H

#include <stdint.h>
#include <stddef.h>

struct reg_if {
	const struct reg_if_ops *ops;
	void *priv;
	size_t size;
	size_t offset;
};

struct reg_if_ops {
	int (*read8)(const struct reg_if *reg, size_t offset, uint8_t *value);
	int (*write8)(const struct reg_if *reg, size_t offset, uint8_t value);
	int (*read16)(const struct reg_if *reg, size_t offset, uint16_t *value);
	int (*write16)(const struct reg_if *reg, size_t offset, uint16_t value);
	int (*read32)(const struct reg_if *reg, size_t offset, uint32_t *value);
	int (*write32)(const struct reg_if *reg, size_t offset, uint32_t value);
	int (*read64)(const struct reg_if *reg, size_t offset, uint64_t *value);
	int (*write64)(const struct reg_if *reg, size_t offset, uint64_t value);
	void (*close)(const struct reg_if *reg);
};

int reg_if_read8(const struct reg_if *reg, size_t offset, uint8_t *value);
int reg_if_write8(const struct reg_if *reg, size_t offset, uint8_t value);
int reg_if_read16(const struct reg_if *reg, size_t offset, uint16_t *value);
int reg_if_write16(const struct reg_if *reg, size_t offset, uint16_t value);
int reg_if_read32(const struct reg_if *reg, size_t offset, uint32_t *value);
int reg_if_write32(const struct reg_if *reg, size_t offset, uint32_t value);
int reg_if_read64(const struct reg_if *reg, size_t offset, uint64_t *value);
int reg_if_write64(const struct reg_if *reg, size_t offset, uint64_t value);
void reg_if_close(struct reg_if *reg);

struct reg_if *reg_if_open_raw(void *regs, size_t size);

struct reg_if *reg_if_open_offset(struct reg_if *reg, size_t offset, size_t size);

#endif /* REG_IF_H */
