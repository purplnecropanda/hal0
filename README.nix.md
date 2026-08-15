# NixOS

`hal0` is packaged as a flake and exposes a NixOS module. The flake follows the
same AMD runtime split as `noamsto/nix-amd-ai`: the application owns the control
plane and Podman/Quadlet lifecycle, while the AMD/NPU stack remains supplied by
`nix-amd-ai`.

## Example

```nix
{
  inputs.hal0.url = "github:purplnecropanda/hal0";
  inputs.nix-amd-ai.url = "github:noamsto/nix-amd-ai";

  outputs = { self, nixpkgs, hal0, nix-amd-ai, ... }:
    {
      nixosConfigurations.host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          nix-amd-ai.nixosModules.default
          hal0.nixosModules.default
          ({ config, ... }: {
            hardware.amd-npu = {
              enable = true;
              enableNPU = true;
              enableFastFlowLM = true;
              enableROCm = true;
              enableVulkan = true;
            };

            services.hal0 = {
              enable = true;
              bindHost = "0.0.0.0";
              modelStore = "/data/models";
              flmModelStore = "/data/flm-models";
              agents.hermes.enable = false;
            };
          })
        ];
      };
    };
}
```

`hardware.amd-npu` stays the source of truth for XRT, AMD-XDNA/FLM, ROCm,
Vulkan, udev, render/video permissions, and the memlock requirements. Enabling a
hal0 service does not silently mutate those options.

The NixOS module creates the dedicated `hal0` service user, Podman/Quadlet
runtime directories, `hal0-api.service`, `hal0.target`, optional agent template
instances, a declarative `/etc/hal0/hal0.toml`, and the narrow `hal0-systemctl`
sudo seam used by the upstream slot lifecycle.
