# Public package entry point.
# Keep the implementation in nix/package.nix for backwards compatibility while
# exposing the conventional pkgs/<name>/ layout used by nix-amd-ai.
{ callPackage, ... }:
callPackage ../../nix/package.nix { }
