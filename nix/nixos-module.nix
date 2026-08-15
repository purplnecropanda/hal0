{ config, lib, pkgs, ... }:

let
  cfg = config.services.hal0;
  inherit (lib) mkEnableOption mkIf mkMerge mkOption optional optionals types;

  hal0 = cfg.package;
  seam = "${hal0}/libexec/hal0/hal0-systemctl";
  benchSeam = "${hal0}/libexec/hal0/hal0-benchctl";

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

  hal0Toml = lib.generators.toTOML {} (lib.recursiveUpdate generatedHal0 cfg.settings);
  writeToml = value: lib.generators.toTOML {} value;

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

  commonPath = with pkgs; [
    podman sudo systemd bash coreutils util-linux iproute2 pciutils lshw procps curl jq git
  ] ++ cfg.extraPackages;

  slotEtc = lib.mapAttrs' (name: value:
    lib.nameValuePair "hal0/slots/${name}.toml" { text = writeToml value; mode = "0644"; }
  ) cfg.slotConfigs;

  agentEtc = lib.mapAttrs' (name: value:
    lib.nameValuePair "hal0/agents/${name}.toml" { text = writeToml value; mode = "0644"; }
  ) cfg.agentConfigs;

  generatedEtc = {
    "hal0/hal0.toml" = { text = hal0Toml; mode = "0644"; };
    "hal0/providers.toml" = { text = writeToml cfg.providers; mode = "0644"; };
    "hal0/upstreams.toml" = { text = writeToml cfg.upstreams; mode = "0640"; };
    "hal0/profiles.toml" = { text = writeToml cfg.profiles; mode = "0644"; };
    "hal0/capabilities.toml" = { text = writeToml cfg.capabilities; mode = "0644"; };
  } // slotEtc // agentEtc // cfg.extraConfigFiles;

  apiUnit = {
    description = "hal0 API and control plane";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "podman.service" ];
    requires = [ "podman.service" ];
    environment = apiEnvironment;
    path = commonPath;
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
      ReadWritePaths = [ "/etc/hal0" "/var/lib/hal0" "/var/log/hal0" "/run/hal0" "/etc/containers/systemd" ];
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

  benchUnit = {
    description = "hal0 scheduled benchmark session";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = cfg.user;
      Group = cfg.group;
      ExecStart = "${hal0}/bin/hal0 bench run --suite roster --scheduled";
      TimeoutStartSec = "6h";
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "hal0-bench";
      LimitMEMLOCK = cfg.limitMemlock;
    };
    environment = apiEnvironment;
    path = commonPath;
  };

