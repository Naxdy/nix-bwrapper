{ pkgs, nixpkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "nix-bwrapper-graphical";

  enableOCR = true;

  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        imports = [
          "${nixpkgs}/nixos/tests/common/x11.nix"
          "${nixpkgs}/nixos/tests/common/user-account.nix"
        ];

        environment.variables."XAUTHORITY" = "/home/alice/.Xauthority";

        environment.variables."XDG_RUNTIME_DIR" = "/run/user/1000";

        test-support.displayManager.auto.user = "alice";

        environment.systemPackages = [
          pkgs.gnugrep
          (pkgs.mkBwrapper {
            app = {
              package = pkgs.nedit;
              runScript = "nedit";
            };

            fhsenv.skipExtraInstallCmds = true;
            flatpak.enable = false;
            dbus.enable = false;

            mounts = {
              readWrite = [
                "/home/alice/Shared"
              ];
            };

            sockets = {
              x11 = true;

              # we have no wayland or audio in the VM
              wayland = false;
              pipewire = false;
              pulseaudio = false;
            };
          })
        ];
      };
  };

  testScript = ''
    import shlex

    machine.wait_for_unit("default.target")

    machine.wait_for_x()

    # Run as user alice
    def ru(cmd):
        return "su - alice -c " + shlex.quote(cmd)

    def launch_editor(arg = ""):
      machine.succeed(ru(f"nedit {arg} >&2 & disown"))

    machine.succeed(ru("mkdir -p /home/alice/Secret && echo 'grass touched' > /home/alice/Secret/grass"))
    machine.succeed(ru("mkdir -p /home/alice/Shared && echo 'grass touched' > /home/alice/Shared/grass"))

    launch_editor()

    machine.wait_for_text("Untitled")

    machine.send_key("ctrl-q")

    # confirm we can read & write to shared file
    launch_editor("/home/alice/Shared/grass")

    machine.wait_for_text("grass touched")

    machine.send_chars(" hard")
    machine.send_key("ctrl-s")
    machine.send_key("ctrl-q")

    machine.succeed(ru("cat /home/alice/Shared/grass | grep hard"))

    # confirm we cannot read secret file
    launch_editor("/home/alice/Secret/grass")

    machine.wait_for_text("unavailable")
  '';
}
