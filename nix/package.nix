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

  # Hashes are intentionally left as explicit TODO markers rather than fake
  # values. Run `nix build .#hal0` once with network access; Nix will report the
  # exact fixed-output hashes to paste here. This prevents a reviewable PR from
  # pretending that an unbuilt derivation is reproducible.
  src = fetchFromGitHub {
    owner = "purplnecropanda";
    repo = "hal0";
    rev = "main";
    hash = "sha256-REPLACE_WITH_NIX_HASH";
  };

  ui = buildNpmPackage {
    pname = "hal0-ui";
    inherit version src;
    sourceRoot = "source/ui";
    npmDepsHash = "sha256-REPLACE_WITH_NPM_DEPS_HASH";
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
  nativeBuildInputs = [ makeWrapper bash ];

  postInstall = ''
    mkdir -p $out/share/hal0/ui
    cp -r ${ui}/dist $out/share/hal0/ui/dist

    # Preserve the upstream FHS-relative read-only code tree for code paths
    # that resolve shipped templates/assets through hal0.config.paths.lib().
    mkdir -p $out/usr-lib/hal0/current
    cp -r src/hal0/. $out/usr-lib/hal0/current/

    mkdir -p $out/share/hal0/systemd $out/libexec/hal0
    cp installer/wrappers/hal0-systemctl $out/libexec/hal0/hal0-systemctl
    chmod 0755 $out/libexec/hal0/hal0-systemctl
    cp installer/systemd/hal0.target $out/share/hal0/systemd/hal0.target
    cp installer/systemd/hal0-agent@.service $out/share/hal0/systemd/hal0-agent@.service

    wrapProgram $out/bin/hal0 \
      --set-default HAL0_USR_LIB "$out/usr-lib/hal0/current" \
      --set-default HAL0_LIB "$out/usr-lib/hal0" \
      --set-default HAL0_UI_DIST "$out/share/hal0/ui/dist" \
      --prefix PATH : ${lib.makeBinPath [ podman systemd bash fastflowlm xrt ]}

    wrapProgram $out/bin/hal0-agent \
      --set-default HAL0_USR_LIB "$out/usr-lib/hal0/current" \
      --set-default HAL0_LIB "$out/usr-lib/hal0" \
      --set-default HAL0_UI_DIST "$out/share/hal0/ui/dist" \
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
