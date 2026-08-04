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
        # --- Byte patterns we look for in the exported cBPF program. ---
        # The BPF is a stream of 8-byte struct sock_filter entries; all of the
        # following u32 constants appear little-endian, so the file bytes are
        # the reverse of the value's hex spelling (e.g. 0xc000003e -> 3e 00 00 c0).

        # AUDIT_ARCH_X86_64 = 0xc000003e (bytes 3e 00 00 c0).
        # A seccomp program dispatches on seccomp_data.arch; a jeq against this
        # value selects the x86_64 syscall table. Present in every x86_64 filter.
        x86_64_arch_hex=3e0000c0

        # AUDIT_ARCH_I386 = 0x40000003 (bytes 03 00 00 40).
        # The 32-bit x86 syscall table. Only present when --multiarch ran
        # seccomp_arch_add(SCMP_ARCH_X86); its presence proves the filter is
        # genuinely dual-arch.
        i386_arch_hex=03000040

        # SCMP_ACT_ERRNO(EAFNOSUPPORT) = 0x00050061 (bytes 61 00 05 00).
        # The `ret` instruction that terminates the socket-family-blocked
        # branch (EAFNOSUPPORT = 97). Present in single-arch filters; dropped
        # in multiarch because exact socket-family rules cannot be represented
        # across arches (the documented tradeoff of the fix).
        eafnosupport_hex=61000500

        # hexify FILE prints the file as one contiguous lowercase hex string.
        hexify() { od -A n -t x1 "$1" | tr -d ' \n'; }
        # has_hex FILE HEX succeeds if the hex pattern appears in the file.
        has_hex() { hexify "$1" | grep -q "$2"; }

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
        # x86_64 dispatch present, i386 dispatch absent (single-arch).
        has_hex bpf-single.bin "$x86_64_arch_hex"
        ! has_hex bpf-single.bin "$i386_arch_hex"
        # Socket-family allowlist rule must be present.
        has_hex bpf-single.bin "$eafnosupport_hex"

        # --- Multiarch filter: builds, spans both arches, drops socket-family
        # exact rules with a warning (pre-fix this hard-failed with -EOPNOTSUPP). ---
        ./setup-seccomp --multiarch > bpf-multi.bin 2> stderr-multi.txt
        test -s bpf-multi.bin
        test $(( $(stat -c %s bpf-multi.bin) % 8 )) -eq 0
        ! grep -q "setup-seccomp: error" stderr-multi.txt
        grep -q "multi-arch filters do not support exact rules" stderr-multi.txt
        # Both dispatches present -> the filter spans x86_64 and i386.
        has_hex bpf-multi.bin "$x86_64_arch_hex"
        has_hex bpf-multi.bin "$i386_arch_hex"
        # Documented tradeoff: the socket-family rule must be absent here.
        ! has_hex bpf-multi.bin "$eafnosupport_hex"

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
