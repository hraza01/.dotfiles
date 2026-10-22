/* SPDX-License-Identifier: MIT */
#pragma once
#include <stdbool.h>
#include <stdint.h>
struct capture_frame {
    void *data;
    uint32_t width, height, stride, format;
    bool y_invert;
};
struct capture;
struct capture *capture_open(const char *output_name);
/* -1: disconnected/error, 0: no new frame, 1: frame available */
int capture_poll(struct capture *capture, struct capture_frame *frame);
void capture_release(struct capture *capture);
void capture_close(struct capture *capture);
