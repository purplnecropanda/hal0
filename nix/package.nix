{ lib
, buildNpmPackage
, python312Packages
, nodejs_20
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

  src = ./..;

  ui = buildNpmPackage {
    pname = "hal0-ui";
    inherit version src;
    sourceRoot = "source/ui";
    npmDepsHash = "sha256-REPLACE_WITH_NPM_DEPS_HASH";
    nodejs = nodejs_20;
    npmBuildScript = "build";
    installPhase = ''
      runHook preInstall
      mkdir -p $out/dist
      cp -r dist/. $out/dist/
      runHook postInstall
    '';
  };

  pythonPackages = with python312Packages; [
    fastapi
    uvicorn
    uvloop
    httptools
    watchfiles
    websockets
    python-dotenv
    httpx
    pydantic
    pydantic-settings
    typer
    structlog
    tomli-w
    rich
    mcp
    jinja2
    pyyaml
    psutil
    packaging
    sentry-sdk
    guidellm
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

    mkdir -p $out/share/hal0/ui $out/share/hal0/systemd $out/share/hal0/etc-hal0 $out/share/hal0/comfyui $out/libexec/hal0
    cp -a ${ui}/dist $out/share/hal0/ui/dist
    cp -a installer/systemd/. $out/share/hal0/systemd/
    cp -a installer/etc-hal0/. $out/share/hal0/etc-hal0/
    cp -a installer/comfyui/. $out/share/hal0/comfyui/
    cp -a installer/wrappers/hal0-systemctl $out/libexec/hal0/hal0-systemctl
    if [ -f installer/wrappers/hal0-benchctl ]; then
      cp -a installer/wrappers/hal0-benchctl $out/libexec/hal0/hal0-benchctl
    fi
    if [ -f installer/wrappers/hal0-agentenv ]; then
      cp -a installer/wrappers/hal0-agentenv $out/libexec/hal0/hal0-agentenv
    fi
    chmod 0755 $out/libexec/hal0/*

    runtimePath=${lib.makeBinPath [
      podman sudo systemd bash coreutils util-linux curl jq git pciutils lshw procps
      fastflowlm xrt
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
