# Taxi Example Design for XEM8320

## Introduction

This example design targets the Opal Kelley XEM8320 FPGA board.

The design places looped-back MACs on SFP+ cages.

*  SFP+ cages
    *  Looped-back 1000BASE-X via Xilinx PCS/PMA core and GTH transceiver
    *  Looped-back 10GBASE-R MAC via GTH transceiver

## Board details

*  FPGA: xcau25p-ffvb676-2-e
*  10GBASE-R PHY: Soft PCS with GTH transceiver

## Licensing

*  Toolchain
    *  Vivado Enterprise (requires license)
*  IP
    *  No licensed vendor IP or 3rd party IP

## How to build

Run `make` in the appropriate `fpga*` subdirectory to build the bitstream.  Ensure that the Xilinx Vivado toolchain components are in PATH.

## How to test

Run `make program` to program the board with Vivado.

To test the looped-back MAC, it is recommended to use a network tester like the Viavi T-BERD 5800 that supports basic layer 2 tests with a loopback.  Do not connect the looped-back MAC to a network as the reflected packets may cause problems.
