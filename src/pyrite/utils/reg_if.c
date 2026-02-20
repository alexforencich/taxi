// SPDX-License-Identifier: GPL
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#include <stdlib.h>

#include "reg_if.h"

int reg_if_read8(const struct reg_if *reg, size_t offset, uint8_t *value)
{
	if (!reg || !reg->ops || !reg->ops->read8)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->read8(reg, offset, value);
}

int reg_if_write8(const struct reg_if *reg, size_t offset, uint8_t value)
{
	if (!reg || !reg->ops || !reg->ops->write8)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->write8(reg, offset, value);
}

int reg_if_read16(const struct reg_if *reg, size_t offset, uint16_t *value)
{
	if (!reg || !reg->ops || !reg->ops->read16)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->read16(reg, offset, value);
}

int reg_if_write16(const struct reg_if *reg, size_t offset, uint16_t value)
{
	if (!reg || !reg->ops || !reg->ops->write16)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->write16(reg, offset, value);
}

int reg_if_read32(const struct reg_if *reg, size_t offset, uint32_t *value)
{
	if (!reg || !reg->ops || !reg->ops->read32)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->read32(reg, offset, value);
}

int reg_if_write32(const struct reg_if *reg, size_t offset, uint32_t value)
{
	if (!reg || !reg->ops || !reg->ops->write32)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->write32(reg, offset, value);
}

int reg_if_read64(const struct reg_if *reg, size_t offset, uint64_t *value)
{
	if (!reg || !reg->ops || !reg->ops->read64)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->read64(reg, offset, value);
}

int reg_if_write64(const struct reg_if *reg, size_t offset, uint64_t value)
{
	if (!reg || !reg->ops || !reg->ops->write64)
		return -1;
	if (reg->size && offset >= reg->size)
		return -1;
	return reg->ops->write64(reg, offset, value);
}

void reg_if_close(struct reg_if *reg)
{
	if (!reg)
		return;
	if (reg->ops && reg->ops->close)
		reg->ops->close(reg);
	free(reg);
}

static int reg_if_raw_read8(const struct reg_if *reg, size_t offset, uint8_t *value)
{
	uint8_t *regs = reg->priv;
	*value = *(volatile uint8_t *)(regs+offset);
	return 0;
}

static int reg_if_raw_write8(const struct reg_if *reg, size_t offset, uint8_t value)
{
	uint8_t *regs = reg->priv;
	*(volatile uint8_t *)(regs+offset) = value;
	return 0;
}

static int reg_if_raw_read16(const struct reg_if *reg, size_t offset, uint16_t *value)
{
	uint8_t *regs = reg->priv;
	*value = *(volatile uint16_t *)(regs+offset);
	return 0;
}

static int reg_if_raw_write16(const struct reg_if *reg, size_t offset, uint16_t value)
{
	uint8_t *regs = reg->priv;
	*(volatile uint16_t *)(regs+offset) = value;
	return 0;
}

static int reg_if_raw_read32(const struct reg_if *reg, size_t offset, uint32_t *value)
{
	uint8_t *regs = reg->priv;
	*value = *(volatile uint32_t *)(regs+offset);
	return 0;
}

static int reg_if_raw_write32(const struct reg_if *reg, size_t offset, uint32_t value)
{
	uint8_t *regs = reg->priv;
	*(volatile uint32_t *)(regs+offset) = value;
	return 0;
}

static int reg_if_raw_read64(const struct reg_if *reg, size_t offset, uint64_t *value)
{
	uint8_t *regs = reg->priv;
	*value = *(volatile uint64_t *)(regs+offset);
	return 0;
}

static int reg_if_raw_write64(const struct reg_if *reg, size_t offset, uint64_t value)
{
	uint8_t *regs = reg->priv;
	*(volatile uint64_t *)(regs+offset) = value;
	return 0;
}

static const struct reg_if_ops reg_if_raw_ops = {
	.read8 = reg_if_raw_read8,
	.write8 = reg_if_raw_write8,
	.read16 = reg_if_raw_read16,
	.write16 = reg_if_raw_write16,
	.read32 = reg_if_raw_read32,
	.write32 = reg_if_raw_write32,
	.read64 = reg_if_raw_read64,
	.write64 = reg_if_raw_write64,
};

struct reg_if *reg_if_open_raw(void *regs, size_t size)
{
	struct reg_if *reg = calloc(sizeof(struct reg_if), 1);

	if (!reg)
		return NULL;

	reg->ops = &reg_if_raw_ops;
	reg->priv = regs;
	reg->size = size;
	reg->offset = 0;

	return reg;
}

static int reg_if_offset_read8(const struct reg_if *reg, size_t offset, uint8_t *value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_read8(regs, reg->offset+offset, value);
}

static int reg_if_offset_write8(const struct reg_if *reg, size_t offset, uint8_t value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_write8(regs, reg->offset+offset, value);
}

static int reg_if_offset_read16(const struct reg_if *reg, size_t offset, uint16_t *value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_read16(regs, reg->offset+offset, value);
}

static int reg_if_offset_write16(const struct reg_if *reg, size_t offset, uint16_t value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_write16(regs, reg->offset+offset, value);
}

static int reg_if_offset_read32(const struct reg_if *reg, size_t offset, uint32_t *value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_read32(regs, reg->offset+offset, value);
}

static int reg_if_offset_write32(const struct reg_if *reg, size_t offset, uint32_t value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_write32(regs, reg->offset+offset, value);
}

static int reg_if_offset_read64(const struct reg_if *reg, size_t offset, uint64_t *value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_read64(regs, reg->offset+offset, value);
}

static int reg_if_offset_write64(const struct reg_if *reg, size_t offset, uint64_t value)
{
	const struct reg_if *regs = reg->priv;
	return reg_if_write64(regs, reg->offset+offset, value);
}

static const struct reg_if_ops reg_if_offset_ops = {
	.read8 = reg_if_offset_read8,
	.write8 = reg_if_offset_write8,
	.read16 = reg_if_offset_read16,
	.write16 = reg_if_offset_write16,
	.read32 = reg_if_offset_read32,
	.write32 = reg_if_offset_write32,
	.read64 = reg_if_offset_read64,
	.write64 = reg_if_offset_write64,
};

struct reg_if *reg_if_open_offset(struct reg_if *regs, size_t offset, size_t size)
{
	if (!regs)
		return NULL;

	if (regs->size && offset >= regs->size)
		return NULL;

	if (regs->size && (!size || size >= regs->size))
		size = regs->size - offset;

	struct reg_if *reg = calloc(sizeof(struct reg_if), 1);

	if (!reg)
		return NULL;

	reg->ops = &reg_if_offset_ops;
	reg->priv = regs;
	reg->size = size;
	reg->offset = offset;

	return reg;
}
