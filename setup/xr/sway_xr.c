/* Native Wayland viewer: wlroots capture + XRLinuxDriver OpenTrack UDP.
 * Local experimental Sway integration.
 * SPDX-License-Identifier: MIT
 */
#include <SDL2/SDL.h>
#include <GL/gl.h>
#include <arpa/inet.h>
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>
#include "sway_capture.h"

static volatile sig_atomic_t zoom_in, zoom_out;
struct screen {
    char name[128];
    struct capture *capture;
    GLuint texture;
    int width, height;
    bool y_invert;
    unsigned frames;
};
static const char *sides[] = {"left", "center", "right"};
static void zoom_signal(int sig) {
    if (sig == SIGUSR1) zoom_in = 1;
    if (sig == SIGUSR2) zoom_out = 1;
}

static double setting(const char *name, double fallback, double low, double high) {
    const char *value = getenv(name);
    if (!value) return fallback;
    char *end;
    double number = strtod(value, &end);
    if (end == value || *end || !isfinite(number) || number < low || number > high) {
        fprintf(stderr, "Invalid %s\n", name);
        exit(1);
    }
    return number;
}

static void screen_close(struct screen *s) {
    capture_close(s->capture);
    glDeleteTextures(1, &s->texture);
    memset(s, 0, sizeof(*s));
}

static bool screen_open(struct screen *s, const char *name, bool test) {
    struct capture *capture = test ? NULL : capture_open(name);
    if (!test && !capture) return false;
    snprintf(s->name, sizeof(s->name), "%s", name);
    s->capture = capture;
    glGenTextures(1, &s->texture);
    glBindTexture(GL_TEXTURE_2D, s->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return true;
}

static int control_open(const char *path) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(path) >= sizeof(address.sun_path)) {
        fprintf(stderr, "XR control socket path is too long.\n");
        return -1;
    }
    snprintf(address.sun_path, sizeof(address.sun_path), "%s", path);
    int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    unlink(path);
    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0 || chmod(path, 0600) < 0) {
        perror("Opening XR control socket");
        close(fd);
        return -1;
    }
    return fd;
}

static void control_poll(int fd, struct screen screens[3]) {
    if (fd < 0) return;
    /* Bound command work per frame so control messages cannot starve tracking. */
    for (int request = 0; request < 4; request++) {
        char message[256], command[16], side[16], name[128], extra;
        struct sockaddr_un peer = {0};
        socklen_t peer_length = sizeof(peer);
        ssize_t length = recvfrom(fd, message, sizeof(message) - 1, 0,
                                 (struct sockaddr *)&peer, &peer_length);
        if (length < 0) return;
        message[length] = '\0';
        int fields = sscanf(message, "%15s %15s %127s %c", command, side, name, &extra);
        const char *reply = "ERROR invalid command";
        if (fields == 1 && strcmp(command, "ping") == 0) {
            reply = "OK";
        } else if (fields >= 2) {
            int slot = strcmp(side, "left") == 0 ? 0 : strcmp(side, "right") == 0 ? 2 : -1;
            if (slot >= 0 && fields == 3 && strcmp(command, "add") == 0) {
                if (screens[slot].name[0]) {
                    reply = strcmp(screens[slot].name, name) == 0 ? "OK" : "ERROR side already occupied";
                } else if (screen_open(&screens[slot], name, false)) {
                    printf("Added %s screen: %s\n", side, name);
                    reply = "OK";
                } else reply = "ERROR cannot capture output";
            } else if (slot >= 0 && fields == 2 && strcmp(command, "remove") == 0) {
                screen_close(&screens[slot]);
                printf("Removed %s screen; capture and texture released.\n", side);
                reply = "OK";
            }
        }
        sendto(fd, reply, strlen(reply), MSG_NOSIGNAL, (struct sockaddr *)&peer, peer_length);
    }
}

