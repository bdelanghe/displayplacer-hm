{
  description = "displayplacer-hm: displayplacer (macOS display arrangement from the CLI) for Home Manager, with a guarded applier that reasserts a pinned arrangement";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # Only for the module-eval check; consumers already carry home-manager and should `follows` it.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      # The upstream release asset is arm64 only.
      packages.aarch64-darwin = rec {
        displayplacer = import ./nix/package.nix { inherit lib pkgs; };
        default = displayplacer;
      };

      homeManagerModules.default = import ./nix/module.nix;

      checks.aarch64-darwin =
        let
          hm = extra: (home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ self.homeManagerModules.default { home = { username = "t"; homeDirectory = "/Users/t"; stateVersion = "24.11"; }; } extra ];
          }).config;
          spec = "id:AAAA-1 res:1512x982 hz:120 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0";
          on = hm { programs.displayplacer = { enable = true; arrangement = [ spec ]; }; };
          bare = hm { programs.displayplacer.enable = true; };
          off = hm { };
          applier = lib.findFirst (p: (p.name or "") == "displayplacer-apply") (throw "no applier") on.home.packages;
        in
        {
          # The adhoc linker signature survived the build (a stripped one builds green and dies "killed: 9").
          signature = pkgs.runCommand "displayplacer-signature" { } ''
            /usr/bin/codesign -dv ${self.packages.aarch64-darwin.default}/bin/displayplacer 2>&1 | grep -q linker-signed
            touch $out
          '';
          # Under Home Manager: nothing when off; tools without the activation step when no arrangement; the guarded applier when pinned.
          module-eval =
            assert off.home.packages == [ ] || !(lib.any (p: (p.name or "") == "displayplacer-apply") off.home.packages);
            assert !(bare.home.activation ? displayplacerArrangement);
            assert on.home.activation ? displayplacerArrangement;
            pkgs.runCommand "displayplacer-module-eval" { } ''
              grep -qx 'for id in AAAA-1; do' ${applier}/bin/displayplacer-apply
              ${pkgs.bash}/bin/bash -n ${applier}/bin/displayplacer-apply
              touch $out
            '';
          # The guard: with a pinned display absent, the applier does nothing and exits 0 (a display tool must never fail a switch).
          guard = pkgs.runCommand "displayplacer-guard" { } ''
            mkdir bin; printf '#!/bin/sh\n[ "$1" = list ] && { echo "Persistent screen id: OTHER"; exit 0; }\necho APPLIED >> %s/applied; exit 0\n' "$PWD" > bin/dp; chmod +x bin/dp
            sed "s|^dp=.*|dp=$PWD/bin/dp|" ${applier}/bin/displayplacer-apply > apply.sh
            msg=$(${pkgs.bash}/bin/bash apply.sh 2>&1); rc=$?
            [ "$rc" = 0 ] && [ ! -e applied ] && echo "$msg" | grep -q "AAAA-1 not connected"
            sed -i.bak 's/OTHER/AAAA-1/' bin/dp; ${pkgs.bash}/bin/bash apply.sh; grep -q APPLIED applied
            touch $out
          '';
        };
    };
}
