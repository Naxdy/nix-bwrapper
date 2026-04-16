{
  description = "A user-friendly method of sandboxing applications using bubblewrap with portals support.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    nuschtosSearch = {
      url = "github:NuschtOS/search/v0.1.0";

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

            mdbook-admonish = pkgs.mdbook-admonish.overrideAttrs (old: {
              patches = (old.patches or [ ]) ++ [
                # mdbook 0.5 compatibility
                (pkgs.fetchpatch2 {
                  url = "https://github.com/tommilligan/mdbook-admonish/commit/f67dc47c24bc48dada3ae4decf055fdd6ba4a4ed.patch";
                  hash = "sha256-xSEtwDXUiGYwALQKyz1kqqaeqmyG2gTD9BLX0NQSxt8=";
                })
              ];

              cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
                inherit (mdbook-admonish) src name patches;
                hash = "sha256-FQo58eT9SyO5bhuoRQOAfBcAi1acBOPjYH6WUtiJPIE=";
              };
            });
          in
          f {
            inherit
              mdbook-admonish
              pkgs
              system
              treefmtEval
              ;
          }
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
            bwrapperPresetsMeta = bwrapperLib.presets-meta;
          };

        forPkgs = pkgs: import ./modules { inherit pkgs nixpkgs; };
      };

      formatter = forEachSupportedSystem ({ treefmtEval, ... }: treefmtEval.config.build.wrapper);

      devShells = forEachSupportedSystem (
        {
          mdbook-admonish,
          pkgs,
          treefmtEval,
          ...
        }:
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [
              pkgs.mdbook
              mdbook-admonish
              treefmtEval.config.build.wrapper
            ];
          };
        }
      );

      packages = forEachSupportedSystem (
        {
          mdbook-admonish,
          pkgs,
          system,
          ...
        }:
        let
          bwrapperLib = self.lib.forPkgs pkgs;
        in
        {
          optionsDoc = bwrapperLib.options-json;

          search = nuschtosSearch.packages.${system}.mkSearch {
            optionsJSON = (self.lib.forPkgs pkgs).options-json + "/share/doc/nixos/options.json";
            urlPrefix = "https://github.com/Naxdy/nix-bwrapper/tree/main/";
            title = "Nix Bwrapper Options Search";
            baseHref = "/nix-bwrapper/options-search/";
          };

          docs = pkgs.callPackage ./docs {
            inherit mdbook-admonish;
            bwrapperVersion = "1.1.0";
          };

          gh-pages =
            let
              searchForGh = pkgs.runCommandLocal "search" { } ''
                mkdir -p $out
                ln -s ${self.packages.${system}.search} $out/options-search
              '';
            in
            pkgs.symlinkJoin {
              name = "nix-bwrapper-pages";
              paths = [
                searchForGh
                self.packages.${system}.docs
              ];
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
            bwrapperPresetsMeta
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
        {
          pkgs,
          treefmtEval,
          system,
          ...
        }:
        {
          inherit (self.packages.${system}) gh-pages docs;

          formatting = treefmtEval.config.build.check self;

          # note that `pkgs` already includes the overlay we need

          hello-bwrapper = pkgs.callPackage ./tests/hello.nix { };

          hello-bwrapper-override = pkgs.callPackage ./tests/hello-override.nix { };
        }
      );
    };
}
