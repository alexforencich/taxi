// SPDX-License-Identifier: GPL
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#include "flash.h"

#include <stdio.h>
#include <stdlib.h>

#define SPI_CMD_RESET_ENABLE                 0x66
#define SPI_CMD_RESET_MEMORY                 0x99
#define SPI_CMD_READ_ID                      0x9F
#define SPI_CMD_READ                         0x03
#define SPI_CMD_FAST_READ                    0x0B
#define SPI_CMD_FAST_READ_DUAL_OUT           0x3B
#define SPI_CMD_FAST_READ_DUAL_IO            0xBB
#define SPI_CMD_FAST_READ_QUAD_OUT           0x6B
#define SPI_CMD_FAST_READ_QUAD_IO            0xEB
#define SPI_CMD_DTR_FAST_READ                0x0D
#define SPI_CMD_DTR_FAST_READ_DUAL_OUT       0x3D
#define SPI_CMD_DTR_FAST_READ_DUAL_IO        0xBD
#define SPI_CMD_DTR_FAST_READ_QUAD_OUT       0x6D
#define SPI_CMD_DTR_FAST_READ_QUAD_IO        0xED
#define SPI_CMD_4B_READ                      0x13
#define SPI_CMD_4B_FAST_READ                 0x0C
#define SPI_CMD_4B_FAST_READ_DUAL_OUT        0x3C
#define SPI_CMD_4B_FAST_READ_DUAL_IO         0xBC
#define SPI_CMD_4B_FAST_READ_QUAD_OUT        0x6C
#define SPI_CMD_4B_FAST_READ_QUAD_IO         0xEC
#define SPI_CMD_4B_DTR_FAST_READ             0x0E
#define SPI_CMD_4B_DTR_FAST_READ_DUAL_IO     0xBE
#define SPI_CMD_4B_DTR_FAST_READ_QUAD_IO     0xEE
#define SPI_CMD_WRITE_ENABLE                 0x06
#define SPI_CMD_WRITE_DISABLE                0x04
#define SPI_CMD_READ_STATUS_REG              0x05
#define SPI_CMD_READ_FLAG_STATUS_REG         0x70
#define SPI_CMD_READ_NV_CONFIG_REG           0xB5
#define SPI_CMD_READ_V_CONFIG_REG            0x85
#define SPI_CMD_READ_EV_CONFIG_REG           0x65
#define SPI_CMD_READ_EXT_ADDR_REG            0xC8
#define SPI_CMD_WRITE_STATUS_REG             0x01
#define SPI_CMD_WRITE_NV_CONFIG_REG          0xB1
#define SPI_CMD_WRITE_V_CONFIG_REG           0x81
#define SPI_CMD_WRITE_EV_CONFIG_REG          0x61
#define SPI_CMD_WRITE_EXT_ADDR_REG           0xC5
#define SPI_CMD_CLEAR_FLAG_STATUS_REG        0x50
#define SPI_CMD_PAGE_PROGRAM                 0x02
#define SPI_CMD_PAGE_PROGRAM_DUAL_IN         0xA2
#define SPI_CMD_PAGE_PROGRAM_DUAL_IN_EXT     0xD2
#define SPI_CMD_PAGE_PROGRAM_QUAD_IN         0x32
#define SPI_CMD_PAGE_PROGRAM_QUAD_IN_EXT     0x38
#define SPI_CMD_4B_PAGE_PROGRAM              0x12
#define SPI_CMD_4B_PAGE_PROGRAM_QUAD_IN      0x34
#define SPI_CMD_4B_PAGE_PROGRAM_QUAD_IN_EXT  0x3E
#define SPI_CMD_32KB_SUBSECTOR_ERASE         0x52
#define SPI_CMD_4KB_SUBSECTOR_ERASE          0x20
#define SPI_CMD_SECTOR_ERASE                 0xD8
#define SPI_CMD_BULK_ERASE                   0xC7
#define SPI_CMD_4B_4KB_SUBSECTOR_ERASE       0x21
#define SPI_CMD_4B_SECTOR_ERASE              0xDC
#define SPI_CMD_PROGRAM_SUSPEND              0x75
#define SPI_CMD_PROGRAM_RESUME               0x7A
#define SPI_CMD_READ_OTP_ARRAY               0x4B
#define SPI_CMD_PROGRAM_OTP_ARRAY            0x42
#define SPI_CMD_ENTER_4B_ADDR_MODE           0xB7
#define SPI_CMD_EXIT_4B_ADDR_MODE            0xE9
#define SPI_CMD_ENTER_QUAD_IO_MODE           0x35
#define SPI_CMD_EXIT_QUAD_IO_MODE            0xF5
#define SPI_CMD_ENTER_DEEP_POWER_DOWN        0xB9
#define SPI_CMD_EXIT_DEEP_POWER_DOWN         0xAB
#define SPI_CMD_READ_SECTOR_PROTECTION       0x2D
#define SPI_CMD_PRGM_SECTOR_PROTECTION       0x2C
#define SPI_CMD_READ_V_LOCK_BITS             0xE8
#define SPI_CMD_WRITE_V_LOCK_BITS            0xE5
#define SPI_CMD_4B_READ_V_LOCK_BITS          0xE0
#define SPI_CMD_4B_WRITE_V_LOCK_BITS         0xE1
#define SPI_CMD_READ_NV_LOCK_BITS            0xE2
#define SPI_CMD_PRGM_NV_LOCK_BITS            0xE3
#define SPI_CMD_ERASE_NV_LOCK_BITS           0xE4
#define SPI_CMD_READ_GLOBAL_FREEZE_BIT       0xA7
#define SPI_CMD_WRITE_GLOBAL_FREEZE_BIT      0xA6
#define SPI_CMD_READ_PASSWORD                0x27
#define SPI_CMD_WRITE_PASSWORD               0x28
#define SPI_CMD_UNLOCK_PASSWORD              0x29

