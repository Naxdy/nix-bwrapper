{
  config,
  lib,
  pkgs,
  nixpkgs,
  ...
}:
let
  cfg = config.fhsenv;
in
{
  options.fhsenv = {
    bwrap = {
      baseArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        internal = true;
      };
      finalArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        internal = true;
      };
      additionalArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        internal = true;
      };
    };
    extraInstallCmds = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        mv $out/bin/''${config.app.runScript} $out/bin/myCustomAppName
      '';
      description = ''
        Extra install commands to be passed to `buildFHSEnv`. If `config.fhsenv.skipExtraInstallCmds`
        is `false`, this will copy over any application icons and desktop files. Note that whatever you
        set this value to, it will be merged with the default, unless you set `config.fhsenv.skipExtraInstallCmds = true`.

        You should not need to modify this, unless you need some custom logic, e.g. renaming the final
        executable file name.
      '';
    };
    skipExtraInstallCmds = lib.mkOption {
      type = lib.types.bool;
      default = config.app.isFhsenv;
      defaultText = lib.literalExpression "config.app.isFhsenv";
      description = "Whether to skip extra install commands such as copying over application icons and ensuring the `.desktop` file exists under the correct name";
    };
    package = lib.mkOption {
      type = lib.types.functionTo lib.types.package;
      internal = true;
    };
    opts = {
      unshareUser = lib.mkOption {
        type = lib.types.bool;
        description = "Create a new user namespace";
        default = false;
      };
      unshareUts = lib.mkOption {
        type = lib.types.bool;
        description = "Create a new uts namespace";
        default = false;
      };
      unshareCgroup = lib.mkOption {
        type = lib.types.bool;
        description = "Create a new cgroup namespace";
        default = false;
      };
      unsharePid = lib.mkOption {
        type = lib.types.bool;
        description = "Create a new pid namespace";
        default = true;
      };
      unshareNet = lib.mkOption {
        type = lib.types.bool;
        description = "Create a new network namespace";
        default = false;
      };
      unshareIpc = lib.mkOption {
        type = lib.types.bool;
        description = "Create a new ipc namespace";
        default = true;
      };
      dieWithParent = lib.mkOption {
        type = lib.types.bool;
        description = ''
          Ensures child process (COMMAND) dies when bwrap's parent dies.
          Kills (SIGKILL) all bwrap sandbox processes in sequence from parent
          to child including COMMAND process when bwrap or bwrap's parent dies.
          See prctl, PR_SET_PDEATHSIG.

          Note: It is recommended to leave this enabled in order to avoid
          zombie processes.
        '';
        default = true;
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (!cfg.skipExtraInstallCmds) {
      fhsenv.extraInstallCmds = ''
        # some fhsenv packages add these by default, but we want our own
        rm -rf $out/share/{applications,icons,pixmaps}

        mkdir -p $out/share/{applications,icons,pixmaps}

        test -d ${config.app.package}/share/icons && ln -s ${config.app.package}/share/icons/* $out/share/icons
        test -d ${config.app.package}/share/pixmaps && ln -s ${config.app.package}/share/pixmaps/* $out/share/pixmaps
      ''
      + (
        if config.app.renameDesktopFile then
          ''
            test $(ls ${config.app.package}/share/applications/*.desktop | wc -l) -eq 1 || \
              (echo "You have chosen to automatically rename ${config.app.bwrapPath}'s desktop file, but there is more than 1. You will have to manually specify the appId using config.app.id instead (it should match the desktop file)" && exit 1)

            cp ${config.app.package}/share/applications/*.desktop $out/share/applications/${config.app.id}.desktop
          ''
        else
          ''
            test -d ${config.app.package}/share/applications && cp ${config.app.package}/share/applications/* $out/share/applications
          ''
      )
      + (lib.optionalString config.app.overwriteExec ''
        sed -i "s|^Exec=.*|Exec=${config.app.runScript} ${config.app.execArgs}|" $out/share/applications/*.desktop
      '');
    })
    {
      fhsenv.package = pkgs.callPackage ../build-fhsenv-bubblewrap { inherit nixpkgs; };

      fhsenv.bwrap.baseArgs = [
        "--new-session"
        "--tmpfs /home"
        "--tmpfs /mnt"
        "--tmpfs /run"
        "--ro-bind-try /run/current-system /run/current-system"
        "--ro-bind-try /run/booted-system /run/booted-system"
        "--ro-bind-try /run/opengl-driver /run/opengl-driver"
        "--ro-bind-try /run/opengl-driver-32 /run/opengl-driver-32"
        "--bind \"$XDG_RUNTIME_DIR/doc/by-app/${config.app.id}\" \"$XDG_RUNTIME_DIR/doc\""
      ]
      ++ (lib.unique (
        lib.mapAttrsToList (
          name: value:
          ''--setenv ${name} ${
            if builtins.typeOf value == "string" then ("\"${value}\"") else (builtins.toString value)
          }''
        ) config.app.env
      ));

      fhsenv.bwrap.finalArgs = cfg.bwrap.baseArgs ++ cfg.bwrap.additionalArgs;
    }
  ];
}
