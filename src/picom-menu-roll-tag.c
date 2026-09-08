/*
 * picom-menu-roll-tag -- tag popup/dropdown menus with which edge is nearest
 * the cursor, so picom.conf can pick "roll up" vs "roll down" from the REAL
 * click point instead of guessing from screen position.
 *
 * Build:
 *     gcc -O2 -Wall -o ~/.local/bin/picom-menu-roll-tag \
 *         ~/.local/src/picom-menu-roll-tag.c -lX11
 *
 * WHY IT EXISTS. picom's match conditions can only see a window's OWN
 * x/y/width/height -- there is no monitor geometry and no cursor position
 * available there, and animation SCRIPTS have no comparison/conditional
 * operators at all (only + - * / ^, see the animations in picom.conf). So
 * neither picom mechanism can answer "did this menu open below the cursor,
 * or did the toolkit flip it to open above?" -- the only thing that
 * actually answers that is the real cursor position at the moment the menu
 * mapped, compared to which of the menu's own edges it's closer to. A
 * screen-position proxy (e.g. "is this window in the top or bottom half of
 * the screen") gets this wrong near the middle, and doesn't generalize to
 * monitors of arbitrary size/position without hardcoding their geometry.
 *
 * This is the same trick as _PICOM_SLIDE (see picom-slide-switch and
 * picom-slide-fire.c): an external process with real X access computes
 * something picom's own rule language cannot, and hands the answer over as
 * a plain window property. picom.conf then just matches on it.
 *
 * MECHANISM. Listens for MapNotify on the root window (SubstructureNotifyMask
 * catches it for every child, override-redirect popups included). For each
 * mapped window whose _NET_WM_WINDOW_TYPE is popup_menu or dropdown_menu:
 *   - XQueryPointer for the real cursor position
 *   - compare the cursor's Y to the window's top edge (y) and bottom edge
 *     (y + height)
 *   - whichever edge is closer is the anchor: closer to the top means the
 *     menu grew DOWNWARD from the click point (roll down), closer to the
 *     bottom means it grew UPWARD (roll up)
 *   - tag the window: _PICOM_ROLL = "d" or "u" (format 8, type STRING --
 *     same encoding xprop's "8s" produces, so it matches picom.conf's
 *     `_PICOM_ROLL@ = 'u'` the same way `_PICOM_SLIDE@ = 'l'` already does)
 *
 * No monitor geometry is needed at all: comparing the real cursor position
 * to the real window edges is correct regardless of which monitor either
 * one is on, or that monitor's resolution.
 *
 * TIMING. This has to win a race against picom, which reacts to the same
 * MapNotify to start the "open" animation. By the time MapNotify is sent,
 * the mapping client's OWN preceding requests (including setting
 * _NET_WM_WINDOW_TYPE and final geometry) are guaranteed already processed
 * -- X delivers a single client's requests in order -- so the property read
 * here is never stale. Winning the race against picom is a matter of being
 * fast: this does three round trips (get window type, query pointer, set
 * property) on one otherwise-idle connection, which easily beats picom's
 * own frame cadence (~16ms at 60Hz). See picom-slide-fire.c for the same
 * reasoning applied to the workspace-slide animation.
 *
 * FALLBACK. If this daemon isn't running, or loses the race for a given
 * menu, the window is simply never tagged. picom.conf's rules treat
 * "untagged" the same as "tagged d" (roll down) rather than requiring an
 * exact match, so a menu never ends up with no animation at all -- it just
 * falls back to the less accurate default.
 */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static Atom a_wm_window_type, a_type_popup_menu, a_type_dropdown_menu, a_roll;

/* A window can vanish between the MapNotify that told us about it and the
 * handful of round trips we do to tag it (closed as fast as it was opened,
 * or never fully realized). The default Xlib error handler treats any
 * BadWindow etc. from that as fatal and kills the process -- for a daemon
 * that has to run forever, a race like that should just drop this one
 * window, not take the whole thing down. */
static int ignore_x_errors(Display *dpy, XErrorEvent *err) {
	(void)dpy;
	(void)err;
	return 0;
}

static int is_menu(Display *dpy, Window win) {
	Atom actual_type;
	int actual_format;
	unsigned long nitems, bytes_after;
	unsigned char *prop = NULL;
	int result = 0;

	if (XGetWindowProperty(dpy, win, a_wm_window_type, 0, 16, False, XA_ATOM,
	                        &actual_type, &actual_format, &nitems, &bytes_after,
	                        &prop) != Success ||
	    !prop) {
		return 0;
	}
	if (actual_type == XA_ATOM && actual_format == 32) {
		Atom *atoms = (Atom *)prop;
		for (unsigned long i = 0; i < nitems; i++) {
			if (atoms[i] == a_type_popup_menu || atoms[i] == a_type_dropdown_menu) {
				result = 1;
				break;
			}
		}
	}
	XFree(prop);
	return result;
}

static void tag_window(Display *dpy, Window win) {
	XWindowAttributes attrs;
	if (!XGetWindowAttributes(dpy, win, &attrs)) {
		return;
	}

	/* attrs.x/y are relative to the window's parent. Override-redirect
	 * popups are usually direct children of root already, but translate
	 * properly rather than assume that. */
	Window child;
	int root_x, root_y;
	if (!XTranslateCoordinates(dpy, win, DefaultRootWindow(dpy), 0, 0, &root_x,
	                            &root_y, &child)) {
		return;
	}

	Window root_ret, child_ret;
	int pointer_x, pointer_y, win_x, win_y;
	unsigned int mask;
	if (!XQueryPointer(dpy, DefaultRootWindow(dpy), &root_ret, &child_ret,
	                    &pointer_x, &pointer_y, &win_x, &win_y, &mask)) {
		return;
	}

	int top = root_y;
	int bottom = root_y + attrs.height;
	int dist_top = abs(pointer_y - top);
	int dist_bottom = abs(pointer_y - bottom);
	const char *dir = (dist_top <= dist_bottom) ? "d" : "u";

	XChangeProperty(dpy, win, a_roll, XA_STRING, 8, PropModeReplace,
	                (const unsigned char *)dir, 1);
	XFlush(dpy);
}

int main(void) {
	Display *dpy = XOpenDisplay(NULL);
	if (!dpy) {
		fprintf(stderr, "picom-menu-roll-tag: cannot open display\n");
		return 1;
	}
	XSetErrorHandler(ignore_x_errors);

	Window root = DefaultRootWindow(dpy);

	a_wm_window_type = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
	a_type_popup_menu = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_POPUP_MENU", False);
	a_type_dropdown_menu = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU", False);
	a_roll = XInternAtom(dpy, "_PICOM_ROLL", False);

	XSelectInput(dpy, root, SubstructureNotifyMask);

	XEvent ev;
	for (;;) {
		XNextEvent(dpy, &ev);
		if (ev.type == MapNotify) {
			Window win = ev.xmap.window;
			if (is_menu(dpy, win)) {
				tag_window(dpy, win);
			}
		}
	}

	XCloseDisplay(dpy);
	return 0;
}
