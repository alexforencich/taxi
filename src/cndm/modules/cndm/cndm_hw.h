/* SPDX-License-Identifier: GPL */
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#ifndef CNDM_HW_H
#define CNDM_HW_H

#include <linux/types.h>

#define CNDM_CMD_OP_NOP 0x0000

#define CNDM_CMD_OP_CFG        0x0100

#define CNDM_CMD_OP_ACCESS_REG 0x0180
#define CNDM_CMD_OP_PTP        0x0190
#define CNDM_CMD_OP_HWID       0x01A0
#define CNDM_CMD_OP_HWMON      0x01B0
#define CNDM_CMD_OP_PLL        0x01C0

#define CNDM_CMD_OP_CREATE_EQ  0x0200
#define CNDM_CMD_OP_MODIFY_EQ  0x0201
#define CNDM_CMD_OP_QUERY_EQ   0x0202
#define CNDM_CMD_OP_DESTROY_EQ 0x0203

#define CNDM_CMD_OP_CREATE_CQ  0x0210
#define CNDM_CMD_OP_MODIFY_CQ  0x0211
#define CNDM_CMD_OP_QUERY_CQ   0x0212
#define CNDM_CMD_OP_DESTROY_CQ 0x0213

#define CNDM_CMD_OP_CREATE_SQ  0x0220
#define CNDM_CMD_OP_MODIFY_SQ  0x0221
#define CNDM_CMD_OP_QUERY_SQ   0x0222
#define CNDM_CMD_OP_DESTROY_SQ 0x0223

#define CNDM_CMD_OP_CREATE_RQ  0x0230
#define CNDM_CMD_OP_MODIFY_RQ  0x0231
#define CNDM_CMD_OP_QUERY_RQ   0x0232
#define CNDM_CMD_OP_DESTROY_RQ 0x0233

#define CNDM_CMD_OP_CREATE_QP  0x0240
#define CNDM_CMD_OP_MODIFY_QP  0x0241
#define CNDM_CMD_OP_QUERY_QP   0x0242
#define CNDM_CMD_OP_DESTROY_QP 0x0243

#define CNDM_CMD_BRD_OP_NOP 0x0000

#define CNDM_CMD_BRD_OP_FLASH_RD  0x0100
#define CNDM_CMD_BRD_OP_FLASH_WR  0x0101
#define CNDM_CMD_BRD_OP_FLASH_CMD 0x0108

#define CNDM_CMD_BRD_OP_EEPROM_RD 0x0200
#define CNDM_CMD_BRD_OP_EEPROM_WR 0x0201

#define CNDM_CMD_BRD_OP_OPTIC_RD 0x0300
#define CNDM_CMD_BRD_OP_OPTIC_WR 0x0301

#define CNDM_CMD_BRD_OP_HWID_SN_RD  0x0400
#define CNDM_CMD_BRD_OP_HWID_VPD_RD 0x0410
#define CNDM_CMD_BRD_OP_HWID_MAC_RD 0x0480

#define CNDM_CMD_BRD_OP_PLL_STATUS_RD   0x0500
#define CNDM_CMD_BRD_OP_PLL_TUNE_RAW_RD 0x0502
#define CNDM_CMD_BRD_OP_PLL_TUNE_RAW_WR 0x0503
#define CNDM_CMD_BRD_OP_PLL_TUNE_PPT_RD 0x0504
#define CNDM_CMD_BRD_OP_PLL_TUNE_PPT_WR 0x0505

#define CNDM_CMD_BRD_OP_I2C_RD 0x8100
#define CNDM_CMD_BRD_OP_I2C_WR 0x8101

struct cndm_cmd_cfg {
	__le16 rsvd;
	union {
		__le16 opcode;
		__le16 status;
	};
	__le32 flags;
	struct {
		__le16 cfg_page;
		__le16 cfg_page_max;
	};
	__le32 cmd_ver;

	__le32 fw_ver;
	__u8 port_count;
	__u8 rsvd2[3];
	__le32 rsvd3[2];

	union {
		struct {
			// Page 0: FW ID
			__le32 fpga_id;
			__le32 fw_id;
			__le32 fw_ver;
			__le32 board_id;
			__le32 board_ver;
			__le32 build_date;
			__le32 git_hash;
			__le32 release_info;
		} p0;
		struct {
			// Page 1: HW config
			__le16 port_count;
			__le16 rsvd1;
			__le32 rsvd2[3];
			__le16 sys_clk_per_ns_den;
			__le16 sys_clk_per_ns_num;
			__le16 ptp_clk_per_ns_den;
			__le16 ptp_clk_per_ns_num;
			__le32 rsvd3[2];
		} p1;
		struct {
			// Page 2: Resources
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
			__le32 rsvd[4];
		} p2;
	};
};

#define CNDM_CMD_REG_FLG_WRITE  0x00000001
#define CNDM_CMD_REG_FLG_RAW    0x00000100

struct cndm_cmd_reg {
	__le16 rsvd;
	union {
		__le16 opcode;
		__le16 status;
	};
	__le32 flags;
	__le32 rsvd1[5];
	__le32 reg_addr;
	__le64 write_val;
	__le64 read_val;
	__le32 rsvd2[4];
};

#define CNDM_CMD_PTP_FLG_SET_TOD    0x00000001
#define CNDM_CMD_PTP_FLG_OFFSET_TOD 0x00000002
#define CNDM_CMD_PTP_FLG_SET_REL    0x00000004
#define CNDM_CMD_PTP_FLG_OFFSET_REL 0x00000008
#define CNDM_CMD_PTP_FLG_OFFSET_FNS 0x00000010
#define CNDM_CMD_PTP_FLG_SET_PERIOD 0x00000080

struct cndm_cmd_ptp {
	__le16 rsvd;
	union {
		__le16 opcode;
		__le16 status;
	};
	__le32 flags;
	__le32 fns;
	__le32 tod_ns;

	__le64 tod_sec;
	__le64 rel_ns;

	__le64 ptm;
	__le64 nom_period;

	__le64 period;
	__le32 rsvd2[2];
};

struct cndm_cmd_hwid {
	__le16 rsvd;
	union {
		__le16 opcode;
		__le16 status;
	};
	__le32 flags;
	__le16 index;
	union {
		__le16 brd_opcode;
		__le16 brd_status;
	};
	__le32 brd_flags;
	__u8 page;
	__u8 bank;
	__u8 dev_addr_offset;
	__u8 rsvd2;
	__le32 addr;
	__le32 len;
	__le32 rsvd3;
	__le32 data[8];
};

struct cndm_cmd_queue {
	__le16 rsvd;
	union {
		__le16 opcode;
		__le16 status;
	};
	__le32 flags;
	__le32 port;
	__le32 qn;

	__le32 qn2;
	__le32 pd;
	__le32 size;
	__le32 dboffs;

	__le64 ptr1;
	__le64 ptr2;

	__le32 prod;
	__le32 cons;
	__le32 dw14;
	__le32 dw15;
};

struct cndm_desc {
	__le16 rsvd0;
	union {
		struct {
			__le16 csum_cmd;
		} tx;
		struct {
			__le16 rsvd0;
		} rx;
	};

	__le32 len;
	__le64 addr;
};

struct cndm_cpl {
	__u8 rsvd[4];
	__le32 len;
	__le32 ts_ns;
	__le16 ts_fns;
	__u8 ts_s;
	__u8 phase;
};

struct cndm_event {
	__le16 rsvd0;
	__le16 type;
	__le32 source;
	__le32 rsvd1;
	__le32 phase;
};

#endif
