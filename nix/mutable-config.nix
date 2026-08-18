{ config, lib, ... }:

let
  cfg = config.services.hal0;

  generatedHal0 = {
    meta = { schema_version = 1; };
    slots = {
      port_range_start = cfg.slotPortRange.start;
      port_range_end = cfg.slotPortRange.end;
      publish_host = cfg.slotPublishHost;
      network_mode = cfg.slotNetworkMode;
    };
    dispatcher = {
      prefetch_timeout_s = cfg.prefetchTimeout;
      prefetch_parallel_cap = cfg.prefetchParallelCap;
    };
    telemetry = { enabled = cfg.telemetry; };
    models = {
      store = cfg.modelStore;
      pull_root = cfg.modelStore;
      flm_store = cfg.flmModelStore;
    };
  };

  toToml = value: lib.generators.toTOML {} value;
  hal0Toml = toToml (lib.recursiveUpdate generatedHal0 cfg.settings);
  providersToml = toToml cfg.providers;
  upstreamsToml = toToml cfg.upstreams;
  profilesToml = toToml cfg.profiles;
  capabilitiesToml = toToml cfg.capabilities;

  disabledCoreEtc = {
    "hal0/hal0.toml" = lib.mkForce { enable = false; };
    "hal0/providers.toml" = lib.mkForce { enable = false; };
    "hal0/upstreams.toml" = lib.mkForce { enable = false; };
    "hal0/profiles.toml" = lib.mkForce { enable = false; };
    "hal0/capabilities.toml" = lib.mkForce { enable = false; };
  } // lib.mapAttrs' (name: _:
    lib.nameValuePair "hal0/slots/${name}.toml" (lib.mkForce { enable = false; })
  ) cfg.slotConfigs;
in
{
  config = lib.mkIf cfg.enable {
    # The core module's declarative environment.etc entries are store-backed;
    # hal0 itself is intentionally allowed to update these files at runtime.
    # Disable those generated entries and materialize writable copies once at
    # boot instead. Operator edits, migrations, slot lifecycle and API writes
    # then continue to work exactly like the upstream installer.
    environment.etc = lib.mkIf cfg.mutableConfig disabledCoreEtc;

    systemd.services.hal0-seed-nixos-config = lib.mkIf cfg.mutableConfig {
      description = "hal0 seed writable NixOS runtime configuration";
      before = [ "hal0-seed-static-config.service" "hal0-bootstrap.service" "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        set -eu
        install -d -m 0755 -o ${cfg.user} -g ${cfg.group} /etc/hal0 /etc/hal0/slots

        seed() {
          dst="$1"
          mode="$2"
          owner="$3"
          group="$4"
          if [ ! -e "$dst" ]; then
            install -m "$mode" -o "$owner" -g "$group" /dev/stdin "$dst"
          fi
        }

        seed /etc/hal0/hal0.toml 0644 ${cfg.user} ${cfg.group} <<'HAL0_TOML'
${hal0Toml}
HAL0_TOML

        seed /etc/hal0/providers.toml 0644 ${cfg.user} ${cfg.group} <<'PROVIDERS_TOML'
${providersToml}
PROVIDERS_TOML

        seed /etc/hal0/upstreams.toml 0640 ${cfg.user} ${cfg.group} <<'UPSTREAMS_TOML'
${upstreamsToml}
UPSTREAMS_TOML

        seed /etc/hal0/profiles.toml 0644 ${cfg.user} ${cfg.group} <<'PROFILES_TOML'
${profilesToml}
PROFILES_TOML

        seed /etc/hal0/capabilities.toml 0644 ${cfg.user} ${cfg.group} <<'CAPABILITIES_TOML'
${capabilitiesToml}
CAPABILITIES_TOML
      '';
    };
  };
}
