/*
 * picom-slide-fire -- switch workspace and nudge the sticky widgets from ONE
 * X connection, so picom sees both in the same frame.
 *
 * Build:
 *     gcc -O2 -Wall -o ~/.local/bin/picom-slide-fire \
 *         ~/.local/src/picom-slide-fire.c -lX11
 *
 * Used by ~/.local/bin/picom-slide-switch, which falls back to
 * `xdotool set_desktop` + a loop of `xprop` if this binary is missing.
 *
 * WHY IT EXISTS. The conky cards are sticky, so they are animated by a change
 * to _NET_WM_WINDOW_OPACITY rather than by being unmapped (see the sticky
 * rules in ~/.config/picom/picom.conf). Doing that with one `xprop` per card
 * plus `xdotool set_desktop` for the switch is six processes racing each
 * other to the X server. Measured over eight switches with picom's debug log:
 * the cards started 0-30 ms after the windows did, and in three of the eight
 * one card started 25-52 ms after its siblings. At 60 Hz that is one to three
 * frames, and early in the slide the sheet covers ~350 px per frame -- so the
 * stack visibly broke formation, which is the whole thing the animation is
 * trying to preserve.
 *
 * One connection fixes it: the requests are queued back to back and the
 * server processes them in order, microseconds apart, so every card's
 * PropertyNotify lands in the same picom frame.
 *
 * PER-CLASS OPACITY. --opacity applies to every window id that FOLLOWS it, and
 * may be given more than once, so one invocation can nudge two sets of sticky
 * windows to two different values and still put them all on one connection.
 * That is needed because the conky cards are nudged around whatever level
 * bin/focusdim.py has faded them to, while the wallpaper sheet is always
 * nudged around opaque:
 *
 *     picom-slide-fire --desktop 2 --opacity A -- <cards> --opacity B -- <sheet>
 *
 * The old single-group form is unchanged.
 *
 * ORDERING. The desktop switch is queued FIRST. It has the longer path to
 * picom -- the server hands the client message to xfwm4, xfwm4 unmaps the
 * windows, and only then does picom see anything -- while a property change
 * is delivered straight to picom's own connection. Sending it first gives
 * xfwm4 that head start.
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(void) {
	fprintf(stderr,
	        "usage: picom-slide-fire [--desktop N] "
	        "[--opacity V [--] <winid>...]...\n"
	        "       --opacity applies to every winid after it, and may repeat\n"
	        "       winid may be decimal or 0x-prefixed hex\n");
	exit(2);
}

int main(int argc, char **argv) {
	long desktop = -1;
	unsigned long opacity = 0;
	int have_opacity = 0, i, n = 0;

	/* Parsed into a list first, and the switch is sent before any of it, so
	 * --desktop keeps its head start wherever it appears on the command
	 * line. Never more entries than there are arguments. */
	struct { Window win; unsigned long opacity; } *set =
	        calloc(argc > 0 ? argc : 1, sizeof *set);
	if (!set) {
		fprintf(stderr, "picom-slide-fire: out of memory\n");
		return 1;
	}

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--desktop") && i + 1 < argc) {
			desktop = strtol(argv[++i], NULL, 0);
		} else if (!strcmp(argv[i], "--opacity") && i + 1 < argc) {
			opacity = strtoul(argv[++i], NULL, 0);
			have_opacity = 1;
		} else if (!strcmp(argv[i], "--")) {
			continue;   /* a separator, not the end of the options */
		} else if (argv[i][0] == '-' && argv[i][1] != '\0' && argv[i][1] < '0') {
			usage();
		} else {
			Window win = (Window)strtoul(argv[i], NULL, 0);
			if (!win || !have_opacity)
				continue;
			set[n].win = win;
			set[n].opacity = opacity;
			n++;
		}
	}

	Display *dpy = XOpenDisplay(NULL);
	if (!dpy) {
		fprintf(stderr, "picom-slide-fire: cannot open display\n");
		return 1;
	}
	Window root = DefaultRootWindow(dpy);

	if (desktop >= 0) {
		XEvent ev;
		memset(&ev, 0, sizeof ev);
		ev.xclient.type = ClientMessage;
		ev.xclient.window = root;
		ev.xclient.message_type = XInternAtom(dpy, "_NET_CURRENT_DESKTOP", False);
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = desktop;
		ev.xclient.data.l[1] = CurrentTime;
		XSendEvent(dpy, root, False,
		           SubstructureNotifyMask | SubstructureRedirectMask, &ev);
	}

	if (n) {
		Atom prop = XInternAtom(dpy, "_NET_WM_WINDOW_OPACITY", False);
		for (i = 0; i < n; i++) {
			/* format 32 means "array of long" to Xlib, not uint32_t. */
			unsigned long value = set[i].opacity;
			XChangeProperty(dpy, set[i].win, prop, XA_CARDINAL, 32,
			                PropModeReplace, (unsigned char *)&value, 1);
		}
	}

	XSync(dpy, False);
	XCloseDisplay(dpy);
	free(set);
	return 0;
}
