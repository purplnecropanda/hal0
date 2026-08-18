{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.services.hal0;
  h = cfg.hindsight;
  ow = cfg.openwebui;
  he = cfg.hermes;
  bw = cfg.benchWorker;
  seeds = cfg.staticSeeds;
  setup = cfg.bootstrap;
  brain = cfg.models.brain;
  agent = cfg.models.agent;
  comfy = cfg.comfyui;
  python = pkgs.python312Packages.python;

  hostGateway = "host.docker.internal:host-gateway";
  hindsightImage = "ghcr.io/vectorize-io/hindsight:0.7.2";
  openWebuiImage = "ghcr.io/open-webui/open-webui@sha256:7f1b0a1a50cfbac23da3b16f96bc968fd757b26dc9e54e93813d61768ea9184e";
  hermesImage = "docker.io/nousresearch/hermes-agent:v2026.7.7.2";

  enabled = cfg.enable;
  pythonPath = "${cfg.package}/${python.sitePackages}";
in
{
  imports = [ (modulesPath + "/virtualisation/oci-containers.nix") ];

  options.services.hal0 = {
    staticSeeds.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Seed the upstream slot/profile asset catalog into mutable /etc/hal0 state on first boot, without overwriting operator changes or tombstones.";
    };

    bootstrap = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run hal0's non-interactive first-boot capability/slot bootstrap (`hal0 setup --auto --no-pull --no-extensions`).";
      };
      modelsStorageDir = lib.mkOption {
        type = lib.types.path;
        default = cfg.modelStore;
        description = "Storage directory passed to the first-boot hal0 setup command.";
      };
    };

    models = {
      hfTokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Optional EnvironmentFile containing HF_TOKEN for model pulls.";
      };
      brain = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run the hardware-aware hal0 brain model provisioner. Failures are non-fatal and leave the brain slot model-less.";
        };
        modelOverride = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional curated hal0 brain model id, equivalent to HAL0_BRAIN_MODEL.";
        };
      };
      agent = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Opt into the larger Hermes fallback agent model pull. This is intentionally off by default.";
        };
        modelOverride = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional curated Hermes agent model id, equivalent to HAL0_AGENT_MODEL.";
        };
      };
    };

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
        description = "Run the bundled Hermes Agent companion.";
      };
      runtime = lib.mkOption {
        type = lib.types.enum [ "native" "container" ];
        default = "native";
        description = "Hermes runtime implementation.";
      };
      image = lib.mkOption { type = lib.types.str; default = hermesImage; };
      dataDir = lib.mkOption { type = lib.types.path; default = "/var/lib/hal0/hermes"; };
      dashboardPort = lib.mkOption { type = lib.types.port; default = 9119; };
      apiPort = lib.mkOption { type = lib.types.port; default = 8642; };
      bindHost = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      model = lib.mkOption { type = lib.types.str; default = "hal0/agent"; };
      apiServer = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Expose Hermes' optional API server. Requires apiKeyFile.";
        };
        apiKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "EnvironmentFile containing API_SERVER_KEY when Hermes API server is enabled.";
        };
      };
    };

    benchWorker.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run hal0's queue worker used by the benchmark dashboard.";
    };

    comfyui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create and seed the ComfyUI model share consumed by the image slot.";
      };
      modelsRoot = lib.mkOption {
        type = lib.types.path;
        default = "/mnt/ai-models/comfyui";
        description = "Persistent ComfyUI model/share root.";
      };
      seedAssets = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Seed extra_model_paths.yaml and shipped custom nodes when absent.";
      };
    };
  };

  config = lib.mkIf enabled {
    virtualisation.oci-containers.backend = "podman";

    environment.systemPackages = lib.optional (he.enable && he.runtime == "container") pkgs.podman;

    # The core module deliberately keeps service construction small. Run the
    # installed hal0 executable itself so the full packaged dependency closure
    # and its path wrappers are used by API/CLI operations.
    systemd.services.hal0-api.serviceConfig.ExecStart = lib.mkForce "${cfg.package}/bin/hal0 serve --port ${toString cfg.port}";

    systemd.tmpfiles.rules = [
      "d ${h.dataDir} 2775 ${cfg.user} ${cfg.group} - -"
      "d ${ow.dataDir} 2775 ${cfg.user} ${cfg.group} - -"
      "d ${he.dataDir} 2775 ${cfg.user} ${cfg.group} - -"
      "d ${comfy.modelsRoot} 2775 ${cfg.user} ${cfg.group} - -"
      "d ${comfy.modelsRoot}/models 2775 ${cfg.user} ${cfg.group} - -"
      "d ${comfy.modelsRoot}/output 2775 ${cfg.user} ${cfg.group} - -"
      "d ${comfy.modelsRoot}/input 2775 ${cfg.user} ${cfg.group} - -"
      "d ${comfy.modelsRoot}/user 2775 ${cfg.user} ${cfg.group} - -"
      "d ${comfy.modelsRoot}/custom_nodes 2775 ${cfg.user} ${cfg.group} - -"
    ];

    environment.etc."hal0/hermes/config.yaml" = lib.mkIf (he.enable && he.runtime == "container") {
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

    systemd.services.hal0-seed-static-config = lib.mkIf seeds.enable {
      description = "hal0 seed immutable installer assets into mutable /etc/hal0";
      before = [ "hal0-bootstrap.service" "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        set -eu
        src=${cfg.package}/share/hal0/etc-hal0
        install -d -m 0755 /etc/hal0/slots
        if [ ! -e /etc/hal0/profiles.toml ]; then
          install -m 0644 "$src/profiles.toml" /etc/hal0/profiles.toml
        fi
        for f in "$src"/slots/*.toml; do
          name=$(basename "$f")
          if [ ! -e "/etc/hal0/slots/$name" ]; then
            install -m 0644 "$f" "/etc/hal0/slots/$name"
          fi
        done
      '';
    };

    systemd.services.hal0-bootstrap = lib.mkIf setup.enable {
      description = "hal0 non-interactive first-boot capability and slot bootstrap";
      after = [ "network-online.target" "hal0-seed-static-config.service" ];
      before = [ "hal0-api.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HAL0_ETC = "/etc/hal0";
        HAL0_VAR_LIB = "/var/lib/hal0";
        HAL0_MODEL_STORE = setup.modelsStorageDir;
        HAL0_FLM_MODELS_DIR = cfg.flmModelStore;
      };
      path = with pkgs; [ podman bash coreutils curl jq systemd ] ++ cfg.extraPackages;
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${cfg.package}/bin/hal0 setup --auto --no-pull --no-extensions --storage-dir ${setup.modelsStorageDir}";
        RemainAfterExit = true;
        TimeoutStartSec = "10min";
      };
    };

    systemd.services.hal0-brain-model = lib.mkIf brain.enable {
      description = "hal0 hardware-aware brain model provisioner";
      after = [ "network-online.target" "hal0-bootstrap.service" "hal0-api.service" ];
      wants = [ "network-online.target" "hal0-bootstrap.service" "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HAL0_ETC = "/etc/hal0";
        HAL0_VAR_LIB = "/var/lib/hal0";
        HAL0_MODEL_STORE = cfg.modelStore;
        HAL0_FLM_MODELS_DIR = cfg.flmModelStore;
        HAL0_BRAIN_MODEL = lib.optionalString (brain.modelOverride != null) brain.modelOverride;
        PYTHONPATH = pythonPath;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${python}/bin/python -m hal0.install.brain_model";
        RemainAfterExit = true;
        TimeoutStartSec = "90min";
        EnvironmentFile = lib.optional brain.enable (lib.mkIf (cfg.models.hfTokenFile != null) cfg.models.hfTokenFile);
      };
      path = with pkgs; [ curl coreutils ] ++ cfg.extraPackages;
    };

    systemd.services.hal0-agent-model = lib.mkIf agent.enable {
      description = "hal0 optional Hermes agent model provisioner";
      after = [ "network-online.target" "hal0-bootstrap.service" ];
      wants = [ "network-online.target" "hal0-bootstrap.service" ];
      wantedBy = [ "multi-user.target" ];
      environment = {
        HAL0_ETC = "/etc/hal0";
        HAL0_VAR_LIB = "/var/lib/hal0";
        HAL0_MODEL_STORE = cfg.modelStore;
        HAL0_FLM_MODELS_DIR = cfg.flmModelStore;
        HAL0_AGENT_MODEL = lib.optionalString (agent.modelOverride != null) agent.modelOverride;
        PYTHONPATH = pythonPath;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${python}/bin/python -m hal0.install.agent_model";
        RemainAfterExit = true;
        TimeoutStartSec = "3h";
        EnvironmentFile = lib.optional agent.enable (lib.mkIf (cfg.models.hfTokenFile != null) cfg.models.hfTokenFile);
      };
      path = with pkgs; [ curl coreutils ] ++ cfg.extraPackages;
    };

    systemd.services.hal0-comfyui-share = lib.mkIf comfy.enable {
      description = "hal0 seed ComfyUI model share";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; User = "root"; RemainAfterExit = true; };
      script = ''
        set -eu
        root=${comfy.modelsRoot}
        mkdir -p "$root"/{models,output,input,user,custom_nodes}
        ${lib.optionalString comfy.seedAssets ''
          if [ ! -e "$root/extra_model_paths.yaml" ]; then
            install -m 0644 ${cfg.package}/share/hal0/comfyui/extra_model_paths.yaml "$root/extra_model_paths.yaml"
          fi
          for f in ${cfg.package}/share/hal0/comfyui/custom_nodes/*.py; do
            [ -e "$f" ] || continue
            dst="$root/custom_nodes/$(basename "$f")"
            [ -e "$dst" ] || install -m 0644 "$f" "$dst"
          done
        ''}
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
      (lib.mkIf (he.enable && he.runtime == "container") {
        hal0-hermes = {
          image = he.image;
          autoStart = true;
          ports = [ "${he.bindHost}:${toString he.dashboardPort}:9119" ] ++ lib.optional he.apiServer.enable "${he.bindHost}:${toString he.apiPort}:8642";
          volumes = [
            "${he.dataDir}:/opt/data:rw"
            "/etc/hal0/hermes/config.yaml:/opt/data/config.yaml:ro"
            "/var/lib/hal0/skills:/opt/data/skills:rw"
          ];
          environment = {
            HERMES_DASHBOARD = "1";
            HERMES_DASHBOARD_HOST = "0.0.0.0";
            HERMES_DASHBOARD_INSECURE = "1";
            API_SERVER_ENABLED = lib.boolToString he.apiServer.enable;
            API_SERVER_HOST = "0.0.0.0";
            API_SERVER_PORT = toString he.apiPort;
            HINDSIGHT_API_URL = "http://host.docker.internal:${toString h.port}";
            HINDSIGHT_TIMEOUT = "60";
          };
          environmentFiles = lib.optional (he.apiServer.enable && he.apiServer.apiKeyFile != null) he.apiServer.apiKeyFile;
          cmd = [ "gateway" "run" ];
          extraOptions = [ "--add-host=${hostGateway}" ];
        };
      })
    ];

    assertions = [
      {
        assertion = !he.apiServer.enable || he.apiServer.apiKeyFile != null;
        message = "services.hal0.hermes.apiServer.apiKeyFile must be set when services.hal0.hermes.apiServer.enable is true.";
      }
    ];

    # Stable unit names expected by the hal0 runtime/CLI while the underlying
    # OCI module owns container lifecycle.
    systemd.services.hindsight-api = lib.mkIf h.enable {
      description = "hal0 Hindsight API companion";
      after = [ "podman-halo0-hindsight.service" "podman-hal0-hindsight.service" "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl start podman-hal0-hindsight.service";
        ExecStop = "${pkgs.systemd}/bin/systemctl stop podman-hal0-hindsight.service";
        RemainAfterExit = true;
      };
    };

    systemd.services.hal0-openwebui = lib.mkIf ow.enable {
      description = "hal0 OpenWebUI companion service";
      after = [ "podman-hal0-openwebui.service" "hal0-api.service" ];
      wants = [ "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl start podman-hal0-openwebui.service";
        ExecStop = "${pkgs.systemd}/bin/systemctl stop podman-hal0-openwebui.service";
        RemainAfterExit = true;
      };
    };

    systemd.services.hal0-hermes = lib.mkIf (he.enable && he.runtime == "container") {
      description = "hal0 Hermes Agent companion service";
      after = [ "podman-hal0-hermes.service" "hal0-api.service" ];
      wants = [ "hal0-api.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl start podman-hal0-hermes.service";
        ExecStop = "${pkgs.systemd}/bin/systemctl stop podman-hal0-hermes.service";
        RemainAfterExit = true;
      };
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
        ExecStart = "${cfg.package}/bin/hal0 bench worker --poll 10";
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
