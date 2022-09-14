{
  description = "Archi Nix Flake";

  inputs.nix-filter.url = "github:numtide/nix-filter";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:anmonteiro/nix-overlays";
  inputs.nixpkgs.inputs.flake-utils.follows = "flake-utils";

  outputs = { self, nixpkgs, nix-filter, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";
        packages = pkgs.callPackage ./nix { nix-filter = nix-filter.lib; };
      in
      {
        defaultPackage = packages.archi;
        inherit packages;
        devShells = {
          default = pkgs.callPackage ./shell.nix { inherit packages; };
          release = pkgs.callPackage ./shell.nix {
            inherit packages;
            release-mode = true;
          };
        };
      });
}
