# TODO: unfortunately, in this setup we have problems
# with ambient capabilities, causing bwrap to fail to run :(
{ pkgs, nixpkgs, ... }:
let
  konsole-wrapped = pkgs.mkBwrapper {
    app = {
      package = pkgs.kdePackages.konsole;
      runScript = "konsole";
    };

    fhsenv.opts = {
      unshareUser = false;
      unshareIpc = false;
    };

    fhsenv.skipExtraInstallCmds = true;
    flatpak.enable = false;
    dbus.enable = false;

    mounts.readWrite = [
      "/home/alice/Shared"
    ];

    sockets = {
      wayland = true;

      # we have no audio in the VM
      pipewire = false;
      pulseaudio = false;
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "nix-bwrapper-graphical";

  enableOCR = true;

  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        imports = [
          "${nixpkgs}/nixos/tests/common/wayland-cage.nix"
        ];

        systemd.services.prepareDirs = {
          wantedBy = [ "multi-user.target" ];
          script = ''
            mkdir -p /home/alice/{Secret,Shared}
            chown -R alice /home/alice
          '';
        };

        environment.variables.DISPLAY = "do not use";

        environment.systemPackages = [
          pkgs.gnugrep
          konsole-wrapped
        ];
      };
  };

  testScript =
    # python
    ''
      import shlex

      start_all()
      machine.wait_for_unit("graphical.target")

      machine.wait_for_text("alice@machine", 10)
      machine.send_chars("konsole\n", 0.25)
      machine.wait_for_text("alice@machine", 10)

      # Run as user alice
      def ru(cmd):
          return "su - alice -c " + shlex.quote(cmd)

      machine.succeed(ru("echo 'secrets touched' > /home/alice/Secret/grass"))
      machine.succeed(ru("echo 'grass touched' > /home/alice/Shared/grass"))

      # confirm we can read & write to shared file
      machine.send_chars("cat ~/Shared/grass\n", 0.25)
      machine.wait_for_text("grass touched", 10)
      machine.send_chars("echo hard >> ~/Shared/grass\n", 0.25)
      machine.succeed(ru("cat /home/alice/Shared/grass | grep hard"))

      # confirm we cannot read secret file
      machine.send_chars("cat ~/Secret/grass\n", 0.25)

      machine.wait_for_text("No such file or directory", 10)
    '';
}
