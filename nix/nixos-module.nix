{ config, lib, pkgs, ... }:

let
  cfg = config.services.hal0;
  inherit (lib) mkEnableOption mkOption types mkIf mkMerge optional optionals concatStringsSep;

  hal0 = cfg.package;
  systemctlSeam = "${hal0}/libexec/hal0/hal0-systemctl";

  configText = builtins.toJSON {
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
    telemetry.enabled = cfg.telemetry;
    models.store = cfg.modelStore;
    models.pull_root = cfg.modelStore;
    models.flm_store = cfg.flmModelStore;
  };

  # Generate EnvironmentFile syntax from an attrset while keeping secrets out
  # of the Nix store whenever callers use normal NixOS secret-file options.
  envLines = lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "${n}=${v}") cfg.environment);

  apiUnit = {
    description = "hal0 API and control plane";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "podman.service" ];
    requires = [ "podman.service" ];
    environment = {
      HAL0_PORT = toString cfg.port;
      HAL0_BIND_HOST = cfg.bindHost;
      HAL0_UI_DIST = "${hal0}/share/hal0/ui/dist";
      HAL0_USR_LIB = "${hal0}";
      HAL0_LIB = "${hal0}";
      HAL0_ETC = "/etc/hal0";
      HAL0_VAR_LIB = "/var/lib/hal0";
      HAL0_VAR_LOG = "/var/log/hal0";
      HAL0_MODEL_STORE = cfg.modelStore;
      HAL0_FLM_MODELS_DIR = cfg.flmModelStore;
      HAL0_CONTAINER_RUNTIME = "${pkgs.podman}/bin/podman";
    } // cfg.environment;
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
      ReadWritePaths = [ "/etc/hal0" "/var/lib/hal0" "/var/log/hal0" "/run/hal0" "/etc/containers/systemd" ];
      UMask = "0027";
    };
    path = with pkgs; [ podman systemd bash coreutils util-linux iproute2 pciutils lshw ] ++ cfg.extraPackages;
  };

  targetUnit = {
    description = "hal0 inference slots";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
  };

  agentUnit = {
    description = "hal0 agent (%i)";
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HAL0_AGENT_ID = "%i";
      HAL0_USR_LIB = "${hal0}";
      HAL0_LIB = "${hal0}";
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
      EnvironmentFile = optionalString (cfg.agentEnvironmentFile != null) cfg.agentEnvironmentFile;
    };
  };

  seamUnit = {
    description = "hal0 privileged systemd/Quadlet seam";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/true";
      RemainAfterExit = true;
    };
  };
in
{
  options.services.hal0 = {
    enable = mkEnableOption "hal0 AI inference platform";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix {
        inherit (pkgs) python312Packages nodejs_20 makeWrapper podman systemd bash;
        # nix-amd-ai packages are exposed through the package's flake input when
        # the flake is used. For standalone NixOS imports, these are optional
        # nulls and the runtime remains GPU/NPU agnostic until a slot needs them.
        fastflowlm = pkgs.fastflowlm or pkgs.hello;
        xrt = pkgs.xrt or pkgs.hello;
        xrt-plugin-amdxdna = pkgs.xrt-plugin-amdxdna or pkgs.hello;
        llama-cpp-vulkan = pkgs.llama-cpp-vulkan or pkgs.llama-cpp;
        llama-cpp-rocm = pkgs.llama-cpp-rocm or pkgs.llama-cpp;
        whisper-cpp-vulkan = pkgs.whisper-cpp-vulkan or pkgs.whisper-cpp;
        stable-diffusion-cpp-vulkan = pkgs.stable-diffusion-cpp-vulkan or pkgs.stable-diffusion-cpp;
        stable-diffusion-cpp-rocm = pkgs.stable-diffusion-cpp-rocm or pkgs.stable-diffusion-cpp;
      };
      description = "hal0 package to run";
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
      description = "Persistent model store shared with slot containers.";
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
      description = "Podman network mode; empty means bridge networking.";
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
      description = "Additional hal0 API environment variables.";
    };

    agentEnvironmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };

    agents = mkOption {
      type = types.attrsOf (types.submodule { options.enable = mkOption { type = types.bool; default = true; }; });
      default = { };
      description = "Declaratively enabled hal0-agent instances.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        { assertion = cfg.slotPortRange.start <= cfg.slotPortRange.end; message = "services.hal0.slotPortRange.start must be <= end"; }
      ];

      environment.systemPackages = [ hal0 pkgs.podman pkgs.systemd ];

      users.groups.${cfg.group} = { };
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
        "d /var/lib/hal0 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/models 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/registry 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/lib/hal0/slots 2775 ${cfg.user} ${cfg.group} - -"
        "d /var/log/hal0 0755 ${cfg.user} ${cfg.group} - -"
        "d /etc/containers/systemd 0755 root root - -"
      ];

      environment.etc."hal0/hal0.toml" = {
        mode = "0644";
        text = builtins.toJSON configText;
      };

      systemd.services.hal0-api = apiUnit;
      systemd.targets.hal0 = targetUnit;
      systemd.services."hal0-agent@" = agentUnit;

      # The upstream seam script is deliberately invoked through sudo only by
      # the hal0 service user. Keep the rule exact: no arbitrary systemctl,
      # no wildcard arguments, no shell.
      security.sudo.extraRules = [{
        users = [ cfg.user ];
        commands = [
          { command = "${systemctlSeam} write-quadlet *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} remove-quadlet *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} daemon-reload"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} start *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} stop *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} restart *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} enable *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} disable *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} reset-failed *"; options = [ "NOPASSWD" ]; }
          { command = "${systemctlSeam} restart-self"; options = [ "NOPASSWD" ]; }
        ];
      }];
    }

    {
      systemd.services = lib.mapAttrs' (name: agentCfg:
        lib.nameValuePair "hal0-agent@${name}" { wantedBy = lib.optional agentCfg.enable "multi-user.target"; }
      ) cfg.agents;
    }
  ]);
}
