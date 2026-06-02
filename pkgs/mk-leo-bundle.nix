# Resolves and bundles a leo-lang release together with its compat-latest
# plugin versions (leo-fmt, leo-lsp) into a single symlinkJoin.
#
# Resolution rule (per the plan):
#   For each plugin component, take the set of plugin versions whose
#   `compat.leo-lang` equals the target leo-lang version, union with the
#   leo-lang release's own `leo-release.toml` pin (recorded as
#   `components.leo-lang.versions.<v>.compat.<plugin>`), then pick the highest
#   semver of that set. The toml pin is the fallback when no plugin release
#   has explicitly claimed compat with this leo-lang.
{
  lib,
  symlinkJoin,
}:
{
  mkLeoBin,
  manifest,
  leoLangVersion,
}:
let
  components = manifest.components or { };
  leoLangData = components.leo-lang.versions.${leoLangVersion};

  resolvePlugin =
    pluginName:
    let
      versions = (components.${pluginName} or { }).versions or { };
      versionNames = lib.attrNames versions;
      # Plugin versions that explicitly declare compat with this leo-lang.
      explicit = lib.filter (v: (versions.${v}.compat.leo-lang or null) == leoLangVersion) versionNames;
      # leo-lang's own toml pin (always present for releases that shipped a toml).
      pinned = leoLangData.compat.${pluginName} or null;
      candidates = lib.unique (
        explicit ++ (lib.optional (pinned != null && versions ? ${pinned}) pinned)
      );
      sorted = lib.sort (a: b: lib.versionOlder a b) candidates;
    in
    if sorted == [ ] then
      throw "leo-bin: cannot resolve a ${pluginName} version compatible with leo-lang ${leoLangVersion}"
    else
      lib.last sorted;

  mkComponentDrv =
    component: version:
    mkLeoBin {
      inherit component version;
      versionData = components.${component}.versions.${version};
      binaries = components.${component}.binaries;
    };

  cliDrv = mkComponentDrv "leo-lang" leoLangVersion;
  fmtVersion = resolvePlugin "leo-fmt";
  lspVersion = resolvePlugin "leo-lsp";
  fmtDrv = mkComponentDrv "leo-fmt" fmtVersion;
  lspDrv = mkComponentDrv "leo-lsp" lspVersion;
in
symlinkJoin {
  name = "leo-bin-${leoLangVersion}";
  paths = [
    cliDrv
    fmtDrv
    lspDrv
  ];
  passthru = {
    inherit (cliDrv) version;
    cli = cliDrv;
    fmt = fmtDrv;
    lsp = lspDrv;
    resolvedVersions = {
      leo-lang = leoLangVersion;
      leo-fmt = fmtVersion;
      leo-lsp = lspVersion;
    };
  };
  meta = {
    description = "Prebuilt leo CLI plus compat-resolved leo-fmt and leo-lsp (leo-lang v${leoLangVersion}).";
    platforms = lib.foldl' lib.intersectLists (lib.attrNames (import ./bin-systems.nix)) [
      cliDrv.meta.platforms
      fmtDrv.meta.platforms
      lspDrv.meta.platforms
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