in
{
  options.services.hal0 = {
    enable = mkEnableOption "hal0 AI inference platform";
    package = mkOption { type = types.package; default = pkgs.hal0; defaultText = lib.literalExpression "pkgs.hal0"; description = "The hal0 package to run."; };
    user = mkOption { type = types.str; default = "hal0"; };
    group = mkOption { type = types.str; default = "hal0"; };
    port = mkOption { type = types.port; default = 8080; };
    bindHost = mkOption { type = types.str; default = "127.0.0.1"; description = "Address the hal0 API binds to."; };
    modelStore = mkOption { type = types.path; default = "/var/lib/hal0/models"; description = "Persistent model store shared with inference containers."; };
    flmModelStore = mkOption { type = types.path; default = "/var/lib/hal0/.config/flm/models"; };
    slotPortRange.start = mkOption { type = types.port; default = 8081; };
    slotPortRange.end = mkOption { type = types.port; default = 8099; };
    slotPublishHost = mkOption { type = types.str; default = "127.0.0.1"; };
    slotNetworkMode = mkOption { type = types.str; default = ""; description = "Podman network mode; empty means the default bridge network."; };
    prefetchTimeout = mkOption { type = types.ints.positive; default = 8; };
    prefetchParallelCap = mkOption { type = types.ints.positive; default = 4; };
    telemetry = mkOption { type = types.bool; default = false; };
    limitMemlock = mkOption { type = types.str; default = "infinity"; };
    environment = mkOption { type = types.attrsOf types.str; default = {}; description = "Additional environment variables for hal0-api."; };
    agentEnvironmentFile = mkOption { type = types.nullOr types.path; default = null; description = "Optional environment file for hal0-agent instances."; };
    extraPackages = mkOption { type = types.listOf types.package; default = []; };

    settings = mkOption { type = types.attrs; default = {}; description = "Additional hal0.toml values, recursively merged with module defaults."; };
    providers = mkOption { type = types.attrs; default = {}; description = "Complete providers.toml contents."; };
    upstreams = mkOption { type = types.attrs; default = {}; description = "Complete upstreams.toml contents."; };
    profiles = mkOption { type = types.attrs; default = {}; description = "Complete profiles.toml contents."; };
    capabilities = mkOption { type = types.attrs; default = {}; description = "Complete capabilities.toml contents."; };
    slotConfigs = mkOption { type = types.attrsOf types.attrs; default = {}; description = "Complete slot TOMLs keyed by slot name."; };
    agentConfigs = mkOption { type = types.attrsOf types.attrs; default = {}; description = "Complete /etc/hal0/agents/<id>.toml configurations for hal0-agent."; };
    extraConfigFiles = mkOption {
      type = types.attrsOf (types.submodule ({ ... }: {
        options = {
          text = mkOption { type = types.lines; };
          mode = mkOption { type = types.str; default = "0644"; };
        };
      }));
      default = {};
      description = "Additional files under /etc/hal0, for advanced/upstream configuration surfaces.";
    };

    agents = mkOption {
      type = types.attrsOf (types.submodule { options.enable = mkOption { type = types.bool; default = true; }; });
      default = {};
      description = "Declaratively enabled hal0-agent instances.";
    };

    enableBench = mkOption { type = types.bool; default = false; description = "Enable hal0's scheduled benchmark service and timer."; };
    benchSchedule = mkOption { type = types.str; default = "Sun *-*-* 03:00"; description = "systemd OnCalendar expression for the benchmark timer."; };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        { assertion = cfg.slotPortRange.start <= cfg.slotPortRange.end; message = "services.hal0.slotPortRange.start must be <= end"; }
      ];

      environment.systemPackages = [ cfg.package pkgs.podman pkgs.sudo ];
      environment.etc = generatedEtc;

      users.groups.${cfg.group} = {};
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = "/var/lib/hal0";
        createHome = true;
        shell = "${pkgs.shadow}/bin/nologin";
        extraGroups = optionals (config.users.groups ? render) [ "render" ] ++ optionals (config.users.groups ? video) [ "video" ];
      };

      systemd.tmpfiles.rules = [
        "d /etc/hal0 0755 ${cfg.user} ${cfg.group} - -"
        "d /etc/hal0/slots 0755 ${cfg.user} ${cfg.group} - -"
        "d /etc/hal0/agents 0755 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/models 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/registry 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/slots 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/agents 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/log/hal0 0755 ${cfg.user} ${cfg.group} - -"
        "d /etc/containers/systemd 0755 root root - -"
      ];

      systemd.services.hal0-api = apiUnit;
      systemd.targets.hal0 = {
        description = "hal0 inference slots";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
      };
      systemd.services."hal0-agent@" = agentBase;

      security.sudo.extraRules = [{
        users = [ cfg.user ];
        commands = [
          { command = "${seam} write-quadlet *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} remove-quadlet *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} daemon-reload"; options = [ "NOPASSWD" ]; }
          { command = "${seam} start *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} stop *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} restart *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} enable *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} disable *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} reset-failed *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} restart-self"; options = [ "NOPASSWD" ]; }
          { command = "${seam} stop-agent *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} start-agent *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} restart-agent *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} disable-agent *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} enable-agent *"; options = [ "NOPASSWD" ]; }
          { command = "${seam} write-gateway-dropin"; options = [ "NOPASSWD" ]; }
          { command = "${seam} remove-gateway-dropin"; options = [ "NOPASSWD" ]; }
          { command = "${seam} write-hindsight-dropin"; options = [ "NOPASSWD" ]; }
          { command = "${seam} remove-hindsight-dropin"; options = [ "NOPASSWD" ]; }
          { command = "${seam} prune-dnat *"; options = [ "NOPASSWD" ]; }
        ];
      }];
    }
    {
      systemd.services = lib.mapAttrs' (name: agentCfg:
        lib.nameValuePair "hal0-agent@${name}" { wantedBy = lib.optional agentCfg.enable "multi-user.target"; }
      ) cfg.agents;
    }
    (mkIf cfg.enableBench {
      systemd.services.hal0-bench = benchUnit;
      systemd.timers.hal0-bench = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.benchSchedule;
          Persistent = true;
          RandomizedDelaySec = "15m";
          Unit = "hal0-bench.service";
        };
      };
      security.sudo.extraRules = [{
        users = [ cfg.user ];
        commands = [{ command = "${benchSeam} *"; options = [ "NOPASSWD" ]; }];
      }];
    })
  ]);
}
