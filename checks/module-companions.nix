{ pkgs, module }:
let
  system = pkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./../modules/hal0/core.nix
      module
      {
        services.hal0 = {
          enable = true;
          hindsight.enable = false;
          openwebui.enable = false;
          hermes.enable = false;
          benchWorker.enable = false;
          comfyui.enable = false;
        };
      }
    ];
  };
in
pkgs.runCommand "hal0-module-companions-check" {} ''
  test '${toString system.config.virtualisation.oci-containers.backend}' = podman
  test -n '${system.config.systemd.tmpfiles.rules}'
  touch $out
''
