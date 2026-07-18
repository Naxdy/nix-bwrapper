{ testers, pkgs }:

let
  seccompProbe = pkgs.stdenv.mkDerivation {
    pname = "seccomp-probe";
    version = "1";
    dontUnpack = true;
    buildPhase = ''
      cc -O2 ${./seccomp-probe.c} -o probe
    '';
    installPhase = ''
      mkdir -p $out/bin
      cp probe $out/bin/probe
    '';
  };

  bwrappedProbe = pkgs.mkBwrapper {
    app = {
      package = seccompProbe;
      runScript = "probe";
    };
  };
in
testers.runNixOSTest {
  name = "nix-bwrapper-seccomp";

  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        environment.systemPackages = [ bwrappedProbe ];
      };
  };

  testScript =
    # python
    ''
      machine.wait_for_unit("default.target")
      result = machine.succeed("seccomp-probe")
      print("=== probe output ===")
      print(result)
      print("====================")

      # All tests from the C probe must pass
      t.assertIn("ALL TESTS PASSED", result,
                 "seccomp probe should pass all tests")

      # Parse the SIGWINCH_BLINKER line: sid != pid means session inherited,
      # which means SIGWINCH from the controlling terminal WILL reach the TUI.
      for line in result.split("\n"):
          if "SIGWINCH_BLINKER" in line:
              parts = line.split()
              sid = int(parts[1].split("=")[1])
              pid = int(parts[3].split("=")[1])
              t.assertTrue(sid != pid,
                  "SIGWINCH propagation: sid (%d) should differ from pid (%d) "
                  "- sandbox inherited the parent session (no setsid)"
                  % (sid, pid))
              print("SIGWINCH_BLINKER: sid=%d != pid=%d -> session inherited" % (sid, pid))
              break
    '';
}
