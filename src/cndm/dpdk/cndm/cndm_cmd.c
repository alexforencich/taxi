/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright (c) 2026 FPGA Ninja, LLC
 *
 * Authors:
 * - Alex Forencich
 */

#include "cndm.h"

#include <ctype.h>

#include <rte_hexdump.h>
#include <rte_io.h>

int cndm_exec_mbox_cmd(struct cndm_dev *cdev, void *cmd, void *rsp)
{
	bool done = false;
	int ret = 0;
	int k;

	if (!cmd || !rsp)
		return -EINVAL;

	rte_spinlock_lock(&cdev->mbox_lock);

	// write command to mailbox
	for (k = 0; k < 16; k++) {
		rte_write32(*((__u32 *)((__u8 *)cmd + k*4)), cdev->hw_addr + 0x10000 + k*4);
	}

	// ensure the command is completely written
	rte_wmb();

	// execute it
	rte_write32(0x00000001, cdev->hw_addr + 0x0200);

	// wait for completion
	for (k = 0; k < 100; k++) {
		done = (rte_read32(cdev->hw_addr + 0x0200) & 0x00000001) == 0;
		if (done)
			break;

		rte_delay_us(100);
	}

	if (done) {
		// read response from mailbox
		for (k = 0; k < 16; k++) {
			*((__u32 *)((__u8 *)rsp + k*4)) = rte_read32(cdev->hw_addr + 0x10000 + 0x40 + k*4);
		}
	} else {
		DRV_LOG(ERR, "Command timed out");
		rte_hexdump(stderr, "cmd", cmd, sizeof(struct cndm_cmd_cfg));
		ret = -ETIMEDOUT;
	}

	rte_spinlock_unlock(&cdev->mbox_lock);
	return ret;
}

int cndm_exec_cmd(struct cndm_dev *cdev, void *cmd, void *rsp)
{
	return cndm_exec_mbox_cmd(cdev, cmd, rsp);
}

int cndm_access_reg(struct cndm_dev *cdev, __u32 reg, int raw, int write, __u64 *data)
{
	struct cndm_cmd_reg cmd;
	struct cndm_cmd_reg rsp;
	int ret = 0;

	cmd.opcode = CNDM_CMD_OP_ACCESS_REG;
	cmd.flags = 0x00000000;
	cmd.reg_addr = reg;
	cmd.write_val = *data;
	cmd.read_val = 0;

	if (write)
		cmd.flags |= CNDM_CMD_REG_FLG_WRITE;
	if (raw)
		cmd.flags |= CNDM_CMD_REG_FLG_RAW;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret)
		return ret;

	if (rsp.status)
		return rsp.status;

	if (!write)
		*data = rsp.read_val;

	return 0;
}

int cndm_hwid_sn_rd(struct cndm_dev *cdev, int *len, void *data)
{
	struct cndm_cmd_hwid cmd;
	struct cndm_cmd_hwid rsp;
	int k = 0;
	int ret = 0;
	char buf[64];
	const char *ptr;

	cmd.opcode = CNDM_CMD_OP_HWID;
	cmd.flags = 0x00000000;
	cmd.index = 0;
	cmd.brd_opcode = CNDM_CMD_BRD_OP_HWID_SN_RD;
	cmd.brd_flags = 0x00000000;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret)
		return ret;

	if (rsp.status || rsp.brd_status)
		return rsp.status ? rsp.status : rsp.brd_status;

	// memcpy(&buf, &rsp.data, min(cmd.len, 32)); // TODO
	memcpy(&buf, &rsp.data, 32);
	buf[32] = 0;

	for (k = 0; k < 32; k++) {
		if (!isascii(buf[k]) || !isprint(buf[k])) {
			buf[k] = 0;
			break;
		}
	}

	ptr = rte_str_skip_leading_spaces(buf);

	if (len)
		*len = strlen(ptr);
	if (data)
		rte_strscpy(data, ptr, 32);

	return 0;
}

int cndm_hwid_mac_rd(struct cndm_dev *cdev, __u16 index, int *cnt, void *data)
{
	struct cndm_cmd_hwid cmd;
	struct cndm_cmd_hwid rsp;
	int ret = 0;

	cmd.opcode = CNDM_CMD_OP_HWID;
	cmd.flags = 0x00000000;
	cmd.index = index;
	cmd.brd_opcode = CNDM_CMD_BRD_OP_HWID_MAC_RD;
	cmd.brd_flags = 0x00000000;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret)
		return ret;

	if (rsp.status || rsp.brd_status)
		return rsp.status ? rsp.status : rsp.brd_status;

	if (cnt)
		*cnt = 1; // *((__u16 *)&rsp.data); // TODO
	if (data)
		memcpy(data, ((__u8 *)&rsp.data)+2, ETH_ALEN);

	return 0;
}
