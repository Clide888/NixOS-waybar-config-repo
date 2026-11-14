# Fedora port — river-classic + waybar

The same Catppuccin Mocha bar as the NixOS/Home Manager setup in the repo root,
as plain config files for **Fedora**: waybar + mako + river-classic from the
official Fedora repos, an installer script, and no Nix anywhere in sight.
Scripts, `style.css` and behavior are identical to the NixOS port.

```
fedora/
├── install.sh          # dnf deps, nerd font, drop files into ~/.config, backups
├── uninstall.sh        # remove what install.sh installed (leaves dnf alone)
├── waybar/config.jsonc # the bar (mirrors modules/waybar-config.nix as JSON)
├── mako/config         # mirrors services.mako from modules/waybar-river.nix
└── river/init          # mirrors the river settings HM generates + starts mako/waybar
```

`style.css` is **not** copied here — the installer uses the single source at the
repo root for both ports. `scripts/*.sh` likewise. Only the two toolkits'
glue files live here.

## Quick start

```sh
git clone <this repo> && cd NixOS-waybar-config-repo
fedora/install.sh
# log out, pick the "river" session in the display manager (GDM's gear menu)
```

`install.sh` is idempotent. Flags: `--no-dnf` (skip packages, config only),
`--no-font` (skip the font download). Everything it would overwrite is backed
up first as `<file>.bak.<timestamp>`.

After login the bar and notifications are started by `~/.config/river/init` —
there is no systemd service to enable. If the bar is not there, run `waybar`
from a terminal to see the errors, or `waybar-launch` (installed into
`~/.local/bin`) to restart it.

## Packages

Installed by `dnf` (Fedora 43, 44, 45 and rawhide at the time of writing):

| dnf package        | Provides                     | Used by |
|--------------------|------------------------------|---------|
| `river-classic`    | `river`, `riverctl`, `rivertile`, the `river` session | the compositor |
| `waybar`           | `waybar` (0.14/0.15, built with `HAVE_RIVER`) | the bar |
| `mako`             | `mako`, `makoctl`            | notifications, `custom/notify` |
| `wlrctl`           | `wlrctl`                     | `custom/window` (F42+; older Fedora: placeholder glyph) |
| `fuzzel`           | `fuzzel`                     | `Super+F` launcher in `river/init` |
| `jq`, `gawk`, `procps-ng`, `util-linux` | core tools | the `custom/*` scripts |
| `NetworkManager`   | `nmcli`                      | `custom/wifi` |
| `bluez`            | `bluetoothctl`               | `custom/bluetooth` |
| `blueman`          | `blueman-manager`            | `custom/bluetooth` right click |
| `wireplumber`      | `wpctl`                      | volume keys, `wireplumber` module |
| `pavucontrol`      | `pavucontrol`                | volume module, right click |
| `libnotify`        | `notify-send`                | battery-critical alert |
| `brightnessctl`    | `brightnessctl`              | backlight module + brightness keys |
| `upower`           | `upower` (D-Bus activated)   | battery module — nothing to enable |
| `power-profiles-daemon` | `power-profiles-daemon`  | power-profiles-daemon module |
| `curl`, `unzip`    | —                            | the font install |

`NetworkManager`, `bluetooth` and `power-profiles-daemon` are
`systemctl enable --now`d by the installer (idempotent; skip with a transplant
if you manage services yourself).

### river-classic is *not* the `river` package on F44+

Fedora ships two different compositors:

- **`river-classic`** — the maintained 0.3.x line (0.3.14 on F43, 0.3.17 on
  F44/F45). This is what this config needs: Waybar's `river/tags` speaks
  `zriver_status_manager_v1`, which only river-classic implements. It ships the
  `river`, `riverctl` and `rivertile` binaries, conflicts with the 0.4+ `river`
  package, and installs `/usr/share/wayland-sessions/river.desktop`.
- **`river`** — the 0.4/0.5 rewrite that splits window management out of the
  compositor. Installing it instead of river-classic leaves the tags area of the
  bar blank. If both are somehow installed, `sudo dnf swap river river-classic`.

## What lands where

| Destination | Content |
|---|---|
| `~/.config/waybar/config` | the bar layout (from `waybar/config.jsonc` — top-level JSON **array**, like home-manager emits) |
| `~/.config/waybar/style.css` | capsule colors, Catppuccin palette (from the repo-root `style.css`) |
| `~/.config/waybar/scripts/*.sh` | the `custom/*` backends, executable |
| `~/.config/waybar/config` exec lines | reference `$HOME/.config/waybar/scripts/…` — waybar runs `exec` via `/bin/sh -c`, so `$HOME` expands |
| `~/.config/mako/config` | Catppuccin palette, no border on critical-only timeout, `do-not-disturb` mode |
| `~/.config/river/init` | borders, layout (`rivertile`), all keybindings, `mako &`, `waybar &` |
| `~/.local/bin/waybar-launch` | restart the bar without logging out |
| `~/.local/share/fonts/JetBrainsMonoNerdFont` | JetBrainsMono Nerd Font 3.5.1 (not in the Fedora repos) |

