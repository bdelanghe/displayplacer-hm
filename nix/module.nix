{ config, lib, pkgs, ... }:

# displayplacer for Home Manager: the release binary (nix/package.nix explains why not a source build),
# displayplacer-apply (reasserts a pinned arrangement, a no-op unless every pinned display is connected),
# and an activation step that runs it when `arrangement` is set.
let
  cfg = config.programs.displayplacer;

  displayplacer = import ./package.nix { inherit lib pkgs; };

  # The persistent id out of each spec — `id:XXXX res:… degree:…` → `XXXX`.
  # Computed here rather than parsed in the shell so a malformed spec is an
  # eval error, not a runtime surprise during activation.
  ids = map (s: lib.removePrefix "id:" (lib.head (lib.splitString " " s))) cfg.arrangement;

  # The applier, exposed as a command in its own right and ALSO called from
  # activation. Having it on PATH is what makes the declared arrangement
  # recoverable on demand — plug the monitor back in, run
  # `displayplacer-apply`, without waiting for the next switch.
  #
  # THE GUARD IS THE POINT. displayplacer given a spec for a display that is
  # not connected does not quietly skip it, and an activation script that can
  # fail is an activation script that can fail a `home-manager switch` — over
  # an undocked monitor, on a machine that switches itself unattended. So:
  # every declared id must be present, or this does nothing and says so.
  # Exit 0 either way; a display tool must never be able to break a switch.
  apply = pkgs.writeShellScriptBin "displayplacer-apply" ''
    set -u

    dp=${lib.getExe displayplacer}

    if ! list=$("$dp" list 2>&1); then
      echo "displayplacer-apply: cannot read the display list; leaving it alone" >&2
      exit 0
    fi

    for id in ${lib.escapeShellArgs ids}; do
      case "$list" in
        *"$id"*) ;;
        *)
          echo "displayplacer-apply: $id not connected; leaving the arrangement alone" >&2
          exit 0
          ;;
      esac
    done

    "$dp" ${lib.escapeShellArgs cfg.arrangement} || {
      echo "displayplacer-apply: displayplacer refused the arrangement" >&2
      exit 0
    }
  '';
in
{
  options.programs.displayplacer = {
    enable = lib.mkEnableOption "displayplacer and displayplacer-apply, and (when `arrangement` is set) reasserting that arrangement at every activation";
    arrangement = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = lib.literalExpression ''
        [ "id:37D8832A-… res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" ]
      '';
      description = ''
        Display specs to reassert on every activation, in displayplacer's own
        syntax. `displayplacer list` prints the line for the current layout as
        its last line — paste its arguments here.

        Empty (the default) installs the tool and pins nothing.

        The ids are persistent-per-monitor, not per-port: they survive a
        replug but die with the monitor. Replacing a screen means re-running
        `displayplacer list` and editing this list.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The tool, plus the applier — which is useful by hand whether or not
    # anything is pinned (it is a no-op when `arrangement` is empty).
    home.packages = [ displayplacer apply ];

    # PINNED ON SWITCH. Stated plainly because it is a trade, not a free win:
    # a rotation you make by hand is undone the next time this machine
    # switches. That is what pinning means and it was asked for deliberately.
    #
    # How often that is depends on how often the machine switches, not on
    # the clock: the arrangement is reasserted at the moments the machine is
    # already rebuilding itself.
    #
    # `entryAfter [ "writeBoundary" ]` because this runs a command out of the
    # new profile: before the boundary, that path is not on disk yet.
    home.activation.displayplacerArrangement =
      lib.mkIf (cfg.arrangement != [ ])
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ${lib.getExe apply}
        '');
  };
}
