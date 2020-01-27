{ pkgs ? import ./sources.nix { inherit ocamlVersion; }, ocamlVersion ? "4_09" }:

let
  inherit (pkgs) lib ocamlPackages;
in
  ocamlPackages.buildDunePackage {
    pname = "archi";
    version = "0.0.1-dev";

    src = lib.gitignoreSource ./..;
    nativeBuildInputs = with ocamlPackages; [dune_2];
    propagatedBuildInputs = with ocamlPackages; [
      hmap
      lwt4
    ];
  }

