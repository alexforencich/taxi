/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright (c) 2026 FPGA Ninja, LLC
 *
 * Authors:
 * - Alex Forencich
 */

#include "cndm.h"

#include <ethdev_driver.h>
#include <ethdev_pci.h>
#include <rte_io.h>
#include <rte_mbuf.h>

static int cndm_link_update(struct rte_eth_dev *eth_dev, int wait_to_complete __rte_unused)
{
	struct rte_eth_link link;

	memset(&link, 0, sizeof(link));

	link.link_duplex = RTE_ETH_LINK_FULL_DUPLEX;
	link.link_autoneg = RTE_ETH_LINK_SPEED_FIXED;
	link.link_speed = RTE_ETH_SPEED_NUM_100G;
	link.link_status = RTE_ETH_LINK_UP;

	if (!eth_dev->data->dev_started)
		link.link_status = RTE_ETH_LINK_DOWN;

	return rte_eth_linkstatus_set(eth_dev, &link);
}

static int cndm_promiscuous_mode_enable(struct rte_eth_dev *eth_dev __rte_unused)
{
	return 0;
}

static int cndm_promiscuous_mode_disable(struct rte_eth_dev *eth_dev __rte_unused)
{
	return 0;
}

static int cndm_mac_addr_set(struct rte_eth_dev *eth_dev, struct rte_ether_addr *addr)
{
	rte_ether_addr_copy(addr, eth_dev->data->mac_addrs);

	return 0;
}

static int cndm_mtu_set(struct rte_eth_dev *eth_dev, uint16_t mtu)
{
	// struct cndm_priv *priv = eth_dev->data->dev_private;

	// TODO limits

	eth_dev->data->mtu = mtu;

	return 0;
}


static int cndm_stats_get(struct rte_eth_dev *eth_dev __rte_unused,
		struct rte_eth_stats *stats __rte_unused, struct eth_queue_stats *qstats __rte_unused)
{
	// TODO

	return 0;
}

static int cndm_stats_reset(struct rte_eth_dev *eth_dev __rte_unused)
{
	// TODO

	return 0;
}

static int cndm_dev_info_get(struct rte_eth_dev *eth_dev,
		struct rte_eth_dev_info *dev_info)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;

	DRV_LOG(DEBUG, "Info get for eth_dev %s", eth_dev->data->name);

	dev_info->min_mtu = RTE_ETHER_MIN_MTU;
	dev_info->max_mtu = 1500; // TODO

	dev_info->min_rx_bufsize = 64;
	dev_info->max_rx_pktlen = dev_info->max_mtu + RTE_ETHER_HDR_LEN;

	dev_info->max_rx_queues = 1; //RTE_MIN(1 << priv->log_max_rq, UINT16_MAX);
	dev_info->max_tx_queues = 1; //RTE_MIN(1 << priv->log_max_sq, UINT16_MAX);

	dev_info->max_mac_addrs = 1;
	dev_info->max_hash_mac_addrs = 0;

	dev_info->max_vfs = 0;

	dev_info->rx_offload_capa = 0;

	dev_info->tx_offload_capa = 0;

	dev_info->reta_size = 0;
	dev_info->hash_key_size = 0;
	dev_info->flow_type_rss_offloads = 0;

	dev_info->default_rxconf = (struct rte_eth_rxconf){
		.rx_thresh = {
			.pthresh = 8,
			.hthresh = 8,
			.wthresh = 0,
		},
		.rx_free_thresh = 32,
		.rx_drop_en = 1,
	};

	dev_info->default_txconf = (struct rte_eth_txconf){
		.tx_thresh = {
			.pthresh = 32,
			.hthresh = 0,
			.wthresh = 0,
		},
		.tx_rs_thresh = 32,
		.tx_free_thresh = 32,
	};

	dev_info->rx_desc_lim.nb_min = 4;
	dev_info->rx_desc_lim.nb_max = RTE_MIN(1 << priv->cdev->log_max_rq_sz, UINT16_MAX);
	dev_info->rx_desc_lim.nb_align = 4;
	dev_info->rx_desc_lim.nb_seg_max = 1;
	dev_info->rx_desc_lim.nb_mtu_seg_max = 1;

	dev_info->tx_desc_lim.nb_min = 4;
	dev_info->tx_desc_lim.nb_max = RTE_MIN(1 << priv->cdev->log_max_sq_sz, UINT16_MAX);
	dev_info->tx_desc_lim.nb_align = 4;
	dev_info->tx_desc_lim.nb_seg_max = 1;
	dev_info->tx_desc_lim.nb_mtu_seg_max = 1;

	dev_info->speed_capa = RTE_ETH_LINK_SPEED_100G;

	dev_info->default_rxportconf.burst_size = 1;
	dev_info->default_rxportconf.ring_size = 128;
	dev_info->default_rxportconf.nb_queues = 1;

	dev_info->default_txportconf.burst_size = 1;
	dev_info->default_txportconf.ring_size = 128;
	dev_info->default_txportconf.nb_queues = 1;

	return 0;
}

