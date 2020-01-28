{ ocamlVersion ? "4_09" }:

let
  overlays = builtins.fetchTarball {
    url = https://github.com/anmonteiro/nix-overlays/archive/dbacb5b9.tar.gz;
    sha256 = "1rag5zyxkak79wp66bp6zjrln8ggwvpzp4i5j34c4g37y2p10l18";
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
