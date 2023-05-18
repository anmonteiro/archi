{ lib
, ocamlPackages
, nix-filter
, doCheck ? true
}:

with ocamlPackages;

let
  genSrc = files:
    with nix-filter; filter {
      root = ./..;
      include = [ "dune-project" ] ++ files;
    };

  buildArchi = args: buildDunePackage ({
    version = "0.0.1-dev";
    doCheck = doCheck;
  } // args);
in
rec {
  archi = buildArchi {
    pname = "archi";
    src = genSrc [ "archi.opam" "lib" "test" "vendor" ];
    buildInputs = [ alcotest ];
  };

  archi-lwt = buildArchi {
    pname = "archi-lwt";
    src = genSrc [ "lwt" "archi-lwt.opam" ];
    propagatedBuildInputs = [ archi lwt ];
    doCheck = false;
  };

  archi-async = buildArchi {
    pname = "archi-async";
    src = genSrc [ "async" "archi-async.opam" ];
    propagatedBuildInputs = with ocamlPackages; [ archi async ];

    doCheck = false;
  };

  archi-eio = buildArchi {
    pname = "archi-eio";
    src = genSrc [ "eio" "archi-eio.opam" ];
    propagatedBuildInputs = with ocamlPackages; [ archi eio ];

    doCheck = false;
  };
}
