# Entry point for `imports = [ ... ]`.
#
# Pulling in both modules keeps the split deliberate: waybar-config.nix is the
# bar, waybar-river.nix is the desktop glue around it (packages, mako, river
# bindings). Import only the first if you want the bar without the opinions.
{
  imports = [
    ./waybar-config.nix
    ./waybar-river.nix
  ];
}
