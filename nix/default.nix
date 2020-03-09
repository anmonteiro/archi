{ pkgs ? import ./sources.nix { inherit ocamlVersion; }
, ocamlVersion ? "4_10"
, doCheck ? true }:

let
  inherit (pkgs) lib ocamlPackages;
in
  with ocamlPackages;

  let buildArchi = args: buildDunePackage ({
      version = "0.0.1-dev";
      doCheck = doCheck;
      src = lib.gitignoreSource ./..;
    } // args);

  archiPkgs = rec {
    archi = buildArchi {
      pname = "archi";
      buildInputs = [ alcotest ];
      propagatedBuildInputs = [ hmap ];
    };

    archi-lwt = buildArchi {
      pname = "archi-lwt";
      propagatedBuildInputs = [ archi lwt4 ];
      doCheck = false;
    };
  };
  in
    archiPkgs // (if (lib.versionOlder "4.08" ocaml.version) then {
    archi-async = buildArchi {
      pname = "archi-async";
      propagatedBuildInputs = with ocamlPackages; with archiPkgs; [ archi async ];

      doCheck = false;
    };} else {}
  )

