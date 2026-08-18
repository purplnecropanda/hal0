# NixOS

`hal0` is packaged as a NixOS deployment rather than only a Python/UI package. The default module composes the core hal0 service with its companion runtime graph and follows the AMD split used by `noamsto/nix-amd-ai`.

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

              # These are enabled by default and can be disabled independently.
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

## Runtime graph

The default module now declares the major services the upstream installer provisions:

- `hal0-api` — core control plane/API.
- rootless `hal0-agent@<id>` template support for declarative agent instances.
- `hal0-bench-worker` — dashboard benchmark queue worker.
- `hal0-bench` and `hal0-bench.timer` — scheduled benchmark sessions.
- Hindsight memory engine as an OCI companion, with persistent pg0/HF state and its OpenAI-compatible extraction/reflection endpoint pointed at hal0.
- OpenWebUI as the pinned Podman companion on port 3001, prewired to hal0 chat/STT/TTS endpoints.
- Hermes Agent as a persistent Podman companion with dashboard/API ports and a declarative custom-provider configuration pointing at hal0's `/v1` endpoint.
- Podman/Docker FORWARD reconciliation for hosts where Docker is installed alongside Podman.
- The upstream `hal0-systemctl` and `hal0-benchctl` restricted privileged seams.

The inference slot system remains Quadlet/Podman-based, exactly as in the upstream runtime. The AMD/NPU layer remains the responsibility of `nix-amd-ai`, including XRT, AMD-XDNA/FastFlowLM, ROCm, Vulkan, udev, device access, and memlock policy.

The companion images are intentionally configurable. Hindsight defaults to the 0.7.2 image used by hal0's current installer contract; OpenWebUI uses the release-pinned image digest shipped by the installer; Hermes defaults to the upstream v2026.7.7.2 image corresponding to the currently supported Hermes release line.

## Declarative vs mutable state

Nix owns service wiring and immutable defaults. Persistent runtime state lives under `/var/lib/hal0`, including model storage, Hindsight pg0/HF state, OpenWebUI data, Hermes data, benchmark state, and slot/registry state. The module exposes typed options plus complete TOML attrsets for advanced/upstream configuration surfaces.

`services.hal0.mutableConfig = true` preserves the upstream operator workflow for `hal0 config edit`, migrations, and runtime state updates. Set it to `false` when the host should reject imperative writes to generated `/etc/hal0` configuration.

## Security

The API defaults to loopback under NixOS (`127.0.0.1`) and OpenWebUI/Hermes default to loopback listeners as well; expose them explicitly when a LAN/reverse-proxy deployment is intended. The hal0 service user receives render/video access when those groups exist. Privileged lifecycle operations continue through the narrow helper binaries rather than granting arbitrary systemctl access.
