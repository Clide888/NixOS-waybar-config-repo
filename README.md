![Showcase](images/waybar.png)

# Waybar config — river-classic on NixOS (+ a Fedora port in `fedora/`)

A [Waybar](https://github.com/Alexays/Waybar) status bar themed
[Catppuccin Mocha](https://catppuccin.com/), rewritten from a Hyprland-on-Arch
setup for **river-classic** (river 0.3.x) on **NixOS + Home Manager**. A plain
config-file port for **Fedora** (river-classic from the official repos, no
Home Manager) lives in [`fedora/`](fedora/) — see its README.

The layout, colors and behaviour are the same where river can support them. The
sections below list exactly what changed and why — nothing was silently dropped.

```
.
├── flake.nix               # homeManagerModules.default + a buildable example
├── modules/
│   ├── default.nix         # imports both
│   ├── waybar-config.nix   # the bar: programs.waybar settings + style.css
│   └── waybar-river.nix    # packages, mako, river bindings
├── examples/               # copy-paste flake.nix / configuration.nix / home.nix
├── scripts/                # the custom/* module backends (bash)
├── style.css               # GTK3 CSS, read by waybar-config.nix and the Fedora port
├── fedora/                 # Fedora port: installer + waybar/mako/river drop-ins
└── LICENCE                 # MIT, from the original project
```

## Install

Three things to know before you start:

1. **You need `river-classic`, not `river`.** River 0.4+ removed the
   `zriver_status_manager_v1` protocol, and that is what Waybar's `river/tags` and
   `river/window` modules speak. The Home Manager `river` module already defaults
   to `pkgs.river-classic`, and this config asserts on it so you find out at build
   time rather than with a blank bar.
2. **The flake input is pinned to this branch** while the work is unmerged. After
   it lands on `main`, drop the suffix from the URL.
3. **Nothing needs root except the system services.** The bar, its scripts and
   mako are all per-user Home Manager options.

Copy-paste examples live in `examples/`: `flake.nix`, `configuration.nix`,
`home.nix`. Replace `HOSTNAME` and `USER`, then:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#HOSTNAME   # Option A
# or, for standalone Home Manager:
home-manager switch --flake .#USER@HOSTNAME             # Option B
```

Then log out and pick the **river** session at the display manager. The bar starts
with `river-session.target`; no autostart line and no `launch.sh` in
`~/.config/river/init` is needed.

### The short version

```nix
# flake.nix
inputs.waybar-river.url =
  "github:Clide888/NixOS-waybar-config-repo/arena/f4451ba9-nixos-waybar-config-repo";
# after merge: "github:Clide888/NixOS-waybar-config-repo"
```

```nix
# home.nix
{ inputs, pkgs, ... }:
{
  imports = [ inputs.waybar-river.homeManagerModules.default ];

  services.waybar-river.enable = true;

  wayland.windowManager.river = {
    enable = true;
    package = pkgs.river-classic;   # the default, spelled out on purpose
    # your own bindings / rules stay here, untouched
  };
}
```

```nix
# configuration.nix
services.displayManager.sessionPackages = [ pkgs.river-classic ];
networking.networkmanager.enable = true;      # nmcli, custom/wifi
hardware.bluetooth.enable = true;             # bluetoothctl, custom/bluetooth
services.power-profiles-daemon.enable = true; # power-profiles-daemon module
services.upower.enable = true;                # battery module
hardware.acpilight.enable = true;             # backlight module
```

### Without flakes

```nix
# home.nix
{
  imports = [ /path/to/NixOS-waybar-config-repo/modules/default.nix ];
  services.waybar-river.enable = true;
}
```

`/path/to/...` is copied into the Nix store at evaluation, so a `git clone` into
`~/src/waybar-river` works fine. Point it at a fixed path, not `~/.config`, and
re-run `nixos-rebuild`/`home-manager switch` after editing the scripts here.

### Checking it builds before switching

```sh
nix build .#checks.x86_64-linux.example     # this repo's own example config
# or, in your own flake:
nixos-rebuild build --flake .#HOSTNAME
home-manager build --flake .#USER@HOSTNAME
```

### If something is missing from the bar

| Symptom | Cause |
|---|---|
| Tags render but never highlight, `river/window` empty | you are running `pkgs.river` (0.4+), not `river-classic` |
| Bar never appears | no display manager session: check `services.displayManager.sessionPackages` includes `river-classic`, or start it once by hand with `waybar` |
| Glyphs are boxes | `nerd-fonts.jetbrains-mono` is installed per-user by the module; check `fc-list \| grep -iE "JetBrainsMono.*(Nerd|NFP)"` inside the session |
| `custom/*` capsules empty | run the script by hand, e.g. `waybar-wifi` / `waybar-bluetooth`, and read stderr |
| `power-profiles-daemon` empty | `services.power-profiles-daemon.enable = true`, and no `services.tlp` (they conflict) |
| `custom/notify` shows the "on" bell but DND does nothing | `makoctl mode` must list `do-not-disturb`; `services.mako` in this module sets it up |

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

`custom/uptime` + stopwatch, `custom/wifi` + `custom/bluetooth` (nmcli /
bluetoothctl, one capsule each), `custom/sysinfo` (CPU/RAM, thresholds, pulse
animation), battery, backlight,
`wireplumber`, `power-profiles-daemon`, clock with the calendar tooltip. Same
scripts, with the small fixes listed below.

### Small fixes made while porting

- **Glyphs are octal UTF-8 now, not `printf '\U000F13AB'`.** Under a POSIX/ASCII
  locale — the usual locale of a systemd user service — bash writes the literal
  text `\U000F13AB` instead of the glyph. Verified and fixed in every script.
- `scripts/wifi.sh` no longer hardcodes `wlo1`; the interface is detected from
  NetworkManager, with `WAYBAR_WIFI_IFACE` as an override. `grep -oP` (GNU grep
  PCRE) became `sed`, and the WiFi glyphs are built with `printf`. The Bluetooth
  half moved out into `scripts/bluetooth.sh` (`custom/bluetooth`).
- **The script wrappers pass the script name as `$0`.** Without it, the first
  argument meant for the script was swallowed by `bash -c` as `$0`, so
  `waybar-stopwatch toggle` (the stopwatch left click) never did anything.
- The `power-profiles-daemon` tooltip uses a real newline, not a literal `\n`
  that would show up as text on the bar.
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
| right    | backlight, wireplumber, custom/uptime, custom/wifi, custom/bluetooth, power-profiles-daemon, custom/sysinfo, custom/notify |

- **clock** — `H:M`, calendar in the tooltip
- **battery** — icon + %, color-only warning/critical, `notify-send` on critical
- **custom/window** — focused app name; tooltip carries the window title
- **river/tags** — click to view, right click to toggle into the view
- **backlight**, **volume** — volume: scroll to change, left click mutes, right
  click opens `pavucontrol`, mic-off glyph when the source is muted
- **custom/uptime** — `uptime -p`, doubles as a stopwatch (left click
  start/pause, right click reset)
- **custom/wifi** — WiFi signal; the tooltip carries SSID and signal strength
- **custom/bluetooth** — right next to `custom/wifi`; glyph shows the controller
  state (off / on / connected), tooltip lists connected devices with battery
  percentages; left click toggles the radio power, right click opens
  `blueman-manager`
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
| `wifi.sh` | `custom/wifi` | jq, nmcli |
| `bluetooth.sh` | `custom/bluetooth` | jq, bluetoothctl (`blueman-manager` for the right click) |
| `window.sh` | `custom/window` | jq, wlrctl |
| `notify.sh`, `notify-toggle.sh` | `custom/notify` | jq, makoctl |
| `system-reset.sh` | `custom/sysinfo` click, `META+SHIFT+R` | riverctl |
| `toggle-tag-bar.sh` | `META+A` | riverctl, pkill/pgrep |
| `launch.sh` | manual restart (`waybar-launch`) | pgrep/pkill |

Override the app set spawned by the reset button with
`SYSTEM_RESET_APPS="firefox \"kitty -e htop\" dolphin"`.

## Moving from the Arch setup

1. Back up `~/.config/waybar`, `~/.config/swaync` and `~/.config/mako`.
2. Delete the Hyprland autostart lines (`swaync &`, `waybar &`,
   `workspace_bar_daemon.py &`) and the `SUPER+A` binding — they now come from
   `river/init` and `river-session.target` instead. Leaving the old ones in place
   gives you two bars fighting over the same layer surface.
3. Mask anything the Arch setup enabled that NixOS will not manage, e.g.
   `systemctl --user disable --now swaync.service`.
4. `~/.config/waybar`, `~/.config/mako` and `~/.config/river/init` become
   read-only store symlinks. Do not edit them in place; edit `home.nix`.

## Fedora

A plain config-file port for Fedora (river-classic from the official repos, no
Home Manager) is in [`fedora/`](fedora/). Short version:

```sh
git clone <this repo> && cd NixOS-waybar-config-repo
fedora/install.sh        # dnf deps, nerd font, ~/.config drop-ins, backups
# log out, pick the "river" session at the display manager
```

`fedora/README.md` documents the package mapping, what gets installed where,
and how the Bluetooth widget behaves.

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
`bluez` (bluetoothctl), `blueman`, `pavucontrol`, `libnotify`,
`nerd-fonts.jetbrains-mono` (the nerd-fonts family; style.css accepts both the
`JetBrainsMono Nerd Font` and `JetBrainsMono NFP` family names).
`services.waybar-river.extraPackages` adds more.
