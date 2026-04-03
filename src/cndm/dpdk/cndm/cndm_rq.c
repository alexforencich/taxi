/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright (c) 2025-2026 FPGA Ninja, LLC
 *
 * Authors:
 * - Alex Forencich
 */

#include "cndm.h"

#include <rte_malloc.h>
#include <rte_io.h>

struct cndm_ring *cndm_create_rq(struct cndm_priv *priv, unsigned int socket_id)
{
	struct cndm_ring *rq;

	rq = rte_zmalloc_socket("cndm_rq", sizeof(*rq), 0, socket_id);
	if (!rq)
		return NULL;

	rq->cdev = priv->cdev;
	rq->priv = priv;
	rq->socket_id = socket_id;

	rq->index = -1;
	rq->enabled = 0;

	rq->prod_ptr = 0;
	rq->cons_ptr = 0;

	rq->db_offset = 0;
	rq->db_addr = NULL;

	return rq;
}

void cndm_destroy_rq(struct cndm_ring *rq)
{
	cndm_close_rq(rq);

	rte_free(rq);
}

int cndm_open_rq(struct cndm_ring *rq, struct cndm_priv *priv, struct cndm_cq *cq, int size)
{
	int ret = 0;

	struct cndm_cmd_queue cmd;
	struct cndm_cmd_queue rsp;

	if (rq->enabled || rq->buf || !priv || !cq)
		return -EINVAL;

	rq->size = rte_align32pow2(size);
	rq->size_mask = rq->size - 1;
	rq->stride = 16;

	rq->rx_info = rte_zmalloc_socket("cndm_rq_info_ring",
			sizeof(*rq->rx_info) * rq->size,
			RTE_CACHE_LINE_SIZE, rq->socket_id);
	if (!rq->rx_info)
		return -ENOMEM;

	rq->buf_size = rq->size * rq->stride;
	rq->buf = rte_zmalloc_socket("cndm_rq_ring", rq->buf_size,
			RTE_CACHE_LINE_SIZE, rq->socket_id);
	if (!rq->buf) {
		ret = -ENOMEM;
		goto fail;
	}
	rq->buf_dma_addr = rte_malloc_virt2iova(rq->buf);

	rq->priv = priv;
	rq->cq = cq;
	cq->src_ring = rq;

	rq->prod_ptr = 0;
	rq->cons_ptr = 0;

	cmd.opcode = CNDM_CMD_OP_CREATE_RQ;
	cmd.flags = 0x00000000;
	cmd.port = rq->priv->dev_port;
	cmd.qn = 0;
	cmd.qn2 = cq->cqn;
	cmd.pd = 0;
	cmd.size = rte_log2_u32(rq->size);
	cmd.dboffs = 0;
	cmd.ptr1 = rq->buf_dma_addr;
	cmd.ptr2 = 0;

	ret = cndm_exec_cmd(rq->cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(ERR, "Failed to execute command");
		goto fail;
	}

	if (rsp.status || rsp.dboffs == 0) {
		DRV_LOG(ERR, "Failed to allocate RQ");
		ret = rsp.status;
		goto fail;
	}

	rq->index = rsp.qn;
	rq->db_offset = rsp.dboffs;
	rq->db_addr = rq->cdev->hw_addr + rsp.dboffs;

	rq->enabled = 1;

	DRV_LOG(DEBUG, "Opened RQ %d (CQ %d)", rq->index, cq->cqn);

	ret = cndm_refill_rx_buffers(rq);
	if (ret) {
		DRV_LOG(ERR, "failed to allocate RX buffer for RX queue index %d (of %u total) entry index %u (of %u total)",
				rq->index, priv->rxq_count, rq->prod_ptr, rq->size);
		if (ret == -ENOMEM)
			DRV_LOG(ERR, "machine might not have enough DMA-capable RAM; try to decrease number of RX channels (currently %u) and/or RX ring parameters (entries; currently %u)",
					priv->rxq_count, rq->size);

		goto fail;
	}

	return 0;

fail:
	cndm_close_rq(rq);
	return ret;
}

void cndm_close_rq(struct cndm_ring *rq)
{
	struct cndm_dev *cdev = rq->cdev;
	struct cndm_cmd_queue cmd;
	struct cndm_cmd_queue rsp;

	rq->enabled = 0;

	if (rq->cq) {
		rq->cq->src_ring = NULL;
		rq->cq->handler = NULL;
	}

	rq->cq = NULL;

	if (rq->index != -1) {
		cmd.opcode = CNDM_CMD_OP_DESTROY_RQ;
		cmd.flags = 0x00000000;
		cmd.port = rq->priv->dev_port;
		cmd.qn = rq->index;

		cndm_exec_cmd(cdev, &cmd, &rsp);

		rq->index = -1;
		rq->db_offset = 0;
		rq->db_addr = NULL;
	}

	if (rq->buf) {
		// cndm_free_rx_buf(rq); // TODO!!!

		rte_free(rq->buf);
		rq->buf = NULL;
		rq->buf_dma_addr = 0;
	}

	if (rq->rx_info) {
		rte_free(rq->rx_info);
		rq->rx_info = NULL;
	}

	rq->priv = NULL;
}

