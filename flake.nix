{
  description = "A user-friendly method of sandboxing applications using bubblewrap with portals support.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }: (flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.default
        ];
      };
    in
    {
      packages.brave-wrapped = pkgs.bwrapper {
        pkg = pkgs.brave;
        appId = "com.brave.Browser";
        runScript = "brave";
      };
    })) // {
    overlays.default = final: prev: {
      bwrapper = final.callPackage ./bwrapper.nix { };
    };
  };
}
