# Native helper build for Termux-iOS.
# `ios` must be run on macOS with Xcode's iPhoneOS SDK.

CC ?= cc
CFLAGS ?= -Wall -Wextra -O2
LDFLAGS ?=
TARGET := jb-chroot

.PHONY: all clean ios

all: $(TARGET)

$(TARGET): jb-chroot.c jb-chroot.h
	$(CC) $(CFLAGS) jb-chroot.c -o $@ $(LDFLAGS)

ios: clean
	xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0 \
		$(CFLAGS) -DTERMUX_IOS_DEVICE_BUILD jb-chroot.c -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET) *.o
