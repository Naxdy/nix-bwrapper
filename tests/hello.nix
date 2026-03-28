{ pkgs, ... }:
pkgs.testers.runNixOSTest {
  name = "nix-bwrapper-hello";
  nodes = {
    machine =
      { config, pkgs, ... }:
      {
        environment.systemPackages = [
          (pkgs.mkBwrapper {
            app = {
              package = pkgs.hello;
              runScript = "hello";
            };
          })
        ];
      };
  };

  testScript = ''
    machine.wait_for_unit("default.target")

    machine.succeed("hello")
  '';
}
