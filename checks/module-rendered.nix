{ pkgs, nixosLib, module }:
let
  system = nixosLib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      module
      {
        services.hal0.enable = true;
        services.hal0.hindsight.enable = false;
        services.hal0.openwebui.enable = false;
        services.hal0.hermes.enable = false;
        services.hal0.benchWorker.enable = false;
        services.hal0.comfyui.enable = false;
      }
    ];
  };
  api = system.config.systemd.services.hal0-api.serviceConfig;
  agent = system.config.systemd.services."hal0-agent@".serviceConfig;
in
pkgs.runCommand "hal0-module-rendered-check" {} ''
  test '${api.Type}' = simple
  test -n '${api.ExecStart}'
  test -n '${agent.ExecStart}'
  touch $out
''
