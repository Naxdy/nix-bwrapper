{
  bwrapperPresetsMeta,
  bwrapperVersion,
  lib,
  mdbook,
  mdbook-admonish,
  stdenvNoCC,
  writeText,
}:
let
  presetsSummary = lib.foldlAttrs (
    acc: name: value:
    "${acc}\n- [${value.meta.name}](./presets/${value.meta.name}.md)"
  ) "" bwrapperPresetsMeta;

  presetsMarkdowns = lib.mapAttrsToList (name: value: {
    path = "./src/presets/${value.meta.name}.md";
    textFile = writeText "${value.meta.name}-doc.md" ''
      # ${value.meta.name}

      ${value.meta.description}

      Use via:

      ```nix
      {
        myPackage = pkgs.mkBwrapper {
          imports = [
            pkgs.bwrapperPresets.${value.meta.name}
          ];
          # your config here
        };
      }
      ```

      Source reference:

      ```nix
      ${builtins.readFile value.path}
      ```
    '';
  }) bwrapperPresetsMeta;
in
stdenvNoCC.mkDerivation {
  pname = "nix-bwrapper-docs";
  version = bwrapperVersion;

  src = builtins.path {
    path = ./.;
    name = "source";
  };

  nativeBuildInputs = [
    mdbook
    mdbook-admonish
  ];

  configurePhase = ''
    runHook preConfigure

    mkdir -p ./src/presets

    ${builtins.concatStringsSep "\n" (
      map (e: ''
        ln -s "${e.textFile}" "${e.path}"
      '') presetsMarkdowns
    )}

    substituteInPlace ./src/SUMMARY.md \
      --replace-fail @presetsSummary@ ${lib.escapeShellArg presetsSummary}

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    mdbook build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r book/* $out

    runHook postInstall
  '';
}
