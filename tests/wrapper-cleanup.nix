{ testers, pkgs }:
let
  devshellProbe = import ./probe.nix { inherit pkgs; };

  # DBus forwarding starts `xdg-dbus-proxy` inside a background `bwrap` for both
  # the session and the system bus. Those helpers are what the wrapper's
  # `trap ... EXIT` has to reap.
  bwrappedDbusProbe = pkgs.mkBwrapper {
    app = {
      package = devshellProbe;
      runScript = "devshell-probe";
      # the probe needs `bash` within the FHS environment
      addPkgs = [ pkgs.bashInteractive ];
    };

    # the wrapper enters the sandbox with `--chdir "$PWD"`
    mounts.readWrite = [ "$PWD" ];

    dbus.enable = true;
  };
in
testers.runNixOSTest {
  name = "nix-bwrapper-wrapper-cleanup";

  nodes = {
    machine =
      { ... }:
      {
        services.dbus.enable = true;

        environment.systemPackages = [ bwrappedDbusProbe ];
      };
  };

  testScript =
    # python
    ''
      import shlex

      PROJ = "/home/alice/project"
      APP_DIR = "/run/user/0/app/nix.bwrapper.devshell_probe"
      BUS = "unix:path=/run/dbus/system_bus_socket"

      machine.wait_for_unit("default.target")
      machine.wait_for_unit("dbus.socket")
      machine.succeed("install -d -m700 /run/user/0")
      machine.succeed("mkdir -p %s" % PROJ)

      # The proxies bind their sockets below `$XDG_RUNTIME_DIR`, and a compound
      # command line means the wrapper is not necessarily the leader of its own
      # process group.
      launch = "cd %s && XDG_RUNTIME_DIR=/run/user/0 DBUS_SESSION_BUS_ADDRESS=%s devshell-probe -c %s" % (
          PROJ,
          shlex.quote(BUS),
          shlex.quote('echo APP-RAN; ls "$XDG_RUNTIME_DIR/bus"'),
      )

      status, out = machine.execute(launch + " 2>&1")
      t.assertEqual(status, 0, "the app should launch with dbus forwarding enabled: %s" % out)
      t.assertIn("APP-RAN", out, "the app should run")
      t.assertIn("bus", out, "the sandbox should see the forwarded session bus")
      t.assertNotIn("No such process", out, "the exit trap should not complain about its process group")

      # the proxies keep their sockets around after being reaped, so this only
      # proves that they were started for this launch
      t.assertIn("bus_system", machine.succeed("ls %s" % APP_DIR),
                 "the system bus proxy should have created its socket")

      _, leftover = machine.execute("sleep 0.5; pgrep xdg-dbus-proxy || echo NO-LEFTOVER")
      t.assertIn("NO-LEFTOVER", leftover, "the dbus proxies should die together with the app")

      print("wrapper cleanup test passed")
    '';
}
