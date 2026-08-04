{ pkgs }:
# Regression test for https://github.com/Naxdy/nix-bwrapper/issues/56.
# A multilib (multiArch) FHS env spans two architectures (x86_64 + x86),
# which made the seccomp-bpf derivation fail to build. This check
#   1. builds a bwrapper-wrapped multilib env (the original integration
#      regression: `appPkg.override { buildFHSEnv = ... }` with `multiArch`
#      preserved), and
#   2. compiles the real setup-seccomp.c and asserts on its behavior for both
#      single- and multiarch filters: exit code, stderr warnings, and the bytes
#      of the exported BPF program.
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

  wrappedMultiarch = pkgs.mkBwrapper {
    app = {
      package = multilibProbe;
      isFhsenv = true;
      runScript = "probe";
    };
  };

  checkBpf =
    pkgs.runCommandLocal "seccomp-multiarch-check"
      {
        nativeBuildInputs = [
          pkgs.gnugrep
          pkgs.coreutils
        ];
      }
      ''
        # Compile setup-seccomp.c exactly like the production derivation
        # (build-fhsenv-bubblewrap/default.nix).
        ${pkgs.stdenv.cc}/bin/cc -O2 -I${pkgs.libseccomp.dev}/include \
          -o setup-seccomp ${../build-fhsenv-bubblewrap/setup-seccomp.c} \
          -L${pkgs.libseccomp.lib}/lib -Wl,-rpath,${pkgs.libseccomp.lib}/lib \
          -lseccomp

        # --- Single-arch filter: security-critical path is unchanged. ---
        ./setup-seccomp > bpf-single.bin 2> stderr-single.txt
        test -s bpf-single.bin
        test $(( $(stat -c %s bpf-single.bin) % 8 )) -eq 0
        ! grep -q "setup-seccomp: error" stderr-single.txt
        ! grep -q "multi-arch filters do not support exact rules" stderr-single.txt
        # AUDIT_ARCH_X86_64 (0xc000003e) present, AUDIT_ARCH_I386 (0x40000003) absent.
        od -A n -t x1 bpf-single.bin | tr -d ' \n' | grep -q 3e0000c0
        ! od -A n -t x1 bpf-single.bin | tr -d ' \n' | grep -q 03000040
        # Socket-family allowlist rule (SCMP_ACT_ERRNO(EAFNOSUPPORT) = 0x00050061,
        # bytes 61 00 05 00 in the little-endian BPF) must be present.
        od -A n -t x1 bpf-single.bin | tr -d ' \n' | grep -q 61000500

        # --- Multiarch filter: builds, spans both arches, drops socket-family
        # exact rules with a warning (pre-fix this hard-failed with -EOPNOTSUPP). ---
        ./setup-seccomp --multiarch > bpf-multi.bin 2> stderr-multi.txt
        test -s bpf-multi.bin
        test $(( $(stat -c %s bpf-multi.bin) % 8 )) -eq 0
        ! grep -q "setup-seccomp: error" stderr-multi.txt
        grep -q "multi-arch filters do not support exact rules" stderr-multi.txt
        od -A n -t x1 bpf-multi.bin | tr -d ' \n' | grep -q 3e0000c0
        od -A n -t x1 bpf-multi.bin | tr -d ' \n' | grep -q 03000040
        # Documented tradeoff: exact socket-family rules cannot be represented
        # across arches, so the EAFNOSUPPORT rule must be absent here.
        ! od -A n -t x1 bpf-multi.bin | tr -d ' \n' | grep -q 61000500

        # Keep the wrapped multilib env as an input so the bwrapper integration
        # path stays covered by this check.
        test -d ${wrappedMultiarch}

        mkdir -p $out
        echo "setup-seccomp single/multiarch assertions passed" > $out/result
      '';
in
if pkgs.stdenv.hostPlatform.isx86_64 then
  checkBpf
else
  (pkgs.runCommand "seccomp-multiarch" { } "echo 'multiarch not supported on this platform' > $out")
