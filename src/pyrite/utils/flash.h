/* SPDX-License-Identifier: GPL */
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#ifndef FLASH_H
#define FLASH_H

#include <stdint.h>
#include <unistd.h>

#include "reg_if.h"

#define FLASH_ERASE_REGIONS 2

struct flash_driver;
struct flash_ops;

struct flash_erase_region_info {
	size_t block_count;
	size_t block_size;
	size_t region_start;
	size_t region_end;
};

struct flash_device {
	const struct flash_driver *driver;
	const struct flash_ops *ops;

	const struct reg_if *reg;

	size_t ctrl_reg_offset;
	size_t addr_reg_offset;
	size_t data_reg_offset;

	size_t size;
	int data_width;

	size_t write_buffer_size;
	size_t erase_block_size;

	int protocol;
	int bulk_protocol;

	int read_dummy_cycles;

	int erase_region_count;
	struct flash_erase_region_info erase_region[FLASH_ERASE_REGIONS];
};

struct flash_ops {
	void (*init)(struct flash_device *fdev);
	int (*sector_erase)(struct flash_device *fdev, size_t addr);
	int (*buffered_program)(struct flash_device *fdev, size_t addr, size_t len, const void *src);
};

struct flash_driver {
	int (*init)(struct flash_device *fdev);
	void (*release)(struct flash_device *fdev);
	int (*read)(struct flash_device *fdev, size_t addr, size_t len, void *dest);
	int (*write)(struct flash_device *fdev, size_t addr, size_t len, const void *src);
	int (*erase)(struct flash_device *fdev, size_t addr, size_t len);
};

struct flash_device *flash_open_spi(int data_width, const struct reg_if *reg, size_t ctrl_reg_offset);
struct flash_device *flash_open_bpi(int data_width, const struct reg_if *reg, size_t ctrl_reg_offset, size_t addr_reg_offset, size_t data_reg_offset);
void flash_release(struct flash_device *fdev);
int flash_read(struct flash_device *fdev, size_t addr, size_t len, void *dest);
int flash_write(struct flash_device *fdev, size_t addr, size_t len, const void *src);
int flash_erase(struct flash_device *fdev, size_t addr, size_t len);

#endif /* FLASH_H */
