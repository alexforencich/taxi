/* SPDX-License-Identifier: GPL */
// Copyright (c) 2025 FPGA Ninja

#ifndef CNDM_PROTO_H
#define CNDM_PROTO_H

#include <linux/kernel.h>
#include <linux/pci.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>

#define DRIVER_NAME "cndm_proto"
#define DRIVER_VERSION "0.1"

struct cndm_proto_dev {
	struct pci_dev *pdev;
	struct device *dev;

	struct net_device *ndev[32];

	void __iomem *bar;
	resource_size_t bar_len;

	u32 port_count;
	u32 port_offset;
	u32 port_stride;
};

struct cndm_proto_tx_info {
	struct sk_buff *skb;
	dma_addr_t dma_addr;
	u32 len;
};

struct cndm_proto_rx_info {
	struct page *page;
	dma_addr_t dma_addr;
	u32 len;
};

struct cndm_proto_priv {
	struct device *dev;
	struct net_device *ndev;
	struct cndm_proto_dev *cdev;

	bool registered;
	bool port_up;

	void __iomem *hw_addr;

	size_t txq_region_len;
	void *txq_region;
	dma_addr_t txq_region_addr;

	struct cndm_proto_tx_info *tx_info;
	struct cndm_proto_rx_info *rx_info;

	struct netdev_queue *tx_queue;

	struct napi_struct tx_napi;
	struct napi_struct rx_napi;

	u32 txq_log_size;
	u32 txq_size;
	u32 txq_mask;
	u32 txq_prod;
	u32 txq_cons;

	size_t rxq_region_len;
	void *rxq_region;
	dma_addr_t rxq_region_addr;

	u32 rxq_log_size;
	u32 rxq_size;
	u32 rxq_mask;
	u32 rxq_prod;
	u32 rxq_cons;

	size_t txcq_region_len;
	void *txcq_region;
	dma_addr_t txcq_region_addr;

	u32 txcq_log_size;
	u32 txcq_size;
	u32 txcq_mask;
	u32 txcq_prod;
	u32 txcq_cons;

	size_t rxcq_region_len;
	void *rxcq_region;
	dma_addr_t rxcq_region_addr;

	u32 rxcq_log_size;
	u32 rxcq_size;
	u32 rxcq_mask;
	u32 rxcq_prod;
	u32 rxcq_cons;
};

struct cndm_proto_desc {
	__u8 rsvd[4];
	__le32 len;
	__le64 addr;
};

struct cndm_proto_cpl {
	__u8 rsvd[4];
	__le32 len;
	__u8 rsvd2[7];
	__u8 phase;
};

irqreturn_t cndm_proto_irq(int irqn, void *data);
struct net_device *cndm_proto_create_netdev(struct cndm_proto_dev *cdev, int port, void __iomem *hw_addr);
void cndm_proto_destroy_netdev(struct net_device *ndev);

int cndm_proto_free_tx_buf(struct cndm_proto_priv *priv);
int cndm_proto_poll_tx_cq(struct napi_struct *napi, int budget);
int cndm_proto_start_xmit(struct sk_buff *skb, struct net_device *ndev);

int cndm_proto_free_rx_buf(struct cndm_proto_priv *priv);
int cndm_proto_refill_rx_buffers(struct cndm_proto_priv *priv);
int cndm_proto_poll_rx_cq(struct napi_struct *napi, int budget);

#endif