// Macronix
#define SPI_MXIC_CMD_RDCR   0x15
#define SPI_MXIC_CMD_RDSCUR 0x2B
#define SPI_MXIC_CMD_WRSCUR 0x2F
#define SPI_MXIC_CMD_GBLK   0x7E
#define SPI_MXIC_CMD_GBULK  0x98
#define SPI_MXIC_CMD_WRLR   0x2C
#define SPI_MXIC_CMD_RDLR   0x2D
#define SPI_MXIC_CMD_WRSPB  0xE3
#define SPI_MXIC_CMD_ESSPB  0xE4
#define SPI_MXIC_CMD_RDSPB  0xE2
#define SPI_MXIC_CMD_WRDPB  0xE1
#define SPI_MXIC_CMD_RDDPB  0xE0

#define SPI_PROTO_STR       0
#define SPI_PROTO_DTR       1
#define SPI_PROTO_DUAL_STR  2
#define SPI_PROTO_DUAL_DTR  3
#define SPI_PROTO_QUAD_STR  4
#define SPI_PROTO_QUAD_DTR  5

#define SPI_PAGE_SIZE       0x100
#define SPI_SUBSECTOR_SIZE  0x1000
#define SPI_SECTOR_SIZE     0x10000

#define FLASH_D_0     (1 << 0)
#define FLASH_D_1     (1 << 1)
#define FLASH_D_2     (1 << 2)
#define FLASH_D_3     (1 << 3)
#define FLASH_D_01    (FLASH_D_0 | FLASH_D_1)
#define FLASH_D_0123  (FLASH_D_0 | FLASH_D_1 | FLASH_D_2 | FLASH_D_3)
#define FLASH_OE_0    (1 << 8)
#define FLASH_OE_1    (1 << 9)
#define FLASH_OE_2    (1 << 10)
#define FLASH_OE_3    (1 << 11)
#define FLASH_OE_01   (FLASH_OE_0 | FLASH_OE_1)
#define FLASH_OE_0123 (FLASH_OE_0 | FLASH_OE_1 | FLASH_OE_2 | FLASH_OE_3)
#define FLASH_CLK     (1 << 16)
#define FLASH_CS_N    (1 << 17)

