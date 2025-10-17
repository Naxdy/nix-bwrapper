{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "nix-bwrapper-hello";
  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        environment.systemPackages = [
          (pkgs.mkBwrapper {
            app = {
              package = pkgs.hello;
              runScript = "hello";
            };

            # disable things not needed by cli apps or not available
            flatpak.enable = false;
            fhsenv.skipExtraInstallCmds = true;
            dbus.enable = false;
            sockets = {
              x11 = false;
              wayland = false;
              pipewire = false;
              pulseaudio = false;
            };
          })
        ];
      };
  };

  testScript = ''
    machine.wait_for_unit("default.target")

    machine.succeed("hello")
  '';
}
