{ config, lib, pkgs, ... }:

let
  cfg = config.services.hal0;
  he = cfg.hermes;
  native = he.runtime == "native";
  hal0AgentUnit = "hal0-agent@hermes.service";
in
{
  options.services.hal0.hermes.runtime = lib.mkOption {
    type = lib.types.enum [ "native" "container" ];
    default = "native";
    description = ''
      Hermes runtime mode. `native` uses hal0's pinned Hermes provisioning
      pipeline and the real `hal0-agent@hermes` systemd service. `container`
      retains the OCI fallback for operators who explicitly prefer it.
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optional native {
      assertion = he.enable;
      message = "services.hal0.hermes.runtime = native requires services.hal0.hermes.enable = true.";
    };

    systemd.tmpfiles.rules = lib.optionals native [
      "d /var/lib/hal0/venvs 0775 ${cfg.user} ${cfg.group} - -"
      "d /var/lib/hal0/state 0775 ${cfg.user} ${cfg.group} - -"
      "d /var/lib/hal0/state/agents 0775 ${cfg.user} ${cfg.group} - -"
      "d /var/lib/hal0/state/agents/hermes 0775 ${cfg.user} ${cfg.group} - -"
      "d /var/lib/hal0/secrets 0755 root root - -"
      "d /var/lib/hal0/secrets/agents 0700 root root - -"
      "d /etc/hal0/agents 0755 root root - -"
      "d /var/lib/hal0/.hermes 0775 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.hal0-hermes-provision = lib.mkIf native {
      description = "hal0 provision pinned Hermes Agent runtime";
      after = [ "network-online.target" "hal0-api.service" "hal0-bootstrap.service" ];
      wants = [ "network-online.target" "hal0-api.service" ];
      before = [ hal0AgentUnit ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HAL0_ETC = "/etc/hal0";
        HAL0_VAR_LIB = "/var/lib/hal0";
        HAL0_MODEL_STORE = cfg.modelStore;
        HAL0_FLM_MODELS_DIR = cfg.flmModelStore;
        HERMES_HOME = "/var/lib/hal0/.hermes";
        HERMES_VENV = "/var/lib/hal0/venvs/hermes";
        HAL0_AGENT_ID = "hermes";
      } // cfg.environment;
      path = with pkgs; [
        bash coreutils curl git gnugrep gnused gawk findutils which python312Packages.python
      ] ++ cfg.extraPackages;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${cfg.package}/bin/hal0 agent bootstrap hermes";
        RemainAfterExit = true;
        TimeoutStartSec = "3h";
        UMask = "0027";
      };
    };

    systemd.services."hal0-agent@" = lib.mkIf native (lib.mkMerge [
      {
        after = [ "hal0-hermes-provision.service" ];
        wants = [ "hal0-hermes-provision.service" ];
        serviceConfig = {
          Environment = [
            "HAL0_AGENT_ID=%i"
            "HAL0_USR_LIB=${cfg.package}/usr-lib/hal0/current"
            "HAL0_LIB=${cfg.package}/usr-lib/hal0"
            "HAL0_ETC=/etc/hal0"
            "HAL0_VAR_LIB=/var/lib/hal0"
            "HAL0_VAR_LOG=/var/log/hal0"
          ];
        };
      }
    ]);

    # The companion module always defines the OCI wrapper, so explicitly
    # disable that host unit when native mode is selected. The OCI container
    # itself is also prevented from auto-starting below.
    systemd.services.hal0-hermes.enable = lib.mkIf native false;

    virtualisation.oci-containers.containers.hal0-hermes = lib.mkIf he.enable {
      autoStart = lib.mkForce (!native);
    };
  };
}
