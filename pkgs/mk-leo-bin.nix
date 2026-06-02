{
  autoPatchelfHook,
  fetchurl,
  lib,
  openssl,
  stdenv,
  symlinkJoin,
  unzip,
}:
{
  version,
  data,
}:
let
  nixToTarget = import ./bin-systems.nix;

  platformsFromTargets =
    targets: lib.filter (sys: targets ? ${nixToTarget.${sys}}) (lib.attrNames nixToTarget);

  mkComponent =
    cname: cdata:
    let
      sys = stdenv.hostPlatform.system;
      target = nixToTarget.${sys} or (throw "leo-bin: no upstream binary available for ${sys}");
      hash =
        cdata.targets.${target} or (throw "leo-bin: '${cname}' v${version} has no asset for ${target}");
      url = builtins.replaceStrings [ "{target}" ] [ target ] cdata.archive_url_template;
    in
    stdenv.mkDerivation {
      pname = "${cname}-bin";
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
        install -Dm755 ${lib.concatStringsSep " " cdata.binaries} -t $out/bin
        runHook postInstall
      '';

      meta = {
        description = "Prebuilt upstream ${cname} binary (v${version}).";
        platforms = platformsFromTargets cdata.targets;
        sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      };
    };

  components = lib.mapAttrs mkComponent data.components;

  componentPlatforms = map (c: c.meta.platforms) (lib.attrValues components);
  combinedPlatforms = lib.foldl' lib.intersectLists (lib.attrNames nixToTarget) componentPlatforms;
in
symlinkJoin {
  name = "leo-bin-${version}";
  paths = lib.attrValues components;
  passthru = {
    inherit version components;
    cli = components.leo-lang;
    fmt = components.leo-fmt;
    lsp = components.leo-lsp;
  };
  meta = {
    description = "Prebuilt leo CLI plus first-party plugins (v${version}).";
    platforms = combinedPlatforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
