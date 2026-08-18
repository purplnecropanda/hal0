{ lib, ... }:

let
  source = builtins.readFile ./companion-module.nix;
  fixed = builtins.replaceStrings
    [
      "{ config, lib, pkgs, ... }:"
      "imports = [\n    (pkgs.path + \"/nixos/modules/virtualisation/oci-containers.nix\")\n  ];"
      "environment.systemPackages = lib.optional he.enable pkgs.podman;"
      "environment.etc.\"hal0/hermes/config.yaml\" = lib.mkIf he.enable {"
      "(lib.mkIf he.enable {\n        hal0-hermes = {"
      "systemd.services.hal0-hermes = lib.mkIf he.enable {"
    ]
    [
      "{ config, lib, pkgs, modulesPath, ... }:"
      "imports = [ (modulesPath + \"/virtualisation/oci-containers.nix\") ];"
      "environment.systemPackages = lib.optional (he.enable && he.runtime == \"container\") pkgs.podman;"
      "environment.etc.\"hal0/hermes/config.yaml\" = lib.mkIf (he.enable && he.runtime == \"container\") {"
      "(lib.mkIf (he.enable && he.runtime == \"container\") {\n        hal0-hermes = {"
      "systemd.services.hal0-hermes = lib.mkIf (he.enable && he.runtime == \"container\") {"
    ]
    source;
  fixedPath = builtins.toFile "hal0-companion-module-fixed.nix" fixed;
in
{
  imports = [ fixedPath ];
}
