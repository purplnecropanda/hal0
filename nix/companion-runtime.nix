{ config, lib, pkgs, ... }:

let
  cfg = config.services.hal0;
  h = cfg.hindsight;
  he = cfg.hermes;
  python = pkgs.python312Packages.python;
  pythonPath = "${cfg.package}/${python.sitePackages}";
in
{
  config = lib.mkIf cfg.enable {
    # Hindsight's official image runs as UID 1000. Keep its embedded pg0 and
    # local HF cache writable when a NixOS host path is bind-mounted.
    systemd.tmpfiles.rules = [
      "d ${h.dataDir} 0770 1000 1000 - -"
      "d ${h.dataDir}/hf-cache 0770 1000 1000 - -"
      "d ${he.dataDir} 0775 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.hal0-hindsight-perms = lib.mkIf h.enable {
      description = "hal0 fix Hindsight persistent-volume ownership";
      before = [ "podman-hal0-hindsight.service" "hindsight-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; User = "root"; RemainAfterExit = true; };
      script = ''
        set -eu
        install -d -m 0770 -o 1000 -g 1000 ${h.dataDir} ${h.dataDir}/hf-cache
        chown -R 1000:1000 ${h.dataDir}
      '';
    };

    virtualisation.oci-containers.containers.hal0-hindsight = lib.mkIf h.enable {
      volumes = lib.mkForce [
        "${h.dataDir}/.pg0:/home/hindsight/.pg0:rw"
        "${h.dataDir}/hf-cache:/home/hindsight/hf-cache:rw"
      ];
    };

    # Seed the Hermes config as mutable runtime state. The upstream provisioner
    # writes this file and may migrate it; keeping it on the host data volume
    # preserves that behaviour while Nix still owns the initial template.
    systemd.services.hal0-hermes-config = lib.mkIf he.enable {
      description = "hal0 seed writable Hermes runtime config";
      before = [ "podman-hal0-hermes.service" "hal0-hermes.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; User = "root"; RemainAfterExit = true; };
      script = ''
        set -eu
        install -d -m 0775 -o ${cfg.user} -g ${cfg.group} ${he.dataDir}
        if [ ! -e ${he.dataDir}/config.yaml ]; then
          install -m 0644 -o ${cfg.user} -g ${cfg.group} /etc/hal0/hermes/config.yaml ${he.dataDir}/config.yaml
        fi
      '';
    };

    virtualisation.oci-containers.containers.hal0-hermes = lib.mkIf he.enable {
      volumes = lib.mkForce [
        "${he.dataDir}:/opt/data:rw"
        "/var/lib/hal0/skills:/opt/data/skills:rw"
      ];
    };

    # The installer-created slot/profile seeds are mutable runtime data. Make
    # the copy owner explicit after the seed stage so the hal0 service can edit
    # them without an imperative chmod/chown after first boot.
    systemd.services.hal0-fix-seed-perms = lib.mkIf cfg.staticSeeds.enable {
      description = "hal0 normalize seeded config ownership";
      after = [ "hal0-seed-static-config.service" "hal0-seed-nixos-config.service" ];
      before = [ "hal0-bootstrap.service" "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; User = "root"; RemainAfterExit = true; };
      script = ''
        set -eu
        chown ${cfg.user}:${cfg.group} /etc/hal0/profiles.toml 2>/dev/null || true
        find /etc/hal0/slots -maxdepth 1 -type f -name '*.toml' -exec chown ${cfg.user}:${cfg.group} {} +
        chmod 0644 /etc/hal0/profiles.toml 2>/dev/null || true
        chmod 0644 /etc/hal0/slots/*.toml 2>/dev/null || true
      '';
    };
  };
}
