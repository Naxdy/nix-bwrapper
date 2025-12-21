{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.sockets;
in
{
  options.sockets = {
    x11 = lib.mkOption {
      description = ''
        Whether to bind an X11 socket using [xwayland-satellite](https://github.com/Supreeeme/xwayland-satellite).
        This spawns a unique xorg server per sandboxed application, and does not require your compositor to support xwayland
      '';
      default = true;
      type = lib.types.bool;
    };
    wayland = lib.mkOption {
      description = "Whether to bind a Wayland socket within the sandbox";
      default = true;
      type = lib.types.bool;
    };
    pipewire = lib.mkOption {
      description = "Whether to bind a Pipewire socket within the sandbox";
      default = true;
      type = lib.types.bool;
    };
    pulseaudio = lib.mkOption {
      description = "Whether to bind a Pulseaudio socket within the sandbox";
      default = true;
      type = lib.types.bool;
    };
    cups = lib.mkOption {
      description = "Whether to bind a cups socket withihn the sandbox";
      default = false;
      type = lib.types.bool;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.pulseaudio {
      runtime.binds = [
        "pulse"
      ];

      fhsenv.bwrap.additionalArgs = [
        ''--ro-bind-try "$XDG_RUNTIME_DIR/pulse" "$XDG_RUNTIME_DIR/pulse"''
      ];
    })
    (lib.mkIf cfg.wayland {
      script.preCmds.stage3 = ''
        declare -a wayland_binds
        wayland_sockets=$(ls "$XDG_RUNTIME_DIR/wayland-"*)

        for file in $wayland_sockets; do
          wayland_binds+=(--ro-bind "$file" "$file")
        done
      '';

      app.env = {
        WAYLAND_DISPLAY = "$WAYLAND_DISPLAY";
      };

      fhsenv.bwrap.additionalArgs = [
        "\"$\{wayland_binds[@]\}\""
      ];
    })
    (lib.mkIf cfg.pipewire {
      script.preCmds.stage3 = ''
        declare -a pipewire_binds
        pipewire_sockets=$(ls "$XDG_RUNTIME_DIR/pipewire-"*)

        for file in $pipewire_sockets; do
          pipewire_binds+=(--ro-bind "$file" "$file")
        done
      '';

      fhsenv.bwrap.additionalArgs = [
        "\"$\{pipewire_binds[@]\}\""
      ];
    })
    (lib.mkIf cfg.x11 {
      assertions = [
        {
          assertion = cfg.wayland;
          message = "Enabling X11 support via `xwayland-satellite` requires a wayland socket to be available in the sandbox";
        }
      ];

      script.preCmds.stage1 = ''
        test -d "$XDG_RUNTIME_DIR/bwrapper/by-app/${config.app.id}/X11" || mkdir -p "$XDG_RUNTIME_DIR/bwrapper/by-app/${config.app.id}/X11"
      '';

      # notes:
      # - using display 99 is arbitrary, to make it less likely to conflict with other X11 sockets
      # - we need to unshare net, because otherwise xwayland-satellite will listen on localhost, breaking sandboxing
      script.preCmds.stage2 = ''
        setup_xwayland_satellite() {
          ${pkgs.bubblewrap}/bin/bwrap \
            --unshare-user \
            --unshare-cgroup \
            --unshare-pid \
            --unshare-ipc \
            --unshare-net \
            --new-session \
            --ro-bind "/nix/store" "/nix/store" \
            --bind "/run" "/run" \
            --ro-bind "/sys" "/sys" \
            --dev-bind "/dev" "/dev" \
            --ro-bind "/etc" "/etc" \
            --bind "$XDG_RUNTIME_DIR/bwrapper/by-app/${config.app.id}/X11" "/tmp/.X11-unix" \
            ${lib.optionalString config.flatpak.enable ''--ro-bind "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info" "/.flatpak-info"''} \
            --die-with-parent \
            --unsetenv DISPLAY \
            "''${wayland_binds[@]}" \
            -- \
            ${pkgs.xwayland-satellite}/bin/xwayland-satellite :99
        }

        setup_xwayland_satellite &
      '';

      fhsenv.bwrap.additionalArgs = [
        "--bind \"$XDG_RUNTIME_DIR/bwrapper/by-app/${config.app.id}/X11\" \"/tmp/.X11-unix\""
        "--setenv DISPLAY :99"
      ];
    })
    (lib.mkIf cfg.cups {
      fhsenv.bwrap.additionalArgs = [
        ''--ro-bind-try "/run/cups/cups.sock" "/run/cups/cups.sock"''
      ];
    })
  ];
}