Nothing outside your home directory is touched except `dnf` packages and
`systemctl enable --now` for the three system services above.

### Why not `~/.config/systemd/user/waybar.service`?

The waybar RPM's user unit is bound to `graphical-session.target` with a
`Requisite=` on it — and a river session never activates that target. So:
waybar is spawned by `river/init` like everything else in the session, and
`waybar-launch` (or `killall waybar && waybar &`) is how you restart it.
If you *do* want a systemd user unit, bind one to nothing and start it from
`river/init` anyway — there is no river equivalent of `river-session.target`
without writing your own target.

## The Bluetooth widget

`custom/bluetooth`, between `custom/wifi` and `power-profiles-daemon`:

- glyph: `󰂲` controller off · `󰂯` powered, idle · `󰂰` at least one device
  connected
- tooltip: power state + one line per connected device, with battery
  percentage when BlueZ reports it
- left click: toggle controller power (`bluetooth.sh toggle`)
- right click: `blueman-manager`
- polled every 10s like WiFi

The power toggle is best-effort: on some setups BlueZ restricts who may set
`Powered` (polkit). If the click does nothing, use the right click —
blueman-manager does the same thing through the UI (and may ask for your
password). If the widget always shows `off` while the adapter is in fact on,
you've hit an rfkill soft block: `rfkill list` / `rfkill unblock bluetooth`.

## Notes and gotchas

- **"waybar spawns but no bar appears"** is the signature of a waybar config
  that parses but is the wrong *shape*. `~/.config/waybar/config` must be a
  top-level JSON **array** of bar objects — exactly what home-manager's
  `programs.waybar.settings` emits on NixOS. A bare object (e.g. wrapping the
  bar in `mainBar`) is accepted silently: no output matches it, the `Bar`
  constructor throws before a window is created, and waybar stays running
  with nothing on screen. `install.sh` refuses to finish with a malformed
  config, and logs `waybar config sanity check passed` when it's fine.
  Verify with:
  ```sh
  jq -e 'type == "array"' ~/.config/waybar/config
  journalctl --user -b | grep -i waybar     # GDM sessions log river's children here
  waybar -l debug                           # run by hand on the live session to see the error
  ```
- **Glyph font**: v3 nerd-fonts installs the family as `JetBrainsMono Nerd Font`
  (and the legacy alias `JetBrainsMono NFP`). `style.css` asks for both, so the
  bar is consistent with the NixOS port either way. If you install the font by
  hand, run `fc-cache -f`.
- **DND**: `makoctl mode -t do-not-disturb` flips Do Not Disturb (the bell in
  the bar, click to toggle). `[mode=do-not-disturb]` in the mako config is what
  makes that do anything.
- **Terminal and launcher**: the default `river/init` spawns `ghostty`
  (`Super+Return`) and `fuzzel` (`Super+F`). `fuzzel` is installed by the
  installer; `ghostty` is **not in the official Fedora repos** — install it
  from upstream or from a Copr (e.g. `a-zhn/ghostty`), or change the spawn
  line to a terminal you already have (`kitty`/`foot`/`alacritty` are all in
  the repos). The installer warns about this at the end if `ghostty` is
  missing from PATH.
- **`Super+E` exits river** in this default config (no confirmation prompt) —
  it used to be unbound; change the binding if that is too close to `Super+Q`
  for you.
- **Backlight**: `brightnessctl` works out of the box for the local session on
  Fedora (udev ACL). If the backlight module is empty you're probably on a
  desktop with no `/sys/class/backlight` — that's expected.
- **Battery**: uses upower; the module hides itself on machines without one.
- **`wlrctl`** is packaged from F42. Without it `custom/window` shows a
  "no windows" placeholder; everything else works.
- **systemd-boot/grub/gdm**: not touched. The river-classic RPM registers the
  session; if GDM doesn't list "river", reinstall the package so the
  `wayland-sessions/river.desktop` file is rewritten, or run `river` from a tty.

## Uninstall

```sh
fedora/uninstall.sh       # removes the installed files; leaves dnf alone
sudo dnf remove river-classic waybar mako wlrctl blueman   # optional
```

Backups made by the installer are `<file>.bak.<timestamp>` next to the
originals.

## Keeping this in sync with the NixOS port

- `scripts/` and `style.css` are shared — edit once, both ports get it.
- `fedora/waybar/config.jsonc` mirrors `modules/waybar-config.nix` by hand
  (Nix → JSON). Change both, or the bar drifts between hosts. Keep the top
  level an array of bar objects — that is what home-manager produces. The glyph
  codepoints, module order and click bindings were cross-checked mechanically
  when the port was written.
- `fedora/mako/config` mirrors the `services.mako` settings.
- `fedora/river/init` is the Fedora-side default session script: the same
  bindings and borders as the NixOS river config, with `ghostty`, `fuzzel` and a
  `Super+E` exit on top. It also starts mako + waybar, which Home Manager used
  to do via `river-session.target` + the waybar systemd unit.
