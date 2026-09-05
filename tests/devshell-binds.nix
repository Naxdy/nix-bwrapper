{ testers, pkgs }:
let
  # Minimal "devshell" style app: forwards its arguments to `bash`, so that the
  # test can inspect the resulting sandbox from within.
  devshellProbe = pkgs.stdenv.mkDerivation {
    pname = "devshell-probe";
    version = "1";
    dontUnpack = true;
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out/bin
      {
        echo '#!/bin/sh'
        echo 'exec bash "$@"'
      } > $out/bin/devshell-probe
      chmod +x $out/bin/devshell-probe
    '';
  };

  bwrappedProbe = pkgs.mkBwrapper {
    imports = [ pkgs.bwrapperPresets.devshell ];

    app = {
      package = devshellProbe;
      runScript = "devshell-probe";
      # the probe needs `bash` within the FHS environment
      addPkgs = [ pkgs.bashInteractive ];
    };
  };
in
testers.runNixOSTest {
  name = "nix-bwrapper-devshell-binds";

  nodes = {
    machine =
      { ... }:
      {
        environment.systemPackages = [ bwrappedProbe ];
      };
  };

  testScript =
    # python
    ''
      import shlex

      PROJ = "/home/alice/project"
      EXTRA = "/home/alice/extra"
      EXTRA2 = "/home/alice/extra2"
      SPACED = "/home/alice/with space"

      machine.wait_for_unit("default.target")
      machine.succeed("install -d -m700 /run/user/0")

      machine.succeed("mkdir -p %s" % " ".join(shlex.quote(d) for d in [PROJ, EXTRA, EXTRA2, SPACED]))
      machine.succeed("echo PROJECT-MARKER > %s/marker" % PROJ)
      machine.succeed("echo HOST-MARKER > %s/marker" % EXTRA)
      machine.succeed("echo SECOND-MARKER > %s/marker" % EXTRA2)
      machine.succeed("echo SPACED-MARKER > %s/marker" % shlex.quote(SPACED))

      # Run `inner` within the sandbox, with `$PWD` set to `cwd`.
      def run(inner, env={}, cwd=PROJ):
          assigns = " ".join("%s=%s" % (k, shlex.quote(v)) for k, v in env.items())
          return "cd %s && %s devshell-probe -c %s" % (cwd, assigns, shlex.quote(inner))

      # --- baseline: without any of the variables, only `$PWD` is exposed
      out = machine.succeed(run("pwd; cat marker; ls -d $HOME/.cache; ls /home/alice"))
      t.assertIn(PROJ, out, "the sandbox should start in the invoking directory")
      t.assertIn("PROJECT-MARKER", out, "$PWD should be bound read-write by the preset")
      t.assertIn("/root/.cache", out, "the preset's persistent sandbox dirs should survive `additionalArgs`")
      t.assertNotIn("HOST-MARKER", out, "extra directories should be hidden without BWRAP_MOUNTS_*")

      # --- BWRAP_MOUNTS_RW: readable, and writes reach the host
      out = machine.succeed(run("cat /home/alice/extra/marker", {"BWRAP_MOUNTS_RW": EXTRA}))
      t.assertIn("HOST-MARKER", out, "BWRAP_MOUNTS_RW should expose the path read-write")

      machine.succeed(run("echo rw-inside >> /home/alice/extra/marker", {"BWRAP_MOUNTS_RW": EXTRA}))
      t.assertIn("rw-inside", machine.succeed("cat %s/marker" % EXTRA),
                 "BWRAP_MOUNTS_RW should permit writes")

      # --- BWRAP_MOUNTS_RO: readable, but writes are refused
      out = machine.succeed(run("cat /home/alice/extra/marker", {"BWRAP_MOUNTS_RO": EXTRA}))
      t.assertIn("HOST-MARKER", out, "BWRAP_MOUNTS_RO should expose the path read-only")

      machine.fail(run("echo ro-inside >> /home/alice/extra/marker", {"BWRAP_MOUNTS_RO": EXTRA}))
      t.assertNotIn("ro-inside", machine.succeed("cat %s/marker" % EXTRA),
                    "BWRAP_MOUNTS_RO should not permit writes")

      # --- both variables at once, colon-separated, with leading, trailing and
      #     consecutive separators
      markers = " ".join(shlex.quote(p + "/marker") for p in [EXTRA, EXTRA2, SPACED])
      out = machine.succeed(run(
          "cat " + markers,
          {
              "BWRAP_MOUNTS_RO": ":/home/alice/extra:/home/alice/extra2::",
              "BWRAP_MOUNTS_RW": "%s:" % SPACED,
          },
      ))
      for marker in ["HOST-MARKER", "SECOND-MARKER", "SPACED-MARKER"]:
          t.assertIn(marker, out, "%s should be visible via a colon-separated list" % marker)

      # paths containing spaces stay a single argument, and relative paths are
      # canonicalized against the invoking directory
      out = machine.succeed(run('cat "/home/alice/with space/marker"', {"BWRAP_MOUNTS_RW": SPACED}))
      t.assertIn("SPACED-MARKER", out, "paths containing spaces should not be word-split")

      out = machine.succeed(run("cat /home/alice/extra/marker", {"BWRAP_MOUNTS_RO": "../extra"}))
      t.assertIn("HOST-MARKER", out, "'../extra' should resolve to /home/alice/extra")

      # an empty variable is a no-op rather than a broken invocation
      out = machine.succeed(run("echo EMPTY-OK", {"BWRAP_MOUNTS_RW": "", "BWRAP_MOUNTS_RO": ""}))
      t.assertIn("EMPTY-OK", out, "empty BWRAP_MOUNTS_* should still launch the app")

      # --- garbled input: the value is handed to bwrap as one literal path,
      #     and never re-evaluated or split into further arguments.
      # `stdout` excludes bwrap's stderr, so it stays empty whenever the app
      # did not actually get as far as executing `inner`.
      def garbled(value):
          cmd = run("echo SHOULD-NOT-RUN", {"BWRAP_MOUNTS_RO": value})
          status, stdout = machine.execute(cmd)
          ignored, err = machine.execute(cmd + " 2>&1")
          return status, stdout.strip(), err

      status, stdout, err = garbled("%s --tmpfs /home/alice" % EXTRA)
      t.assertEqual(status, 1, "an unresolvable path should abort the sandbox")
      t.assertEqual(stdout, "", "the app should not run when its mount is invalid")
      t.assertIn("extra --tmpfs /home/alice", err,
                 "the whole value should be kept as a single mount path")

      status, stdout, err = garbled("%s; echo INJECTED" % EXTRA)
      t.assertEqual(status, 1, "a path with a trailing command should abort the sandbox")
      t.assertEqual(stdout, "", "the trailing command should not be executed")
      t.assertIn("extra; echo INJECTED", err, "the value should stay a single literal path")

      status, stdout, err = garbled("$(echo INJECTED)")
      t.assertEqual(status, 1, "an unexpanded substitution should abort the sandbox")
      t.assertEqual(stdout, "", "the substitution should not be evaluated")
      t.assertIn("/home/alice/project/$(echo INJECTED)", err,
                 "the substitution should be resolved relative to $PWD")

      # relative entries are resolved against `$PWD`, not against `/`
      status, stdout, err = garbled("sub")
      t.assertEqual(status, 1, "a missing relative path should abort the sandbox")
      t.assertIn("/home/alice/project/sub", err, "relative paths should resolve against $PWD")

      print("devshell bind test passed")
    '';
}
