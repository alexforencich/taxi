// SPDX-License-Identifier: GPL
// Copyright (c) 2025 FPGA Ninja

#include "cndm_proto.h"
#include <linux/module.h>
#include <linux/delay.h>

MODULE_DESCRIPTION("Corundum-proto device driver");
MODULE_AUTHOR("FPGA Ninja");
MODULE_LICENSE("GPL");
MODULE_VERSION(DRIVER_VERSION);

static int cndm_proto_pci_probe(struct pci_dev *pdev, const struct pci_device_id *ent)
{
	struct device *dev = &pdev->dev;
	struct cndm_proto_dev *cdev;
	int ret = 0;
	int k;

	dev_info(dev, DRIVER_NAME " PCI probe");
	dev_info(dev, "Corundum-proto device driver");
	dev_info(dev, "Version " DRIVER_VERSION);
	dev_info(dev, "Copyright (c) 2025 FPGA Ninja");
	dev_info(dev, "https://fpga.ninja/");

	pcie_print_link_status(pdev);

	cdev = devm_kzalloc(dev, sizeof(struct cndm_proto_dev), GFP_KERNEL);
	if (!cdev)
		return -ENOMEM;

	cdev->pdev = pdev;
	cdev->dev = dev;
	pci_set_drvdata(pdev, cdev);

	ret = pci_enable_device_mem(pdev);
	if (ret) {
		dev_err(dev, "Failed to enable device");
		goto fail_enable_device;
	}

	pci_set_master(pdev);

	ret = pci_request_regions(pdev, DRIVER_NAME);
	if (ret) {
		dev_err(dev, "Failed to reserve regions");
		goto fail_regions;
	}

	cdev->bar_len = pci_resource_len(pdev, 0);

	dev_info(dev, "BAR size: %llu", cdev->bar_len);
	cdev->bar = pci_ioremap_bar(pdev, 0);
	if (!cdev->bar) {
		ret = -ENOMEM;
		dev_err(dev, "Failed to map BAR 0");
		goto fail_map_bars;
	}

	if (ioread32(cdev->bar + 0x0000) == 0xffffffff) {
		ret = -EIO;
		dev_err(dev, "Device needs to be reset");
		goto fail_map_bars;
	}

	ret = pci_alloc_irq_vectors(pdev, 1, 32, PCI_IRQ_MSI | PCI_IRQ_MSIX);
	if (ret < 0) {
		dev_err(dev, "Failed to allocate IRQs");
		goto fail_map_bars;
	}

	cdev->port_count = ioread32(cdev->bar + 0x0100);
	cdev->port_offset = ioread32(cdev->bar + 0x0104);
	cdev->port_stride = ioread32(cdev->bar + 0x0108);

	dev_info(dev, "Port count: %d", cdev->port_count);
	dev_info(dev, "Port offset: 0x%x", cdev->port_offset);
	dev_info(dev, "Port stride: 0x%x", cdev->port_stride);

	for (k = 0; k < cdev->port_count; k++) {
		struct net_device *ndev;

		ndev = cndm_proto_create_netdev(cdev, k, cdev->bar + cdev->port_offset + (cdev->port_stride*k));
		if (IS_ERR_OR_NULL(ndev)) {
			ret = PTR_ERR(ndev);
			goto fail_netdev;
		}

		ret = pci_request_irq(pdev, k, cndm_proto_irq, 0, ndev, DRIVER_NAME);
		if (ret < 0) {
			dev_err(dev, "Failed to request IRQ");
			cndm_proto_destroy_netdev(ndev);
			goto fail_netdev;
		}

		cdev->ndev[k] = ndev;
	}

	return 0;

fail_netdev:
	for (k = 0; k < 32; k++) {
		if (cdev->ndev[k]) {
			pci_free_irq(pdev, k, cdev->ndev[k]);
			cndm_proto_destroy_netdev(cdev->ndev[k]);
			cdev->ndev[k] = NULL;
		}
	}
	pci_free_irq_vectors(pdev);
fail_map_bars:
	if (cdev->bar)
		pci_iounmap(pdev, cdev->bar);
	pci_release_regions(pdev);
fail_regions:
	pci_clear_master(pdev);
	pci_disable_device(pdev);
fail_enable_device:
	return ret;
}

static void cndm_proto_pci_remove(struct pci_dev *pdev)
{
	struct device *dev = &pdev->dev;
	struct cndm_proto_dev *cdev = pci_get_drvdata(pdev);
	int k;

	dev_info(dev, DRIVER_NAME " PCI remove");

	for (k = 0; k < 32; k++) {
		if (cdev->ndev[k]) {
			pci_free_irq(pdev, k, cdev->ndev[k]);
			cndm_proto_destroy_netdev(cdev->ndev[k]);
			cdev->ndev[k] = NULL;
		}
	}

	pci_free_irq_vectors(pdev);
	if (cdev->bar)
		pci_iounmap(pdev, cdev->bar);
	pci_release_regions(pdev);
	pci_clear_master(pdev);
	pci_disable_device(pdev);
}

static const struct pci_device_id cndm_proto_pci_id_table[] = {
	{PCI_DEVICE(0x1234, 0xC070)},
	{0}
};

static struct pci_driver cndm_proto_driver = {
	.name = DRIVER_NAME,
	.id_table = cndm_proto_pci_id_table,
	.probe = cndm_proto_pci_probe,
	.remove = cndm_proto_pci_remove
};

static int __init cndm_proto_init(void)
{
	return pci_register_driver(&cndm_proto_driver);
}

static void __exit cndm_proto_exit(void)
{
	pci_unregister_driver(&cndm_proto_driver);
}

module_init(cndm_proto_init);
module_exit(cndm_proto_exit);
