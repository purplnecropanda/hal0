# NixOS

`hal0` is packaged as a complete NixOS deployment rather than only a Python/UI package. The default module composes the core service, model/bootstrap lifecycle, inference tooling, and companion runtime graph, while `noamsto/nix-amd-ai` remains authoritative for the AMD/NPU substrate.

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
              hindsight.enable = true;
              openwebui.enable = true;
              hermes.enable = true;
              benchWorker.enable = true;
            };
          })
        ];
      };
    };
}
```

## Deployment graph

A fresh NixOS host gets declarative equivalents of the load-bearing installer stages:

- `hal0-api` control plane and OpenAI-compatible gateway.
- Quadlet/rootful Podman slot lifecycle and the `hal0-agent@<id>` template.
- Static slot/profile seed assets copied to writable `/etc/hal0` only when absent, preserving tombstones and operator edits.
- `hal0 setup --auto --no-pull --no-extensions` bootstrap for capability/slot scaffolding.
- Hardware-aware brain-model provisioning using the same curated HAL0 model logic as the installer, with optional HF token and model override.
- Optional Hermes fallback-agent model provisioning.
- Hindsight memory service with persistent pg0 and HF cache.
- OpenWebUI companion with chat, STT and TTS routes pointed at hal0.
- Hermes Agent companion with persistent state, dashboard/API options and Hindsight integration.
- Benchmark worker plus scheduled benchmark service/timer.
- ComfyUI model/share setup and its shipped `extra_model_paths.yaml` assets.
- Rootful Podman host setup and root lingering for stable container netns lifecycle.
- All shipped privileged helper wrappers, including `hal0-systemctl`, `hal0-agentenv`, `hal0-benchctl`, `hal0-podman-ro`, and `hal0-update`, with narrowly scoped NixOS sudo grants.
- Release/toolbox manifest and the shipped installer/systemd/config assets.

## AMD stack

`hardware.amd-npu` from `nix-amd-ai` remains the source of truth for XRT, AMD-XDNA/FastFlowLM, ROCm, Vulkan, udev, device access and memlock. The hal0 package consumes the corresponding runtime packages instead of duplicating that platform layer.

## Persistent state

Nix owns immutable package/service definitions. Mutable runtime state lives below `/etc/hal0` and `/var/lib/hal0`, including models, slot/registry state, Hindsight data, OpenWebUI data, Hermes data, and benchmark state.

`services.hal0.mutableConfig = true` preserves the upstream CLI/migration behavior. Set it to `false` for a strictly declarative configuration posture.

## Networking and security

The API defaults to loopback. OpenWebUI and Hermes default to loopback listeners as well. Explicitly expose them only when the host/reverse proxy is intended to serve LAN clients.

The API/service user keeps render/video access where those groups exist. Rootful lifecycle and write operations go through the packaged, argument-constrained helper seams rather than arbitrary systemctl or root shell access.
