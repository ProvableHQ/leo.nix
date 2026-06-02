{
  autoPatchelfHook,
  fetchurl,
  lib,
  openssl,
  stdenv,
  unzip,
}:
{
  component,
  version,
  versionData,
  binaries,
}:
let
  nixToTarget = import ./bin-systems.nix;
  sys = stdenv.hostPlatform.system;
  target = nixToTarget.${sys} or (throw "${component}-bin: no upstream binary available for ${sys}");
  hash =
    versionData.targets.${target} or (throw "${component}-bin: v${version} has no asset for ${target}");
  url = builtins.replaceStrings [ "{target}" ] [ target ] versionData.archive_url_template;

  platformsFromTargets =
    targets: lib.filter (s: targets ? ${nixToTarget.${s}}) (lib.attrNames nixToTarget);
in
stdenv.mkDerivation {
  pname = "${component}-bin";
  inherit version;

  src = fetchurl { inherit url hash; };

  nativeBuildInputs = [ unzip ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.isLinux [
    openssl
    stdenv.cc.cc.lib
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    unzip "$src"
    install -Dm755 ${lib.concatStringsSep " " binaries} -t $out/bin
    runHook postInstall
  '';

  passthru = {
    inherit version component;
    compat = versionData.compat or { };
  };

  meta = {
    description = "Prebuilt upstream ${component} binary (v${version}).";
    platforms = platformsFromTargets versionData.targets;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
