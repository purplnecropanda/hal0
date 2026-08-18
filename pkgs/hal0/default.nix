{ lib
, symlinkJoin
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

symlinkJoin {
  name = "hal0";
  paths = [ hal0-core hal0-assets ];

  postBuild = ''
    mkdir -p $out/share/hal0
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
