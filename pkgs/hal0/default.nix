{ lib
, stdenvNoCC
, makeWrapper
, coreutils
, curl
, git
, jq
, lshw
, pciutils
, podman
, procps
, sudo
, systemd
, util-linux
, python
, hal0-core
, hal0-ui
, hal0-assets
}:

stdenvNoCC.mkDerivation {
  pname = "hal0";
  version = "1.0.0-rc.6";
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/usr-lib/hal0 $out/share/hal0 $out/libexec
    ln -s ${hal0-core}/* $out/
    ln -s ${hal0-assets}/usr-lib/hal0/current $out/usr-lib/hal0/current
    ln -s ${hal0-assets}/usr-lib/hal0/bin $out/usr-lib/hal0/bin
    ln -s ${hal0-assets}/share/hal0/systemd $out/share/hal0/systemd
    ln -s ${hal0-assets}/share/hal0/etc-hal0 $out/share/hal0/etc-hal0
    ln -s ${hal0-assets}/share/hal0/comfyui $out/share/hal0/comfyui
    ln -s ${hal0-assets}/libexec/hal0 $out/libexec/hal0-assets
    ln -s ${hal0-ui}/dist $out/share/hal0/ui-dist

    rm -f $out/bin/hal0 $out/bin/hal0-agent
    runtimePath=${lib.makeBinPath [
      podman sudo systemd coreutils util-linux curl jq git pciutils lshw procps python
    ]}

    makeWrapper ${hal0-core}/bin/hal0 $out/bin/hal0 \
      --set-default HAL0_USR_LIB "$out/usr-lib/hal0/current" \
      --set-default HAL0_LIB "$out/usr-lib/hal0" \
      --set-default HAL0_UI_DIST "$out/share/hal0/ui-dist" \
      --prefix PATH : "$runtimePath"

    makeWrapper ${hal0-core}/bin/hal0-agent $out/bin/hal0-agent \
      --set-default HAL0_USR_LIB "$out/usr-lib/hal0/current" \
      --set-default HAL0_LIB "$out/usr-lib/hal0" \
      --set-default HAL0_UI_DIST "$out/share/hal0/ui-dist" \
      --prefix PATH : "$runtimePath"

    runHook postInstall
  '';

  passthru = { inherit hal0-core hal0-ui hal0-assets; };

  meta = {
    description = "Open-source home AI inference platform";
    homepage = "https://hal0.dev";
    license = lib.licenses.asl20;
    mainProgram = "hal0";
    platforms = lib.platforms.linux;
  };
}
