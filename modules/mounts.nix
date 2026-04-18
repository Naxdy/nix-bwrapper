{ config, lib, ... }:
let
  cfg = config.mounts;
  mountPairType = lib.types.submodule {
    options = {
      from = lib.mkOption {
        type = lib.types.str;
        description = "Path on the host system.";
      };
      to = lib.mkOption {
        type = lib.types.str;
        description = "Path to mount within the sandbox.";
      };
    };
  };
  mountsType = lib.types.listOf (
    lib.types.coercedTo (lib.types.either lib.types.str mountPairType) (
      m:
      if builtins.isString m then
        {
          from = m;
          to = m;
        }
      else
        m
    ) mountPairType
  );
in
{
  options.mounts = {
    privateTmp = lib.mkOption {
      type = lib.types.bool;
      description = "Whether to isolate the /tmp folder within the sandbox";
      default = true;
    };
    read = lib.mkOption {
      type = mountsType;
      description = ''
        Paths to be mounted read-only within the sandbox. Supports environment
        variables like `$HOME`.

        List entries may either be paths, or a mapping of a host path to a
        different path within the sandbox.
      '';
      default = [ ];
    };
    readWrite = lib.mkOption {
      type = mountsType;
      description = ''
        Paths to be mounted read-write within the sandbox. Supports environment
        variables like `$HOME`.

        If the path to be mounted doesn't exist in the host system, a corresponding
        directory will be created at the specified location.

        List entries may either be paths, or a mapping of a host path to a
        different path within the sandbox.
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
          map (e: ''(test -d "${e.from}" || test -f "${e.from}") || mkdir -p "${e.from}"'') (
            lib.unique cfg.readWrite
          )
        ));

      fhsenv.bwrap.additionalArgs =
        (map (e: ''--bind "$HOME/.bwrapper/${config.app.bwrapPath}/${e.name}" "${e.path}"'') (
          lib.unique cfg.sandbox
        ))
        ++ (map (e: "--ro-bind-try \"${e.from}\" \"${e.to}\"") (lib.unique cfg.read))
        ++ (map (e: "--bind \"${e.from}\" \"${e.to}\"") (lib.unique cfg.readWrite));
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
