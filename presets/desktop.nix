{ config, lib, ... }:
let
  inherit (lib) mkDefault;
in
{
  config = {
    app = {
      renameDesktopFile = true;
      overwriteExec = true;
    };

    dbus = {
      enable = mkDefault true;
      session = {
        talks = [
          "org.freedesktop.Notifications"
          "com.canonical.AppMenu.Registrar"
          "com.canonical.Unity.LauncherEntry"
          "org.freedesktop.ScreenSaver"
          "com.canonical.indicator.application"
          "org.kde.StatusNotifierWatcher"
          "org.freedesktop.portal.Documents"
          "org.freedesktop.portal.Flatpak"
          "org.freedesktop.portal.Desktop"
          "org.freedesktop.portal.Notifications"
          "org.freedesktop.portal.FileChooser"
        ];
        calls = [
          "org.freedesktop.portal.*=*@/org/freedesktop/portal/desktop"
        ];
        broadcasts = [
          "org.freedesktop.portal.Desktop=*@/org/freedesktop/portal/desktop"
        ];
      };
      system = {
        talks = [
          "com.canonical.AppMenu.Registrar"
          "com.canonical.Unity.LauncherEntry"
        ];
      };
    };

    sockets = {
      pipewire = mkDefault true;
      pulseaudio = mkDefault true;
      wayland = mkDefault true;

      # Enabling this is safe, because we use a separate `xwayland-satellite` for every sandbox.
      x11 = mkDefault true;
    };

    flatpak.enable = mkDefault true;

    fhsenv.performDesktopPostInstall = mkDefault (!config.app.isFhsenv);

    mounts = {
      read = [
        "$HOME/.icons"
        "$HOME/.fonts"
        "$HOME/.themes"
        "$HOME/.config/gtk-3.0"
        "$HOME/.config/gtk-4.0"
        "$HOME/.config/gtk-2.0"
        "$HOME/.config/Kvantum"
        "$HOME/.config/gtkrc-2.0"
        "$HOME/.local/share/color-schemes"
      ];

      sandbox = [
        {
          name = "config";
          path = "$HOME/.config";
        }
        {
          name = "local";
          path = "$HOME/.local";
        }
        {
          name = "cache";
          path = "$HOME/.cache";
        }
      ];
    };
  };

  meta = {
    name = "desktop";
    description = ''
      This preset enables various options useful for sandboxing most graphical desktop applications.

      Note that this merely includes basic options, such as allowing commonly used dbus interfaces, display & audio sockets,
      mounting directories needed for fonts, themes, etc.
    '';
  };
}