static void cndm_dev_rxq_info_get(struct rte_eth_dev *eth_dev,
		uint16_t rx_queue_id, struct rte_eth_rxq_info *qinfo)
{
	struct cndm_ring *rq;

	rq = eth_dev->data->rx_queues[rx_queue_id];

	if (!rq)
		return;

	qinfo->mp = rq->mp;
	qinfo->scattered_rx = eth_dev->data->scattered_rx;
	qinfo->nb_desc = rq->size;
	// qinfo->rx_buf_size;
	qinfo->avail_thresh = 0;
	// qinfo->conf;
}

static void cndm_dev_txq_info_get(struct rte_eth_dev *eth_dev,
		uint16_t tx_queue_id, struct rte_eth_txq_info *qinfo)
{
	struct cndm_ring *sq;

	sq = eth_dev->data->tx_queues[tx_queue_id];

	if (!sq)
		return;

	qinfo->nb_desc = sq->size;
	// qinfo->conf;
}

static int cndm_dev_fw_version_get(struct rte_eth_dev *eth_dev,
		char *fw_version, size_t fw_size)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	struct cndm_dev *cdev = priv->cdev;
	int ret;

	ret = snprintf(fw_version, fw_size, "%d.%d.%d", cdev->fw_ver >> 20,
		(cdev->fw_ver >> 12) & 0xff, cdev->fw_ver & 0xfff);
	if (ret < 0)
		return -EINVAL;

	ret += 1;

	if (fw_size < (size_t)ret)
		return ret;

	return 0;
}

static int cndm_dev_rx_queue_stop(struct rte_eth_dev *eth_dev,
		uint16_t rx_queue_id)
{
	struct cndm_ring *rq;
	struct cndm_cq *cq;

	DRV_LOG(DEBUG, "RX queue stop for eth_dev %s queue %d", eth_dev->data->name, rx_queue_id);

	rq = eth_dev->data->rx_queues[rx_queue_id];

	if (!rq)
		goto done;

	cq = rq->cq;

	cndm_close_rq(rq);

	if (cq) {
		cndm_close_cq(cq);
		cndm_destroy_cq(cq);
	}

done:
	eth_dev->data->rx_queue_state[rx_queue_id] = RTE_ETH_QUEUE_STATE_STOPPED;
	return 0;
}

static int cndm_dev_rx_queue_start(struct rte_eth_dev *eth_dev,
		uint16_t rx_queue_id)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	struct cndm_ring *rq;
	struct cndm_cq *cq;
	int ret = 0;

	DRV_LOG(DEBUG, "RX queue start for eth_dev %s queue %d", eth_dev->data->name, rx_queue_id);

	rq = eth_dev->data->rx_queues[rx_queue_id];

	if (!rq)
		return -EINVAL;

	cq = cndm_create_cq(priv, rq->socket_id);
	if (!cq) {
		goto fail;
	}

	ret = cndm_open_cq(cq, rq->size);
	if (ret) {
		cndm_destroy_cq(cq);
		goto fail;
	}

	ret = cndm_open_rq(rq, priv, cq, rq->size);
	if (ret) {
		cndm_destroy_cq(cq);
		goto fail;
	}

	eth_dev->data->rx_queue_state[rx_queue_id] = RTE_ETH_QUEUE_STATE_STARTED;

	return 0;
fail:
	cndm_dev_rx_queue_stop(eth_dev, rx_queue_id);
	return ret;
}

