/*
 * jb-chroot.c
 *
 * Native /var/jb launcher for Termux-iOS.  A real chroot is attempted only
 * when the caller is UID 0; every other execution uses the rootless prefix
 * environment and never pretends that chroot succeeded.
 *
 * The package-manager policy is intentionally one-way: pacman/pkg are
 * allowed and apt/apt-get are blocked by name before exec.
 */
#include "jb-chroot.h"

#include <limits.h>
#include <fcntl.h>
#include <sys/wait.h>

static const char *command_basename(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash == NULL ? path : slash + 1;
}

static int is_blocked_package_command(const char *path) {
    const char *name = command_basename(path);
    return strcmp(name, "apt") == 0 || strcmp(name, "apt-get") == 0 ||
           strcmp(name, "apt-cache") == 0 || strcmp(name, "apt-mark") == 0 ||
           strcmp(name, "dpkg") == 0 || strcmp(name, "dpkg-deb") == 0;
}

int check_jb_path_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static int executable_exists(const char *path) {
    return access(path, X_OK) == 0;
}

void print_banner(void) {
    printf("===============================================================\n");
    printf("  Termux-iOS /var/jb launcher (v%s)\n", TERMUX_IOS_VERSION);
    printf("  Target: iPhone 8 | iOS 15/16 | palera1n rootless\n");
    printf("  Package manager: PACMAN only (apt/dpkg blocked)\n");
    printf("===============================================================\n");
}

void print_usage(const char *progname) {
    printf("Usage: %s [options] [command [args...]]\n\n", progname);
    printf("Options:\n");
    printf("  -h, --help      Show this help\n");
    printf("  -v, --version   Show version\n");
    printf("  -s, --status    Show /var/jb and pacman status\n");
    printf("\nExamples:\n");
    printf("  %s                  # default shell\n", progname);
    printf("  %s pacman -Syu      # upgrade with pacman\n", progname);
    printf("  %s pkg install git  # Termux-style wrapper\n", progname);
}

void print_status(void) {
    print_banner();
    struct stat st;
    char pacman_path[PATH_MAX];
    char pkg_path[PATH_MAX];
    char apt_path[PATH_MAX];
    snprintf(pacman_path, sizeof(pacman_path), "%s/usr/bin/pacman", DEFAULT_JB_ROOT);
    snprintf(pkg_path, sizeof(pkg_path), "%s/usr/bin/pkg", DEFAULT_JB_ROOT);
    snprintf(apt_path, sizeof(apt_path), "%s/usr/bin/apt", DEFAULT_JB_ROOT);

    uid_t uid = getuid();
    gid_t gid = getgid();
    printf("/var/jb                 : %s\n", check_jb_path_exists(DEFAULT_JB_ROOT) ? "FOUND" : "NOT FOUND");
    printf("execution mode          : %s (uid=%u gid=%u)\n",
           (uid == 0 || geteuid() == 0) ? "root/chroot eligible" : "rootless prefix",
           (unsigned)uid, (unsigned)gid);
    printf("pacman                  : %s\n", stat(pacman_path, &st) == 0 ? "present" : "not found");
    printf("pkg wrapper             : %s\n", executable_exists(pkg_path) ? "present" : "not found");
    printf("apt policy              : %s\n", stat(apt_path, &st) == 0 ? "guard installed" : "blocked by launcher policy");
    printf("rootless PREFIX         : %s/usr\n", DEFAULT_JB_ROOT);
    printf("rootless PATH           : %s\n", PATH_ROOTLESS);
}

static void set_common_environment(void) {
    setenv("TERMUX_VERSION", TERMUX_IOS_VERSION, 1);
    setenv("TERMUX_PKG_MANAGER", "pacman", 1);
    setenv("TERM", "xterm-256color", 1);
    setenv("COLORTERM", "truecolor", 1);
    setenv("LANG", "en_US.UTF-8", 1);
    setenv("LC_CTYPE", "en_US.UTF-8", 1);
}

