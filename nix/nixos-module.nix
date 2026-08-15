{ config, lib, pkgs, ... }:

let
  cfg = config.services.hal0;
  inherit (lib) mkEnableOption mkIf mkMerge mkOption optional optionals types;

  hal0 = cfg.package;
  seam = "${hal0}/libexec/hal0/hal0-systemctl";

  configText = ''
    [meta]
    schema_version = 1

    [slots]
    port_range_start = ${toString cfg.slotPortRange.start}
    port_range_end = ${toString cfg.slotPortRange.end}
    publish_host = "${cfg.slotPublishHost}"
    network_mode = "${cfg.slotNetworkMode}"

    [dispatcher]
    prefetch_timeout_s = ${toString cfg.prefetchTimeout}
    prefetch_parallel_cap = ${toString cfg.prefetchParallelCap}

    [telemetry]
    enabled = ${lib.boolToString cfg.telemetry}

    [models]
    store = "${cfg.modelStore}"
    pull_root = "${cfg.modelStore}"
    flm_store = "${cfg.flmModelStore}"
  '';

  apiEnvironment = {
    HAL0_PORT = toString cfg.port;
    HAL0_BIND_HOST = cfg.bindHost;
    HAL0_UI_DIST = "${hal0}/share/hal0/ui/dist";
    HAL0_USR_LIB = "${hal0}/usr-lib/hal0/current";
    HAL0_LIB = "${hal0}/usr-lib/hal0";
    HAL0_ETC = "/etc/hal0";
    HAL0_VAR_LIB = "/var/lib/hal0";
    HAL0_VAR_LOG = "/var/log/hal0";
    HAL0_MODEL_STORE = cfg.modelStore;
    HAL0_FLM_MODELS_DIR = cfg.flmModelStore;
    HAL0_CONTAINER_RUNTIME = "${pkgs.podman}/bin/podman";
  } // cfg.environment;

  apiUnit = {
    description = "hal0 API and control plane";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "podman.service" ];
    requires = [ "podman.service" ];
    environment = apiEnvironment;
    path = with pkgs; [
      podman
      systemd
      bash
      coreutils
      util-linux
      iproute2
      pciutils
      lshw
    ] ++ cfg.extraPackages;
    serviceConfig = {
      Type = "simple";
      User = cfg.user;
      Group = cfg.group;
      ExecStart = "${pkgs.python312Packages.uvicorn}/bin/uvicorn hal0.api:app --host ${cfg.bindHost} --port ${toString cfg.port}";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = 120;
      LimitNOFILE = 65536;
      LimitMEMLOCK = cfg.limitMemlock;
      RuntimeDirectory = "hal0";
      StateDirectory = "hal0";
      LogsDirectory = "hal0";
      UMask = "0027";
      ReadWritePaths = [
        "/etc/hal0"
        "/var/lib/hal0"
        "/var/log/hal0"
        "/run/hal0"
        "/etc/containers/systemd"
      ];
    };
  };

  agentBase = {
    description = "hal0 agent (%i)";
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HAL0_AGENT_ID = "%i";
      HAL0_USR_LIB = "${hal0}/usr-lib/hal0/current";
      HAL0_LIB = "${hal0}/usr-lib/hal0";
      HAL0_ETC = "/etc/hal0";
      HAL0_VAR_LIB = "/var/lib/hal0";
      HAL0_VAR_LOG = "/var/log/hal0";
    };
    serviceConfig = {
      Type = "notify";
      User = cfg.user;
      Group = cfg.group;
      ExecStart = "${hal0}/bin/hal0-agent %i serve";
      ExecStop = "${hal0}/bin/hal0-agent %i stop";
      Restart = "on-failure";
      RestartSec = 5;
      TimeoutStartSec = 120;
      TimeoutStopSec = 15;
      WatchdogSec = 60;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      PrivateTmp = true;
      ProtectHome = true;
      RuntimeDirectory = "hal0";
      RuntimeDirectoryPreserve = true;
      LogsDirectory = "hal0";
      ReadWritePaths = [ "/etc/hal0" "/var/lib/hal0" "/var/log/hal0" "/run/hal0" ];
      EnvironmentFile = optional cfg.agentEnvironmentFile;
    };
  };
