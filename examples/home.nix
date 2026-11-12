# Your Home Manager configuration. This is the whole bar setup: one import and
# one enable. Everything else (packages, mako, river bindings) comes with it.
{ inputs, pkgs, ... }:
{
  imports = [ inputs.waybar-river.homeManagerModules.default ];

  home.username = "USER";
  home.homeDirectory = "/home/USER";
  home.stateVersion = "25.05";

  services.waybar-river.enable = true;

  # River itself. `package` already defaults to pkgs.river-classic; it is spelled
  # out because using pkgs.river instead leaves river/tags blank (river 0.4+
  # dropped the status protocol the module needs).
  wayland.windowManager.river = {
    enable = true;
    package = pkgs.river-classic;

    # Your own river config goes here. The bar adds META+A and META+SHIFT+R and
    # the media keys on top of it; nothing you put here is removed.
    settings = {
      border-width = 2;
      border-color-focused = "0x7aa2f7";
      border-color-unfocused = "0x3b4261";
      default-layout = "rivertile";

      map.normal."Super Return" = "spawn 'kitty'";
      map.normal."Super Q" = "close";
      map.normal."Super J" = "focus-view next";
      map.normal."Super K" = "focus-view previous";
      map.normal."Super Shift J" = "swap next";
      map.normal."Super Shift K" = "swap previous";
      map.normal."Super 1" = "set-focused-tags 1";
      map.normal."Super 2" = "set-focused-tags 2";
      map.normal."Super 3" = "set-focused-tags 4";
      map.normal."Super 4" = "set-focused-tags 8";
      map.normal."Super 5" = "set-focused-tags 16";
      map.normal."Super Shift 1" = "toggle-focused-tags 1";
      map.normal."Super Shift 2" = "toggle-focused-tags 2";
      map.normal."Super Shift 3" = "toggle-focused-tags 4";
      map.normal."Super Shift 4" = "toggle-focused-tags 8";
      map.normal."Super Shift 5" = "toggle-focused-tags 16";

      map-pointer.normal."Super BTN_LEFT" = "move-view";
      map-pointer.normal."Super BTN_RIGHT" = "resize-view";
    };

    # The layout generator has to be running; start it with the session.
    extraConfig = ''
      rivertile -view-padding 4 -outer-padding 4 &
    '';
  };
}
