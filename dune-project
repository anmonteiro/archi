(lang dune 2.5)

(name archi)

(generate_opam_files true)

(source
 (github anmonteiro/archi))

(authors "Antonio Nuno Monteiro <anmonteiro@gmail.com>")

(maintainers "Antonio Nuno Monteiro <anmonteiro@gmail.com>")

(homepage "https://github.com/anmonteiro/archi")

(bug_reports "https://github.com/anmonteiro/archi/issues")

(license "BSD-3-clause")

(package
 (name archi)
 (synopsis
  "A library for managing the lifecycle of stateful components in OCaml")
 (description
  "Archi is an OCaml library for managing the lifecycle of stateful components and\n  their dependencies.")
 (depends
  (ocaml
   (>= "4.13.0"))
  (alcotest :with-test)))

(package
 (name archi-lwt)
 (synopsis
  "Lwt runtime for Archi, a library for managing the lifecycle of stateful components in OCaml")
 (depends
  (ocaml
   (>= "4.13.0"))
  archi
  lwt))

(package
 (name archi-async)
 (synopsis
  "Async runtime for Archi, a library for managing the lifecycle of stateful components in OCaml")
 (depends
  (ocaml
   (>= "4.13.0"))
  archi
  async))

(package
 (name archi-eio)
 (synopsis
  "EIO runtime for Archi, a library for managing the lifecycle of stateful components in OCaml")
 (depends
  (ocaml
   (>= "4.13.0"))
  archi
  eio))