static uint32_t ctrl_reg_read(struct flash_device *fdev)
{
	uint32_t reg_val = 0;
	reg_if_read32(fdev->reg, fdev->ctrl_reg_offset, &reg_val);
	return reg_val;
}

static void ctrl_reg_write(struct flash_device *fdev, uint32_t val)
{
	reg_if_write32(fdev->reg, fdev->ctrl_reg_offset, val);
}

void spi_flash_select(struct flash_device *fdev)
{
	ctrl_reg_write(fdev, 0);
}

void spi_flash_deselect(struct flash_device *fdev)
{
	ctrl_reg_write(fdev, FLASH_CS_N);
}

uint8_t spi_flash_read_byte(struct flash_device *fdev, int protocol)
{
	uint8_t val = 0;

	switch (protocol){
	case SPI_PROTO_STR:
		for (int i = 7; i >= 0; i--) {
			ctrl_reg_write(fdev, 0);
			ctrl_reg_read(fdev); // dummy read
			val |= ((ctrl_reg_read(fdev) & FLASH_D_1) != 0) << i;
			ctrl_reg_write(fdev, FLASH_CLK);
			ctrl_reg_read(fdev); // dummy read
		}
		break;
	case SPI_PROTO_DTR:
		break;
	case SPI_PROTO_DUAL_STR:
		for (int i = 6; i >= 0; i -= 2) {
			ctrl_reg_write(fdev, 0);
			ctrl_reg_read(fdev); // dummy read
			val |= (ctrl_reg_read(fdev) & FLASH_D_01) << i;
			ctrl_reg_write(fdev, FLASH_CLK);
			ctrl_reg_read(fdev); // dummy read
		}
		break;
	case SPI_PROTO_DUAL_DTR:
		break;
	case SPI_PROTO_QUAD_STR:
		for (int i = 4; i >= 0; i -= 4) {
			ctrl_reg_write(fdev, 0);
			ctrl_reg_read(fdev); // dummy read
			val |= (ctrl_reg_read(fdev) & FLASH_D_0123) << i;
			ctrl_reg_write(fdev, FLASH_CLK);
			ctrl_reg_read(fdev); // dummy read
		}
		break;
	case SPI_PROTO_QUAD_DTR:
		break;
	}

	ctrl_reg_write(fdev, 0);

	return val;
}

void spi_flash_write_byte(struct flash_device *fdev, uint8_t val, int protocol)
{
	uint8_t bit;

	switch (protocol){
	case SPI_PROTO_STR:
		for (int i = 7; i >= 0; i--) {
			bit = (val >> i) & 0x1;
			ctrl_reg_write(fdev, bit | FLASH_OE_0);
			ctrl_reg_read(fdev); // dummy read
			ctrl_reg_write(fdev, bit | FLASH_OE_0 | FLASH_CLK);
			ctrl_reg_read(fdev); // dummy read
		}
		break;
	case SPI_PROTO_DTR:
		break;
	case SPI_PROTO_DUAL_STR:
		for (int i = 6; i >= 0; i -= 2) {
			bit = (val >> i) & 0x3;
			ctrl_reg_write(fdev, bit | FLASH_OE_01);
			ctrl_reg_read(fdev); // dummy read
			ctrl_reg_write(fdev, bit | FLASH_OE_01 | FLASH_CLK);
			ctrl_reg_read(fdev); // dummy read
		}
		break;
	case SPI_PROTO_DUAL_DTR:
		break;
	case SPI_PROTO_QUAD_STR:
		for (int i = 4; i >= 0; i -= 4) {
			bit = (val >> i) & 0xf;
			ctrl_reg_write(fdev, bit | FLASH_OE_0123);
			ctrl_reg_read(fdev); // dummy read
			ctrl_reg_write(fdev, bit | FLASH_OE_0123 | FLASH_CLK);
			ctrl_reg_read(fdev); // dummy read
		}
		break;
	case SPI_PROTO_QUAD_DTR:
		break;
	}

	ctrl_reg_write(fdev, 0);
}

