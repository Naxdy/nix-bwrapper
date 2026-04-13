# Getting Started

````admonish note
Starting with version 1.0.0, nix-bwrapper publishes to FlakeHub with semantic versioning. It is recommended to lock
your flake input to a major version (as shown in the example below), to avoid sudden unexpected breaking changes.

Alternatively, if you don't care about that and just want the latest version no matter what, you may set it to any of
the following:

> ```
> # For any tagged release
> https://flakehub.com/f/Naxdy/nix-bwrapper/*
> 
> # To get the latest commit to `main`
> github:Naxdy/nix-bwrapper
> ```
````

## Packages

Import this flake like you would any other. It provides an overlay, which in turn provides the `mkBwrapper` and
`mkBwrapperFHSEnv` functions.

Both functions take in a `module` describing the app you want sandboxed, and exactly how you want it to be sandboxed.
Here is a minimal flake that exports a wrapped `discord` package:

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

Presets for commonly shared functionality are available under the `bwrapperPresets` attribute. To see exactly which
options they enable, have a look at the `./presets` directory in this repo.

`bwrapper` also provides a `nixosModule` that simply enables the overlay, which can be used in NixOS configurations,
like so:

```nix
nixosConfigurations.myMachine = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    bwrapper.nixosModules.default
    ({ pkgs, ... }: {
      environment.systemPackages = [
        (pkgs.mkBwrapper {
          imports = [ pkgs.bwrapperPresets.desktop ];
          app = {
            package = pkgs.discord;
          };
          # ...
        })
      ];
    })
  ];
};
```

Packages already using `buildFHSEnv` can also be wrapped, like so:

```nix
packages.lutris-wrapped = pkgs.mkBwrapper ({
  imports = [ pkgs.bwrapperPresets.desktop ];
  app = {
    package = pkgs.lutris;
    isFhsenv = true; # tells bwrapper that the app is already using buildFHSEnv
    id = "net.lutris.Lutris";
  };
  # ...
});
```

Packages using `buildFHSEnv` in a custom manner can also be wrapped, by using `mkBwrapperFHSEnv` like so:

```nix
{
  packages.bottles-wrapped = pkgs.bottles.override {
    # Need to override it like this because `pkgs.bottles` is a `symlinkJoin`.
    # Also, when using `mkBwrapperFHSEnv`, `app.isFhsenv` is implicitly set to `true`, and
    # it is only necessary to specify `package-unwrapped`, as opposed to `package`, which should
    # be set to the _unwrapped_ package (the package that is meant to be passed to `buildFHSEnv`)
    buildFHSEnv = pkgs.mkBwrapperFHSEnv {
      imports = [ pkgs.bwrapperPresets.desktop ];
      app = {
        package-unwrapped = pkgs.bottles-unwrapped;
        id = "com.usebottles.bottles";
      };
      # ...
    };
  };
}
```

See `examples/flake.nix` for more complete use cases. Note that they are only intended as examples, and may not be
(fully) usable as-is.

## DevShells

You can also use `mkBwrapper` to declare a sandboxed `devShell` in your flake:

```nix
{
  devShells.zsh =
    (pkgs.mkBwrapper {
      app = {
        package = pkgs.zsh;
        # Your dev dependencies & tools go here
        addPkgs = [
          pkgs.gron
        ];
      };
      imports = [ pkgs.bwrapperPresets.devshell ];
      mounts.readWrite = [
        "$HOME/.zshrc"
        "$HOME/.p10k.zsh"
        "$HOME/.zshrc.zni"
        "$HOME/.oh-my-zsh"

        # Note that you may not want this, depending on what is
        # contained in your history!
        "$HOME/.zsh_history"
      ];
    }).env;
}
```

Then, you can enter the sandboxed dev environment as you would normally, using `nix develop .#`, or using tools like
`direnv`. Additional dependencies and tools can be declared under `config.app.addPkgs`.
