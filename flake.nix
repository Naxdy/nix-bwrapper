{
  description = "A user-friendly method of sandboxing applications using bubblewrap with portals support.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    nuschtosSearch.url = "github:NuschtOS/search";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nuschtosSearch,
    }:
    (flake-utils.lib.eachDefaultSystem (
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
      in
      {
        lib = import ./modules { inherit pkgs nixpkgs; };

        packages.optionsDoc = self.lib.${system}.options-json;

        packages.search = nuschtosSearch.packages.${system}.mkSearch {
          optionsJSON = self.lib.${system}.options-json + "/share/doc/nixos/options.json";
          urlPrefix = "https://github.com/Naxdy/nix-bwrapper/tree/main/";
          title = "Nix Bwrapper Options Search";
          baseHref = "/nix-bwrapper/";
        };

        packages.brave-wrapped = pkgs.mkBwrapper {
          app = {
            package = pkgs.brave;
            runScript = "brave";
          };
        };

        packages.lutris-wrapped = pkgs.mkBwrapper ({
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
            logging = true;
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

        packages.bottles-wrapped = pkgs.mkBwrapper {
          app = {
            package = pkgs.bottles;
            # needed because `pkgs.bottles` is a `symlinkJoin`
            package-unwrapped = pkgs.bottles-unwrapped;
            isFhsenv = true;
          };
          dbus.system.talks = [
            "org.freedesktop.UDisks2"
          ];
          dbus.session.owns = [
            "com.usebottles.bottles"
          ];
        };

        packages.slack-wrapped = pkgs.mkBwrapper {
          app = {
            package = pkgs.slack;
            runScript = "slack";
            execArgs = "-s %U";
            addPkgs = [
              pkgs.libdbusmenu # to make global menu work in KDE
            ];
          };
          dbus.system.talks = [
            "org.freedesktop.UPower"
            "org.freedesktop.login1"
          ];
          dbus.session.talks = [
            "org.kde.kwalletd6"
            "org.freedesktop.secrets"
            "org.kde.kwalletd5"
          ];
        };

        packages.discord-wrapped = pkgs.mkBwrapper {
          app = {
            package = pkgs.discord;
            runScript = "discord";
            id = "com.discordapp.Discord";
          };
          mounts = {
            readWrite = [
              "$XDG_RUNTIME_DIR/app/com.discordapp.Discord"
            ];
          };
          dbus.session.owns = [
            "com.discordapp.Discord"
          ];
        };
      }
    ))
    // {
      nixosModules.default = {
        nixpkgs.overlays = [ self.overlays.default ];
      };

      overlays.default = final: prev: {
        mkBwrapper =
          (import ./modules {
            pkgs = final;
            inherit nixpkgs;
          }).bwrapper;

        bwrapper = builtins.throw "`bwrapper` has been replaced by a unified module-based system available under `mkBwrapper`";

        bwrapperFHSEnv = builtins.throw "`bwrapperFHSEnv` has been replaced by a unified module-based system available under `mkBwrapper`";
      };
    };
}
