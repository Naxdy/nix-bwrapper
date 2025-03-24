{ pkgs, nixpkgs }:
let
  inherit (pkgs) lib;

  mainModule =
    { config, lib, ... }:
    {
      imports = [
        ./runtime.nix
        ./socket.nix
        ./dbus.nix
        ./mounts.nix
        ./flatpak.nix
        ./script.nix
        ./app.nix
        ./build.nix
        ./fhsenv.nix
      ];
    };

  noPkgs =
    let
      # Known suffixes for package sets
      suffixes = [
        "Plugins"
        "Packages"
      ];

      # Predicate for whether an attr name looks like a package set
      # Determines whether stubPackage should recurse
      isPackageSet = name: builtins.any (lib.flip lib.strings.hasSuffix name) suffixes;

      # Need to retain `meta.homepage` if present
      stubPackage =
        prefix: name: package:
        let
          loc = prefix ++ [ name ];
        in
        if isPackageSet name then
          lib.mapAttrs (stubPackage loc) package
        else
          lib.mapAttrs (_: throwAccessError loc) package
          // lib.optionalAttrs (package ? meta) { inherit (package) meta; };

      throwAccessError =
        loc:
        throw "Attempted to access `${
          lib.concatStringsSep "." ([ "pkgs" ] ++ loc)
        }` while rendering the docs.";
    in
    lib.fix (
      self:
      lib.mapAttrs (stubPackage [ ]) pkgs
      // {
        pkgs = self;
        # The following pkgs attrs are required to eval nixvim, even for the docs:
        inherit (pkgs)
          _type
          stdenv
          stdenvNoCC
          symlinkJoin
          runCommand
          runCommandLocal
          writeShellApplication
          ;
      }
    );

  evalMod =
    mod:
    pkgs.lib.evalModules {
      modules = [
        mod
        mainModule
      ];
      specialArgs = {
        inherit nixpkgs pkgs;
        inherit (pkgs) lib;
      };
    };

  modulesForDoc = evalMod ({
    _module.args.pkgs = lib.mkForce noPkgs;
  });
in
{
  bwrapper = mod: (evalMod mod).config.build.package;

  bwrapperFhsEnv = mod: (evalMod mod).config.build.fhsenv;

  options-json =
    (pkgs.nixosOptionsDoc {
      inherit (modulesForDoc) options;
    }).optionsJSON;

  inherit evalMod;
}
