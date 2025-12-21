{
  description = "A user-friendly method of sandboxing applications using bubblewrap with portals support.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    nuschtosSearch.url = "github:NuschtOS/search";

    treefmt-nix.url = "github:numtide/treefmt-nix";
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
        "x86_64-darwin"
        "aarch64-darwin"
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

              # needed for the example packages
              config.allowUnfreePredicate =
                pkg:
                builtins.elem (pkgs.lib.getName pkg) [
                  "steam"
                  "steam-unwrapped"
                  "discord"
                  "slack"
                ];
            };

            treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
          in
          f { inherit pkgs system treefmtEval; }
        );
    in
    {
      lib = forEachSupportedSystem ({ pkgs, ... }: import ./modules { inherit pkgs nixpkgs; });

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

      # NOTE: These are only examples that may or may not be functional.
      # The packages defined here are not intended to be used as-is, as they may become
      # outdated or lack functionality.
      packages = forEachSupportedSystem (
        { pkgs, system, ... }:
        {
          optionsDoc = self.lib.${system}.options-json;

          search = nuschtosSearch.packages.${system}.mkSearch {
            optionsJSON = self.lib.${system}.options-json + "/share/doc/nixos/options.json";
            urlPrefix = "https://github.com/Naxdy/nix-bwrapper/tree/main/";
            title = "Nix Bwrapper Options Search";
            baseHref = "/nix-bwrapper/";
          };

          brave-wrapped = pkgs.mkBwrapper {
            app = {
              package = pkgs.brave;
              runScript = "brave";
            };
          };

          lutris-wrapped = pkgs.mkBwrapper ({
            app = {
              package = pkgs.lutris;
              isFhsenv = true;
              id = "net.lutris.Lutris";
              env = {
                WEBKIT_DISABLE_DMABUF_RENDERER = 1;
                APPIMAGE_EXTRACT_AND_RUN = 1;
              };
            };
            fhsenv = {
              skipExtraInstallCmds = false;
            };
            dbus = {
              session = {
                talks = [
                  "org.freedesktop.Flatpak"
                  "org.kde.StatusNotifierWatcher"
                  "org.kde.KWin"
                  "org.gnome.Mutter.DisplayConfig"
                  "org.freedesktop.ScreenSaver"
                ];
                owns = [
                  "net.lutris.Lutris"
                ];
              };
              system = {
                talks = [
                  "org.freedesktop.UDisks2"
                ];
              };
            };
            mounts = {
              read = [
                "$HOME/.config/kdedefaults"
                "$HOME/.local/share/color-schemes"
              ];
              readWrite = [
                "$HOME/.steam"
                "$HOME/.local/share/steam"
                "$HOME/.local/share/applications"
                "$HOME/.local/share/desktop-directories"
                "$HOME/Games"
              ];
            };
          });

          bottles-wrapped = pkgs.bottles.override {
            # need to override it like this because `pkgs.bottles` is a `symlinkJoin`
            buildFHSEnv = pkgs.mkBwrapperFHSEnv {
              app = {
                package-unwrapped = pkgs.bottles-unwrapped;
                id = "com.usebottles.bottles";
              };
              dbus.system.talks = [
                "org.freedesktop.UDisks2"
              ];
              dbus.session.owns = [
                "com.usebottles.bottles"
              ];
            };
          };

          slack-wrapped = pkgs.mkBwrapper {
            app = {
              package = pkgs.slack;
              runScript = "slack";
              execArgs = "-s %U";
              addPkgs = [
                pkgs.libdbusmenu
              ];
            };
            mounts.readWrite = [
              "$HOME/Downloads"
            ];
            dbus.system.talks = [
              "org.freedesktop.UPower"
              "org.freedesktop.login1"
            ];
            dbus.session.talks = [
              "org.kde.kwalletd6"
              "org.freedesktop.secrets"
              "org.kde.kwalletd5"
              "org.kde.StatusNotifierWatcher"
              "org.freedesktop.ScreenSaver"
              "org.freedesktop.Notifications"
            ];
            dbus.session.owns = [
              "com.slack.slack"
            ];
          };

          discord-wrapped = pkgs.mkBwrapper {
            app = {
              package = pkgs.discord;
              runScript = "discord";
              env = {
                ELECTRON_TRASH = "gio";
              };
            };
            mounts.readWrite = [
              "$XDG_RUNTIME_DIR/app/com.discordapp.Discord"
              "$XDG_RUNTIME_DIR/speech-dispatcher"
              "$HOME/Downloads"
            ];
            dbus.session.talks = [
              "org.freedesktop.ScreenSaver"
              "org.kde.StatusNotifierWatcher"
              "com.canonical.AppMenu.Registrar"
              "com.canonical.indicator.application"
              "com.canonical.Unity"
            ];
            dbus.system.talks = [
              "org.freedesktop.UPower"
            ];
            dbus.session.owns = [
              "com.discordapp.Discord"
            ];
          };
        }
      );

      overlays.default = self.overlays.bwrapper;

      overlays.bwrapper = final: prev: {
        bwrapperEval =
          (import ./modules {
            pkgs = final;
            inherit nixpkgs;
          }).bwrapperEval;

        mkBwrapper = mod: (final.bwrapperEval mod).config.build.package;

        mkBwrapperFHSEnv =
          mod:
          (final.bwrapperEval {
            imports = [ mod ];
            app = {
              package = null;
              isFhsenv = true;
            };
          }).config.build.fhsenv;

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
