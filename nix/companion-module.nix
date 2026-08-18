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
  imports = [
    (modulesPath + "/virtualisation/oci-containers.nix")
  ];

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
        description = "Run the bundled Hermes Agent companion using the upstream container runtime.";
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

    environment.systemPackages = lib.optional he.enable pkgs.podman;

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
          } // lib.optionalAttrs (h.environmentFile != null) {
            HINDSIGHT_ENVIRONMENT_FILE = h.environmentFile;
          };
        };
      })
      (lib.mkIf ow.enable {
        hal0-openwebui = {
          image = ow.image;
          autoStart = true;
          ports = [ "${ow.bindHost}:3001:8080" ];
          volumes = [ "${ow.dataDir}:/app/backend/data:rw" ];
          environment = {
            WEBUI_AUTH = if ow.trustedEmailHeader != null then "true" else "false";
          } // lib.optionalAttrs (ow.trustedEmailHeader != null) {
            WEBUI_AUTH_TRUSTED_EMAIL_HEADER = ow.trustedEmailHeader;
          };
        };
      })
      (lib.mkIf he.enable {
        hal0-hermes = {
          image = he.image;
          autoStart = true;
          ports = [ "${he.bindHost}:${toString he.dashboardPort}:${toString he.dashboardPort}" ];
          volumes = [ "${he.dataDir}:/opt/data:rw" ];
          environment = {
            HERMES_CONFIG = "/etc/hal0/hermes/config.yaml";
          };
          extraOptions = [ "--add-host=${hostGateway}" ];
        };
      })
      (lib.mkIf bw.enable {
        hal0-bench-worker = {
          image = he.image;
          autoStart = true;
          volumes = [ "/var/lib/hal0:/var/lib/hal0:rw" ];
          environment = {
            HERMES_CONFIG = "/etc/hal0/hermes/config.yaml";
          };
          extraOptions = [ "--add-host=${hostGateway}" ];
          cmd = [ "python" "-m" "hermes_agent.bench_worker" ];
        };
      })
    ];
  };
}
