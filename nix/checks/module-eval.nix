{ pkgs, module }:

pkgs.testers.nixosTest {
  name = "hal0-module-eval";

  nodes.machine = { ... }:
    {
      imports = [ module ];

      services.hal0 = {
        enable = true;
        package = pkgs.hello;
        settings = {
          server = { env = { TEST_FEATURE = "enabled"; }; };
        };
        providers = { local = { kind = "openai"; }; };
        upstreams = { local = { url = "http://127.0.0.1:8080/v1"; }; };
        profiles = { test = { device = "cpu"; }; };
        capabilities = { schema_version = 2; };
        slotConfigs.primary = {
          name = "primary";
          port = 8081;
          device = "cpu";
          model.default = "test-model";
        };
        agentConfigs.hermes = {
          type = "hermes";
          host = "127.0.0.1";
          port = 9119;
          serve_args = [ "--host" "127.0.0.1" ];
        };
        extraConfigFiles."custom.toml" = {
          mode = "0640";
          text = ''
            [custom]
            enabled = true
          '';
        };
        agents.hermes.enable = true;
        enableBench = true;
      };

      virtualisation.podman.enable = true;
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl cat hal0-api.service")
    machine.succeed("systemctl cat hal0-agent@.service")
    machine.succeed("systemctl cat hal0-bench.service")
    machine.succeed("systemctl cat hal0-bench.timer")
    machine.succeed("test -f /etc/hal0/hal0.toml")
    machine.succeed("test -f /etc/hal0/providers.toml")
    machine.succeed("test -f /etc/hal0/upstreams.toml")
    machine.succeed("test -f /etc/hal0/profiles.toml")
    machine.succeed("test -f /etc/hal0/capabilities.toml")
    machine.succeed("test -f /etc/hal0/slots/primary.toml")
    machine.succeed("test -f /etc/hal0/agents/hermes.toml")
    machine.succeed("test -f /etc/hal0/custom.toml")
    machine.succeed("id hal0")
    machine.succeed("test -r /etc/sudoers.d/hal0-systemctl")
    machine.succeed("systemctl is-enabled hal0-agent@hermes.service")
    machine.succeed("systemctl is-enabled hal0-bench.timer")
  '';
}
