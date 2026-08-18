{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "hal0-assets";
  version = "1.0.0-rc.6";
  src = ../..;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/usr-lib/hal0/current
    cp -a src/hal0/. $out/usr-lib/hal0/current/
    cp -a manifest.json pyproject.toml installer $out/usr-lib/hal0/current/

    mkdir -p $out/share/hal0/systemd $out/share/hal0/etc-hal0 $out/share/hal0/comfyui $out/libexec/hal0
    cp -a installer/systemd/. $out/share/hal0/systemd/
    cp -a installer/etc-hal0/. $out/share/hal0/etc-hal0/
    cp -a installer/comfyui/. $out/share/hal0/comfyui/
    cp -a installer/wrappers/. $out/libexec/hal0/
    chmod 0755 $out/libexec/hal0/*

    mkdir -p $out/usr-lib/hal0/bin
    for helper in $out/libexec/hal0/*; do
      [ -f "$helper" ] || continue
      ln -s "$helper" "$out/usr-lib/hal0/bin/$(basename "$helper")"
    done

    runHook postInstall
  '';

  meta = {
    description = "Immutable hal0 runtime, installer, systemd and configuration assets";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
