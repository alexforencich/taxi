/* SPDX-License-Identifier: BSD-3-Clause
 * Copyright (c) 2025-2026 FPGA Ninja, LLC
 *
 * Authors:
 * - Alex Forencich
 */

#include "cndm.h"

#include <time.h>

#include <bus_pci_driver.h>
#include <rte_io.h>
#include <rte_malloc.h>
#include <rte_pci.h>

static void cndm_common_remove(struct cndm_dev *cdev);

static int cndm_common_probe(struct cndm_dev *cdev)
{
	int ret = 0;

	struct cndm_cmd_cfg cmd;
	struct cndm_cmd_cfg rsp;

	rte_spinlock_init(&cdev->mbox_lock);

	// Read config page 0
	cmd.opcode = CNDM_CMD_OP_CFG;
	cmd.flags = 0x00000000;
	cmd.cfg_page = 0;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(NOTICE, "Failed to execute command");
		goto fail;
	}

	if (rsp.status) {
		DRV_LOG(NOTICE, "Command failed");
		ret = rsp.status;
		goto fail;
	}

	cdev->cfg_page_max = rsp.cfg_page_max;
	cdev->cmd_ver = rsp.cmd_ver;

	DRV_LOG(NOTICE, "Config pages: %d", cdev->cfg_page_max+1);
	DRV_LOG(NOTICE, "Command version: %d.%d.%d", cdev->cmd_ver >> 20,
		(cdev->cmd_ver >> 12) & 0xff,
		cdev->cmd_ver & 0xfff);

	// FW ID
	cdev->fpga_id = rsp.p0.fpga_id;
	cdev->fw_id = rsp.p0.fw_id;
	cdev->fw_ver = rsp.p0.fw_ver;
	cdev->board_id = rsp.p0.board_id;
	cdev->board_ver = rsp.p0.board_ver;
	cdev->build_date = rsp.p0.build_date;
	cdev->git_hash = rsp.p0.git_hash;
	cdev->release_info = rsp.p0.release_info;

	DRV_LOG(NOTICE, "FPGA ID: 0x%08x", cdev->fpga_id);
	DRV_LOG(NOTICE, "FW ID: 0x%08x", cdev->fw_id);
	DRV_LOG(NOTICE, "FW version: %d.%d.%d", cdev->fw_ver >> 20,
		(cdev->fw_ver >> 12) & 0xff,
		cdev->fw_ver & 0xfff);
	DRV_LOG(NOTICE, "Board ID: 0x%08x", cdev->board_id);
	DRV_LOG(NOTICE, "Board version: %d.%d.%d", cdev->board_ver >> 20,
		(cdev->board_ver >> 12) & 0xff,
		cdev->board_ver & 0xfff);

	time_t build_date = cdev->build_date;
	struct tm *tm_info = gmtime(&build_date);
	strftime(cdev->build_date_str, sizeof(cdev->build_date_str), "%F %T", tm_info);

	DRV_LOG(NOTICE, "Build date: %s UTC (raw: 0x%08x)", cdev->build_date_str, cdev->build_date);
	DRV_LOG(NOTICE, "Git hash: %08x", cdev->git_hash);
	DRV_LOG(NOTICE, "Release info: %08x", cdev->release_info);

	// Read config page 1
	cmd.opcode = CNDM_CMD_OP_CFG;
	cmd.flags = 0x00000000;
	cmd.cfg_page = 1;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(NOTICE, "Failed to execute command");
		goto fail;
	}

	if (rsp.status) {
		DRV_LOG(NOTICE, "Command failed");
		ret = rsp.status;
		goto fail;
	}

	// HW config
	cdev->port_count = rsp.p1.port_count;
	cdev->sys_clk_per_ns_num = rsp.p1.sys_clk_per_ns_num;
	cdev->sys_clk_per_ns_den = rsp.p1.sys_clk_per_ns_den;
	cdev->ptp_clk_per_ns_num = rsp.p1.ptp_clk_per_ns_num;
	cdev->ptp_clk_per_ns_den = rsp.p1.ptp_clk_per_ns_den;

	DRV_LOG(NOTICE, "Port count: %d", cdev->port_count);
	if (cdev->sys_clk_per_ns_num != 0) {
		__u64 a, b, c;
		a = (__u64)cdev->sys_clk_per_ns_den * 1000;
		b = a / cdev->sys_clk_per_ns_num;
		c = a - (b * cdev->sys_clk_per_ns_num);
		c = (c * 1000000000) / cdev->sys_clk_per_ns_num;
		DRV_LOG(NOTICE, "Sys clock freq: %lld.%09lld MHz (raw %d/%d ns)", b, c, cdev->sys_clk_per_ns_num, cdev->sys_clk_per_ns_den);
	}
	if (cdev->ptp_clk_per_ns_num != 0) {
		__u64 a, b, c;
		a = (__u64)cdev->ptp_clk_per_ns_den * 1000;
		b = a / cdev->ptp_clk_per_ns_num;
		c = a - (b * cdev->ptp_clk_per_ns_num);
		c = (c * 1000000000) / cdev->ptp_clk_per_ns_num;
		DRV_LOG(NOTICE, "PTP clock freq: %lld.%09lld MHz (raw %d/%d ns)", b, c, cdev->ptp_clk_per_ns_num, cdev->ptp_clk_per_ns_den);
	}

	// Read config page 2
	cmd.opcode = CNDM_CMD_OP_CFG;
	cmd.flags = 0x00000000;
	cmd.cfg_page = 2;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret) {
		DRV_LOG(NOTICE, "Failed to execute command");
		goto fail;
	}

	if (rsp.status) {
		DRV_LOG(NOTICE, "Command failed");
		ret = rsp.status;
		goto fail;
	}

	// Resources
	cdev->log_max_eq = rsp.p2.log_max_eq;
	cdev->log_max_eq_sz = rsp.p2.log_max_eq_sz;
	cdev->eq_pool = rsp.p2.eq_pool;
	cdev->eqe_ver = rsp.p2.eqe_ver;
	cdev->log_max_cq = rsp.p2.log_max_cq;
	cdev->log_max_cq_sz = rsp.p2.log_max_cq_sz;
	cdev->cq_pool = rsp.p2.cq_pool;
	cdev->cqe_ver = rsp.p2.cqe_ver;
	cdev->log_max_sq = rsp.p2.log_max_sq;
	cdev->log_max_sq_sz = rsp.p2.log_max_sq_sz;
	cdev->sq_pool = rsp.p2.sq_pool;
	cdev->sqe_ver = rsp.p2.sqe_ver;
	cdev->log_max_rq = rsp.p2.log_max_rq;
	cdev->log_max_rq_sz = rsp.p2.log_max_rq_sz;
	cdev->rq_pool = rsp.p2.rq_pool;
	cdev->rqe_ver = rsp.p2.rqe_ver;

	DRV_LOG(NOTICE, "Max EQ count: %d (log %d)", 1 << cdev->log_max_eq, cdev->log_max_eq);
	DRV_LOG(NOTICE, "Max EQ size: %d (log %d)", 1 << cdev->log_max_eq_sz, cdev->log_max_eq_sz);
	DRV_LOG(NOTICE, "EQ pool: %d", cdev->eq_pool);
	DRV_LOG(NOTICE, "EQE version: %d", cdev->eqe_ver);
	DRV_LOG(NOTICE, "Max CQ count: %d (log %d)", 1 << cdev->log_max_cq, cdev->log_max_cq);
	DRV_LOG(NOTICE, "Max CQ size: %d (log %d)", 1 << cdev->log_max_cq_sz, cdev->log_max_cq_sz);
	DRV_LOG(NOTICE, "CQ pool: %d", cdev->cq_pool);
	DRV_LOG(NOTICE, "CQE version: %d", cdev->cqe_ver);
	DRV_LOG(NOTICE, "Max SQ count: %d (log %d)", 1 << cdev->log_max_sq, cdev->log_max_sq);
	DRV_LOG(NOTICE, "Max SQ size: %d (log %d)", 1 << cdev->log_max_sq_sz, cdev->log_max_sq_sz);
	DRV_LOG(NOTICE, "SQ pool: %d", cdev->sq_pool);
	DRV_LOG(NOTICE, "SQE version: %d", cdev->sqe_ver);
	DRV_LOG(NOTICE, "Max RQ count: %d (log %d)", 1 << cdev->log_max_rq, cdev->log_max_rq);
	DRV_LOG(NOTICE, "Max RQ size: %d (log %d)", 1 << cdev->log_max_rq_sz, cdev->log_max_rq_sz);
	DRV_LOG(NOTICE, "RQ pool: %d", cdev->rq_pool);
	DRV_LOG(NOTICE, "RQE version: %d", cdev->rqe_ver);

	DRV_LOG(NOTICE, "Read HW IDs");

	ret = cndm_hwid_sn_rd(cdev, NULL, &cdev->sn_str);
	if (ret || !strlen(cdev->sn_str)) {
		DRV_LOG(NOTICE, "No readable serial number");
	} else {
		DRV_LOG(NOTICE, "SN: %s", cdev->sn_str);
	}

	ret = cndm_hwid_mac_rd(cdev, 0, &cdev->mac_cnt, &cdev->base_mac);
	if (ret) {
		DRV_LOG(NOTICE, "No readable MACs");
		cdev->mac_cnt = 0;
	} else if (!rte_is_valid_assigned_ether_addr(&cdev->base_mac)) {
		DRV_LOG(WARNING
			, "Base MAC is invalid");
		cdev->mac_cnt = 0;
	} else {
		DRV_LOG(NOTICE, "MAC count: %d", cdev->mac_cnt);
		DRV_LOG(NOTICE, "Base MAC: " RTE_ETHER_ADDR_PRT_FMT,
				RTE_ETHER_ADDR_BYTES(&cdev->base_mac));
	}

	if (cdev->port_count > ARRAY_SIZE(cdev->eth_dev))
		cdev->port_count = ARRAY_SIZE(cdev->eth_dev);

	for (__u32 k = 0; k < cdev->port_count; k++) {
		struct rte_eth_dev *eth_dev;

		eth_dev = cndm_create_eth_dev(cdev, k);
		if (!eth_dev) {
			ret = -1;
			goto fail_eth_dev;
		}

		cdev->eth_dev[k] = eth_dev;
	}

