/* SPDX-License-Identifier: GPL */
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#ifndef BITFILE_H
#define BITFILE_H

#include <stddef.h>

struct bitfile {
	char *header;
	char *name;
	char *part;
	char *date;
	char *time;

	size_t data_len;
	char *data;
};

struct bitfile *bitfile_create_from_file(const char *bit_file_name);

struct bitfile *bitfile_create_from_buffer(char *buffer, size_t len);

int bitfile_parse(struct bitfile *bf, char *buffer, size_t len);

void bitfile_close(struct bitfile *bf);

#endif // BITFILE_H
