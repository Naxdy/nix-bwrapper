# Nix-Bwrapper

Nix-Bwrapper is a utility aimed at creating a user-friendly method of sandboxing applications using bubblewrap with
portals support. To do this, bwrapper leverages NixOS' built-in `buildFHSEnv` wrapper.

Key features:

- fully declarative & composable configuration of app permissions
- supports config presets by ways of nixpkgs' module system
  - Nix-Bwrapper also comes with a couple presets out of the box to help get you started
- can pre-configure entire applications based on their Flatpak manifest file

For a list of all available options and their functionality, refer to our
[option search](https://naxdy.github.io/nix-bwrapper/options-search/).

The `examples/flake.nix` contains a few examples with some commonly used (unfree) applications.
