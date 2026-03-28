# Nix-Bwrapper

> [!NOTE]
>
> Starting with version 1.0.0, nix-bwrapper publishes to FlakeHub with semantic versioning. It is recommended to lock
> your flake input to a major version (as shown in the example below), to avoid sudden unexpected breaking changes.
>
> Alternatively, if you don't care about that and just want the latest version no matter what, you may set it to any of
> the following:
>
> ```
> # For any tagged release
> https://flakehub.com/f/Naxdy/nix-bwrapper/*
>
> # To get the latest commit to `main`
> github:Naxdy/nix-bwrapper
> ```

Nix-Bwrapper is a utility aimed at creating a user-friendly method of sandboxing applications using bubblewrap with
portals support. To do this, bwrapper leverages NixOS' built-in `buildFHSEnv` wrapper.

Example:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-bwrapper.url = "https://flakehub.com/f/Naxdy/nix-bwrapper/1.*";
  };

  outputs = { self, nixpkgs, nix-bwrapper }:
  let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true; # discord is unfree
      overlays = [
        nix-bwrapper.overlays.default # provides `mkBwrapper`
      ];
    };
  in {
    packages.x86_64-linux.discord-wrapped = pkgs.mkBwrapper {
      imports = [
        # Enables common desktop functionality (bind sockets for audio, display, dbus, mount
        # directories for fonts, theming, etc.).
        pkgs.bwrapperPresets.desktop
      ];
      app = {
        package = pkgs.discord;
        runScript = "discord";
      };
      # ...
    };
  };
}
```

For more details, head on over to our [documentation](https://naxdy.github.io/nix-bwrapper).
