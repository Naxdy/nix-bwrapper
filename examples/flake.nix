{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-bwrapper.url = "../";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-bwrapper,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          let
            pkgs = import nixpkgs {
              inherit system;
              overlays = [
                nix-bwrapper.overlays.default
              ];

              # We're packaging mainly unfree apps here.
              config.allowUnfree = true;
            };
          in
          f { inherit pkgs system; }
        );
    in
    {
      # NOTE: These are only examples that may or may not be functional.
      # The packages defined here are not intended to be used as-is, as they may become
      # outdated or lack functionality.
      packages = forAllSystems (
        { pkgs, ... }:
        {
          opencode-wrapped = pkgs.mkBwrapper {
            app = {
              package = pkgs.opencode;
            };
            imports = [
              pkgs.bwrapperPresets.devshell
            ];
            mounts.readWrite = [
              "$HOME/.config/opencode"
              "$HOME/.local/share/opencode"
              "$HOME/.local/state/opencode"
            ];
          };

          librewolf-wrapped = pkgs.mkBwrapper {
            imports = [
              pkgs.bwrapperPresets.desktop
            ];
            app = {
              package = pkgs.librewolf;
              runScript = "librewolf";
            };
            flatpak.manifestFile = pkgs.fetchurl {
              url = "https://raw.githubusercontent.com/flathub/io.gitlab.librewolf-community/550f51a8f4ed02430d217e62ac4d92583b2b30ea/io.gitlab.librewolf-community.json";
              hash = "sha256-QtN4n2btK254Ar2R59ihFc0K2+Uu5Eia05HZnTpw7z4=";
            };
          };

          brave-wrapped = pkgs.mkBwrapper {
            imports = [
              pkgs.bwrapperPresets.desktop
            ];
            app = {
              package = pkgs.brave;
              runScript = "brave";
            };
          };

          lutris-wrapped = pkgs.mkBwrapper ({
            imports = [
              pkgs.bwrapperPresets.desktop
            ];
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
              performDesktopPostInstall = true;
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
            imports = [
              pkgs.bwrapperPresets.desktop
            ];
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
            imports = [
              pkgs.bwrapperPresets.desktop
            ];
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
            imports = [
              pkgs.bwrapperPresets.desktop
            ];
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
    };
}
