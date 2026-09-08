# Builds the two X11 helper daemons and installs everything where the live
# config expects to find it. Paths here must stay in step with the absolute
# paths baked into picom.conf, the systemd unit and the .desktop file.

CC      ?= cc
CFLAGS  ?= -O2 -Wall
LDLIBS  := -lX11

PREFIX      := $(HOME)/.local
BINDIR      := $(PREFIX)/bin
SRCDIR      := $(PREFIX)/src
PICOMDIR    := $(HOME)/.config/picom
SHADERDIR   := $(PICOMDIR)/picom-shaders
UNITDIR     := $(HOME)/.config/systemd/user
AUTOSTARTDIR:= $(HOME)/.config/autostart
CONKYBIN    := $(HOME)/.config/conky/gruvbox-dark/bin

BINARIES := bin/picom-menu-roll-tag bin/picom-slide-fire
SCRIPTS  := bin/picom-slide-mark bin/picom-slide-switch bin/wallpaper-sheet \
            bin/lock-screen bin/skippy-expose

.PHONY: all clean install install-bin install-config install-units

all: $(BINARIES)

bin/%: src/%.c
	$(CC) $(CFLAGS) -o $@ $< $(LDLIBS)

clean:
	rm -f $(BINARIES)

install: install-bin install-config install-units

install-bin: all
	install -d $(BINDIR) $(SRCDIR)
	install -m 755 $(BINARIES) $(SCRIPTS) $(BINDIR)
	# The systemd unit's Documentation= and picom.conf's comments point at
	# ~/.local/src, so the sources ship alongside the binaries.
	install -m 644 src/*.c $(SRCDIR)
	install -d $(CONKYBIN)
	install -m 755 conky/focusdim.py $(CONKYBIN)

install-config:
	install -d $(PICOMDIR)
	install -m 644 picom.conf $(PICOMDIR)
	install -m 755 config/generate-monitor-defines.sh $(PICOMDIR)
	# monitors.conf is generated output; only seed it if absent, otherwise
	# an install would clobber the current monitor layout.
	[ -e $(PICOMDIR)/monitors.conf ] || install -m 644 config/monitors.conf $(PICOMDIR)
	# lock.glsl is a local modification of the upstream picom-shaders clone
	# -- see README. Overwrites the checkout's working-tree copy.
	@test -d $(SHADERDIR) || { echo "missing $(SHADERDIR): git clone https://github.com/ikz87/picom-shaders/ $(SHADERDIR)"; exit 1; }
	install -m 644 shaders/lock.glsl $(SHADERDIR)/3DCamera/lock.glsl

install-units:
	install -d $(UNITDIR) $(AUTOSTARTDIR)
	install -m 644 systemd/picom-menu-roll-tag.service $(UNITDIR)
	install -m 644 autostart/wallpaper-sheet.desktop $(AUTOSTARTDIR)
	systemctl --user daemon-reload
	systemctl --user enable --now picom-menu-roll-tag.service
