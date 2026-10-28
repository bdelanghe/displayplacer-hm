# displayplacer-hm

[displayplacer](https://github.com/jakehilborn/displayplacer) (set macOS display resolution, refresh rate,
rotation and origin from the CLI) for Home Manager, aarch64-darwin.

- The **release binary**, not a source build: upstream links four private frameworks that exist only under the
  host's `/System/Library/PrivateFrameworks`, outside the nix sandbox. `dontFixup` keeps its adhoc linker signature
  (a stripped one builds green and dies with `killed: 9`). See `nix/package.nix`.
- **`displayplacer-apply`** reasserts `programs.displayplacer.arrangement`, and does nothing (exit 0) unless every
  pinned display id is connected — an undocked monitor must never fail a switch.
- With `arrangement` set, every activation runs the applier: a rotation made by hand is undone at the next switch.

```nix
inputs.displayplacer-hm = { url = "github:bdelanghe/displayplacer-hm"; inputs.nixpkgs.follows = "nixpkgs"; inputs.home-manager.follows = "home-manager"; };
# modules = [ displayplacer-hm.homeManagerModules.default ];
programs.displayplacer = {
  enable = true;
  # paste the arguments from the last line of `displayplacer list`
  arrangement = [ "id:… res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" ];
};
```

## Checks

`nix flake check` (aarch64-darwin): the signature survives the build, the module under Home Manager, and the
applier's guard against a stub. `tests/displayplacer.sh` is a read-only dogfood test for a real Mac.
