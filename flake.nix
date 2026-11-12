{
  description = "Catppuccin waybar config for river-classic (river 0.3) on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, home-manager }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      # Home Manager module: `imports = [ waybar-river.homeManagerModules.default ];`
      homeManagerModules = {
        default = self.homeManagerModules.waybar-river;
        waybar-river = import ./modules/default.nix;
      };

      # A complete example configuration, so the module can be evaluated and
      # built without guessing: `nix build .#example.home-manager.activationPackage`
      # (or `nix build .#checks.x86_64-linux/example-...`).
      checks = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          example = home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [
              self.homeManagerModules.default
              {
                home.username = "example";
                home.homeDirectory = "/home/example";
                home.stateVersion = "25.05";
                services.waybar-river.enable = true;
                wayland.windowManager.river = {
                  enable = true;
                  # River's own config is managed elsewhere; this keeps the
                  # example from writing an init file over the user's.
                  package = null;
                };
              }
            ];
          };
        }
      );
    };
}