static void cndm_dev_rx_queue_release(struct rte_eth_dev *eth_dev,
		uint16_t rx_queue_id)
{
	struct cndm_ring *rq;

	DRV_LOG(DEBUG, "RX queue release for eth_dev %s queue %d", eth_dev->data->name, rx_queue_id);

	cndm_dev_rx_queue_stop(eth_dev, rx_queue_id);

	rq = eth_dev->data->rx_queues[rx_queue_id];

	cndm_destroy_rq(rq);

	eth_dev->data->rx_queues[rx_queue_id] = NULL;
}

static int cndm_dev_rx_queue_setup(struct rte_eth_dev *eth_dev,
		uint16_t rx_queue_id, uint16_t nb_rx_desc,
		unsigned int socket_id,
		const struct rte_eth_rxconf *rx_conf __rte_unused,
		struct rte_mempool *mp)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	struct cndm_ring *rq;

	DRV_LOG(DEBUG, "RX queue setup for eth_dev %s queue %d", eth_dev->data->name, rx_queue_id);

	rq = cndm_create_rq(priv, socket_id);

	if (!rq)
		return -ENOMEM;

	rq->size = rte_align32pow2(nb_rx_desc);
	rq->mp = mp;

	eth_dev->data->rx_queues[rx_queue_id] = rq;

	return 0;
}

static int cndm_dev_tx_queue_stop(struct rte_eth_dev *eth_dev,
		uint16_t tx_queue_id)
{
	struct cndm_ring *sq;
	struct cndm_cq *cq;

	DRV_LOG(DEBUG, "TX queue stop for eth_dev %s queue %d", eth_dev->data->name, tx_queue_id);

	sq = eth_dev->data->tx_queues[tx_queue_id];

	if (!sq)
		goto done;

	cq = sq->cq;

	cndm_close_sq(sq);

	if (cq) {
		cndm_close_cq(cq);
		cndm_destroy_cq(cq);
	}

done:
	eth_dev->data->tx_queue_state[tx_queue_id] = RTE_ETH_QUEUE_STATE_STOPPED;
	return 0;
}

static int cndm_dev_tx_queue_start(struct rte_eth_dev *eth_dev,
		uint16_t tx_queue_id)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	struct cndm_ring *sq;
	struct cndm_cq *cq;
	int ret = 0;

	DRV_LOG(DEBUG, "TX queue start for eth_dev %s queue %d", eth_dev->data->name, tx_queue_id);

	sq = eth_dev->data->tx_queues[tx_queue_id];

	if (!sq)
		return -EINVAL;

	cq = cndm_create_cq(priv, sq->socket_id);
	if (!cq) {
		goto fail;
	}

	ret = cndm_open_cq(cq, sq->size);
	if (ret) {
		cndm_destroy_cq(cq);
		goto fail;
	}

	ret = cndm_open_sq(sq, priv, cq, sq->size);
	if (ret) {
		cndm_destroy_cq(cq);
		goto fail;
	}

	eth_dev->data->tx_queue_state[tx_queue_id] = RTE_ETH_QUEUE_STATE_STARTED;

	return 0;
fail:
	cndm_dev_tx_queue_stop(eth_dev, tx_queue_id);
	return ret;
}

static void cndm_dev_tx_queue_release(struct rte_eth_dev *eth_dev,
		uint16_t tx_queue_id)
{
	struct cndm_ring *sq;

	DRV_LOG(DEBUG, "TX queue release for eth_dev %s queue %d", eth_dev->data->name, tx_queue_id);

	cndm_dev_tx_queue_stop(eth_dev, tx_queue_id);

	sq = eth_dev->data->tx_queues[tx_queue_id];

	cndm_destroy_sq(sq);

	eth_dev->data->tx_queues[tx_queue_id] = NULL;
}

static int cndm_dev_tx_queue_setup(struct rte_eth_dev *eth_dev,
		uint16_t tx_queue_id, uint16_t nb_tx_desc,
		unsigned int socket_id,
		const struct rte_eth_txconf *tx_conf __rte_unused)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	struct cndm_ring *sq;

	DRV_LOG(DEBUG, "TX queue setup for eth_dev %s queue %d", eth_dev->data->name, tx_queue_id);

	sq = cndm_create_sq(priv, socket_id);

	if (!sq)
		return -ENOMEM;

	sq->size = rte_align32pow2(nb_tx_desc);

	eth_dev->data->tx_queues[tx_queue_id] = sq;

	return 0;
}

