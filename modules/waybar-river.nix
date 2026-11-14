# Session glue for the bar: the packages the modules shell out to, the
# notification daemon, and the river bindings that replace the Hyprland ones.
#
# Import this from configuration.nix. It is a Home Manager module, not a NixOS
# one: everything is per-user, exactly like the Arch setup it replaces. Enabling
# system services (NetworkManager, bluetooth, power-profiles-daemon) still needs
# root - that snippet is in README.md.
{ config, lib, pkgs, ... }:

let
  cfg = config.services.waybar-river;

  # A river binding can only run a command, so the scripts it calls need a stable
  # name on PATH. (The waybar modules call the same scripts through store paths
  # directly - see waybar-config.nix.)
  #
  # The body is handed to `bash -c` as one quoted argument instead of being
  # pasted in: writeShellApplication prepends its own `set -o errexit` prologue,
  # so a shebang copied in from the file would land mid-script. The scripts use
  # bash-only syntax (`[[ ]]`, arrays), hence bash and not the wrapper's /bin/sh.
  # `name` is passed as $0: without it, a first argument meant for the script
  # would be swallowed by bash as $0 and the script's own $1 would be empty.
  mkScript = { file, name, runtimeInputs }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = ''
        exec ${pkgs.bash}/bin/bash -c ${lib.escapeShellArg (builtins.readFile (../scripts + "/${file}.sh"))} ${lib.escapeShellArg name} "$@"
      '';
    };

  toggleTagBar = mkScript {
    file = "toggle-tag-bar";
    name = "waybar-toggle-tag-bar";
    runtimeInputs = [ pkgs.river-classic pkgs.procps pkgs.util-linux ];
  };
  systemReset = mkScript {
    file = "system-reset";
    name = "waybar-system-reset";
    runtimeInputs = [ pkgs.river-classic pkgs.util-linux ];
  };
  barLaunch = mkScript {
    file = "launch";
    name = "waybar-launch";
    runtimeInputs = [ pkgs.procps pkgs.util-linux ];
  };

  barScripts = pkgs.symlinkJoin {
    name = "waybar-river-scripts";
    paths = [ toggleTagBar systemReset barLaunch ];
  };
in
{
  options.services.waybar-river = {
    enable = lib.mkEnableOption "the river desktop glue for the waybar config";

    extraPackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.playerctl ]";
      description = "Extra packages added to the user profile, so they are on the session PATH for the bar and its scripts.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # river/tags and river/window exist only in river-classic (0.3.x); river
        # 0.4+ dropped zriver_status_manager_v1, and those modules go blank.
        assertion = config.wayland.windowManager.river.package == null
          || lib.getName config.wayland.windowManager.river.package == "river-classic";
        message = ''
          services.waybar-river expects river-classic (river 0.3.x).
          wayland.windowManager.river.package is not river-classic, and the
          river/tags bar module needs zriver_status_manager_v1, which river 0.4+
          removed.
        '';
      }
    ];

    # ---- packages the custom/* scripts shell out to -----------------------
    home.packages = with pkgs; [
      jq              # every custom/* module
      wlrctl          # custom/window: activated toplevel -> app name
      networkmanager  # nmcli        -> custom/wifi
      bluez           # bluetoothctl -> custom/bluetooth
      blueman         # blueman-manager, custom/bluetooth right click
      pavucontrol     # volume module, right click
      libnotify       # battery-critical notification
      river-classic   # riverctl     -> system-reset, toggle-tag-bar
      barScripts
      nerd-fonts.jetbrains-mono   # the glyphs; "JetBrainsMono NFP" in style.css
    ] ++ cfg.extraPackages;

    # Start the bar with the river session, not with graphical-session.target
    # (which a river session never activates).
    programs.waybar.systemd.targets = [ "river-session.target" ];

    # ---- notification daemon: swaync -> mako -----------------------------
    # mako is D-Bus activated and wlroots-native; custom/notify reads its Do Not
    # Disturb *mode*. swaync's service was WantedBy=graphical-session.target in
    # the old setup, which never activates under river - mako avoids that trap by
    # ordering on river-session.target here.
    services.mako = {
      enable = true;
      settings = {
        font = "JetBrainsMono NFP 11";
        background-color = "#1e1e2e";
        text-color = "#cdd6f4";
        border-color = "#313244";
        progress-color = "over #313244";
        border-radius = 10;
        border-size = 2;
        padding = "10";
        margin = "8";
        default-timeout = 6000;
        anchor = "top-right";
        layer = "overlay";
        icons = true;
        max-icon-size = 48;
        markup = true;
        width = 360;
        height = 140;
        # Do Not Disturb: mako has no DND switch, only modes. custom/notify
        # toggles this one (`makoctl mode -t do-not-disturb`).
        "mode=do-not-disturb" = {
          invisible = 1;
        };
        "[urgency=critical]" = {
          border-color = "#f38ba8";
          default-timeout = 0;
        };
      };
    };

    systemd.user.services.mako = {
      Unit = {
        Description = "mako notification daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.mako}";
        ExecReload = "${lib.getExe' pkgs.mako "makoctl"} reload";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "river-session.target" ];
    };

    # ---- river bindings (were hl.bind/hl.exec_once in hyprland.lua) ------
    #
    # `settings` is merged with whatever you set elsewhere, so your own bindings
    # survive unless a key collides. Bindings the nix->riverctl converter cannot
    # represent (combined mods, argument-less commands) belong in
    # `wayland.windowManager.river.extraConfig` instead.
    wayland.windowManager.river.settings = {
      # META+A - hide/show the bar on the current tag
      map.normal."Super A" = "spawn 'waybar-toggle-tag-bar'";
      # META+SHIFT+R - session reset (was custom/sysinfo's click action)
      map.normal."Super Shift R" = "spawn 'waybar-system-reset'";

      # media keys the Hyprland config carried
      map.normal."None XF86AudioRaiseVolume" =
        "spawn 'wpctl set-volume -l 1.2 @DEFAULT_AUDIO_SINK@ 5%+'";
      map.normal."None XF86AudioLowerVolume" =
        "spawn 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-'";
      map.normal."None XF86AudioMute" =
        "spawn 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle'";
      map.normal."None XF86AudioMicMute" =
        "spawn 'wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle'";
      map.normal."None XF86MonBrightnessUp" = "spawn 'brightnessctl set +5%'";
      map.normal."None XF86MonBrightnessDown" = "spawn 'brightnessctl set 5%-'";
    };
  };
}
