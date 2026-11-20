# Native helpers used by the shell. `make install` puts them in ~/.local/bin.
#   update_theme  - wallpaper-derived palette generator (writes palette.json, applies GTK/Hyprland colours)
#   prgnotifier   - volume / brightness / mic notifier (talks to SwayNC)
# update_theme needs stb_image.h (Arch: `pacman -S stb`).
PREFIX ?= $(HOME)/.local
CC     ?= cc
CFLAGS ?= -O2 -Wall -Wextra

TOOLS := update_theme prgnotifier

all: $(addprefix build/,$(TOOLS))

build/%: scripts/%.c
	@mkdir -p build
	$(CC) $(CFLAGS) -o $@ $< -lm

install: all
	@for t in $(TOOLS); do install -Dm755 build/$$t $(PREFIX)/bin/$$t; done

clean:
	rm -rf build

.PHONY: all install clean
