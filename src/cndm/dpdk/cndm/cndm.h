/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright (c) 2025-2026 FPGA Ninja, LLC
 *
 * Authors:
 * - Alex Forencich
 */

#ifndef CNDM_H
#define CNDM_H

#include <rte_common.h>
#include <rte_ether.h>

#include "cndm_hw.h"

#define ARRAY_SIZE(x) RTE_DIM(x)
#define ETH_ALEN RTE_ETHER_ADDR_LEN

#ifndef RTE_PCI_EXP_LNKCAP
#define RTE_PCI_EXP_LNKCAP 12
#endif

#ifndef RTE_PCI_EXP_LNKCTL_RCB
#define RTE_PCI_EXP_LNKCTL_RCB 0x0008
#endif

#ifndef RTE_PCI_EXP_LNKCAP_SLS
#define RTE_PCI_EXP_LNKCAP_SLS 0x0000000f
#endif

#ifndef RTE_PCI_EXP_LNKCAP_MLW
#define RTE_PCI_EXP_LNKCAP_MLW 0x000003f0
#endif

#ifndef RTE_PCI_EXP_DEVCTL_RELAX_EN
#define RTE_PCI_EXP_DEVCTL_RELAX_EN 0x0010
#endif

#ifndef RTE_PCI_EXP_DEVCTL_PHANTOM
#define RTE_PCI_EXP_DEVCTL_PHANTOM 0x0200
#endif

#ifndef RTE_PCI_EXP_DEVCTL_NOSNOOP_EN
#define RTE_PCI_EXP_DEVCTL_NOSNOOP_EN 0x0800
#endif

#define DRIVER_VERSION "0.1"

struct cndm_dev {
	struct rte_pci_device *pdev;

	struct rte_eth_dev *eth_dev[32];

	uint64_t hw_regs_size;
	phys_addr_t hw_regs_phys;
	__u8 *hw_addr;

	rte_spinlock_t mbox_lock;

	__u32 port_count;

	// config
	__u16 cfg_page_max;
	__u32 cmd_ver;

	// FW ID
	__u32 fpga_id;
	__u32 fw_id;
	__u32 fw_ver;
	__u32 board_id;
	__u32 board_ver;
	__u32 build_date;
	__u32 git_hash;
	__u32 release_info;
	char build_date_str[32];

	// HW config
	__u16 sys_clk_per_ns_num;
	__u16 sys_clk_per_ns_den;
	__u16 ptp_clk_per_ns_num;
	__u16 ptp_clk_per_ns_den;

	// Resources
	__u8 log_max_eq;
	__u8 log_max_eq_sz;
	__u8 eq_pool;
	__u8 eqe_ver;
	__u8 log_max_cq;
	__u8 log_max_cq_sz;
	__u8 cq_pool;
	__u8 cqe_ver;
	__u8 log_max_sq;
	__u8 log_max_sq_sz;
	__u8 sq_pool;
	__u8 sqe_ver;
	__u8 log_max_rq;
	__u8 log_max_rq_sz;
	__u8 rq_pool;
	__u8 rqe_ver;

	// HW IDs
	char sn_str[32];
	struct rte_ether_addr base_mac;
	int mac_cnt;
};

struct cndm_tx_info {
	struct rte_mbuf *mbuf;
};

struct cndm_rx_info {
	struct rte_mbuf *mbuf;
};

struct __rte_cache_aligned cndm_ring {
	// written on enqueue
	__u32 prod_ptr;
	__u64 bytes;
	__u64 packet;
	__u64 dropped_packets;
	struct netdev_queue *tx_queue;

	// written from completion
	__u32 cons_ptr __rte_cache_aligned;
	__u64 ts_s;
	__u8 ts_valid;

	// mostly constant
	__u32 size;
	__u32 full_size;
	__u32 size_mask;
	__u32 stride;

	__u32 mtu;

	size_t buf_size;
	__u8 *buf;
	rte_iova_t buf_dma_addr;

	union {
		struct cndm_tx_info *tx_info;
		struct cndm_rx_info *rx_info;
	};

	struct cndm_dev *cdev;
	struct cndm_priv *priv;
	unsigned int socket_id;
	int index;
	int enabled;

