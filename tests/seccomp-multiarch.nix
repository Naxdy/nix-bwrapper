{ pkgs }:
# Regression test for https://github.com/Naxdy/nix-bwrapper/issues/56.
# A multilib (multiArch) FHS env spans two architectures (x86_64 + x86),
# which made the seccomp-bpf derivation fail to build. Wrapping such an env
# must still build.
let
  # Mimic how nixpkgs packages like lutris are structured: the package
  # function takes `buildFHSEnv` as an argument, so bwrapper can override it
  # (and keep `multiArch`) via `app.isFhsenv = true`.
  multilibProbe = pkgs.callPackage (
    { buildFHSEnv }:
    buildFHSEnv {
      pname = "seccomp-probe-multiarch";
      version = "1";
      runScript = "probe";
      targetPkgs = p: [ pkgs.hello ];
      multiArch = true;
    }
  ) { };
in
if pkgs.stdenv.hostPlatform.isx86_64 then
  pkgs.mkBwrapper {
    app = {
      package = multilibProbe;
      isFhsenv = true;
      runScript = "probe";
    };
  }
else
  (pkgs.runCommand "seccomp-multiarch" { } "echo 'multiarch not supported on this platform' > $out")
