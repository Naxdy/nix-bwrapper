{
  description = "A user-friendly method of sandboxing applications using bubblewrap with portals support.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    nuschtosSearch = {
      url = "github:NuschtOS/search";

      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";

      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nuschtosSearch,
      treefmt-nix,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;

              overlays = [
                self.overlays.default
              ];
            };

            treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
          in
          f { inherit pkgs system treefmtEval; }
        );
    in
    {
      lib = {
        mkNixBwrapper =
          pkgs:
          let
            bwrapperLib = (self.lib.forPkgs pkgs);
            bwrapperEval = (bwrapperLib).bwrapperEval;
          in
          {
            inherit bwrapperEval;

            mkBwrapper = mod: (bwrapperEval mod).config.build.package;

            mkBwrapperFHSEnv =
              mod:
              (bwrapperEval {
                imports = [ mod ];
                app = {
                  package = null;
                  isFhsenv = true;
                };
              }).config.build.fhsenv;

            bwrapperPresets = bwrapperLib.presets;
          };

        forPkgs = pkgs: import ./modules { inherit pkgs nixpkgs; };
      };

      formatter = forEachSupportedSystem ({ treefmtEval, ... }: treefmtEval.config.build.wrapper);

      devShells = forEachSupportedSystem (
        { pkgs, treefmtEval, ... }:
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [
              treefmtEval.config.build.wrapper
            ];
          };
        }
      );

      packages = forEachSupportedSystem (
        { pkgs, system, ... }:
        let
          bwrapperLib = self.lib.forPkgs pkgs;
        in
        {
          optionsDoc = bwrapperLib.options-json;

          search = nuschtosSearch.packages.${system}.mkSearch {
            optionsJSON = (self.lib.forPkgs pkgs).options-json + "/share/doc/nixos/options.json";
            urlPrefix = "https://github.com/Naxdy/nix-bwrapper/tree/main/";
            title = "Nix Bwrapper Options Search";
            baseHref = "/nix-bwrapper/";
          };
        }
      );

      overlays.default = self.overlays.bwrapper;

      overlays.bwrapper =
        final: prev:
        let
          bwrapperLib = self.lib.mkNixBwrapper final;
        in
        {
          inherit (bwrapperLib)
            bwrapperEval
            mkBwrapper
            mkBwrapperFHSEnv
            bwrapperPresets
            ;

          bwrapper = builtins.throw "`bwrapper` has been replaced by a unified module-based system available under `mkBwrapper`";

          bwrapperFHSEnv = builtins.throw "`bwrapperFHSEnv` has been replaced by a unified module-based system available under `mkBwrapper`";
        };

      nixosModules.default = self.nixosModules.bwrapper;

      nixosModules.bwrapper =
        { ... }:
        {
          nixpkgs.overlays = [
            self.overlays.bwrapper
          ];
        };

      checks = forEachSupportedSystem (
        { pkgs, treefmtEval, ... }:
        {
          formatting = treefmtEval.config.build.check self;

          # note that `pkgs` already includes the overlay we need

          hello-bwrapper = import ./tests/hello.nix {
            inherit pkgs;
          };
        }
      );
    };
}
