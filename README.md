# Nix-Bwrapper

Nix-Bwrapper is a utility aimed at creating a user-friendly method of sandboxing applications using bubblewrap with
portals support. To do this, bwrapper leverages NixOS' built-in `buildFHSEnv` wrapper.

The `flake.nix` contains a few examples with some commonly used (unfree) applications.

## Getting Started

Import this flake like you would any other. It provides an overlay, which in turn provides the `mkBwrapper` and
`mkBwrapperFHSEnv` functions.

Both functions take in a `module` describing the app you want sandboxed, and exactly how you want it to be sandboxed.
Here is a minimal flake that exports a wrapped `discord` package:

```nix
{
  imports = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-bwrapper.url = "github:Naxdy/nix-bwrapper";
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
      app = {
        package = pkgs.discord;
        runScript = "discord";
        id = "com.discordapp.Discord";
      };
      mounts = {
        readWrite = [
          "$XDG_RUNTIME_DIR/app/com.discordapp.Discord"
        ];
      };
      dbus.session.owns = [
        "com.discordapp.Discord"
      ];
    };
  };
}
```

Packages already using `buildFHSEnv` can also be wrapped, like so:

```nix
  packages.lutris-wrapped = pkgs.mkBwrapper ({
    app = {
      package = pkgs.lutris;
      isFhsenv = true; # tells bwrapper that the app is already using buildFHSEnv
      id = "net.lutris.Lutris";
      env = {
        WEBKIT_DISABLE_DMABUF_RENDERER = 1;
        APPIMAGE_EXTRACT_AND_RUN = 1;
      };
    };
    fhsenv = {
      skipExtraInstallCmds = false;
    };
    dbus = {
      session = {
        talks = [
          "org.freedesktop.Flatpak"
          "org.kde.StatusNotifierWatcher"
          "org.kde.KWin"
          "org.gnome.Mutter.DisplayConfig"
          "org.freedesktop.ScreenSaver"
        ];
        owns = [
          "net.lutris.Lutris"
        ];
      };
      system = {
        talks = [
          "org.freedesktop.UDisks2"
        ];
      };
    };
    mounts = {
      read = [
        "$HOME/.config/kdedefaults"
        "$HOME/.local/share/color-schemes"
      ];
      readWrite = [
        "$HOME/.steam"
        "$HOME/.local/share/steam"
        "$HOME/.local/share/applications"
        "$HOME/.local/share/desktop-directories"
        "$HOME/Games"
      ];
    };
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
      app = {
        package-unwrapped = pkgs.bottles-unwrapped;
        id = "com.usebottles.bottles";
      };
      dbus.system.talks = [
        "org.freedesktop.UDisks2"
      ];
      dbus.session.owns = [
        "com.usebottles.bottles"
      ];
    };
  };
}
```

See the `flake.nix` for some other examples.

### Options

> [!NOTE] A comprehensive interactive option search is available at https://naxdy.github.io/nix-bwrapper

`bwrapper` is preconfigured in such a way that it should integrate with your DE and your theming, and as such includes a
number of read-only mounts for some of your home directories (e.g. `~/.fonts`, `~/.icons`, etc.).

This behavior can be overridden just like in any other NixOS module, by using `lib.mkForce`. For example:

```nix
{
  packages.discord-wrapped = pkgs.mkBwrapper {
    app = {
      package = pkgs.discord;
      runScript = "discord";
      id = "com.discordapp.Discord";
    };
    mounts = {
      read = lib.mkForce [ ]; # do not grant Discord access to any other paths
      readWrite = [
        "$XDG_RUNTIME_DIR/app/com.discordapp.Discord" # for rich presence
      ];
    };
    dbus.session.owns = [
      "com.discordapp.Discord"
    ];
  };
}
```

Additionally, `bwrapper` will attempt to bind `pulse`, `pipewire` and `wayland` sockets from `$XDG_RUNTIME_DIR`, as well
as any `X11` sockets it can find.

This can be disabled by setting the respective `sockets` option to `false`:

