{ config, lib, ... }:

let
  cfg = config.services.hal0;
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    # hal0 deliberately uses ROOTFUL slot containers. Keep root's user runtime
    # alive across SSH/session logout so Podman netns teardown remains reliable;
    # this mirrors the upstream installer requirement that prevents stale
    # netavark DNAT rules from accumulating after a root login session ends.
    users.users.root.linger = true;
  };
}
