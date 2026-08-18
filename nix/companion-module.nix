{ config, lib, pkgs, ... }:

let
  cfg = config.services.hal0;
  h = cfg.hindsight;
  ow = cfg.openwebui;
  he = cfg.hermes;
  bw = cfg.benchWorker;

  hostGateway = "host.docker.internal:host-gateway";
  hindsightImage = "ghcr.io/vectorize-io/hindsight:0.7.2";
  openWebuiImage = "ghcr.io/open-webui/open-webui@sha256:7f1b0a1a50cfbac23da3b16f96bc968fd757b26dc9e54e93813d61768ea9184e";
  hermesImage = "docker.io/nousresearch/hermes-agent:v2026.7.7.2";

  enabled = cfg.enable;
in
{
  imports = [
    (pkgs.path + "/nixos/modules/virtualisation/oci-containers.nix")
  ];

  options.services.hal0 = {
    hindsight = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run hal0's persistent Hindsight memory service.";
      };
      image = lib.mkOption {
        type = lib.types.str;
        default = hindsightImage;
        description = "Hindsight OCI image. The default matches hal0's pinned 0.7.2 runtime contract.";
      };
      port = lib.mkOption { type = lib.types.port; default = 9177; };
      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/hal0/memory/hindsight";
        description = "Persistent Hindsight pg0/HF state.";
      };
      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional EnvironmentFile supplying HINDSIGHT_API_LLM_API_KEY and other secrets.";
      };
      llmProvider = lib.mkOption { type = lib.types.str; default = "openai"; };
      llmModel = lib.mkOption { type = lib.types.str; default = "hal0/utility"; };
      llmBaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://host.docker.internal:8080/v1";
        description = "OpenAI-compatible endpoint used by Hindsight extraction/reflection.";
      };
      timeout = lib.mkOption { type = lib.types.ints.positive; default = 300; };
    };

    openwebui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the pinned OpenWebUI companion used by hal0.";
      };
      image = lib.mkOption { type = lib.types.str; default = openWebuiImage; };
      bindHost = lib.mkOption {
        type = lib.types.str;
        default = cfg.bindHost;
        description = "Host address for OpenWebUI port 3001.";
      };
      dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/hal0/openwebui"; };
      trustedEmailHeader = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Trusted proxy email header. When set, OpenWebUI authentication is enabled.";
      };
    };

    hermes = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the bundled Hermes Agent companion using the upstream container runtime.";
      };
      image = lib.mkOption { type = lib.types.str; default = hermesImage; };
      dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/hal0/hermes"; };
      dashboardPort = lib.mkOption { type = lib.types.port; default = 9119; };
      apiPort = lib.mkOption { type = lib.types.port; default = 8642; };
      bindHost = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      model = lib.mkOption { type = lib.types.str; default = "hal0/agent"; };
      apiKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional secret file containing Hermes API_SERVER_KEY, when its API server is enabled.";
      };
    };

    benchWorker.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run hal0's queue worker used by the benchmark dashboard.";
    };
  };

  config = lib.mkIf enabled {
    virtualisation.oci-containers.backend = "podman";

    environment.systemPackages = lib.optional he.enable pkgs.podman;

    systemd.tmpfiles.rules = [
      "d ${h.dataDir} 2775 ${cfg.user} ${cfg.group} - -"
      "d ${ow.dataDir} 2775 ${cfg.user} ${cfg.group} - -"
      "d ${he.dataDir} 2775 ${cfg.user} ${cfg.group} - -"
    ];

    environment.etc."hal0/hermes/config.yaml" = lib.mkIf he.enable {
      mode = "0644";
      text = ''
        model:
          default: ${he.model}
          provider: custom
          base_url: http://host.docker.internal:${toString cfg.port}/v1
          api_key: sk-hal0-local
        terminal:
          backend: local
          cwd: /opt/data/workspace
        gateway:
          allowed_users: []
      '';
    };

    virtualisation.oci-containers.containers = lib.mkMerge [
      (lib.mkIf h.enable {
        hal0-hindsight = {
          image = h.image;
          autoStart = true;
          ports = [ "127.0.0.1:${toString h.port}:${toString h.port}" ];
          volumes = [ "${h.dataDir}:/home/hindsight/.pg0:rw" ];
          environment = {
            HINDSIGHT_API_HOST = "0.0.0.0";
            HINDSIGHT_API_PORT = toString h.port;
            HINDSIGHT_API_LLM_PROVIDER = h.llmProvider;
            HINDSIGHT_API_LLM_BASE_URL = h.llmBaseUrl;
            HINDSIGHT_API_LLM_MODEL = h.llmModel;
            HINDSIGHT_API_LLM_API_KEY = "hal0-local-noauth";
            HINDSIGHT_API_LLM_TIMEOUT = toString h.timeout;
            HINDSIGHT_API_SKIP_LLM_VERIFICATION = "true";
            HINDSIGHT_API_EMBEDDINGS_LOCAL_FORCE_CPU = "true";
            HINDSIGHT_API_RERANKER_LOCAL_FORCE_CPU = "true";
            HF_HOME = "/home/hindsight/hf-cache";
          };
          environmentFiles = lib.optional (h.environmentFile != null) h.environmentFile;
          cmd = [ "--host" "0.0.0.0" "--port" (toString h.port) ];
          extraOptions = [ "--add-host=${hostGateway}" ];
        };
      })
      (lib.mkIf ow.enable {
        hal0-openwebui = {
          image = ow.image;
          autoStart = true;
          ports = [ "${ow.bindHost}:3001:8080" ];
          volumes = [ "${ow.dataDir}:/app/backend/data:rw" ];
          environment = {
            OPENAI_API_BASE_URLS = "http://host.docker.internal:${toString cfg.port}/v1";
            WEBUI_AUTH = if ow.trustedEmailHeader == null then "False" else "True";
            WEBUI_NAME = "hal0";
            ENABLE_OPENAI_API = "True";
            ENABLE_OLLAMA_API = "False";
            ENABLE_PERSISTENT_CONFIG = "False";
            DATA_DIR = "/app/backend/data";
            DEFAULT_LOCALE = "en";
            AUDIO_STT_ENGINE = "openai";
            AUDIO_STT_OPENAI_API_BASE_URL = "http://host.docker.internal:${toString cfg.port}/v1";
            AUDIO_STT_OPENAI_API_KEY = "sk-hal0-local";
            AUDIO_STT_MODEL = "whisper-v3:turbo";
            AUDIO_TTS_ENGINE = "openai";
            AUDIO_TTS_OPENAI_API_BASE_URL = "http://host.docker.internal:${toString cfg.port}/v1";
            AUDIO_TTS_OPENAI_API_KEY = "sk-hal0-local";
            AUDIO_TTS_MODEL = "kokoro-v1";
            AUDIO_TTS_VOICE = "af_heart";
          } // lib.optionalAttrs (ow.trustedEmailHeader != null) {
            WEBUI_AUTH_TRUSTED_EMAIL_HEADER = ow.trustedEmailHeader;
          };
          extraOptions = [ "--add-host=${hostGateway}" "--security-opt" "apparmor=unconfined" ];
        };
      })
      (lib.mkIf he.enable {
        hal0-hermes = {
          image = he.image;
          autoStart = true;
          ports = [
            "${he.bindHost}:${toString he.dashboardPort}:9119"
          ] ++ lib.optional (he.bindHost != "") "${he.bindHost}:${toString he.apiPort}:8642";
          volumes = [
            "${he.dataDir}:/opt/data:rw"
            "/etc/hal0/hermes/config.yaml:/opt/data/config.yaml:rw"
            "/var/lib/hal0/skills:/opt/data/skills:rw"
          ];
          environment = {
            HERMES_DASHBOARD = "1";
            HERMES_DASHBOARD_HOST = "0.0.0.0";
            HERMES_DASHBOARD_INSECURE = "1";
            API_SERVER_ENABLED = "true";
            API_SERVER_HOST = "0.0.0.0";
            API_SERVER_PORT = toString he.apiPort;
            HINDSIGHT_API_URL = "http://host.docker.internal:${toString h.port}";
            HINDSIGHT_TIMEOUT = "60";
          };
          environmentFiles = lib.optional (he.apiKeyFile != null) he.apiKeyFile;
          cmd = [ "gateway" "run" ];
          extraOptions = [ "--add-host=${hostGateway}" ];
        };
      })
    ];

    systemd.services.hal0-hindsight = lib.mkIf h.enable {
      description = "hal0 Hindsight companion service";
      after = [ "podman.service" "hal0-api.service" ];
      wants = [ "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.systemd}/bin/systemctl start podman-hal0-hindsight.service"; ExecStop = "${pkgs.systemd}/bin/systemctl stop podman-hal0-hindsight.service"; RemainAfterExit = true; };
    };

    systemd.services.hal0-openwebui = lib.mkIf ow.enable {
      description = "hal0 OpenWebUI companion service";
      after = [ "podman.service" "hal0-api.service" ];
      wants = [ "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.systemd}/bin/systemctl start podman-hal0-openwebui.service"; ExecStop = "${pkgs.systemd}/bin/systemctl stop podman-hal0-openwebui.service"; RemainAfterExit = true; };
    };

    systemd.services.hal0-hermes = lib.mkIf he.enable {
      description = "hal0 Hermes Agent companion service";
      after = [ "podman.service" "hal0-api.service" "hal0-hindsight.service" ];
      wants = [ "hal0-api.service" "hal0-hindsight.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; ExecStart = "${pkgs.systemd}/bin/systemctl start podman-hal0-hermes.service"; ExecStop = "${pkgs.systemd}/bin/systemctl stop podman-hal0-hermes.service"; RemainAfterExit = true; };
    };

    systemd.services.hal0-bench-worker = lib.mkIf bw.enable {
      description = "hal0 benchmark run-queue worker";
      after = [ "network-online.target" "hal0-api.service" ];
      wants = [ "network-online.target" "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        PYTHONUNBUFFERED = "1";
        HAL0_PORT = toString cfg.port;
        HAL0_BIND_HOST = cfg.bindHost;
        HAL0_ETC = "/etc/hal0";
        HAL0_VAR_LIB = "/var/lib/hal0";
        HAL0_MODEL_STORE = cfg.modelStore;
        HAL0_CONTAINER_RUNTIME = "${pkgs.podman}/bin/podman";
      } // cfg.environment;
      path = with pkgs; [ podman sudo systemd bash coreutils util-linux jq curl ] ++ cfg.extraPackages;
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${hal0}/bin/hal0 bench worker --poll 10";
        Restart = "on-failure";
        RestartSec = 10;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "hal0-bench-worker";
        LimitMEMLOCK = cfg.limitMemlock;
      };
    };

    systemd.services.hal0-podman-forward = {
      description = "hal0 podman/Docker FORWARD reconciliation";
      after = [ "docker.service" ];
      partOf = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -eu
        ${pkgs.iptables}/bin/iptables -L DOCKER-USER -n >/dev/null 2>&1 || exit 0
        ${pkgs.iproute2}/bin/ip link show podman0 >/dev/null 2>&1 || exit 0
        ${pkgs.iptables}/bin/iptables -C DOCKER-USER -i podman0 -j ACCEPT 2>/dev/null || ${pkgs.iptables}/bin/iptables -I DOCKER-USER -i podman0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -C DOCKER-USER -o podman0 -j ACCEPT 2>/dev/null || ${pkgs.iptables}/bin/iptables -I DOCKER-USER -o podman0 -j ACCEPT
      '';
    };
  };
}