static int cndm_dev_configure(struct rte_eth_dev *eth_dev)
{
	DRV_LOG(DEBUG, "Dev configure for eth_dev %s", eth_dev->data->name);

	return 0;
}

static int cndm_dev_stop(struct rte_eth_dev *eth_dev)
{
	DRV_LOG(DEBUG, "Dev stop for eth_dev %s", eth_dev->data->name);

	eth_dev->data->dev_started = 0;

	eth_dev->rx_pkt_burst = rte_eth_pkt_burst_dummy;
	eth_dev->tx_pkt_burst = rte_eth_pkt_burst_dummy;

	// Stop all queues
	for (int i = 0; i < eth_dev->data->nb_rx_queues; i++) {
		cndm_dev_rx_queue_stop(eth_dev, i);
	}

	for (int i = 0; i < eth_dev->data->nb_tx_queues; i++) {
		cndm_dev_tx_queue_stop(eth_dev, i);
	}

	return 0;
}

static int cndm_dev_start(struct rte_eth_dev *eth_dev)
{
	int ret = 0;

	DRV_LOG(DEBUG, "Dev start for eth_dev %s", eth_dev->data->name);

	if (eth_dev->data->dev_started)
		return -EINVAL;

	// Start all queues
	for (int i = 0; i < eth_dev->data->nb_rx_queues; i++) {
		ret = cndm_dev_rx_queue_start(eth_dev, i);
		if (ret)
			goto fail;
	}

	for (int i = 0; i < eth_dev->data->nb_tx_queues; i++) {
		ret = cndm_dev_tx_queue_start(eth_dev, i);
		if (ret)
			goto fail;
	}

	eth_dev->rx_pkt_burst = cndm_recv_pkt_burst;
	eth_dev->tx_pkt_burst = cndm_xmit_pkt_burst;

	eth_dev->data->dev_started = 1;

	return 0;
fail:
	cndm_dev_stop(eth_dev);
	return ret;
}

static int cndm_dev_close(struct rte_eth_dev *eth_dev)
{
	DRV_LOG(DEBUG, "Dev close for eth_dev %s", eth_dev->data->name);

	cndm_dev_stop(eth_dev);

	// TODO

	return 0;
}

static int cndm_read_eeprom(struct cndm_priv *priv, __u16 offset, __u16 len, __u8 *data)
{
	int ret = 0;

	struct cndm_cmd_hwid cmd;
	struct cndm_cmd_hwid rsp;

	if (len > 32)
		len = 32;

	cmd.opcode = CNDM_CMD_OP_HWID;
	cmd.flags = 0x00000000;
	cmd.index = 0;
	cmd.brd_opcode = CNDM_CMD_BRD_OP_EEPROM_RD;
	cmd.brd_flags = 0x00000000;
	cmd.dev_addr_offset = 0;
	cmd.page = 0;
	cmd.bank = 0;
	cmd.addr = offset;
	cmd.len = len;

	ret = cndm_exec_cmd(priv->cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(ERR, "Failed to execute command");
		return -ret;
	}

	if (rsp.status || rsp.brd_status) {
		DRV_LOG(WARNING, "Failed to read EEPROM");
		return rsp.status ? -rsp.status : -rsp.brd_status;
	}

	if (data)
		memcpy(data, ((void *)&rsp.data), len);

	return len;
}

static int cndm_write_eeprom(struct cndm_priv *priv, __u16 offset, __u16 len, __u8 *data)
{
	int ret = 0;

	struct cndm_cmd_hwid cmd;
	struct cndm_cmd_hwid rsp;

	// limit length to 32
	if (len > 32)
		len = 32;

	// do not cross 32-byte boundaries
	if (len > 32 - (offset & 31))
		len = 32 - (offset & 31);

	cmd.opcode = CNDM_CMD_OP_HWID;
	cmd.flags = 0x00000000;
	cmd.index = 0;
	cmd.brd_opcode = CNDM_CMD_BRD_OP_EEPROM_WR;
	cmd.brd_flags = 0x00000000;
	cmd.dev_addr_offset = 0;
	cmd.page = 0;
	cmd.bank = 0;
	cmd.addr = offset;
	cmd.len = len;

	memcpy(((void *)&cmd.data), data, len);

	ret = cndm_exec_cmd(priv->cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(ERR, "Failed to execute command");
		return -ret;
	}

	if (rsp.status || rsp.brd_status) {
		DRV_LOG(WARNING, "Failed to write EEPROM");
		return rsp.status ? -rsp.status : -rsp.brd_status;
	}

	return len;
}