void spi_flash_write_addr(struct flash_device *fdev, size_t addr, int protocol)
{
	spi_flash_write_byte(fdev, (addr >> 16) & 0xff, protocol);
	spi_flash_write_byte(fdev, (addr >> 8) & 0xff, protocol);
	spi_flash_write_byte(fdev, (addr >> 0) & 0xff, protocol);
}

void spi_flash_write_addr_4b(struct flash_device *fdev, size_t addr, int protocol)
{
	spi_flash_write_byte(fdev, (addr >> 24) & 0xff, protocol);
	spi_flash_write_byte(fdev, (addr >> 16) & 0xff, protocol);
	spi_flash_write_byte(fdev, (addr >> 8) & 0xff, protocol);
	spi_flash_write_byte(fdev, (addr >> 0) & 0xff, protocol);
}

void spi_flash_write_enable(struct flash_device *fdev, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_WRITE_ENABLE, protocol);
	spi_flash_deselect(fdev);
}

void spi_flash_write_disable(struct flash_device *fdev, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_WRITE_DISABLE, protocol);
	spi_flash_deselect(fdev);
}

uint8_t spi_flash_read_status_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_STATUS_REG, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

void spi_flash_write_status_reg(struct flash_device *fdev, uint8_t val, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_WRITE_STATUS_REG, protocol);
	spi_flash_write_byte(fdev, val, protocol);
	spi_flash_deselect(fdev);
}

void spi_mxic_flash_write_status_cfg_reg(struct flash_device *fdev, uint8_t status, uint8_t cfg, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_WRITE_STATUS_REG, protocol);
	spi_flash_write_byte(fdev, status, protocol);
	spi_flash_write_byte(fdev, cfg, protocol);
	spi_flash_deselect(fdev);
}

uint8_t spi_mxic_flash_read_cfg_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_MXIC_CMD_RDCR, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

uint8_t spi_mxic_flash_read_security_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_MXIC_CMD_RDSCUR, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

uint8_t spi_flash_read_flag_status_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_FLAG_STATUS_REG, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

void spi_flash_clear_flag_status_reg(struct flash_device *fdev, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_CLEAR_FLAG_STATUS_REG, protocol);
	spi_flash_deselect(fdev);
}

uint16_t spi_flash_read_nv_cfg_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_NV_CONFIG_REG, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	val |= (uint16_t)spi_flash_read_byte(fdev, protocol) << 8;
	spi_flash_deselect(fdev);
	return val;
}

uint8_t spi_flash_read_volatile_cfg_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_V_CONFIG_REG, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

void spi_flash_write_volatile_config_reg(struct flash_device *fdev, uint8_t val, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_WRITE_V_CONFIG_REG, protocol);
	spi_flash_write_byte(fdev, val, protocol);
	spi_flash_deselect(fdev);
}

uint8_t spi_flash_read_ev_cfg_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_EV_CONFIG_REG, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

void spi_flash_write_ev_cfg_reg(struct flash_device *fdev, uint8_t val, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_WRITE_EV_CONFIG_REG, protocol);
	spi_flash_write_byte(fdev, val, protocol);
	spi_flash_deselect(fdev);
}

uint8_t spi_flash_read_ext_addr_reg(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_EXT_ADDR_REG, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

void spi_flash_write_ext_addr_reg(struct flash_device *fdev, uint8_t val, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_WRITE_EXT_ADDR_REG, protocol);
	spi_flash_write_byte(fdev, val, protocol);
	spi_flash_deselect(fdev);
}

uint16_t spi_flash_read_sector_protection_reg(struct flash_device *fdev, int protocol)
{
	uint16_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_SECTOR_PROTECTION, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	val |= (uint16_t)spi_flash_read_byte(fdev, protocol) << 8;
	spi_flash_deselect(fdev);
	return val;
}