in
{
  options.services.hal0 = {
    enable = mkEnableOption "hal0 AI inference platform";

    package = mkOption {
      type = types.package;
      default = pkgs.hal0;
      defaultText = lib.literalExpression "pkgs.hal0";
      description = "The hal0 package to run.";
    };

    user = mkOption {
      type = types.str;
      default = "hal0";
    };

    group = mkOption {
      type = types.str;
      default = "hal0";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
    };

    bindHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address the hal0 API binds to.";
    };

    modelStore = mkOption {
      type = types.path;
      default = "/var/lib/hal0/models";
      description = "Persistent model store shared with inference containers.";
    };

    flmModelStore = mkOption {
      type = types.path;
      default = "/var/lib/hal0/.config/flm/models";
    };

    slotPortRange = {
      start = mkOption { type = types.port; default = 8081; };
      end = mkOption { type = types.port; default = 8099; };
    };

    slotPublishHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    slotNetworkMode = mkOption {
      type = types.str;
      default = "";
      description = "Podman network mode; empty means the default bridge network.";
    };

    prefetchTimeout = mkOption {
      type = types.ints.positive;
      default = 8;
    };

    prefetchParallelCap = mkOption {
      type = types.ints.positive;
      default = 4;
    };

    telemetry = mkOption {
      type = types.bool;
      default = false;
    };

    limitMemlock = mkOption {
      type = types.str;
      default = "infinity";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Additional environment variables for hal0-api.";
    };

    agentEnvironmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional environment file for hal0-agent instances.";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };

    agents = mkOption {
      type = types.attrsOf (types.submodule {
        options.enable = mkOption {
          type = types.bool;
          default = true;
        };
      });
      default = { };
      description = "Declaratively enabled hal0-agent instances.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = cfg.slotPortRange.start <= cfg.slotPortRange.end;
          message = "services.hal0.slotPortRange.start must be <= end";
        }
      ];

      environment.systemPackages = [ cfg.package pkgs.podman ];

      users.groups.${cfg.group} = { };
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = "/var/lib/hal0";
        createHome = true;
        shell = "${pkgs.shadow}/bin/nologin";
        extraGroups = optionals (config.users.groups ? render) [ "render" ]
          ++ optionals (config.users.groups ? video) [ "video" ];
      };

      systemd.tmpfiles.rules = [
        "d /etc/hal0 0755 ${cfg.user} ${cfg.group} - -"
        "d /etc/hal0/slots 0755 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/models 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/registry 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/slots 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/log/hal0 0755 ${cfg.user} ${cfg.group} - -"
        "d /etc/containers/systemd 0755 root root - -"
      ];

      environment.etc."hal0/hal0.toml" = {
        mode = "0644";
        text = configText;
      };

      systemd.services.hal0-api = apiUnit;
      systemd.targets.hal0 = {
        description = "hal0 inference slots";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      systemd.services."hal0-agent@" = agentBase;

      environment.etc."sudoers.d/hal0-systemctl" = {
        mode = "0440";
        text = ''
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} write-quadlet *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} remove-quadlet *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} daemon-reload
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} start *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} stop *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} restart *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} enable *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} disable *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} reset-failed *
          ${cfg.user} ALL=(root) NOPASSWD: ${seam} restart-self
        '';
      };
    }
    {
      systemd.services = lib.mapAttrs' (name: agentCfg:
        lib.nameValuePair "hal0-agent@${name}" {
          wantedBy = lib.optional agentCfg.enable "multi-user.target";
        }
      ) cfg.agents;
    }
  ]);
}
