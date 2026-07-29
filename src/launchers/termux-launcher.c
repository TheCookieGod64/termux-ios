/*
 * termux-launcher.c
 *
 * A real arm64 Mach-O fallback executable used only when Xcode is unavailable.
 * It is deliberately the CFBundleExecutable; a shell script must never occupy
 * that slot because TrollStore requires a valid Mach-O main binary.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int launch(const char *path, char *const argv[]) {
    execv(path, argv);
    return errno;
}

int main(int argc, char **argv) {
    const char *helper = "/var/jb/usr/bin/jb-chroot";
    char **child_argv = calloc((size_t)argc + 1U, sizeof(*child_argv));
    if (child_argv == NULL) {
        return 126;
    }

    child_argv[0] = (char *)helper;
    for (int i = 1; i < argc; ++i) {
        child_argv[i] = argv[i];
    }
    child_argv[argc] = NULL;

    int error = launch(helper, child_argv);
    fprintf(stderr, "termux-launcher: unable to execute %s: %s\n", helper, strerror(error));
    free(child_argv);
    return 127;
}
