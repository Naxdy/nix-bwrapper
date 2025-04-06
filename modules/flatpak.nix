{ config, lib, ... }:
let
  cfg = config.flatpak;
in
{
  options.flatpak = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable certain tricks to make the sandboxed app think it's being run as a flatpak. This is required for portals to work.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.enable -> config.dbus.enable;
        message = "Flatpak emulation will do nothing without forwarding the required DBus interfaces.";
      }
    ];

    fhsenv.bwrap.additionalArgs = [
      "--ro-bind \"$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info\" \"/.flatpak-info\""
    ];

    # HACK: To make most flatpak apps function correctly, we need a fake `.flatpak-info` file at
    # the root of the sandbox. Additionally, we need a fake `bwrapinfo.json` file in the host
    # system. Don't yet know if the values in there should be something sensible, for now just
    # setting everything to `1` seems to work fine.
    script.preCmds.stage1 = ''
      test -f "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info" && rm "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info"
      printf "[Application]\nname=${config.app.id}\n\n[Instance]\ninstance-id = 0\nsystem-bus-proxy = true\nsession-bus-proxy = true\n" > "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info"

      mkdir -p "$XDG_RUNTIME_DIR/.flatpak/0"
      printf '{"child-pid": 1, "mnt-namespace": 1, "net-namespace": 1, "pid-namespace": 1}' > "$XDG_RUNTIME_DIR/.flatpak/0/bwrapinfo.json"
    '';
  };
}
