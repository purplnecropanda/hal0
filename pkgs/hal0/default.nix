{ lib
, buildNpmPackage
, importNpmLock
, python312Packages
, nodejs_24
, makeWrapper
, podman
, systemd
, bash
, coreutils
, util-linux
, curl
, jq
, git
, pciutils
, lshw
, procps
, sudo
, fastflowlm
, xrt
, xrt-plugin-amdxdna
, llama-cpp-vulkan
, llama-cpp-rocm
, whisper-cpp-vulkan
, stable-diffusion-cpp-vulkan
, stable-diffusion-cpp-rocm
}:

let
  pname = "hal0";
  version = "1.0.0-rc.6";
  buildPythonApplication = python312Packages.buildPythonApplication;
  python = python312Packages.python;
  src = ./../..;

  ui = buildNpmPackage {
    pname = "hal0-ui";
    version = version;
    src = ./../../ui;
    npmDeps = importNpmLock { npmRoot = ./../../ui; };
    npmConfigHook = importNpmLock.npmConfigHook;
    nodejs = nodejs_24;
    npmBuildScript = "build";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/dist
      cp -r dist/. $out/dist/
      runHook postInstall
    '';
  };

  pythonPackages = with python312Packages; [
    fastapi uvicorn uvloop httptools watchfiles websockets httpx
    pydantic pydantic-settings typer structlog tomli-w rich mcp jinja2
    pyyaml psutil packaging
  ];
in
buildPythonApplication {
  inherit pname version src;
  pyproject = true;
  dontUseSetuptoolsBuild = true;
  build-system = [ python312Packages.hatchling ];
  dependencies = pythonPackages;
  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    mkdir -p $out/usr-lib/hal0/current
    cp -a src/hal0/. $out/usr-lib/hal0/current/
    cp -a manifest.json $out/usr-lib/hal0/current/manifest.json
    cp -a pyproject.toml $out/usr-lib/hal0/current/pyproject.toml
    cp -a installer $out/usr-lib/hal0/current/installer

    mkdir -p $out/share/hal0/ui $out/share/hal0/systemd $out/share/hal0/etc-hal0 $out/share/hal0/comfyui $out/libexec/hal0
    cp -a ${ui}/dist $out/share/hal0/ui/dist
    cp -a installer/systemd/. $out/share/hal0/systemd/
    cp -a installer/etc-hal0/. $out/share/hal0/etc-hal0/
    cp -a installer/comfyui/. $out/share/hal0/comfyui/
    cp -a installer/wrappers/. $out/libexec/hal0/
    chmod 0755 $out/libexec/hal0/*

    substituteInPlace $out/libexec/hal0/hal0-agentenv \
      --replace-fail 'python3 -c' '${python}/bin/python -c'

    mkdir -p $out/usr-lib/hal0/bin
    for helper in $out/libexec/hal0/*; do
      [ -f "$helper" ] || continue
      ln -s "$helper" "$out/usr-lib/hal0/bin/$(basename "$helper")"
    done

    # Keep the base package lightweight: accelerator runtimes are exposed via
    # passthru and consumed by the feature-specific NixOS modules/services.
    runtimePath=${lib.makeBinPath [
      podman sudo systemd bash coreutils util-linux curl jq git pciutils lshw procps python
    ]}

    wrapProgram $out/bin/hal0 \
      --set-default HAL0_USR_LIB "$out/usr-lib/hal0/current" \
      --set-default HAL0_LIB "$out/usr-lib/hal0" \
      --set-default HAL0_UI_DIST "$out/share/hal0/ui/dist" \
      --prefix PATH : "$runtimePath"

    wrapProgram $out/bin/hal0-agent \
      --set-default HAL0_USR_LIB "$out/usr-lib/hal0/current" \
      --set-default HAL0_LIB "$out/usr-lib/hal0" \
      --set-default HAL0_UI_DIST "$out/share/hal0/ui/dist" \
      --prefix PATH : "$runtimePath"
  '';

  passthru = {
    inherit ui;
    systemdUnits = "$out/share/hal0/systemd";
    installerAssets = "$out/share/hal0/etc-hal0";
    installerRoot = "$out/usr-lib/hal0/current/installer";
    comfyuiAssets = "$out/share/hal0/comfyui";
    privilegedWrappers = "$out/libexec/hal0";
    amdAiRuntime = {
      inherit fastflowlm xrt xrt-plugin-amdxdna llama-cpp-vulkan llama-cpp-rocm
        whisper-cpp-vulkan stable-diffusion-cpp-vulkan stable-diffusion-cpp-rocm;
    };
  };

  meta = {
    description = "Open-source home AI inference platform";
    homepage = "https://hal0.dev";
    license = lib.licenses.asl20;
    mainProgram = "hal0";
    platforms = [ "x86_64-linux" ];
  };
}
