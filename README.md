# picom-conf



Custom picom animation setup: `picom.conf` plus the helper programs, 
shader and desktop glue it depends on. Everything here is a
copy of a live file from `~`; `make install` puts it all back.

>[!NOTE]
> This is tailored to my own workflow and hardware, and is not yet 
> at a stage where it can be guaranteed to work OOTB. I do plan to
> at some point in the near future, but for now you will likely need
> to make changes to certain paths, variables and keybinds.
> At least for now, think of this as more of a referecne!


## Requirements

Built against **stock Arch `picom 13-2.1`** (upstream picom v13, revision `d87a5ba`)

- X11 (`libX11` headers to build), 
- `conky`
- `i3lock-fancy`
- `xrandr`
- XFCE (`xfdesktop`),

optionally:
- `skippy-xd`
- `libinput-gestures`

## Layout

| Path | Installs to | What it is |
|---|---|---|
| `picom.conf` | `~/.config/picom/` | The config itself |
| `src/*.c` | `~/.local/src/` | Sources for the two X11 helper daemons |
| `bin/picom-menu-roll-tag` * | `~/.local/bin/` | Tags popup menus with `_PICOM_ROLL` from the real cursor position |
| `bin/picom-slide-fire` * | `~/.local/bin/` | Fires the slide animation trigger |
| `bin/picom-slide-mark` | `~/.local/bin/` | Marks conky cards with `_PICOM_SLIDE_STICKY` |
| `bin/picom-slide-switch` | `~/.local/bin/` | Sliding workspace switch; bound to gestures and keys |
| `bin/wallpaper-sheet` | `~/.local/bin/` | Repeating wallpaper window so the backdrop can slide |
| `bin/lock-screen` | `~/.local/bin/` | Regenerates shader defines, reloads picom, then `i3lock-fancy` |
| `bin/skippy-expose` | `~/.local/bin/` | One-way macOS-esque Exposé wrapper; excludes the slide windows |
| `shaders/lock.glsl` | `~/.config/picom/picom-shaders/3DCamera/` | Local rewrite of the upstream lock shader (see below) |
| `config/generate-monitor-defines.sh` | `~/.config/picom/` | Writes `monitors.conf` from the current `xrandr` layout |
| `config/monitors.conf` | `~/.config/picom/` | Generated `NUM_MONITORS` / `MONITOR_RECTS` shader defines |
| `conky/focusdim.py` | `~/.config/conky/gruvbox-dark/bin/` | Sets card opacity; the fade rule in `picom.conf` animates its steps |
| `systemd/picom-menu-roll-tag.service` | `~/.config/systemd/user/` | Runs the menu-roll daemon |
| `autostart/wallpaper-sheet.desktop` | `~/.config/autostart/` | Starts `wallpaper-sheet` at login |
| `bindings/*.excerpt` | -- | Reference only; the picom lines out of two larger config files |

## The lock shader

`~/.config/picom/picom-shaders/` is a clone of
[ikz87/picom-shaders](https://github.com/ikz87/picom-shaders), pinned in this
setup at `65ecd9d`. `shaders/lock.glsl` is a **local rewrite** of that repo's
`3DCamera/lock.glsl` (-174/+106 against upstream) and lives here because it
would otherwise exist only as an uncommitted working-tree change inside that
nested checkout.

It is parameterised by the `NUM_MONITORS` / `MONITOR_RECTS` defines that
`picom.conf`'s `class_g = 'i3lock'` rule passes in, which is why
`generate-monitor-defines.sh` runs (via `lock-screen`) before every lock.

## Build and install

```sh
make          # compile src/*.c into bin/
make install  # copy everything to its live location, enable the unit
```

`make install-config` will refuse to run if the `picom-shaders` clone is
missing; clone it first:

```sh
git clone https://github.com/ikz87/picom-shaders/ ~/.config/picom/picom-shaders
```

`monitors.conf` is generated output and is only seeded if absent, so
installing never clobbers the current monitor layout.

## Bindings

Not installed automatically; these lines belong to larger config files owned
by other tools. See `bindings/` for the relevant excerpts:

- `libinput-gestures.conf`: three-finger left/right swipe -> `picom-slide-switch --wrap --dir …`
- `xfce4-keyboard-shortcuts.xml`: `Ctrl+Alt+Left/Right` -> `picom-slide-switch --wrap ±1`, `Ctrl+Alt+L` -> `lock-screen`
