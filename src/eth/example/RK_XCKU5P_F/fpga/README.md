# Taxi Example Design for RK-XCKU5P-F

## Introduction

This example design targets the RK-XCKU5P-F FPGA board.

The design places looped-back MACs on the QSFP28 cage.

*  USB UART
  *  XFCP (3 Mbaud)
*  RJ-45 Ethernet port with Realtek RTL8211F PHY
  *  Looped-back MAC via RGMII
* QSFP28
  * Looped-back 10GBASE-R or 25GBASE-R MAC via GTY transceiver

## Board details

* FPGA: xcku5p-ffvb676-2-e
* USB UART: FTDI FT2232
* 1000BASE-T PHY: Realtek RTL8211F via RGMII
* 25GBASE-R PHY: Soft PCS with GTY transceiver

## Licensing

* Toolchain
  * Vivado Standard (enterprise license not required)
* IP
  * No licensed vendor IP or 3rd party IP

## How to build

Run `make` in the appropriate `fpga*` subdirectory to build the bitstream.  Ensure that the Xilinx Vivado toolchain components are in PATH.

## How to test

Run `make program` to program the board with Vivado.

To test the looped-back MAC, it is recommended to use a network tester like the Viavi T-BERD 5800 that supports basic layer 2 tests with a loopback.  Do not connect the looped-back MAC to a network as the reflected packets may cause problems.
