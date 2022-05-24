{ pkgs ? import ./sources.nix { inherit ocamlVersion; }
, ocamlVersion ? "4_10"
, doCheck ? true
}:

let
  inherit (pkgs) lib ocamlPackages;
in

with ocamlPackages;

let
  genSrc = { dirs, files }: lib.filterGitSource {
    src = ./..;
    inherit dirs;
    files = files ++ [ "dune-project" ];
  };
  buildArchi = args: buildDunePackage ({
    version = "0.0.1-dev";
    doCheck = doCheck;
  } // args);
in
rec {
  archi = buildArchi {
    pname = "archi";
    src = genSrc {
      dirs = [ "lib" "test" ];
      files = [ "archi.opam" ];
    };
    buildInputs = [ alcotest ];
    propagatedBuildInputs = [ hmap ];
  };

  archi-lwt = buildArchi {
    pname = "archi-lwt";
    src = genSrc {
      dirs = [ "lwt" ];
      files = [ "archi-lwt.opam" ];
    };
    propagatedBuildInputs = [ archi lwt ];
    doCheck = false;
  };

  archi-async = buildArchi {
    pname = "archi-async";
    src = genSrc {
      dirs = [ "async" ];
      files = [ "archi-async.opam" ];
    };
    propagatedBuildInputs = with ocamlPackages; [ archi async ];

    doCheck = false;
  };
}
