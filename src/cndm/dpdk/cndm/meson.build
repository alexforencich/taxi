# SPDX-License-Identifier: BSD-3-Clause
# Copyright 2026 FPGA Ninja, LLC

if not is_linux
    build = false
    reason = 'only supported on Linux'
    subdir_done()
endif

sources = files(
    'cndm_main.c',
    'cndm_cmd.c',
    'cndm_ethdev.c',
    'cndm_cq.c',
    'cndm_sq.c',
    'cndm_rq.c',
)
