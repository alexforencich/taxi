// SPDX-License-Identifier: GPL
/*

Copyright (c) 2025 FPGA Ninja, LLC

Authors:
- Alex Forencich

*/

#include "cndm.h"

#include <linux/ethtool.h>

static void cndm_get_drvinfo(struct net_device *ndev,
	struct ethtool_drvinfo *drvinfo)
{
	struct cndm_priv *priv = netdev_priv(ndev);
	struct cndm_dev *cdev = priv->cdev;

	strscpy(drvinfo->driver, KBUILD_MODNAME, sizeof(drvinfo->driver));
	strscpy(drvinfo->version, DRIVER_VERSION, sizeof(drvinfo->version));
	snprintf(drvinfo->fw_version, sizeof(drvinfo->fw_version), "TODO"); // TODO
	strscpy(drvinfo->bus_info, dev_name(cdev->dev), sizeof(drvinfo->bus_info));
}

const struct ethtool_ops cndm_ethtool_ops = {
	.get_drvinfo = cndm_get_drvinfo,
};
