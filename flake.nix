{
  description = "hal0 — open-source home AI inference platform, packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";
    flake-compat.flake = false;
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ inputs, ... }:
      {
        systems = [ "x86_64-linux" ];

        perSystem = { pkgs, system, ... }:
          let
            amdAiPkgs = inputs.nix-amd-ai.packages.${system};
            hal0 = pkgs.callPackage ./pkgs/hal0 {
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
              module = ./modules/hal0;
            };

            checks.nixos-default-module = import ./nix/checks/module-eval.nix {
              inherit pkgs;
              module = ./modules/hal0;
            };
          };

        flake = {
          nixosModules.default = ./modules/hal0;
          nixosModules.core = ./nix/nixos-module.nix;
          nixosModules.companions = {
            imports = [
              ./nix/companion-module-fixed.nix
              ./nix/mutable-config.nix
              ./nix/companion-overrides.nix
              ./nix/companion-runtime.nix
              ./nix/host-runtime.nix
              ./nix/wrapper-sudo.nix
              ./nix/hermes-native.nix
            ];
          };
          overlays.default = final: prev: {
            hal0 = final.callPackage ./pkgs/hal0 {
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
