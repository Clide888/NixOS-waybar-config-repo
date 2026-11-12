# Copy this next to your configuration.nix / home.nix.
#
# Replace HOSTNAME and USER with yours, e.g.
#   nixosConfigurations.nixos = ...
#   homeConfigurations."you@nixos" = ...
#
# The waybar-river input points at the branch this work lives on. Once it is
# merged to main, shorten it to:
#   url = "github:Clide888/NixOS-waybar-config-repo";
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    waybar-river = {
      url = "github:Clide888/NixOS-waybar-config-repo/arena/f4451ba9-nixos-waybar-config-repo";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      # ---- Option A: Home Manager as a NixOS module (recommended) --------
      nixosConfigurations.HOSTNAME = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.USER = import ./home.nix;
          }
        ];
      };

      # ---- Option B: standalone Home Manager ---------------------------
      # `home-manager switch --flake .#USER@HOSTNAME`
      homeConfigurations."USER@HOSTNAME" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./home.nix ];
      };
    };
}
