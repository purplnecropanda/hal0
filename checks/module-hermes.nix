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
        services.hal0.benchWorker.enable = false;
        services.hal0.comfyui.enable = false;
      }
    ];
  };
in
pkgs.runCommand "hal0-module-hermes-check" {} ''
  test '${system.config.services.hal0.hermes.runtime}' = native
  test -n '${system.config.systemd.services.hal0-hermes-provision.serviceConfig.ExecStart}'
  test -n '${system.config.systemd.services."hal0-agent@".serviceConfig.ExecStart}'
  touch $out
''
