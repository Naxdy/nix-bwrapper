{ config, lib, ... }:
let
  cfg = config.runtime;
in
{
  options.runtime = {
    binds = lib.mkOption {
      internal = true;
      type = lib.types.listOf lib.types.str;
      default = [ ];
      apply = binds: map (e: "--ro-bind-try \"$XDG_RUNTIME_DIR/${e}\" \"$XDG_RUNTIME_DIR/${e}\"") binds;
    };
  };

  config = {
    script.preCmds.stage1 = ''
      test -d "$XDG_RUNTIME_DIR/app/${config.app.id}" || mkdir -p "$XDG_RUNTIME_DIR/app/${config.app.id}"
      test -d "$XDG_RUNTIME_DIR/doc/by-app/${config.app.id}" || mkdir -p "$XDG_RUNTIME_DIR/doc/by-app/${config.app.id}"
    '';
  };
}
