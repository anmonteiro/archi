{pkgs ? import ./nix/sources.nix {} }:

with pkgs;

let
  archiPkgs = pkgs.recurseIntoAttrs (import ./nix { inherit pkgs; doCheck = false; });
  archiDrvs = lib.filterAttrs (_: value: lib.isDerivation value) archiPkgs;
in

(mkShell {
  inputsFrom = lib.attrValues archiDrvs;
  buildInputs = with ocamlPackages; [ merlin ocamlformat utop ];
 }).overrideAttrs (o : {
    propagatedBuildInputs = lib.filter
      (drv: drv.pname == null || !(lib.any (name: name == drv.pname) (lib.attrNames archiDrvs)))
      o.propagatedBuildInputs;
  })