static int cndm_get_eeprom_length(struct rte_eth_dev *eth_dev __rte_unused)
{
	return 256; // TODO
}

static int cndm_get_eeprom(struct rte_eth_dev *eth_dev, struct rte_dev_eeprom_info *eeprom)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	unsigned int i = 0;
	int read_len;

	if (eeprom->length == 0)
		return -EINVAL;

	eeprom->magic = 0x4d444e43;

	memset(eeprom->data, 0, eeprom->length);

	while (i < eeprom->length) {
		read_len = cndm_read_eeprom(priv, eeprom->offset + i,
				eeprom->length - i, (__u8 *)eeprom->data + i);

		if (read_len == 0)
			return 0;

		if (read_len < 0) {
			DRV_LOG(ERR, "Failed to read EEPROM (%d)", read_len);
			return read_len;
		}

		i += read_len;
	}

	return 0;
}

static int cndm_set_eeprom(struct rte_eth_dev *eth_dev, struct rte_dev_eeprom_info *eeprom)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	unsigned int i = 0;
	int write_len;

	if (eeprom->length == 0)
		return -EINVAL;

	if (eeprom->magic != 0x4d444e43)
		return -EFAULT;

	while (i < eeprom->length) {
		write_len = cndm_write_eeprom(priv, eeprom->offset + i,
				eeprom->length - i, (__u8 *)eeprom->data + i);

		if (write_len == 0)
			return 0;

		if (write_len < 0) {
			DRV_LOG(ERR, "Failed to write EEPROM (%d)", write_len);
			return write_len;
		}

		i += write_len;
	}

	return 0;
}

#define SFF_MODULE_ID_SFP        0x03
#define SFF_MODULE_ID_QSFP       0x0c
#define SFF_MODULE_ID_QSFP_PLUS  0x0d
#define SFF_MODULE_ID_QSFP28     0x11

static int cndm_read_module_eeprom(struct cndm_priv *priv,
		unsigned short i2c_addr, __u16 page, __u16 bank, __u16 offset, __u16 len, __u8 *data)
{
	int ret = 0;

	struct cndm_cmd_hwid cmd;
	struct cndm_cmd_hwid rsp;

	if (len > 32)
		len = 32;

	cmd.opcode = CNDM_CMD_OP_HWMON;
	cmd.flags = 0x00000000;
	cmd.index = 0; // TODO
	cmd.brd_opcode = CNDM_CMD_BRD_OP_OPTIC_RD;
	cmd.brd_flags = 0x00000000;
	cmd.dev_addr_offset = i2c_addr - 0x50;
	cmd.page = page;
	cmd.bank = bank;
	cmd.addr = offset;
	cmd.len = len;

	ret = cndm_exec_cmd(priv->cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(ERR, "Failed to execute command");
		return -ret;
	}

	if (rsp.status || rsp.brd_status) {
		DRV_LOG(WARNING, "Failed to read module EEPROM");
		return rsp.status ? -rsp.status : -rsp.brd_status;
	}

	if (data)
		memcpy(data, ((void *)&rsp.data), len);

	return len;
}

static int cndm_query_module_id(struct cndm_priv *priv)
{
	int ret;
	__u8 data = 0;

	ret = cndm_read_module_eeprom(priv, 0x50, 0, 0, 0, 1, &data);

	if (ret < 0)
		return ret;

	return data;
}

