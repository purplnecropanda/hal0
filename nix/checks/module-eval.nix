{ pkgs, module }:

pkgs.nixosTest {
  name = "hal0-module-eval";

  nodes.machine = { ... }:
    {
      imports = [ module ];

      services.hal0 = {
        enable = true;
        package = pkgs.hello;
      };

      virtualisation = {
        podman.enable = true;
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl cat hal0-api.service")
    machine.succeed("test -f /etc/hal0/hal0.toml")
    machine.succeed("id hal0")
    machine.succeed("test -f /etc/sudoers.d/hal0-systemctl")
  '';
}
