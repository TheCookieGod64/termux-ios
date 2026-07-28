/*
 * jb-chroot.h
 * Termux-iOS Jailbreak Chroot Helper for iPhone 8 / palera1n (/var/jb)
 *
 * Designed for TrollStore & palera1n rootless jailbreak on iOS 15/16.
 * Provides a native chroot("/var/jb") execution environment with fallback
 * to rootless prefix execution when not running as UID 0.
 *
 * Configured exclusively for 'pacman' package manager (no apt).
 */

#ifndef JB_CHROOT_H
#define JB_CHROOT_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>

#define TERMUX_IOS_VERSION "0.118.0-ios-pacman"
#define DEFAULT_JB_ROOT "/var/jb"
#define DEFAULT_SHELL_CHROOT "/bin/bash"
#define DEFAULT_SHELL_ROOTLESS "/var/jb/usr/bin/bash"
#define DEFAULT_HOME_CHROOT "/home/mobile"
#define DEFAULT_HOME_ROOTLESS "/var/jb/var/mobile"

#define PATH_CHROOT "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
#define PATH_ROOTLESS "/var/jb/usr/local/sbin:/var/jb/usr/local/bin:/var/jb/usr/sbin:/var/jb/usr/bin:/var/jb/sbin:/var/jb/bin:/usr/bin:/bin"

/* Function prototypes */
int check_jb_path_exists(const char *path);
void print_banner(void);
void print_usage(const char *progname);
void print_status(void);
int execute_in_chroot(const char *jb_root, int argc, char *const argv[]);

#endif /* JB_CHROOT_H */
