# Makefile for JITAllower native C helper
# Target: iPhone 8 (iOS 15.0+ arm64) | TrollStore | palera1n (/var/jb)

CC ?= cc
CFLAGS ?= -Wall -Wextra -O2 -g
LDFLAGS ?=

TARGET = jit-helper
SRCS = jit-helper.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $(TARGET) $(LDFLAGS)

%.o: %.c jit-helper.h
	$(CC) $(CFLAGS) -c $< -o $@

ios: CC = xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=15.0
ios: CFLAGS += -DTERMIOS_IOS_BUILD
ios: clean all
	@echo "Built $(TARGET) for iOS arm64."

clean:
	rm -f $(OBJS) $(TARGET)

.PHONY: all clean ios
