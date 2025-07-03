{ config, lib, ... }:
let
  cfg = config.sockets;
in
{
  options.sockets = {
    x11 = lib.mkOption {
      description = "Whether to bind an X11 socket within the sandbox";
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
    (lib.mkIf cfg.x11 {
      script.preCmds.stage3 = ''
        declare -a x11_socket_binds

        # Try to guess X socket path. This doesn't cover _everything_, but it covers some things.
        if [[ "$DISPLAY" == *:* ]]; then
          # recover display number from $DISPLAY formatted [host]:num[.screen]
          display_nr=''${DISPLAY/#*:} # strip host
          display_nr=''${display_nr/%.*} # strip screen
          local_socket=/tmp/.X11-unix/X$display_nr
          x11_socket_binds+=(--ro-bind-try "$local_socket" "$local_socket")
        fi

        # there shouldn't be more than 1 xauth file, but best to be safe
        declare -a x11_auth_binds
        shopt -s nullglob
        xauth_files=("$XDG_RUNTIME_DIR/xauth_"* "$XDG_RUNTIME_DIR"/.*Xwaylandauth* "$HOME"/.*Xauthority*)
        shopt -u nullglob

        for file in $xauth_files; do
          x11_auth_binds+=(--ro-bind "$file" "$file")
        done
      '';

      app.env = {
        DISPLAY = "$DISPLAY";
      };

      fhsenv.bwrap.additionalArgs = [
        "\"$\{x11_socket_binds[@]\}\""
        "\"$\{x11_auth_binds[@]\}\""
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
