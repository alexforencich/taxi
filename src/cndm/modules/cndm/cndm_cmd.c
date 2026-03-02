// SPDX-License-Identifier: GPL
/*

Copyright (c) 2026 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#include "cndm.h"

int cndm_exec_mbox_cmd(struct cndm_dev *cdev, void *cmd, void *rsp)
{
	int k;

	if (!cmd || !rsp)
		return -EINVAL;

	// write command to mailbox
	for (k = 0; k < 16; k++) {
		iowrite32(*((u32 *)(cmd + k*4)), cdev->hw_addr + 0x10000 + k*4);
	}

	// execute it
	iowrite32(0x00000001, cdev->hw_addr + 0x0200);

	// wait for completion
	for (k = 0; k < 10; k++) {
		if ((ioread32(cdev->hw_addr + 0x0200) & 0x00000001) == 0) {
			break;
		}

		udelay(100);
	}

	// read response from mailbox
	for (k = 0; k < 16; k++) {
		*((u32 *)(rsp + k*4)) = ioread32(cdev->hw_addr + 0x10000 + 0x40 + k*4);
	}
	return 0;
}

int cndm_exec_cmd(struct cndm_dev *cdev, void *cmd, void *rsp)
{
	return cndm_exec_mbox_cmd(cdev, cmd, rsp);
}

int cndm_access_reg(struct cndm_dev *cdev, u32 reg, int raw, int write, u64 *data)
{
	struct cndm_cmd cmd;
	struct cndm_cmd rsp;

	cmd.opcode = CNDM_CMD_OP_ACCESS_REG;
	cmd.flags = 0x00000000;
	cmd.port = 0;
	cmd.qn = 0;
	cmd.qn2 = 0;
	cmd.pd = 0;
	cmd.size = 0;
	cmd.dboffs = reg;
	cmd.ptr1 = *data;
	cmd.ptr2 = 0;

	if (write)
		cmd.flags |= 0x00000001;
	if (raw)
		cmd.flags |= 0x00000100;

	cndm_exec_cmd(cdev, &cmd, &rsp);

	if (!write)
		*data = rsp.ptr2;

	return 0;
}
