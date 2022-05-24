{
  description = "Archi Nix Flake";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:anmonteiro/nix-overlays";
  inputs.nixpkgs.inputs.flake-utils.follows = "flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";
        archiPkgs = (pkgs.callPackage ./nix { inherit pkgs; });
      in
      rec {
        packages = archiPkgs // { default = archiPkgs.archi; };
        devShells = {
          default = pkgs.callPackage ./shell.nix { inherit packages; };
          release = pkgs.callPackage ./shell.nix {
            inherit packages;
            release-mode = true;
          };
        };
      });
}
