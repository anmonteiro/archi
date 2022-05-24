{
  description = "H2 Nix Flake";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:anmonteiro/nix-overlays";
  inputs.nixpkgs.inputs.flake-utils.follows = "flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";
      in
      rec {
        packages = pkgs.callPackage ./nix { inherit pkgs; };
        defaultPackage = packages.archi;
        devShell = pkgs.callPackage ./shell.nix { inherit packages; };
        devShells = {
          release = pkgs.callPackage ./shell.nix {
            inherit packages;
            release-mode = true;
          };
        };
      });
}
