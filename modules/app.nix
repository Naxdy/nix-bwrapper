{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.app;
in
{
  options.app = {
    id = lib.mkOption {
      type = lib.types.str;
      default = "nix.bwrapper.${
        builtins.replaceStrings [ "-" ] [ "_" ] (
          if cfg.isFhsenv then cfg.package-unwrapped.pname else cfg.package.pname
        )
      }";
      defaultText = lib.literalExpression ''nix.bwrapper.''${builtins.replaceStrings [ "-" ] [ "_" ] config.app.package.pname}'';
      description = ''
        The (fake) app id to be used within the sandbox. This should be unique for every
        application. Normally, you should not have to change this, as most apps will
        retrieve their app id from the `.desktop` file belonging to them, but certain
        apps will set their id themselves (e.g. Lutris), in which case you will need to
        set this to their chosen id in order to ensure they function as intended (e.g. are
        able to make dbus calls, have their icon show up properly, etc.).
      '';
    };
    addPkgs = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      description = ''List of packages to be added to the sandbox' FHS environment. Includes the packaged app's `buildInputs` by default.'';
    };
    runScript = lib.mkOption {
      type = lib.types.str;
      default = cfg.package.meta.mainProgram;
      defaultText = lib.literalExpression "config.app.package.meta.mainProgram";
      description = "The command / program to be executed within the sandbox";
    };
    execArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Additional arguments to run the program with";
    };
    overwriteExec = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to overwrite the `Exec` section in the app's `.desktop` file";
    };
    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        The main package to be sandboxed. If it is already wrapped using `buildFHSEnv`, make sure
        to set `config.app.isFhsenv` to `true`.
      '';
    };
    env = lib.mkOption {
      type =
        with lib.types;
        attrsOf (oneOf [
          (listOf (oneOf [
            int
            str
            path
          ]))
          int
          str
          path
        ]);
      description = "A set of environment variables to be passed to the sandboxed application";
      default = { };
      example = {
        NOTIFY_IGNORE_PORTAL = 1;
        DISPLAY = "$DISPLAY";
      };
    };
    package-unwrapped = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = if cfg.isFhsenv then (builtins.elemAt (cfg.package.args.targetPkgs pkgs) 0) else null;
      defaultText = lib.literalExpression "if config.app.isFhsenv then (builtins.elemAt (config.app.package.args.targetPkgs pkgs) 0) else null";
      description = ''
        The unwrapped main package in case `config.app.package` is already FHS-wrapped. The default value picks the first
        package within the `targetPkgs` list of the input package.
      '';
    };
    isFhsenv = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether the package in `config.app.package` is already wrapped in an FHS env
      '';
    };
    renameDesktopFile = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to rename the application's desktop file to its new app id in `config.app.id`";
    };
    bwrapPath = lib.mkOption {
      type = lib.types.str;
      default = if cfg.isFhsenv then cfg.package-unwrapped.pname else cfg.package.pname;
      defaultText = lib.literalExpression "config.app.package.pname";
      description = "The path under $HOME/.bwrapper where to store sandboxed application data";
    };
  };

  config = {
    app.addPkgs = if cfg.isFhsenv then [ ] else (cfg.package.buildInputs or [ ]);

    app.env = {
      NOTIFY_IGNORE_PORTAL = 1;
    };
  };
}
