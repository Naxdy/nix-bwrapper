{
  config,
  lib,
  pkgs,
  ...
}:
let
  dbusTalkDesc = ''
    A list of DBus names to grant the "TALK" permission to. The default initial policy of xdg-dbus-proxy
    is that the the user is only allowed to TALK to the bus itself (org.freedesktop.DBus,
    or no destination specified), and TALK to its own unique ID. All other clients are invisible.

    Here is a description of the policy levels (each level implies the ones before it):

    SEE

    - The name/ID is visible in the ListNames reply

    - The name/ID is visible in the ListActivatableNames reply

    - You can call GetNameOwner on the name

    - You can call NameHasOwner on the name

    - You see NameOwnerChanged signals on the name

    - You see NameOwnerChanged signals on the ID when the client disconnects

    - You can call the GetXXX methods on the name/ID to get e.g. the peer pid

    - You get AccessDenied rather than NameHasNoOwner when sending messages to the name/ID

    TALK

    - You can send any method calls and signals to the name/ID

    - You will receive broadcast signals from the name/ID (if you have a match rule for them)

    - You can call StartServiceByName on the name
  '';

  dbusCallDesc = ''
    A list of methods that may be called from the sandbox.

    Must be of the form [METHOD][@PATH], where METHOD can be either '*' or a D-Bus interface,
    possible with a '.*' suffix, or a fully-qualified method name, and PATH is a D-Bus object path,
    possible with a '/*' suffix.
  '';

  dbusBroadcastDesc = ''
    A list of methods that may be subcribed to from the sandbox.

    Must be of the form [METHOD][@PATH], where METHOD can be either '*' or a D-Bus interface,
    possible with a '.*' suffix, or a fully-qualified method name, and PATH is a D-Bus object path,
    possible with a '/*' suffix.
  '';

  cfg = config.dbus;

  commonDbusOpts = {
    talks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = dbusTalkDesc;
      apply = talks: map (e: "--talk=\"${e}\"") (lib.unique talks);
    };
    calls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = dbusCallDesc;
      apply = talks: map (e: "--call=\"${e}\"") (lib.unique talks);
    };
    broadcasts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = dbusBroadcastDesc;
      apply = talks: map (e: "--broadcast=\"${e}\"") (lib.unique talks);
    };
  };
in
{
  options.dbus = {
    logging = lib.mkEnableOption "dbus logging (useful for debugging purposes)";
    session = commonDbusOpts // {
      owns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Grants all permissions for "TALK", as well as:

          - You are allowed to call RequestName/ReleaseName/ListQueuedOwners on the name
        '';
        apply = talks: map (e: "--own=\"${e}\"") (lib.unique talks);
      };
      args = lib.mkOption {
        type = lib.types.str;
        internal = true;
      };
    };
    system = commonDbusOpts // {
      args = lib.mkOption {
        type = lib.types.str;
        internal = true;
      };
    };
  };

  config = {
    # Defaults declared here so they merge with user options by default instead of getting overwritten
    dbus.session.talks = [
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

    dbus.session.calls = [
      "org.freedesktop.portal.*=*@/org/freedesktop/portal/desktop"
    ];

    dbus.session.broadcasts = [
      "org.freedesktop.portal.Desktop=*@/org/freedesktop/portal/desktop"
    ];

    dbus.system.talks = [
      "com.canonical.AppMenu.Registrar"
      "com.canonical.Unity.LauncherEntry"
    ];

    app.env = {
      DBUS_SESSION_BUS_ADDRESS = "unix:path=$XDG_RUNTIME_DIR/bus";
    };

    dbus.session.args = builtins.concatStringsSep " \\\n      " (
      cfg.session.talks ++ cfg.session.calls ++ cfg.session.broadcasts ++ cfg.session.owns
    );

    dbus.system.args = builtins.concatStringsSep " \\\n      " (
      cfg.system.talks ++ cfg.system.calls ++ cfg.system.broadcasts
    );

    script.preCmds.stage2 = ''
      set_up_dbus_proxy() {
        ${pkgs.bubblewrap}/bin/bwrap \
          --new-session \
          --ro-bind /nix /nix \
          --bind "/run" "/run" \
          --ro-bind "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info" "/.flatpak-info" \
          --die-with-parent \
          --clearenv \
          -- \
          ${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy "$DBUS_SESSION_BUS_ADDRESS" "$XDG_RUNTIME_DIR/app/${config.app.id}/bus" --filter ${lib.optionalString cfg.logging "--log"} ${cfg.session.args}
      }

      set_up_system_dbus_proxy() {
        ${pkgs.bubblewrap}/bin/bwrap \
          --new-session \
          --ro-bind /nix /nix \
          --bind "/run" "/run" \
          --ro-bind "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info" "/.flatpak-info" \
          --die-with-parent \
          --clearenv \
          -- \
          ${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy unix:path=/run/dbus/system_bus_socket "$XDG_RUNTIME_DIR/app/${config.app.id}/bus_system" --filter ${lib.optionalString cfg.logging "--log"} ${cfg.system.args}
      }

      set_up_dbus_proxy &
      set_up_system_dbus_proxy &
      ${pkgs.coreutils}/bin/sleep 0.1
    '';

    fhsenv.bwrap.additionalArgs = [
      ''--bind "$XDG_RUNTIME_DIR/app/${config.app.id}/bus" "$XDG_RUNTIME_DIR/bus"''
      ''--bind "$XDG_RUNTIME_DIR/app/${config.app.id}/bus_system" /run/dbus/system_bus_socket''
    ];
  };
}
