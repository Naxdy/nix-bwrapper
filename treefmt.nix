{ ... }:
{
  programs.nixfmt.enable = true;
  programs.typos = {
    enable = true;
    includes = [
      "*.md"
      "*.nix"
    ];
  };
  programs.mdformat = {
    enable = true;
    settings = {
      wrap = 120;
    };
  };
}
