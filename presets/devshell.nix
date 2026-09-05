{ lib, ... }:
let
  inherit (lib) mkDefault;
in
{
  config = {
    fhsenv = {
      opts.unshareNet = mkDefault false;

      bwrap.additionalArgs = [
        ''"''${user_rw_binds[@]}"''
        ''"''${user_ro_binds[@]}"''
      ];
    };

    mounts = {
      readWrite = [
        "$PWD"
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
        {
          name = "cargo";
          path = "$HOME/.cargo";
        }
      ];
    };

    script.preCmds.stage3 = ''
      declare -a user_rw_binds

      # Parse BWRAP_MOUNTS_RW: colon-separated list of paths to bind-mount read-write.
      # User-specified and trusted. Sanitized to prevent weird characters or spaces
      # from breaking the script. Paths canonicalized to absolute form via realpath.
      if [[ -n "''${BWRAP_MOUNTS_RW:-}" ]]; then
        BWRAP_SAVE_IFS="$IFS"
        IFS=':'
        read -r -a bwrap_mount_paths <<< "$BWRAP_MOUNTS_RW"
        IFS="$BWRAP_SAVE_IFS"

        for raw_path in "''${bwrap_mount_paths[@]}"; do
          # Skip empty entries (consecutive/leading/trailing colons)
          if [[ -z "$raw_path" ]]; then continue; fi

          # Canonicalize: resolve . and .. components, make path absolute
          sanitized="$(realpath -m -- "$raw_path" 2>/dev/null)" || sanitized=""

          # Skip if canonicalization failed or produced non-absolute path
          if [[ -z "$sanitized" ]]; then continue; fi
          if [[ "$sanitized" != /* ]]; then continue; fi

          user_rw_binds+=("--bind" "$sanitized" "$sanitized")
        done
      fi

      declare -a user_ro_binds

      if [[ -n "''${BWRAP_MOUNTS_RO:-}" ]]; then
        BWRAP_SAVE_IFS="$IFS"
        IFS=':'
        read -r -a bwrap_mount_paths <<< "$BWRAP_MOUNTS_RO"
        IFS="$BWRAP_SAVE_IFS"

        for raw_path in "''${bwrap_mount_paths[@]}"; do
          if [[ -z "$raw_path" ]]; then continue; fi

          sanitized="$(realpath -m -- "$raw_path" 2>/dev/null)" || sanitized=""

          if [[ -z "$sanitized" ]]; then continue; fi
          if [[ "$sanitized" != /* ]]; then continue; fi

          user_ro_binds+=("--ro-bind" "$sanitized" "$sanitized")
        done
      fi
    '';
  };

  meta = {
    name = "devshell";
    description = ''
      A preset designed to be used as part of a development environment, for example to confine AI agents, or to limit the
      impact of potentially malicious dependencies / supply chain attacks, as seen in the past with providers like npm,
      cargo, or pypi.

      Confines any application to the current directory (at time of execution), and provides persistence within the sandbox
      for a number of commonly used directories (e.g. `$HOME/.cache`).

      Additional read-write and read-only directories may be added by specifying the `BWRAP_MOUNTS_RW` and `BWRAP_MOUNTS_RO`
      environment variables at runtime respectively. Both take in colon-separated lists of paths. For example:

      ```bash
      cd ~/git/my-project

      BWRAP_MOUNTS_RO="$HOME/git/my-other-project" nvim-bwrapped
      ```

      This spawns a bwrapped `nvim` with read-write access to `$HOME/my-projets` (since that's the current directory), and
      read-only access to `$HOME/git/my-other-project`. The two environment variables can be combined:

      ```bash
      cd ~/git/my-project

      BWRAP_MOUNTS_RO="$HOME/git/my-readwrite-project:$HOME/git/my-other-readonly-project" BWRAP_MOUNTS_RW="$HOME/git/my-readwrite-project" nvim-bwrapped
      ```

      This allows you to sandbox commonly used tools like text editors without having to create separate wrappers for each
      use case, having to move directories around, or invoking the tools from a parent directory, which may expose more
      information than is necessary.
    '';
  };
}
