# NixOS

`hal0` is packaged as a flake and exposes a NixOS module. The flake follows the
AMD runtime split used by `noamsto/nix-amd-ai`: hal0 owns its control plane,
Podman/Quadlet lifecycle, model/config state and UI, while the AMD/NPU runtime
is supplied by `nix-amd-ai`.

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
          ({ ... }: {
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

              # Complete slot/schema fields can be represented here.
              slotConfigs.primary = {
                name = "primary";
                port = 8081;
                device = "gpu-vulkan";
                n_gpu_layers = -1;
                model.default = "my-model";
              };
            };
          })
        ];
      };
    };
}
```

## Feature coverage

The Nix package preserves the repository's complete Python package and bundled
assets rather than selecting only the API server. It includes the CLI surfaces
for slots, models, registry, profiles, providers/upstreams, capabilities,
MCP, memory, board, ComfyUI, agents, auth, setup/migration, diagnostics,
benchmarking, chat and system information, plus the dashboard build.

The NixOS module exposes deployment controls directly and provides full-schema
escape hatches:

- `services.hal0.settings` → `hal0.toml`
- `services.hal0.providers` → `providers.toml`
- `services.hal0.upstreams` → `upstreams.toml`
- `services.hal0.profiles` → `profiles.toml`
- `services.hal0.capabilities` → `capabilities.toml`
- `services.hal0.slotConfigs` → `slots/*.toml`
- `services.hal0.extraConfigFiles` → additional `/etc/hal0/*` files

This is intentional: hal0's Pydantic schema evolves frequently, so modelling
only today's fields in Nix would make the package lag behind upstream. The
module's typed options cover common service/runtime controls while the
attrset/TOML interface keeps the complete upstream configuration surface
available.

`services.hal0.enableBench` enables the repository's scheduled benchmark unit
and timer. The package also ships the audited `hal0-benchctl` and
`hal0-systemctl` privileged seams.

## AMD/NPU integration

`hardware.amd-npu` remains the source of truth for XRT, AMD-XDNA/FLM, ROCm,
Vulkan, udev, kernel/NPU setup and render/video permissions. The hal0 module
consumes runtime packages from `nix-amd-ai` and does not duplicate that
hardware stack.

For NPU-capable systems, import both modules and enable the desired
`hardware.amd-npu` features. For GPU-only systems, use the corresponding
`nix-amd-ai` GPU configuration and leave the NPU path disabled.

## Validation

The repository includes a NixOS module test that evaluates the configuration
surface, creates a declarative slot and agent, verifies the benchmark timer,
checks generated `/etc/hal0` files, and checks the privileged seam.

The package still requires the generated `npmDepsHash` to be materialized by a
network-enabled Nix build before the first release/merge. No fabricated fixed
output hash is used.
