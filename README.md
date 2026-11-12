![Showcase](images/waybar.png)

# Waybar config — river-classic on NixOS

A [Waybar](https://github.com/Alexays/Waybar) status bar themed
[Catppuccin Mocha](https://catppuccin.com/), rewritten from a Hyprland-on-Arch
setup for **river-classic** (river 0.3.x) on **NixOS + Home Manager**.

The layout, colors and behaviour are the same where river can support them. The
sections below list exactly what changed and why — nothing was silently dropped.

```
.
├── flake.nix               # homeManagerModules.default + a buildable example
├── modules/
│   ├── default.nix         # imports both
│   ├── waybar-config.nix   # the bar: programs.waybar settings + style.css
│   └── waybar-river.nix    # packages, mako, river bindings
├── scripts/                # the custom/* module backends (bash)
├── style.css               # GTK3 CSS, read by waybar-config.nix
└── LICENCE                 # MIT, from the original project
```

## Install

You need `river-classic`, not `river`: river 0.4+ removed the
`zriver_status_manager_v1` protocol, and that is what Waybar's `river/tags` and
`river/window` modules speak. The Home Manager `river` module already defaults to
`pkgs.river-classic`, and this flake asserts on it.

### Flake

```nix
# flake.nix of your own config
inputs.waybar-river.url = "github:Clide888/NixOS-waybar-config-repo";
```

```nix
# home.nix
{ inputs, ... }:
{
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.waybar-river.homeManagerModules.default
  ];

  services.waybar-river.enable = true;

  # Your river config (bindings/window rules) is yours; this config only adds
  # the bar-related binds.
  wayland.windowManager.river = {
    enable = true;
    package = pkgs.river-classic;   # the default, spelled out for clarity
  };
}
```

### Non-flake

```nix
# home.nix
{
  imports = [ /path/to/NixOS-waybar-config-repo/modules/default.nix ];
  services.waybar-river.enable = true;
}
```

### NixOS side

The scripts used to be installed by `first_time_setup.sh` with `pacman` and
`systemctl`. That is `configuration.nix` now:

```nix
{
  services.xserver.enable = true;               # for a display manager
  services.displayManager.sessionPackages = [ pkgs.river-classic ];

  networking.networkmanager.enable = true;      # nmcli, custom/wifi
  hardware.bluetooth.enable = true;             # bluetoothctl, custom/wifi
  services.power-profiles-daemon.enable = true; # power-profiles-daemon module
  services.upower.enable = true;                # battery module
  hardware.acpilight.enable = true;             # backlight module (or brightnessctl)
}
```

`programs.waybar.systemd.targets` is set to `river-session.target` by the module,
so the bar starts with the session instead of waiting for a
`graphical-session.target` that a river session never activates — the trap the old
swaync service fell into.

## What changed, and why

### Replaced — river has a native module

| Was (Hyprland) | Now (river) | Notes |
|---|---|---|
| `hyprland/workspaces` | `river/tags` | 9 tags, `{id}` → tag numbers. Left click views a tag, right click adds it to the view. Style classes: `#tags button.focused`, `.occupied`, `.urgent`, `.output`. |
| `hyprland/window` (hidden, for the `.empty` class) | `river/window` | Not in the layout: it supplies window titles for the tooltip. |
| `custom/window` (python + `hyprctl`) | `custom/window` (`wlrctl`) | App **name** stays; river's own module owns the title. See below. |
| `SUPER + A` → `toggle_workspace_bar.sh` + `workspace_bar_daemon.py` | `SUPER + A` → `toggle-tag-bar.sh` | River exposes tags as bitmasks; the caching daemon is gone, see the "removed" section. |

`window.py` lost its reason to exist: it parsed Hyprland's IPC and resolved icons
from `.desktop` files. `scripts/window.sh` asks `wlrctl toplevel list
state:activated` for the focused app instead, which river answers through
`wlr-foreign-toplevel-management`, and keeps an app-id → name map for the
fallback. Waybar's embedded-icon escape is no longer used (it re-runs icon
extraction on every update and drops the image on unchanged payloads — that was
the reason for the old script's dedupe dance).

### Replaced — different daemon

| Was | Now |
|---|---|
| `swaync` + `custom/swaync` (unread counter, click = panel, right click = DND) | `mako` + `custom/notify` |

mako has no unread counter and no panel, so the counter is gone; the glyph is
static and its tooltip/tooltip class shows Do Not Disturb state. Clicks: left
toggles DND (`makoctl mode -t do-not-disturb`, wired to `invisible=1`), right
clears all notifications (`makoctl dismiss -a`). Config lives in
`services.mako` with the Catppuccin palette and a no-timeout critical rule.

### Removed — no equivalent, or nothing to run

| Removed | Why |
|---|---|
| `scripts/focus.sh` — "close every window, relaunch the app set" | river gives clients no window list and no close command; only a layout generator can close views, and stock `rivertile` does not. The click on `custom/sysinfo` now runs `scripts/system-reset.sh`, which keeps the port-able half: spawn the app set onto tags 1/3/4/5/6 (`META+SHIFT+R` also runs it). |
| `workspace_bar_daemon.py` — auto-restore the bar on workspace switch | It listened on Hyprland's socket2. River's tag state lives only behind the Wayland status protocol, and nothing packaged in nixpkgs subscribes to it (the compositor ships no such client). `SUPER+A` still hides/shows the bar and records the tag bitmask in `~/.cache/waybar/hidden_tags`, but the bar does **not** come back on its own when you switch tags — press the binding again. |
| Transparent bar on an empty workspace (`window#waybar.empty`) | That class came from `hyprland/window`'s `setClass("empty", ...)`. `river/window` has no `.empty` class (only `.focused`, per output), so there is no signal to hook. The CSS keeps the styling note but no rule that can never match. |
| `24` kB of AUR install logic (`first_time_setup.sh`, yay, `waybar-git`) | NixOS has `pkgs.waybar`; river support is compiled in unconditionally (`HAVE_RIVER`), so no feature-flag package is needed. |

### Kept, ported as-is

`custom/uptime` + stopwatch, `custom/wifi` (nmcli + bluetoothctl, one tooltip),
`custom/sysinfo` (CPU/RAM, thresholds, pulse animation), battery, backlight,
`wireplumber`, `power-profiles-daemon`, clock with the calendar tooltip. Same
scripts, with the small fixes listed below.

### Small fixes made while porting

- **Glyphs are octal UTF-8 now, not `printf '\U000F13AB'`.** Under a POSIX/ASCII
  locale — the usual locale of a systemd user service — bash writes the literal
  text `\U000F13AB` instead of the glyph. Verified and fixed in every script.
- `scripts/wifi_bt.sh` no longer hardcodes `wlo1`; the interface is detected from
  NetworkManager, with `WAYBAR_WIFI_IFACE` as an override. `grep -oP` (GNU grep
  PCRE) became `sed`, and the WiFi glyphs are built with `printf`.
- `scripts/launch.sh` actually restarts the bar. The original
  `pgrep -x waybar && killall waybar || waybar &` never restarted anything:
  `killall` succeeded, so the `||` branch was skipped and the bar just vanished.
- The bar height is `26` instead of `1`. Waybar treats `height: 1` as "use the
  module's natural height" (`configureGlobalOffset` skips any height ≤ 1), which
  is not what the old config looked like it was asking for.

## Modules

| Position | Modules |
|----------|---------|
| left     | clock, battery, custom/window |
| center   | river/tags |
| right    | backlight, wireplumber, custom/uptime, custom/wifi, power-profiles-daemon, custom/sysinfo, custom/notify |

- **clock** — `H:M`, calendar in the tooltip
- **battery** — icon + %, color-only warning/critical, `notify-send` on critical
- **custom/window** — focused app name; tooltip carries the window title
- **river/tags** — click to view, right click to toggle into the view
- **backlight**, **volume** — volume: scroll to change, left click mutes, right
  click opens `pavucontrol`, mic-off glyph when the source is muted
- **custom/uptime** — `uptime -p`, doubles as a stopwatch (left click
  start/pause, right click reset)
- **custom/wifi** — WiFi signal + Bluetooth in one tooltip
- **power-profiles-daemon** — click cycles the profile
- **custom/sysinfo** — CPU + RAM; click respawns the app set (see above)
- **custom/notify** — mako DND state

## Scripts

All in `scripts/`, all bash, all wrapped by the Home Manager module with exactly
the tools they need (`jq`, `nmcli`, `bluetoothctl`, `makoctl`, `wlrctl`,
`riverctl`) rather than relying on the bar's `PATH`.

| Script | Used by | Needs |
|---|---|---|
| `uptime.sh`, `stopwatch.sh` | `custom/uptime` | jq, coreutils |
| `sysinfo.sh` | `custom/sysinfo` | jq, gawk, procps |
| `wifi_bt.sh` | `custom/wifi` | jq, nmcli, bluetoothctl |
| `window.sh` | `custom/window` | jq, wlrctl |
| `notify.sh`, `notify-toggle.sh` | `custom/notify` | jq, makoctl |
| `system-reset.sh` | `custom/sysinfo` click, `META+SHIFT+R` | riverctl |
| `toggle-tag-bar.sh` | `META+A` | riverctl, pkill/pgrep |
| `launch.sh` | manual restart (`waybar-launch`) | pgrep/pkill |

Override the app set spawned by the reset button with
`SYSTEM_RESET_APPS="firefox \"kitty -e htop\" dolphin"`.

## Restarting the bar

```
$ waybar-launch
```

`systemctl --user restart waybar` does the same when the Home Manager systemd
integration is on (it is, via `programs.waybar.systemd.enable`).

## Multi-monitor

`river/tags` is per output — each bar shows its own output's tags, which the old
`hyprland/workspaces` with `all-outputs: true` did not. `toggle-tag-bar.sh`
records a bitmask, so its hidden list is shared between monitors; with a single
screen this distinction never comes up.

## Dependencies

Everything is `home.packages` in `modules/waybar-river.nix`, all from nixpkgs:
`waybar`, `river-classic`, `wlrctl`, `mako`, `jq`, `networkmanager` (nmcli),
`bluez` (bluetoothctl), `pavucontrol`, `libnotify`,
`nerd-fonts.jetbrains-mono` (the `JetBrainsMono NFP` glyph font).
`services.waybar-river.extraPackages` adds more.
