{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) filter showWarnings;

  fhsEnvArgs =
    {
      pkg ? config.app.package,
      runScript ? config.app.runScript,
    }:
    {
      inherit (config.fhsenv.opts)
        unshareIpc
        unshareUser
        unshareUts
        unshareCgroup
        unsharePid
        unshareNet
        dieWithParent
        ;

      inherit runScript;

      inherit (config.mounts) privateTmp;

      extraInstallCommands = config.fhsenv.extraInstallCmds;

      targetPkgs = pkgs: [ pkg ] ++ config.app.addPkgs;

      extraPreBwrapCmds = config.script.preCmds.combined;

      extraBwrapArgs = config.fhsenv.bwrap.finalArgs;
    };

  # Handle assertions and warnings

  failedAssertions = map (x: x.message) (filter (x: !x.assertion) config.assertions);

  assertWarn =
    f:
    if failedAssertions != [ ] then
      throw "\nFailed assertions:\n${builtins.concatStringsSep "\n" (map (x: "- ${x}") failedAssertions)}"
    else
      showWarnings config.warnings f;
in
{
  options.build = {
    fhsenv = lib.mkOption {
      readOnly = true;
      internal = true;
      type = lib.types.functionTo lib.types.package;
    };
    package = lib.mkOption {
      readOnly = true;
      internal = true;
      type = lib.types.nullOr lib.types.package;
    };
  };

  config = {
    build.fhsenv =
      {
        name ? null,
        pname ? null,
        version ? null,
        runScript ? "bash",
        extraInstallCommands ? "",
        meta ? { },
        passthru ? { },
        extraPreBwrapCmds ? "",
        extraBwrapArgs ? [ ],
        unshareUser ? false,
        unshareIpc ? false,
        unsharePid ? false,
        unshareNet ? false,
        unshareUts ? false,
        unshareCgroup ? false,
        privateTmp ? false,
        dieWithParent ? true,
        ...
      }@args:
      let
        pname = if args ? name && args.name != null then args.name else args.pname;
        versionStr = lib.optionalString (version != null) ("-" + version);
        name = pname + versionStr;

        envArgs = fhsEnvArgs {
          pkg = config.app.package or (builtins.elemAt (args.targetPkgs pkgs) 0);
          inherit runScript;
        };
      in
      assertWarn (
        config.fhsenv.package (
          args
          // (envArgs)
          // {
            inherit name;

            targetPkgs = pkgs: (envArgs.targetPkgs pkgs) ++ (args.targetPkgs pkgs);

            extraInstallCommands = (args.extraInstallCommands or "") + (envArgs.extraInstallCommands);

            extraPreBwrapCmds = (args.extraPreBwrapCmds or "") + envArgs.extraPreBwrapCmds;

            extraBwrapArgs = (args.extraBwrapArgs or [ ]) ++ envArgs.extraBwrapArgs;
          }
        )
      );

    build.package = assertWarn (
      if config.app.isFhsenv then
        (config.app.package.override {
          buildFHSEnv = config.build.fhsenv;
        })
      else
        (config.fhsenv.package (
          (fhsEnvArgs { })
          // {
            inherit (config.app.package) pname version meta;
          }
        ))
    );
  };
}
