/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright (c) 2025-2026 FPGA Ninja, LLC
 *
 * Authors:
 * - Alex Forencich
 */

#include "cndm.h"

#include <rte_malloc.h>
#include <rte_io.h>

struct cndm_ring *cndm_create_sq(struct cndm_priv *priv, unsigned int socket_id)
{
	struct cndm_ring *sq;

	sq = rte_zmalloc_socket("cndm_sq", sizeof(*sq), 0, socket_id);
	if (!sq)
		return NULL;

	sq->cdev = priv->cdev;
	sq->priv = priv;
	sq->socket_id = socket_id;

	sq->index = -1;
	sq->enabled = 0;

	sq->prod_ptr = 0;
	sq->cons_ptr = 0;

	sq->db_offset = 0;
	sq->db_addr = NULL;

	return sq;
}

void cndm_destroy_sq(struct cndm_ring *sq)
{
	cndm_close_sq(sq);

	rte_free(sq);
}

int cndm_open_sq(struct cndm_ring *sq, struct cndm_priv *priv, struct cndm_cq *cq, int size)
{
	int ret = 0;

	struct cndm_cmd_queue cmd;
	struct cndm_cmd_queue rsp;

	if (sq->enabled || sq->buf || !priv || !cq)
		return -EINVAL;

	sq->size = rte_align32pow2(size);
	sq->size_mask = sq->size - 1;
	sq->stride = 16;

	sq->tx_info = rte_zmalloc_socket("cndm_sq_info_ring",
			sizeof(*sq->tx_info) * sq->size,
			RTE_CACHE_LINE_SIZE, sq->socket_id);
	if (!sq->tx_info)
		return -ENOMEM;

	sq->buf_size = sq->size * sq->stride;
	sq->buf = rte_zmalloc_socket("cndm_sq_ring", sq->buf_size,
			RTE_CACHE_LINE_SIZE, sq->socket_id);
	if (!sq->buf) {
		ret = -ENOMEM;
		goto fail;
	}
	sq->buf_dma_addr = rte_malloc_virt2iova(sq->buf);

	sq->priv = priv;
	sq->cq = cq;
	cq->src_ring = sq;

	sq->prod_ptr = 0;
	sq->cons_ptr = 0;

	cmd.opcode = CNDM_CMD_OP_CREATE_SQ;
	cmd.flags = 0x00000000;
	cmd.port = sq->priv->dev_port;
	cmd.qn = 0;
	cmd.qn2 = cq->cqn;
	cmd.pd = 0;
	cmd.size = rte_log2_u32(sq->size);
	cmd.dboffs = 0;
	cmd.ptr1 = sq->buf_dma_addr;
	cmd.ptr2 = 0;

	ret = cndm_exec_cmd(sq->cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(ERR, "Failed to execute command");
		goto fail;
	}

	if (rsp.status || rsp.dboffs == 0) {
		DRV_LOG(ERR, "Failed to allocate SQ");
		ret = rsp.status;
		goto fail;
	}

	sq->index = rsp.qn;
	sq->db_offset = rsp.dboffs;
	sq->db_addr = sq->cdev->hw_addr + rsp.dboffs;

	sq->enabled = 1;

	DRV_LOG(DEBUG, "Opened SQ %d (CQ %d)", sq->index, cq->cqn);

	return 0;

fail:
	cndm_close_sq(sq);
	return ret;
}

void cndm_close_sq(struct cndm_ring *sq)
{
	struct cndm_dev *cdev = sq->cdev;
	struct cndm_cmd_queue cmd;
	struct cndm_cmd_queue rsp;

	sq->enabled = 0;

	if (sq->cq) {
		sq->cq->src_ring = NULL;
		sq->cq->handler = NULL;
	}

	sq->cq = NULL;

	if (sq->index != -1) {
		cmd.opcode = CNDM_CMD_OP_DESTROY_SQ;
		cmd.flags = 0x00000000;
		cmd.port = sq->priv->dev_port;
		cmd.qn = sq->index;

		cndm_exec_cmd(cdev, &cmd, &rsp);

		sq->index = -1;
		sq->db_offset = 0;
		sq->db_addr = NULL;
	}

	if (sq->buf) {
		// cndm_free_tx_buf(sq); // TODO!!!

		rte_free(sq->buf);
		sq->buf = NULL;
		sq->buf_dma_addr = 0;
	}

	if (sq->tx_info) {
		rte_free(sq->tx_info);
		sq->tx_info = NULL;
	}

	sq->priv = NULL;
}

