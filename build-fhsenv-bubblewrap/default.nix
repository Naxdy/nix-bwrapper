{
  lib,
  stdenv,
  callPackage,
  runCommandLocal,
  writeShellScript,
  glibc,
  pkgsi686Linux,
  coreutils,
  bubblewrap,
  nixpkgs,
}:

{
  runScript ? "bash",
  nativeBuildInputs ? [ ],
  extraInstallCommands ? "",
  meta ? { },
  passthru ? { },
  extraPreBwrapCmds ? "",
  extraBwrapArgs ? [ ],
  unshareUser ? false,
  unshareIpc ? false,
  unsharePid ? false,
  unshareNet ? false,
  unshareUts ? false,
  unshareCgroup ? false,
  privateTmp ? false,
  dieWithParent ? true,
  ...
}@args:

assert (!args ? pname || !args ? version) -> (args ? name); # You must provide name if pname or version (preferred) is missing.

let
  inherit (lib)
    concatLines
    concatStringsSep
    escapeShellArgs
    filter
    optionalString
    splitString
    ;

  inherit (lib.attrsets) removeAttrs;

  name = args.name or "${args.pname}-${args.version}";
  executableName = args.pname or args.name;
  # we don't know which have been supplied, and want to avoid defaulting missing attrs to null. Passed into runCommandLocal
  nameAttrs = lib.filterAttrs (
    key: value:
    builtins.elem key [
      "name"
      "pname"
      "version"
    ]
  ) args;

  buildFHSEnv =
    callPackage "${nixpkgs}/pkgs/build-support/build-fhsenv-bubblewrap/buildFHSEnv.nix"
      { };

  fhsenv = buildFHSEnv (
    removeAttrs args [
      "runScript"
      "extraInstallCommands"
      "meta"
      "passthru"
      "extraPreBwrapCmds"
      "extraBwrapArgs"
      "dieWithParent"
      "unshareUser"
      "unshareCgroup"
      "unshareUts"
      "unshareNet"
      "unsharePid"
      "unshareIpc"
      "privateTmp"
    ]
  );

  etcBindEntries =
    let
      files = [
        # NixOS Compatibility
        "static"
        "nix" # mainly for nixUnstable users, but also for access to nix/netrc
        # Shells
        "shells"
        "bashrc"
        "zshenv"
        "zshrc"
        "zinputrc"
        "zprofile"
        # Users, Groups, NSS
        "passwd"
        "group"
        "shadow"
        "hosts"
        "resolv.conf"
        "nsswitch.conf"
        # User profiles
        "profiles"
        # Sudo & Su
        "login.defs"
        "sudoers"
        "sudoers.d"
        # Time
        "localtime"
        "zoneinfo"
        # Other Core Stuff
        "machine-id"
        "os-release"
        # PAM
        "pam.d"
        # Fonts
        "fonts"
        # ALSA
        "alsa"
        "asound.conf"
        # SSL
        "ssl/certs"
        "ca-certificates"
        "pki"
      ];
    in
    map (path: "/etc/${path}") files;

  # Create this on the fly instead of linking from /nix
  # The container might have to modify it and re-run ldconfig if there are
  # issues running some binary with LD_LIBRARY_PATH
  createLdConfCache = ''
    cat > /etc/ld.so.conf <<EOF
    /lib
    /lib/x86_64-linux-gnu
    /lib64
    /usr/lib
    /usr/lib/x86_64-linux-gnu
    /usr/lib64
    /lib/i386-linux-gnu
    /lib32
    /usr/lib/i386-linux-gnu
    /usr/lib32
    /run/opengl-driver/lib
    /run/opengl-driver-32/lib
    EOF
    ldconfig &> /dev/null
  '';
  init =
    run:
    writeShellScript "${name}-init" ''
      source /etc/profile
      ${createLdConfCache}
      ${run} "$@"
    '';

  indentLines = str: concatLines (map (s: "  " + s) (filter (s: s != "") (splitString "\n" str)));
  bwrapCmd =
    {
      initArgs ? "",
    }:
    ''
      ignored=(/nix /dev /proc /etc ${optionalString privateTmp "/tmp"})
      ro_mounts=()
      symlinks=()
      etc_ignored=()

      ${extraPreBwrapCmds}

      # loop through all entries of root in the fhs environment, except its /etc.
      for i in ${fhsenv}/*; do
        path="/''${i##*/}"
        if [[ $path == '/etc' ]]; then
          :
        elif [[ -L $i ]]; then
          symlinks+=(--symlink "$(${coreutils}/bin/readlink "$i")" "$path")
          ignored+=("$path")
        else
          ro_mounts+=(--ro-bind "$i" "$path")
          ignored+=("$path")
        fi
      done

      # loop through the entries of /etc in the fhs environment.
      if [[ -d ${fhsenv}/etc ]]; then
        for i in ${fhsenv}/etc/*; do
          path="/''${i##*/}"
          # NOTE: we're binding /etc/fonts and /etc/ssl/certs from the host so we
          # don't want to override it with a path from the FHS environment.
          if [[ $path == '/fonts' || $path == '/ssl' ]]; then
            continue
          fi
          if [[ -L $i ]]; then
            symlinks+=(--symlink "$i" "/etc$path")
          else
            ro_mounts+=(--ro-bind "$i" "/etc$path")
          fi
          etc_ignored+=("/etc$path")
        done
      fi

      # propagate /etc from the actual host if nested
      if [[ -e /.host-etc ]]; then
        ro_mounts+=(--ro-bind /.host-etc /.host-etc)
      else
        ro_mounts+=(--ro-bind /etc /.host-etc)
      fi

      # link selected etc entries from the actual root
      for i in ${escapeShellArgs etcBindEntries}; do
        if [[ "''${etc_ignored[@]}" =~ "$i" ]]; then
          continue
        fi
        if [[ -e $i ]]; then
          symlinks+=(--symlink "/.host-etc/''${i#/etc/}" "$i")
        fi
      done

      declare -a auto_mounts
      # loop through all directories in the root
      for dir in /*; do
        # if it is a directory and it is not ignored
        if [[ -d "$dir" ]] && [[ ! "''${ignored[@]}" =~ "$dir" ]]; then
          # add it to the mount list
          auto_mounts+=(--bind "$dir" "$dir")
        fi
      done

      declare -a x11_args
      # Always mount a tmpfs on /tmp/.X11-unix
      # Rationale: https://github.com/flatpak/flatpak/blob/be2de97e862e5ca223da40a895e54e7bf24dbfb9/common/flatpak-run.c#L277
      x11_args+=(--tmpfs /tmp/.X11-unix)

      # Try to guess X socket path. This doesn't cover _everything_, but it covers some things.
      if [[ "$DISPLAY" == *:* ]]; then
        # recover display number from $DISPLAY formatted [host]:num[.screen]
        display_nr=''${DISPLAY/#*:} # strip host
        display_nr=''${display_nr/%.*} # strip screen
        local_socket=/tmp/.X11-unix/X$display_nr
        x11_args+=(--ro-bind-try "$local_socket" "$local_socket")
      fi

      ${optionalString privateTmp ''
        # sddm places XAUTHORITY in /tmp
        if [[ "$XAUTHORITY" == /tmp/* ]]; then
          x11_args+=(--ro-bind-try "$XAUTHORITY" "$XAUTHORITY")
        fi

        # dbus-run-session puts the socket in /tmp
        IFS=";" read -ra addrs <<<"$DBUS_SESSION_BUS_ADDRESS"
        for addr in "''${addrs[@]}"; do
          [[ "$addr" == unix:* ]] || continue
          IFS="," read -ra parts <<<"''${addr#unix:}"
          for part in "''${parts[@]}"; do
            printf -v part '%s' "''${part//\\/\\\\}"
            printf -v part '%b' "''${part//%/\\x}"
            [[ "$part" == path=/tmp/* ]] || continue
            x11_args+=(--ro-bind-try "''${part#path=}" "''${part#path=}")
          done
        done
      ''}

      cmd=(
        ${bubblewrap}/bin/bwrap
        --dev-bind /dev /dev
        --proc /proc
        --chdir "$(pwd)"
        ${optionalString unshareUser "--unshare-user"}
        ${optionalString unshareIpc "--unshare-ipc"}
        ${optionalString unsharePid "--unshare-pid"}
        ${optionalString unshareNet "--unshare-net"}
        ${optionalString unshareUts "--unshare-uts"}
        ${optionalString unshareCgroup "--unshare-cgroup"}
        ${optionalString dieWithParent "--die-with-parent"}
        --ro-bind /nix/store /nix/store
        ${optionalString privateTmp "--tmpfs /tmp"}
        # Our glibc will look for the cache in its own path in `/nix/store`.
        # As such, we need a cache to exist there, because pressure-vessel
        # depends on the existence of an ld cache. However, adding one
        # globally proved to be a bad idea (see #100655), the solution we
        # settled on being mounting one via bwrap.
        # Also, the cache needs to go to both 32 and 64 bit glibcs, for games
        # of both architectures to work.
        --tmpfs ${glibc}/etc \
        --tmpfs /etc \
        --symlink /etc/ld.so.conf ${glibc}/etc/ld.so.conf \
        --symlink /etc/ld.so.cache ${glibc}/etc/ld.so.cache \
        --ro-bind ${glibc}/etc/rpc ${glibc}/etc/rpc \
        --remount-ro ${glibc}/etc \
    ''
    + optionalString fhsenv.isMultiBuild (indentLines ''
      --tmpfs ${pkgsi686Linux.glibc}/etc \
      --symlink /etc/ld.so.conf ${pkgsi686Linux.glibc}/etc/ld.so.conf \
      --symlink /etc/ld.so.cache ${pkgsi686Linux.glibc}/etc/ld.so.cache \
      --ro-bind ${pkgsi686Linux.glibc}/etc/rpc ${pkgsi686Linux.glibc}/etc/rpc \
      --remount-ro ${pkgsi686Linux.glibc}/etc \
    '')
    + ''
        "''${ro_mounts[@]}"
        "''${symlinks[@]}"
        "''${auto_mounts[@]}"
        "''${x11_args[@]}"
        ${concatStringsSep "\n  " extraBwrapArgs}
        ${init runScript} ${initArgs}
      )
      "''${cmd[@]}"
    '';

  bin = writeShellScript "${name}-bwrap" (bwrapCmd {
    initArgs = ''"$@"'';
  });
in
runCommandLocal name
  (
    nameAttrs
    // {
      inherit nativeBuildInputs meta;

      passthru = passthru // {
        env =
          runCommandLocal "${name}-shell-env"
            {
              shellHook = bwrapCmd { };
            }
            ''
              echo >&2 ""
              echo >&2 "*** User chroot 'env' attributes are intended for interactive nix-shell sessions, not for building! ***"
              echo >&2 ""
              exit 1
            '';
        inherit args fhsenv;
      };
    }
  )
  ''
    mkdir -p $out/bin
    ln -s ${bin} $out/bin/${executableName}

    ${extraInstallCommands}
  ''
