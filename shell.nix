{pkgs ? import ./nix/sources.nix {} }:

with pkgs;

mkShell {
  inputsFrom = [ (import ./nix { inherit pkgs; }) ];
  buildInputs = with ocamlPackages; [ merlin ocamlformat utop ];
}
