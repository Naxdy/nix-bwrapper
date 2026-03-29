# Packaging Applications

Packaging applications is easiest if your application exists as a flatpak. In this case, you can simply import the
flatpak manifest into `config.flatpak.manifestFile` and have Nix-Bwrapper handle most (if not all) of the necessary
configuration for you.

When doing this, you can of course still add / revoke additional permissions using the module system as necessary.

## Your application has a flatpak manifest

If the application has a Flatpak manifest (either `.json` or `.yaml`/`.yml`), you can pre-fill most of bwrapper's
options by setting `flatpak.manifestFile` accordingly. For example, for librewolf you could have:

```nix
{
  packages.librewolf-wrapped = pkgs.mkBwrapper {
    imports = [ pkgs.bwrapperPresets.desktop ];
    app.package = pkgs.librewolf;
    flatpak.manifestFile = pkgs.fetchurl {
      url = "https://github.com/flathub/io.gitlab.librewolf-community/raw/refs/heads/master/io.gitlab.librewolf-community.json";
      hash = "...";
    };
  };
}
```

YAML manifests are also supported directly:

```nix
{
  packages.signal-wrapped = pkgs.mkBwrapper {
    imports = [ pkgs.bwrapperPresets.desktop ];
    app.package = pkgs.signal-desktop;
    flatpak.manifestFile = pkgs.fetchurl {
      url = "https://github.com/flathub/org.signal.Signal/raw/refs/heads/master/org.signal.Signal.yaml";
      hash = "...";
    };
  };
}
```

The manifest is automatically normalized at build time, including conversion of the `app-id` field (used in YAML
manifests) to `id` (used in JSON manifests).

This will already take care of most (if not all) necessary options for you. You can still override options normally
using Nix' module system, e.g. to disallow access to some directory or socket that is listed in the manifest by default.

At the moment, bwrapper supports pre-filling options for the following:

- `app.id`
- `app.env` variables
- sockets: `pulseaudio`, `pipewire`, `cups`
- fhsenv options: `unshareNet`, `unshareIpc`
- `mounts.read` and `mounts.readWrite`, including substitutions for: `home`, `xdg-desktop`, `xdg-documents`,
  `xdg-download`, `xdg-music`, `xdg-pictures`, `xdg-public-share`, `xdg-templates`, `xdg-videos`, `xdg-run`,
  `xdg-config`, `xdg-cache`, `xdg-data`
- `mounts.sandbox`
- `dbus.{session,system}.{talks,owns,calls}`

### Inspecing & overriding options

If you want to see exactly what the final config will be, you can use `bwrapperEval` and inspect the resulting `config`
attribute, for example:

```nix
{
  packages.my-librewolf-config = (pkgs.bwrapperEval {
    imports = [ pkgs.bwrapperPresets.desktop ];
    flatpak.manifestFile = pkgs.fetchurl {
      url = "https://github.com/flathub/io.gitlab.librewolf-community/raw/refs/heads/master/io.gitlab.librewolf-community.json";
      hash = "...";
    };
  }).config;
}
```

Then you can run `nix eval .#my-librewolf-config` to get a full dump of your final config, or run something like
`nix eval .#my-librewolf-config.app` instead, to only inspect parts of it.

You can also pass `--json` to parts of the config that can be converted to valid JSON, i.e. anything not under `build`.
For example, running `nix eval .#my-librewolf-config.app --json` could produce something like this:

```json
{
  "addPkgs": [
    "/nix/store/wbmwh79ccgjfm6xl9zgxrk6l62xivds6-gtk+3-3.24.49-dev"
  ],
  "bwrapPath": "librewolf",
  "env": {
    "DBUS_SESSION_BUS_ADDRESS": "unix:path=$XDG_RUNTIME_DIR/bus",
    "DICPATH": "/usr/share/hunspell",
    "MOZ_USE_XINPUT2": "1",
    "NOTIFY_IGNORE_PORTAL": 1,
    "WAYLAND_DISPLAY": "$WAYLAND_DISPLAY"
  },
  "execArgs": "",
  "id": "io.gitlab.librewolf-community",
  "isFhsenv": false,
  "overwriteExec": true,
  "package": "/nix/store/g91s89dc8lwnwdwhnyr2mq02k5xnc227-librewolf-143.0-1",
  "package-unwrapped": null,
  "renameDesktopFile": true,
  "runScript": "librewolf"
}
```

If you then decide, for example, that you want to change the app id, or add an additional environment variable, you can
do this as follows:

```nix
{
  packages.my-librewolf-config = (pkgs.bwrapperEval {
    imports = [ pkgs.bwrapperPresets.desktop ];
    flatpak.manifestFile = pkgs.fetchurl {
      url = "https://github.com/flathub/io.gitlab.librewolf-community/raw/refs/heads/master/io.gitlab.librewolf-community.json";
      hash = "...";
    };
    app = {
      # will completely override the app id from the manifest
      id = pkgs.lib.mkForce "my-custom-id";
      env = {
        # will be merged with the env vars from the manifest file
        MY_CUSTOM_ENV_VAR = "example";
      };
    };
  }).config;
}
```

## Manually packaging applications with help of a manifest

If the application doesn't have a suitable Flatpak manifest, or you prefer to configure permissions manually, you can
specify all options explicitly.

First, obtain the info about the permissions the app needs:

1. Go to [flathub.org](https://flathub.org) and look for the application you want to wrap. We'll use
   [Slack](https://flathub.org/apps/com.slack.Slack) as an example here.

1. At the bottom, click on "Links", and then "Manifest". For Slack, it should lead you
   [here](https://github.com/flathub/com.slack.Slack).

1. Open the manifest file (`.json`, `.yaml`, or `.yml`), in this case `com.slack.Slack.yaml`

This file shows all the permissions that are being granted to the application. You can use this as a blueprint for which
permissions to grant in your wrapper. We can see that the file contains the following:

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
    imports = [ pkgs.bwrapperPresets.desktop ];
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

## Your application does not have a flatpak manifest

Begin with a minimal example (see the `flake.nix` for a minimal example using `brave`). Then, run your application from
a terminal (to see the logs it outputs). Use it as you would normally, if you notice something doesn't work quite right
(or at all), see if the terminal gives you a clue as to what's wrong. Amend your wrapper, and repeat.

As you might be able to tell, there's a lot of trial and error involved if you go down this route.

```admonish tip
Set `dbus.logging = true` to see which DBus interfaces the application attempts to access.
```
