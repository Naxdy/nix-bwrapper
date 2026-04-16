{ testers }:
testers.runNixOSTest {
  name = "nix-bwrapper-hello-override";
  nodes = {
    machine =
      { config, pkgs, ... }:
      let
        bwrapped-hello = (
          pkgs.mkBwrapper {
            app = {
              package = pkgs.hello;
              runScript = "hello";
            };
          }
        );

        overridden = bwrapped-hello.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            +
            # bash
            ''
              substituteInPlace src/hello.c \
                --replace-fail "Hello, world!" "Hello, overridden!"
            '';

          doCheck = false;
        });
      in
      {
        environment.systemPackages = [
          overridden
        ];
      };
  };

  testScript =
    # python
    ''
      machine.wait_for_unit("default.target")

      t.assertIn("Hello, overridden!", machine.succeed("hello"), "wrong stdout")
    '';
}
