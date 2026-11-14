# The system half. Everything here needs root; the bar itself does not.
#
# This is the NixOS equivalent of what scripts/first_time_setup.sh used to do
# with pacman + systemctl on Arch.
{ pkgs, inputs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "HOSTNAME";
  networking.networkmanager.enable = true;   # nmcli -> custom/wifi

  hardware.bluetooth.enable = true;          # bluetoothctl -> custom/bluetooth
  hardware.bluetooth.powerOnBoot = true;

  # ---- graphical session ------------------------------------------------
  # River is a Wayland compositor, so X isn't the session, but a display manager
  # and Xwayland still want it.
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.displayManager.defaultSession = "river";

  # river-classic advertises providedSessions = [ "river" ], so registering it
  # here is what makes it appear in the session list.
  services.displayManager.sessionPackages = [ pkgs.river-classic ];

  # ---- modules that need a system service ------------------------------
  services.upower.enable = true;                 # battery module
  services.power-profiles-daemon.enable = true;  # power-profiles-daemon module
  hardware.acpilight.enable = true;              # backlight module (/sys/class/backlight)

  # Rust/zig compositor talks to the GPU directly
  hardware.graphics.enable = true;

  # ---- fonts -------------------------------------------------------------
  # JetBrainsMono NFP is installed per-user by services.waybar-river; nothing to
  # do here unless you want the glyph font system-wide too.
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # ---- home manager ------------------------------------------------------
  # Only needed when Home Manager is wired up as a NixOS module - see
  # examples/flake.nix, Option A.
  imports = [ inputs.home-manager.nixosModules.home-manager ];
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit inputs; };
  home-manager.users.USER = import ./home.nix;

  users.users.USER = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    shell = pkgs.bash;
  };

  system.stateVersion = "25.05";
}
