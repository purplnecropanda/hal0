{
  description = "hal0 — open-source home AI inference platform, packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";
    flake-compat.url = "github:edolstra/flake-compat";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ self, inputs, ... }:
      {
        systems = [ "x86_64-linux" ];

        perSystem = { pkgs, system, ... }:
          let
            amdAiPkgs = inputs.nix-amd-ai.packages.${system};
          in
          {
            packages = {
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
              default = self.packages.${system}.hal0;
            };

            checks = {
              package = self.packages.${system}.hal0;
              nixos-module = pkgs.nixos-rebuild;
            };
          };

        flake = {
          nixosModules.default = import ./nix/nixos-module.nix;
        };
      });
}
