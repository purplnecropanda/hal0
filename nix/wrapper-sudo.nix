{ config, lib, ... }:

let
  cfg = config.services.hal0;
  bin = name: "${cfg.package}/usr-lib/hal0/bin/${name}";
in
{
  config = lib.mkIf cfg.enable {
    security.sudo.extraRules = [
      {
        users = [ cfg.user ];
        commands = [
          { command = bin "hal0-agentenv"; options = [ "NOPASSWD" ]; }
          { command = bin "hal0-benchctl"; options = [ "NOPASSWD" ]; }
          { command = bin "hal0-podman-ro"; options = [ "NOPASSWD" ]; }
          { command = bin "hal0-update"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];
  };
}
