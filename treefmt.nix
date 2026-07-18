{ pkgs, lib, ... }:
{
  programs = {
    clang-format.enable = true;
    clang-tidy.enable = true;
    nixfmt.enable = true;
    typos = {
      enable = true;
      includes = [
        "*.md"
        "*.nix"
      ];
    };
    mdformat = {
      enable = true;
      settings = {
        wrap = 120;
      };
    };
  };

  settings.formatter.clang-tidy.options =
    let
      cLibs = [
        pkgs.libseccomp
      ];
    in
    map (e: "--extra-arg-before=-I${lib.getDev e}/include") cLibs;
}
