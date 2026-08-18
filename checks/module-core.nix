{ pkgs, nixosLib, module }:
let
  system = nixosLib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      module
      {
        services.hal0.enable = true;
        services.hal0.port = 8080;
      }
    ];
  };
in
pkgs.runCommand "hal0-module-core-check" {} ''
  test '${toString system.config.services.hal0.port}' = 8080
  test -n '${system.config.systemd.services.hal0-api.serviceConfig.ExecStart}'
  touch $out
''
