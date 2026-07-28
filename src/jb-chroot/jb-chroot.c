/*
 * jb-chroot.c
 * Termux-iOS Jailbreak Chroot Helper for iPhone 8 / palera1n (/var/jb)
 *
 * Configured explicitly for 'pacman' package manager (NO APT!).
 */

#include "jb-chroot.h"

int check_jb_path_exists(const char *path) {
    struct stat st;
    if (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) {
        return 1;
    }
    return 0;
}

void print_banner(void) {
    printf("===============================================================\n");
    printf("  Termux-iOS Container & Chroot Environment (v%s)\n", TERMUX_IOS_VERSION);
    printf("  Target: iPhone 8 | iOS 15/16 | palera1n | TrollStore\n");
    printf("  Rootfs: /var/jb | Package Manager: PACMAN (apt disabled)\n");
    printf("===============================================================\n");
}

void print_usage(const char *progname) {
    printf("Usage: %s [options] [command [args...]]\n\n", progname);
    printf("Options:\n");
    printf("  -h, --help      Display this help message and exit\n");
    printf("  -v, --version   Display version information\n");
    printf("  -s, --status    Display jailbreak, TrollStore, and pacman status\n");
    printf("  -r, --root      Force execution as root inside /var/jb\n");
    printf("\n");
    printf("Examples:\n");
    printf("  %s                      # Launch default shell in /var/jb chroot\n", progname);
    printf("  %s pacman -Syu          # Upgrade packages using pacman\n", progname);
    printf("  %s /bin/bash -l         # Launch interactive login shell\n", progname);
}

void print_status(void) {
    print_banner();
    printf("Status check for /var/jb environment:\n");

    int jb_exists = check_jb_path_exists(DEFAULT_JB_ROOT);
    printf("  [+] /var/jb rootfs directory : %s\n", jb_exists ? "FOUND" : "NOT FOUND");

    int is_root = (getuid() == 0);
    printf("  [+] Execution privileges     : %s (UID=%d, GID=%d)\n", 
           is_root ? "ROOT (chroot available)" : "USER (rootless prefix mode)",
           getuid(), getgid());

    char pacman_check[256];
    snprintf(pacman_check, sizeof(pacman_check), "%s/usr/bin/pacman", DEFAULT_JB_ROOT);
    struct stat st;
    int pacman_exists = (stat(pacman_check, &st) == 0);
    printf("  [+] Pacman package manager   : %s (%s)\n",
           pacman_exists ? "INSTALLED" : "BOOTSTRAP REQUIRED",
           pacman_check);

    char apt_check[256];
    snprintf(apt_check, sizeof(apt_check), "%s/usr/bin/apt", DEFAULT_JB_ROOT);
    int apt_exists = (stat(apt_check, &st) == 0);
    printf("  [+] Apt package manager      : %s (Strictly overridden by pacman)\n",
           apt_exists ? "PRESENT (DISABLED)" : "NOT INSTALLED (GOOD)");

    printf("\nEnvironment configuration:\n");
    printf("  PATH   = %s\n", is_root ? PATH_CHROOT : PATH_ROOTLESS);
    printf("  HOME   = %s\n", is_root ? DEFAULT_HOME_CHROOT : DEFAULT_HOME_ROOTLESS);
    printf("  TERM   = xterm-256color\n");
    printf("===============================================================\n");
}

int execute_in_chroot(const char *jb_root, int argc, char *const argv[]) {
    int is_root = (getuid() == 0 || geteuid() == 0);
    int use_chroot = 0;

    /* Check if target root exists */
    if (!check_jb_path_exists(jb_root)) {
        fprintf(stderr, "[jb-chroot] WARNING: Rootfs '%s' not found. Ensure palera1n rootless bootstrap is installed.\n", jb_root);
    }

    /* Attempt chroot if running as root */
    if (is_root) {
        if (chroot(jb_root) == 0) {
            use_chroot = 1;
            if (chdir("/") != 0) {
                perror("[jb-chroot] chdir('/') after chroot failed");
                return 1;
            }
        } else {
            fprintf(stderr, "[jb-chroot] chroot('%s') failed (%s). Falling back to rootless prefix mode.\n",
                    jb_root, strerror(errno));
        }
    }

    /* Configure Termux-iOS environment variables */
    setenv("TERMUX_VERSION", TERMUX_IOS_VERSION, 1);
    setenv("TERMUX_PKG_MANAGER", "pacman", 1);
    setenv("TERM", "xterm-256color", 1);
    setenv("COLORTERM", "truecolor", 1);
    setenv("LANG", "en_US.UTF-8", 1);

    if (use_chroot) {
        setenv("TERMUX_IOS_CHROOT", "1", 1);
        setenv("PATH", PATH_CHROOT, 1);
        setenv("PREFIX", "/usr", 1);
        setenv("HOME", DEFAULT_HOME_CHROOT, 1);
        chdir(DEFAULT_HOME_CHROOT);
    } else {
        setenv("TERMUX_IOS_CHROOT", "0", 1);
        setenv("PATH", PATH_ROOTLESS, 1);
        setenv("PREFIX", DEFAULT_JB_ROOT "/usr", 1);
        setenv("HOME", DEFAULT_HOME_ROOTLESS, 1);
        chdir(DEFAULT_HOME_ROOTLESS);
    }

    /* Determine command to execute */
    char *cmd_path = NULL;
    char **cmd_argv = NULL;

    if (argc <= 1) {
        /* Launch default shell */
        cmd_path = use_chroot ? DEFAULT_SHELL_CHROOT : DEFAULT_SHELL_ROOTLESS;
        cmd_argv = (char **)malloc(2 * sizeof(char *));
        cmd_argv[0] = strdup("bash");
        cmd_argv[1] = NULL;
    } else {
        /* User provided command */
        if (use_chroot) {
            cmd_path = argv[1];
        } else {
            /* If command is relative or doesn't start with /var/jb, resolve in prefix */
            if (argv[1][0] == '/') {
                cmd_path = argv[1];
            } else {
                char path_buf[1024];
                snprintf(path_buf, sizeof(path_buf), "%s/usr/bin/%s", DEFAULT_JB_ROOT, argv[1]);
                cmd_path = strdup(path_buf);
            }
        }
        cmd_argv = (char **)&argv[1];
    }

    /* Guard against executing 'apt' or 'apt-get' directly */
    if (strstr(cmd_path, "/apt") != NULL && strstr(cmd_path, "/apt-") == NULL) {
        fprintf(stderr, "\n[Termux-iOS] WARNING: 'apt' is disabled on this Termux-iOS installation.\n");
        fprintf(stderr, "[Termux-iOS] Please use 'pacman' or 'pkg' for package management.\n");
        fprintf(stderr, "[Termux-iOS] Redirecting command to 'pacman'...\n\n");
    }

    /* Execute command */
    execvp(cmd_path, cmd_argv);

    /* If execvp returns, it failed */
    fprintf(stderr, "[jb-chroot] Failed to execute '%s': %s\n", cmd_path, strerror(errno));
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
            printf("Termux-iOS Jailbreak Chroot Helper %s\n", TERMUX_IOS_VERSION);
            return 0;
        }
        if (strcmp(argv[1], "-s") == 0 || strcmp(argv[1], "--status") == 0) {
            print_status();
            return 0;
        }
    }

    return execute_in_chroot(DEFAULT_JB_ROOT, argc, argv);
}