fail_eth_dev:
	return 0;

fail:
	cndm_common_remove(cdev);
	return ret;
}

static void cndm_common_remove(struct cndm_dev *cdev)
{
	for (size_t k = 0; k < ARRAY_SIZE(cdev->eth_dev); k++) {
		if (cdev->eth_dev[k]) {
			cndm_destroy_eth_dev(cdev->eth_dev[k]);
			cdev->eth_dev[k] = NULL;
		}
	}
}

static int cndm_pci_probe(struct rte_pci_driver *pdrv __rte_unused, struct rte_pci_device *pdev)
{
	struct cndm_dev *cdev;
	off_t pcie_cap;
	int ret = 0;

	DRV_LOG(NOTICE, "PCI probe");
	DRV_LOG(NOTICE, "Corundum DPDK PMD");
	DRV_LOG(NOTICE, "Version " DRIVER_VERSION);
	DRV_LOG(NOTICE, "Copyright (c) 2026 FPGA Ninja, LLC");
	DRV_LOG(NOTICE, "https://fpga.ninja/");
	DRV_LOG(NOTICE, "PCIe configuration summary:");

	pcie_cap = rte_pci_find_capability(pdev, RTE_PCI_CAP_ID_EXP);

	if (pcie_cap) {
		__u16 devctl;
		__u32 lnkcap;
		__u16 lnkctl;
		__u16 lnksta;

		rte_pci_read_config(pdev, &devctl, 2, pcie_cap + RTE_PCI_EXP_DEVCTL);
		rte_pci_read_config(pdev, &lnkcap, 4, pcie_cap + RTE_PCI_EXP_LNKCAP);
		rte_pci_read_config(pdev, &lnkctl, 2, pcie_cap + RTE_PCI_EXP_LNKCTL);
		rte_pci_read_config(pdev, &lnksta, 2, pcie_cap + RTE_PCI_EXP_LNKSTA);

		DRV_LOG(NOTICE, "  Max payload size: %d bytes",
				128 << ((devctl & RTE_PCI_EXP_DEVCTL_PAYLOAD) >> 5));
		DRV_LOG(NOTICE, "  Max read request size: %d bytes",
				128 << ((devctl & RTE_PCI_EXP_DEVCTL_READRQ) >> 12));
		DRV_LOG(NOTICE, "  Read completion boundary: %d bytes",
				lnkctl & RTE_PCI_EXP_LNKCTL_RCB ? 128 : 64);
		DRV_LOG(NOTICE, "  Link capability: gen %d x%d",
				lnkcap & RTE_PCI_EXP_LNKCAP_SLS, (lnkcap & RTE_PCI_EXP_LNKCAP_MLW) >> 4);
		DRV_LOG(NOTICE, "  Link status: gen %d x%d",
				lnksta & RTE_PCI_EXP_LNKSTA_CLS, (lnksta & RTE_PCI_EXP_LNKSTA_NLW) >> 4);
		DRV_LOG(NOTICE, "  Relaxed ordering: %s",
				devctl & RTE_PCI_EXP_DEVCTL_RELAX_EN ? "enabled" : "disabled");
		DRV_LOG(NOTICE, "  Phantom functions: %s",
				devctl & RTE_PCI_EXP_DEVCTL_PHANTOM ? "enabled" : "disabled");
		DRV_LOG(NOTICE, "  Extended tags: %s",
				devctl & RTE_PCI_EXP_DEVCTL_EXT_TAG ? "enabled" : "disabled");
		DRV_LOG(NOTICE, "  No snoop: %s",
				devctl & RTE_PCI_EXP_DEVCTL_NOSNOOP_EN ? "enabled" : "disabled");
	}

	DRV_LOG(NOTICE, "  NUMA node: %d", pdev->device.numa_node);

	cdev = rte_zmalloc_socket(pdev->device.name,
			sizeof(struct cndm_dev), RTE_CACHE_LINE_SIZE,
			pdev->device.numa_node);

	if (!cdev)
		return -ENOMEM;

	cdev->pdev = pdev;

	// TODO store cdev reference

	cdev->hw_regs_size = pdev->mem_resource[0].len;
	cdev->hw_regs_phys = pdev->mem_resource[0].phys_addr;
	cdev->hw_addr = pdev->mem_resource[0].addr;

	DRV_LOG(NOTICE, "Control BAR size: %lu", cdev->hw_regs_size);
	if (!cdev->hw_addr) {
		ret = -ENOMEM;
		DRV_LOG(ERR, "Failed to map control BAR");
		goto fail;
	}

	if (rte_read32(pdev->mem_resource[0].addr) == 0xffffffff) {
		ret = -EIO;
		DRV_LOG(ERR, "Device needs to be reset");
		goto fail;
	}

	ret = cndm_common_probe(cdev);
	if (ret)
		goto fail;

	return 0;

fail:
	rte_free(cdev);
	return ret;
}

static int cndm_pci_remove(struct rte_pci_device *pdev __rte_unused)
{
	DRV_LOG(NOTICE, "PCI remove");

	return 0;
}

static const struct rte_pci_id pci_id_cndm_map[] = {
	{RTE_PCI_DEVICE(0x1234, 0xC001)},
	{0}
};

static struct rte_pci_driver rte_cndm_pmd = {
	.id_table = pci_id_cndm_map,
	.drv_flags = RTE_PCI_DRV_NEED_MAPPING,
	.probe = cndm_pci_probe,
	.remove = cndm_pci_remove,
};

RTE_PMD_REGISTER_PCI(net_cndm, rte_cndm_pmd);
RTE_PMD_REGISTER_PCI_TABLE(net_cndm, pci_id_cndm_map);
RTE_PMD_REGISTER_KMOD_DEP(net_cndm, "* vfio-pci");
RTE_LOG_REGISTER_DEFAULT(cndm_logtype_driver, NOTICE);
