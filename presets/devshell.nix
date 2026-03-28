{ ... }:
{
  config = {
    mounts = {
      write = [
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
      ];
    };
  };

  meta = {
    name = "devshell";
    description = ''
      A preset designed to be used as part of a development environment, for example to confine AI agents, or to limit the
      impact of potentially malicious dependencies / supply chain attacks.

      Confines any application to the current directory (at time of execution), and provides persistence within the sandbox
      for a number of commonly used directores (e.g. `$HOME/.cache`).
    '';
  };
}
