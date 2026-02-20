// SPDX-License-Identifier: GPL
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#include "flash.h"

#include <stdlib.h>

extern const struct flash_driver spi_flash_driver;
extern const struct flash_driver bpi_flash_driver;

struct flash_device *flash_open_spi(int data_width, const struct reg_if *reg, size_t ctrl_reg_offset)
{
	struct flash_device *fdev;

	if (!reg)
		return NULL;

	fdev = calloc(1, sizeof(struct flash_device));

	if (!fdev)
		return NULL;

	fdev->driver = &spi_flash_driver;

	fdev->data_width = data_width;

	fdev->reg = reg;
	fdev->ctrl_reg_offset = ctrl_reg_offset;

	if (fdev->driver->init(fdev)) {
		goto err;
	}

	return fdev;

err:
	flash_release(fdev);
	return NULL;
}

struct flash_device *flash_open_bpi(int data_width, const struct reg_if *reg, size_t ctrl_reg_offset, size_t addr_reg_offset, size_t data_reg_offset)
{
	struct flash_device *fdev;

	if (!reg)
		return NULL;

	fdev = calloc(1, sizeof(struct flash_device));

	if (!fdev)
		return NULL;

	fdev->driver = &bpi_flash_driver;

	fdev->data_width = data_width;

	fdev->reg = reg;
	fdev->ctrl_reg_offset = ctrl_reg_offset;
	fdev->addr_reg_offset = addr_reg_offset;
	fdev->data_reg_offset = data_reg_offset;

	if (fdev->driver->init(fdev)) {
		goto err;
	}

	return fdev;

err:
	flash_release(fdev);
	return NULL;
}

void flash_release(struct flash_device *fdev)
{
	if (!fdev)
		return;

	fdev->driver->release(fdev);

	free(fdev);
}

int flash_read(struct flash_device *fdev, size_t addr, size_t len, void *dest)
{
	if (!fdev)
		return -1;

	return fdev->driver->read(fdev, addr, len, dest);
}

int flash_write(struct flash_device *fdev, size_t addr, size_t len, const void *src)
{
	if (!fdev)
		return -1;

	return fdev->driver->write(fdev, addr, len, src);
}

int flash_erase(struct flash_device *fdev, size_t addr, size_t len)
{
	if (!fdev)
		return -1;

	return fdev->driver->erase(fdev, addr, len);
}
