# Corundum for KCU105

## Introduction

This design targets the Xilinx KCU105 FPGA board.

*  USB UART
    *  XFCP (921600 baud)
*  RJ-45 Ethernet port with Marvell 88E1111 PHY
    *  Looped-back MAC via SGMII via Xilinx PCS/PMA core and LVDS IOSERDES
*  SFP+ cages
    *  1000BASE-X via Xilinx PCS/PMA core and GTH transceiver
    *  10GBASE-R MAC via GTH transceiver

## Board details

*  FPGA: xcku040-ffva1156-2-e
*  USB UART: Silicon Labs CP2105 SCI
*  1000BASE-T PHY: Marvell 88E1111 via SGMII
*  10GBASE-R PHY: Soft PCS with GTH transceiver

## Licensing

*  Toolchain
    *  Vivado Enterprise (requires license)
*  IP
    *  No licensed vendor IP or 3rd party IP

## How to build

Run `make` in the appropriate `fpga*` subdirectory to build the bitstream.  Ensure that the Xilinx Vivado toolchain components are in PATH.

On the host system, run `make` in `modules/cndm` to build the driver.  Ensure that the headers for the running kernel are installed, otherwise the driver cannot be compiled.

## How to test

Run `make program` to program the board with Vivado.  Then, reboot the machine to re-enumerate the PCIe bus.  Finally, load the driver on the host system with `insmod cndm.ko`.  Check `dmesg` for output from driver initialization.  Run `cndm_ddcmd.sh =p` to enable all debug messages.
