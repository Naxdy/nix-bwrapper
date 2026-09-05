{ pkgs }:
# Minimal "devshell" style app: forwards its arguments to `bash`, so that tests
# can inspect the resulting sandbox from within.
pkgs.stdenv.mkDerivation {
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
}
