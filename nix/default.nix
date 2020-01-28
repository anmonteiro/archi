{ pkgs ? import ./sources.nix { inherit ocamlVersion; }
, ocamlVersion ? "4_09"
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

  in
  rec {
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
  } // (if (lib.versionOlder "4.08" ocaml.version) then {
    archi-async = buildArchi {
      pname = "archi-async";
      propagatedBuildInputs = with ocamlPackages; [ archi async ];

      doCheck = false;
    };} else {}
  )