	struct rte_mempool *mp;

	struct cndm_cq *cq;

	__u32 db_offset;
	__u8 *db_addr;
};

struct cndm_cq {
	__u32 cons_ptr;

	__u32 size;
	__u32 size_mask;
	__u32 stride;

	size_t buf_size;
	__u8 *buf;
	rte_iova_t buf_dma_addr;

	struct cndm_dev *cdev;
	struct cndm_priv *priv;
	unsigned int socket_id;
	int cqn;
	int enabled;

	struct cndm_ring *src_ring;

	void (*handler)(struct cndm_cq *cq);

	__u32 db_offset;
	__u8 *db_addr;
};

struct cndm_priv {
	struct rte_eth_dev *eth_dev;
	struct cndm_dev *cdev;

	int dev_port;
	int port_id;

	bool registered;
	bool port_up;

	__u8 *hw_addr;

	int rxq_count;
	int txq_count;

	struct cndm_ring *txq;
	struct cndm_ring *rxq;
};

extern int cndm_logtype_driver;
#define RTE_LOGTYPE_CNDM_DRIVER cndm_logtype_driver

#define DRV_LOG(level, ...) \
	RTE_LOG_LINE_PREFIX(level, CNDM_DRIVER, "%s(): ", __func__, __VA_ARGS__)

// cndm_cmd.c
int cndm_exec_mbox_cmd(struct cndm_dev *cdev, void *cmd, void *rsp);
int cndm_exec_cmd(struct cndm_dev *cdev, void *cmd, void *rsp);
int cndm_access_reg(struct cndm_dev *cdev, __u32 reg, int raw, int write, __u64 *data);
int cndm_hwid_sn_rd(struct cndm_dev *cdev, int *len, void *data);
int cndm_hwid_mac_rd(struct cndm_dev *cdev, __u16 index, int *cnt, void *data);

// cndm_ethdev.c
struct rte_eth_dev *cndm_create_eth_dev(struct cndm_dev *cdev, int port);
void cndm_destroy_eth_dev(struct rte_eth_dev *eth_dev);

// cndm_cq.c
struct cndm_cq *cndm_create_cq(struct cndm_priv *priv, unsigned int socket_id);
void cndm_destroy_cq(struct cndm_cq *cq);
int cndm_open_cq(struct cndm_cq *cq, int size);
void cndm_close_cq(struct cndm_cq *cq);
void cndm_cq_write_cons_ptr(const struct cndm_cq *cq);
void cndm_cq_write_cons_ptr_arm(const struct cndm_cq *cq);

// cndm_sq.c
struct cndm_ring *cndm_create_sq(struct cndm_priv *priv, unsigned int socket_id);
void cndm_destroy_sq(struct cndm_ring *sq);
int cndm_open_sq(struct cndm_ring *sq, struct cndm_priv *priv, struct cndm_cq *cq, int size);
void cndm_close_sq(struct cndm_ring *sq);
bool cndm_is_sq_ring_empty(const struct cndm_ring *sq);
bool cndm_is_sq_ring_full(const struct cndm_ring *sq);
void cndm_sq_write_prod_ptr(const struct cndm_ring *sq);
uint16_t cndm_xmit_pkt_burst(void *queue, struct rte_mbuf **pkts, uint16_t nb_pkts);

// cndm_rq.c
struct cndm_ring *cndm_create_rq(struct cndm_priv *priv, unsigned int socket_id);
void cndm_destroy_rq(struct cndm_ring *rq);
int cndm_open_rq(struct cndm_ring *rq, struct cndm_priv *priv, struct cndm_cq *cq, int size);
void cndm_close_rq(struct cndm_ring *rq);
bool cndm_is_rq_ring_empty(const struct cndm_ring *rq);
bool cndm_is_rq_ring_full(const struct cndm_ring *rq);
void cndm_rq_write_prod_ptr(const struct cndm_ring *rq);
int cndm_refill_rx_buffers(struct cndm_ring *rq);
uint16_t cndm_recv_pkt_burst(void *queue, struct rte_mbuf **pkts, uint16_t nb_pkts);

#endif
