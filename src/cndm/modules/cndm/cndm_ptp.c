// SPDX-License-Identifier: GPL
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#include "cndm.h"
#include <linux/version.h>

ktime_t cndm_read_cpl_ts(struct cndm_ring *ring, const struct cndm_cpl *cpl)
{
	struct cndm_dev *cdev = ring->cdev;

	// u64 ts_s = le16_to_cpu(cpl->ts_s);
	u64 ts_s = cpl->ts_s;
	u32 ts_ns = le32_to_cpu(cpl->ts_ns);

	if (unlikely(!ring->ts_valid || (ring->ts_s ^ ts_s) & 0xf0)) {
		// seconds MSBs do not match, update cached timestamp
		ring->ts_s = ioread32(cdev->hw_addr + 0x0308);
		ring->ts_s |= (u64) ioread32(cdev->hw_addr + 0x030C) << 32;
		ring->ts_valid = 1;
	}

	ts_s |= ring->ts_s & 0xfffffffffffffff0;

	dev_dbg(cdev->dev, "%s: Read timestamp: %lld.%09d", __func__, ts_s, ts_ns);

	return ktime_set(ts_s, ts_ns);
}

static int cndm_phc_adjfine(struct ptp_clock_info *ptp, long scaled_ppm)
{
	struct cndm_dev *cdev = container_of(ptp, struct cndm_dev, ptp_clock_info);
	struct cndm_cmd_ptp cmd;
	struct cndm_cmd_ptp rsp;
	int ret = 0;

	bool neg = false;
	u64 nom_per_fns, adj;

	dev_dbg(cdev->dev, "%s: scaled_ppm: %ld", __func__, scaled_ppm);

	if (scaled_ppm < 0) {
		neg = true;
		scaled_ppm = -scaled_ppm;
	}

	nom_per_fns = cdev->ptp_nom_period;

	if (nom_per_fns == 0)
		nom_per_fns = 0x4ULL << 32;

	adj = div_u64(((nom_per_fns >> 16) * scaled_ppm) + 500000, 1000000);

	if (neg)
		adj = nom_per_fns - adj;
	else
		adj = nom_per_fns + adj;

	cmd.opcode = CNDM_CMD_OP_PTP;
	cmd.flags = CNDM_CMD_PTP_FLG_SET_PERIOD;
	cmd.period = adj;

	dev_dbg(cdev->dev, "%s adj: 0x%llx", __func__, adj);

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret) {
		dev_err(cdev->dev, "Failed to execute command");
		return ret;
	}

	if (rsp.status) {
		dev_err(cdev->dev, "Failed to adjust PHC");
		return rsp.status;
	}

	return 0;
}

static int cndm_phc_gettime(struct ptp_clock_info *ptp, struct timespec64 *ts)
{
	struct cndm_dev *cdev = container_of(ptp, struct cndm_dev, ptp_clock_info);

	ioread32(cdev->hw_addr + 0x0320);
	ts->tv_nsec = ioread32(cdev->hw_addr + 0x0324);
	ts->tv_sec = ioread32(cdev->hw_addr + 0x0328);
	ts->tv_sec |= (u64) ioread32(cdev->hw_addr + 0x032C) << 32;

	dev_dbg(cdev->dev, "%s: Get time: %lld.%09ld", __func__, ts->tv_sec, ts->tv_nsec);

	return 0;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 0, 0)
static int cndm_phc_gettimex(struct ptp_clock_info *ptp, struct timespec64 *ts, struct ptp_system_timestamp *sts)
{
	struct cndm_dev *cdev = container_of(ptp, struct cndm_dev, ptp_clock_info);

	ptp_read_system_prets(sts);
	ioread32(cdev->hw_addr + 0x0320);
	ptp_read_system_postts(sts);
	ts->tv_nsec = ioread32(cdev->hw_addr + 0x0324);
	ts->tv_sec = ioread32(cdev->hw_addr + 0x0328);
	ts->tv_sec |= (u64) ioread32(cdev->hw_addr + 0x032C) << 32;

	dev_dbg(cdev->dev, "%s: Get time: %lld.%09ld", __func__, ts->tv_sec, ts->tv_nsec);

	return 0;
}
#endif

static int cndm_phc_settime(struct ptp_clock_info *ptp, const struct timespec64 *ts)
{
	struct cndm_dev *cdev = container_of(ptp, struct cndm_dev, ptp_clock_info);
	struct cndm_cmd_ptp cmd;
	struct cndm_cmd_ptp rsp;
	int ret = 0;

	cmd.opcode = CNDM_CMD_OP_PTP;
	cmd.flags = CNDM_CMD_PTP_FLG_SET_TOD;
	cmd.tod_ns = ts->tv_nsec;
	cmd.tod_sec = ts->tv_sec;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret) {
		dev_err(cdev->dev, "Failed to execute command");
		return ret;
	}

	if (rsp.status) {
		dev_err(cdev->dev, "Failed to adjust PHC");
		return rsp.status;
	}

	return 0;
}

