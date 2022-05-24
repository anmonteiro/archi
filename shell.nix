{ packages
, mkShell
, lib
, ocamlPackages
, cacert
, curl
, git
, opam
, release-mode ? false
}:

(mkShell {
  inputsFrom = lib.filter lib.isDerivation (lib.attrValues packages);
  buildInputs = (with ocamlPackages; [ merlin ocamlformat utop ]) ++
    lib.optional release-mode [
      cacert
      curl
      ocamlPackages.dune-release
      git
      opam
    ];
}).overrideAttrs (o: {
  propagatedBuildInputs = lib.filter
    (drv: drv.pname == null || !(lib.any (name: name == drv.pname) (lib.attrNames packages)))
    o.propagatedBuildInputs;
})
