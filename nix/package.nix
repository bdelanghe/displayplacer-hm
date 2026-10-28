{ lib, pkgs }:

# displayplacer — read and set the display arrangement (resolution, refresh
# rate, rotation, origin, mirroring) from the command line. Wanted because
# `system_profiler SPDisplaysDataType` can only READ that state: it reports
# a portrait monitor at 1200x1920 degree:270, but nothing could put it back
# there after an unplug except the Displays pane and a mouse.
#
# NOT in nixpkgs — there is no `pkgs.displayplacer`. `pkgs/by-name/di/` has
# display3d and displaycal and nothing else, and a grep across the whole
# pinned tree finds no reference. Hence a derivation here rather than a name
# in packages.nix.
#
# THE RELEASE BINARY, NOT A SOURCE BUILD, and that is forced rather than
# chosen. src/Makefile links five private frameworks:
#
#   -F/System/Library/PrivateFrameworks -framework DisplayServices \
#     -framework CoreDisplay -framework OSD -framework MonitorPanel \
#     -framework SkyLight
#
# Upstream vendors exactly one of them (src/Headers/MonitorPanel.framework).
# The other four exist only under the host's /System/Library/PrivateFrameworks
# — they are not in the CommandLineTools SDK as .tbd stubs, and they are not
# in the nix darwin build sandbox. Building from source would need
# __noChroot, which would succeed on one self-hosted runner and fail on
# every other machine and in every other checkout.
#
# Same posture as betterdisplay in nixpkgs:
# fetch the signed release artifact and get out of its way.
pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "displayplacer";
  version = "1.4.0";

  src = pkgs.fetchurl {
    # The asset name is NOT derived from `version`. Upstream names it
    # `displayplacer-apple-v140` — dots stripped, and "apple" rather than
    # "arm64"/"aarch64" (the sibling asset is `displayplacer-intel-v140`).
    # Written out so a version bump fails loudly on a 404 instead of
    # silently reconstructing the wrong name.
    url = "https://github.com/jakehilborn/displayplacer/releases/download/v${finalAttrs.version}/displayplacer-apple-v140";
    hash = "sha256-BXLD0pGOR8fguddyOQeGTi6itTudOwI3l2n//PRPfqA=";
  };

  # A bare Mach-O, not an archive — there is nothing to unpack.
  dontUnpack = true;

  # LOAD-BEARING, not tidiness. The asset ships adhoc linker-signed
  # (`codesign -dv` reports flags=0x20002(adhoc,linker-signed)), and macOS
  # refuses to exec an arm64 binary whose signature no longer matches its
  # contents. nix's fixup phase strips by default, which invalidates it. The
  # failure mode is a green `nix build` followed by "killed: 9" at run time,
  # which is why the `signature` check (and tests/displayplacer.sh) runs the
  # binary rather than trusting the build.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/displayplacer
    runHook postInstall
  '';

  meta = {
    description = "Save and restore macOS display arrangement, resolution, rotation and refresh rate from the CLI";
    homepage = "https://github.com/jakehilborn/displayplacer";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "displayplacer";
  };
})
