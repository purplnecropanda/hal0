# Public NixOS module entry point for hal0.
# The implementation remains split into focused modules so each runtime concern
# stays independently testable and reusable.
{
  imports = [
    ../../nix/nixos-module.nix
    ../../nix/companion-module-fixed.nix
    ../../nix/mutable-config.nix
    ../../nix/companion-overrides.nix
    ../../nix/companion-runtime.nix
    ../../nix/host-runtime.nix
    ../../nix/wrapper-sudo.nix
    ../../nix/hermes-native.nix
  ];
}
