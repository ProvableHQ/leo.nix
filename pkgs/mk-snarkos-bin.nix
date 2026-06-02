{
  autoPatchelfHook,
  fetchurl,
  lib,
  openssl,
  stdenv,
  unzip,
  zlib,
}:
{
  version,
  data,
}:
let
  nixToTarget = import ./bin-systems.nix;
  sys = stdenv.hostPlatform.system;
  target = nixToTarget.${sys} or (throw "snarkos-bin: no upstream binary available for ${sys}");
  hash = data.targets.${target} or (throw "snarkos-bin: v${version} has no asset for ${target}");
  url = builtins.replaceStrings [ "{target}" ] [ target ] data.archive_url_template;

  platformsFromTargets =
    targets: lib.filter (s: targets ? ${nixToTarget.${s}}) (lib.attrNames nixToTarget);
in
stdenv.mkDerivation {
  pname = "snarkos-bin";
  inherit version;

  src = fetchurl { inherit url hash; };

  nativeBuildInputs = [ unzip ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  # zlib is needed by snarkos v4.0–v4.5 (later versions drop the dependency
  # but adding it unconditionally is harmless).
  buildInputs = lib.optionals stdenv.isLinux [
    openssl
    stdenv.cc.cc.lib
    zlib
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    unzip "$src"
    install -Dm755 ${data.binary} -t $out/bin
    runHook postInstall
  '';

  passthru = { inherit version; };

  meta = {
    description = "Prebuilt upstream snarkOS binary (v${version}).";
    platforms = platformsFromTargets data.targets;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
