/* Event-driven wlroots screen capture. SPDX-License-Identifier: MIT */
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "sway_capture.h"
#include "wlr-screencopy-client.h"
#include <errno.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-client.h>

struct output {
    struct wl_output *proxy;
    uint32_t id;
    char name[128];
    int transform;
};
struct capture {
    struct wl_display *display;
    struct wl_registry *registry;
    struct wl_shm *shm;
    struct zwlr_screencopy_manager_v1 *manager;
    struct zwlr_screencopy_frame_v1 *pending;
    struct wl_buffer *buffer;
    struct capture_frame current;
    bool ready, failed;
    size_t map_size;
    struct output outputs[32], *selected;
    unsigned output_count;
};

static void output_geometry(void *data, struct wl_output *output, int32_t x, int32_t y,
        int32_t pw, int32_t ph, int32_t subpixel, const char *make, const char *model, int32_t transform) {
    ((struct output *)data)->transform = transform;
}
static void output_mode(void *data, struct wl_output *output, uint32_t flags, int32_t w, int32_t h, int32_t hz) {}
static void output_done(void *data, struct wl_output *output) {}
static void output_scale(void *data, struct wl_output *output, int32_t scale) {}
static void output_name(void *data, struct wl_output *output, const char *name) {
    struct output *out = data;
    snprintf(out->name, sizeof(out->name), "%s", name);
}
static void output_description(void *data, struct wl_output *output, const char *description) {}
static const struct wl_output_listener output_listener = {
    .geometry = output_geometry, .mode = output_mode, .done = output_done,
    .scale = output_scale, .name = output_name, .description = output_description,
};

static void global(void *data, struct wl_registry *registry, uint32_t id, const char *interface, uint32_t version) {
    struct capture *c = data;
    if (strcmp(interface, wl_shm_interface.name) == 0) {
        c->shm = wl_registry_bind(registry, id, &wl_shm_interface, 1);
    } else if (strcmp(interface, zwlr_screencopy_manager_v1_interface.name) == 0) {
        /* Version 1 guarantees wl_shm and does not require DMA-BUF negotiation. */
        c->manager = wl_registry_bind(registry, id, &zwlr_screencopy_manager_v1_interface, 1);
    } else if (strcmp(interface, wl_output_interface.name) == 0 && version >= 4) {
        unsigned slot = 0;
        while (slot < c->output_count && c->outputs[slot].proxy) slot++;
        if (slot == 32) return;
        if (slot == c->output_count) c->output_count++;
        struct output *out = &c->outputs[slot];
        memset(out, 0, sizeof(*out));
        out->id = id;
        out->proxy = wl_registry_bind(registry, id, &wl_output_interface, 4);
        wl_output_add_listener(out->proxy, &output_listener, out);
    }
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t id) {
    struct capture *c = data;
    if (c->selected && c->selected->id == id) c->failed = true;
    for (unsigned i = 0; i < c->output_count; i++) {
        if (c->outputs[i].proxy && c->outputs[i].id == id) {
            wl_output_release(c->outputs[i].proxy);
            c->outputs[i].proxy = NULL;
        }
    }
}
static const struct wl_registry_listener registry_listener = {.global = global, .global_remove = global_remove};

static void frame_buffer(void *data, struct zwlr_screencopy_frame_v1 *frame,
                         uint32_t format, uint32_t width, uint32_t height, uint32_t stride) {
    struct capture *c = data;
    if (!width || !height || width > INT_MAX / 4 || stride < width * 4 || stride % 4 ||
        (size_t)stride * height > INT_MAX ||
        (format != WL_SHM_FORMAT_XRGB8888 && format != WL_SHM_FORMAT_ARGB8888 &&
         format != WL_SHM_FORMAT_XBGR8888 && format != WL_SHM_FORMAT_ABGR8888)) {
        fprintf(stderr, "Unsupported capture buffer: format=%u %ux%u stride=%u\n", format, width, height, stride);
        c->failed = true;
        return;
    }
    if (!c->buffer || c->current.width != width || c->current.height != height ||
        c->current.stride != stride || c->current.format != format) {
        if (c->buffer) { wl_buffer_destroy(c->buffer); c->buffer = NULL; }
        if (c->current.data) { munmap(c->current.data, c->map_size); c->current.data = NULL; }
        c->map_size = (size_t)stride * height;
        int fd = memfd_create("sway-xr-capture", MFD_CLOEXEC);
        if (fd < 0 || ftruncate(fd, (off_t)c->map_size) < 0) {
            perror("Capture shared memory");
            if (fd >= 0) close(fd);
            c->failed = true;
            return;
        }
        c->current.data = mmap(NULL, c->map_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (c->current.data == MAP_FAILED) {
            c->current.data = NULL;
            close(fd);
            c->failed = true;
            return;
        }
        struct wl_shm_pool *pool = wl_shm_create_pool(c->shm, fd, (int)c->map_size);
        c->buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, format);
        wl_shm_pool_destroy(pool);
        close(fd);
        c->current.width = width; c->current.height = height;
        c->current.stride = stride; c->current.format = format;
    }
    zwlr_screencopy_frame_v1_copy(frame, c->buffer);
}
static void frame_flags(void *data, struct zwlr_screencopy_frame_v1 *frame, uint32_t flags) {
    struct capture *c = data;
    c->current.y_invert = (flags & ZWLR_SCREENCOPY_FRAME_V1_FLAGS_Y_INVERT) != 0;
}
static void frame_ready(void *data, struct zwlr_screencopy_frame_v1 *frame, uint32_t hi, uint32_t lo, uint32_t ns) {
    struct capture *c = data;
    c->ready = true;
    zwlr_screencopy_frame_v1_destroy(frame);
    c->pending = NULL;
}
static void frame_failed(void *data, struct zwlr_screencopy_frame_v1 *frame) {
    struct capture *c = data;
    fprintf(stderr, "Screen capture of %s failed (source disconnected, disabled, or session locked).\n", c->selected->name);
    c->failed = true;
    zwlr_screencopy_frame_v1_destroy(frame);
    c->pending = NULL;
}
static const struct zwlr_screencopy_frame_v1_listener frame_listener = {
    .buffer = frame_buffer, .flags = frame_flags, .ready = frame_ready, .failed = frame_failed,
};

