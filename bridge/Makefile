CC ?= cc

.DEFAULT_GOAL := all
.SUFFIXES:
.DELETE_ON_ERROR:

CFLAGS ?= -O2 -g -Wall -Wextra -Wno-unused-parameter -std=c11
CFLAGS += -D_DEFAULT_SOURCE -Ivendor
CFLAGS += $(shell pkg-config --cflags sdl2 SDL2_ttf SDL2_image)
LDLIBS := $(shell pkg-config --libs sdl2 SDL2_ttf SDL2_image)

OBJECTS := main.o vendor/cJSON.o
DEPENDENCIES := $(OBJECTS:.o=.d)

.PHONY: all clean

all: rubyos_bridge

rubyos_bridge: $(OBJECTS)
	$(CC) $(CFLAGS) -o $@ $(OBJECTS) $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

-include $(DEPENDENCIES)

clean:
	rm -f $(OBJECTS) $(DEPENDENCIES) rubyos_bridge
