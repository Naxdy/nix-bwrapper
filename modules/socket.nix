{ config, lib, ... }:
let
  cfg = config.sockets;
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "sockets" "x11" ] ''
      The X11 socket option has been removed due to its ability for sandbox escape.
      A new implementation using `xwayland-satellite` is underway.
      For more information, see https://github.com/Naxdy/nix-bwrapper/pull/16'')
  ];

  options.sockets = {
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
  ];
}
