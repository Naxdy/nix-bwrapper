# Nix-Bwrapper

This is a very early attempt at creating a user-friendly method of sandboxing applications using bubblewrap with portals support. To do this, bwrapper leverages NixOS' built-in `buildFHSEnv` wrapper.

A proof-of-concept using Brave browser can be built using:

```
nix build .#brave-wrapped
```

Note that you need [Nix](https://nixos.org/download) with [flakes enabled](https://nixos.wiki/wiki/Flakes) (available on any distro, and even macOS).

Upon building, the wrapper script can be found in `./result/bin/brave`

## Usage

Import this flake like you would any other. It provides an overlay, which in turn provides the `bwrapper` "package" (it's a function, really).

Then, wrap any native package of your choosing using `bwrapper`. Note: FHS packages are currently NOT supported.

Examples:

```nix
{
    discord-wrapped = bwrapper {
        pkg = pkgs.discord;
        appId = "com.discordapp.Discord";
        runScript = "discord";
        overwriteExec = "discord";
        additionalFolderPathsReadWrite = [
            "$HOME/Downloads"
            "$XDG_RUNTIME_DIR/app/com.discordapp.Discord"
        ];
    };

    slack-wrapped = bwrapper {
        pkg = pkgs.slack;
        appId = "com.slack.Slack";
        runScript = "slack";
        overwriteExec = "slack -s %U";
        addPkgs = [
            pkgs.libdbusmenu
        ];
        additionalFolderPathsReadWrite = [
            "$HOME/Downloads"
        ];
        systemDbusTalks = [
            "org.freedesktop.UPower"
            "org.freedesktop.login1"
        ];
        dbusTalks = [
            "org.kde.kwalletd6"
            "org.freedesktop.secrets"
            "org.kde.kwalletd5"
        ];
    };
}

```

## Disclaimer

This project is still very much WIP, and as such things may not work as expected (or at all). For example, portals currently don't work very well.