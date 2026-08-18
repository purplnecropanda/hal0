{
  description = "hal0 — open-source home AI inference platform, packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ inputs, ... }:
      {
        systems = [ "x86_64-linux" ];

        perSystem = { pkgs, system, ... }:
          let
            amdAiPkgs = inputs.nix-amd-ai.packages.${system};
            hal0 = pkgs.callPackage ./nix/package.nix {
              inherit (amdAiPkgs)
                fastflowlm
                xrt
                xrt-plugin-amdxdna
                llama-cpp-vulkan
                llama-cpp-rocm
                whisper-cpp-vulkan
                stable-diffusion-cpp-vulkan
                stable-diffusion-cpp-rocm
                ;
            };
          in
          {
            packages = {
              inherit hal0;
              default = hal0;
            };

            checks.nixos-module = import ./nix/checks/module-eval.nix {
              inherit pkgs;
              module = ./nix/nixos-module.nix;
            };

            checks.nixos-default-module = import ./nix/checks/module-eval.nix {
              inherit pkgs;
              module = {
                imports = [ ./nix/nixos-module.nix ./nix/companion-module.nix ];
              };
            };
          };

        flake = {
          nixosModules.default = {
            imports = [
              ./nix/nixos-module.nix
              ./nix/companion-module.nix
            ];
          };
          nixosModules.core = import ./nix/nixos-module.nix;
          nixosModules.companions = import ./nix/companion-module.nix;
          overlays.default = final: prev: {
            hal0 = final.callPackage ./nix/package.nix {
              inherit (inputs.nix-amd-ai.packages.${final.system})
                fastflowlm
                xrt
                xrt-plugin-amdxdna
                llama-cpp-vulkan
                llama-cpp-rocm
                whisper-cpp-vulkan
                stable-diffusion-cpp-vulkan
                stable-diffusion-cpp-rocm
                ;
            };
          };
        };
      });
}
