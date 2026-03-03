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

	mutex_lock(&cdev->mbox_lock);

	// write command to mailbox
	for (k = 0; k < 16; k++) {
		iowrite32(*((u32 *)(cmd + k*4)), cdev->hw_addr + 0x10000 + k*4);
	}

	// ensure the command is completely written
	wmb();

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

	mutex_unlock(&cdev->mbox_lock);

	return 0;
}

int cndm_exec_cmd(struct cndm_dev *cdev, void *cmd, void *rsp)
{
	return cndm_exec_mbox_cmd(cdev, cmd, rsp);
}

int cndm_access_reg(struct cndm_dev *cdev, u32 reg, int raw, int write, u64 *data)
{
	struct cndm_cmd_reg cmd;
	struct cndm_cmd_reg rsp;

	cmd.opcode = CNDM_CMD_OP_ACCESS_REG;
	cmd.flags = 0x00000000;
	cmd.reg_addr = reg;
	cmd.write_val = *data;
	cmd.read_val = 0;

	if (write)
		cmd.flags |= CNDM_CMD_REG_FLG_WRITE;
	if (raw)
		cmd.flags |= CNDM_CMD_REG_FLG_RAW;

	cndm_exec_cmd(cdev, &cmd, &rsp);

	if (!write)
		*data = rsp.read_val;

	return 0;
}