static char *resolve_rootless_command(const char *command, char *storage, size_t storage_size) {
    if (command[0] == '/') {
        if (strncmp(command, DEFAULT_JB_ROOT "/", strlen(DEFAULT_JB_ROOT) + 1U) == 0) {
            return (char *)command;
        }
        /* Map a conventional /bin or /usr path into the rootless prefix when
           that executable exists; otherwise preserve the caller's absolute path. */
        if (snprintf(storage, storage_size, "%s%s", DEFAULT_JB_ROOT, command) < (int)storage_size &&
            access(storage, X_OK) == 0) {
            return storage;
        }
        return (char *)command;
    }
    if (snprintf(storage, storage_size, "%s/usr/bin/%s", DEFAULT_JB_ROOT, command) >= (int)storage_size) {
        return NULL;
    }
    if (access(storage, X_OK) == 0) {
        return storage;
    }
    /* execvp can resolve commands in the rootless PATH when no direct file exists. */
    return (char *)command;
}

int execute_in_chroot(const char *jb_root, int argc, char *const argv[]) {
    int use_chroot = 0;
    const int caller_is_root = (getuid() == 0 || geteuid() == 0);

    if (caller_is_root && chroot(jb_root) == 0) {
        use_chroot = 1;
        if (chdir("/") != 0) {
            perror("[jb-chroot] chdir after chroot");
            return 1;
        }
    } else if (caller_is_root) {
        fprintf(stderr, "[jb-chroot] chroot(%s) failed: %s; using prefix mode\n", jb_root, strerror(errno));
    }

    set_common_environment();

    if (use_chroot) {
        setenv("TERMUX_IOS_CHROOT", "1", 1);
        setenv("PREFIX", "/usr", 1);
        setenv("PATH", PATH_CHROOT, 1);
        setenv("HOME", DEFAULT_HOME_CHROOT, 1);
        (void)chdir(DEFAULT_HOME_CHROOT);
    } else {
        setenv("TERMUX_IOS_CHROOT", "0", 1);
        setenv("PREFIX", DEFAULT_JB_ROOT "/usr", 1);
        setenv("PATH", PATH_ROOTLESS, 1);
        setenv("HOME", DEFAULT_HOME_ROOTLESS, 1);
        (void)chdir(DEFAULT_HOME_ROOTLESS);
    }

    char *command = NULL;
    char rootless_command[PATH_MAX];
    char **child_argv = NULL;

    if (argc <= 1) {
        command = use_chroot ? (char *)DEFAULT_SHELL_CHROOT : (char *)DEFAULT_SHELL_ROOTLESS;
        child_argv = calloc(2, sizeof(*child_argv));
        if (child_argv == NULL) return 126;
        child_argv[0] = (char *)"bash";
        child_argv[1] = NULL;
    } else {
        command = use_chroot ? argv[1] : resolve_rootless_command(argv[1], rootless_command, sizeof(rootless_command));
        if (command == NULL) {
            fprintf(stderr, "[jb-chroot] command path is too long\n");
            return 126;
        }
        child_argv = (char **)&argv[1];
    }

    if (is_blocked_package_command(command)) {
        fprintf(stderr, "[Termux-iOS] %s is disabled. This installation uses pacman/pkg exclusively.\n",
                command_basename(command));
        fprintf(stderr, "[Termux-iOS] Examples: pkg update, pkg install <package>, pkg upgrade\n");
        return 126;
    }

    execvp(command, child_argv);
    fprintf(stderr, "[jb-chroot] unable to execute %s: %s\n", command, strerror(errno));
    if (argc <= 1) free(child_argv);
    return 127;
}

int main(int argc, char *argv[]) {
    if (argc >= 2) {
        if (strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
            print_banner();
            print_usage(argv[0]);
            return 0;
        }
        if (strcmp(argv[1], "-v") == 0 || strcmp(argv[1], "--version") == 0) {
            printf("Termux-iOS jb-chroot %s\n", TERMUX_IOS_VERSION);
            return 0;
        }
        if (strcmp(argv[1], "-s") == 0 || strcmp(argv[1], "--status") == 0) {
            print_status();
            return 0;
        }
    }
    return execute_in_chroot(DEFAULT_JB_ROOT, argc, argv);
}
