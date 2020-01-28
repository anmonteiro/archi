{ ocamlVersion ? "4_09" }:

let
  overlays = builtins.fetchTarball {
    url = https://github.com/anmonteiro/nix-overlays/archive/53aed484.tar.gz;
    sha256 = "1x3p39f763sc6ivckddrj7b71wdrfx8r9xavg16c1h78w4cw09l1";
  };

  pkgs = import <nixpkgs> {
    overlays = [
      (import overlays)
      (self: super: {
        ocamlPackages = super.ocaml-ng."ocamlPackages_${ocamlVersion}".overrideScope'
            (super.callPackage "${overlays}/ocaml" {});
      })
    ];
  };

in
  pkgs
