# DPDK PMD for Corundum

## Introduction

This is an out-of-tree DPDK PMD for corundum-micro and corundum-lite.  It has feature parity with the main Linux kernel driver, at least in terms of the core datapath.  Some features may be limited by the architecture and API of DPDK.  This PMD has been tested with DPDK 26.03, but will likely work with other versions as well.

## How to build

- Download DPDK in a separate directory
- Create a symbolic link from `taxi/src/cndm/dpdk/cndm` to `dpdk/drivers/net/cndm`
- Edit `dpdk/drivers/net/meson.build` to add `cndm` to the drivers list
- In the root of the DPDK repo, run meson
  - Default: `meson setup build`
  - Build all examples: `meson setup -Dexamples=all build`
  - Forced reconfigure: `meson setup --wipe build`
  - Check the meson summary - some system packages may need to be installed
- In the root of the DPDK repo, run `ninja -C build`

## How to test

- It may be necessary to enable huge pages on the kernel command line
  - For example, `default_hugepagesz=1G hugepagesz=1G hugepages=16`
  - This must be done in the bootloader configuration (grub, systemd-boot, etc.)
- Run `sudo ./usertools/dpdk-devbind.py -s` to determine NIC PCI ID and NUMA node
- Run `sudo ./usertools/dpdk-devbind.py -b vfio-pci <pci id>` to bind the vfio-pci driver to the NIC
  - It may be necessary to add `--noimmu-mode` if the IOMMU is disabled
- Run `numactl -H` to determine which CPU cores are on the same NUMA node as the NIC
- Run `dpdk-testpmd`
  - `sudo ./build/app/dpdk-testpmd -l <cpulist> -- -i --portlist=<portlist>`
  - cpulist specifies the CPU cores to use (e.g. `-l 0-3`)
  - portlist specifies the ports to use (e.g. `--portlist=0,2`)
- At the `dpdk-testpmd` command line:
  - Run `start tx_first` to start a simple forwarding test, with the first port in the list acting as the transmitter
  - Run `stop` to stop the test and print statistics
  - Run `show port info 0` to display port configuration information
  - Run `show port 0 eeprom` to dump the board EEPROM
  - Run `show port 0 module_eeprom` to dump the module EEPROM
  - Use the `help` command to get more information about the testpmd commands
  - Run `quit` to quit