static int cndm_phc_adjtime(struct ptp_clock_info *ptp, s64 delta)
{
	struct cndm_dev *cdev = container_of(ptp, struct cndm_dev, ptp_clock_info);
	struct timespec64 ts;
	struct cndm_cmd_ptp cmd;
	struct cndm_cmd_ptp rsp;
	int ret = 0;

	dev_dbg(cdev->dev, "%s: delta: %lld", __func__, delta);

	if (delta > 536000000 || delta < -536000000) {
		// for a large delta, perform a non-precision step
		cndm_phc_gettime(ptp, &ts);
		ts = timespec64_add(ts, ns_to_timespec64(delta));
		return cndm_phc_settime(ptp, &ts);
	} else {
		// for a small delta, perform a precision atomic offset
		cmd.opcode = CNDM_CMD_OP_PTP;
		cmd.flags = CNDM_CMD_PTP_FLG_OFFSET_TOD;
		cmd.tod_ns = delta & 0xffffffff;

		ret = cndm_exec_cmd(cdev, &cmd, &rsp);
		if (ret) {
			dev_err(cdev->dev, "Failed to execute command");
			return ret;
		}

		if (rsp.status) {
			dev_err(cdev->dev, "Failed to adjust PHC");
			return rsp.status;
		}
	}

	return 0;
}

static int cndm_phc_set_from_system_clock(struct ptp_clock_info *ptp)
{
	struct timespec64 ts;

#ifdef ktime_get_clocktai_ts64
	ktime_get_clocktai_ts64(&ts);
#else
	ts = ktime_to_timespec64(ktime_get_clocktai());
#endif

	return cndm_phc_settime(ptp, &ts);
}

int cndm_register_phc(struct cndm_dev *cdev)
{
	struct cndm_cmd_ptp cmd;
	struct cndm_cmd_ptp rsp;
	int ret = 0;

	if (cdev->ptp_clock) {
		dev_warn(cdev->dev, "PTP clock already registered");
		return 0;
	}

	cmd.opcode = CNDM_CMD_OP_PTP;
	cmd.flags = 0x00000000;
	cmd.nom_period = 0;

	ret = cndm_exec_cmd(cdev, &cmd, &rsp);
	if (ret) {
		dev_err(cdev->dev, "Failed to execute command");
		return ret;
	}

	if (rsp.status || rsp.nom_period == 0) {
		dev_info(cdev->dev, "PTP clock not present");
		return rsp.status;
	}

	cdev->ptp_nom_period = rsp.nom_period;

	dev_info(cdev->dev, "PHC nominal period: %lld.%08lld ns (raw 0x%llx)", cdev->ptp_nom_period >> 32,
		((cdev->ptp_nom_period & 0xffffffff) * 1000000000) / 0x100000000ll, cdev->ptp_nom_period);

	cdev->ptp_clock_info.owner = THIS_MODULE;
	snprintf(cdev->ptp_clock_info.name, sizeof(cdev->ptp_clock_info.name), "%s_phc", cdev->name);
	cdev->ptp_clock_info.max_adj = 1000000000;
	cdev->ptp_clock_info.n_alarm = 0;
	cdev->ptp_clock_info.n_ext_ts = 0;
	cdev->ptp_clock_info.n_per_out = 0;
	cdev->ptp_clock_info.n_pins = 0;
	cdev->ptp_clock_info.pps = 0;
	cdev->ptp_clock_info.adjfine = cndm_phc_adjfine;
	cdev->ptp_clock_info.adjtime = cndm_phc_adjtime;
	cdev->ptp_clock_info.gettime64 = cndm_phc_gettime;
	cdev->ptp_clock_info.gettimex64 = cndm_phc_gettimex;
	cdev->ptp_clock_info.settime64 = cndm_phc_settime;

	cdev->ptp_clock = ptp_clock_register(&cdev->ptp_clock_info, cdev->dev);

	if (IS_ERR(cdev->ptp_clock)) {
		dev_err(cdev->dev, "failed to register PHC");
		ret = PTR_ERR(cdev->ptp_clock);
		cdev->ptp_clock = NULL;
		return ret;
	}

	dev_info(cdev->dev, "registered PHC (index %d)", ptp_clock_index(cdev->ptp_clock));

	cndm_phc_set_from_system_clock(&cdev->ptp_clock_info);

	return 0;
}

void cndm_unregister_phc(struct cndm_dev *cdev)
{
	if (cdev->ptp_clock) {
		ptp_clock_unregister(cdev->ptp_clock);
		cdev->ptp_clock = NULL;
		dev_info(cdev->dev, "unregistered PHC");
	}
}
