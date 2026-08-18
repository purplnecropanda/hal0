{ config, lib, ... }:

let
  cfg = config.services.hal0;
  hf = lib.optional (cfg.models.hfTokenFile != null) cfg.models.hfTokenFile;
in
{
  config = lib.mkIf cfg.enable {
    systemd.services.hal0-brain-model.serviceConfig.EnvironmentFile = lib.mkForce hf;
    systemd.services.hal0-agent-model.serviceConfig.EnvironmentFile = lib.mkForce hf;
  };
}
