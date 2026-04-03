/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright (c) 2025-2026 FPGA Ninja, LLC
 *
 * Authors:
 * - Alex Forencich
 */

#include "cndm.h"

#include <rte_malloc.h>
#include <rte_io.h>

struct cndm_cq *cndm_create_cq(struct cndm_priv *priv, unsigned int socket_id)
{
	struct cndm_cq *cq;

	cq = rte_zmalloc_socket("cndm_cq", sizeof(*cq), 0, socket_id);
	if (!cq)
		return NULL;

	cq->cdev = priv->cdev;
	cq->priv = priv;
	cq->socket_id = socket_id;

	cq->cqn = -1;
	cq->enabled = 0;

	cq->cons_ptr = 0;

	cq->db_offset = 0;
	cq->db_addr = NULL;

	return cq;
}

void cndm_destroy_cq(struct cndm_cq *cq)
{
	cndm_close_cq(cq);

	rte_free(cq);
}

int cndm_open_cq(struct cndm_cq *cq, int size)
{
	__u32 dqn = 0xC0000000;
	int ret = 0;

	struct cndm_cmd_queue cmd;
	struct cndm_cmd_queue rsp;

	if (cq->enabled || cq->buf)
		return -EINVAL;

	cq->size = rte_align32pow2(size);
	cq->size_mask = cq->size - 1;
	cq->stride = 16;

	cq->buf_size = cq->size * cq->stride;
	cq->buf = rte_zmalloc_socket("cndm_cq_ring", cq->buf_size,
			RTE_CACHE_LINE_SIZE, cq->socket_id);
	if (!cq->buf)
		return -ENOMEM;
	cq->buf_dma_addr = rte_malloc_virt2iova(cq->buf);

	cq->cons_ptr = 0;

	// clear all phase tag bits
	memset(cq->buf, 0, cq->buf_size);

	cmd.opcode = CNDM_CMD_OP_CREATE_CQ;
	cmd.flags = 0x00000000;
	cmd.port = cq->priv->dev_port;
	cmd.qn = 0;
	cmd.qn2 = dqn;
	cmd.pd = 0;
	cmd.size = rte_log2_u32(cq->size);
	cmd.dboffs = 0;
	cmd.ptr1 = cq->buf_dma_addr;
	cmd.ptr2 = 0;

	ret = cndm_exec_cmd(cq->cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(ERR, "Failed to execute command");
		goto fail;
	}

	if (rsp.status || rsp.dboffs == 0) {
		DRV_LOG(ERR, "Failed to allocate CQ");
		ret = rsp.status;
		goto fail;
	}

	cq->cqn = rsp.qn;
	cq->db_offset = rsp.dboffs;
	cq->db_addr = cq->cdev->hw_addr + rsp.dboffs;

	cq->enabled = 1;

	DRV_LOG(DEBUG, "Opened CQ %d", cq->cqn);

	return 0;

fail:
	cndm_close_cq(cq);
	return ret;
}

void cndm_close_cq(struct cndm_cq *cq)
{
	struct cndm_dev *cdev = cq->cdev;
	struct cndm_cmd_queue cmd;
	struct cndm_cmd_queue rsp;

	cq->enabled = 0;

	if (cq->cqn != -1) {
		cmd.opcode = CNDM_CMD_OP_DESTROY_CQ;
		cmd.flags = 0x00000000;
		cmd.port = cq->priv->dev_port;
		cmd.qn = cq->cqn;

		cndm_exec_cmd(cdev, &cmd, &rsp);

		cq->cqn = -1;
		cq->db_offset = 0;
		cq->db_addr = NULL;
	}

	if (cq->buf) {
		rte_free(cq->buf);
		cq->buf = NULL;
		cq->buf_dma_addr = 0;
	}
}

void cndm_cq_write_cons_ptr(const struct cndm_cq *cq)
{
	rte_write32(cq->cons_ptr & 0xffff, cq->db_addr);
}

void cndm_cq_write_cons_ptr_arm(const struct cndm_cq *cq)
{
	rte_write32((cq->cons_ptr & 0xffff) | 0x80000000, cq->db_addr);
}
