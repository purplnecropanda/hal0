{ ... }:
{
  imports = [
    ../../nix/companion-module-fixed.nix
    ../../nix/mutable-config.nix
    ../../nix/companion-overrides.nix
    ../../nix/companion-runtime.nix
    ../../nix/host-runtime.nix
    ../../nix/wrapper-sudo.nix
  ];
}