static int cndm_query_module_eeprom_by_page(struct cndm_priv *priv,
		unsigned short i2c_addr, __u16 page, __u16 bank, __u16 offset, __u16 len, __u8 *data)
{
	int module_id;
	int ret;

	module_id = cndm_query_module_id(priv);

	if (module_id < 0) {
		DRV_LOG(ERR, "Failed to read module ID (%d)", module_id);
		return module_id;
	}

	switch (module_id) {
	case SFF_MODULE_ID_SFP:
		if (page > 0 || bank > 0)
			return -EINVAL;
		if (i2c_addr != 0x50 && i2c_addr != 0x51)
			return -EINVAL;
		break;
	case SFF_MODULE_ID_QSFP:
	case SFF_MODULE_ID_QSFP_PLUS:
	case SFF_MODULE_ID_QSFP28:
		if (page > 3 || bank > 0)
			return -EINVAL;
		if (i2c_addr != 0x50)
			return -EINVAL;
		break;
	default:
		DRV_LOG(ERR, "Unknown module ID (0x%x)", module_id);
		return -EINVAL;
	}

	// read data
	ret = cndm_read_module_eeprom(priv, i2c_addr, page, bank, offset, len, data);

	return ret;
}

static int cndm_query_module_eeprom(struct cndm_priv *priv,
		__u16 offset, __u16 len, __u8 *data)
{
	int module_id;
	unsigned short i2c_addr = 0x50;
	__u16 page = 0;
	__u16 bank = 0;

	module_id = cndm_query_module_id(priv);

	if (module_id < 0) {
		DRV_LOG(ERR, "Failed to read module ID (%d)", module_id);
		return module_id;
	}

	switch (module_id) {
	case SFF_MODULE_ID_SFP:
		i2c_addr = 0x50;
		page = 0;
		if (offset >= 256) {
			offset -= 256;
			i2c_addr = 0x51;
		}
		break;
	case SFF_MODULE_ID_QSFP:
	case SFF_MODULE_ID_QSFP_PLUS:
	case SFF_MODULE_ID_QSFP28:
		i2c_addr = 0x50;
		if (offset < 256) {
			page = 0;
		} else {
			page = 1 + ((offset - 256) / 128);
			offset -= page * 128;
		}
		break;
	default:
		DRV_LOG(ERR, "Unknown module ID (0x%x)", module_id);
		return -EINVAL;
	}

	// clip request to end of page
	if (offset + len > 256)
		len = 256 - offset;

	return cndm_query_module_eeprom_by_page(priv, i2c_addr,
			page, bank, offset, len, data);
}

static int cndm_get_module_info(struct rte_eth_dev *eth_dev, struct rte_eth_dev_module_info *modinfo)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	int read_len = 0;
	__u8 data[16];

	// read module ID and revision
	read_len = cndm_read_module_eeprom(priv, 0x50, 0, 0, 0, 2, data);

	if (read_len < 0)
		return read_len;

	if (read_len < 2)
		return -EIO;

	// check identifier byte at address 0
	switch (data[0]) {
	case SFF_MODULE_ID_SFP:
		modinfo->type = RTE_ETH_MODULE_SFF_8472;
		modinfo->eeprom_len = RTE_ETH_MODULE_SFF_8472_LEN;
		break;
	case SFF_MODULE_ID_QSFP:
		modinfo->type = RTE_ETH_MODULE_SFF_8436;
		modinfo->eeprom_len = RTE_ETH_MODULE_SFF_8436_MAX_LEN;
		break;
	case SFF_MODULE_ID_QSFP_PLUS:
		// check revision at address 1
		if (data[1] >= 0x03) {
			modinfo->type = RTE_ETH_MODULE_SFF_8636;
			modinfo->eeprom_len = RTE_ETH_MODULE_SFF_8636_MAX_LEN;
		} else {
			modinfo->type = RTE_ETH_MODULE_SFF_8436;
			modinfo->eeprom_len = RTE_ETH_MODULE_SFF_8436_MAX_LEN;
		}
		break;
	case SFF_MODULE_ID_QSFP28:
		modinfo->type = RTE_ETH_MODULE_SFF_8636;
		modinfo->eeprom_len = RTE_ETH_MODULE_SFF_8636_MAX_LEN;
		break;
	default:
		DRV_LOG(ERR, "Unknown module ID (0x%x)", data[0]);
		return -EINVAL;
	}

	return 0;
}

static int cndm_get_module_eeprom(struct rte_eth_dev *eth_dev, struct rte_dev_eeprom_info *eeprom)
{
	struct cndm_priv *priv = eth_dev->data->dev_private;
	unsigned int i = 0;
	int read_len;

	if (eeprom->length == 0)
		return -EINVAL;

	eeprom->magic = 0x4d444e43;

	memset(eeprom->data, 0, eeprom->length);

	while (i < eeprom->length) {
		read_len = cndm_query_module_eeprom(priv, eeprom->offset + i,
				eeprom->length - i, (__u8 *)eeprom->data + i);

		if (read_len == 0)
			return 0;

		if (read_len < 0) {
			DRV_LOG(ERR, "Failed to read module EEPROM (%d)", read_len);
			return read_len;
		}

		i += read_len;
	}

	return 0;
}

