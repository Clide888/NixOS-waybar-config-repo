# The bar itself: module layout, per-module options, and the CSS.
#
# Plain Home Manager `programs.waybar`, so it builds and can be inspected on its
# own (`home-manager build`). Packages, session services and river bindings that
# the bar depends on are in waybar-river.nix.
#
# Every custom/* module runs a script from ../scripts, wrapped with the tools it
# needs (jq, nmcli, bluetoothctl, makoctl, wlrctl). A bare home.file copy would
# depend on those being on the *bar's* PATH, which under a systemd user service
# is not the login PATH.
{ config, lib, pkgs, ... }:

let
  src = ../scripts;

  # The scripts are bash (arrays, `[[ ]]`, `local`), so the interpreter is pinned
  # instead of relying on the wrapper's default /bin/sh.
  #
  # The body is passed to `bash -c` as a single quoted string. Writing it after a
  # shebang would not work: writeShellApplication prepends its own
  # `set -o errexit` prologue, and a second shebang would land in the middle of
  # the file.
  mkScript = { file, name, runtimeInputs }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = ''
        exec ${pkgs.bash}/bin/bash -c ${lib.escapeShellArg (builtins.readFile (src + "/${file}.sh"))} "$@"
      '';
    };

  uptime = mkScript {
    file = "uptime";
    name = "waybar-uptime";
    runtimeInputs = with pkgs; [ coreutils jq ];
  };

  stopwatch = mkScript {
    file = "stopwatch";
    name = "waybar-stopwatch";
    runtimeInputs = with pkgs; [ coreutils jq ];
  };

  sysinfo = mkScript {
    file = "sysinfo";
    name = "waybar-sysinfo";
    runtimeInputs = with pkgs; [ coreutils jq gawk procps ];
  };

  systemReset = mkScript {
    file = "system-reset";
    name = "waybar-system-reset";
    runtimeInputs = with pkgs; [ river-classic coreutils util-linux ];
  };

  wifiBt = mkScript {
    file = "wifi_bt";
    name = "waybar-wifi-bt";
    runtimeInputs = with pkgs; [ coreutils jq gawk networkmanager bluez ];
  };

  # wlrctl is only a fallback source for the app name (see scripts/window.sh);
  # it is wrapped in so the module keeps working if the user has no wlrctl on
  # the session PATH.
  window = mkScript {
    file = "window";
    name = "waybar-window";
    runtimeInputs = with pkgs; [ coreutils jq gawk wlrctl ];
  };

  notifyState = mkScript {
    file = "notify";
    name = "waybar-notify";
    runtimeInputs = with pkgs; [ coreutils jq mako ];
  };

  notifyToggle = mkScript {
    file = "notify-toggle";
    name = "waybar-notify-toggle";
    runtimeInputs = [ pkgs.mako ];
  };
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 26;
        spacing = 2;
        exclusive = true;
        gtk-layer-shell = true;
        passthrough = false;
        fixed-center = true;

        modules-left = [
          "clock"
          "battery"
          "custom/window"
        ];

        # river/tags replaces hyprland/workspaces. Tags are numbered from 1 and
        # the bitmasks are 1 << (tag - 1), matching `riverctl focus-tags`.
        modules-center = [ "river/tags" ];

        modules-right = [
          "backlight"
          "wireplumber"
          "custom/uptime"
          "custom/wifi"
          "power-profiles-daemon"
          "custom/sysinfo"
          "custom/notify"
        ];

        "river/tags" = {
          num-tags = 9;
          tag-labels = [ "1" "2" "3" "4" "5" "6" "7" "8" "9" ];
          # left click views one tag, right click toggles a tag into the view
          disable-click = false;
          hide-vacant = false;
        };

        clock = {
          format = "󰥔 {:%H:%M}";
          calendar = {
            format = {
              days = "<span weight='normal'>{}</span>";
              months = "<span color='#cdd6f4'><b>{}</b></span>";
              today = "<span color='#f38ba8' weight='700'><u>{}</u></span>";
              weekdays = "<span color='#f9e2af'><b>{}</b></span>";
              weeks = "<span color='#a6e3a1'><b>W{}</b></span>";
            };
            mode = "month";
            mode-mon-col = 1;
            on-scroll = 1;
          };
          tooltip-format = "<span color='#cdd6f4' font='JetBrainsMono NFP 14'><tt><small>{calendar}</small></tt></span>";
        };

        battery = {
          states = {
            warning = 20;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = "󰚥 {capacity}%";
          format-icons = {
            default = [ "󰂎" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹" ];
            charging = [ "󰢟" "󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅" ];
          };
          format-time = "{H}s {M}dk";
          tooltip-format-discharging = "{timeTo}  ·  {power}W";
          tooltip-format-charging = "{timeTo}";
          tooltip-format-full = "Battery full";
          # notify-send is libnotify, added by waybar-river.nix; mako is the
          # daemon that shows it.
          events.on-discharging-critical = "notify-send -u critical -a Battery -i battery-caution 'Battery critical' 'You need to charge'";
        };

        power-profiles-daemon = {
          format = "{icon}";
          tooltip-format = "Power profile: {profile}\\nClick → switch";
          format-icons = {
            default = "󰾅";
            performance = "󰓅";
            balanced = "󰾅";
            power-saver = "󰾆";
          };
        };

        backlight = {
          format = "{icon} {percent}%";
          format-icons = [ "󰃞" "󰃟" "󰃠" ];
          tooltip = false;
        };

        wireplumber = {
          format = "{icon} {volume}%{format_source}";
          format-muted = "󰝟{format_source}";
          format-bluetooth = "󰂰 {volume}%{format_source}";
          format-bluetooth-muted = "󰂲{format_source}";
          format-source = "";
          # mic muted -> mic-off glyph after the volume %
          format-source-muted = " 󰍭";
          format-icons = [ "󰕿" "󰖀" "󰕾" ];
          scroll-step = 5;
          max-volume = 120;
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-click-right = "pavucontrol";
          tooltip-format = "{node_name}  ·  {volume}%";
        };

        # custom/window - the focused app's NAME, with river/window's title in the
        # tooltip. Replaces the old python module that read hyprctl; the hidden
        # hyprland/window (bar transparency when a workspace is empty) is gone,
        # because river/window has no `.empty` class to hang it on.
        "custom/window" = {
          format = "{text}";
          exec = "${window}/bin/waybar-window";
          return-type = "json";
          # the text is plain (no pango markup in window.sh), so escaping is on
          escape = true;
          max-length = 25;
          # wlrctl is polled, not event-driven: 2s keeps the capsule honest
          # without spawning a process every second for the whole session.
          interval = 2;
          tooltip = true;
        };

        "custom/uptime" = {
          format = "󰔟 {text}";
          return-type = "json";
          exec = "${uptime}/bin/waybar-uptime";
          interval = 1;
          tooltip = true;
          on-click = "${stopwatch}/bin/waybar-stopwatch toggle";
          on-click-right = "${stopwatch}/bin/waybar-stopwatch reset";
        };

        "custom/wifi" = {
          format = "{text}";
          return-type = "json";
          exec = "${wifiBt}/bin/waybar-wifi-bt";
          interval = 10;
          tooltip = true;
        };

        "custom/sysinfo" = {
          format = "{text}";
          return-type = "json";
          exec = "${sysinfo}/bin/waybar-sysinfo";
          interval = 2;
          tooltip = true;
          # was the Hyprland "session reset"; river cannot close windows, so this
          # respawns the app set onto tags instead (scripts/system-reset.sh)
          on-click = "${systemReset}/bin/waybar-system-reset";
        };

        # custom/notify - swaync -> mako. mako has no unread counter, so the glyph
        # is a static bell whose tooltip carries the DND state.
        "custom/notify" = {
          format = "{text}";
          return-type = "json";
          exec = "${notifyState}/bin/waybar-notify";
          interval = 5;
          tooltip = true;
          on-click = "${notifyToggle}/bin/waybar-notify-toggle";
          on-click-right = "makoctl dismiss -a";
        };
      };
    };

    style = builtins.readFile ../style.css;
  };
}
