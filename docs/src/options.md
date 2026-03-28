# Options

```admonish note
A comprehensive interactive option search is available at <https://naxdy.github.io/nix-bwrapper/options-search>
```

## Desktop Applications

Nix-Bwrapper provides a preset under `bwrapperPresets.desktop` that is preconfigured in such a way that it should
integrate with your DE and your theming, and as such includes a number of read-only mounts for some of your home
directories (e.g. `~/.fonts`, `~/.icons`, etc.). If you don't need this behavior (e.g. because you're sandboxing a CLI
app), you can omit importing this preset.

For details on the exact configuration this preset provides, see its [doc page](./prsets/desktop.md).

The preset's configuration can be overridden just like in any other NixOS module, by using `lib.mkForce`. For example:

```nix
{
  packages.discord-wrapped = pkgs.mkBwrapper {
    imports = [ pkgs.bwrapperPresets.desktop ];
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

Additionally, `bwrapperPresets.desktop` will attempt to bind `pulse`, `pipewire` and `wayland` sockets from
`$XDG_RUNTIME_DIR`.

If `sockets.x11` is enabled (which `bwrapperPresets.desktop` enables by default), Nix-Bwrapper will also provide an
`X11` socket via [xwayland-satellite](https://github.com/Supreeeme/xwayland-satellite). This ensures that every
sandboxed app receives its own `xorg` instance, meaning that sandboxed `X11` apps cannot spy on each other.

This can be disabled by setting the respective `sockets` option to `false`:

```nix
{
  packages.slack-wrapped = pkgs.mkBwrapper {
    imports = [ pkgs.bwrapperPresets.desktop ];
    app = {
      package = pkgs.slack;
      runScript = "slack";
      execArgs = "-s %U";
    };
    sockets.x11 = false; # do not spawn an X11 socket in this sandbox
    # ...
  };
}
```

Sandboxed files are stored in `$HOME/.bwrapper/${config.app.bwrapPath}` on the host system.

Access is granted to all hardware devices by default.