static const struct eth_dev_ops cndm_eth_dev_ops = {
	.dev_configure		= cndm_dev_configure,
	.dev_start		= cndm_dev_start,
	.dev_stop		= cndm_dev_stop,
	.dev_close		= cndm_dev_close,
	.link_update		= cndm_link_update,
	.promiscuous_enable	= cndm_promiscuous_mode_enable,
	.promiscuous_disable	= cndm_promiscuous_mode_disable,
	.mac_addr_set		= cndm_mac_addr_set,
	.mtu_set		= cndm_mtu_set,
	.stats_get		= cndm_stats_get,
	.stats_reset		= cndm_stats_reset,
	.dev_infos_get		= cndm_dev_info_get,
	.rxq_info_get		= cndm_dev_rxq_info_get,
	.txq_info_get		= cndm_dev_txq_info_get,
	.fw_version_get		= cndm_dev_fw_version_get,
	.rx_queue_start		= cndm_dev_rx_queue_start,
	.rx_queue_stop		= cndm_dev_rx_queue_stop,
	.tx_queue_start		= cndm_dev_tx_queue_start,
	.tx_queue_stop		= cndm_dev_tx_queue_stop,
	.rx_queue_setup		= cndm_dev_rx_queue_setup,
	.rx_queue_release	= cndm_dev_rx_queue_release,
	.tx_queue_setup		= cndm_dev_tx_queue_setup,
	.tx_queue_release	= cndm_dev_tx_queue_release,
	.get_eeprom_length	= cndm_get_eeprom_length,
	.get_eeprom		= cndm_get_eeprom,
	.set_eeprom		= cndm_set_eeprom,
	.get_module_info	= cndm_get_module_info,
	.get_module_eeprom	= cndm_get_module_eeprom,
};

struct rte_eth_dev *cndm_create_eth_dev(struct cndm_dev *cdev, int port)
{
	struct rte_eth_dev *eth_dev = NULL;
	struct cndm_priv *priv;
	char name[RTE_ETH_NAME_MAX_LEN];

	snprintf(name, sizeof(name), "%s_p%d", cdev->pdev->device.name, port);

	DRV_LOG(DEBUG, "Create eth_dev %s (port %d)", name, port);

	eth_dev = rte_eth_dev_allocate(name);
	if (!eth_dev)
		return NULL;

	priv = rte_zmalloc_socket(NULL, sizeof(*priv), RTE_CACHE_LINE_SIZE,
			cdev->pdev->device.numa_node);
	if (!priv)
		goto fail;

	eth_dev->data->dev_private = priv;
	eth_dev->device = &cdev->pdev->device;
	priv->eth_dev = eth_dev;
	priv->cdev = cdev;

	priv->port_id = eth_dev->data->port_id;
	priv->dev_port = port;

	rte_eth_copy_pci_info(eth_dev, cdev->pdev);

	priv->hw_addr = cdev->hw_addr;

	priv->rxq_count = 1;
	priv->txq_count = 1;

	eth_dev->data->mac_addrs = rte_calloc("cndm_mac", 1,
			sizeof(struct rte_ether_addr), 0);
	rte_eth_random_addr((void *)eth_dev->data->mac_addrs);

	eth_dev->dev_ops = &cndm_eth_dev_ops;
	eth_dev->rx_pkt_burst = rte_eth_pkt_burst_dummy;
	eth_dev->tx_pkt_burst = rte_eth_pkt_burst_dummy;

	rte_eth_dev_probing_finish(eth_dev);

	priv->registered = 1;

	return eth_dev;

fail:
	cndm_destroy_eth_dev(eth_dev);
	return NULL;
}

void cndm_destroy_eth_dev(struct rte_eth_dev *eth_dev)
{
	DRV_LOG(DEBUG, "Destroy eth_dev %s", eth_dev->data->name);

	cndm_dev_stop(eth_dev);
}