int main(int argc, char **argv) {
    bool test = argc == 2 && strcmp(argv[1], "--test-pattern") == 0;
    struct screen screens[3] = {0};
    const char *names[3] = {0}, *legacy[3] = {0}, *control_path = NULL;
    int legacy_count = 0;
    if (test) {
        names[1] = "test grid";
    } else {
        for (int i = 1; i < argc; i += 2) {
            if (i + 1 >= argc) goto usage;
            if (strcmp(argv[i], "--control") == 0) control_path = argv[i + 1];
            else if (strcmp(argv[i], "--output") == 0 && legacy_count < 3)
                legacy[legacy_count++] = argv[i + 1];
            else if (strcmp(argv[i], "--left") == 0) names[0] = argv[i + 1];
            else if (strcmp(argv[i], "--center") == 0) names[1] = argv[i + 1];
            else if (strcmp(argv[i], "--right") == 0) names[2] = argv[i + 1];
            else goto usage;
        }
        if (legacy_count) {
            if (names[0] || names[1] || names[2]) goto usage;
            for (int i = 0; i < legacy_count; i++)
                names[legacy_count == 1 ? 1 : legacy_count == 2 ? i * 2 : i] = legacy[i];
        }
    }
    if ((!names[0] && !names[1] && !names[2]) || (control_path && !names[1])) {
usage:
        fprintf(stderr, "Usage: %s --center NAME [--left NAME] [--right NAME] [--control PATH] | --output NAME | --test-pattern\n", argv[0]);
        return 1;
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    int udp = socket(AF_INET, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons(4243),
                               .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    if (udp < 0 || bind(udp, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("Binding tracking receiver to 127.0.0.1:4243");
        return 1;
    }

    SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");
    SDL_SetHint("SDL_VIDEO_WAYLAND_WMCLASS", "sway-xr");
    SDL_SetHint("SDL_APP_ID", "sway-xr");
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        fprintf(stderr, "SDL: %s\n", SDL_GetError());
        return 1;
    }
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_Window *window = SDL_CreateWindow("Sway XR — VITURE", 0, 0, 1920, 1080,
        SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    SDL_GLContext context = window ? SDL_GL_CreateContext(window) : NULL;
    if (!context) {
        fprintf(stderr, "OpenGL: %s\n", SDL_GetError());
        return 1;
    }
    SDL_GL_SetSwapInterval(1);
    SDL_ShowCursor(SDL_DISABLE);
    printf("Renderer: %s; window backend: %s\n", glGetString(GL_RENDERER), SDL_GetCurrentVideoDriver());
    signal(SIGUSR1, zoom_signal);
    signal(SIGUSR2, zoom_signal);

    for (int i = 0; i < 3; i++)
        if (names[i] && !screen_open(&screens[i], names[i], test)) return 1;
    int control = control_path ? control_open(control_path) : -1;
    if (control_path && control < 0) return 1;
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    if (test) {
        unsigned char pixels[320 * 180 * 3];
        for (int y = 0; y < 180; y++) for (int x = 0; x < 320; x++) {
            int i = (y * 320 + x) * 3;
            bool grid = x % 20 < 2 || y % 20 < 2;
            pixels[i] = grid ? 255 : 25;
            pixels[i+1] = grid ? 255 : 60;
            pixels[i+2] = grid ? 255 : 100;
        }
        screens[1].width = 320; screens[1].height = 180;
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, 320, 180, 0, GL_RGB, GL_UNSIGNED_BYTE, pixels);
    }

    bool running = true, received = false;
    double pose[6] = {0};
    Uint64 last_pose = SDL_GetTicks64(), last_report = last_pose;
    unsigned renders = 0, packets = 0;
    float scale = 1.0f;
    const double diagonal_m = setting("SWAY_XR_DIAGONAL_INCHES", 24, 8, 100) * 0.0254;
    const double screen_distance = setting("SWAY_XR_DISTANCE_M", 0.9, 0.25, 5);
    const double screen_gap = setting("SWAY_XR_GAP_DEGREES", 1, 0, 10);
    printf("Virtual screen diagonal: %.1f inches; viewing distance: %.2f m (3DoF size approximation)\n",
           diagonal_m / 0.0254, screen_distance);
    printf("Screen gap: %.1f degrees\n", screen_gap);
    const double rad = 3.141592653589793 / 180.0;
    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) running = false;
            if (event.type == SDL_KEYDOWN) {
                if (event.key.keysym.sym == SDLK_ESCAPE) running = false;
                if (event.key.keysym.sym == SDLK_EQUALS) zoom_in = 1;
                if (event.key.keysym.sym == SDLK_MINUS) zoom_out = 1;
            }
        }
        if (zoom_in) { scale = fminf(scale * 1.1f, 4.0f); zoom_in = 0; }
        if (zoom_out) { scale = fmaxf(scale / 1.1f, 0.2f); zoom_out = 0; }

        control_poll(control, screens);

        unsigned char packet[256];
        ssize_t length;
        while ((length = recv(udp, packet, sizeof(packet), 0)) >= 0) {
            if (length != 52 && length != 48) continue;
            double latest[6];
            memcpy(latest, packet, sizeof(latest));
            if (!isfinite(latest[3]) || !isfinite(latest[4]) || !isfinite(latest[5])) continue;
            memcpy(pose, latest, sizeof(pose));
            last_pose = SDL_GetTicks64();
            packets++;
            if (!received) puts("Live head tracking received.");
            received = true;
        }
        if (errno != EAGAIN && errno != EWOULDBLOCK) {
            perror("Tracking receive");
            return 1;
        }
        if (SDL_GetTicks64() - last_pose > (received ? 3000 : 10000)) {
            fprintf(stderr, "Tracking stopped. Check xr-driver and the glasses connection.\n");
            return 1;
        }

        for (int i = 0; !test && i < 3; i++) {
            struct screen *s = &screens[i];
            if (!s->capture) continue;
            struct capture_frame frame;
            int status = capture_poll(s->capture, &frame);
            if (status < 0) return 1;
            if (status > 0) {
                glBindTexture(GL_TEXTURE_2D, s->texture);
                GLenum format = (frame.format == WL_SHM_FORMAT_XRGB8888 || frame.format == WL_SHM_FORMAT_ARGB8888) ? GL_BGRA : GL_RGBA;
                glPixelStorei(GL_UNPACK_ROW_LENGTH, frame.stride / 4);
                if ((int)frame.width != s->width || (int)frame.height != s->height) {
                    s->width = frame.width; s->height = frame.height;
                    /* Keep a four-channel texture to match the capture buffer;
                     * blending is disabled, so XRGB's unused alpha is harmless. */
                    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, s->width, s->height, 0, format, GL_UNSIGNED_BYTE, frame.data);
                    printf("Captured %s: %dx%d\n", s->name, s->width, s->height);
                } else {
                    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, s->width, s->height, format, GL_UNSIGNED_BYTE, frame.data);
                }
                glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
                s->y_invert = frame.y_invert;
                s->frames++;
                capture_release(s->capture);
            }
        }

        int width, height;
        SDL_GL_GetDrawableSize(window, &width, &height);
        if (width <= 0 || height <= 0) { SDL_Delay(10); continue; }
        double aspect = (double)width / height;
        /* Pro 2: 44.5 degree diagonal FOV, per XRLinuxDriver's device profile. */
        double tan_half_vertical = tan(44.5 * rad / 2) / sqrt(1 + (16.0 / 9) * (16.0 / 9));
        glViewport(0, 0, width, height);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        double top = 0.1 * tan_half_vertical;
        glFrustum(-top * aspect, top * aspect, -top, top, 0.1, 100);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        /* Inverse NWU ZYX orientation, transformed into OpenGL EUS axes. */
        glRotated(pose[5], 0, 0, 1);
        glRotated(pose[4], 1, 0, 0);
        glRotated(-pose[3], 0, 1, 0);
        double half_heights[3], half_widths[3], half_angles[3];
        for (int i = 0; i < 3; i++) {
            double ratio = screens[i].height > 0 ? (double)screens[i].width / screens[i].height : 16.0 / 9;
            half_heights[i] = diagonal_m * scale / (2 * sqrt(1 + ratio * ratio));
            half_widths[i] = half_heights[i] * ratio;
            half_angles[i] = atan(half_widths[i] / screen_distance) / rad;
        }
        for (int i = 0; received && i < 3; i++) {
            struct screen *s = &screens[i];
            if (s->width <= 0 || s->height <= 0) continue;
            double half_w = half_widths[i];
            double half_h = half_heights[i];
            double angle = 0;
            /* Fixed slots keep the center anchored when a side is toggled. */
            if (i != 1)
                angle = (i == 0 ? 1 : -1) * (half_angles[1] + half_angles[i] + screen_gap);
            glPushMatrix();
            glRotated(angle, 0, 1, 0);
            glColor3f(1, 1, 1);
            glBindTexture(GL_TEXTURE_2D, s->texture);
            glEnable(GL_TEXTURE_2D);
            float vtop = s->y_invert ? 1 : 0, vbottom = s->y_invert ? 0 : 1;
            glBegin(GL_QUADS);
            glTexCoord2f(0, vbottom); glVertex3d(-half_w, -half_h, -screen_distance);
            glTexCoord2f(1, vbottom); glVertex3d( half_w, -half_h, -screen_distance);
            glTexCoord2f(1, vtop); glVertex3d( half_w,  half_h, -screen_distance);
            glTexCoord2f(0, vtop); glVertex3d(-half_w,  half_h, -screen_distance);
            glEnd();
            glPopMatrix();
        }
        SDL_GL_SwapWindow(window);
        renders++;
        Uint64 now = SDL_GetTicks64();
        if (now - last_report >= 10000) {
            double seconds = (now - last_report) / 1000.0;
            printf("Rates: %.1f render fps, %.1f tracking Hz", renders / seconds, packets / seconds);
            for (int i = 0; i < 3; i++) {
                if (!screens[i].name[0]) continue;
                printf(", %s/%s %.1f capture fps", sides[i], screens[i].name, screens[i].frames / seconds);
                screens[i].frames = 0;
            }
            puts("");
            renders = packets = 0;
            last_report = now;
        }
        SDL_Delay(1); /* avoid a busy loop if the compositor disables vsync */
    }
    close(udp);
    if (control >= 0) { close(control); unlink(control_path); }
    for (int i = 0; i < 3; i++) screen_close(&screens[i]);
    SDL_GL_DeleteContext(context);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
