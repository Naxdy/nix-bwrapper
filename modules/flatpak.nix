{ config, lib, ... }:
{
  fhsenv.bwrap.additionalArgs = [
    "--tmpfs \"$XDG_RUNTIME_DIR/.flatpak/0\""
    "--ro-bind \"$HOME/.bwrapper/${config.app.bwrapPath}/.bwrapinfo\" \"$XDG_RUNTIME_DIR/.flatpak/0/bwrapinfo.json\""
    "--ro-bind \"$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info\" \"/.flatpak-info\""
  ];

  script.preCmds.stage1 = ''
    test -f "$HOME/.bwrapper/${config.app.id}/.flatpak-info" && rm "$HOME/.bwrapper/${config.app.id}/.flatpak-info"
    test -f "$HOME/.bwrapper/${config.app.id}/.bwrapinfo" && rm "$HOME/.bwrapper/${config.app.id}/.bwrapinfo"

    printf "[Application]\nname=${config.app.id}\n\n[Instance]\ninstance-id = 0\nsystem-bus-proxy = true\nsession-bus-proxy = true\n" > "$HOME/.bwrapper/${config.app.bwrapPath}/.flatpak-info"
    printf '{"child-pid": 0, "mnt-namespace": 0, "net-namespace": 0, "pid-namespace": 0}' > "$HOME/.bwrapper/${config.app.bwrapPath}/.bwrapinfo"
  '';
}
