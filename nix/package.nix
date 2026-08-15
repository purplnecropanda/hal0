{ lib
, buildPythonApplication
, buildNpmPackage
, fetchFromGitHub
, python312Packages
, nodejs_20
, makeWrapper
, podman
, systemd
, bash
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
  version = "1.0.0-rc.5";

  src = fetchFromGitHub {
    owner = "purplnecropanda";
    repo = "hal0";
    rev = "main";
    hash = lib.fakeHash;
  };

  # The UI is built from the repository's lockfile rather than from the
  # interactive installer. This keeps the Nix build reproducible and removes
  # Node/npm provisioning from the runtime closure.
  ui = buildNpmPackage {
    pname = "hal0-ui";
    inherit version src;
    sourceRoot = "source/ui";
    npmDepsHash = lib.fakeHash;
    nodejs = nodejs_20;
    npmBuildScript = "build";
  };

  pythonPackages = with python312Packages; [
    fastapi
    uvicorn
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
  ];
in

buildPythonApplication {
  inherit pname version src;
  pyproject = true;

  build-system = [ python312Packages.hatchling ];
  dependencies = pythonPackages;

  nativeBuildInputs = [
    makeWrapper
    bash
  ];

  # hal0 is intentionally packaged as an immutable application. Its upstream
  # self-updater is not part of the NixOS runtime contract; configuration and
  # mutable state remain under /etc/hal0 and /var/lib/hal0 instead.
  postPatch = ''
    substituteInPlace src/hal0/config/paths.py \
      --replace-fail 'def usr_lib() -> Path:' 'def usr_lib() -> Path:'
  '';

  postInstall = ''
    mkdir -p $out/share/hal0/ui
    cp -r ${ui}/lib/node_modules/hal0-ui/dist $out/share/hal0/ui/ 2>/dev/null || true
    if [ ! -e $out/share/hal0/ui/dist ]; then
      cp -r ${ui}/dist $out/share/hal0/ui/dist
    fi

    mkdir -p $out/share/hal0/systemd $out/libexec/hal0
    cp installer/wrappers/hal0-systemctl $out/libexec/hal0/hal0-systemctl
    chmod +x $out/libexec/hal0/hal0-systemctl
    cp installer/systemd/hal0.target $out/share/hal0/systemd/hal0.target
    cp installer/systemd/hal0-agent@.service $out/share/hal0/systemd/hal0-agent@.service

    # NixOS supplies the runtime on PATH, but keeping these helpers in the
    # package makes `hal0`/`hal0-agent` usable from `nix run` as well.
    wrapProgram $out/bin/hal0 \
      --prefix PATH : ${lib.makeBinPath [ podman systemd bash fastflowlm xrt ]}
    wrapProgram $out/bin/hal0-agent \
      --prefix PATH : ${lib.makeBinPath [ podman systemd bash fastflowlm xrt ]}
  '';

  passthru = {
    inherit ui;
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
