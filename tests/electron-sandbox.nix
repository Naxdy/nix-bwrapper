{
  lib,
  mkBwrapper,
  chromium,
  testers,
}:

# Regression test for the Chromium/Electron process sandbox inside the bubblewrap
# sandbox (see PR #55).
#
# Chromium - and therefore Electron, which ships the same sandbox code path -
# builds its process sandbox on top of a *nested user namespace*. It needs
# `clone(CLONE_NEWUSER)`, `unshare(CLONE_NEWUSER)` and `chroot()` (see
# `sandbox/linux/services/credentials.cc` in upstream Chromium). Our seccomp
# filter (build-fhsenv-bubblewrap/setup-seccomp.c) blocks all three by default
# (they are the ones Flatpak also blocks). When they are blocked, Chromium
# cannot start its namespace sandbox and instead falls back to the SUID
# `chrome-sandbox` helper, which is not setuid in the Nix store, and aborts
# with either "SUID sandbox helper binary was found, but is not configured
# correctly" or "No usable sandbox! ... try using --no-sandbox".
#
# `fhsenv.opts.allowNestedUserNamespaces` (added in #55) is the opt-in that
# unblocks those three syscalls. This test asserts:
#  1. the default filter still breaks Chromium's sandbox (documents the bug),
#  2. opting in actually lets Chromium start its process sandbox.
#
# The option only exists on revisions that contain #55. `hasUsernsOption`
# detects this so the check runs everywhere: on older revisions it only runs
# case 1; once the option exists it also asserts case 2, guarding against
# regressions of the fix.

let
  makeChromium =
    userns:
    mkBwrapper (
      {
        # Minimal wrapper: the seccomp filter is applied regardless of presets.
        app = {
          package = chromium;
          runScript = "chromium";
        };
      }
      // lib.optionalAttrs userns {
        fhsenv.opts.allowNestedUserNamespaces = true;
      }
    );

  cases = [
    {
      name = "opt-in";
      drv = makeChromium true;
      expectFatal = false;
    }
    {
      name = "default";
      drv = makeChromium false;
      expectFatal = true;
    }
  ];

  runCase =
    case:
    # python
    ''
      out = machine.succeed(
        "su tester -c \"HOME=/home/tester XDG_RUNTIME_DIR=/run/user/1000 "
        "timeout 40 ${case.drv}/bin/chromium 2>&1 || true\"")
      print("===== [${case.name}] Chromium inside bwrap output =====")
      print(out)
      print("===========================================================")
      ${
        if case.expectFatal then
          # python
          ''
            fatal = ("No usable sandbox" in out) or ("SUID sandbox helper" in out)
            t.assertTrue(
              fatal,
              "default filter should break Chromium's sandbox (no nested userns); got: " + out)
          ''
        else
          # python
          ''
            t.assertNotIn("No usable sandbox", out,
                          "opt-in must not hit 'No usable sandbox'; got: " + out)
            t.assertNotIn("SUID sandbox helper", out,
                          "opt-in must not need the SUID helper; got: " + out)
            t.assertTrue(
              ("Missing X server" in out) or ("platform failed to initialize" in out),
              "opt-in should get past sandbox setup to display init (headless VM); got: " + out)
          ''
      }
    '';
in
testers.runNixOSTest {
  name = "nix-bwrapper-electron-sandbox";

  nodes.machine =
    { ... }:
    {
      users.users.tester = {
        isNormalUser = true;
        createHome = true;
      };
    };

  testScript =
    # python
    ''
      machine.wait_for_unit("default.target")

      # Chromium refuses to run with a sandbox as root, so test through a normal
      # user as Chromium would run on a desktop session.
      machine.succeed("mkdir -p /run/user/1000 /home/tester && chown tester /run/user/1000")

      ${lib.concatMapStringsSep "\n" runCase cases}
    '';
}