```nix
{
  packages.slack-wrapped = pkgs.mkBwrapper {
    app = {
      package = pkgs.slack;
      runScript = "slack";
      execArgs = "-s %U";
      addPkgs = [
        pkgs.libdbusmenu # to make global menu work in KDE
      ];
    };
    sockets.x11 = false; # prevent Slack from accessing X11
    dbus.system.talks = [
      "org.freedesktop.UPower"
      "org.freedesktop.login1"
    ];
    dbus.session.talks = [
      "org.kde.kwalletd6"
      "org.freedesktop.secrets"
      "org.kde.kwalletd5"
    ];
  };
}
```

Sandboxed files are stored in `$HOME/.bwrapper/${config.app.bwrapPath}` on the host system.

Access is granted to all hardware devices by default.

### How to package a new application

#### Your application has a flatpak

First, obtain the info about the permissions the app needs:

1. Go to [flathub.org](https://flathub.org) and look for the application you want to wrap. We'll use
   [Slack](https://flathub.org/apps/com.slack.Slack) as an example here.

1. At the bottom, click on "Links", and then "Manifest". For Slack, it should lead you
   [here](https://github.com/flathub/com.slack.Slack).

1. Open the `.yaml` file, in this case `com.slack.Slack.yaml`

This file shows all the permissions that are being granted to the application. You can use this as a blueprint for which
permissions to grant in your wrapper. We can see, that the file contains the following:

```yaml
finish-args:
    - --device=all
    - --env=XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons
    - --share=ipc
    - --share=network
    - --socket=pulseaudio
    - --socket=x11

    # Filesystems
    - --filesystem=xdg-download

    # D-Bus Access
    - --talk-name=com.canonical.AppMenu.Registrar
    - --talk-name=org.freedesktop.Notifications
    - --talk-name=org.freedesktop.ScreenSaver
    - --talk-name=org.freedesktop.secrets
    - --talk-name=org.kde.StatusNotifierWatcher
    - --talk-name=org.kde.kwalletd5
    - --talk-name=org.kde.kwalletd6

    # System D-Bus Access
    - --system-talk-name=org.freedesktop.UPower
    - --system-talk-name=org.freedesktop.login1
```

Now it's time to translate the above to nix. Let's first see what we can ignore:

- `--device=all` can be ignored, since `bwrapper` by default already grants access to all devices.

- `--env=XCURSOR_PATH=/run/host/user-share/icons:/run/host/share/icons` can also be ignored, since the `$HOME/.icons`
  directory is mounted readonly as is, therefore this environment variable would only lead to confusion.

- `--socket=pulseaudio` and `--socket=x11` can be ignored, since pulseaudio and `X11` sockets are shared by default
  anyway.

That leaves the rest to be added. The final wrapper looks as follows:

```nix
{
  packages.slack-wrapped = pkgs.mkBwrapper {
    # basic settings
    app = {
      package = pkgs.slack;
      runScript = "slack";
      execArgs = "-s %U";
      # to make global menu work in KDE
      addPkgs = [
        pkgs.libdbusmenu
      ];
    };

    # taken from the .yaml file above
    mounts.readWrite = [
      "$HOME/Downloads"
    ];
    dbus.system.talks = [
      "org.freedesktop.UPower"
      "org.freedesktop.login1"
    ];
    dbus.session.talks = [
      "com.canonical.AppMenu.Registrar"
      "org.freedesktop.Notifications"
      "org.freedesktop.ScreenSaver"
      "org.freedesktop.secrets"
      "org.kde.StatusNotifierWatcher"
      "org.kde.kwalletd5"
      "org.kde.kwalletd6"
    ];
  };
}
```

Note that even though some dbus talks, e.g. `org.freedesktop.Notifications`, are already granted by `bwrapper` by
default, specifying it here again doesn't do any harm, since it filters for unique names anyway.

#### Your application does not have a flatpak

Begin with a minimal example (see the `flake.nix` for a minimal example using `brave`). Then, run your application from
a terminal (to see the logs it outputs). Use it as you would normally, if you notice something doesn't work quite right
(or at all), see if the terminal gives you a clue as to what's wrong. Amend your wrapper, and repeat.

As you might be able to tell, there's a lot of trial and error involved if you go down this route.

> [!TIP] Set `dbus.logging = true` to see which DBus interfaces the application attempts to access.
