{ lib
, buildNpmPackage
, importNpmLock
, nodejs_24
}:

buildNpmPackage {
  pname = "hal0-ui";
  version = "1.0.0-rc.6";
  src = ../../ui;
  npmDeps = importNpmLock { npmRoot = ../../ui; };
  npmConfigHook = importNpmLock.npmConfigHook;
  nodejs = nodejs_24;
  npmBuildScript = "build";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/dist
    cp -r dist/. $out/dist/
    runHook postInstall
  '';

  meta = {
    description = "hal0 web dashboard";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
