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
            amdAiOverlay = inputs.nix-amd-ai.overlays.default;
            amdAiPkgs = inputs.nix-amd-ai.packages.${system};

            hal0-assets = pkgs.callPackage ./pkgs/hal0-assets { };
            hal0-ui = pkgs.callPackage ./pkgs/hal0-ui { };
            hal0-core = pkgs.callPackage ./pkgs/hal0-core { };
            hal0 = pkgs.callPackage ./pkgs/hal0 { inherit hal0-assets hal0-ui hal0-core; };
          in
          {
            packages = {
              inherit hal0 hal0-core hal0-ui hal0-assets;
              inherit (amdAiPkgs)
                fastflowlm
                xrt
                xrt-plugin-amdxdna
                llama-cpp-vulkan
                llama-cpp-rocm
                whisper-cpp-vulkan
                stable-diffusion-cpp-vulkan
                stable-diffusion-cpp-rocm;
              default = hal0;
            };

            checks = {
              package-assets = pkgs.runCommand "hal0-check-package-assets" { } ''
                test -d ${hal0-assets}/usr-lib/hal0/current
                test -f ${hal0-assets}/usr-lib/hal0/current/manifest.json
                test -d ${hal0-assets}/share/hal0/systemd
                test -x ${hal0-assets}/libexec/hal0/hal0-systemctl
                touch $out
              '';

              package-core = pkgs.runCommand "hal0-check-package-core" { } ''
                test -x ${hal0-core}/bin/hal0
                test -x ${hal0-core}/bin/hal0-agent
                touch $out
              '';

              package-ui = pkgs.runCommand "hal0-check-package-ui" { } ''
                test -f ${hal0-ui}/dist/index.html
                touch $out
              '';

              package-composition = pkgs.runCommand "hal0-check-package-composition" { } ''
                test -x ${hal0}/bin/hal0
                test -x ${hal0}/bin/hal0-agent
                test -f ${hal0}/share/hal0/ui-dist/index.html
                test -f ${hal0}/usr-lib/hal0/current/manifest.json
                touch $out
              '';

              nixos-module-core = import ./checks/module-core.nix {
                inherit pkgs;
                module = ./modules/hal0/core.nix;
              };
              nixos-module-companions = import ./checks/module-companions.nix {
                inherit pkgs;
                module = ./modules/hal0/companions.nix;
              };
              nixos-module-hermes = import ./checks/module-hermes.nix {
                inherit pkgs;
                module = ./modules/hal0/hermes.nix;
              };
              nixos-module-rendered = import ./checks/module-rendered.nix {
                inherit pkgs;
                module = ./modules/hal0;
              };
            };
          };

        flake = {
          nixosModules.default = ./modules/hal0;
          nixosModules.core = ./modules/hal0/core.nix;
          nixosModules.companions = ./modules/hal0/companions.nix;

          overlays.default = final: prev:
            (amdAiOverlay final prev) // {
              hal0-assets = final.callPackage ./pkgs/hal0-assets { };
              hal0-ui = final.callPackage ./pkgs/hal0-ui { };
              hal0-core = final.callPackage ./pkgs/hal0-core { };
              hal0 = final.callPackage ./pkgs/hal0 {
                hal0-assets = final.hal0-assets;
                hal0-ui = final.hal0-ui;
                hal0-core = final.hal0-core;
              };
            };
        };
      });
}