bool cndm_is_rq_ring_empty(const struct cndm_ring *rq)
{
	return rq->prod_ptr == rq->cons_ptr;
}

bool cndm_is_rq_ring_full(const struct cndm_ring *rq)
{
	return (rq->prod_ptr - rq->cons_ptr) >= rq->size;
}

void cndm_rq_write_prod_ptr(const struct cndm_ring *rq)
{
	rte_write32(rq->prod_ptr & 0xffff, rq->db_addr);
}

// static void cndm_free_rx_desc(struct cndm_ring *rq, int index)
// {
// 	struct cndm_priv *priv = rq->priv;
// 	struct device *dev = priv->dev;
// 	struct cndm_rx_info *rx_info = &rq->rx_info[index];

// 	DRV_LOG(DEBUG, "Free RX desc index %d", index);

// 	if (!rx_info->page)
// 		return;

// 	dma_unmap_page(dev, rx_info->dma_addr, rx_info->len, DMA_FROM_DEVICE);
// 	rx_info->dma_addr = 0;
// 	__free_pages(rx_info->page, 0);
// 	rx_info->page = NULL;
// }

// int cndm_free_rx_buf(struct cndm_ring *rq)
// {
// 	u32 index;
// 	int cnt = 0;

// 	while (!cndm_is_rq_ring_empty(rq)) {
// 		index = rq->cons_ptr & rq->size_mask;
// 		cndm_free_rx_desc(rq, index);
// 		rq->cons_ptr++;
// 		cnt++;
// 	}

// 	return cnt;
// }

#define BATCH_SIZE 32

int cndm_refill_rx_buffers(struct cndm_ring *rq)
{
	__u32 missing = rq->size - (rq->prod_ptr - rq->cons_ptr);
	int ret = 0;
	struct rte_mbuf *mbufs[BATCH_SIZE];
	int batch_count;
	__u32 index;
	struct cndm_desc *rx_desc;
	struct cndm_rx_info *rx_info;
	struct rte_mbuf *mbuf;

	if (missing < 8)
		return 0;

	while (missing > 0) {
		batch_count = RTE_MIN((int)missing, BATCH_SIZE);
		ret = rte_pktmbuf_alloc_bulk(rq->mp, mbufs, batch_count);
		if (ret) {
			DRV_LOG(ERR, "Failed to allocate mbufs");
			goto done;
		}

		for (int i = 0; i < batch_count; i++) {
			mbuf = mbufs[i];
			index = rq->prod_ptr & rq->size_mask;

			rx_desc = (struct cndm_desc *)(rq->buf + index*rq->stride);
			rx_info = &rq->rx_info[index];

			rx_desc->len = rte_cpu_to_le_32(rte_pktmbuf_data_room_size(rq->mp) - RTE_PKTMBUF_HEADROOM);
			rx_desc->addr = rte_cpu_to_le_64(rte_pktmbuf_iova(mbuf));

			rx_info->mbuf = mbuf;

			rq->prod_ptr++;
			missing--;
		}
	}

done:
	rte_io_wmb();
	cndm_rq_write_prod_ptr(rq);

	return ret;
}

uint16_t cndm_recv_pkt_burst(void *queue, struct rte_mbuf **pkts, uint16_t nb_pkts)
{
	struct cndm_ring *rq = queue;
	struct cndm_cq *cq = rq->cq;
	__u32 index;
	uint16_t pkt_recv = 0;
	struct cndm_cpl *cpl;
	struct cndm_rx_info *rx_info;
	struct rte_mbuf *mbuf;

	__u32 len;
	__u32 cq_cons_ptr;
	__u32 cq_index;
	__u32 cons_ptr;

	cq_cons_ptr = cq->cons_ptr;
	cons_ptr = rq->cons_ptr;

	while (pkt_recv < nb_pkts) {
		cq_index = cq_cons_ptr & cq->size_mask;
		cpl = (struct cndm_cpl *)(cq->buf + cq_index*cq->stride);

		if (!!(cpl->phase & 0x80) == !!(cq_cons_ptr & cq->size))
			break;

		rte_io_rmb();

		index = cons_ptr & rq->size_mask;
		rx_info = &rq->rx_info[index];
		mbuf = rx_info->mbuf;

		len = RTE_MIN(rte_le_to_cpu_32(cpl->len), rte_pktmbuf_data_room_size(rq->mp) - RTE_PKTMBUF_HEADROOM);

		if (!mbuf) {
			DRV_LOG(ERR, "null mbuf at index %d", index);
		} else {
			mbuf->nb_segs = 1;
			mbuf->next = NULL;
			mbuf->data_len = len;
			mbuf->pkt_len = len;
			mbuf->port = rq->priv->port_id;

			pkts[pkt_recv] = mbuf;
			rx_info->mbuf = NULL;
		}

		cq_cons_ptr++;
		cons_ptr++;
		pkt_recv++;
	}

	cq->cons_ptr = cq_cons_ptr;
	rq->cons_ptr = cons_ptr;

	cndm_cq_write_cons_ptr(cq);

	if (pkt_recv) {
		cndm_refill_rx_buffers(rq);
	}

	return pkt_recv;
}
