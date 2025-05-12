{ config, lib, ... }:
let
  cfg = config.script;
in
{
  options.script = {
    preCmds = {
      stage1 = lib.mkOption {
        type = lib.types.lines;
        internal = true;
        default = "";
      };
      stage2 = lib.mkOption {
        type = lib.types.lines;
        internal = true;
        default = "";
      };
      stage3 = lib.mkOption {
        type = lib.types.lines;
        internal = true;
        default = "";
      };
      stage4 = lib.mkOption {
        type = lib.types.lines;
        internal = true;
        default = "";
      };
      combined = lib.mkOption {
        type = lib.types.str;
        internal = true;
      };
    };
  };

  config = {
    script.preCmds.combined = ''
      trap 'trap - SIGTERM && kill -- -$$' SIGINT SIGTERM EXIT

      # Stage 1
      ${cfg.preCmds.stage1}
      # Stage 2
      ${cfg.preCmds.stage2}
      # Stage 3
      ${cfg.preCmds.stage3}
      # Stage 4
      ${cfg.preCmds.stage4}
    '';
  };
}