uint8_t spi_flash_read_global_freeze_bit(struct flash_device *fdev, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_GLOBAL_FREEZE_BIT, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

uint8_t spi_flash_read_nv_lock_bits(struct flash_device *fdev, size_t addr, int protocol)
{
	uint8_t val;
	spi_flash_write_byte(fdev, SPI_CMD_READ_NV_LOCK_BITS, protocol);
	spi_flash_write_addr_4b(fdev, addr, protocol);
	val = spi_flash_read_byte(fdev, protocol);
	spi_flash_deselect(fdev);
	return val;
}

void spi_flash_unlock_password(struct flash_device *fdev, char *val, int protocol)
{
	spi_flash_write_byte(fdev, SPI_CMD_UNLOCK_PASSWORD, protocol);
	for (int k = 0; k < 8; k++)
		spi_flash_write_byte(fdev, val[k], protocol);
	spi_flash_deselect(fdev);
}

void spi_flash_reset(struct flash_device *fdev, int protocol)
{
	spi_flash_deselect(fdev);
	spi_flash_write_byte(fdev, SPI_CMD_RESET_ENABLE, protocol);
	spi_flash_deselect(fdev);
	ctrl_reg_read(fdev); // dummy read
	ctrl_reg_read(fdev); // dummy read
	spi_flash_write_byte(fdev, SPI_CMD_RESET_MEMORY, protocol);
	spi_flash_deselect(fdev);
	ctrl_reg_read(fdev); // dummy read
	ctrl_reg_read(fdev); // dummy read
}

void spi_flash_release(struct flash_device *fdev)
{
	spi_flash_deselect(fdev);
}

int spi_flash_init(struct flash_device *fdev)
{
	int ret = 0;

	if (!fdev)
		return -1;

	spi_flash_reset(fdev, SPI_PROTO_STR);

	spi_flash_write_byte(fdev, SPI_CMD_READ_ID, SPI_PROTO_STR);
	int mfr_id = spi_flash_read_byte(fdev, SPI_PROTO_STR);
	int mem_type = spi_flash_read_byte(fdev, SPI_PROTO_STR);
	int mem_capacity = spi_flash_read_byte(fdev, SPI_PROTO_STR);
	spi_flash_deselect(fdev);

	printf("Manufacturer ID: 0x%02x\n", mfr_id);
	printf("Memory type: 0x%02x\n", mem_type);
	printf("Memory capacity: 0x%02x\n", mem_capacity);

	if (mfr_id == 0 || mfr_id == 0xff) {
		fprintf(stderr, "Failed to read flash ID\n");
		spi_flash_deselect(fdev);
		return -1;
	}

	switch (mfr_id) {
	case 0x20:
		// Micron
		printf("Manufacturer: Micron\n");
		// convert from BCD
		mem_capacity = (mem_capacity & 0xf) + (((mem_capacity >> 4) & 0xf) * 10);
		fdev->size = ((size_t)1) << (mem_capacity+6);
		break;
	case 0xC2:
		// Macronix
		printf("Manufacturer: Macronix\n");
		fdev->size = ((size_t)1) << (mem_capacity-32);
		break;
	default:
		// unknown
		fprintf(stderr, "Unknown flash ID\n");
		spi_flash_deselect(fdev);
		return -1;
	}

	printf("Flash size: %ld MB\n", fdev->size / (1 << 20));

	fdev->protocol = SPI_PROTO_STR;
	fdev->bulk_protocol = SPI_PROTO_STR;
	fdev->read_dummy_cycles = 0;
	fdev->write_buffer_size = SPI_PAGE_SIZE;
	fdev->erase_block_size = SPI_SUBSECTOR_SIZE;

	printf("Write buffer size: %ld B\n", fdev->write_buffer_size);
	printf("Erase block size: %ld B\n", fdev->erase_block_size);

	printf("Status register: 0x%02x\n", spi_flash_read_status_reg(fdev, SPI_PROTO_STR));

	switch (mfr_id) {
	case 0x20:
		// Micron
		printf("Flag status register: 0x%02x\n", spi_flash_read_flag_status_reg(fdev, SPI_PROTO_STR));
		printf("Nonvolatile config register: 0x%04x\n", spi_flash_read_nv_cfg_reg(fdev, SPI_PROTO_STR));
		printf("Volatile config register: 0x%02x\n", spi_flash_read_volatile_cfg_reg(fdev, SPI_PROTO_STR));
		printf("Enhanced volatile config register: 0x%02x\n", spi_flash_read_ev_cfg_reg(fdev, SPI_PROTO_STR));
		printf("Global freeze bit: 0x%02x\n", spi_flash_read_global_freeze_bit(fdev, SPI_PROTO_STR));
		printf("Sector protection register: 0x%04x\n", spi_flash_read_sector_protection_reg(fdev, SPI_PROTO_STR));

		if (fdev->data_width == 4) {
			spi_flash_write_volatile_config_reg(fdev, 0xFB, SPI_PROTO_STR);
			fdev->bulk_protocol = SPI_PROTO_QUAD_STR;
			fdev->read_dummy_cycles = 10;
		}

		break;
	case 0xC2:
		// Macronix
		printf("Config register: 0x%02x\n", spi_mxic_flash_read_cfg_reg(fdev, SPI_PROTO_STR));
		printf("Sector protection register: 0x%04x\n", spi_flash_read_sector_protection_reg(fdev, SPI_PROTO_STR));
		printf("Security register: 0x%02x\n", spi_mxic_flash_read_security_reg(fdev, SPI_PROTO_STR));

		if (fdev->data_width == 4) {
			spi_mxic_flash_write_status_cfg_reg(fdev, 0x40, 0x07, SPI_PROTO_STR);
			fdev->bulk_protocol = SPI_PROTO_QUAD_STR;
			fdev->read_dummy_cycles = 6;
		}

		break;
	}

	spi_flash_release(fdev);
	return ret;
}

int spi_flash_read(struct flash_device *fdev, size_t addr, size_t len, void *dest)
{
	char *d = dest;

	int protocol = SPI_PROTO_STR;

	if (fdev->data_width == 4) {
		protocol = SPI_PROTO_QUAD_STR;
	}

	if (fdev->size > 0x1000000) {
		// four byte address read
		if (protocol == SPI_PROTO_QUAD_STR) {
			spi_flash_write_byte(fdev, SPI_CMD_4B_FAST_READ_QUAD_IO, SPI_PROTO_STR);
		} else {
			spi_flash_write_byte(fdev, SPI_CMD_4B_READ, SPI_PROTO_STR);
		}
		spi_flash_write_addr_4b(fdev, addr, protocol);
	} else {
		// normal read
		if (protocol == SPI_PROTO_QUAD_STR) {
			spi_flash_write_byte(fdev, SPI_CMD_FAST_READ_QUAD_IO, SPI_PROTO_STR);
		} else {
			spi_flash_write_byte(fdev, SPI_CMD_READ, SPI_PROTO_STR);
		}
		spi_flash_write_addr(fdev, addr, protocol);
	}

	if (protocol != SPI_PROTO_STR) {
		// dummy cycles
		for (int i = 0; i < fdev->read_dummy_cycles; i++) {
			ctrl_reg_write(fdev, FLASH_CLK);
			ctrl_reg_write(fdev, 0);
		}
	}

	while (len > 0) {
		*d = spi_flash_read_byte(fdev, protocol);
		len--;
		d++;
	}

	spi_flash_deselect(fdev);

	return 0;
}

int spi_flash_write(struct flash_device *fdev, size_t addr, size_t len, const void *src)
{
	const char *s = src;

	int protocol = SPI_PROTO_STR;

	if (fdev->data_width == 4) {
		protocol = SPI_PROTO_QUAD_STR;
	}

	while (len > 0) {
		// check alignment
		if ((addr & (SPI_PAGE_SIZE-1)) != 0) {
			fprintf(stderr, "Invalid write request\n");
			spi_flash_deselect(fdev);
			return -1;
		}

		// set extended address
		// note: some devices do not support 4B address program operations (e.g. N25Q256Ax1E)
		// so we always use 3B operations
		if (fdev->size > 0x1000000) {
			spi_flash_write_ext_addr_reg(fdev, addr >> 24, SPI_PROTO_STR);
		}

		// enable writing
		spi_flash_write_enable(fdev, SPI_PROTO_STR);

		if (!(spi_flash_read_status_reg(fdev, SPI_PROTO_STR) & 0x02)) {
			fprintf(stderr, "Failed to enable writing\n");
			spi_flash_deselect(fdev);
			return -1;
		}

		// write page
		if (protocol == SPI_PROTO_QUAD_STR) {
			spi_flash_write_byte(fdev, SPI_CMD_PAGE_PROGRAM_QUAD_IN, SPI_PROTO_STR);
			spi_flash_write_addr(fdev, addr, SPI_PROTO_STR);
		} else {
			spi_flash_write_byte(fdev, SPI_CMD_PAGE_PROGRAM, SPI_PROTO_STR);
			spi_flash_write_addr(fdev, addr, SPI_PROTO_STR);
		}

		while (len > 0) {
			spi_flash_write_byte(fdev, *s, protocol);
			addr++;
			s++;
			len--;

			if ((addr & (SPI_PAGE_SIZE-1)) == 0)
				break;
		}

		spi_flash_deselect(fdev);

		// wait for operation to complete
		while (spi_flash_read_status_reg(fdev, SPI_PROTO_STR) & 0x01) {};
	}

	spi_flash_deselect(fdev);

	return 0;
}

int spi_flash_erase(struct flash_device *fdev, size_t addr, size_t len)
{
	size_t erase_block_size = fdev->erase_block_size;

	while (len > 0) {
		// determine sector size and check alignment
		erase_block_size = 0;

		if ((addr & (SPI_SECTOR_SIZE-1)) == 0 && len >= SPI_SECTOR_SIZE) {
			erase_block_size = SPI_SECTOR_SIZE;
		} else if ((addr & (SPI_SUBSECTOR_SIZE-1)) == 0 && len >= SPI_SUBSECTOR_SIZE) {
			erase_block_size = SPI_SUBSECTOR_SIZE;
		}

		if (!erase_block_size) {
			fprintf(stderr, "Invalid erase request\n");
			spi_flash_deselect(fdev);
			return -1;
		}

		// set extended address
		// note: some devices do not support 4B address program operations (e.g. N25Q256Ax1E)
		// so we always use 3B operations
		if (fdev->size > 0x1000000) {
			spi_flash_write_ext_addr_reg(fdev, addr >> 24, SPI_PROTO_STR);
		}

		// enable writing
		spi_flash_write_enable(fdev, SPI_PROTO_STR);

		if (!(spi_flash_read_status_reg(fdev, SPI_PROTO_STR) & 0x02)) {
			fprintf(stderr, "Failed to enable writing\n");
			spi_flash_deselect(fdev);
			return -1;
		}

		// block erase
		if (erase_block_size == SPI_SECTOR_SIZE) {
			// normal sector erase
			spi_flash_write_byte(fdev, SPI_CMD_SECTOR_ERASE, SPI_PROTO_STR);
			spi_flash_write_addr(fdev, addr, SPI_PROTO_STR);
		} else if (erase_block_size == SPI_SUBSECTOR_SIZE) {
			// normal 4KB subsector erase
			spi_flash_write_byte(fdev, SPI_CMD_4KB_SUBSECTOR_ERASE, SPI_PROTO_STR);
			spi_flash_write_addr(fdev, addr, SPI_PROTO_STR);
		}

		spi_flash_deselect(fdev);

		// wait for operation to complete
		while (spi_flash_read_status_reg(fdev, SPI_PROTO_STR) & 0x01) {};

		if (len <= erase_block_size)
			break;

		addr += erase_block_size;
		len -= erase_block_size;
	}

	spi_flash_deselect(fdev);

	return 0;
}

const struct flash_driver spi_flash_driver = {
	.init = spi_flash_init,
	.release = spi_flash_release,
	.read = spi_flash_read,
	.write = spi_flash_write,
	.erase = spi_flash_erase
};
