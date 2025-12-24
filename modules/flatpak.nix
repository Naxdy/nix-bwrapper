{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.flatpak;

  # Convert a manifest file (YAML or JSON) to normalized JSON.
  # This handles both formats since JSON is valid YAML, and normalizes
  # the "app-id" field to "id" (YAML manifests use "app-id", JSON uses "id").
  normalizeManifest =
    manifestFile:
    pkgs.runCommand "manifest.json"
      {
        nativeBuildInputs = [
          pkgs.yj
          pkgs.jq
        ];
      }
      ''
        # Convert YAML to JSON (works for both YAML and JSON input since JSON is valid YAML),
        # then normalize "app-id" to "id" for consistency with nix-bwrapper expectations
        yj -yj < ${manifestFile} | jq 'if has("app-id") then . + {id: ."app-id"} | del(."app-id") else . end' > $out
      '';
in
{
  options.flatpak = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable certain tricks to make the sandboxed app think it's being run as a flatpak. This is required for portals to work.";
    };

    manifestFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression ''
        fetchurl {
          url = "https://raw.githubusercontent.com/flathub/io.gitlab.librewolf-community/refs/heads/master/io.gitlab.librewolf-community.json";
          hash = "...";
        }
      '';
      description = ''
        A path pointing to a Flatpak manifest file in JSON or YAML format.

        If set, will parse the given manifest file and pre-set applicable options in bwrapper wherever possible.
        In a perfect world, this should make it unnecessary for you to have to customize any other options.

        Both JSON and YAML formats are supported. The manifest is automatically normalized at build time,
        including conversion of the `app-id` field (used in YAML manifests) to `id` (used in JSON manifests).
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.enable -> config.dbus.enable;
            message = "Flatpak emulation will do nothing without forwarding the required DBus interfaces.";
          }
        ];

        fhsenv.bwrap.additionalArgs = [
          "--ro-bind \"$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info\" \"/.flatpak-info\""
        ];

        # HACK: To make most flatpak apps function correctly, we need a fake `.flatpak-info` file at
        # the root of the sandbox. Additionally, we need a fake `bwrapinfo.json` file in the host
        # system. Don't yet know if the values in there should be something sensible, for now just
        # setting everything to `1` seems to work fine.
        script.preCmds.stage1 = ''
          test -f "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info" && rm "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info"
          mkdir -p "$HOME/.bwrapper/${config.app.bwrapPath}" || { echo 'could not ensure directory under $HOME/.bwrapper'; exit 1; }
          printf "[Application]\nname=${config.app.id}\n\n[Instance]\ninstance-id = 0\nsystem-bus-proxy = true\nsession-bus-proxy = true\n" > "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info" || { echo 'could not write .flatpak-info'; exit 1; }

          mkdir -p "$XDG_RUNTIME_DIR/.flatpak/0" || { echo 'could not ensure fake flatpak directory'; exit 1; }
          printf '{"child-pid": 1, "mnt-namespace": 1, "net-namespace": 1, "pid-namespace": 1}' > "$XDG_RUNTIME_DIR/.flatpak/0/bwrapinfo.json" || { echo 'could not write fake bwrapinfo.json'; exit 1; }
        '';
      }

      (lib.mkIf (cfg.manifestFile != null) (
        let
          # Use the normalized manifest (handles YAML/JSON and app-id normalization)
          normalizedManifestFile = normalizeManifest cfg.manifestFile;
          manifest = builtins.fromJSON (builtins.readFile normalizedManifestFile);

          argsOf =
            type:
            map (e: lib.removePrefix "--${type}=" e) (
              builtins.filter (e: lib.hasPrefix "--${type}=" e) manifest.finish-args
            );

          hasSocket = name: lib.lists.any (e: e == name) (argsOf "socket");
          hasShare = name: lib.lists.any (e: e == name) (argsOf "share");
          hasUnshare = name: lib.lists.any (e: e == name) (argsOf "unshare");

          filesystemSubstitutes =
            let
              xdg-user-dirs = "${pkgs.xdg-user-dirs}/bin/xdg-user-dir";

              xdg-dir = dir: "$(${xdg-user-dirs} ${dir})";
            in
            {
              "home/" = "$HOME/";
              "xdg-desktop" = xdg-dir "DESKTOP";
              "xdg-documents" = xdg-dir "DOCUMENTS";
              "xdg-download" = xdg-dir "DOWNLOAD";
              "xdg-music" = xdg-dir "MUSIC";
              "xdg-pictures" = xdg-dir "PICTURES";
              "xdg-public-share" = xdg-dir "PUBLICSHARE";
              "xdg-templates" = xdg-dir "TEMPLATES";
              "xdg-videos" = xdg-dir "VIDEOS";
              "xdg-run" = "$XDG_RUNTIME_DIR";
              "xdg-config" = "$HOME/.config";
              "xdg-cache" = "$HOME/.cache";
              "xdg-data" = "$HOME/.local/share";
            };

          unsupportedFsSubstitutes = [
            "host/"
            "host-os/"
            "host-etc/"
          ];

          substituteFsPath =
            path:
            builtins.replaceStrings (builtins.attrNames filesystemSubstitutes)
              (builtins.attrValues filesystemSubstitutes)
              path;
        in
        {
          app = {
            inherit (manifest) id;

            env = builtins.listToAttrs (
              map (
                e:
                let
                  split = lib.splitString "=" e;
                in
                {
                  name = builtins.elemAt split 0;
                  value = builtins.concatStringsSep "=" (lib.lists.sublist 1 ((builtins.length split) - 1) split);
                }
              ) (argsOf "env")
            );
          };

          sockets = {
            pulseaudio = hasSocket "pulseaudio";
            pipewire = hasSocket "pulseaudio" || hasSocket "pipewire";
            cups = hasSocket "cups";
          };

          fhsenv.opts = {
            unshareNet = !(hasShare "network") || (hasUnshare "network");
            unshareIpc = !(hasShare "ipc") || (hasUnshare "ipc");
          };

          mounts = {
            read = map (e: substituteFsPath (lib.removeSuffix ":ro" e)) (
              builtins.filter (
                e: (lib.hasSuffix ":ro" e) && !(lib.lists.any (i: lib.hasInfix i e) unsupportedFsSubstitutes)
              ) (argsOf "filesystem")
            );
            readWrite = map (e: substituteFsPath (lib.removeSuffix ":create" (lib.removeSuffix ":rw" e))) (
              builtins.filter (
                e:
                ((lib.hasSuffix ":rw" e) || (lib.hasSuffix ":create" e))
                && !(lib.lists.any (i: lib.hasInfix i e) unsupportedFsSubstitutes)
              ) (argsOf "filesystem")
            );
            sandbox = map (e: {
              name = if (lib.hasPrefix "/" e) then "root/${lib.removePrefix "/" e}" else e;
              path = if (lib.hasPrefix "/" e) then e else "$HOME/${e}";
            }) (argsOf "persist");
          };

          dbus = {
            session = {
              talks = argsOf "talk-name";
              owns = argsOf "own-name";
              calls = argsOf "call-name";
            };
            system = {
              talks = argsOf "system-talk-name";
              calls = argsOf "system-call-name";
            };
          };
        }
      ))
    ]
  );
}
