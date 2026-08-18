{ lib
, python312Packages
}:

let
  python = python312Packages.python;
  pythonPackages = with python312Packages; [
    fastapi
    uvicorn
    uvloop
    httptools
    watchfiles
    websockets
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
python312Packages.buildPythonApplication {
  pname = "hal0-core";
  version = "1.0.0-rc.6";
  src = ../..;
  pyproject = true;
  dontUseSetuptoolsBuild = true;
  build-system = [ python312Packages.hatchling ];
  dependencies = pythonPackages;

  meta = {
    description = "hal0 Python control plane and CLI";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
