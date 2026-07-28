# Makefile for Termux-iOS jb-chroot helper
# Target: iPhone 8 (iOS 15.0+ arm64) | TrollStore | palera1n (/var/jb)

CC ?= cc
CFLAGS ?= -Wall -Wextra -O2 -g
LDFLAGS ?=

TARGET = jb-chroot
SRCS = jb-chroot.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $(TARGET) $(LDFLAGS)

%.o: %.c jb-chroot.h
	$(CC) $(CFLAGS) -c $< -o $@

# Cross-compile target for iOS arm64 (when iOS toolchain / Xcode is present)
ios: CC = xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0
ios: CFLAGS += -DTERMIOS_IOS_BUILD
ios: clean all
	@echo "Built $(TARGET) for iOS arm64."

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean ios
