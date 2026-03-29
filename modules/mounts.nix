{ config, lib, ... }:
let
  cfg = config.mounts;
in
{
  options.mounts = {
    privateTmp = lib.mkOption {
      type = lib.types.bool;
      description = "Whether to isolate the /tmp folder within the sandbox";
      default = true;
    };
    read = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Paths to be mounted read-only within the sandbox. Supports environment
        variables like `$HOME`. The default includes common paths needed for
        theming to function in most apps.
      '';
      default = [ ];
    };
    readWrite = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Paths to be mounted read-write within the sandbox. Supports environment
        variables like `$HOME`.

        If the path doesn't exist, a corresponding directory will be created at
        the specified location.
      '';
      default = [ ];
    };
    sandbox = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options.name = lib.mkOption {
            type = lib.types.str;
            description = "The directory name to be created under `$HOME/.bwrapper/[bwrapPath]`";
          };
          options.path = lib.mkOption {
            type = lib.types.str;
            description = "The path for this directory to be mounted as within the sandbox";
          };
        }
      );
      description = ''
        Additional paths to be preserved within the sandbox. They will be created
        under `$HOME/.bwrapper/[bwrapPath]`. The default includes `~/.config`,
        `~/.local` and `~/.cache`.
      '';
      default = [ ];
    };
    sandboxArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
    };
  };

  config = lib.mkMerge [
    {
      script.preCmds.stage1 =
        (builtins.concatStringsSep "\n" (
          map (
            e:
            ''test -d "$HOME/.bwrapper/${config.app.bwrapPath}/${e.name}" || mkdir -p "$HOME/.bwrapper/${config.app.bwrapPath}/${e.name}"''
          ) (lib.unique cfg.sandbox)
        ))
        + "\n"
        + (builtins.concatStringsSep "\n" (
          map (e: ''(test -d "${e}" || test -f "${e}") || mkdir -p "${e}"'') (lib.unique cfg.readWrite)
        ));

      fhsenv.bwrap.additionalArgs =
        (map (e: ''--bind "$HOME/.bwrapper/${config.app.bwrapPath}/${e.name}" "${e.path}"'') (
          lib.unique cfg.sandbox
        ))
        ++ (map (e: "--ro-bind-try \"${e}\" \"${e}\"") (lib.unique cfg.read))
        ++ (map (e: "--bind \"${e}\" \"${e}\"") (lib.unique cfg.readWrite));
    }
    (lib.mkIf cfg.privateTmp {
      script.preCmds.stage1 = ''
        test -d "/tmp/app/${config.app.id}" || mkdir -p "/tmp/app/${config.app.id}"
      '';

      fhsenv.bwrap.additionalArgs = [
        ''--bind "/tmp/app/${config.app.id}" "/tmp"''
      ];
    })
  ];
}