bool cndm_is_sq_ring_empty(const struct cndm_ring *sq)
{
	return sq->prod_ptr == sq->cons_ptr;
}

bool cndm_is_sq_ring_full(const struct cndm_ring *sq)
{
	return (sq->prod_ptr - sq->cons_ptr) >= sq->size;
}

void cndm_sq_write_prod_ptr(const struct cndm_ring *sq)
{
	rte_write32(sq->prod_ptr & 0xffff, sq->db_addr);
}

// static void cndm_free_tx_desc(struct cndm_ring *sq, int index, int napi_budget)
// {
// 	struct cndm_priv *priv = sq->priv;
// 	struct cndm_tx_info *tx_info = &sq->tx_info[index];
// 	struct sk_buff *skb = tx_info->skb;

// 	DRV_LOG(DEBUG, "Free TX desc index %d", index);

// 	dma_unmap_single(dev, tx_info->dma_addr, tx_info->len, DMA_TO_DEVICE);
// 	tx_info->dma_addr = 0;

// 	napi_consume_skb(skb, napi_budget);
// 	tx_info->skb = NULL;
// }

// int cndm_free_tx_buf(struct cndm_ring *sq)
// {
// 	__u32 index;
// 	int cnt = 0;

// 	while (!cndm_is_sq_ring_empty(sq)) {
// 		index = sq->cons_ptr & sq->size_mask;
// 		cndm_free_tx_desc(sq, index, 0);
// 		sq->cons_ptr++;
// 		cnt++;
// 	}

// 	return cnt;
// }

uint16_t cndm_xmit_pkt_burst(void *queue, struct rte_mbuf **pkts, uint16_t nb_pkts)
{
	struct cndm_ring *sq = queue;
	struct cndm_cq *cq = sq->cq;
	__u32 index;
	uint16_t pkt_sent = 0;
	struct cndm_desc *tx_desc;
	struct cndm_cpl *cpl;
	struct cndm_tx_info *tx_info;

	__u32 cq_cons_ptr;
	__u32 cq_index;
	__u32 cons_ptr;

	for (uint16_t pkt_idx = 0; pkt_idx < nb_pkts; pkt_idx++) {
		struct rte_mbuf *pkt_mbuf = pkts[pkt_idx];

		if (sq->prod_ptr - sq->cons_ptr >= sq->size) {
			DRV_LOG(DEBUG, "TX ring full");
			break;
		}

		if (pkt_mbuf->nb_segs > 1) {
			DRV_LOG(ERR, "too many segments (%d > 1)", pkt_mbuf->nb_segs);
			// TODO free mbuf, perhaps?
			continue;
		}

		index = sq->prod_ptr & sq->size_mask;

		tx_desc = (struct cndm_desc *)(sq->buf + index*sq->stride);
		tx_info = &sq->tx_info[index];

		tx_desc->len = rte_cpu_to_le_32(pkt_mbuf->data_len);
		tx_desc->addr = rte_cpu_to_le_64(rte_pktmbuf_iova(pkt_mbuf));

		tx_info->mbuf = pkt_mbuf;

		sq->prod_ptr++;
		pkt_sent++;
	}

	if (pkt_sent) {
		rte_io_wmb();
		cndm_sq_write_prod_ptr(sq);
	}

	cq_cons_ptr = cq->cons_ptr;
	cons_ptr = sq->cons_ptr;

	while (true) {
		cq_index = cq_cons_ptr & cq->size_mask;
		cpl = (struct cndm_cpl *)(cq->buf + cq_index*cq->stride);

		if (!!(cpl->phase & 0x80) == !!(cq_cons_ptr & cq->size))
			break;

		rte_io_rmb();

		index = cons_ptr & sq->size_mask;
		tx_info = &sq->tx_info[index];

		if (!tx_info->mbuf) {
			DRV_LOG(ERR, "null mbuf at index %d", index);
		} else {
			rte_pktmbuf_free(tx_info->mbuf);
		}

		cq_cons_ptr++;
		cons_ptr++;
	}

	cq->cons_ptr = cq_cons_ptr;
	sq->cons_ptr = cons_ptr;

	cndm_cq_write_cons_ptr(cq);

	return pkt_sent;
}
