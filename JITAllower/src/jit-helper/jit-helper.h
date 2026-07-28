/*
 * jit-helper.h
 * JITAllower Real Native C Helper for iPhone 8 (iOS 15/16) | TrollStore | palera1n
 *
 * Uses real Darwin kernel syscalls (sysctl, ptrace, csops) to enumerate
 * active running processes and inject CS_DEBUGGED kernel flag for JIT.
 */

#ifndef JIT_HELPER_H
#define JIT_HELPER_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <signal.h>

#define JITALLOWER_VERSION "1.1.0-ios-native"

/* Function prototypes */
void print_banner(void);
void print_usage(const char *progname);
int enable_jit_for_pid(pid_t pid);
int enable_jit_all_user_apps(void);
int list_running_apps(void);

#endif /* JIT_HELPER_H */
