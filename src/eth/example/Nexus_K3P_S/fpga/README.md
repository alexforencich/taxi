# Taxi Example Design for Cisco Nexus K35-S/K3P-S (ExaNIC X10/X25)

## Introduction

This example design targets the Cisco Nexus K35-S/K3P-S (ExaNIC X10/X25) FPGA board.

The design places looped-back MACs on the SFP+ cages.

* SFP+ cages
  * Looped-back 10GBASE-R or 25GBASE-R MAC via GTH or GTY transceiver

## Board details

* FPGA:
  * K35-S/X10: xcku035-fbva676-2-e
  * K3P-S/X25: xcku3p-ffvb676-2-e
* 25GBASE-R PHY: Soft PCS with GTH or GTY transceiver

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