void capture_release(struct capture *c) {
    c->ready = false;
    c->current.y_invert = false;
    c->pending = zwlr_screencopy_manager_v1_capture_output(c->manager, 1, c->selected->proxy);
    zwlr_screencopy_frame_v1_add_listener(c->pending, &frame_listener, c);
    if (wl_display_flush(c->display) < 0 && errno != EAGAIN) c->failed = true;
}

struct capture *capture_open(const char *name) {
    struct capture *c = calloc(1, sizeof(*c));
    if (!c) return NULL;
    c->display = wl_display_connect(NULL);
    if (!c->display) { fprintf(stderr, "Cannot connect to Sway for capture.\n"); goto fail; }
    c->registry = wl_display_get_registry(c->display);
    wl_registry_add_listener(c->registry, &registry_listener, c);
    if (wl_display_roundtrip(c->display) < 0 || wl_display_roundtrip(c->display) < 0) goto fail;
    for (unsigned i = 0; i < c->output_count; i++) if (strcmp(c->outputs[i].name, name) == 0) c->selected = &c->outputs[i];
    if (!c->selected || !c->shm || !c->manager) {
        fprintf(stderr, "Output %s or wlroots screencopy protocol unavailable.\n", name);
        goto fail;
    }
    if (c->selected->transform != WL_OUTPUT_TRANSFORM_NORMAL) {
        fprintf(stderr, "This experimental capture currently requires an unrotated source output.\n");
        goto fail;
    }
    printf("Capturing Sway output %s directly.\n", name);
    capture_release(c);
    return c;
fail:
    capture_close(c);
    return NULL;
}

int capture_poll(struct capture *c, struct capture_frame *frame) {
    while (wl_display_prepare_read(c->display) != 0) {
        if (wl_display_dispatch_pending(c->display) < 0) return -1;
    }
    int flushed = wl_display_flush(c->display);
    if (flushed < 0 && errno != EAGAIN) { wl_display_cancel_read(c->display); return -1; }
    struct pollfd fd = {.fd = wl_display_get_fd(c->display), .events = POLLIN};
    int result = poll(&fd, 1, 0);
    if (result > 0 && (fd.revents & POLLIN)) {
        if (wl_display_read_events(c->display) < 0 || wl_display_dispatch_pending(c->display) < 0) return -1;
    } else {
        wl_display_cancel_read(c->display);
        if ((result < 0 && errno != EINTR) || (fd.revents & (POLLERR | POLLHUP | POLLNVAL))) return -1;
    }
    if (c->failed) return -1;
    if (!c->ready) return 0;
    *frame = c->current;
    return 1;
}

void capture_close(struct capture *c) {
    if (!c) return;
    if (c->pending) zwlr_screencopy_frame_v1_destroy(c->pending);
    if (c->buffer) wl_buffer_destroy(c->buffer);
    if (c->current.data) munmap(c->current.data, c->map_size);
    for (unsigned i = 0; i < c->output_count; i++)
        if (c->outputs[i].proxy) wl_output_release(c->outputs[i].proxy);
    if (c->manager) zwlr_screencopy_manager_v1_destroy(c->manager);
    if (c->shm) wl_shm_destroy(c->shm);
    if (c->registry) wl_registry_destroy(c->registry);
    if (c->display) wl_display_disconnect(c->display);
    free(c);
}
